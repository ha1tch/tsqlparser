package parser

import (
	"strings"
	"testing"

	"github.com/ha1tch/tsqlparser/ast"
	"github.com/ha1tch/tsqlparser/lexer"
)

// TestTableHintsComprehensive tests all forms of table hint syntax
func TestTableHintsComprehensive(t *testing.T) {
	tests := []struct {
		name          string
		input         string
		expectedHints [][]string // hints per table in FROM clause
	}{
		// Basic forms without alias
		{
			name:          "WITH (NOLOCK) no alias",
			input:         `SELECT * FROM Orders WITH (NOLOCK)`,
			expectedHints: [][]string{{"NOLOCK"}},
		},
		{
			name:          "Legacy (NOLOCK) no alias",
			input:         `SELECT * FROM Orders (NOLOCK)`,
			expectedHints: [][]string{{"NOLOCK"}},
		},

		// With alias - the forms that were previously failing
		{
			name:          "Alias WITH (NOLOCK)",
			input:         `SELECT o.ID FROM Orders o WITH (NOLOCK)`,
			expectedHints: [][]string{{"NOLOCK"}},
		},
		{
			name:          "Alias (NOLOCK) legacy",
			input:         `SELECT o.ID FROM Orders o (NOLOCK)`,
			expectedHints: [][]string{{"NOLOCK"}},
		},
		{
			name:          "AS alias WITH (NOLOCK)",
			input:         `SELECT o.ID FROM Orders AS o WITH (NOLOCK)`,
			expectedHints: [][]string{{"NOLOCK"}},
		},
		{
			name:          "AS alias (NOLOCK) legacy",
			input:         `SELECT o.ID FROM Orders AS o (NOLOCK)`,
			expectedHints: [][]string{{"NOLOCK"}},
		},

		// Schema-qualified tables
		{
			name:          "Schema.table (NOLOCK)",
			input:         `SELECT * FROM dbo.Orders (NOLOCK)`,
			expectedHints: [][]string{{"NOLOCK"}},
		},
		{
			name:          "Schema.table alias (NOLOCK)",
			input:         `SELECT o.ID FROM dbo.Orders o (NOLOCK)`,
			expectedHints: [][]string{{"NOLOCK"}},
		},
		{
			name:          "Schema.table WITH (NOLOCK)",
			input:         `SELECT * FROM dbo.Orders WITH (NOLOCK)`,
			expectedHints: [][]string{{"NOLOCK"}},
		},
		{
			name:          "Schema.table alias WITH (NOLOCK)",
			input:         `SELECT o.ID FROM dbo.Orders o WITH (NOLOCK)`,
			expectedHints: [][]string{{"NOLOCK"}},
		},

		// Three-part names
		{
			name:          "Database.schema.table (NOLOCK)",
			input:         `SELECT * FROM MyDB.dbo.Orders (NOLOCK)`,
			expectedHints: [][]string{{"NOLOCK"}},
		},
		{
			name:          "Database.schema.table alias (NOLOCK)",
			input:         `SELECT o.ID FROM MyDB.dbo.Orders o (NOLOCK)`,
			expectedHints: [][]string{{"NOLOCK"}},
		},

		// Different hint types
		{
			name:          "HOLDLOCK hint",
			input:         `SELECT * FROM Orders o (HOLDLOCK)`,
			expectedHints: [][]string{{"HOLDLOCK"}},
		},
		{
			name:          "UPDLOCK hint",
			input:         `SELECT * FROM Orders o (UPDLOCK)`,
			expectedHints: [][]string{{"UPDLOCK"}},
		},
		{
			name:          "ROWLOCK hint",
			input:         `SELECT * FROM Orders o (ROWLOCK)`,
			expectedHints: [][]string{{"ROWLOCK"}},
		},
		{
			name:          "TABLOCK hint",
			input:         `SELECT * FROM Orders o (TABLOCK)`,
			expectedHints: [][]string{{"TABLOCK"}},
		},
		{
			name:          "TABLOCKX hint",
			input:         `SELECT * FROM Orders o (TABLOCKX)`,
			expectedHints: [][]string{{"TABLOCKX"}},
		},
		{
			name:          "READUNCOMMITTED hint",
			input:         `SELECT * FROM Orders o (READUNCOMMITTED)`,
			expectedHints: [][]string{{"READUNCOMMITTED"}},
		},
		{
			name:          "NOWAIT hint",
			input:         `SELECT * FROM Orders o (NOWAIT)`,
			expectedHints: [][]string{{"NOWAIT"}},
		},

		// Multiple hints
		{
			name:          "Multiple hints WITH syntax",
			input:         `SELECT * FROM Orders WITH (NOLOCK, ROWLOCK)`,
			expectedHints: [][]string{{"NOLOCK", "ROWLOCK"}},
		},
		{
			name:          "Multiple hints with alias",
			input:         `SELECT * FROM Orders o WITH (NOLOCK, HOLDLOCK)`,
			expectedHints: [][]string{{"NOLOCK", "HOLDLOCK"}},
		},

		// JOINs with hints on both tables
		{
			name:          "JOIN both WITH (NOLOCK)",
			input:         `SELECT * FROM Orders o WITH (NOLOCK) JOIN Customers c WITH (NOLOCK) ON o.CustomerID = c.ID`,
			expectedHints: [][]string{{"NOLOCK"}, {"NOLOCK"}},
		},
		{
			name:          "JOIN both legacy (NOLOCK)",
			input:         `SELECT * FROM Orders o (NOLOCK) JOIN Customers c (NOLOCK) ON o.CustomerID = c.ID`,
			expectedHints: [][]string{{"NOLOCK"}, {"NOLOCK"}},
		},
		{
			name:          "JOIN mixed hint syntax",
			input:         `SELECT * FROM Orders o (NOLOCK) JOIN Customers c WITH (NOLOCK) ON o.CustomerID = c.ID`,
			expectedHints: [][]string{{"NOLOCK"}, {"NOLOCK"}},
		},
		{
			name:          "LEFT JOIN with hints",
			input:         `SELECT * FROM Orders o (NOLOCK) LEFT JOIN Customers c (NOLOCK) ON o.CustomerID = c.ID`,
			expectedHints: [][]string{{"NOLOCK"}, {"NOLOCK"}},
		},
		{
			name:          "Three-way JOIN with hints",
			input:         `SELECT * FROM A a (NOLOCK) JOIN B b (NOLOCK) ON a.ID = b.AID JOIN C c (NOLOCK) ON b.ID = c.BID`,
			expectedHints: [][]string{{"NOLOCK"}, {"NOLOCK"}, {"NOLOCK"}},
		},
		{
			name:          "JOIN different hints",
			input:         `SELECT * FROM Orders o (NOLOCK) JOIN Customers c (HOLDLOCK) ON o.CustomerID = c.ID`,
			expectedHints: [][]string{{"NOLOCK"}, {"HOLDLOCK"}},
		},

		// With WHERE clause
		{
			name:          "Alias (NOLOCK) WHERE",
			input:         `SELECT o.ID FROM Orders o (NOLOCK) WHERE o.Status = 1`,
			expectedHints: [][]string{{"NOLOCK"}},
		},
		{
			name:          "Alias WITH (NOLOCK) WHERE",
			input:         `SELECT o.ID FROM Orders o WITH (NOLOCK) WHERE o.Status = 1`,
			expectedHints: [][]string{{"NOLOCK"}},
		},

		// With ORDER BY
		{
			name:          "Alias (NOLOCK) ORDER BY",
			input:         `SELECT o.ID FROM Orders o (NOLOCK) ORDER BY o.ID`,
			expectedHints: [][]string{{"NOLOCK"}},
		},

		// With GROUP BY
		{
			name:          "Alias (NOLOCK) GROUP BY",
			input:         `SELECT o.Status, COUNT(*) FROM Orders o (NOLOCK) GROUP BY o.Status`,
			expectedHints: [][]string{{"NOLOCK"}},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			l := lexer.New(tt.input)
			p := New(l)
			program := p.ParseProgram()

			if len(p.Errors()) > 0 {
				t.Fatalf("parser errors: %v", p.Errors())
			}

			if len(program.Statements) == 0 {
				t.Fatal("no statements parsed")
			}

			stmt, ok := program.Statements[0].(*ast.SelectStatement)
			if !ok {
				t.Fatalf("expected SelectStatement, got %T", program.Statements[0])
			}

			if stmt.From == nil {
				t.Fatal("expected FROM clause")
			}

			// Collect all tables from the FROM clause (handling JOINs)
			tables := collectTables(stmt.From.Tables)

			if len(tables) != len(tt.expectedHints) {
				t.Fatalf("expected %d tables, got %d", len(tt.expectedHints), len(tables))
			}

			for i, table := range tables {
				expectedHints := tt.expectedHints[i]
				if len(table.Hints) != len(expectedHints) {
					t.Errorf("table %d: expected %d hints, got %d: %v",
						i, len(expectedHints), len(table.Hints), table.Hints)
					continue
				}

				for j, hint := range expectedHints {
					if !strings.EqualFold(table.Hints[j], hint) {
						t.Errorf("table %d hint %d: expected %s, got %s",
							i, j, hint, table.Hints[j])
					}
				}
			}
		})
	}
}

