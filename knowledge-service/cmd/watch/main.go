package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

var (
	org           = env("GITHUB_ORG", "")
	serviceURL    = env("KNOWLEDGE_SERVICE_URL", "http://localhost:8080")
	sinceHours, _ = strconv.Atoi(env("SINCE_HOURS", "24"))
	reposDir      = env("REPOS_DIR", homeDir()+"/git")
	stateFile     = env("STATE_FILE", homeDir()+"/.ai-engineer/.watch-state")
	limit, _      = strconv.Atoi(env("REPO_LIMIT", "200"))
)

func main() {
	ctx := context.Background()

	since := loadLastRun()
	now := time.Now().UTC()

	log.Printf("[watch] verificando merges desde %s na org %s", since.Format(time.RFC3339), org)

	repos, err := listRepos(ctx)
	if err != nil {
		log.Fatalf("[watch] listar repos: %v", err)
	}
	log.Printf("[watch] %d repos ativos encontrados", len(repos))

	changed := detectChanged(ctx, repos, since, now)
	if len(changed) == 0 {
		log.Printf("[watch] nenhum merge detectado. encerrando.")
		saveLastRun(now)
		return
	}

	log.Printf("[watch] %d repo(s) com mudancas: %v", len(changed), changed)

	for _, repo := range changed {
		if err := processRepo(ctx, repo); err != nil {
			log.Printf("[watch] erro em %s: %v", repo, err)
		}
	}

	saveLastRun(now)
	log.Printf("[watch] concluido. proxima execucao verificara desde %s", now.Format(time.RFC3339))
}

type ghRepo struct {
	Name     string `json:"name"`
	Language struct {
		Name string `json:"name"`
	} `json:"primaryLanguage"`
	IsArchived bool `json:"isArchived"`
}

func listRepos(ctx context.Context) ([]ghRepo, error) {
	out, err := ghCmd(ctx, "repo", "list", org,
		"--limit", strconv.Itoa(limit),
		"--json", "name,primaryLanguage,isArchived")
	if err != nil {
		return nil, err
	}
	var repos []ghRepo
	if err := json.Unmarshal(out, &repos); err != nil {
		return nil, err
	}
	var active []ghRepo
	for _, r := range repos {
		if !r.IsArchived {
			active = append(active, r)
		}
	}
	return active, nil
}

func detectChanged(ctx context.Context, repos []ghRepo, since, until time.Time) []string {
	var changed []string
	for _, r := range repos {
		count := countMerges(ctx, r.Name, since, until)
		if count > 0 {
			log.Printf("[watch] %s: %d merge(s)", r.Name, count)
			changed = append(changed, r.Name)
		}
	}
	return changed
}

func countMerges(ctx context.Context, repo string, since, until time.Time) int {
	out, err := ghCmd(ctx, "api",
		fmt.Sprintf("repos/%s/%s/commits", org, repo),
		"-f", "since="+since.Format(time.RFC3339),
		"-f", "until="+until.Format(time.RFC3339),
		"-f", "per_page=20",
		"--jq", `[.[] | select((.commit.message | startswith("Merge")) or (.parents | length > 1))] | length`,
	)
	if err != nil {
		return 0
	}
	n, _ := strconv.Atoi(strings.TrimSpace(string(out)))
	return n
}

func processRepo(ctx context.Context, repoName string) error {
	log.Printf("[watch] processando %s...", repoName)

	repoPath, tmpDir, err := ensureRepo(ctx, repoName)
	if err != nil {
		return err
	}
	if tmpDir != "" {
		defer os.RemoveAll(tmpDir)
	} else {
		// Atualiza repo local
		if err := gitPull(ctx, repoPath); err != nil {
			log.Printf("[watch] git pull falhou em %s: %v", repoName, err)
		}
	}

	lang := detectLang(repoPath)
	repoType := "service"
	if strings.HasSuffix(repoName, "-infra") {
		repoType = "infra"
	}

	if err := deleteRepoChunks(ctx, repoName); err != nil {
		log.Printf("[watch] delete chunks %s: %v", repoName, err)
	}

	chunks := chunkRepo(repoName, repoPath, lang, repoType)
	for _, c := range chunks {
		if err := ingest(ctx, c); err != nil {
			log.Printf("[watch] ingest chunk %s::%s: %v", repoName, c.Section, err)
		}
	}

	log.Printf("[watch] %s: %d chunks ingeridos", repoName, len(chunks))
	return nil
}

type IngestPayload struct {
	Repo     string `json:"repo"`
	Section  string `json:"section"`
	Content  string `json:"content"`
	Lang     string `json:"lang"`
	RepoType string `json:"repo_type"`
}

