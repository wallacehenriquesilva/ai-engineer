package main

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestEnv_ComValor_RetornaValor(t *testing.T) {
	os.Setenv("TEST_ENV_VAR", "custom")
	defer os.Unsetenv("TEST_ENV_VAR")

	if got := env("TEST_ENV_VAR", "default"); got != "custom" {
		t.Errorf("esperava 'custom', recebeu '%s'", got)
	}
}

func TestEnv_SemValor_RetornaDefault(t *testing.T) {
	os.Unsetenv("TEST_ENV_VAR_MISSING")

	if got := env("TEST_ENV_VAR_MISSING", "fallback"); got != "fallback" {
		t.Errorf("esperava 'fallback', recebeu '%s'", got)
	}
}

func TestHomeDir_RetornaAlgo(t *testing.T) {
	h := homeDir()
	if h == "" {
		t.Error("homeDir() retornou vazio")
	}
}

func TestFirstN_StringMenorQueN(t *testing.T) {
	if got := firstN("abc", 10); got != "abc" {
		t.Errorf("esperava 'abc', recebeu '%s'", got)
	}
}

func TestFirstN_StringMaiorQueN(t *testing.T) {
	if got := firstN("abcdefgh", 3); got != "abc" {
		t.Errorf("esperava 'abc', recebeu '%s'", got)
	}
}

func TestFirstN_StringIgualN(t *testing.T) {
	if got := firstN("abc", 3); got != "abc" {
		t.Errorf("esperava 'abc', recebeu '%s'", got)
	}
}

func TestReadFile_ArquivoExistente(t *testing.T) {
	tmp := t.TempDir()
	os.WriteFile(filepath.Join(tmp, "test.txt"), []byte("conteudo"), 0644)

	got := readFile(tmp, "test.txt")
	if got != "conteudo" {
		t.Errorf("esperava 'conteudo', recebeu '%s'", got)
	}
}

func TestReadFile_ArquivoInexistente(t *testing.T) {
	got := readFile("/tmp", "nao-existe-xyz.txt")
	if got != "" {
		t.Errorf("esperava vazio, recebeu '%s'", got)
	}
}

func TestDetectLang_Go(t *testing.T) {
	tmp := t.TempDir()
	os.WriteFile(filepath.Join(tmp, "go.mod"), []byte("module test"), 0644)

	if got := detectLang(tmp); got != "Go" {
		t.Errorf("esperava 'Go', recebeu '%s'", got)
	}
}

func TestDetectLang_Node(t *testing.T) {
	tmp := t.TempDir()
	os.WriteFile(filepath.Join(tmp, "package.json"), []byte("{}"), 0644)

	if got := detectLang(tmp); got != "Node" {
		t.Errorf("esperava 'Node', recebeu '%s'", got)
	}
}

func TestDetectLang_Java(t *testing.T) {
	tmp := t.TempDir()
	os.WriteFile(filepath.Join(tmp, "pom.xml"), []byte("<project/>"), 0644)

	if got := detectLang(tmp); got != "Java" {
		t.Errorf("esperava 'Java', recebeu '%s'", got)
	}
}

func TestDetectLang_Terraform(t *testing.T) {
	tmp := t.TempDir()
	os.WriteFile(filepath.Join(tmp, "main.tf"), []byte("resource {}"), 0644)

	if got := detectLang(tmp); got != "Terraform" {
		t.Errorf("esperava 'Terraform', recebeu '%s'", got)
	}
}

func TestDetectLang_Desconhecido(t *testing.T) {
	tmp := t.TempDir()

	if got := detectLang(tmp); got != "unknown" {
		t.Errorf("esperava 'unknown', recebeu '%s'", got)
	}
}

func TestChunkRepo_RepoVazio_RetornaChunks(t *testing.T) {
	tmp := t.TempDir()

	chunks := chunkRepo("test-repo", tmp, "Go", "service")
	if len(chunks) == 0 {
		t.Error("esperava pelo menos 1 chunk, recebeu 0")
	}

	// Verifica que todos têm repo preenchido
	for _, c := range chunks {
		if c.Repo != "test-repo" {
			t.Errorf("chunk com repo errado: '%s'", c.Repo)
		}
		if c.Lang != "Go" {
			t.Errorf("chunk com lang errado: '%s'", c.Lang)
		}
	}
}

