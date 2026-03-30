package handler_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/wallacehenriquesilva/ai-engineer/internal/embedder"
	"github.com/wallacehenriquesilva/ai-engineer/internal/handler"
	"github.com/wallacehenriquesilva/ai-engineer/internal/router"
)

type fakeEmbedder struct{}

func (f *fakeEmbedder) Embed(_ context.Context, _ string) ([]float32, error) {
	v := make([]float32, 768)
	for i := range v {
		v[i] = 0.1
	}
	return v, nil
}

func (f *fakeEmbedder) Dimensions() int { return 768 }

var _ embedder.Embedder = (*fakeEmbedder)(nil)

func newServer(emb embedder.Embedder) http.Handler {
	h := handler.New(nil, emb)
	return router.New(h)
}

func doRequest(t *testing.T, srv http.Handler, method, path, body string) *httptest.ResponseRecorder {
	t.Helper()
	var r *http.Request
	if body != "" {
		r = httptest.NewRequest(method, path, strings.NewReader(body))
	} else {
		r = httptest.NewRequest(method, path, nil)
	}
	r.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	srv.ServeHTTP(w, r)
	return w
}

func TestIngest_SemBody_Retorna400(t *testing.T) {
	srv := newServer(&fakeEmbedder{})
	w := doRequest(t, srv, http.MethodPost, "/ingest", "")
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

func TestIngest_SemCamposObrigatorios_Retorna400(t *testing.T) {
	tests := []struct {
		name string
		body string
	}{
		{"missing repo and content", `{}`},
		{"missing content", `{"repo":"r"}`},
		{"missing repo", `{"content":"c"}`},
		{"empty repo", `{"repo":"","content":"c"}`},
		{"empty content", `{"repo":"r","content":""}`},
	}
	srv := newServer(&fakeEmbedder{})
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			w := doRequest(t, srv, http.MethodPost, "/ingest", tt.body)
			if w.Code != http.StatusBadRequest {
				t.Errorf("expected 400, got %d", w.Code)
			}
		})
	}
}

func TestIngest_SemEmbedder_Retorna503(t *testing.T) {
	srv := newServer(nil)
	w := doRequest(t, srv, http.MethodPost, "/ingest", `{"repo":"r","content":"c"}`)
	if w.Code != http.StatusServiceUnavailable {
		t.Errorf("expected 503, got %d", w.Code)
	}
}

func TestQuery_SemBody_Retorna400(t *testing.T) {
	srv := newServer(&fakeEmbedder{})
	w := doRequest(t, srv, http.MethodPost, "/query", "")
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

func TestQuery_SemEmbedder_Retorna503(t *testing.T) {
	srv := newServer(nil)
	w := doRequest(t, srv, http.MethodPost, "/query", `{"query":"test"}`)
	if w.Code != http.StatusServiceUnavailable {
		t.Errorf("expected 503, got %d", w.Code)
	}
}

func TestCreateLearning_SemBody_Retorna400(t *testing.T) {
	srv := newServer(&fakeEmbedder{})
	w := doRequest(t, srv, http.MethodPost, "/learnings", "")
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

func TestCreateLearning_SemCamposObrigatorios_Retorna400(t *testing.T) {
	tests := []struct {
		name string
		body string
	}{
		{"missing both", `{}`},
		{"missing solution", `{"pattern":"p"}`},
		{"missing pattern", `{"solution":"s"}`},
		{"empty pattern", `{"pattern":"","solution":"s"}`},
		{"empty solution", `{"pattern":"p","solution":""}`},
	}
	srv := newServer(&fakeEmbedder{})
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			w := doRequest(t, srv, http.MethodPost, "/learnings", tt.body)
			if w.Code != http.StatusBadRequest {
				t.Errorf("expected 400, got %d", w.Code)
			}
		})
	}
}

func TestSearchLearnings_SemQuery_Retorna400(t *testing.T) {
	srv := newServer(&fakeEmbedder{})
	w := doRequest(t, srv, http.MethodPost, "/learnings/search", `{}`)
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

func TestSearchLearnings_SemEmbedder_Retorna503(t *testing.T) {
	srv := newServer(nil)
	w := doRequest(t, srv, http.MethodPost, "/learnings/search", `{"query":"test"}`)
	if w.Code != http.StatusServiceUnavailable {
		t.Errorf("expected 503, got %d", w.Code)
	}
}

func TestStartExecution_SemBody_Retorna400(t *testing.T) {
	srv := newServer(nil)
	w := doRequest(t, srv, http.MethodPost, "/executions", "")
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

func TestStartExecution_SemCommand_Retorna400(t *testing.T) {
	srv := newServer(nil)
	w := doRequest(t, srv, http.MethodPost, "/executions", `{"task":"t"}`)
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

func TestEndExecution_SemID_RetornaErro(t *testing.T) {
	srv := newServer(nil)
	w := doRequest(t, srv, http.MethodPut, "/executions/", `{"status":"success"}`)
	if w.Code == http.StatusOK {
		t.Error("expected non-200 for missing execution ID")
	}
}

func TestRoutes_MetodoInvalido_Retorna405(t *testing.T) {
	tests := []struct {
		name   string
		method string
		path   string
	}{
		{"GET on ingest", http.MethodGet, "/ingest"},
		{"DELETE on ingest", http.MethodDelete, "/ingest"},
		{"GET on query", http.MethodGet, "/query"},
		{"PUT on learnings", http.MethodPut, "/learnings"},
		{"DELETE on executions", http.MethodDelete, "/executions"},
	}
	srv := newServer(nil)
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			w := doRequest(t, srv, tt.method, tt.path, "")
			if w.Code != http.StatusMethodNotAllowed {
				t.Errorf("expected 405, got %d", w.Code)
			}
		})
	}
}

func TestRoutes_PathInexistente_Retorna404(t *testing.T) {
	tests := []struct {
		name string
		path string
	}{
		{"random path", "/naoexiste"},
		{"nested path", "/api/v1/whatever"},
	}
	srv := newServer(nil)
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			w := doRequest(t, srv, http.MethodGet, tt.path, "")
			if w.Code != http.StatusNotFound {
				t.Errorf("expected 404, got %d", w.Code)
			}
		})
	}
}
