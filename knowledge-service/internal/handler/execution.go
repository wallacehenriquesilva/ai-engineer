package handler

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/wallacehenriquesilva/ai-engineer/internal/model"
)

func (h *Handler) HandleStartExecution(w http.ResponseWriter, r *http.Request) {
	var req model.ExecutionStartRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON: "+err.Error(), http.StatusBadRequest)
		return
	}
	if req.Command == "" {
		http.Error(w, "command is required", http.StatusBadRequest)
		return
	}

	id := fmt.Sprintf("%s_%s_%s", time.Now().Format("20060102_150405"), req.Command, req.Task)

	_, err := h.DB.Exec(r.Context(), `
		INSERT INTO executions (id, command, task, repo, agent_id, started_at, status)
		VALUES ($1, $2, $3, $4, $5, NOW(), 'running')
	`, id, req.Command, req.Task, req.Repo, req.AgentID)
	if err != nil {
		http.Error(w, "db error: "+err.Error(), http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]string{"id": id, "status": "running"})
}

func (h *Handler) HandleEndExecution(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if id == "" {
		http.Error(w, "id is required", http.StatusBadRequest)
		return
	}

	var req model.ExecutionEndRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON: "+err.Error(), http.StatusBadRequest)
		return
	}

	_, err := h.DB.Exec(r.Context(), `
		UPDATE executions SET
			finished_at = NOW(),
			duration_seconds = EXTRACT(EPOCH FROM (NOW() - started_at))::int,
			status = $2,
			result = $3,
			failed_step = $4,
			failure_reason = $5,
			cost_usd = $6,
			pr_url = $7,
			tokens_input = $8,
			tokens_cache_write = $9,
			tokens_cache_read = $10,
			tokens_output = $11
		WHERE id = $1
	`, id, req.Status, req.Result, req.FailedStep, req.FailureReason,
		req.CostUSD, req.PRURL, req.Tokens.Input, req.Tokens.CacheWrite,
		req.Tokens.CacheRead, req.Tokens.Output)
	if err != nil {
		http.Error(w, "db error: "+err.Error(), http.StatusInternalServerError)
		return
	}
	json.NewEncoder(w).Encode(map[string]string{"id": id, "status": req.Status})
}