// collectTables recursively collects TableName nodes from table references
func collectTables(refs []ast.TableReference) []*ast.TableName {
	var tables []*ast.TableName
	for _, ref := range refs {
		tables = append(tables, collectTablesFromRef(ref)...)
	}
	return tables
}

func collectTablesFromRef(ref ast.TableReference) []*ast.TableName {
	var tables []*ast.TableName

	switch t := ref.(type) {
	case *ast.TableName:
		tables = append(tables, t)
	case *ast.JoinClause:
		tables = append(tables, collectTablesFromRef(t.Left)...)
		tables = append(tables, collectTablesFromRef(t.Right)...)
	}

	return tables
}

// TestTableHintsInSubqueries tests hints in various subquery contexts
func TestTableHintsInSubqueries(t *testing.T) {
	tests := []struct {
		name  string
		input string
	}{
		{
			name:  "IN subquery with alias hint",
			input: `SELECT * FROM Orders WHERE CustomerID IN (SELECT c.ID FROM Customers c (NOLOCK))`,
		},
		{
			name:  "EXISTS subquery with alias hint",
			input: `SELECT * FROM Orders o WHERE EXISTS (SELECT 1 FROM Customers c (NOLOCK) WHERE c.ID = o.CustomerID)`,
		},
		{
			name:  "Scalar subquery with alias hint",
			input: `SELECT *, (SELECT COUNT(*) FROM OrderItems i (NOLOCK) WHERE i.OrderID = o.ID) AS ItemCount FROM Orders o`,
		},
		{
			name:  "Derived table with hint inside",
			input: `SELECT * FROM (SELECT * FROM Orders o (NOLOCK) WHERE o.Status = 1) AS ActiveOrders`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			l := lexer.New(tt.input)
			p := New(l)
			program := p.ParseProgram()

			if len(p.Errors()) > 0 {
				t.Fatalf("parser errors: %v", p.Errors())
			}

			if len(program.Statements) == 0 {
				t.Fatal("no statements parsed")
			}

			// Just verify it parses without error
			_, ok := program.Statements[0].(*ast.SelectStatement)
			if !ok {
				t.Fatalf("expected SelectStatement, got %T", program.Statements[0])
			}
		})
	}
}

