package parser

import (
	"testing"

	"github.com/ha1tch/tsqlparser/ast"
	"github.com/ha1tch/tsqlparser/lexer"
)

func TestDistinctAggregate(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		fn       string
		distinct bool
		arg      string
	}{
		{"COUNT DISTINCT",    `SELECT COUNT(DISTINCT status) FROM tasks`, "COUNT", true,  "status"},
		{"COUNT plain",       `SELECT COUNT(status) FROM tasks`,          "COUNT", false, "status"},
		{"SUM DISTINCT",      `SELECT SUM(DISTINCT amount) FROM orders`,  "SUM",   true,  "amount"},
		{"AVG DISTINCT",      `SELECT AVG(DISTINCT score) FROM results`,  "AVG",   true,  "score"},
		{"MIN DISTINCT",      `SELECT MIN(DISTINCT price) FROM items`,    "MIN",   true,  "price"},
		{"MAX DISTINCT",      `SELECT MAX(DISTINCT qty) FROM stock`,      "MAX",   true,  "qty"},
		{"COUNT star",        `SELECT COUNT(*) FROM tasks`,               "COUNT", false, "*"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			l := lexer.New(tt.input)
			p := New(l)
			prog := p.ParseProgram()

			if len(p.Errors()) > 0 {
				t.Fatalf("parse error: %s", p.Errors()[0])
			}

			sel, ok := prog.Statements[0].(*ast.SelectStatement)
			if !ok {
				t.Fatal("expected SelectStatement")
			}
			fc, ok := sel.Columns[0].Expression.(*ast.FunctionCall)
			if !ok {
				t.Fatal("expected FunctionCall expression")
			}

			if fc.Function.String() != tt.fn {
				t.Errorf("Function = %q, want %q", fc.Function.String(), tt.fn)
			}
			if fc.Distinct != tt.distinct {
				t.Errorf("Distinct = %v, want %v", fc.Distinct, tt.distinct)
			}
			if len(fc.Arguments) != 1 {
				t.Fatalf("len(Arguments) = %d, want 1", len(fc.Arguments))
			}
			if fc.Arguments[0].String() != tt.arg {
				t.Errorf("Arguments[0] = %q, want %q", fc.Arguments[0].String(), tt.arg)
			}

			// Verify String() round-trips correctly
			if tt.distinct {
				want := tt.fn + "(DISTINCT " + tt.arg + ")"
				if fc.String() != want {
					t.Errorf("String() = %q, want %q", fc.String(), want)
				}
			}
		})
	}
}
