package embedder

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

type geminiEmbedder struct {
	apiKey string
	model  string
}

func (e *geminiEmbedder) Dimensions() int { return 768 }

func (e *geminiEmbedder) Embed(ctx context.Context, text string) ([]float32, error) {
	url := fmt.Sprintf(
		"https://generativelanguage.googleapis.com/v1beta/models/%s:embedContent?key=%s",
		e.model, e.apiKey,
	)

	body, _ := json.Marshal(map[string]any{
		"model":                "models/" + e.model,
		"outputDimensionality": 768,
		"content": map[string]any{
			"parts": []map[string]any{
				{"text": text},
			},
		},
	})

	req, _ := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		b, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("gemini error %d: %s", resp.StatusCode, b)
	}

	var out struct {
		Embedding struct {
			Values []float32 `json:"values"`
		} `json:"embedding"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, err
	}
	if len(out.Embedding.Values) == 0 {
		return nil, fmt.Errorf("gemini: resposta vazia")
	}
	return out.Embedding.Values, nil
}