func chunkRepo(name, path, lang, repoType string) []IngestPayload {
	var chunks []IngestPayload

	add := func(section, content string) {
		if strings.TrimSpace(content) == "" {
			return
		}
		// Trunca chunks muito grandes (max ~6000 chars)
		if len(content) > 6000 {
			content = content[:6000] + "\n...[truncado]"
		}
		chunks = append(chunks, IngestPayload{
			Repo:     name,
			Section:  section,
			Content:  content,
			Lang:     lang,
			RepoType: repoType,
		})
	}

	if b := readFile(path, "README.md"); b != "" {
		add("readme", fmt.Sprintf("# %s\n\n%s", name, firstN(b, 3000)))
	}

	if b := readFile(path, "CLAUDE.md"); b != "" {
		add("claude-md", b)
	}

	structure := dirTree(path, 3)
	add("structure", fmt.Sprintf("Estrutura de pastas de %s:\n\n```\n%s\n```", name, structure))

	if b := readFile(path, "go.mod"); b != "" {
		add("go-mod", fmt.Sprintf("Dependencias Go de %s:\n\n```\n%s\n```", name, b))
	}

	if b := readFile(path, "package.json"); b != "" {
		add("package-json", fmt.Sprintf("Dependencias Node de %s:\n\n```json\n%s\n```", name, firstN(b, 2000)))
	}

	envVars := extractEnvVars(path)
	if envVars != "" {
		add("env-vars", fmt.Sprintf("Variaveis de ambiente de %s:\n\n%s", name, envVars))
	}

	endpoints := extractEndpoints(path)
	if endpoints != "" {
		add("endpoints", fmt.Sprintf("Endpoints HTTP de %s:\n\n%s", name, endpoints))
	}

	if repoType == "infra" {
		resources := extractTFResources(path)
		if resources != "" {
			add("terraform", fmt.Sprintf("Recursos Terraform de %s:\n\n%s", name, resources))
		}
	}

	return chunks
}

func extractEnvVars(path string) string {
	out, _ := exec.Command("sh", "-c",
		fmt.Sprintf(`grep -rh "os.Getenv\|viper.Get\|process.env\." "%s" --include="*.go" --include="*.js" --include="*.ts" 2>/dev/null | grep -oP '"[A-Z_]+"' | sort -u | head -30`, path),
	).Output()
	return string(out)
}

func extractEndpoints(path string) string {
	out, _ := exec.Command("sh", "-c",
		fmt.Sprintf(`grep -rh "router\.\|http\.\|gin\.\|echo\.\|mux\." "%s" --include="*.go" 2>/dev/null | grep -E "(GET|POST|PUT|DELETE|PATCH)" | head -20`, path),
	).Output()
	return string(out)
}

func extractTFResources(path string) string {
	out, _ := exec.Command("sh", "-c",
		fmt.Sprintf(`grep -rh "^resource\|^module" "%s" --include="*.tf" 2>/dev/null | sort -u | head -30`, path),
	).Output()
	return string(out)
}

func dirTree(path string, depth int) string {
	out, _ := exec.Command("find", path,
		"-maxdepth", strconv.Itoa(depth),
		"-not", "-path", "*/.git/*",
		"-not", "-path", "*/vendor/*",
		"-not", "-path", "*/node_modules/*",
	).Output()
	lines := strings.Split(string(out), "\n")
	var clean []string
	for _, l := range lines {
		clean = append(clean, strings.TrimPrefix(l, path+"/"))
	}
	if len(clean) > 60 {
		clean = clean[:60]
	}
	return strings.Join(clean, "\n")
}

func detectLang(path string) string {
	checks := map[string]string{
		"go.mod":       "Go",
		"package.json": "Node",
		"pom.xml":      "Java",
		"Cargo.toml":   "Rust",
		"main.tf":      "Terraform",
	}
	for file, lang := range checks {
		if _, err := os.Stat(filepath.Join(path, file)); err == nil {
			return lang
		}
	}
	return "unknown"
}

func ingest(ctx context.Context, payload IngestPayload) error {
	b, _ := json.Marshal(payload)
	req, _ := http.NewRequestWithContext(ctx, "POST", serviceURL+"/ingest", bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 201 {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("ingest %d: %s", resp.StatusCode, body)
	}
	return nil
}

func deleteRepoChunks(ctx context.Context, repo string) error {
	req, _ := http.NewRequestWithContext(ctx, "DELETE", serviceURL+"/repo/"+repo, nil)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	return nil
}

func ensureRepo(ctx context.Context, name string) (repoPath, tmpDir string, err error) {
	found, _ := exec.Command("find", reposDir, "-maxdepth", "2", "-type", "d", "-name", name).Output()
	if p := strings.TrimSpace(string(found)); p != "" {
		return p, "", nil
	}
	tmp, _ := os.MkdirTemp("", "watch-*")
	_, err = ghCmd(ctx, "repo", "clone", org+"/"+name, tmp+"/"+name, "--", "--depth=1", "--quiet")
	if err != nil {
		os.RemoveAll(tmp)
		return "", "", fmt.Errorf("clone %s: %w", name, err)
	}
	return tmp + "/" + name, tmp, nil
}

func gitPull(ctx context.Context, path string) error {
	cmd := exec.CommandContext(ctx, "git", "-C", path, "pull", "--quiet")
	return cmd.Run()
}

func ghCmd(ctx context.Context, args ...string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, "gh", args...)
	if token := os.Getenv("GITHUB_TOKEN"); token != "" {
		cmd.Env = append(os.Environ(), "GH_TOKEN="+token)
	}
	return cmd.Output()
}

func readFile(base, name string) string {
	b, err := os.ReadFile(filepath.Join(base, name))
	if err != nil {
		return ""
	}
	return string(b)
}

func firstN(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n]
}

func loadLastRun() time.Time {
	b, err := os.ReadFile(stateFile)
	if err != nil {
		return time.Now().UTC().Add(-time.Duration(sinceHours) * time.Hour)
	}
	t, err := time.Parse(time.RFC3339, strings.TrimSpace(string(b)))
	if err != nil {
		return time.Now().UTC().Add(-time.Duration(sinceHours) * time.Hour)
	}
	return t
}

func saveLastRun(t time.Time) {
	os.MkdirAll(filepath.Dir(stateFile), 0755)
	os.WriteFile(stateFile, []byte(t.Format(time.RFC3339)), 0644)
}

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func homeDir() string {
	h, _ := os.UserHomeDir()
	return h
}
