package storage

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
)

func Migrate(ctx context.Context, db *pgxpool.Pool, dims int) error {
	_, err := db.Exec(ctx, fmt.Sprintf(`
		CREATE EXTENSION IF NOT EXISTS vector;

		CREATE TABLE IF NOT EXISTS chunks (
			id          TEXT PRIMARY KEY,
			repo        TEXT NOT NULL,
			section     TEXT NOT NULL,
			content     TEXT NOT NULL,
			lang        TEXT,
			repo_type   TEXT,
			embedding   vector(%d),
			updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
		);

		CREATE INDEX IF NOT EXISTS chunks_embedding_idx
			ON chunks USING ivfflat (embedding vector_cosine_ops)
			WITH (lists = 100);

		CREATE INDEX IF NOT EXISTS chunks_repo_idx ON chunks (repo);

		-- Learnings: aprendizados compartilhados entre agentes
		CREATE TABLE IF NOT EXISTS learnings (
			id              TEXT PRIMARY KEY,
			repo            TEXT NOT NULL,
			task            TEXT,
			step            INTEGER,
			error_type      TEXT NOT NULL,
			error_message   TEXT NOT NULL,
			root_cause      TEXT NOT NULL,
			solution        TEXT NOT NULL,
			pattern         TEXT NOT NULL UNIQUE,
			embedding       vector(%d),
			times_seen      INTEGER NOT NULL DEFAULT 1,
			resolved        BOOLEAN NOT NULL DEFAULT FALSE,
			promoted        BOOLEAN NOT NULL DEFAULT FALSE,
			agent_id        TEXT,
			created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
		);

		CREATE INDEX IF NOT EXISTS learnings_repo_idx ON learnings (repo);
		CREATE INDEX IF NOT EXISTS learnings_pattern_idx ON learnings (pattern);

		-- Executions: histórico de execuções de todos os agentes
		CREATE TABLE IF NOT EXISTS executions (
			id                 TEXT PRIMARY KEY,
			command            TEXT NOT NULL,
			task               TEXT,
			repo               TEXT,
			agent_id           TEXT,
			started_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			finished_at        TIMESTAMPTZ,
			duration_seconds   INTEGER DEFAULT 0,
			status             TEXT NOT NULL DEFAULT 'running',
			result             TEXT,
			failed_step        INTEGER,
			failure_reason     TEXT,
			cost_usd           NUMERIC(10,4) DEFAULT 0,
			pr_url             TEXT,
			tokens_input       BIGINT DEFAULT 0,
			tokens_cache_write BIGINT DEFAULT 0,
			tokens_cache_read  BIGINT DEFAULT 0,
			tokens_output      BIGINT DEFAULT 0
		);

		CREATE INDEX IF NOT EXISTS executions_status_idx ON executions (status);
		CREATE INDEX IF NOT EXISTS executions_repo_idx ON executions (repo);
		CREATE INDEX IF NOT EXISTS executions_agent_idx ON executions (agent_id);
		CREATE INDEX IF NOT EXISTS executions_started_idx ON executions (started_at DESC);
	`, dims, dims))
	return err
}
