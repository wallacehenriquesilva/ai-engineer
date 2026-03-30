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

func (h *Handler) HandleCreateLearning(w http.ResponseWriter, r *http.Request) {
	var req model.LearningCreateRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON: "+err.Error(), http.StatusBadRequest)
		return
	}
	if req.Pattern == "" || req.Solution == "" {
		http.Error(w, "pattern and solution are required", http.StatusBadRequest)
		return
	}

	var existingID string
	err := h.DB.QueryRow(r.Context(),
		`UPDATE learnings SET times_seen = times_seen + 1, updated_at = NOW()
		 WHERE pattern = $1 RETURNING id`, req.Pattern).Scan(&existingID)
	if err == nil {
		var l model.Learning
		h.DB.QueryRow(r.Context(),
			`SELECT id, repo, task, step, error_type, error_message, root_cause, solution,
			        pattern, times_seen, resolved, promoted, agent_id, created_at, updated_at
			 FROM learnings WHERE id = $1`, existingID).Scan(
			&l.ID, &l.Repo, &l.Task, &l.Step, &l.ErrorType, &l.ErrorMessage,
			&l.RootCause, &l.Solution, &l.Pattern, &l.TimesSeen, &l.Resolved,
			&l.Promoted, &l.AgentID, &l.CreatedAt, &l.UpdatedAt)
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(l)
		return
	}

	text := req.ErrorMessage + " " + req.RootCause + " " + req.Solution
	var vec string
	if h.Embedder != nil {
		embedding, err := h.Embedder.Embed(r.Context(), text)
		if err != nil {
			http.Error(w, "embedding failed: "+err.Error(), http.StatusInternalServerError)
			return
		}
		vec = storage.FmtVector(embedding)
	}

	id := fmt.Sprintf("%s_%s_%s", time.Now().Format("20060102_150405"), req.Repo, req.ErrorType)

	if vec != "" {
		_, err = h.DB.Exec(r.Context(), `
			INSERT INTO learnings (id, repo, task, step, error_type, error_message, root_cause,
			                       solution, pattern, embedding, agent_id)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::vector, $11)
		`, id, req.Repo, req.Task, req.Step, req.ErrorType, req.ErrorMessage,
			req.RootCause, req.Solution, req.Pattern, vec, req.AgentID)
	} else {
		_, err = h.DB.Exec(r.Context(), `
			INSERT INTO learnings (id, repo, task, step, error_type, error_message, root_cause,
			                       solution, pattern, agent_id)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
		`, id, req.Repo, req.Task, req.Step, req.ErrorType, req.ErrorMessage,
			req.RootCause, req.Solution, req.Pattern, req.AgentID)
	}
	if err != nil {
		http.Error(w, "db error: "+err.Error(), http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]any{"id": id, "status": "created", "times_seen": 1})
}

