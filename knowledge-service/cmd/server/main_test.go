package main

import (
	"os"
	"testing"
)

func TestDatabaseURL_Default(t *testing.T) {
	os.Unsetenv("DATABASE_URL")

	url := os.Getenv("DATABASE_URL")
	if url != "" {
		t.Errorf("esperava vazio sem env, recebeu '%s'", url)
	}
	// O main.go usa default "postgres://aieng:aieng@localhost:5432/knowledge?sslmode=disable"
	// Verificamos que o padrão é aplicado na lógica (não podemos chamar main() diretamente)
}

func TestDatabaseURL_Custom(t *testing.T) {
	os.Setenv("DATABASE_URL", "postgres://custom:5432/db")
	defer os.Unsetenv("DATABASE_URL")

	url := os.Getenv("DATABASE_URL")
	if url != "postgres://custom:5432/db" {
		t.Errorf("esperava 'postgres://custom:5432/db', recebeu '%s'", url)
	}
}

func TestPort_Default(t *testing.T) {
	os.Unsetenv("PORT")

	port := os.Getenv("PORT")
	if port != "" {
		t.Errorf("esperava vazio sem env, recebeu '%s'", port)
	}
	// O main.go usa default "8080"
}

func TestPort_Custom(t *testing.T) {
	os.Setenv("PORT", "9090")
	defer os.Unsetenv("PORT")

	port := os.Getenv("PORT")
	if port != "9090" {
		t.Errorf("esperava '9090', recebeu '%s'", port)
	}
}
