package lexer

import (
	"testing"

	"github.com/ha1tch/tsqlparser/token"
)

// TestTokenizeFunction tests the Tokenize convenience function
func TestTokenizeFunction(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		minCount int
	}{
		{"simple SELECT", "SELECT 1", 3},
		{"empty input", "", 1},
		{"whitespace only", "   \t\n  ", 1},
		{"SELECT with columns", "SELECT a, b FROM t", 7},
		{"full statement", "SELECT * FROM t WHERE x = 1", 9},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tokens := Tokenize(tt.input)
			if len(tokens) < tt.minCount {
				t.Errorf("expected at least %d tokens, got %d", tt.minCount, len(tokens))
			}
			// Last token should be EOF
			if tokens[len(tokens)-1].Type != token.EOF {
				t.Errorf("last token should be EOF")
			}
		})
	}
}

// TestFloatEdgeCases tests floating point number parsing edge cases
func TestFloatEdgeCases(t *testing.T) {
	tests := []struct {
		name  string
		input string
	}{
		{"dot followed by non-digit", ".abc"},
		{"dot at end", "a."},
		{"multiple dots", "a.b.c"},
		{"exponent without sign", "1e5"},
		{"exponent with plus", "1e+5"},
		{"exponent with minus", "1e-5"},
		{"float with exponent", "3.14e2"},
		{"dot float", ".5"},
		{"dot float with exponent", ".5e2"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tokens := Tokenize(tt.input)
			if len(tokens) < 1 {
				t.Errorf("expected at least 1 token")
			}
		})
	}
}

// TestCompoundKeywordEdgeCases tests edge cases in compound keyword recognition
func TestCompoundKeywordEdgeCases(t *testing.T) {
	tests := []struct {
		name  string
		input string
	}{
		{"NEXT not followed by VALUE", "NEXT something"},
		{"NEXT VALUE not followed by FOR", "NEXT VALUE something"},
		{"XML not followed by SCHEMA", "XML something"},
		{"XML SCHEMA not followed by COLLECTION", "XML SCHEMA something"},
		{"ASYMMETRIC not followed by KEY", "ASYMMETRIC something"},
		{"ASYMMETRIC KEY not followed by ::", "ASYMMETRIC KEY something"},
		{"SYMMETRIC KEY not followed by ::", "SYMMETRIC KEY something"},
		{"END CONVERSATION", "END CONVERSATION"},
		{"NEXT VALUE FOR", "NEXT VALUE FOR seq"},
		{"XML SCHEMA COLLECTION", "XML SCHEMA COLLECTION dbo.Col"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tokens := Tokenize(tt.input)
			if len(tokens) < 2 {
				t.Errorf("expected at least 2 tokens")
			}
		})
	}
}

// TestAssignmentOperators tests compound assignment operators
func TestAssignmentOperators(t *testing.T) {
	tests := []struct {
		input    string
		expected token.Type
	}{
		{"+=", token.PLUSEQ},
		{"-=", token.MINUSEQ},
		{"*=", token.MULEQ},
		{"/=", token.DIVEQ},
		{"%=", token.MODEQ},
		{"&=", token.ANDEQ},
		{"|=", token.OREQ},
		{"^=", token.XOREQ},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			l := New(tt.input)
			tok := l.NextToken()
			if tok.Type != tt.expected {
				t.Errorf("input %q: expected %v, got %v", tt.input, tt.expected, tok.Type)
			}
		})
	}
}

// TestMoneyLiterals tests money literal parsing
func TestMoneyLiteralsParsing(t *testing.T) {
	tests := []string{"$100", "$100.50", "$0.99", "$1234567.89"}

	for _, input := range tests {
		t.Run(input, func(t *testing.T) {
			l := New(input)
			tok := l.NextToken()
			if tok.Type != token.MONEY_LIT {
				t.Errorf("expected MONEY_LIT, got %v", tok.Type)
			}
		})
	}
}

// TestUnicodeStringLiteralsParsing tests N'unicode' string literals
func TestUnicodeStringLiteralsParsing(t *testing.T) {
	tests := []string{"N'hello'", "N'it''s'", "N''", "N'こんにちは'"}

	for _, input := range tests {
		t.Run(input, func(t *testing.T) {
			l := New(input)
			tok := l.NextToken()
			if tok.Type != token.NSTRING {
				t.Errorf("expected NSTRING, got %v", tok.Type)
			}
		})
	}
}

// TestScopeOperatorParsing tests :: operator
func TestScopeOperatorParsing(t *testing.T) {
	l := New("ident::method")

	tok := l.NextToken()
	if tok.Type != token.IDENT {
		t.Errorf("expected IDENT, got %v %q", tok.Type, tok.Literal)
	}

	tok = l.NextToken()
	if tok.Type != token.SCOPE {
		t.Errorf("expected SCOPE, got %v %q", tok.Type, tok.Literal)
	}

	tok = l.NextToken()
	if tok.Type != token.IDENT {
		t.Errorf("expected IDENT, got %v %q", tok.Type, tok.Literal)
	}
}

// TestIllegalCharacters tests handling of illegal characters
func TestIllegalCharacters(t *testing.T) {
	l := New("\\")
	tok := l.NextToken()
	if tok.Type != token.ILLEGAL {
		t.Errorf("expected ILLEGAL, got %v", tok.Type)
	}
}
