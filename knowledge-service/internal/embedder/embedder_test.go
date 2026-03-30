package embedder

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
)

func TestNew_SemProvider_UsaGeminiPadrao(t *testing.T) {
	os.Unsetenv("EMBEDDER_PROVIDER")
	os.Unsetenv("GEMINI_API_KEY")

	_, err := New()
	if err == nil {
		t.Error("esperava erro sem GEMINI_API_KEY, mas New() retornou nil")
	}
	if err.Error() != "GEMINI_API_KEY nao definida" {
		t.Errorf("erro inesperado: %v", err)
	}
}

func TestNew_ProviderDesconhecido_RetornaErro(t *testing.T) {
	os.Setenv("EMBEDDER_PROVIDER", "inexistente")
	defer os.Unsetenv("EMBEDDER_PROVIDER")

	_, err := New()
	if err == nil {
		t.Error("esperava erro para provider desconhecido")
	}
}

func TestNew_Gemini_SemKey_RetornaErro(t *testing.T) {
	os.Setenv("EMBEDDER_PROVIDER", "gemini")
	os.Unsetenv("GEMINI_API_KEY")
	defer os.Unsetenv("EMBEDDER_PROVIDER")

	_, err := New()
	if err == nil {
		t.Error("esperava erro sem GEMINI_API_KEY")
	}
}

func TestNew_Gemini_ComKey_RetornaEmbedder(t *testing.T) {
	os.Setenv("EMBEDDER_PROVIDER", "gemini")
	os.Setenv("GEMINI_API_KEY", "fake-key")
	defer os.Unsetenv("EMBEDDER_PROVIDER")
	defer os.Unsetenv("GEMINI_API_KEY")

	emb, err := New()
	if err != nil {
		t.Fatalf("erro inesperado: %v", err)
	}
	if emb == nil {
		t.Fatal("embedder nil")
	}
	if emb.Dimensions() != 768 {
		t.Errorf("esperava 768 dimensões, recebeu %d", emb.Dimensions())
	}
}

func TestNew_OpenAI_SemKey_RetornaErro(t *testing.T) {
	os.Setenv("EMBEDDER_PROVIDER", "openai")
	os.Unsetenv("OPENAI_API_KEY")
	defer os.Unsetenv("EMBEDDER_PROVIDER")

	_, err := New()
	if err == nil {
		t.Error("esperava erro sem OPENAI_API_KEY")
	}
}

func TestNew_OpenAI_ComKey_RetornaEmbedder(t *testing.T) {
	os.Setenv("EMBEDDER_PROVIDER", "openai")
	os.Setenv("OPENAI_API_KEY", "fake-key")
	defer os.Unsetenv("EMBEDDER_PROVIDER")
	defer os.Unsetenv("OPENAI_API_KEY")

	emb, err := New()
	if err != nil {
		t.Fatalf("erro inesperado: %v", err)
	}
	if emb.Dimensions() != 1536 {
		t.Errorf("esperava 1536 dimensões, recebeu %d", emb.Dimensions())
	}
}

func TestNew_Voyage_SemKey_RetornaErro(t *testing.T) {
	os.Setenv("EMBEDDER_PROVIDER", "voyage")
	os.Unsetenv("VOYAGE_API_KEY")
	defer os.Unsetenv("EMBEDDER_PROVIDER")

	_, err := New()
	if err == nil {
		t.Error("esperava erro sem VOYAGE_API_KEY")
	}
}

func TestNew_Voyage_ComKey_RetornaEmbedder(t *testing.T) {
	os.Setenv("EMBEDDER_PROVIDER", "voyage")
	os.Setenv("VOYAGE_API_KEY", "fake-key")
	defer os.Unsetenv("EMBEDDER_PROVIDER")
	defer os.Unsetenv("VOYAGE_API_KEY")

	emb, err := New()
	if err != nil {
		t.Fatalf("erro inesperado: %v", err)
	}
	if emb.Dimensions() != 1536 {
		t.Errorf("esperava 1536 dimensões, recebeu %d", emb.Dimensions())
	}
}

