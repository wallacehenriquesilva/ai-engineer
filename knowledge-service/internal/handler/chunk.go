package handler

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/wallacehenriquesilva/ai-engineer/internal/model"
	"github.com/wallacehenriquesilva/ai-engineer/internal/storage"
)

func (h *Handler) HandleIngest(w http.ResponseWriter, r *http.Request) {
	var req model.IngestRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON: "+err.Error(), http.StatusBadRequest)
		return
	}
	if req.Repo == "" || req.Content == "" {
		http.Error(w, "repo and content are required", http.StatusBadRequest)
		return
	}
	if h.Embedder == nil {
		http.Error(w, "embedder not configured — set GEMINI_API_KEY or another provider", http.StatusServiceUnavailable)
		return
	}

	embedding, err := h.Embedder.Embed(r.Context(), req.Content)
	if err != nil {
		http.Error(w, "embedding failed: "+err.Error(), http.StatusInternalServerError)
		return
	}

	id := fmt.Sprintf("%s::%s", req.Repo, req.Section)
	vec := storage.FmtVector(embedding)

	_, err = h.DB.Exec(r.Context(), `
		INSERT INTO chunks (id, repo, section, content, lang, repo_type, embedding, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7::vector, NOW())
		ON CONFLICT (id) DO UPDATE
		SET content = EXCLUDED.content,
		    embedding = EXCLUDED.embedding,
		    updated_at = NOW()
	`, id, req.Repo, req.Section, req.Content, req.Lang, req.RepoType, vec)
	if err != nil {
		http.Error(w, "db error: "+err.Error(), http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]string{"id": id, "status": "ok"})
}

func (h *Handler) HandleQuery(w http.ResponseWriter, r *http.Request) {
	var req model.QueryRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON: "+err.Error(), http.StatusBadRequest)
		return
	}
	if req.Query == "" {
		http.Error(w, "query is required", http.StatusBadRequest)
		return
	}
	if h.Embedder == nil {
		http.Error(w, "embedder not configured — set GEMINI_API_KEY or another provider", http.StatusServiceUnavailable)
		return
	}
	if req.TopK <= 0 || req.TopK > 20 {
		req.TopK = 5
	}

	embedding, err := h.Embedder.Embed(r.Context(), req.Query)
	if err != nil {
		http.Error(w, "embedding failed: "+err.Error(), http.StatusInternalServerError)
		return
	}

	vec := storage.FmtVector(embedding)

	filters := []string{}
	args := []any{vec, req.TopK}
	if req.Repo != "" {
		args = append(args, req.Repo)
		filters = append(filters, fmt.Sprintf("repo = $%d", len(args)))
	}
	if req.Lang != "" {
		args = append(args, req.Lang)
		filters = append(filters, fmt.Sprintf("lang = $%d", len(args)))
	}

	where := ""
	if len(filters) > 0 {
		where = "WHERE " + strings.Join(filters, " AND ")
	}

	query := fmt.Sprintf(`
		SELECT id, repo, section, content, lang, repo_type, updated_at,
		       1 - (embedding <=> $1::vector) AS score
		FROM chunks
		%s
		ORDER BY embedding <=> $1::vector
		LIMIT $2
	`, where)

	rows, err := h.DB.Query(r.Context(), query, args...)
	if err != nil {
		http.Error(w, "query error: "+err.Error(), http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var results []model.Chunk
	for rows.Next() {
		var c model.Chunk
		if err := rows.Scan(&c.ID, &c.Repo, &c.Section, &c.Content,
			&c.Lang, &c.RepoType, &c.UpdatedAt, &c.Score); err != nil {
			continue
		}
		results = append(results, c)
	}

	json.NewEncoder(w).Encode(model.QueryResponse{
		Results: results,
		Query:   req.Query,
		TopK:    req.TopK,
	})
}

func (h *Handler) HandleDeleteRepo(w http.ResponseWriter, r *http.Request) {
	repo := r.PathValue("repo")
	if repo == "" {
		http.Error(w, "repo is required", http.StatusBadRequest)
		return
	}
	res, err := h.DB.Exec(r.Context(), "DELETE FROM chunks WHERE repo = $1", repo)
	if err != nil {
		http.Error(w, "db error: "+err.Error(), http.StatusInternalServerError)
		return
	}
	json.NewEncoder(w).Encode(map[string]any{
		"repo":    repo,
		"deleted": res.RowsAffected(),
	})
}

func (h *Handler) HandleListRepos(w http.ResponseWriter, r *http.Request) {
	rows, err := h.DB.Query(r.Context(), `
		SELECT repo, lang, repo_type, COUNT(*) as chunks, MAX(updated_at) as last_updated
		FROM chunks
		GROUP BY repo, lang, repo_type
		ORDER BY repo
	`)
	if err != nil {
		http.Error(w, "db error: "+err.Error(), http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	type RepoSummary struct {
		Repo        string    `json:"repo"`
		Lang        string    `json:"lang"`
		RepoType    string    `json:"repo_type"`
		Chunks      int       `json:"chunks"`
		LastUpdated time.Time `json:"last_updated"`
	}

	var repos []RepoSummary
	for rows.Next() {
		var rs RepoSummary
		if err := rows.Scan(&rs.Repo, &rs.Lang, &rs.RepoType, &rs.Chunks, &rs.LastUpdated); err != nil {
			continue
		}
		repos = append(repos, rs)
	}
	json.NewEncoder(w).Encode(repos)
}
