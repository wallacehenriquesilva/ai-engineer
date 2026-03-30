package router

import (
	"net/http"
	"testing"

	"github.com/wallacehenriquesilva/ai-engineer/internal/handler"
)

func TestNew_RetornaHandler(t *testing.T) {
	h := handler.New(nil, nil)
	got := New(h)
	if got == nil {
		t.Fatal("New() returned nil, expected non-nil http.Handler")
	}
	if _, ok := got.(http.Handler); !ok {
		t.Fatal("New() result does not implement http.Handler")
	}
}
