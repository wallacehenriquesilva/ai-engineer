package storage

import "testing"

func TestFmtVector(t *testing.T) {
	got := FmtVector([]float32{1.0, 2.5, 3.75})
	want := "[1.000000,2.500000,3.750000]"
	if got != want {
		t.Errorf("FmtVector([1.0, 2.5, 3.75]) = %q, want %q", got, want)
	}
}

func TestFmtVector_Vazio(t *testing.T) {
	got := FmtVector([]float32{})
	want := "[]"
	if got != want {
		t.Errorf("FmtVector([]) = %q, want %q", got, want)
	}
}
