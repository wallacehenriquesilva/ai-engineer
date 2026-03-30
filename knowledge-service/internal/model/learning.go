package model

import "time"

type Learning struct {
	ID           string    `json:"id"`
	Repo         string    `json:"repo"`
	Task         string    `json:"task,omitempty"`
	Step         int       `json:"step,omitempty"`
	ErrorType    string    `json:"error_type"`
	ErrorMessage string    `json:"error_message"`
	RootCause    string    `json:"root_cause"`
	Solution     string    `json:"solution"`
	Pattern      string    `json:"pattern"`
	TimesSeen    int       `json:"times_seen"`
	Resolved     bool      `json:"resolved"`
	Promoted     bool      `json:"promoted"`
	AgentID      string    `json:"agent_id,omitempty"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
	Score        float64   `json:"score,omitempty"`
}

type LearningCreateRequest struct {
	Repo         string `json:"repo"`
	Task         string `json:"task"`
	Step         int    `json:"step"`
	ErrorType    string `json:"error_type"`
	ErrorMessage string `json:"error_message"`
	RootCause    string `json:"root_cause"`
	Solution     string `json:"solution"`
	Pattern      string `json:"pattern"`
	AgentID      string `json:"agent_id"`
}

type LearningSearchRequest struct {
	Query          string `json:"query"`
	Repo           string `json:"repo,omitempty"`
	ErrorType      string `json:"error_type,omitempty"`
	UnresolvedOnly bool   `json:"unresolved_only,omitempty"`
	TopK           int    `json:"top_k"`
}
