package router

import (
	"net/http"

	"github.com/wallacehenriquesilva/ai-engineer/internal/handler"
)

func New(h *handler.Handler) http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("POST /ingest", h.HandleIngest)
	mux.HandleFunc("POST /query", h.HandleQuery)
	mux.HandleFunc("DELETE /repo/{repo}", h.HandleDeleteRepo)
	mux.HandleFunc("GET /repos", h.HandleListRepos)

	mux.HandleFunc("POST /learnings", h.HandleCreateLearning)
	mux.HandleFunc("POST /learnings/search", h.HandleSearchLearnings)
	mux.HandleFunc("GET /learnings", h.HandleListLearnings)
	mux.HandleFunc("PUT /learnings/{id}/resolve", h.HandleResolveLearning)
	mux.HandleFunc("GET /learnings/promotions", h.HandleGetPromotions)

	mux.HandleFunc("POST /executions", h.HandleStartExecution)
	mux.HandleFunc("PUT /executions/{id}", h.HandleEndExecution)
	mux.HandleFunc("GET /executions", h.HandleListExecutions)
	mux.HandleFunc("GET /executions/stats", h.HandleExecutionStats)

	mux.HandleFunc("GET /health", h.HandleHealth)

	return mux
}