func (h *Handler) HandleSearchLearnings(w http.ResponseWriter, r *http.Request) {
	var req model.LearningSearchRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON: "+err.Error(), http.StatusBadRequest)
		return
	}
	if req.Query == "" {
		http.Error(w, "query is required", http.StatusBadRequest)
		return
	}
	if h.Embedder == nil {
		http.Error(w, "embedder not configured — semantic search unavailable", http.StatusServiceUnavailable)
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
	if req.ErrorType != "" {
		args = append(args, req.ErrorType)
		filters = append(filters, fmt.Sprintf("error_type = $%d", len(args)))
	}
	if req.UnresolvedOnly {
		filters = append(filters, "resolved = false")
	}

	where := ""
	if len(filters) > 0 {
		where = "WHERE " + strings.Join(filters, " AND ")
	}

	query := fmt.Sprintf(`
		SELECT id, repo, task, step, error_type, error_message, root_cause, solution,
		       pattern, times_seen, resolved, promoted, agent_id, created_at, updated_at,
		       1 - (embedding <=> $1::vector) AS score
		FROM learnings %s
		ORDER BY embedding <=> $1::vector
		LIMIT $2
	`, where)

	rows, err := h.DB.Query(r.Context(), query, args...)
	if err != nil {
		http.Error(w, "query error: "+err.Error(), http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var results []model.Learning
	for rows.Next() {
		var l model.Learning
		if err := rows.Scan(&l.ID, &l.Repo, &l.Task, &l.Step, &l.ErrorType,
			&l.ErrorMessage, &l.RootCause, &l.Solution, &l.Pattern, &l.TimesSeen,
			&l.Resolved, &l.Promoted, &l.AgentID, &l.CreatedAt, &l.UpdatedAt, &l.Score); err != nil {
			continue
		}
		results = append(results, l)
	}
	json.NewEncoder(w).Encode(results)
}

func (h *Handler) HandleListLearnings(w http.ResponseWriter, r *http.Request) {
	filters := []string{}
	args := []any{}

	if repo := r.URL.Query().Get("repo"); repo != "" {
		args = append(args, repo)
		filters = append(filters, fmt.Sprintf("repo = $%d", len(args)))
	}
	if pattern := r.URL.Query().Get("pattern"); pattern != "" {
		args = append(args, pattern)
		filters = append(filters, fmt.Sprintf("pattern = $%d", len(args)))
	}
	if r.URL.Query().Get("unresolved") == "true" {
		filters = append(filters, "resolved = false")
	}

	where := ""
	if len(filters) > 0 {
		where = "WHERE " + strings.Join(filters, " AND ")
	}

	query := fmt.Sprintf(`
		SELECT id, repo, task, step, error_type, error_message, root_cause, solution,
		       pattern, times_seen, resolved, promoted, agent_id, created_at, updated_at
		FROM learnings %s ORDER BY times_seen DESC, updated_at DESC`, where)

	rows, err := h.DB.Query(r.Context(), query, args...)
	if err != nil {
		http.Error(w, "db error: "+err.Error(), http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var results []model.Learning
	for rows.Next() {
		var l model.Learning
		if err := rows.Scan(&l.ID, &l.Repo, &l.Task, &l.Step, &l.ErrorType,
			&l.ErrorMessage, &l.RootCause, &l.Solution, &l.Pattern, &l.TimesSeen,
			&l.Resolved, &l.Promoted, &l.AgentID, &l.CreatedAt, &l.UpdatedAt); err != nil {
			continue
		}
		results = append(results, l)
	}
	json.NewEncoder(w).Encode(results)
}

func (h *Handler) HandleResolveLearning(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if id == "" {
		http.Error(w, "id is required", http.StatusBadRequest)
		return
	}
	res, err := h.DB.Exec(r.Context(),
		`UPDATE learnings SET resolved = true, updated_at = NOW() WHERE id = $1`, id)
	if err != nil {
		http.Error(w, "db error: "+err.Error(), http.StatusInternalServerError)
		return
	}
	if res.RowsAffected() == 0 {
		http.Error(w, "learning not found", http.StatusNotFound)
		return
	}
	json.NewEncoder(w).Encode(map[string]string{"id": id, "status": "resolved"})
}

func (h *Handler) HandleGetPromotions(w http.ResponseWriter, r *http.Request) {
	rows, err := h.DB.Query(r.Context(), `
		SELECT id, repo, task, step, error_type, error_message, root_cause, solution,
		       pattern, times_seen, resolved, promoted, agent_id, created_at, updated_at
		FROM learnings
		WHERE times_seen >= 3 AND promoted = false AND resolved = false
		ORDER BY times_seen DESC`)
	if err != nil {
		http.Error(w, "db error: "+err.Error(), http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var results []model.Learning
	for rows.Next() {
		var l model.Learning
		if err := rows.Scan(&l.ID, &l.Repo, &l.Task, &l.Step, &l.ErrorType,
			&l.ErrorMessage, &l.RootCause, &l.Solution, &l.Pattern, &l.TimesSeen,
			&l.Resolved, &l.Promoted, &l.AgentID, &l.CreatedAt, &l.UpdatedAt); err != nil {
			continue
		}
		results = append(results, l)
	}
	json.NewEncoder(w).Encode(results)
}