func (h *Handler) HandleListExecutions(w http.ResponseWriter, r *http.Request) {
	filters := []string{}
	args := []any{}

	if status := r.URL.Query().Get("status"); status != "" {
		args = append(args, status)
		filters = append(filters, fmt.Sprintf("status = $%d", len(args)))
	}
	if command := r.URL.Query().Get("command"); command != "" {
		args = append(args, command)
		filters = append(filters, fmt.Sprintf("command = $%d", len(args)))
	}
	if repo := r.URL.Query().Get("repo"); repo != "" {
		args = append(args, repo)
		filters = append(filters, fmt.Sprintf("repo = $%d", len(args)))
	}
	if agentID := r.URL.Query().Get("agent_id"); agentID != "" {
		args = append(args, agentID)
		filters = append(filters, fmt.Sprintf("agent_id = $%d", len(args)))
	}
	if days := r.URL.Query().Get("days"); days != "" {
		args = append(args, days)
		filters = append(filters, fmt.Sprintf("started_at >= NOW() - INTERVAL '1 day' * $%d", len(args)))
	}

	where := ""
	if len(filters) > 0 {
		where = "WHERE " + strings.Join(filters, " AND ")
	}

	limit := "20"
	if l := r.URL.Query().Get("limit"); l != "" {
		limit = l
	}

	query := fmt.Sprintf(`
		SELECT id, command, task, repo, agent_id, started_at, finished_at,
		       duration_seconds, status, result, failed_step, failure_reason,
		       cost_usd, pr_url, tokens_input, tokens_cache_write,
		       tokens_cache_read, tokens_output
		FROM executions %s
		ORDER BY started_at DESC
		LIMIT %s`, where, limit)

	rows, err := h.DB.Query(r.Context(), query, args...)
	if err != nil {
		http.Error(w, "db error: "+err.Error(), http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	results := make([]model.Execution, 0)
	for rows.Next() {
		var e model.Execution
		var finishedAt *time.Time
		var result, failureReason, prURL, task, repo, agentID *string
		var failedStep *int

		if err := rows.Scan(&e.ID, &e.Command, &task, &repo, &agentID,
			&e.StartedAt, &finishedAt, &e.DurationSeconds, &e.Status, &result,
			&failedStep, &failureReason, &e.CostUSD, &prURL,
			&e.TokensInput, &e.TokensCacheWrite, &e.TokensCacheRead, &e.TokensOutput); err != nil {
			continue
		}
		e.FinishedAt = finishedAt
		e.FailedStep = failedStep
		if result != nil {
			e.Result = *result
		}
		if failureReason != nil {
			e.FailureReason = *failureReason
		}
		if prURL != nil {
			e.PRURL = *prURL
		}
		if task != nil {
			e.Task = *task
		}
		if repo != nil {
			e.Repo = *repo
		}
		if agentID != nil {
			e.AgentID = *agentID
		}
		results = append(results, e)
	}
	json.NewEncoder(w).Encode(results)
}

func (h *Handler) HandleExecutionStats(w http.ResponseWriter, r *http.Request) {
	days := r.URL.Query().Get("days")
	if days == "" {
		days = "30"
	}

	var stats struct {
		Total          int     `json:"total"`
		Success        int     `json:"success"`
		Failure        int     `json:"failure"`
		Running        int     `json:"running"`
		SuccessRate    float64 `json:"success_rate"`
		AvgDurationMin float64 `json:"avg_duration_min"`
		TotalCostUSD   float64 `json:"total_cost_usd"`
	}

	err := h.DB.QueryRow(r.Context(), `
		SELECT
			COUNT(*),
			COUNT(*) FILTER (WHERE status = 'success'),
			COUNT(*) FILTER (WHERE status = 'failure'),
			COUNT(*) FILTER (WHERE status = 'running'),
			CASE WHEN COUNT(*) > 0
				THEN ROUND(COUNT(*) FILTER (WHERE status = 'success')::numeric / COUNT(*)::numeric * 100, 1)
				ELSE 0 END,
			COALESCE(ROUND(AVG(duration_seconds) FILTER (WHERE duration_seconds > 0) / 60.0, 1), 0),
			COALESCE(SUM(cost_usd), 0)
		FROM executions
		WHERE started_at >= NOW() - INTERVAL '1 day' * $1::int
	`, days).Scan(&stats.Total, &stats.Success, &stats.Failure, &stats.Running,
		&stats.SuccessRate, &stats.AvgDurationMin, &stats.TotalCostUSD)
	if err != nil {
		http.Error(w, "db error: "+err.Error(), http.StatusInternalServerError)
		return
	}

	rows, err := h.DB.Query(r.Context(), `
		SELECT command, COUNT(*), COUNT(*) FILTER (WHERE status = 'success')
		FROM executions
		WHERE started_at >= NOW() - INTERVAL '1 day' * $1::int
		GROUP BY command ORDER BY COUNT(*) DESC`, days)
	if err == nil {
		defer rows.Close()
		byCommand := map[string]map[string]int{}
		for rows.Next() {
			var cmd string
			var total, success int
			if rows.Scan(&cmd, &total, &success) == nil {
				byCommand[cmd] = map[string]int{"total": total, "success": success}
			}
		}
		json.NewEncoder(w).Encode(map[string]any{
			"total":            stats.Total,
			"success":          stats.Success,
			"failure":          stats.Failure,
			"running":          stats.Running,
			"success_rate":     stats.SuccessRate,
			"avg_duration_min": stats.AvgDurationMin,
			"total_cost_usd":   stats.TotalCostUSD,
			"by_command":       byCommand,
		})
		return
	}
	json.NewEncoder(w).Encode(stats)
}
