package main

import (
	"context"
	"log"
	"net/http"
	"os"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/wallacehenriquesilva/ai-engineer/internal/embedder"
	"github.com/wallacehenriquesilva/ai-engineer/internal/handler"
	"github.com/wallacehenriquesilva/ai-engineer/internal/router"
	"github.com/wallacehenriquesilva/ai-engineer/internal/storage"
)

func main() {
	ctx := context.Background()

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		dbURL = "postgres://aieng:aieng@localhost:5432/knowledge?sslmode=disable"
	}

	emb, err := embedder.New()
	if err != nil {
		log.Printf("WARN embedder: %v — busca semântica desabilitada, demais endpoints funcionam", err)
	}

	dims := 768 // default para migration
	if emb != nil {
		dims = emb.Dimensions()
	}

	pool, err := pgxpool.New(ctx, dbURL)
	if err != nil {
		log.Fatalf("db connect: %v", err)
	}
	defer pool.Close()

	if err := storage.Migrate(ctx, pool, dims); err != nil {
		log.Fatalf("migrate: %v", err)
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	h := handler.New(pool, emb)
	if emb != nil {
		log.Printf("knowledge-service listening on :%s (embedder dims: %d)", port, dims)
	} else {
		log.Printf("knowledge-service listening on :%s (no embedder — semantic search disabled)", port)
	}
	log.Fatal(http.ListenAndServe(":"+port, router.New(h)))
}
