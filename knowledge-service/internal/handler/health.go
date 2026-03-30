package handler

import (
	"encoding/json"
	"net/http"
)

func (h *Handler) HandleHealth(w http.ResponseWriter, r *http.Request) {
	if err := h.DB.Ping(r.Context()); err != nil {
		http.Error(w, "db unreachable", http.StatusServiceUnavailable)
		return
	}
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}