func TestChunkRepo_ComReadme_IncluiReadme(t *testing.T) {
	tmp := t.TempDir()
	os.WriteFile(filepath.Join(tmp, "README.md"), []byte("# Test"), 0644)

	chunks := chunkRepo("test-repo", tmp, "Go", "service")

	found := false
	for _, c := range chunks {
		if c.Section == "readme" {
			found = true
			break
		}
	}
	if !found {
		t.Error("esperava chunk 'readme', não encontrado")
	}
}

func TestChunkRepo_ComGoMod_IncluiGoMod(t *testing.T) {
	tmp := t.TempDir()
	os.WriteFile(filepath.Join(tmp, "go.mod"), []byte("module test\n\ngo 1.24"), 0644)

	chunks := chunkRepo("test-repo", tmp, "Go", "service")

	found := false
	for _, c := range chunks {
		if c.Section == "go-mod" {
			found = true
			break
		}
	}
	if !found {
		t.Error("esperava chunk 'go-mod', não encontrado")
	}
}

func TestChunkRepo_Infra_IncluiTerraform(t *testing.T) {
	tmp := t.TempDir()
	os.WriteFile(filepath.Join(tmp, "main.tf"), []byte("resource \"aws_s3_bucket\" \"test\" {}"), 0644)

	chunks := chunkRepo("test-infra", tmp, "Terraform", "infra")

	found := false
	for _, c := range chunks {
		if c.Section == "terraform" {
			found = true
			break
		}
	}
	if !found {
		t.Error("esperava chunk 'terraform', não encontrado")
	}
}

func TestChunkRepo_TruncaConteudoGrande(t *testing.T) {
	tmp := t.TempDir()
	big := make([]byte, 10000)
	for i := range big {
		big[i] = 'a'
	}
	os.WriteFile(filepath.Join(tmp, "README.md"), big, 0644)

	chunks := chunkRepo("test-repo", tmp, "Go", "service")

	for _, c := range chunks {
		if len(c.Content) > 6100 {
			t.Errorf("chunk '%s' com conteúdo muito grande: %d chars", c.Section, len(c.Content))
		}
	}
}

func TestSaveAndLoadLastRun(t *testing.T) {
	tmp := t.TempDir()
	oldState := stateFile
	stateFile = filepath.Join(tmp, "state")
	defer func() { stateFile = oldState }()

	now := time.Date(2026, 3, 29, 12, 0, 0, 0, time.UTC)
	saveLastRun(now)

	loaded := loadLastRun()
	if !loaded.Equal(now) {
		t.Errorf("esperava %v, recebeu %v", now, loaded)
	}
}

func TestLoadLastRun_ArquivoInexistente_UsaDefault(t *testing.T) {
	oldState := stateFile
	stateFile = "/tmp/nao-existe-xyz-state"
	defer func() { stateFile = oldState }()

	loaded := loadLastRun()
	// Deve retornar agora - sinceHours
	diff := time.Since(loaded)
	if diff < 0 || diff > time.Duration(sinceHours+1)*time.Hour {
		t.Errorf("loadLastRun com arquivo inexistente retornou tempo inesperado: %v", loaded)
	}
}

func TestLoadLastRun_ArquivoInvalido_UsaDefault(t *testing.T) {
	tmp := t.TempDir()
	oldState := stateFile
	stateFile = filepath.Join(tmp, "bad-state")
	defer func() { stateFile = oldState }()

	os.WriteFile(stateFile, []byte("nao-e-uma-data"), 0644)

	loaded := loadLastRun()
	diff := time.Since(loaded)
	if diff < 0 || diff > time.Duration(sinceHours+1)*time.Hour {
		t.Errorf("loadLastRun com conteúdo inválido retornou tempo inesperado: %v", loaded)
	}
}

func TestDetectChanged_SemRepos_RetornaVazio(t *testing.T) {
	changed := detectChanged(nil, []ghRepo{}, time.Now(), time.Now())
	if len(changed) != 0 {
		t.Errorf("esperava 0 changes, recebeu %d", len(changed))
	}
}
