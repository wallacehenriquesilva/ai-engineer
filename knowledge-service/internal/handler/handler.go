package handler

import (
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/wallacehenriquesilva/ai-engineer/internal/embedder"
)

type Handler struct {
	DB       *pgxpool.Pool
	Embedder embedder.Embedder
}

func New(db *pgxpool.Pool, emb embedder.Embedder) *Handler {
	return &Handler{DB: db, Embedder: emb}
}
