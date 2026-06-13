package version

import "testing"

func TestVersion(t *testing.T) {
	if Version == "" {
		t.Error("Version should not be empty")
	}
	if Version != "0.6.0" {
		t.Errorf("Version = %q, want %q", Version, "0.6.0")
	}
}

func TestString(t *testing.T) {
	if String() != "0.6.0" {
		t.Errorf("String() = %q, want %q", String(), "0.6.0")
	}
}

func TestFull(t *testing.T) {
	want := "tsqlparser version 0.6.0"
	if Full() != want {
		t.Errorf("Full() = %q, want %q", Full(), want)
	}
}