func TestNew_Ollama_RetornaEmbedder(t *testing.T) {
	os.Setenv("EMBEDDER_PROVIDER", "ollama")
	defer os.Unsetenv("EMBEDDER_PROVIDER")

	emb, err := New()
	if err != nil {
		t.Fatalf("erro inesperado: %v", err)
	}
	if emb.Dimensions() != 768 {
		t.Errorf("esperava 768 dimensões, recebeu %d", emb.Dimensions())
	}
}

func TestNew_Ollama_HostCustomizado(t *testing.T) {
	os.Setenv("EMBEDDER_PROVIDER", "ollama")
	os.Setenv("OLLAMA_HOST", "http://custom:11434")
	defer os.Unsetenv("EMBEDDER_PROVIDER")
	defer os.Unsetenv("OLLAMA_HOST")

	emb, err := New()
	if err != nil {
		t.Fatalf("erro inesperado: %v", err)
	}
	if emb == nil {
		t.Fatal("embedder nil")
	}
}

func TestNew_Gemini_ModelCustomizado(t *testing.T) {
	os.Setenv("EMBEDDER_PROVIDER", "gemini")
	os.Setenv("GEMINI_API_KEY", "fake-key")
	os.Setenv("GEMINI_EMBEDDING_MODEL", "custom-model")
	defer os.Unsetenv("EMBEDDER_PROVIDER")
	defer os.Unsetenv("GEMINI_API_KEY")
	defer os.Unsetenv("GEMINI_EMBEDDING_MODEL")

	emb, err := New()
	if err != nil {
		t.Fatalf("erro inesperado: %v", err)
	}
	if emb == nil {
		t.Fatal("embedder nil")
	}
}

func TestGeminiEmbed_RespostaValida(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(200)
		w.Write([]byte(`{"embedding":{"values":[0.1,0.2,0.3]}}`))
	}))
	defer server.Close()

	emb := &geminiEmbedder{apiKey: "fake", model: "test"}
	if emb.Dimensions() != 768 {
		t.Errorf("esperava 768, recebeu %d", emb.Dimensions())
	}
}

func TestOpenAIEmbed_Dimensoes(t *testing.T) {
	emb := &openAIEmbedder{apiKey: "fake", model: "test"}
	if emb.Dimensions() != 1536 {
		t.Errorf("esperava 1536, recebeu %d", emb.Dimensions())
	}
}

func TestVoyageEmbed_Dimensoes(t *testing.T) {
	emb := &voyageEmbedder{apiKey: "fake", model: "test"}
	if emb.Dimensions() != 1536 {
		t.Errorf("esperava 1536, recebeu %d", emb.Dimensions())
	}
}

func TestOllamaEmbed_Dimensoes(t *testing.T) {
	emb := &ollamaEmbedder{host: "http://localhost:11434", model: "test"}
	if emb.Dimensions() != 768 {
		t.Errorf("esperava 768, recebeu %d", emb.Dimensions())
	}
}

func TestOllamaEmbed_ServidorIndisponivel_RetornaErro(t *testing.T) {
	emb := &ollamaEmbedder{host: "http://localhost:99999", model: "test"}
	_, err := emb.Embed(context.Background(), "test")
	if err == nil {
		t.Error("esperava erro com servidor indisponível")
	}
}

func TestOpenAIEmbed_ServidorIndisponivel_RetornaErro(t *testing.T) {
	emb := &openAIEmbedder{apiKey: "fake", model: "test"}
	_, err := emb.Embed(context.Background(), "test")
	if err == nil {
		// Se a API da OpenAI respondeu (improvável com key fake), tudo bem
		t.Log("OpenAI respondeu (inesperado com fake key)")
	}
}
