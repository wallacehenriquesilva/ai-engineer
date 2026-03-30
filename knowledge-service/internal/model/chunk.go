package model

import "time"

type Chunk struct {
	ID        string    `json:"id"`
	Repo      string    `json:"repo"`
	Section   string    `json:"section"`
	Content   string    `json:"content"`
	Lang      string    `json:"lang"`
	RepoType  string    `json:"repo_type"`
	UpdatedAt time.Time `json:"updated_at"`
	Score     float64   `json:"score,omitempty"`
}

type IngestRequest struct {
	Repo     string `json:"repo"`
	Section  string `json:"section"`
	Content  string `json:"content"`
	Lang     string `json:"lang"`
	RepoType string `json:"repo_type"`
}

type QueryRequest struct {
	Query string `json:"query"`
	TopK  int    `json:"top_k"`
	Repo  string `json:"repo,omitempty"`
	Lang  string `json:"lang,omitempty"`
}

type QueryResponse struct {
	Results []Chunk `json:"results"`
	Query   string  `json:"query"`
	TopK    int     `json:"top_k"`
}