// TestTableHintsInCTE tests hints within Common Table Expressions
func TestTableHintsInCTE(t *testing.T) {
	tests := []struct {
		name  string
		input string
	}{
		{
			name: "CTE with hint in definition",
			input: `WITH ActiveOrders AS (
				SELECT * FROM Orders o (NOLOCK) WHERE o.Status = 1
			)
			SELECT * FROM ActiveOrders`,
		},
		{
			name: "CTE with hint in main query",
			input: `WITH OrderTotals AS (
				SELECT CustomerID, SUM(Amount) AS Total FROM Orders GROUP BY CustomerID
			)
			SELECT c.Name, t.Total 
			FROM Customers c (NOLOCK) 
			JOIN OrderTotals t ON c.ID = t.CustomerID`,
		},
		{
			name: "Multiple CTEs with hints",
			input: `WITH 
				Active AS (SELECT * FROM Orders o (NOLOCK) WHERE Status = 1),
				HighValue AS (SELECT * FROM Active WHERE Amount > 1000)
			SELECT * FROM HighValue`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			l := lexer.New(tt.input)
			p := New(l)
			program := p.ParseProgram()

			if len(p.Errors()) > 0 {
				t.Fatalf("parser errors: %v", p.Errors())
			}

			if len(program.Statements) == 0 {
				t.Fatal("no statements parsed")
			}
		})
	}
}

