package model

import "time"

type Execution struct {
	ID               string     `json:"id"`
	Command          string     `json:"command"`
	Task             string     `json:"task,omitempty"`
	Repo             string     `json:"repo,omitempty"`
	AgentID          string     `json:"agent_id,omitempty"`
	StartedAt        time.Time  `json:"started_at"`
	FinishedAt       *time.Time `json:"finished_at,omitempty"`
	DurationSeconds  int        `json:"duration_seconds"`
	Status           string     `json:"status"`
	Result           string     `json:"result,omitempty"`
	FailedStep       *int       `json:"failed_step,omitempty"`
	FailureReason    string     `json:"failure_reason,omitempty"`
	CostUSD          float64    `json:"cost_usd"`
	PRURL            string     `json:"pr_url,omitempty"`
	TokensInput      int64      `json:"tokens_input"`
	TokensCacheWrite int64      `json:"tokens_cache_write"`
	TokensCacheRead  int64      `json:"tokens_cache_read"`
	TokensOutput     int64      `json:"tokens_output"`
}

type ExecutionStartRequest struct {
	Command string `json:"command"`
	Task    string `json:"task"`
	Repo    string `json:"repo"`
	AgentID string `json:"agent_id"`
}

type ExecutionEndRequest struct {
	Status        string  `json:"status"`
	Result        string  `json:"result,omitempty"`
	FailedStep    *int    `json:"failed_step,omitempty"`
	FailureReason string  `json:"failure_reason,omitempty"`
	CostUSD       float64 `json:"cost_usd,omitempty"`
	PRURL         string  `json:"pr_url,omitempty"`
	Tokens        struct {
		Input      int64 `json:"input"`
		CacheWrite int64 `json:"cache_write"`
		CacheRead  int64 `json:"cache_read"`
		Output     int64 `json:"output"`
	} `json:"tokens,omitempty"`
}
