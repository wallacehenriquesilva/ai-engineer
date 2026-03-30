package embedder

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

type openAIEmbedder struct {
	apiKey string
	model  string
}

func (e *openAIEmbedder) Dimensions() int { return 1536 }

func (e *openAIEmbedder) Embed(ctx context.Context, text string) ([]float32, error) {
	body, _ := json.Marshal(map[string]any{
		"model": e.model,
		"input": text,
	})

	req, _ := http.NewRequestWithContext(ctx, "POST",
		"https://api.openai.com/v1/embeddings", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+e.apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		b, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("openai error %d: %s", resp.StatusCode, b)
	}

	var out struct {
		Data []struct {
			Embedding []float32 `json:"embedding"`
		} `json:"data"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, err
	}
	if len(out.Data) == 0 {
		return nil, fmt.Errorf("openai: resposta vazia")
	}
	return out.Data[0].Embedding, nil
}