// TestTableHintsInDML tests hints in INSERT, UPDATE, DELETE statements
func TestTableHintsInDML(t *testing.T) {
	tests := []struct {
		name  string
		input string
	}{
		{
			name:  "UPDATE with hint on target",
			input: `UPDATE Orders WITH (ROWLOCK) SET Status = 2 WHERE ID = 1`,
		},
		{
			name:  "UPDATE with hint in FROM",
			input: `UPDATE o SET o.Status = 2 FROM Orders o (NOLOCK) WHERE o.ID = 1`,
		},
		{
			name:  "UPDATE with JOIN and hints",
			input: `UPDATE o SET o.Status = 2 FROM Orders o (NOLOCK) JOIN Customers c (NOLOCK) ON o.CustomerID = c.ID WHERE c.Active = 1`,
		},
		{
			name:  "DELETE with hint",
			input: `DELETE FROM Orders WITH (TABLOCK) WHERE Status = 0`,
		},
		{
			name:  "DELETE with hint in FROM",
			input: `DELETE o FROM Orders o (NOLOCK) WHERE o.Status = 0`,
		},
		{
			name:  "INSERT with hint",
			input: `INSERT INTO Orders WITH (TABLOCK) (CustomerID, Amount) VALUES (1, 100)`,
		},
		{
			name:  "INSERT SELECT with hint",
			input: `INSERT INTO Archive SELECT * FROM Orders o (NOLOCK) WHERE o.Status = 9`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			l := lexer.New(tt.input)
			p := New(l)
			program := p.ParseProgram()

			if len(p.Errors()) > 0 {
				t.Fatalf("parser errors: %v", p.Errors())
			}

			if len(program.Statements) == 0 {
				t.Fatal("no statements parsed")
			}
		})
	}
}

// TestTableHintsInStoredProcedure tests hints within stored procedure context
func TestTableHintsInStoredProcedure(t *testing.T) {
	input := `
CREATE PROCEDURE GetOrderDetails
    @OrderID INT
AS
BEGIN
    SET NOCOUNT ON
    
    SELECT o.ID, o.Amount, c.Name
    FROM Orders o (NOLOCK)
    JOIN Customers c (NOLOCK) ON o.CustomerID = c.ID
    WHERE o.ID = @OrderID
    
    SELECT i.ProductID, i.Quantity, p.Name
    FROM OrderItems i (NOLOCK)
    JOIN Products p (NOLOCK) ON i.ProductID = p.ID
    WHERE i.OrderID = @OrderID
END
`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()

	if len(p.Errors()) > 0 {
		t.Fatalf("parser errors: %v", p.Errors())
	}

	if len(program.Statements) == 0 {
		t.Fatal("no statements parsed")
	}

	proc, ok := program.Statements[0].(*ast.CreateProcedureStatement)
	if !ok {
		t.Fatalf("expected CreateProcedureStatement, got %T", program.Statements[0])
	}

	if proc.Name == nil || proc.Name.String() != "GetOrderDetails" {
		t.Error("procedure name not parsed correctly")
	}
}

// TestTableHintsPreservedInString tests that hints are preserved in AST String() output
func TestTableHintsPreservedInString(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		contains []string
	}{
		{
			name:     "WITH NOLOCK preserved",
			input:    `SELECT * FROM Orders WITH (NOLOCK)`,
			contains: []string{"NOLOCK"},
		},
		{
			name:     "Multiple hints preserved",
			input:    `SELECT * FROM Orders WITH (NOLOCK, ROWLOCK)`,
			contains: []string{"NOLOCK", "ROWLOCK"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			l := lexer.New(tt.input)
			p := New(l)
			program := p.ParseProgram()

			if len(p.Errors()) > 0 {
				t.Fatalf("parser errors: %v", p.Errors())
			}

			output := program.String()
			for _, s := range tt.contains {
				if !strings.Contains(output, s) {
					t.Errorf("expected output to contain %q, got: %s", s, output)
				}
			}
		})
	}
}
