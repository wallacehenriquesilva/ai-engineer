package embedder

import (
	"context"
	"fmt"
	"os"
)

type Embedder interface {
	Embed(ctx context.Context, text string) ([]float32, error)
	Dimensions() int
}

func New() (Embedder, error) {
	provider := os.Getenv("EMBEDDER_PROVIDER")
	if provider == "" {
		provider = "gemini"
	}

	switch provider {
	case "gemini":
		key := os.Getenv("GEMINI_API_KEY")
		if key == "" {
			return nil, fmt.Errorf("GEMINI_API_KEY nao definida")
		}
		model := os.Getenv("GEMINI_EMBEDDING_MODEL")
		if model == "" {
			model = "gemini-embedding-001"
		}
		return &geminiEmbedder{apiKey: key, model: model}, nil

	case "openai":
		key := os.Getenv("OPENAI_API_KEY")
		if key == "" {
			return nil, fmt.Errorf("OPENAI_API_KEY nao definida")
		}
		model := os.Getenv("OPENAI_EMBEDDING_MODEL")
		if model == "" {
			model = "text-embedding-3-small"
		}
		return &openAIEmbedder{apiKey: key, model: model}, nil

	case "voyage":
		key := os.Getenv("VOYAGE_API_KEY")
		if key == "" {
			return nil, fmt.Errorf("VOYAGE_API_KEY nao definida")
		}
		model := os.Getenv("VOYAGE_EMBEDDING_MODEL")
		if model == "" {
			model = "voyage-code-2"
		}
		return &voyageEmbedder{apiKey: key, model: model}, nil

	case "ollama":
		host := os.Getenv("OLLAMA_HOST")
		if host == "" {
			host = "http://ollama:11434"
		}
		model := os.Getenv("OLLAMA_EMBEDDING_MODEL")
		if model == "" {
			model = "nomic-embed-text"
		}
		return &ollamaEmbedder{host: host, model: model}, nil

	default:
		return nil, fmt.Errorf("EMBEDDER_PROVIDER desconhecido: %s (opcoes: gemini, openai, voyage, ollama)", provider)
	}
}
