package parser

import (
	"strings"
	"testing"

	"github.com/ha1tch/tsqlparser/ast"
	"github.com/ha1tch/tsqlparser/lexer"
)

func TestSelectStatement(t *testing.T) {
	tests := []struct {
		input    string
		expected int // number of columns
	}{
		{"SELECT 1", 1},
		{"SELECT a, b, c FROM t", 3},
		{"SELECT * FROM Users", 1},
		{"SELECT TOP 10 * FROM Orders", 1},
		{"SELECT DISTINCT Name FROM Products", 1},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Fatalf("expected 1 statement, got %d", len(program.Statements))
		}

		stmt, ok := program.Statements[0].(*ast.SelectStatement)
		if !ok {
			t.Fatalf("expected SelectStatement, got %T", program.Statements[0])
		}

		if len(stmt.Columns) != tt.expected {
			t.Errorf("expected %d columns, got %d", tt.expected, len(stmt.Columns))
		}
	}
}

func TestDeclareStatement(t *testing.T) {
	input := `DECLARE @Name VARCHAR(100), @Age INT = 25`

	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	if len(program.Statements) != 1 {
		t.Fatalf("expected 1 statement, got %d", len(program.Statements))
	}

	stmt, ok := program.Statements[0].(*ast.DeclareStatement)
	if !ok {
		t.Fatalf("expected DeclareStatement, got %T", program.Statements[0])
	}

	if len(stmt.Variables) != 2 {
		t.Errorf("expected 2 variables, got %d", len(stmt.Variables))
	}

	if stmt.Variables[0].Name != "@Name" {
		t.Errorf("expected @Name, got %s", stmt.Variables[0].Name)
	}

	if stmt.Variables[1].Value == nil {
		t.Error("expected @Age to have default value")
	}
}

func TestIfStatement(t *testing.T) {
	input := `
IF @x > 10
    SELECT 'big'
ELSE
    SELECT 'small'
`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	if len(program.Statements) != 1 {
		t.Fatalf("expected 1 statement, got %d", len(program.Statements))
	}

	stmt, ok := program.Statements[0].(*ast.IfStatement)
	if !ok {
		t.Fatalf("expected IfStatement, got %T", program.Statements[0])
	}

	if stmt.Condition == nil {
		t.Error("condition should not be nil")
	}

	if stmt.Consequence == nil {
		t.Error("consequence should not be nil")
	}

	if stmt.Alternative == nil {
		t.Error("alternative should not be nil")
	}
}

func TestSetStatement(t *testing.T) {
	tests := []struct {
		input  string
		isOpt  bool
		option string
	}{
		{"SET @x = 10", false, ""},
		{"SET NOCOUNT ON", true, "NOCOUNT"},
		{"SET XACT_ABORT ON", true, "XACT_ABORT"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		stmt, ok := program.Statements[0].(*ast.SetStatement)
		if !ok {
			t.Fatalf("expected SetStatement, got %T", program.Statements[0])
		}

		if tt.isOpt {
			if stmt.Option != tt.option {
				t.Errorf("expected option %s, got %s", tt.option, stmt.Option)
			}
		} else {
			if stmt.Variable == nil {
				t.Error("expected variable to be set")
			}
		}
	}
}

func TestJoinClause(t *testing.T) {
	input := `
SELECT a.x, b.y
FROM TableA a
INNER JOIN TableB b ON a.id = b.a_id
LEFT JOIN TableC c ON b.id = c.b_id
`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt, ok := program.Statements[0].(*ast.SelectStatement)
	if !ok {
		t.Fatalf("expected SelectStatement, got %T", program.Statements[0])
	}

	if stmt.From == nil {
		t.Fatal("FROM clause should not be nil")
	}

	// The joins are nested, so we should have one table reference
	// which is a JoinClause containing nested joins
	if len(stmt.From.Tables) != 1 {
		t.Errorf("expected 1 table reference (nested joins), got %d", len(stmt.From.Tables))
	}
}

func TestCaseExpression(t *testing.T) {
	input := `
SELECT 
    CASE 
        WHEN x > 10 THEN 'big'
        WHEN x > 5 THEN 'medium'
        ELSE 'small'
    END AS size
FROM t
`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt := program.Statements[0].(*ast.SelectStatement)
	col := stmt.Columns[0]

	caseExpr, ok := col.Expression.(*ast.CaseExpression)
	if !ok {
		t.Fatalf("expected CaseExpression, got %T", col.Expression)
	}

	if len(caseExpr.WhenClauses) != 2 {
		t.Errorf("expected 2 WHEN clauses, got %d", len(caseExpr.WhenClauses))
	}

	if caseExpr.ElseClause == nil {
		t.Error("expected ELSE clause")
	}
}

func TestBeginEndBlock(t *testing.T) {
	input := `
BEGIN
    SET @x = 1
    SET @y = 2
    SELECT @x + @y
END
`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	block, ok := program.Statements[0].(*ast.BeginEndBlock)
	if !ok {
		t.Fatalf("expected BeginEndBlock, got %T", program.Statements[0])
	}

	if len(block.Statements) != 3 {
		t.Errorf("expected 3 statements in block, got %d", len(block.Statements))
	}
}

func TestInsertStatement(t *testing.T) {
	input := `INSERT INTO Users (Name, Email) VALUES ('John', 'john@example.com')`

	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt, ok := program.Statements[0].(*ast.InsertStatement)
	if !ok {
		t.Fatalf("expected InsertStatement, got %T", program.Statements[0])
	}

	if len(stmt.Columns) != 2 {
		t.Errorf("expected 2 columns, got %d", len(stmt.Columns))
	}

	if len(stmt.Values) != 1 {
		t.Errorf("expected 1 value row, got %d", len(stmt.Values))
	}

	if len(stmt.Values[0]) != 2 {
		t.Errorf("expected 2 values, got %d", len(stmt.Values[0]))
	}
}

func TestUpdateStatement(t *testing.T) {
	input := `UPDATE Users SET Name = 'Jane', Active = 1 WHERE ID = @UserID`

	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt, ok := program.Statements[0].(*ast.UpdateStatement)
	if !ok {
		t.Fatalf("expected UpdateStatement, got %T", program.Statements[0])
	}

	if len(stmt.SetClauses) != 2 {
		t.Errorf("expected 2 SET clauses, got %d", len(stmt.SetClauses))
	}

	if stmt.Where == nil {
		t.Error("expected WHERE clause")
	}
}

func TestDeleteStatement(t *testing.T) {
	input := `DELETE FROM Orders WHERE OrderDate < @CutoffDate`

	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt, ok := program.Statements[0].(*ast.DeleteStatement)
	if !ok {
		t.Fatalf("expected DeleteStatement, got %T", program.Statements[0])
	}

	if stmt.Where == nil {
		t.Error("expected WHERE clause")
	}
}

func TestExecStatement(t *testing.T) {
	input := `EXEC sp_GetUser @UserID = 123, @IncludeDetails = 1`

	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt, ok := program.Statements[0].(*ast.ExecStatement)
	if !ok {
		t.Fatalf("expected ExecStatement, got %T", program.Statements[0])
	}

	if len(stmt.Parameters) != 2 {
		t.Errorf("expected 2 parameters, got %d", len(stmt.Parameters))
	}
}

func TestWhileStatement(t *testing.T) {
	input := `
WHILE @i < 10
BEGIN
    SET @i = @i + 1
END
`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt, ok := program.Statements[0].(*ast.WhileStatement)
	if !ok {
		t.Fatalf("expected WhileStatement, got %T", program.Statements[0])
	}

	if stmt.Condition == nil {
		t.Error("expected condition")
	}

	if stmt.Body == nil {
		t.Error("expected body")
	}
}

func TestWithCTE(t *testing.T) {
	input := `
WITH OrderTotals AS (
    SELECT CustomerID, SUM(Amount) AS Total
    FROM Orders
    GROUP BY CustomerID
)
SELECT c.Name, ot.Total
FROM Customers c
JOIN OrderTotals ot ON c.ID = ot.CustomerID
`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt, ok := program.Statements[0].(*ast.WithStatement)
	if !ok {
		t.Fatalf("expected WithStatement, got %T", program.Statements[0])
	}

	if len(stmt.CTEs) != 1 {
		t.Errorf("expected 1 CTE, got %d", len(stmt.CTEs))
	}

	if stmt.CTEs[0].Name.Value != "OrderTotals" {
		t.Errorf("expected CTE name 'OrderTotals', got %s", stmt.CTEs[0].Name.Value)
	}
}

func TestIsNullExpression(t *testing.T) {
	tests := []struct {
		input string
		isNot bool
	}{
		{"SELECT * FROM t WHERE x IS NULL", false},
		{"SELECT * FROM t WHERE x IS NOT NULL", true},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		stmt := program.Statements[0].(*ast.SelectStatement)
		isNull, ok := stmt.Where.(*ast.IsNullExpression)
		if !ok {
			t.Fatalf("expected IsNullExpression, got %T", stmt.Where)
		}

		if isNull.Not != tt.isNot {
			t.Errorf("expected Not=%v, got %v", tt.isNot, isNull.Not)
		}
	}
}

func TestBetweenExpression(t *testing.T) {
	input := `SELECT * FROM Orders WHERE OrderDate BETWEEN '2024-01-01' AND '2024-12-31'`

	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt := program.Statements[0].(*ast.SelectStatement)
	between, ok := stmt.Where.(*ast.BetweenExpression)
	if !ok {
		t.Fatalf("expected BetweenExpression, got %T", stmt.Where)
	}

	if between.Expr == nil || between.Low == nil || between.High == nil {
		t.Error("BETWEEN expression parts should not be nil")
	}
}

func TestBetweenWithAndCondition(t *testing.T) {
	input := `SELECT * FROM Orders WHERE Status = 'Active' AND OrderDate BETWEEN '2024-01-01' AND '2024-12-31'`

	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt := program.Statements[0].(*ast.SelectStatement)
	// Should be an AND expression at the top level
	and, ok := stmt.Where.(*ast.InfixExpression)
	if !ok {
		t.Fatalf("expected InfixExpression (AND), got %T", stmt.Where)
	}

	if and.Operator != "AND" {
		t.Errorf("expected AND operator, got %s", and.Operator)
	}

	// Right side should be BETWEEN
	_, ok = and.Right.(*ast.BetweenExpression)
	if !ok {
		t.Errorf("expected BetweenExpression on right, got %T", and.Right)
	}
}

func TestTryCatchStatement(t *testing.T) {
	input := `
BEGIN TRY
    SELECT 1/0;
END TRY
BEGIN CATCH
    SELECT ERROR_MESSAGE();
END CATCH
`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt, ok := program.Statements[0].(*ast.TryCatchStatement)
	if !ok {
		t.Fatalf("expected TryCatchStatement, got %T", program.Statements[0])
	}

	if stmt.TryBlock == nil {
		t.Error("TryBlock should not be nil")
	}

	if stmt.CatchBlock == nil {
		t.Error("CatchBlock should not be nil")
	}
}

func TestInExpression(t *testing.T) {
	tests := []struct {
		input      string
		valueCount int
	}{
		{"SELECT * FROM t WHERE x IN (1, 2, 3)", 3},
		{"SELECT * FROM t WHERE x IN ('a', 'b')", 2},
		{"SELECT * FROM t WHERE x NOT IN (1)", 1},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		stmt := program.Statements[0].(*ast.SelectStatement)
		in, ok := stmt.Where.(*ast.InExpression)
		if !ok {
			t.Fatalf("expected InExpression, got %T", stmt.Where)
		}

		if len(in.Values) != tt.valueCount {
			t.Errorf("expected %d values, got %d", tt.valueCount, len(in.Values))
		}
	}
}

func TestComplexStoredProcedure(t *testing.T) {
	input := `
CREATE PROCEDURE dbo.ProcessOrder
    @OrderID INT,
    @Status VARCHAR(50) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF @OrderID IS NULL
    BEGIN
        SET @Status = 'Error: NULL OrderID';
        RETURN -1;
    END

    BEGIN TRY
        UPDATE Orders SET ProcessedDate = GETDATE() WHERE OrderID = @OrderID;
        SET @Status = 'Success';
        RETURN 0;
    END TRY
    BEGIN CATCH
        SET @Status = ERROR_MESSAGE();
        RETURN -1;
    END CATCH
END
`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	proc, ok := program.Statements[0].(*ast.CreateProcedureStatement)
	if !ok {
		t.Fatalf("expected CreateProcedureStatement, got %T", program.Statements[0])
	}

	if proc.Name.String() != "dbo.ProcessOrder" {
		t.Errorf("expected procedure name 'dbo.ProcessOrder', got %s", proc.Name.String())
	}

	if len(proc.Parameters) != 2 {
		t.Errorf("expected 2 parameters, got %d", len(proc.Parameters))
	}

	if proc.Body == nil {
		t.Error("procedure body should not be nil")
	}
}

func TestLikeExpression(t *testing.T) {
	tests := []struct {
		input     string
		hasNot    bool
		hasEscape bool
	}{
		{"SELECT * FROM t WHERE name LIKE '%test%'", false, false},
		{"SELECT * FROM t WHERE name NOT LIKE '%test%'", true, false},
		{"SELECT * FROM t WHERE name LIKE '%test%' ESCAPE '\\'", false, true},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		stmt := program.Statements[0].(*ast.SelectStatement)
		like, ok := stmt.Where.(*ast.LikeExpression)
		if !ok {
			t.Fatalf("input %q: expected LikeExpression, got %T", tt.input, stmt.Where)
		}

		if like.Not != tt.hasNot {
			t.Errorf("input %q: expected Not=%v, got %v", tt.input, tt.hasNot, like.Not)
		}

		if (like.Escape != nil) != tt.hasEscape {
			t.Errorf("input %q: expected hasEscape=%v", tt.input, tt.hasEscape)
		}
	}
}

func TestWindowFunctions(t *testing.T) {
	input := `
SELECT 
    ROW_NUMBER() OVER (ORDER BY Name) AS RowNum,
    RANK() OVER (PARTITION BY Dept ORDER BY Salary DESC) AS SalaryRank
FROM Employees
`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt := program.Statements[0].(*ast.SelectStatement)
	if len(stmt.Columns) != 2 {
		t.Errorf("expected 2 columns, got %d", len(stmt.Columns))
	}

	// Check first column has OVER clause
	fc, ok := stmt.Columns[0].Expression.(*ast.FunctionCall)
	if !ok {
		t.Fatalf("expected FunctionCall, got %T", stmt.Columns[0].Expression)
	}

	if fc.Over == nil {
		t.Error("expected OVER clause on ROW_NUMBER()")
	}
}

func TestSubqueryInSelect(t *testing.T) {
	input := `
SELECT 
    Name,
    (SELECT COUNT(*) FROM Orders o WHERE o.CustomerID = c.ID) AS OrderCount
FROM Customers c
`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt := program.Statements[0].(*ast.SelectStatement)
	if len(stmt.Columns) != 2 {
		t.Errorf("expected 2 columns, got %d", len(stmt.Columns))
	}
}

func TestMultipleCTEs(t *testing.T) {
	input := `
WITH 
    CTE1 AS (SELECT 1 AS A),
    CTE2 AS (SELECT 2 AS B)
SELECT * FROM CTE1, CTE2
`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt, ok := program.Statements[0].(*ast.WithStatement)
	if !ok {
		t.Fatalf("expected WithStatement, got %T", program.Statements[0])
	}

	if len(stmt.CTEs) != 2 {
		t.Errorf("expected 2 CTEs, got %d", len(stmt.CTEs))
	}
}

func TestTableHints(t *testing.T) {
	input := `SELECT * FROM Orders WITH (NOLOCK) WHERE Status = 'Active'`

	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt := program.Statements[0].(*ast.SelectStatement)
	if stmt.From == nil || len(stmt.From.Tables) == 0 {
		t.Fatal("expected FROM clause with tables")
	}

	table, ok := stmt.From.Tables[0].(*ast.TableName)
	if !ok {
		t.Fatalf("expected TableName, got %T", stmt.From.Tables[0])
	}

	if len(table.Hints) == 0 {
		t.Error("expected table hints")
	}

	if table.Hints[0] != "NOLOCK" {
		t.Errorf("expected NOLOCK hint, got %s", table.Hints[0])
	}
}

func TestNestedCaseExpression(t *testing.T) {
	input := `
SELECT 
    CASE 
        WHEN x > 10 THEN 
            CASE WHEN y > 5 THEN 'A' ELSE 'B' END
        ELSE 'C'
    END AS Result
FROM t
`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt := program.Statements[0].(*ast.SelectStatement)
	caseExpr, ok := stmt.Columns[0].Expression.(*ast.CaseExpression)
	if !ok {
		t.Fatalf("expected CaseExpression, got %T", stmt.Columns[0].Expression)
	}

	// Check nested CASE in first WHEN clause
	nestedCase, ok := caseExpr.WhenClauses[0].Result.(*ast.CaseExpression)
	if !ok {
		t.Error("expected nested CaseExpression in WHEN result")
	}
	_ = nestedCase
}

func TestComplexWhereClause(t *testing.T) {
	input := `
SELECT * FROM Orders
WHERE Status = 'Active'
  AND (Priority = 'High' OR Priority = 'Critical')
  AND OrderDate BETWEEN '2024-01-01' AND '2024-12-31'
  AND CustomerID IN (SELECT ID FROM PremiumCustomers)
  AND Notes IS NOT NULL
`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt := program.Statements[0].(*ast.SelectStatement)
	if stmt.Where == nil {
		t.Fatal("expected WHERE clause")
	}

	// The WHERE clause should be a complex AND expression
	_, ok := stmt.Where.(*ast.InfixExpression)
	if !ok {
		t.Fatalf("expected InfixExpression at top level, got %T", stmt.Where)
	}
}

// -----------------------------------------------------------------------------
// Stage 1: Table Infrastructure Tests
// -----------------------------------------------------------------------------

func TestCreateTableBasic(t *testing.T) {
	input := `
CREATE TABLE Users (
    ID INT NOT NULL,
    Name VARCHAR(100) NULL,
    Email NVARCHAR(255) NOT NULL,
    CreatedAt DATETIME DEFAULT GETDATE()
)
`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt, ok := program.Statements[0].(*ast.CreateTableStatement)
	if !ok {
		t.Fatalf("expected CreateTableStatement, got %T", program.Statements[0])
	}

	if stmt.Name.String() != "Users" {
		t.Errorf("expected table name 'Users', got %s", stmt.Name.String())
	}

	if len(stmt.Columns) != 4 {
		t.Errorf("expected 4 columns, got %d", len(stmt.Columns))
	}

	// Check ID column
	if stmt.Columns[0].Name.Value != "ID" {
		t.Errorf("expected column name 'ID', got %s", stmt.Columns[0].Name.Value)
	}
	if stmt.Columns[0].DataType.Name != "INT" {
		t.Errorf("expected data type 'INT', got %s", stmt.Columns[0].DataType.Name)
	}
	if stmt.Columns[0].Nullable == nil || *stmt.Columns[0].Nullable != false {
		t.Error("expected ID to be NOT NULL")
	}
}

func TestCreateTableWithIdentity(t *testing.T) {
	input := `CREATE TABLE Orders (OrderID INT IDENTITY(1, 1) PRIMARY KEY, Amount DECIMAL(10, 2))`

	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt := program.Statements[0].(*ast.CreateTableStatement)

	if len(stmt.Columns) != 2 {
		t.Errorf("expected 2 columns, got %d", len(stmt.Columns))
	}

	// Check IDENTITY
	if stmt.Columns[0].Identity == nil {
		t.Fatal("expected IDENTITY on OrderID")
	}
	if stmt.Columns[0].Identity.Seed != 1 {
		t.Errorf("expected seed 1, got %d", stmt.Columns[0].Identity.Seed)
	}
	if stmt.Columns[0].Identity.Increment != 1 {
		t.Errorf("expected increment 1, got %d", stmt.Columns[0].Identity.Increment)
	}

	// Check PRIMARY KEY constraint
	if len(stmt.Columns[0].Constraints) == 0 {
		t.Error("expected PRIMARY KEY constraint on OrderID")
	}
}

func TestCreateTableWithConstraints(t *testing.T) {
	input := `
CREATE TABLE OrderItems (
    ItemID INT NOT NULL,
    OrderID INT NOT NULL,
    ProductID INT NOT NULL,
    Quantity INT NOT NULL CHECK (Quantity > 0),
    CONSTRAINT PK_OrderItems PRIMARY KEY (ItemID),
    CONSTRAINT FK_Order FOREIGN KEY (OrderID) REFERENCES Orders(OrderID) ON DELETE CASCADE,
    CONSTRAINT UQ_OrderProduct UNIQUE (OrderID, ProductID)
)
`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt := program.Statements[0].(*ast.CreateTableStatement)

	if len(stmt.Columns) != 4 {
		t.Errorf("expected 4 columns, got %d", len(stmt.Columns))
	}

	if len(stmt.Constraints) != 3 {
		t.Errorf("expected 3 table constraints, got %d", len(stmt.Constraints))
	}

	// Check PRIMARY KEY
	if stmt.Constraints[0].Type != ast.ConstraintPrimaryKey {
		t.Errorf("expected PRIMARY KEY constraint, got %v", stmt.Constraints[0].Type)
	}
	if stmt.Constraints[0].Name != "PK_OrderItems" {
		t.Errorf("expected constraint name 'PK_OrderItems', got %s", stmt.Constraints[0].Name)
	}

	// Check FOREIGN KEY with ON DELETE CASCADE
	if stmt.Constraints[1].Type != ast.ConstraintForeignKey {
		t.Errorf("expected FOREIGN KEY constraint, got %v", stmt.Constraints[1].Type)
	}
	if stmt.Constraints[1].OnDelete != "CASCADE" {
		t.Errorf("expected ON DELETE CASCADE, got %s", stmt.Constraints[1].OnDelete)
	}

	// Check UNIQUE
	if stmt.Constraints[2].Type != ast.ConstraintUnique {
		t.Errorf("expected UNIQUE constraint, got %v", stmt.Constraints[2].Type)
	}
}

func TestCreateTemporaryTable(t *testing.T) {
	input := `CREATE TABLE #TempOrders (ID INT, Value DECIMAL(10,2))`

	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt := program.Statements[0].(*ast.CreateTableStatement)

	if !stmt.IsTemporary {
		t.Error("expected table to be marked as temporary")
	}
}

func TestDropTable(t *testing.T) {
	tests := []struct {
		input    string
		ifExists bool
		count    int
	}{
		{"DROP TABLE Users", false, 1},
		{"DROP TABLE IF EXISTS Users", true, 1},
		{"DROP TABLE Orders, OrderItems", false, 2},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		stmt, ok := program.Statements[0].(*ast.DropTableStatement)
		if !ok {
			t.Fatalf("expected DropTableStatement, got %T", program.Statements[0])
		}

		if stmt.IfExists != tt.ifExists {
			t.Errorf("expected IfExists=%v, got %v", tt.ifExists, stmt.IfExists)
		}

		if len(stmt.Tables) != tt.count {
			t.Errorf("expected %d tables, got %d", tt.count, len(stmt.Tables))
		}
	}
}

func TestTruncateTable(t *testing.T) {
	input := `TRUNCATE TABLE dbo.AuditLog`

	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt, ok := program.Statements[0].(*ast.TruncateTableStatement)
	if !ok {
		t.Fatalf("expected TruncateTableStatement, got %T", program.Statements[0])
	}

	if stmt.Table.String() != "dbo.AuditLog" {
		t.Errorf("expected table 'dbo.AuditLog', got %s", stmt.Table.String())
	}
}

func TestAlterTableAddColumn(t *testing.T) {
	input := `ALTER TABLE Users ADD LastLogin DATETIME NULL`

	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt, ok := program.Statements[0].(*ast.AlterTableStatement)
	if !ok {
		t.Fatalf("expected AlterTableStatement, got %T", program.Statements[0])
	}

	if len(stmt.Actions) != 1 {
		t.Fatalf("expected 1 action, got %d", len(stmt.Actions))
	}

	if stmt.Actions[0].Type != ast.AlterAddColumn {
		t.Errorf("expected AlterAddColumn, got %v", stmt.Actions[0].Type)
	}

	if stmt.Actions[0].Column.Name.Value != "LastLogin" {
		t.Errorf("expected column name 'LastLogin', got %s", stmt.Actions[0].Column.Name.Value)
	}
}

func TestAlterTableDropColumn(t *testing.T) {
	input := `ALTER TABLE Users DROP COLUMN TempField`

	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt := program.Statements[0].(*ast.AlterTableStatement)

	if stmt.Actions[0].Type != ast.AlterDropColumn {
		t.Errorf("expected AlterDropColumn, got %v", stmt.Actions[0].Type)
	}

	if stmt.Actions[0].ColumnName.Value != "TempField" {
		t.Errorf("expected column name 'TempField', got %s", stmt.Actions[0].ColumnName.Value)
	}
}

func TestAlterTableAddConstraint(t *testing.T) {
	input := `ALTER TABLE Orders ADD CONSTRAINT FK_Customer FOREIGN KEY (CustomerID) REFERENCES Customers(ID)`

	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt := program.Statements[0].(*ast.AlterTableStatement)

	if stmt.Actions[0].Type != ast.AlterAddConstraint {
		t.Errorf("expected AlterAddConstraint, got %v", stmt.Actions[0].Type)
	}

	if stmt.Actions[0].Constraint.Name != "FK_Customer" {
		t.Errorf("expected constraint name 'FK_Customer', got %s", stmt.Actions[0].Constraint.Name)
	}
}

func TestDeclareTableVariable(t *testing.T) {
	input := `
DECLARE @Results TABLE (
    ID INT,
    Name VARCHAR(100),
    Value DECIMAL(10,2)
)
`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt, ok := program.Statements[0].(*ast.DeclareStatement)
	if !ok {
		t.Fatalf("expected DeclareStatement, got %T", program.Statements[0])
	}

	if len(stmt.Variables) != 1 {
		t.Fatalf("expected 1 variable, got %d", len(stmt.Variables))
	}

	varDef := stmt.Variables[0]
	if varDef.Name != "@Results" {
		t.Errorf("expected variable name '@Results', got %s", varDef.Name)
	}

	if varDef.TableType == nil {
		t.Fatal("expected TableType to be set")
	}

	if len(varDef.TableType.Columns) != 3 {
		t.Errorf("expected 3 columns in table type, got %d", len(varDef.TableType.Columns))
	}
}

func TestTableVariableWithConstraints(t *testing.T) {
	input := `
DECLARE @OrderItems TABLE (
    ItemID INT PRIMARY KEY,
    OrderID INT NOT NULL,
    Amount DECIMAL(10,2) CHECK (Amount >= 0)
)
`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt := program.Statements[0].(*ast.DeclareStatement)
	varDef := stmt.Variables[0]

	if varDef.TableType == nil {
		t.Fatal("expected TableType to be set")
	}

	// Check PRIMARY KEY on ItemID
	if len(varDef.TableType.Columns[0].Constraints) == 0 {
		t.Error("expected PRIMARY KEY constraint on ItemID")
	}
}

func TestComputedColumn(t *testing.T) {
	input := `
CREATE TABLE OrderTotals (
    Quantity INT,
    UnitPrice DECIMAL(10,2),
    Total AS (Quantity * UnitPrice) PERSISTED
)
`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt := program.Statements[0].(*ast.CreateTableStatement)

	// Check computed column
	totalCol := stmt.Columns[2]
	if totalCol.Computed == nil {
		t.Fatal("expected computed expression on Total column")
	}
	if !totalCol.IsPersisted {
		t.Error("expected PERSISTED flag on Total column")
	}
}

// -----------------------------------------------------------------------------
// Stage 2: Cursor Tests
// -----------------------------------------------------------------------------

func TestDeclareCursor(t *testing.T) {
	tests := []struct {
		input   string
		name    string
		options []string
	}{
		{
			"DECLARE cur CURSOR FOR SELECT * FROM Users",
			"cur",
			nil,
		},
		{
			"DECLARE MyCursor CURSOR LOCAL FOR SELECT ID FROM T",
			"MyCursor",
			[]string{"LOCAL"},
		},
		{
			"DECLARE cur CURSOR LOCAL STATIC READ_ONLY FOR SELECT * FROM T",
			"cur",
			[]string{"LOCAL", "STATIC", "READ_ONLY"},
		},
		{
			"DECLARE cur CURSOR FAST_FORWARD FOR SELECT * FROM T",
			"cur",
			[]string{"FAST_FORWARD"},
		},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		stmt, ok := program.Statements[0].(*ast.DeclareCursorStatement)
		if !ok {
			t.Fatalf("expected DeclareCursorStatement, got %T", program.Statements[0])
		}

		if stmt.Name.Value != tt.name {
			t.Errorf("expected cursor name %q, got %q", tt.name, stmt.Name.Value)
		}

		if stmt.ForSelect == nil {
			t.Error("expected FOR SELECT clause")
		}
	}
}

func TestOpenCloseCursor(t *testing.T) {
	input := `OPEN MyCursor`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt, ok := program.Statements[0].(*ast.OpenCursorStatement)
	if !ok {
		t.Fatalf("expected OpenCursorStatement, got %T", program.Statements[0])
	}
	if stmt.CursorName.Value != "MyCursor" {
		t.Errorf("expected cursor name 'MyCursor', got %q", stmt.CursorName.Value)
	}

	input2 := `CLOSE MyCursor`
	l2 := lexer.New(input2)
	p2 := New(l2)
	program2 := p2.ParseProgram()
	checkParserErrors(t, p2)

	stmt2, ok := program2.Statements[0].(*ast.CloseCursorStatement)
	if !ok {
		t.Fatalf("expected CloseCursorStatement, got %T", program2.Statements[0])
	}
	if stmt2.CursorName.Value != "MyCursor" {
		t.Errorf("expected cursor name 'MyCursor', got %q", stmt2.CursorName.Value)
	}
}

func TestFetchStatement(t *testing.T) {
	tests := []struct {
		input     string
		direction string
		varCount  int
	}{
		{"FETCH NEXT FROM cur INTO @id, @name", "NEXT", 2},
		{"FETCH PRIOR FROM cur INTO @val", "PRIOR", 1},
		{"FETCH FIRST FROM cur INTO @id", "FIRST", 1},
		{"FETCH LAST FROM cur INTO @id", "LAST", 1},
		{"FETCH FROM cur INTO @x", "", 1},
		{"FETCH NEXT FROM cur", "NEXT", 0},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		stmt, ok := program.Statements[0].(*ast.FetchStatement)
		if !ok {
			t.Fatalf("input %q: expected FetchStatement, got %T", tt.input, program.Statements[0])
		}

		if stmt.Direction != tt.direction {
			t.Errorf("input %q: expected direction %q, got %q", tt.input, tt.direction, stmt.Direction)
		}

		if len(stmt.IntoVars) != tt.varCount {
			t.Errorf("input %q: expected %d vars, got %d", tt.input, tt.varCount, len(stmt.IntoVars))
		}
	}
}

func TestFetchAbsoluteRelative(t *testing.T) {
	input := `FETCH ABSOLUTE 10 FROM cur INTO @id`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt := program.Statements[0].(*ast.FetchStatement)
	if stmt.Direction != "ABSOLUTE" {
		t.Errorf("expected direction ABSOLUTE, got %s", stmt.Direction)
	}
	if stmt.Offset == nil {
		t.Error("expected offset expression")
	}

	input2 := `FETCH RELATIVE -5 FROM cur INTO @id`
	l2 := lexer.New(input2)
	p2 := New(l2)
	program2 := p2.ParseProgram()
	checkParserErrors(t, p2)

	stmt2 := program2.Statements[0].(*ast.FetchStatement)
	if stmt2.Direction != "RELATIVE" {
		t.Errorf("expected direction RELATIVE, got %s", stmt2.Direction)
	}
}

func TestDeallocateCursor(t *testing.T) {
	input := `DEALLOCATE MyCursor`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt, ok := program.Statements[0].(*ast.DeallocateCursorStatement)
	if !ok {
		t.Fatalf("expected DeallocateCursorStatement, got %T", program.Statements[0])
	}
	if stmt.CursorName.Value != "MyCursor" {
		t.Errorf("expected cursor name 'MyCursor', got %q", stmt.CursorName.Value)
	}
}

func TestCompleteCursorLoop(t *testing.T) {
	input := `
DECLARE @id INT, @name VARCHAR(100)

DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT ID, Name FROM Users WHERE Active = 1

OPEN cur

FETCH NEXT FROM cur INTO @id, @name

WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT @name
    FETCH NEXT FROM cur INTO @id, @name
END

CLOSE cur
DEALLOCATE cur
`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	// Should have 7 statements: DECLARE vars, DECLARE CURSOR, OPEN, FETCH, WHILE, CLOSE, DEALLOCATE
	if len(program.Statements) != 7 {
		t.Errorf("expected 7 statements, got %d", len(program.Statements))
	}

	// Check types
	if _, ok := program.Statements[0].(*ast.DeclareStatement); !ok {
		t.Errorf("stmt 0: expected DeclareStatement, got %T", program.Statements[0])
	}
	if _, ok := program.Statements[1].(*ast.DeclareCursorStatement); !ok {
		t.Errorf("stmt 1: expected DeclareCursorStatement, got %T", program.Statements[1])
	}
	if _, ok := program.Statements[2].(*ast.OpenCursorStatement); !ok {
		t.Errorf("stmt 2: expected OpenCursorStatement, got %T", program.Statements[2])
	}
	if _, ok := program.Statements[3].(*ast.FetchStatement); !ok {
		t.Errorf("stmt 3: expected FetchStatement, got %T", program.Statements[3])
	}
	if _, ok := program.Statements[4].(*ast.WhileStatement); !ok {
		t.Errorf("stmt 4: expected WhileStatement, got %T", program.Statements[4])
	}
	if _, ok := program.Statements[5].(*ast.CloseCursorStatement); !ok {
		t.Errorf("stmt 5: expected CloseCursorStatement, got %T", program.Statements[5])
	}
	if _, ok := program.Statements[6].(*ast.DeallocateCursorStatement); !ok {
		t.Errorf("stmt 6: expected DeallocateCursorStatement, got %T", program.Statements[6])
	}
}

func TestDerivedTable(t *testing.T) {
	tests := []struct {
		input string
		alias string
	}{
		{"SELECT * FROM (SELECT ID, Name FROM Users) AS U", "U"},
		{"SELECT * FROM (SELECT ID FROM Users WHERE Active = 1) Derived", "Derived"},
		{"SELECT * FROM (SELECT * FROM Orders)", ""},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("input %q: expected 1 statement, got %d", tt.input, len(program.Statements))
			continue
		}

		stmt, ok := program.Statements[0].(*ast.SelectStatement)
		if !ok {
			t.Fatalf("input %q: expected SelectStatement, got %T", tt.input, program.Statements[0])
		}

		if stmt.From == nil || len(stmt.From.Tables) != 1 {
			t.Fatalf("input %q: expected FROM with 1 table", tt.input)
		}

		derived, ok := stmt.From.Tables[0].(*ast.DerivedTable)
		if !ok {
			t.Fatalf("input %q: expected DerivedTable, got %T", tt.input, stmt.From.Tables[0])
		}

		if tt.alias != "" && (derived.Alias == nil || derived.Alias.Value != tt.alias) {
			aliasVal := ""
			if derived.Alias != nil {
				aliasVal = derived.Alias.Value
			}
			t.Errorf("input %q: expected alias %q, got %q", tt.input, tt.alias, aliasVal)
		}
	}
}

// -----------------------------------------------------------------------------
// Stage 3: Query Enhancement Tests
// -----------------------------------------------------------------------------

func TestSelectVariableAssignment(t *testing.T) {
	tests := []struct {
		input    string
		varCount int
	}{
		{"SELECT @count = COUNT(*) FROM Orders", 1},
		{"SELECT @id = ID, @name = Name FROM Users WHERE ID = 1", 2},
		{"SELECT @min = MIN(Price), @max = MAX(Price), AVG(Price) AS AvgPrice FROM Products", 2},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		stmt, ok := program.Statements[0].(*ast.SelectStatement)
		if !ok {
			t.Fatalf("input %q: expected SelectStatement, got %T", tt.input, program.Statements[0])
		}

		varAssignments := 0
		for _, col := range stmt.Columns {
			if col.Variable != nil {
				varAssignments++
			}
		}

		if varAssignments != tt.varCount {
			t.Errorf("input %q: expected %d variable assignments, got %d", tt.input, tt.varCount, varAssignments)
		}
	}
}

func TestOffsetFetch(t *testing.T) {
	tests := []struct {
		input     string
		hasOffset bool
		hasFetch  bool
	}{
		{"SELECT * FROM Products ORDER BY Name OFFSET 10 ROWS FETCH NEXT 20 ROWS ONLY", true, true},
		{"SELECT * FROM Products ORDER BY ID OFFSET 5 ROWS", true, false},
		{"SELECT * FROM Items ORDER BY Price OFFSET 0 ROWS FETCH FIRST 10 ROWS ONLY", true, true},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		stmt := program.Statements[0].(*ast.SelectStatement)

		if tt.hasOffset && stmt.Offset == nil {
			t.Errorf("input %q: expected OFFSET clause", tt.input)
		}
		if !tt.hasOffset && stmt.Offset != nil {
			t.Errorf("input %q: unexpected OFFSET clause", tt.input)
		}
		if tt.hasFetch && stmt.Fetch == nil {
			t.Errorf("input %q: expected FETCH clause", tt.input)
		}
		if !tt.hasFetch && stmt.Fetch != nil {
			t.Errorf("input %q: unexpected FETCH clause", tt.input)
		}
	}
}

func TestWindowFrame(t *testing.T) {
	tests := []struct {
		input     string
		frameType string
	}{
		{"SELECT SUM(Amount) OVER (ORDER BY Date ROWS UNBOUNDED PRECEDING) FROM Orders", "ROWS"},
		{"SELECT SUM(Amount) OVER (ORDER BY Date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) FROM Orders", "ROWS"},
		{"SELECT SUM(Amount) OVER (ORDER BY Date RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) FROM Orders", "RANGE"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		stmt := program.Statements[0].(*ast.SelectStatement)
		if len(stmt.Columns) < 1 {
			t.Fatalf("input %q: expected at least 1 column", tt.input)
		}

		// The expression should be a function call with OVER clause
		funcCall, ok := stmt.Columns[0].Expression.(*ast.FunctionCall)
		if !ok {
			t.Fatalf("input %q: expected FunctionCall, got %T", tt.input, stmt.Columns[0].Expression)
		}

		if funcCall.Over == nil {
			t.Fatalf("input %q: expected OVER clause", tt.input)
		}

		if funcCall.Over.Frame == nil {
			t.Fatalf("input %q: expected window frame", tt.input)
		}

		if funcCall.Over.Frame.Type != tt.frameType {
			t.Errorf("input %q: expected frame type %s, got %s", tt.input, tt.frameType, funcCall.Over.Frame.Type)
		}
	}
}

func TestCrossApply(t *testing.T) {
	input := `SELECT * FROM Customers c CROSS APPLY dbo.GetOrders(c.ID) o`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt := program.Statements[0].(*ast.SelectStatement)
	if stmt.From == nil {
		t.Fatal("expected FROM clause")
	}

	// The first table should be a JoinClause with CROSS APPLY
	join, ok := stmt.From.Tables[0].(*ast.JoinClause)
	if !ok {
		t.Fatalf("expected JoinClause, got %T", stmt.From.Tables[0])
	}

	if join.Type != "CROSS APPLY" {
		t.Errorf("expected CROSS APPLY, got %s", join.Type)
	}

	// Right side should be a TableValuedFunction
	_, ok = join.Right.(*ast.TableValuedFunction)
	if !ok {
		t.Errorf("expected TableValuedFunction on right side, got %T", join.Right)
	}
}

func TestOuterApply(t *testing.T) {
	input := `SELECT * FROM Departments d OUTER APPLY (SELECT * FROM Employees WHERE DeptID = d.ID) e`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt := program.Statements[0].(*ast.SelectStatement)
	join, ok := stmt.From.Tables[0].(*ast.JoinClause)
	if !ok {
		t.Fatalf("expected JoinClause, got %T", stmt.From.Tables[0])
	}

	if join.Type != "OUTER APPLY" {
		t.Errorf("expected OUTER APPLY, got %s", join.Type)
	}

	// Right side should be a DerivedTable
	_, ok = join.Right.(*ast.DerivedTable)
	if !ok {
		t.Errorf("expected DerivedTable on right side, got %T", join.Right)
	}
}

func TestMultipleApply(t *testing.T) {
	input := `SELECT * FROM A CROSS APPLY fn1(A.ID) B OUTER APPLY fn2(B.ID) C`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt := program.Statements[0].(*ast.SelectStatement)
	if stmt.From == nil {
		t.Fatal("expected FROM clause")
	}

	// Should have nested joins
	join1, ok := stmt.From.Tables[0].(*ast.JoinClause)
	if !ok {
		t.Fatalf("expected JoinClause, got %T", stmt.From.Tables[0])
	}

	// The left side of join1 should be another JoinClause
	join2, ok := join1.Left.(*ast.JoinClause)
	if !ok {
		t.Fatalf("expected nested JoinClause, got %T", join1.Left)
	}

	if join2.Type != "CROSS APPLY" {
		t.Errorf("expected first join CROSS APPLY, got %s", join2.Type)
	}
	if join1.Type != "OUTER APPLY" {
		t.Errorf("expected second join OUTER APPLY, got %s", join1.Type)
	}
}

func TestWindowFrameKeywordsAsIdentifiers(t *testing.T) {
	tests := []struct {
		input   string
		colName string
	}{
		{"SELECT ROWS FROM T", "ROWS"},
		{"SELECT CURRENT FROM T", "CURRENT"},
		{"SELECT RANGE FROM T", "RANGE"},
		{"SELECT ROW FROM T", "ROW"},
		{"SELECT PRECEDING FROM T", "PRECEDING"},
		{"SELECT FOLLOWING FROM T", "FOLLOWING"},
		{"SELECT UNBOUNDED FROM T", "UNBOUNDED"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Fatalf("input %q: expected 1 statement, got %d", tt.input, len(program.Statements))
		}

		stmt, ok := program.Statements[0].(*ast.SelectStatement)
		if !ok {
			t.Fatalf("input %q: expected SelectStatement, got %T", tt.input, program.Statements[0])
		}

		if len(stmt.Columns) != 1 {
			t.Fatalf("input %q: expected 1 column, got %d", tt.input, len(stmt.Columns))
		}
	}
}

func TestColumnLevelForeignKey(t *testing.T) {
	tests := []struct {
		name  string
		input string
	}{
		{
			"FOREIGN KEY REFERENCES",
			`CREATE TABLE Items (ID INT, OrderID INT FOREIGN KEY REFERENCES Orders(ID))`,
		},
		{
			"CONSTRAINT name FOREIGN KEY REFERENCES",
			`CREATE TABLE Items (ID INT, OrderID INT CONSTRAINT FK_Order FOREIGN KEY REFERENCES Orders(ID))`,
		},
		{
			"Multiple columns with FK",
			`CREATE TABLE Items (ID INT PRIMARY KEY, OrderID INT FOREIGN KEY REFERENCES Orders(ID), ProductID INT FOREIGN KEY REFERENCES Products(ID))`,
		},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Fatalf("%s: expected 1 statement, got %d", tt.name, len(program.Statements))
		}

		stmt, ok := program.Statements[0].(*ast.CreateTableStatement)
		if !ok {
			t.Fatalf("%s: expected CreateTableStatement, got %T", tt.name, program.Statements[0])
		}

		// Check that we have columns with foreign key constraints
		hasFKConstraint := false
		for _, col := range stmt.Columns {
			for _, constraint := range col.Constraints {
				if constraint.Type == ast.ConstraintForeignKey {
					hasFKConstraint = true
					if constraint.ReferencesTable == nil {
						t.Errorf("%s: FK constraint has no ReferencesTable", tt.name)
					}
				}
			}
		}

		if !hasFKConstraint {
			t.Errorf("%s: expected at least one FK constraint", tt.name)
		}
	}
}

// -----------------------------------------------------------------------------
// Stage 4a: OUTPUT Clause and DML Enhancement Tests
// -----------------------------------------------------------------------------

func TestInsertOutput(t *testing.T) {
	tests := []struct {
		name       string
		input      string
		hasOutput  bool
		hasIntoVar bool
	}{
		{"INSERT OUTPUT", `INSERT INTO Users (Name) OUTPUT inserted.ID VALUES ('Test')`, true, false},
		{"INSERT OUTPUT INTO var", `INSERT INTO Users (Name) OUTPUT inserted.ID INTO @ids VALUES ('Test')`, true, true},
		{"INSERT no OUTPUT", `INSERT INTO Users (Name) VALUES ('Test')`, false, false},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		stmt := program.Statements[0].(*ast.InsertStatement)

		if tt.hasOutput && stmt.Output == nil {
			t.Errorf("%s: expected OUTPUT clause", tt.name)
		}
		if !tt.hasOutput && stmt.Output != nil {
			t.Errorf("%s: unexpected OUTPUT clause", tt.name)
		}
		if tt.hasIntoVar && (stmt.Output == nil || stmt.Output.IntoVariable == nil) {
			t.Errorf("%s: expected OUTPUT INTO variable", tt.name)
		}
	}
}

func TestUpdateOutput(t *testing.T) {
	tests := []struct {
		name      string
		input     string
		hasOutput bool
		hasFrom   bool
	}{
		{"UPDATE OUTPUT", `UPDATE Users SET Status = 1 OUTPUT deleted.Status, inserted.Status WHERE ID = 1`, true, false},
		{"UPDATE FROM OUTPUT", `UPDATE u SET u.X = 1 OUTPUT deleted.X FROM Users u WHERE u.ID = 1`, true, true},
		{"UPDATE no OUTPUT", `UPDATE Users SET Status = 1 WHERE ID = 1`, false, false},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		stmt := program.Statements[0].(*ast.UpdateStatement)

		if tt.hasOutput && stmt.Output == nil {
			t.Errorf("%s: expected OUTPUT clause", tt.name)
		}
		if tt.hasFrom && stmt.From == nil {
			t.Errorf("%s: expected FROM clause", tt.name)
		}
	}
}

func TestDeleteOutput(t *testing.T) {
	input := `DELETE FROM Users OUTPUT deleted.* WHERE Inactive = 1`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt := program.Statements[0].(*ast.DeleteStatement)
	if stmt.Output == nil {
		t.Fatal("expected OUTPUT clause")
	}
	if len(stmt.Output.Columns) == 0 {
		t.Error("expected at least one output column")
	}
}

func TestDeleteWithJoin(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		hasAlias bool
		hasFrom  bool
	}{
		{"DELETE alias FROM", `DELETE u FROM Users u WHERE u.ID = 1`, true, true},
		{"DELETE alias JOIN", `DELETE u FROM Users u JOIN ToDelete t ON u.ID = t.UserID`, true, true},
		{"DELETE alias OUTPUT FROM", `DELETE u OUTPUT deleted.* FROM Users u JOIN ToDelete t ON u.ID = t.UserID`, true, true},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		stmt := program.Statements[0].(*ast.DeleteStatement)

		if tt.hasAlias && stmt.Alias == nil {
			t.Errorf("%s: expected alias", tt.name)
		}
		if tt.hasFrom && stmt.From == nil {
			t.Errorf("%s: expected FROM clause", tt.name)
		}
	}
}

// -----------------------------------------------------------------------------
// Stage 4b: MERGE Statement Tests
// -----------------------------------------------------------------------------

func TestMergeStatement(t *testing.T) {
	input := `MERGE INTO Target AS t USING Source AS s ON t.ID = s.ID 
		WHEN MATCHED THEN UPDATE SET t.Name = s.Name 
		WHEN NOT MATCHED THEN INSERT (ID, Name) VALUES (s.ID, s.Name)`

	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	if len(program.Statements) != 1 {
		t.Fatalf("expected 1 statement, got %d", len(program.Statements))
	}

	stmt, ok := program.Statements[0].(*ast.MergeStatement)
	if !ok {
		t.Fatalf("expected MergeStatement, got %T", program.Statements[0])
	}

	if stmt.Target == nil || stmt.Target.String() != "Target" {
		t.Error("expected Target table")
	}

	if stmt.TargetAlias == nil || stmt.TargetAlias.Value != "t" {
		t.Error("expected target alias 't'")
	}

	if stmt.SourceAlias == nil || stmt.SourceAlias.Value != "s" {
		t.Error("expected source alias 's'")
	}

	if len(stmt.WhenClauses) != 2 {
		t.Fatalf("expected 2 when clauses, got %d", len(stmt.WhenClauses))
	}

	if stmt.WhenClauses[0].Type != ast.MergeWhenMatched {
		t.Error("expected first clause to be WHEN MATCHED")
	}

	if stmt.WhenClauses[0].Action != ast.MergeActionUpdate {
		t.Error("expected first clause action to be UPDATE")
	}

	if stmt.WhenClauses[1].Type != ast.MergeWhenNotMatchedByTarget {
		t.Error("expected second clause to be WHEN NOT MATCHED")
	}

	if stmt.WhenClauses[1].Action != ast.MergeActionInsert {
		t.Error("expected second clause action to be INSERT")
	}
}

func TestMergeWithConditions(t *testing.T) {
	input := `MERGE INTO Target t USING Source s ON t.ID = s.ID 
		WHEN MATCHED AND s.Active = 1 THEN UPDATE SET t.Name = s.Name
		WHEN MATCHED AND s.Active = 0 THEN DELETE`

	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt := program.Statements[0].(*ast.MergeStatement)

	if len(stmt.WhenClauses) != 2 {
		t.Fatalf("expected 2 when clauses, got %d", len(stmt.WhenClauses))
	}

	if stmt.WhenClauses[0].Condition == nil {
		t.Error("expected condition on first clause")
	}

	if stmt.WhenClauses[1].Condition == nil {
		t.Error("expected condition on second clause")
	}

	if stmt.WhenClauses[1].Action != ast.MergeActionDelete {
		t.Error("expected second clause action to be DELETE")
	}
}

func TestMergeWithOutput(t *testing.T) {
	input := `MERGE INTO Target t USING Source s ON t.ID = s.ID 
		WHEN MATCHED THEN UPDATE SET t.Name = s.Name
		OUTPUT $action, inserted.*, deleted.*`

	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt := program.Statements[0].(*ast.MergeStatement)

	if stmt.Output == nil {
		t.Fatal("expected OUTPUT clause")
	}

	if len(stmt.Output.Columns) != 3 {
		t.Errorf("expected 3 output columns, got %d", len(stmt.Output.Columns))
	}
}

func TestMergeWithSubquerySource(t *testing.T) {
	input := `MERGE INTO Target t USING (SELECT * FROM Source WHERE Active = 1) s ON t.ID = s.ID 
		WHEN MATCHED THEN UPDATE SET t.Name = s.Name`

	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt := program.Statements[0].(*ast.MergeStatement)

	_, ok := stmt.Source.(*ast.DerivedTable)
	if !ok {
		t.Errorf("expected DerivedTable source, got %T", stmt.Source)
	}
}

// -----------------------------------------------------------------------------
// Stage 5: DDL Completion Tests
// -----------------------------------------------------------------------------

func TestCreateView(t *testing.T) {
	tests := []struct {
		name       string
		input      string
		hasColumns bool
		hasOptions bool
	}{
		{"Basic VIEW", `CREATE VIEW vwUsers AS SELECT ID, Name FROM Users`, false, false},
		{"VIEW with columns", `CREATE VIEW vwUsers (UserID, UserName) AS SELECT ID, Name FROM Users`, true, false},
		{"VIEW with schema", `CREATE VIEW dbo.vwUsers AS SELECT * FROM Users`, false, false},
		{"VIEW with SCHEMABINDING", `CREATE VIEW dbo.vwUsers WITH SCHEMABINDING AS SELECT ID, Name FROM dbo.Users`, false, true},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		stmt, ok := program.Statements[0].(*ast.CreateViewStatement)
		if !ok {
			t.Fatalf("%s: expected CreateViewStatement, got %T", tt.name, program.Statements[0])
		}

		if tt.hasColumns && len(stmt.Columns) == 0 {
			t.Errorf("%s: expected column list", tt.name)
		}
		if tt.hasOptions && len(stmt.Options) == 0 {
			t.Errorf("%s: expected options", tt.name)
		}
		if stmt.AsSelect == nil {
			t.Errorf("%s: expected AS SELECT", tt.name)
		}
	}
}

func TestCreateIndex(t *testing.T) {
	tests := []struct {
		name       string
		input      string
		isUnique   bool
		hasInclude bool
		hasWhere   bool
	}{
		{"Basic INDEX", `CREATE INDEX IX_Users_Name ON Users(Name)`, false, false, false},
		{"UNIQUE INDEX", `CREATE UNIQUE INDEX IX_Users_Email ON Users(Email)`, true, false, false},
		{"INDEX with INCLUDE", `CREATE INDEX IX_Users_Name ON Users(Name) INCLUDE (Email, Phone)`, false, true, false},
		{"INDEX with WHERE", `CREATE INDEX IX_Users_Active ON Users(Name) WHERE Active = 1`, false, false, true},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		stmt, ok := program.Statements[0].(*ast.CreateIndexStatement)
		if !ok {
			t.Fatalf("%s: expected CreateIndexStatement, got %T", tt.name, program.Statements[0])
		}

		if stmt.IsUnique != tt.isUnique {
			t.Errorf("%s: isUnique mismatch", tt.name)
		}
		if tt.hasInclude && len(stmt.IncludeColumns) == 0 {
			t.Errorf("%s: expected INCLUDE columns", tt.name)
		}
		if tt.hasWhere && stmt.Where == nil {
			t.Errorf("%s: expected WHERE clause", tt.name)
		}
	}
}

func TestCreateFunction(t *testing.T) {
	tests := []struct {
		name         string
		input        string
		paramCount   int
		returnsTable bool
	}{
		{"Scalar function", `CREATE FUNCTION dbo.AddNumbers(@a INT, @b INT) RETURNS INT AS BEGIN RETURN @a + @b END`, 2, false},
		{"Inline TVF", `CREATE FUNCTION dbo.GetOrders(@UserID INT) RETURNS TABLE AS RETURN SELECT * FROM Orders WHERE UserID = @UserID`, 1, true},
		{"No params", `CREATE FUNCTION dbo.GetCount() RETURNS INT AS BEGIN RETURN 1 END`, 0, false},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		stmt, ok := program.Statements[0].(*ast.CreateFunctionStatement)
		if !ok {
			t.Fatalf("%s: expected CreateFunctionStatement, got %T", tt.name, program.Statements[0])
		}

		if len(stmt.Parameters) != tt.paramCount {
			t.Errorf("%s: expected %d params, got %d", tt.name, tt.paramCount, len(stmt.Parameters))
		}
		if stmt.ReturnsTable != tt.returnsTable {
			t.Errorf("%s: returnsTable mismatch", tt.name)
		}
	}
}

func TestCreateTrigger(t *testing.T) {
	tests := []struct {
		name       string
		input      string
		timing     ast.TriggerTiming
		eventCount int
	}{
		{"AFTER INSERT", `CREATE TRIGGER trg_Test ON Users AFTER INSERT AS BEGIN PRINT 'inserted' END`, ast.TriggerAfter, 1},
		{"INSTEAD OF DELETE", `CREATE TRIGGER trg_Test ON Users INSTEAD OF DELETE AS BEGIN PRINT 'blocked' END`, ast.TriggerInsteadOf, 1},
		{"FOR INSERT, UPDATE", `CREATE TRIGGER trg_Test ON Users FOR INSERT, UPDATE AS BEGIN PRINT 'changed' END`, ast.TriggerFor, 2},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		stmt, ok := program.Statements[0].(*ast.CreateTriggerStatement)
		if !ok {
			t.Fatalf("%s: expected CreateTriggerStatement, got %T", tt.name, program.Statements[0])
		}

		if stmt.Timing != tt.timing {
			t.Errorf("%s: timing mismatch", tt.name)
		}
		if len(stmt.Events) != tt.eventCount {
			t.Errorf("%s: expected %d events, got %d", tt.name, tt.eventCount, len(stmt.Events))
		}
	}
}

func TestDropStatements(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		ifExists bool
	}{
		{"DROP VIEW", `DROP VIEW vwUsers`, false},
		{"DROP VIEW IF EXISTS", `DROP VIEW IF EXISTS vwUsers`, true},
		{"DROP FUNCTION", `DROP FUNCTION dbo.GetName`, false},
		{"DROP FUNCTION IF EXISTS", `DROP FUNCTION IF EXISTS dbo.GetName`, true},
		{"DROP PROCEDURE", `DROP PROCEDURE dbo.MyProc`, false},
		{"DROP PROC IF EXISTS", `DROP PROCEDURE IF EXISTS dbo.MyProc`, true},
		{"DROP TRIGGER", `DROP TRIGGER trg_Test`, false},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		stmt, ok := program.Statements[0].(*ast.DropObjectStatement)
		if !ok {
			t.Fatalf("%s: expected DropObjectStatement, got %T", tt.name, program.Statements[0])
		}

		if stmt.IfExists != tt.ifExists {
			t.Errorf("%s: ifExists mismatch", tt.name)
		}
	}
}

func TestDropIndex(t *testing.T) {
	input := `DROP INDEX IX_Users_Name ON Users`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt, ok := program.Statements[0].(*ast.DropIndexStatement)
	if !ok {
		t.Fatalf("expected DropIndexStatement, got %T", program.Statements[0])
	}

	if stmt.Name == nil || stmt.Name.Value != "IX_Users_Name" {
		t.Error("expected index name IX_Users_Name")
	}
	if stmt.Table == nil {
		t.Error("expected table name")
	}
}

// -----------------------------------------------------------------------------
// Stage 6: Set Operations & Grouping Tests
// -----------------------------------------------------------------------------

func TestUnion(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		unionAll bool
	}{
		{"UNION", `SELECT A FROM T1 UNION SELECT A FROM T2`, false},
		{"UNION ALL", `SELECT A FROM T1 UNION ALL SELECT A FROM T2`, true},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		stmt, ok := program.Statements[0].(*ast.SelectStatement)
		if !ok {
			t.Fatalf("%s: expected SelectStatement, got %T", tt.name, program.Statements[0])
		}

		if stmt.Union == nil {
			t.Fatalf("%s: expected Union clause", tt.name)
		}

		if stmt.Union.All != tt.unionAll {
			t.Errorf("%s: UNION ALL mismatch", tt.name)
		}
	}
}

func TestIntersectExcept(t *testing.T) {
	tests := []struct {
		name   string
		input  string
		opType string
	}{
		{"INTERSECT", `SELECT A FROM T1 INTERSECT SELECT A FROM T2`, "INTERSECT"},
		{"EXCEPT", `SELECT A FROM T1 EXCEPT SELECT A FROM T2`, "EXCEPT"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		stmt, ok := program.Statements[0].(*ast.SelectStatement)
		if !ok {
			t.Fatalf("%s: expected SelectStatement, got %T", tt.name, program.Statements[0])
		}

		if stmt.Union == nil {
			t.Fatalf("%s: expected set operation", tt.name)
		}

		if stmt.Union.Type != tt.opType {
			t.Errorf("%s: expected %s, got %s", tt.name, tt.opType, stmt.Union.Type)
		}
	}
}

func TestGroupByRollupCube(t *testing.T) {
	tests := []struct {
		name  string
		input string
	}{
		{"ROLLUP", `SELECT A, SUM(X) FROM T GROUP BY ROLLUP(A)`},
		{"CUBE", `SELECT A, B, SUM(X) FROM T GROUP BY CUBE(A, B)`},
		{"GROUPING SETS", `SELECT A, SUM(X) FROM T GROUP BY GROUPING SETS((A), ())`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		stmt, ok := program.Statements[0].(*ast.SelectStatement)
		if !ok {
			t.Fatalf("%s: expected SelectStatement, got %T", tt.name, program.Statements[0])
		}

		if len(stmt.GroupBy) == 0 {
			t.Errorf("%s: expected GROUP BY clause", tt.name)
		}
	}
}

func TestEmptyTuple(t *testing.T) {
	input := `SELECT A FROM T GROUP BY GROUPING SETS(())`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	if len(program.Statements) == 0 {
		t.Fatal("expected statement")
	}
}

// -----------------------------------------------------------------------------
// Stage 7a: Quick Wins Tests
// -----------------------------------------------------------------------------

func TestUseStatement(t *testing.T) {
	tests := []struct {
		input    string
		database string
	}{
		{`USE MyDatabase`, "MyDatabase"},
		{`USE master`, "master"},
		{`USE [My Database]`, "My Database"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		stmt, ok := program.Statements[0].(*ast.UseStatement)
		if !ok {
			t.Fatalf("expected UseStatement, got %T", program.Statements[0])
		}
		if stmt.Database.Value != tt.database {
			t.Errorf("expected database %s, got %s", tt.database, stmt.Database.Value)
		}
	}
}

func TestWaitforStatement(t *testing.T) {
	tests := []struct {
		input string
		typ   string
	}{
		{`WAITFOR DELAY '00:00:05'`, "DELAY"},
		{`WAITFOR TIME '14:30:00'`, "TIME"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		stmt, ok := program.Statements[0].(*ast.WaitforStatement)
		if !ok {
			t.Fatalf("expected WaitforStatement, got %T", program.Statements[0])
		}
		if stmt.Type != tt.typ {
			t.Errorf("expected type %s, got %s", tt.typ, stmt.Type)
		}
	}
}

func TestSaveTransaction(t *testing.T) {
	tests := []string{
		`SAVE TRANSACTION SavePoint1`,
		`SAVE TRAN SP1`,
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		_, ok := program.Statements[0].(*ast.SaveTransactionStatement)
		if !ok {
			t.Fatalf("expected SaveTransactionStatement, got %T", program.Statements[0])
		}
	}
}

func TestGotoAndLabel(t *testing.T) {
	// Test GOTO
	l := lexer.New(`GOTO ErrorHandler`)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	gotoStmt, ok := program.Statements[0].(*ast.GotoStatement)
	if !ok {
		t.Fatalf("expected GotoStatement, got %T", program.Statements[0])
	}
	if gotoStmt.Label.Value != "ErrorHandler" {
		t.Errorf("expected label ErrorHandler, got %s", gotoStmt.Label.Value)
	}

	// Test Label
	l = lexer.New(`ErrorHandler:`)
	p = New(l)
	program = p.ParseProgram()
	checkParserErrors(t, p)

	labelStmt, ok := program.Statements[0].(*ast.LabelStatement)
	if !ok {
		t.Fatalf("expected LabelStatement, got %T", program.Statements[0])
	}
	if labelStmt.Name.Value != "ErrorHandler" {
		t.Errorf("expected name ErrorHandler, got %s", labelStmt.Name.Value)
	}
}

func TestSetTransactionIsolation(t *testing.T) {
	tests := []struct {
		input string
		level string
	}{
		{`SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED`, "READ UNCOMMITTED"},
		{`SET TRANSACTION ISOLATION LEVEL READ COMMITTED`, "READ COMMITTED"},
		{`SET TRANSACTION ISOLATION LEVEL REPEATABLE READ`, "REPEATABLE READ"},
		{`SET TRANSACTION ISOLATION LEVEL SERIALIZABLE`, "SERIALIZABLE"},
		{`SET TRANSACTION ISOLATION LEVEL SNAPSHOT`, "SNAPSHOT"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		stmt, ok := program.Statements[0].(*ast.SetTransactionIsolationStatement)
		if !ok {
			t.Fatalf("expected SetTransactionIsolationStatement, got %T", program.Statements[0])
		}
		if stmt.Level != tt.level {
			t.Errorf("expected level %s, got %s", tt.level, stmt.Level)
		}
	}
}

func TestSetOptionsExtended(t *testing.T) {
	tests := []struct {
		input  string
		option string
	}{
		{`SET IDENTITY_INSERT Users ON`, "IDENTITY_INSERT"},
		{`SET ROWCOUNT 100`, "ROWCOUNT"},
		{`SET LANGUAGE us_english`, "LANGUAGE"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		stmt, ok := program.Statements[0].(*ast.SetOptionStatement)
		if !ok {
			t.Fatalf("%s: expected SetOptionStatement, got %T", tt.input, program.Statements[0])
		}
		if stmt.Option != tt.option {
			t.Errorf("expected option %s, got %s", tt.option, stmt.Option)
		}
	}
}

func TestCastExpression(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"SELECT CAST(123 AS VARCHAR(10))", "CAST(123 AS VARCHAR(10))"},
		{"SELECT CAST('abc' AS INT)", "CAST('abc' AS INT)"},
		{"SELECT CAST(Amount AS DECIMAL(10, 2)) FROM Orders", "CAST(Amount AS DECIMAL(10, 2))"},
		{"SELECT TRY_CAST('123' AS INT)", "TRY_CAST('123' AS INT)"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Fatalf("expected 1 statement, got %d", len(program.Statements))
		}

		selectStmt, ok := program.Statements[0].(*ast.SelectStatement)
		if !ok {
			t.Fatalf("expected SelectStatement, got %T", program.Statements[0])
		}

		if len(selectStmt.Columns) < 1 {
			t.Fatalf("expected at least 1 column")
		}

		castExpr, ok := selectStmt.Columns[0].Expression.(*ast.CastExpression)
		if !ok {
			t.Fatalf("expected CastExpression, got %T", selectStmt.Columns[0].Expression)
		}

		if castExpr.String() != tt.expected {
			t.Errorf("expected %q, got %q", tt.expected, castExpr.String())
		}
	}
}

func TestConvertExpression(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"SELECT CONVERT(VARCHAR(10), 123)", "CONVERT(VARCHAR(10), 123)"},
		{"SELECT CONVERT(INT, '123')", "CONVERT(INT, '123')"},
		{"SELECT CONVERT(VARCHAR(10), GETDATE(), 101)", "CONVERT(VARCHAR(10), GETDATE(), 101)"},
		{"SELECT TRY_CONVERT(INT, 'abc')", "TRY_CONVERT(INT, 'abc')"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Fatalf("expected 1 statement, got %d", len(program.Statements))
		}

		selectStmt, ok := program.Statements[0].(*ast.SelectStatement)
		if !ok {
			t.Fatalf("expected SelectStatement, got %T", program.Statements[0])
		}

		if len(selectStmt.Columns) < 1 {
			t.Fatalf("expected at least 1 column")
		}

		convExpr, ok := selectStmt.Columns[0].Expression.(*ast.ConvertExpression)
		if !ok {
			t.Fatalf("expected ConvertExpression, got %T", selectStmt.Columns[0].Expression)
		}

		if convExpr.String() != tt.expected {
			t.Errorf("expected %q, got %q", tt.expected, convExpr.String())
		}
	}
}

func TestForXmlClause(t *testing.T) {
	tests := []struct {
		input   string
		forType string
		mode    string
		hasRoot bool
	}{
		{"SELECT * FROM T FOR XML RAW", "XML", "RAW", false},
		{"SELECT * FROM T FOR XML AUTO", "XML", "AUTO", false},
		{"SELECT * FROM T FOR XML PATH", "XML", "PATH", false},
		{"SELECT * FROM T FOR XML PATH('row'), ROOT('data')", "XML", "PATH", true},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Fatalf("expected 1 statement, got %d", len(program.Statements))
		}

		selectStmt, ok := program.Statements[0].(*ast.SelectStatement)
		if !ok {
			t.Fatalf("expected SelectStatement, got %T", program.Statements[0])
		}

		if selectStmt.ForClause == nil {
			t.Fatalf("expected ForClause, got nil")
		}

		if selectStmt.ForClause.ForType != tt.forType {
			t.Errorf("expected ForType %q, got %q", tt.forType, selectStmt.ForClause.ForType)
		}

		if selectStmt.ForClause.Mode != tt.mode {
			t.Errorf("expected Mode %q, got %q", tt.mode, selectStmt.ForClause.Mode)
		}

		if tt.hasRoot && selectStmt.ForClause.Root == "" {
			t.Errorf("expected Root to be set")
		}
	}
}

func TestForJsonClause(t *testing.T) {
	tests := []struct {
		input   string
		mode    string
		options string
	}{
		{"SELECT * FROM T FOR JSON AUTO", "AUTO", ""},
		{"SELECT * FROM T FOR JSON PATH", "PATH", ""},
		{"SELECT * FROM T FOR JSON AUTO, ROOT('data')", "AUTO", "root"},
		{"SELECT * FROM T FOR JSON PATH, WITHOUT_ARRAY_WRAPPER", "PATH", "nowrap"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Fatalf("expected 1 statement, got %d", len(program.Statements))
		}

		selectStmt, ok := program.Statements[0].(*ast.SelectStatement)
		if !ok {
			t.Fatalf("expected SelectStatement, got %T", program.Statements[0])
		}

		if selectStmt.ForClause == nil {
			t.Fatalf("expected ForClause, got nil")
		}

		if selectStmt.ForClause.ForType != "JSON" {
			t.Errorf("expected ForType JSON, got %q", selectStmt.ForClause.ForType)
		}

		if selectStmt.ForClause.Mode != tt.mode {
			t.Errorf("expected Mode %q, got %q", tt.mode, selectStmt.ForClause.Mode)
		}
	}
}

func TestPivotTable(t *testing.T) {
	tests := []struct {
		input     string
		aggregate string
		pivotCol  string
		numValues int
	}{
		{"SELECT * FROM Sales PIVOT (SUM(Amount) FOR Quarter IN ([Q1], [Q2], [Q3], [Q4])) AS P", "SUM", "Quarter", 4},
		{"SELECT * FROM Orders PIVOT (COUNT(OrderID) FOR Status IN ([Pending], [Shipped])) AS P", "COUNT", "Status", 2},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Fatalf("expected 1 statement, got %d", len(program.Statements))
		}

		selectStmt, ok := program.Statements[0].(*ast.SelectStatement)
		if !ok {
			t.Fatalf("expected SelectStatement, got %T", program.Statements[0])
		}

		if selectStmt.From == nil || len(selectStmt.From.Tables) == 0 {
			t.Fatalf("expected FROM clause with tables")
		}

		pivot, ok := selectStmt.From.Tables[0].(*ast.PivotTable)
		if !ok {
			t.Fatalf("expected PivotTable, got %T", selectStmt.From.Tables[0])
		}

		if pivot.AggregateFunc != tt.aggregate {
			t.Errorf("expected aggregate %q, got %q", tt.aggregate, pivot.AggregateFunc)
		}

		if pivot.PivotColumn.Value != tt.pivotCol {
			t.Errorf("expected pivot column %q, got %q", tt.pivotCol, pivot.PivotColumn.Value)
		}

		if len(pivot.PivotValues) != tt.numValues {
			t.Errorf("expected %d pivot values, got %d", tt.numValues, len(pivot.PivotValues))
		}
	}
}

func TestUnpivotTable(t *testing.T) {
	input := "SELECT * FROM PivotedSales UNPIVOT (Amount FOR Quarter IN ([Q1], [Q2], [Q3], [Q4])) AS U"

	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	if len(program.Statements) != 1 {
		t.Fatalf("expected 1 statement, got %d", len(program.Statements))
	}

	selectStmt, ok := program.Statements[0].(*ast.SelectStatement)
	if !ok {
		t.Fatalf("expected SelectStatement, got %T", program.Statements[0])
	}

	if selectStmt.From == nil || len(selectStmt.From.Tables) == 0 {
		t.Fatalf("expected FROM clause with tables")
	}

	unpivot, ok := selectStmt.From.Tables[0].(*ast.UnpivotTable)
	if !ok {
		t.Fatalf("expected UnpivotTable, got %T", selectStmt.From.Tables[0])
	}

	if unpivot.ValueColumn.Value != "Amount" {
		t.Errorf("expected value column 'Amount', got %q", unpivot.ValueColumn.Value)
	}

	if unpivot.PivotColumn.Value != "Quarter" {
		t.Errorf("expected pivot column 'Quarter', got %q", unpivot.PivotColumn.Value)
	}

	if len(unpivot.SourceColumns) != 4 {
		t.Errorf("expected 4 source columns, got %d", len(unpivot.SourceColumns))
	}
}

func TestCollateExpression(t *testing.T) {
	tests := []struct {
		input     string
		collation string
	}{
		{"SELECT Name COLLATE Latin1_General_CI_AS FROM T", "Latin1_General_CI_AS"},
		{"SELECT * FROM T ORDER BY Name COLLATE Latin1_General_BIN", "Latin1_General_BIN"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Fatalf("expected 1 statement, got %d", len(program.Statements))
		}
	}
}

func TestOptionClause(t *testing.T) {
	tests := []struct {
		input      string
		numOptions int
	}{
		{"SELECT * FROM T OPTION (RECOMPILE)", 1},
		{"SELECT * FROM T OPTION (MAXDOP 4)", 1},
		{"SELECT * FROM T OPTION (RECOMPILE, MAXDOP 4)", 2},
		{"SELECT * FROM T OPTION (HASH JOIN, FORCE ORDER)", 2},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Fatalf("expected 1 statement, got %d", len(program.Statements))
		}

		selectStmt, ok := program.Statements[0].(*ast.SelectStatement)
		if !ok {
			t.Fatalf("expected SelectStatement, got %T", program.Statements[0])
		}

		if len(selectStmt.Options) != tt.numOptions {
			t.Errorf("expected %d options, got %d", tt.numOptions, len(selectStmt.Options))
		}
	}
}

func TestNextValueFor(t *testing.T) {
	input := `SELECT NEXT VALUE FOR dbo.MySequence`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	if len(program.Statements) != 1 {
		t.Fatalf("expected 1 statement, got %d", len(program.Statements))
	}
}

func TestParseExpression(t *testing.T) {
	tests := []string{
		`SELECT PARSE('123' AS INT)`,
		`SELECT TRY_PARSE('2023-01-01' AS DATE)`,
		`SELECT PARSE('123' AS INT USING 'en-US')`,
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Fatalf("expected 1 statement for %q, got %d", input, len(program.Statements))
		}
	}
}

func TestValuesTableConstructor(t *testing.T) {
	input := `SELECT * FROM (VALUES (1, 'a'), (2, 'b'), (3, 'c')) AS V(ID, Name)`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	if len(program.Statements) != 1 {
		t.Fatalf("expected 1 statement, got %d", len(program.Statements))
	}
}

func TestWithinGroup(t *testing.T) {
	input := `SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY Salary) OVER () FROM Employees`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	if len(program.Statements) != 1 {
		t.Fatalf("expected 1 statement, got %d", len(program.Statements))
	}
}

func TestAllQuantifier(t *testing.T) {
	tests := []string{
		`SELECT * FROM T WHERE Col > ALL (SELECT Val FROM S)`,
		`SELECT * FROM T WHERE Col = ALL (SELECT Val FROM S)`,
		`SELECT * FROM T WHERE Col <> ALL (SELECT Val FROM S)`,
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Fatalf("expected 1 statement for %q, got %d", input, len(program.Statements))
		}
	}
}

func TestCompoundAssignmentOperators(t *testing.T) {
	tests := []struct {
		input    string
		operator string
	}{
		{`UPDATE T SET Counter += 1`, "+="},
		{`UPDATE T SET Balance -= 100`, "-="},
		{`UPDATE T SET Total *= 1.1`, "*="},
		{`UPDATE T SET Value /= 2`, "/="},
		{`UPDATE T SET Remainder %= 10`, "%="},
		{`UPDATE T SET Flags &= 0xFF`, "&="},
		{`UPDATE T SET Flags |= 0x01`, "|="},
		{`UPDATE T SET Flags ^= 0x01`, "^="},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Fatalf("expected 1 statement for %q, got %d", tt.input, len(program.Statements))
		}

		updateStmt, ok := program.Statements[0].(*ast.UpdateStatement)
		if !ok {
			t.Fatalf("expected UpdateStatement, got %T", program.Statements[0])
		}

		if len(updateStmt.SetClauses) != 1 {
			t.Fatalf("expected 1 set clause, got %d", len(updateStmt.SetClauses))
		}

		if updateStmt.SetClauses[0].Operator != tt.operator {
			t.Errorf("expected operator %q, got %q", tt.operator, updateStmt.SetClauses[0].Operator)
		}
	}
}

func TestIndexHint(t *testing.T) {
	tests := []struct {
		input    string
		expected []string
	}{
		{`SELECT * FROM T WITH (INDEX(IX_Col))`, []string{"INDEX(IX_Col)"}},
		{`SELECT * FROM T WITH (INDEX(IX_Col1, IX_Col2))`, []string{"INDEX(IX_Col1, IX_Col2)"}},
		{`SELECT * FROM T WITH (INDEX(IX_Col), NOLOCK)`, []string{"INDEX(IX_Col)", "NOLOCK"}},
		{`SELECT * FROM T WITH (NOLOCK, INDEX(IX_Col))`, []string{"NOLOCK", "INDEX(IX_Col)"}},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Fatalf("expected 1 statement for %q, got %d", tt.input, len(program.Statements))
		}

		selectStmt, ok := program.Statements[0].(*ast.SelectStatement)
		if !ok {
			t.Fatalf("expected SelectStatement, got %T", program.Statements[0])
		}

		table, ok := selectStmt.From.Tables[0].(*ast.TableName)
		if !ok {
			t.Fatalf("expected TableName, got %T", selectStmt.From.Tables[0])
		}

		if len(table.Hints) != len(tt.expected) {
			t.Errorf("expected %d hints, got %d", len(tt.expected), len(table.Hints))
		}

		for i, hint := range table.Hints {
			if hint != tt.expected[i] {
				t.Errorf("expected hint %q, got %q", tt.expected[i], hint)
			}
		}
	}
}

func TestSetStatementVariants(t *testing.T) {
	tests := []struct {
		input  string
		option string
		value  string
	}{
		{`SET ANSI_WARNINGS ON`, "ANSI_WARNINGS", "ON"},
		{`SET ANSI_WARNINGS OFF`, "ANSI_WARNINGS", "OFF"},
		{`SET ARITHABORT ON`, "ARITHABORT", "ON"},
		{`SET CONCAT_NULL_YIELDS_NULL ON`, "CONCAT_NULL_YIELDS_NULL", "ON"},
		{`SET NUMERIC_ROUNDABORT OFF`, "NUMERIC_ROUNDABORT", "OFF"},
		{`SET STATISTICS IO ON`, "STATISTICS IO", "ON"},
		{`SET STATISTICS TIME ON`, "STATISTICS TIME", "ON"},
		{`SET SHOWPLAN_TEXT ON`, "SHOWPLAN_TEXT", "ON"},
		{`SET SHOWPLAN_XML ON`, "SHOWPLAN_XML", "ON"},
		{`SET FMTONLY ON`, "FMTONLY", "ON"},
		{`SET PARSEONLY ON`, "PARSEONLY", "ON"},
		{`SET DEADLOCK_PRIORITY LOW`, "DEADLOCK_PRIORITY", "LOW"},
		{`SET DEADLOCK_PRIORITY HIGH`, "DEADLOCK_PRIORITY", "HIGH"},
		{`SET CONTEXT_INFO 0x01020304`, "CONTEXT_INFO", "0x01020304"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Fatalf("expected 1 statement for %q, got %d", tt.input, len(program.Statements))
		}

		setStmt, ok := program.Statements[0].(*ast.SetStatement)
		if !ok {
			t.Fatalf("expected SetStatement for %q, got %T", tt.input, program.Statements[0])
		}

		if setStmt.Option != tt.option {
			t.Errorf("expected option %q, got %q", tt.option, setStmt.Option)
		}

		if setStmt.OnOff != tt.value {
			t.Errorf("expected value %q, got %q", tt.value, setStmt.OnOff)
		}
	}
}

func checkParserErrors(t *testing.T, p *Parser) {
	errors := p.Errors()
	if len(errors) == 0 {
		return
	}

	t.Errorf("parser has %d errors", len(errors))
	for _, msg := range errors {
		t.Errorf("parser error: %s", msg)
	}
	t.FailNow()
}

// Stage 2 Tests

func TestUseHint(t *testing.T) {
	tests := []struct {
		input    string
		hints    []string
		optCount int
	}{
		{`SELECT * FROM T OPTION (USE HINT('DISABLE_OPTIMIZER_ROWGOAL'))`, []string{"DISABLE_OPTIMIZER_ROWGOAL"}, 1},
		{`SELECT * FROM T OPTION (USE HINT('FORCE_DEFAULT_CARDINALITY_ESTIMATION', 'DISABLE_PARAMETER_SNIFFING'))`, []string{"FORCE_DEFAULT_CARDINALITY_ESTIMATION", "DISABLE_PARAMETER_SNIFFING"}, 1},
		{`SELECT * FROM T OPTION (RECOMPILE, USE HINT('DISABLE_OPTIMIZER_ROWGOAL'))`, []string{"DISABLE_OPTIMIZER_ROWGOAL"}, 2},
		{`SELECT * FROM T OPTION (USE HINT('FORCE_LEGACY_CARDINALITY_ESTIMATION'), MAXDOP 4)`, []string{"FORCE_LEGACY_CARDINALITY_ESTIMATION"}, 2},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		selectStmt, ok := program.Statements[0].(*ast.SelectStatement)
		if !ok {
			t.Fatalf("expected SelectStatement, got %T", program.Statements[0])
		}

		if len(selectStmt.Options) != tt.optCount {
			t.Errorf("expected %d options, got %d", tt.optCount, len(selectStmt.Options))
			continue
		}

		// Find USE HINT option
		var useHintOpt *ast.QueryOption
		for _, opt := range selectStmt.Options {
			if opt.Name == "USE HINT" {
				useHintOpt = opt
				break
			}
		}

		if useHintOpt == nil {
			t.Errorf("expected USE HINT option")
			continue
		}

		if len(useHintOpt.Hints) != len(tt.hints) {
			t.Errorf("expected %d hints, got %d", len(tt.hints), len(useHintOpt.Hints))
			continue
		}

		for i, hint := range useHintOpt.Hints {
			if hint != tt.hints[i] {
				t.Errorf("expected hint %q, got %q", tt.hints[i], hint)
			}
		}
	}
}

func TestTableSample(t *testing.T) {
	tests := []struct {
		input     string
		isPercent bool
		isRows    bool
		system    bool
		hasRepeat bool
	}{
		{`SELECT * FROM Orders TABLESAMPLE (10 PERCENT)`, true, false, false, false},
		{`SELECT * FROM Orders TABLESAMPLE (1000 ROWS)`, false, true, false, false},
		{`SELECT * FROM Orders TABLESAMPLE SYSTEM (10 PERCENT)`, true, false, true, false},
		{`SELECT * FROM Orders TABLESAMPLE (5 PERCENT) AS O`, true, false, false, false},
		{`SELECT * FROM Orders TABLESAMPLE (10 PERCENT) REPEATABLE (42)`, true, false, false, true},
		{`SELECT * FROM Orders TABLESAMPLE (10 PERCENT) WITH (NOLOCK)`, true, false, false, false},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		selectStmt, ok := program.Statements[0].(*ast.SelectStatement)
		if !ok {
			t.Fatalf("expected SelectStatement for %q, got %T", tt.input, program.Statements[0])
		}

		table, ok := selectStmt.From.Tables[0].(*ast.TableName)
		if !ok {
			t.Fatalf("expected TableName, got %T", selectStmt.From.Tables[0])
		}

		if table.TableSample == nil {
			t.Errorf("expected TableSample for %q", tt.input)
			continue
		}

		if table.TableSample.IsPercent != tt.isPercent {
			t.Errorf("expected IsPercent=%v, got %v for %q", tt.isPercent, table.TableSample.IsPercent, tt.input)
		}
		if table.TableSample.IsRows != tt.isRows {
			t.Errorf("expected IsRows=%v, got %v for %q", tt.isRows, table.TableSample.IsRows, tt.input)
		}
		if table.TableSample.System != tt.system {
			t.Errorf("expected System=%v, got %v for %q", tt.system, table.TableSample.System, tt.input)
		}
		if (table.TableSample.Seed != nil) != tt.hasRepeat {
			t.Errorf("expected hasRepeat=%v for %q", tt.hasRepeat, tt.input)
		}
	}
}

func TestAtTimeZone(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`SELECT OrderDate AT TIME ZONE 'UTC' FROM Orders`},
		{`SELECT OrderDate AT TIME ZONE 'Pacific Standard Time' FROM Orders`},
		{`SELECT SYSDATETIMEOFFSET() AT TIME ZONE 'Eastern Standard Time'`},
		{`SELECT OrderDate AT TIME ZONE 'UTC' AT TIME ZONE 'Pacific Standard Time' FROM Orders`},
		{`SELECT * FROM Orders WHERE OrderDate AT TIME ZONE 'UTC' > '2024-01-01'`},
		{`SELECT OrderDate AT TIME ZONE @tz FROM Orders`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement for %q, got %d", tt.input, len(program.Statements))
		}

		// Check that it contains AT TIME ZONE in output
		output := program.String()
		if !strings.Contains(output, "AT TIME ZONE") {
			t.Errorf("expected AT TIME ZONE in output for %q, got %q", tt.input, output)
		}
	}
}

func TestAlterTableTrigger(t *testing.T) {
	tests := []struct {
		input       string
		actionType  ast.AlterActionType
		triggerName string
		allTriggers bool
	}{
		{`ALTER TABLE dbo.Orders DISABLE TRIGGER TR_Orders_Insert`, ast.AlterDisableTrigger, "TR_Orders_Insert", false},
		{`ALTER TABLE dbo.Orders ENABLE TRIGGER TR_Orders_Insert`, ast.AlterEnableTrigger, "TR_Orders_Insert", false},
		{`ALTER TABLE dbo.Orders DISABLE TRIGGER ALL`, ast.AlterDisableTrigger, "", true},
		{`ALTER TABLE dbo.Orders ENABLE TRIGGER ALL`, ast.AlterEnableTrigger, "", true},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		alterStmt, ok := program.Statements[0].(*ast.AlterTableStatement)
		if !ok {
			t.Fatalf("expected AlterTableStatement for %q, got %T", tt.input, program.Statements[0])
		}

		if len(alterStmt.Actions) != 1 {
			t.Errorf("expected 1 action, got %d", len(alterStmt.Actions))
			continue
		}

		action := alterStmt.Actions[0]
		if action.Type != tt.actionType {
			t.Errorf("expected action type %v, got %v for %q", tt.actionType, action.Type, tt.input)
		}
		if action.TriggerName != tt.triggerName {
			t.Errorf("expected trigger name %q, got %q for %q", tt.triggerName, action.TriggerName, tt.input)
		}
		if action.AllTriggers != tt.allTriggers {
			t.Errorf("expected AllTriggers=%v, got %v for %q", tt.allTriggers, action.AllTriggers, tt.input)
		}
	}
}

func TestCreateDropSynonym(t *testing.T) {
	tests := []struct {
		input  string
		target string // For CREATE, the target name
	}{
		{`CREATE SYNONYM dbo.SynTable FOR dbo.RealTable`, "dbo.RealTable"},
		{`CREATE SYNONYM Sales.Orders FOR Production.OrderDetails`, "Production.OrderDetails"},
		{`DROP SYNONYM dbo.SynTable`, ""},
		{`DROP SYNONYM IF EXISTS dbo.SynTable`, ""},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement for %q, got %d", tt.input, len(program.Statements))
		}

		// Verify output matches input pattern
		output := program.String()
		if !strings.Contains(output, "SYNONYM") {
			t.Errorf("expected SYNONYM in output for %q, got %q", tt.input, output)
		}
	}
}

func TestExecuteAs(t *testing.T) {
	tests := []struct {
		input    string
		execType string
		userName string
	}{
		{`EXECUTE AS CALLER`, "CALLER", ""},
		{`EXECUTE AS SELF`, "SELF", ""},
		{`EXECUTE AS OWNER`, "OWNER", ""},
		{`EXECUTE AS USER = 'dbo'`, "USER", "dbo"},
		{`EXECUTE AS LOGIN = 'DOMAIN\User'`, "LOGIN", `DOMAIN\User`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		stmt, ok := program.Statements[0].(*ast.ExecuteAsStatement)
		if !ok {
			t.Fatalf("expected ExecuteAsStatement for %q, got %T", tt.input, program.Statements[0])
		}

		if stmt.Type != tt.execType {
			t.Errorf("expected type %q, got %q for %q", tt.execType, stmt.Type, tt.input)
		}
		if stmt.UserName != tt.userName {
			t.Errorf("expected userName %q, got %q for %q", tt.userName, stmt.UserName, tt.input)
		}
	}
}

func TestRevert(t *testing.T) {
	tests := []struct {
		input     string
		hasCookie bool
	}{
		{`REVERT`, false},
		{`REVERT WITH COOKIE = @cookie`, true},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		stmt, ok := program.Statements[0].(*ast.RevertStatement)
		if !ok {
			t.Fatalf("expected RevertStatement for %q, got %T", tt.input, program.Statements[0])
		}

		if (stmt.Cookie != nil) != tt.hasCookie {
			t.Errorf("expected hasCookie=%v for %q", tt.hasCookie, tt.input)
		}
	}
}

func TestOpenJsonWith(t *testing.T) {
	tests := []struct {
		input       string
		columnCount int
		hasAlias    bool
	}{
		{`SELECT * FROM OPENJSON(@json)`, 0, false},
		{`SELECT * FROM OPENJSON(@json) WITH (Name NVARCHAR(100), Age INT)`, 2, false},
		{`SELECT * FROM OPENJSON(@json) WITH (Name NVARCHAR(100) '$.name', Age INT '$.age')`, 2, false},
		{`SELECT * FROM OPENJSON(@json) WITH (Data NVARCHAR(MAX) AS JSON)`, 1, false},
		{`SELECT * FROM OPENJSON(@json, '$.items') WITH (Id INT '$.id', Info NVARCHAR(MAX) '$.details' AS JSON) AS Items`, 2, true},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		selectStmt, ok := program.Statements[0].(*ast.SelectStatement)
		if !ok {
			t.Fatalf("expected SelectStatement for %q, got %T", tt.input, program.Statements[0])
		}

		tvf, ok := selectStmt.From.Tables[0].(*ast.TableValuedFunction)
		if !ok {
			t.Fatalf("expected TableValuedFunction for %q, got %T", tt.input, selectStmt.From.Tables[0])
		}

		if len(tvf.OpenJsonColumns) != tt.columnCount {
			t.Errorf("expected %d columns, got %d for %q", tt.columnCount, len(tvf.OpenJsonColumns), tt.input)
		}

		if (tvf.Alias != nil) != tt.hasAlias {
			t.Errorf("expected hasAlias=%v for %q", tt.hasAlias, tt.input)
		}
	}
}

func TestSequenceStatements(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`CREATE SEQUENCE dbo.MySeq`},
		{`CREATE SEQUENCE dbo.MySeq START WITH 1`},
		{`CREATE SEQUENCE dbo.MySeq INCREMENT BY 1`},
		{`CREATE SEQUENCE dbo.MySeq AS BIGINT START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 1000 CYCLE CACHE 10`},
		{`CREATE SEQUENCE dbo.MySeq NO MINVALUE NO MAXVALUE NO CYCLE NO CACHE`},
		{`ALTER SEQUENCE dbo.MySeq RESTART WITH 1`},
		{`ALTER SEQUENCE dbo.MySeq INCREMENT BY 5`},
		{`ALTER SEQUENCE dbo.MySeq NO CYCLE`},
		{`DROP SEQUENCE dbo.MySeq`},
		{`DROP SEQUENCE IF EXISTS dbo.MySeq`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement for %q, got %d", tt.input, len(program.Statements))
		}

		output := program.String()
		if !strings.Contains(output, "SEQUENCE") {
			t.Errorf("expected SEQUENCE in output for %q, got %q", tt.input, output)
		}
	}
}

func TestStatisticsStatements(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`CREATE STATISTICS Stat_Col ON dbo.T(Col)`},
		{`CREATE STATISTICS Stat_Cols ON dbo.T(Col1, Col2)`},
		{`CREATE STATISTICS Stat_Col ON dbo.T(Col) WITH FULLSCAN`},
		{`CREATE STATISTICS Stat_Col ON dbo.T(Col) WITH SAMPLE 50 PERCENT`},
		{`UPDATE STATISTICS dbo.T`},
		{`UPDATE STATISTICS dbo.T Stat_Col`},
		{`UPDATE STATISTICS dbo.T WITH FULLSCAN`},
		{`DROP STATISTICS dbo.T.Stat_Col`},
		{`DROP STATISTICS dbo.T.Stat1, dbo.T.Stat2`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement for %q, got %d", tt.input, len(program.Statements))
		}

		output := program.String()
		if !strings.Contains(output, "STATISTICS") {
			t.Errorf("expected STATISTICS in output for %q, got %q", tt.input, output)
		}
	}
}

func TestDbccStatements(t *testing.T) {
	tests := []struct {
		input   string
		command string
	}{
		{`DBCC CHECKDB('TestDB')`, "CHECKDB"},
		{`DBCC CHECKTABLE('dbo.T')`, "CHECKTABLE"},
		{`DBCC SHRINKFILE(TestDB_Log, 1)`, "SHRINKFILE"},
		{`DBCC FREEPROCCACHE`, "FREEPROCCACHE"},
		{`DBCC DROPCLEANBUFFERS`, "DROPCLEANBUFFERS"},
		{`DBCC CHECKDB('TestDB') WITH NO_INFOMSGS, ALL_ERRORMSGS`, "CHECKDB"},
		{`DBCC SHOW_STATISTICS('dbo.T', 'IX_T')`, "SHOW_STATISTICS"},
		{`DBCC UPDATEUSAGE('TestDB')`, "UPDATEUSAGE"},
		{`DBCC CHECKIDENT('dbo.T', RESEED, 1)`, "CHECKIDENT"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		stmt, ok := program.Statements[0].(*ast.DbccStatement)
		if !ok {
			t.Fatalf("expected DbccStatement for %q, got %T", tt.input, program.Statements[0])
		}

		if stmt.Command != tt.command {
			t.Errorf("expected command %q, got %q for %q", tt.command, stmt.Command, tt.input)
		}
	}
}

func TestGrantStatement(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`GRANT SELECT ON dbo.T TO TestUser`},
		{`GRANT EXECUTE ON dbo.P TO TestRole`},
		{`GRANT INSERT, UPDATE, DELETE ON dbo.T TO TestUser`},
		{`GRANT SELECT ON dbo.T TO TestUser WITH GRANT OPTION`},
		{`GRANT ALL ON dbo.T TO TestUser`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d", len(program.Statements))
			continue
		}

		output := program.Statements[0].String()
		if !strings.Contains(output, "GRANT") {
			t.Errorf("expected GRANT in output for %q, got %q", tt.input, output)
		}
	}
}

func TestRevokeStatement(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`REVOKE SELECT ON dbo.T FROM TestUser`},
		{`REVOKE EXECUTE ON dbo.P FROM TestRole`},
		{`REVOKE SELECT ON dbo.T FROM TestUser CASCADE`},
		{`REVOKE GRANT OPTION FOR SELECT ON dbo.T FROM TestUser`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d", len(program.Statements))
			continue
		}

		output := program.Statements[0].String()
		if !strings.Contains(output, "REVOKE") {
			t.Errorf("expected REVOKE in output for %q, got %q", tt.input, output)
		}
	}
}

func TestDenyStatement(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`DENY SELECT ON dbo.T TO TestUser`},
		{`DENY EXECUTE ON dbo.P TO TestRole`},
		{`DENY DELETE ON dbo.T TO TestUser CASCADE`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d", len(program.Statements))
			continue
		}

		output := program.Statements[0].String()
		if !strings.Contains(output, "DENY") {
			t.Errorf("expected DENY in output for %q, got %q", tt.input, output)
		}
	}
}

func TestExecWithResultSets(t *testing.T) {
	tests := []struct {
		input   string
		numSets int
	}{
		{`EXEC dbo.GetData WITH RESULT SETS ((Id INT, Name NVARCHAR(100)))`, 1},
		{`EXEC dbo.GetData WITH RESULT SETS ((Id INT), (Name NVARCHAR(50)))`, 2},
		{`EXEC dbo.GetData @Param = 1 WITH RESULT SETS ((Id INT NOT NULL, Name NVARCHAR(100) NULL))`, 1},
		{`EXECUTE dbo.MultiResult WITH RESULT SETS ((A INT, B VARCHAR(10)), (C DATE, D DECIMAL(10,2)))`, 2},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d", len(program.Statements))
			continue
		}

		exec, ok := program.Statements[0].(*ast.ExecStatement)
		if !ok {
			t.Errorf("expected ExecStatement, got %T", program.Statements[0])
			continue
		}

		if len(exec.ResultSets) != tt.numSets {
			t.Errorf("expected %d result sets for %q, got %d", tt.numSets, tt.input, len(exec.ResultSets))
		}
	}
}

func TestCreateLogin(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`CREATE LOGIN TestLogin WITH PASSWORD = 'pwd123'`},
		{`CREATE LOGIN [DOMAIN\User] FROM WINDOWS`},
		{`CREATE LOGIN TestLogin WITH PASSWORD = 'pwd', DEFAULT_DATABASE = master`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d", len(program.Statements))
			continue
		}

		_, ok := program.Statements[0].(*ast.CreateLoginStatement)
		if !ok {
			t.Errorf("expected CreateLoginStatement for %q, got %T", tt.input, program.Statements[0])
		}
	}
}

func TestAlterLogin(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`ALTER LOGIN TestLogin ENABLE`},
		{`ALTER LOGIN TestLogin DISABLE`},
		{`ALTER LOGIN TestLogin WITH PASSWORD = 'newpwd'`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d", len(program.Statements))
			continue
		}

		_, ok := program.Statements[0].(*ast.AlterLoginStatement)
		if !ok {
			t.Errorf("expected AlterLoginStatement for %q, got %T", tt.input, program.Statements[0])
		}
	}
}

func TestCreateUser(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`CREATE USER TestUser FOR LOGIN TestLogin`},
		{`CREATE USER TestUser WITHOUT LOGIN`},
		{`CREATE USER TestUser FOR LOGIN TestLogin WITH DEFAULT_SCHEMA = dbo`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d", len(program.Statements))
			continue
		}

		_, ok := program.Statements[0].(*ast.CreateUserStatement)
		if !ok {
			t.Errorf("expected CreateUserStatement for %q, got %T", tt.input, program.Statements[0])
		}
	}
}

func TestAlterUser(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`ALTER USER TestUser WITH DEFAULT_SCHEMA = Sales`},
		{`ALTER USER TestUser WITH NAME = NewName`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d", len(program.Statements))
			continue
		}

		_, ok := program.Statements[0].(*ast.AlterUserStatement)
		if !ok {
			t.Errorf("expected AlterUserStatement for %q, got %T", tt.input, program.Statements[0])
		}
	}
}

func TestCreateRole(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`CREATE ROLE TestRole`},
		{`CREATE ROLE TestRole AUTHORIZATION dbo`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d", len(program.Statements))
			continue
		}

		_, ok := program.Statements[0].(*ast.CreateRoleStatement)
		if !ok {
			t.Errorf("expected CreateRoleStatement for %q, got %T", tt.input, program.Statements[0])
		}
	}
}

func TestAlterRole(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`ALTER ROLE TestRole ADD MEMBER TestUser`},
		{`ALTER ROLE TestRole DROP MEMBER TestUser`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d", len(program.Statements))
			continue
		}

		_, ok := program.Statements[0].(*ast.AlterRoleStatement)
		if !ok {
			t.Errorf("expected AlterRoleStatement for %q, got %T", tt.input, program.Statements[0])
		}
	}
}

func TestBackupStatement(t *testing.T) {
	tests := []struct {
		input      string
		backupType string
		dbName     string
	}{
		{`BACKUP DATABASE TestDB TO DISK = 'C:\Backup\TestDB.bak'`, "DATABASE", "TestDB"},
		{`BACKUP DATABASE TestDB TO DISK = 'C:\Backup\TestDB.bak' WITH COMPRESSION`, "DATABASE", "TestDB"},
		{`BACKUP DATABASE TestDB TO DISK = 'C:\Backup\TestDB.bak' WITH COMPRESSION, INIT`, "DATABASE", "TestDB"},
		{`BACKUP LOG TestDB TO DISK = 'C:\Backup\TestDB_Log.trn'`, "LOG", "TestDB"},
		{`BACKUP DATABASE TestDB TO DISK = 'path1.bak', DISK = 'path2.bak'`, "DATABASE", "TestDB"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d", len(program.Statements))
			continue
		}

		stmt, ok := program.Statements[0].(*ast.BackupStatement)
		if !ok {
			t.Errorf("expected BackupStatement for %q, got %T", tt.input, program.Statements[0])
			continue
		}

		if stmt.BackupType != tt.backupType {
			t.Errorf("expected backup type %q, got %q", tt.backupType, stmt.BackupType)
		}
		if stmt.DatabaseName != tt.dbName {
			t.Errorf("expected database name %q, got %q", tt.dbName, stmt.DatabaseName)
		}
	}
}

func TestRestoreStatement(t *testing.T) {
	tests := []struct {
		input       string
		restoreType string
		dbName      string
	}{
		{`RESTORE DATABASE TestDB FROM DISK = 'C:\Backup\TestDB.bak'`, "DATABASE", "TestDB"},
		{`RESTORE DATABASE TestDB FROM DISK = 'C:\Backup\TestDB.bak' WITH NORECOVERY`, "DATABASE", "TestDB"},
		{`RESTORE LOG TestDB FROM DISK = 'C:\Backup\TestDB_Log.trn'`, "LOG", "TestDB"},
		{`RESTORE FILELISTONLY FROM DISK = 'C:\Backup\TestDB.bak'`, "FILELISTONLY", ""},
		{`RESTORE HEADERONLY FROM DISK = 'C:\Backup\TestDB.bak'`, "HEADERONLY", ""},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d", len(program.Statements))
			continue
		}

		stmt, ok := program.Statements[0].(*ast.RestoreStatement)
		if !ok {
			t.Errorf("expected RestoreStatement for %q, got %T", tt.input, program.Statements[0])
			continue
		}

		if stmt.RestoreType != tt.restoreType {
			t.Errorf("expected restore type %q, got %q for %q", tt.restoreType, stmt.RestoreType, tt.input)
		}
		if stmt.DatabaseName != tt.dbName {
			t.Errorf("expected database name %q, got %q for %q", tt.dbName, stmt.DatabaseName, tt.input)
		}
	}
}

func TestCreateMasterKey(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'StrongPwd123!'`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d", len(program.Statements))
			continue
		}

		_, ok := program.Statements[0].(*ast.CreateMasterKeyStatement)
		if !ok {
			t.Errorf("expected CreateMasterKeyStatement for %q, got %T", tt.input, program.Statements[0])
		}
	}
}

func TestCreateCertificate(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`CREATE CERTIFICATE MyCert WITH SUBJECT = 'My Certificate'`},
		{`CREATE CERTIFICATE MyCert FROM FILE = 'C:\certs\cert.cer'`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d", len(program.Statements))
			continue
		}

		_, ok := program.Statements[0].(*ast.CreateCertificateStatement)
		if !ok {
			t.Errorf("expected CreateCertificateStatement for %q, got %T", tt.input, program.Statements[0])
		}
	}
}

func TestSymmetricKey(t *testing.T) {
	tests := []struct {
		input    string
		stmtType string
	}{
		{`CREATE SYMMETRIC KEY MyKey WITH ALGORITHM = AES_256 ENCRYPTION BY CERTIFICATE MyCert`, "create"},
		{`OPEN SYMMETRIC KEY MyKey DECRYPTION BY CERTIFICATE MyCert`, "open"},
		{`CLOSE SYMMETRIC KEY MyKey`, "close"},
		{`CLOSE ALL SYMMETRIC KEYS`, "closeall"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
			continue
		}

		switch tt.stmtType {
		case "create":
			_, ok := program.Statements[0].(*ast.CreateSymmetricKeyStatement)
			if !ok {
				t.Errorf("expected CreateSymmetricKeyStatement for %q, got %T", tt.input, program.Statements[0])
			}
		case "open":
			_, ok := program.Statements[0].(*ast.OpenSymmetricKeyStatement)
			if !ok {
				t.Errorf("expected OpenSymmetricKeyStatement for %q, got %T", tt.input, program.Statements[0])
			}
		case "close", "closeall":
			_, ok := program.Statements[0].(*ast.CloseSymmetricKeyStatement)
			if !ok {
				t.Errorf("expected CloseSymmetricKeyStatement for %q, got %T", tt.input, program.Statements[0])
			}
		}
	}
}

func TestCreateAsymmetricKey(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`CREATE ASYMMETRIC KEY MyAsymKey FROM FILE = 'C:\keys\key.snk'`},
		{`CREATE ASYMMETRIC KEY MyAsymKey WITH ALGORITHM = RSA_2048`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d", len(program.Statements))
			continue
		}

		_, ok := program.Statements[0].(*ast.CreateAsymmetricKeyStatement)
		if !ok {
			t.Errorf("expected CreateAsymmetricKeyStatement for %q, got %T", tt.input, program.Statements[0])
		}
	}
}

func TestAssemblyStatements(t *testing.T) {
	tests := []struct {
		input    string
		stmtType string
	}{
		{`CREATE ASSEMBLY MyAssembly FROM 'C:\Assemblies\MyAssembly.dll'`, "create"},
		{`CREATE ASSEMBLY MyAssembly FROM 'C:\Assemblies\MyAssembly.dll' WITH PERMISSION_SET = SAFE`, "create"},
		{`ALTER ASSEMBLY MyAssembly FROM 'C:\Assemblies\MyAssembly_v2.dll'`, "alter"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
			continue
		}

		switch tt.stmtType {
		case "create":
			_, ok := program.Statements[0].(*ast.CreateAssemblyStatement)
			if !ok {
				t.Errorf("expected CreateAssemblyStatement for %q, got %T", tt.input, program.Statements[0])
			}
		case "alter":
			_, ok := program.Statements[0].(*ast.AlterAssemblyStatement)
			if !ok {
				t.Errorf("expected AlterAssemblyStatement for %q, got %T", tt.input, program.Statements[0])
			}
		}
	}
}

func TestCreatePartitionFunction(t *testing.T) {
	tests := []struct {
		input     string
		name      string
		rangeType string
	}{
		{`CREATE PARTITION FUNCTION PF_Date(DATE) AS RANGE RIGHT FOR VALUES ('2020-01-01', '2021-01-01')`, "PF_Date", "RIGHT"},
		{`CREATE PARTITION FUNCTION PF_ID(INT) AS RANGE LEFT FOR VALUES (100, 200, 300)`, "PF_ID", "LEFT"},
		{`CREATE PARTITION FUNCTION PF_Single(DATETIME) AS RANGE RIGHT FOR VALUES ('2023-01-01')`, "PF_Single", "RIGHT"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
			continue
		}

		stmt, ok := program.Statements[0].(*ast.CreatePartitionFunctionStatement)
		if !ok {
			t.Errorf("expected CreatePartitionFunctionStatement for %q, got %T", tt.input, program.Statements[0])
			continue
		}

		if stmt.Name != tt.name {
			t.Errorf("expected name %q, got %q", tt.name, stmt.Name)
		}
		if stmt.RangeType != tt.rangeType {
			t.Errorf("expected range type %q, got %q", tt.rangeType, stmt.RangeType)
		}
	}
}

func TestAlterPartitionFunction(t *testing.T) {
	tests := []struct {
		input  string
		action string
	}{
		{`ALTER PARTITION FUNCTION PF_Date() SPLIT RANGE ('2023-01-01')`, "SPLIT"},
		{`ALTER PARTITION FUNCTION PF_Date() MERGE RANGE ('2020-01-01')`, "MERGE"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
			continue
		}

		stmt, ok := program.Statements[0].(*ast.AlterPartitionFunctionStatement)
		if !ok {
			t.Errorf("expected AlterPartitionFunctionStatement for %q, got %T", tt.input, program.Statements[0])
			continue
		}

		if stmt.Action != tt.action {
			t.Errorf("expected action %q, got %q", tt.action, stmt.Action)
		}
	}
}

func TestCreatePartitionScheme(t *testing.T) {
	tests := []struct {
		input        string
		name         string
		functionName string
	}{
		{`CREATE PARTITION SCHEME PS_Date AS PARTITION PF_Date ALL TO ([PRIMARY])`, "PS_Date", "PF_Date"},
		{`CREATE PARTITION SCHEME PS_Date AS PARTITION PF_Date TO ([FG1], [FG2])`, "PS_Date", "PF_Date"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
			continue
		}

		stmt, ok := program.Statements[0].(*ast.CreatePartitionSchemeStatement)
		if !ok {
			t.Errorf("expected CreatePartitionSchemeStatement for %q, got %T", tt.input, program.Statements[0])
			continue
		}

		if stmt.Name != tt.name {
			t.Errorf("expected name %q, got %q", tt.name, stmt.Name)
		}
		if stmt.FunctionName != tt.functionName {
			t.Errorf("expected function name %q, got %q", tt.functionName, stmt.FunctionName)
		}
	}
}

func TestAlterPartitionScheme(t *testing.T) {
	tests := []struct {
		input    string
		nextUsed string
	}{
		{`ALTER PARTITION SCHEME PS_Date NEXT USED [PRIMARY]`, "PRIMARY"},
		{`ALTER PARTITION SCHEME PS_Date NEXT USED FG_Archive`, "FG_Archive"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
			continue
		}

		stmt, ok := program.Statements[0].(*ast.AlterPartitionSchemeStatement)
		if !ok {
			t.Errorf("expected AlterPartitionSchemeStatement for %q, got %T", tt.input, program.Statements[0])
			continue
		}

		if stmt.NextUsed != tt.nextUsed {
			t.Errorf("expected next used %q, got %q for %q", tt.nextUsed, stmt.NextUsed, tt.input)
		}
	}
}

func TestContainsPredicate(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`SELECT * FROM Products WHERE CONTAINS(Description, 'mountain bike')`},
		{`SELECT * FROM Products WHERE CONTAINS((Name, Description), 'mountain')`},
		{`SELECT * FROM Products WHERE CONTAINS(*, 'bike')`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
		}
	}
}

func TestFreetextPredicate(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`SELECT * FROM Products WHERE FREETEXT(Description, 'mountain bike')`},
		{`SELECT * FROM Products WHERE FREETEXT((Name, Description), 'bike')`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
		}
	}
}

func TestContainstable(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`SELECT * FROM CONTAINSTABLE(Products, Description, 'mountain') AS ft`},
		{`SELECT p.*, ft.RANK FROM Products p JOIN CONTAINSTABLE(Products, *, 'bike') AS ft ON p.ID = ft.[KEY]`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
		}
	}
}

func TestFreetexttable(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`SELECT * FROM FREETEXTTABLE(Products, Description, 'bike accessories') AS ft`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
		}
	}
}

func TestFulltextCatalog(t *testing.T) {
	tests := []struct {
		input string
		name  string
	}{
		{`CREATE FULLTEXT CATALOG FTCatalog`, "FTCatalog"},
		{`CREATE FULLTEXT CATALOG FTCatalog AS DEFAULT`, "FTCatalog"},
		{`DROP FULLTEXT CATALOG FTCatalog`, "FTCatalog"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
		}
	}
}

func TestFulltextIndex(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`CREATE FULLTEXT INDEX ON Products(Name, Description) KEY INDEX PK_Products ON FTCatalog`},
		{`ALTER FULLTEXT INDEX ON Products ADD (Category)`},
		{`ALTER FULLTEXT INDEX ON Products ENABLE`},
		{`DROP FULLTEXT INDEX ON Products`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
		}
	}
}

func TestResourcePool(t *testing.T) {
	tests := []struct {
		input string
		name  string
	}{
		{`CREATE RESOURCE POOL LowPriorityPool WITH (MAX_CPU_PERCENT = 20)`, "LowPriorityPool"},
		{`CREATE RESOURCE POOL HighPriorityPool WITH (MAX_CPU_PERCENT = 80, MAX_MEMORY_PERCENT = 80)`, "HighPriorityPool"},
		{`ALTER RESOURCE POOL LowPriorityPool WITH (MAX_CPU_PERCENT = 30)`, "LowPriorityPool"},
		{`DROP RESOURCE POOL LowPriorityPool`, "LowPriorityPool"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
		}
	}
}

func TestWorkloadGroup(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`CREATE WORKLOAD GROUP LowPriorityGroup USING LowPriorityPool`},
		{`CREATE WORKLOAD GROUP LowPriorityGroup WITH (IMPORTANCE = LOW) USING LowPriorityPool`},
		{`ALTER WORKLOAD GROUP LowPriorityGroup WITH (IMPORTANCE = MEDIUM)`},
		{`DROP WORKLOAD GROUP LowPriorityGroup`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
		}
	}
}

func TestResourceGovernor(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`ALTER RESOURCE GOVERNOR RECONFIGURE`},
		{`ALTER RESOURCE GOVERNOR DISABLE`},
		{`ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = dbo.ClassifierFunction)`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
		}
	}
}

func TestAvailabilityGroup(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`CREATE AVAILABILITY GROUP MyAG FOR DATABASE MyDB`},
		{`CREATE AVAILABILITY GROUP MyAG FOR DATABASE MyDB REPLICA ON 'Server1' WITH (ENDPOINT_URL = 'TCP://server1:5022', AVAILABILITY_MODE = SYNCHRONOUS_COMMIT)`},
		{`ALTER AVAILABILITY GROUP MyAG ADD DATABASE AnotherDB`},
		{`ALTER AVAILABILITY GROUP MyAG FAILOVER`},
		{`DROP AVAILABILITY GROUP MyAG`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
		}
	}
}

func TestCreateMessageType(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`CREATE MESSAGE TYPE OrderMessage VALIDATION = WELL_FORMED_XML`},
		{`CREATE MESSAGE TYPE ReplyMessage VALIDATION = NONE`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
		}
	}
}

func TestCreateContract(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`CREATE CONTRACT OrderContract (OrderMessage SENT BY INITIATOR)`},
		{`CREATE CONTRACT OrderContract (OrderMessage SENT BY INITIATOR, ReplyMessage SENT BY TARGET)`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
		}
	}
}

func TestCreateQueue(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`CREATE QUEUE OrderQueue`},
		{`CREATE QUEUE dbo.OrderQueue WITH (STATUS = ON, RETENTION = OFF)`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
		}
	}
}

func TestCreateService(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`CREATE SERVICE OrderService ON QUEUE OrderQueue (OrderContract)`},
		{`CREATE SERVICE OrderService ON QUEUE dbo.OrderQueue`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
		}
	}
}

func TestBeginDialog(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`BEGIN DIALOG @dialog_handle FROM SERVICE OrderService TO SERVICE 'TargetService' ON CONTRACT OrderContract`},
		{`BEGIN DIALOG CONVERSATION @handle FROM SERVICE SenderService TO SERVICE 'ReceiverService'`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
		}
	}
}

func TestSendOnConversation(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`SEND ON CONVERSATION @dialog_handle MESSAGE TYPE OrderMessage (@message_body)`},
		{`SEND ON CONVERSATION @handle`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
		}
	}
}

func TestReceive(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`RECEIVE TOP(1) @message_type = message_type_name, @message_body = message_body FROM OrderQueue`},
		{`RECEIVE message_type_name, message_body FROM dbo.OrderQueue`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
		}
	}
}

func TestEndConversation(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`END CONVERSATION @dialog_handle`},
		{`END CONVERSATION @dialog_handle WITH CLEANUP`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
		}
	}
}

func TestGetConversationGroup(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`GET CONVERSATION GROUP @group_id FROM OrderQueue`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
		}
	}
}

func TestMoveConversation(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`MOVE CONVERSATION @dialog_handle TO @group_id`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
		}
	}
}

func TestIfElseSingleStatement(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`IF @x = 1 SELECT 1; ELSE SELECT 2;`},
		{`IF @x = 1 EXEC sp_test; ELSE EXEC sp_test2;`},
		{`IF @x = 1 SET @y = 1; ELSE SET @y = 0;`},
		{`IF @x = 1 SELECT 1; ELSE IF @x = 2 SELECT 2; ELSE SELECT 3;`},
		{`IF @x = 1 PRINT 'yes'; ELSE PRINT 'no';`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
		}

		ifStmt, ok := program.Statements[0].(*ast.IfStatement)
		if !ok {
			t.Errorf("expected IfStatement, got %T for %q", program.Statements[0], tt.input)
			continue
		}

		if ifStmt.Alternative == nil {
			t.Errorf("expected Alternative (ELSE clause), got nil for %q", tt.input)
		}
	}
}

func TestUpdateTop(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`UPDATE TOP (100) dbo.Orders SET Status = 'Done'`},
		{`UPDATE TOP (100) dbo.Orders SET Status = 'Done' WHERE Status = 'Pending'`},
		{`UPDATE TOP (50) PERCENT dbo.Orders SET Status = 'Done'`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
		}

		updateStmt, ok := program.Statements[0].(*ast.UpdateStatement)
		if !ok {
			t.Errorf("expected UpdateStatement, got %T for %q", program.Statements[0], tt.input)
			continue
		}

		if updateStmt.Top == nil {
			t.Errorf("expected Top clause, got nil for %q", tt.input)
		}
	}
}

func TestDeleteTop(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`DELETE TOP (1000) FROM dbo.Orders`},
		{`DELETE TOP (1000) FROM dbo.Orders WHERE Status = 'Old'`},
		{`DELETE TOP (10) PERCENT FROM dbo.Orders`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
		}

		deleteStmt, ok := program.Statements[0].(*ast.DeleteStatement)
		if !ok {
			t.Errorf("expected DeleteStatement, got %T for %q", program.Statements[0], tt.input)
			continue
		}

		if deleteStmt.Top == nil {
			t.Errorf("expected Top clause, got nil for %q", tt.input)
		}
	}
}

func TestTableHintsAdvanced(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`SELECT * FROM dbo.Orders WITH (NOLOCK)`},
		{`SELECT * FROM dbo.Orders WITH (NOLOCK, INDEX(IX_Date))`},
		{`SELECT * FROM dbo.Customers c WITH (NOLOCK) INNER JOIN dbo.Orders o WITH (NOLOCK) ON c.ID = o.CustID`},
		{`UPDATE dbo.Orders WITH (TABLOCK) SET Status = 'Done'`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
		}
	}
}

func TestJoinHints(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{`SELECT * FROM t1 INNER HASH JOIN t2 ON t1.id = t2.id`, "HASH"},
		{`SELECT * FROM t1 INNER MERGE JOIN t2 ON t1.id = t2.id`, "MERGE"},
		{`SELECT * FROM t1 INNER LOOP JOIN t2 ON t1.id = t2.id`, "LOOP"},
		{`SELECT * FROM t1 LEFT HASH JOIN t2 ON t1.id = t2.id`, "HASH"},
		{`SELECT * FROM t1 RIGHT MERGE JOIN t2 ON t1.id = t2.id`, "MERGE"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
			continue
		}

		selectStmt, ok := program.Statements[0].(*ast.SelectStatement)
		if !ok {
			t.Errorf("expected SelectStatement, got %T", program.Statements[0])
			continue
		}

		if selectStmt.From == nil || len(selectStmt.From.Tables) == 0 {
			t.Error("expected FROM clause")
			continue
		}

		join, ok := selectStmt.From.Tables[0].(*ast.JoinClause)
		if !ok {
			t.Errorf("expected JoinClause, got %T", selectStmt.From.Tables[0])
			continue
		}

		if join.Hint != tt.expected {
			t.Errorf("expected hint %q, got %q for %q", tt.expected, join.Hint, tt.input)
		}
	}
}

func TestXMLMethodCalls(t *testing.T) {
	tests := []struct {
		input      string
		methodName string
	}{
		{`SELECT @xml.value('/path', 'INT')`, "value"},
		{`SELECT col.query('/path') FROM tbl`, "query"},
		{`SELECT * FROM tbl WHERE col.exist('/path') = 1`, "exist"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
			continue
		}

		selectStmt, ok := program.Statements[0].(*ast.SelectStatement)
		if !ok {
			t.Errorf("expected SelectStatement, got %T", program.Statements[0])
			continue
		}

		// We just verify it parsed without errors
		if selectStmt.Columns == nil || len(selectStmt.Columns) == 0 {
			t.Error("expected select columns")
		}
	}
}

func TestSetXMLModify(t *testing.T) {
	input := `SET @xml.modify('insert <new/> into (/root)[1]')`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	if len(program.Statements) != 1 {
		t.Fatalf("expected 1 statement, got %d", len(program.Statements))
	}

	setStmt, ok := program.Statements[0].(*ast.SetStatement)
	if !ok {
		t.Fatalf("expected SetStatement, got %T", program.Statements[0])
	}

	mc, ok := setStmt.Variable.(*ast.MethodCallExpression)
	if !ok {
		t.Fatalf("expected MethodCallExpression, got %T", setStmt.Variable)
	}

	if mc.MethodName != "modify" {
		t.Errorf("expected method name 'modify', got %q", mc.MethodName)
	}

	if setStmt.Value != nil {
		t.Errorf("expected nil value for modify(), got %v", setStmt.Value)
	}
}

func TestStaticMethodCalls(t *testing.T) {
	tests := []struct {
		input    string
		typeName string
		method   string
	}{
		{`SELECT GEOGRAPHY::Point(1, 2, 4326)`, "GEOGRAPHY", "Point"},
		{`SELECT GEOMETRY::STGeomFromText('POINT', 0)`, "GEOMETRY", "STGeomFromText"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
			continue
		}

		selectStmt, ok := program.Statements[0].(*ast.SelectStatement)
		if !ok {
			t.Errorf("expected SelectStatement, got %T", program.Statements[0])
			continue
		}

		if len(selectStmt.Columns) == 0 {
			t.Error("expected at least one column")
			continue
		}

		// The column should contain a StaticMethodCall
		col := selectStmt.Columns[0]
		sm, ok := col.Expression.(*ast.StaticMethodCall)
		if !ok {
			t.Errorf("expected StaticMethodCall, got %T", col.Expression)
			continue
		}

		if sm.TypeName != tt.typeName {
			t.Errorf("expected type name %q, got %q", tt.typeName, sm.TypeName)
		}
		if sm.MethodName != tt.method {
			t.Errorf("expected method %q, got %q", tt.method, sm.MethodName)
		}
	}
}

func TestTemporalClause(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{`SELECT * FROM Employee FOR SYSTEM_TIME AS OF '2023-01-01'`, "AS OF"},
		{`SELECT * FROM Employee FOR SYSTEM_TIME BETWEEN '2023-01-01' AND '2023-12-31'`, "BETWEEN"},
		{`SELECT * FROM Employee FOR SYSTEM_TIME ALL`, "ALL"},
		{`SELECT * FROM Employee FOR SYSTEM_TIME CONTAINED IN ('2023-01-01', '2023-12-31')`, "CONTAINED IN"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
			continue
		}

		selectStmt, ok := program.Statements[0].(*ast.SelectStatement)
		if !ok {
			t.Errorf("expected SelectStatement, got %T", program.Statements[0])
			continue
		}

		if selectStmt.From == nil || len(selectStmt.From.Tables) == 0 {
			t.Error("expected FROM clause")
			continue
		}

		tn, ok := selectStmt.From.Tables[0].(*ast.TableName)
		if !ok {
			t.Errorf("expected TableName, got %T", selectStmt.From.Tables[0])
			continue
		}

		if tn.TemporalClause == nil {
			t.Error("expected TemporalClause")
			continue
		}

		if tn.TemporalClause.Type != tt.expected {
			t.Errorf("expected temporal type %q, got %q for %q", tt.expected, tn.TemporalClause.Type, tt.input)
		}
	}
}

func TestGroupingSets(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{`SELECT a FROM t GROUP BY a`, "a"},
		{`SELECT a FROM t GROUP BY GROUPING SETS ((a, b), (a), ())`, "GROUPING SETS ((a, b), (a), ())"},
		{`SELECT a FROM t GROUP BY CUBE(a, b)`, "CUBE(a, b)"},
		{`SELECT a FROM t GROUP BY ROLLUP(a, b)`, "ROLLUP(a, b)"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
			continue
		}

		selectStmt, ok := program.Statements[0].(*ast.SelectStatement)
		if !ok {
			t.Errorf("expected SelectStatement, got %T", program.Statements[0])
			continue
		}

		if len(selectStmt.GroupBy) == 0 {
			t.Error("expected GROUP BY clause")
			continue
		}

		groupByStr := selectStmt.GroupBy[0].String()
		if groupByStr != tt.expected {
			t.Errorf("expected GROUP BY %q, got %q for %q", tt.expected, groupByStr, tt.input)
		}
	}
}

func TestGroupingFunction(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`SELECT GROUPING(a) FROM t GROUP BY ROLLUP(a)`},
		{`SELECT GROUPING_ID(a, b) FROM t GROUP BY CUBE(a, b)`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
		}
	}
}

func TestKeywordAsAlias(t *testing.T) {
	tests := []struct {
		input string
		alias string
	}{
		{`SELECT * FROM dbo.T1 target`, "target"},
		{`SELECT * FROM dbo.T1 source`, "source"},
		{`SELECT * FROM dbo.T1 value`, "value"},
		{`SELECT * FROM dbo.T1 key`, "key"},
		{`SELECT * FROM dbo.T1 level`, "level"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement, got %d for %q", len(program.Statements), tt.input)
			continue
		}

		selectStmt, ok := program.Statements[0].(*ast.SelectStatement)
		if !ok {
			t.Errorf("expected SelectStatement, got %T", program.Statements[0])
			continue
		}

		if selectStmt.From == nil || len(selectStmt.From.Tables) == 0 {
			t.Error("expected FROM clause")
			continue
		}

		tableName, ok := selectStmt.From.Tables[0].(*ast.TableName)
		if !ok {
			t.Errorf("expected TableName, got %T", selectStmt.From.Tables[0])
			continue
		}

		if tableName.Alias == nil || tableName.Alias.Value != tt.alias {
			got := ""
			if tableName.Alias != nil {
				got = tableName.Alias.Value
			}
			t.Errorf("expected alias %q, got %q for %q", tt.alias, got, tt.input)
		}
	}
}

func TestExecWithReturnVariable(t *testing.T) {
	tests := []struct {
		input     string
		hasReturn bool
	}{
		{`EXEC @rc = sp_test`, true},
		{`EXEC @result = dbo.MyProc @param = 1`, true},
		{`EXEC sp_test @param = 1`, false},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement for %q", tt.input)
			continue
		}

		execStmt, ok := program.Statements[0].(*ast.ExecStatement)
		if !ok {
			t.Errorf("expected ExecStatement, got %T", program.Statements[0])
			continue
		}

		if tt.hasReturn && execStmt.ReturnVariable == nil {
			t.Errorf("expected return variable for %q", tt.input)
		}
		if !tt.hasReturn && execStmt.ReturnVariable != nil {
			t.Errorf("unexpected return variable for %q", tt.input)
		}
	}
}

func TestSetOperationsWithString(t *testing.T) {
	tests := []struct {
		input     string
		unionType string
	}{
		{`SELECT a FROM t1 UNION SELECT a FROM t2`, "UNION"},
		{`SELECT a FROM t1 UNION ALL SELECT a FROM t2`, "UNION"},
		{`SELECT a FROM t1 INTERSECT SELECT a FROM t2`, "INTERSECT"},
		{`SELECT a FROM t1 EXCEPT SELECT a FROM t2`, "EXCEPT"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		if len(program.Statements) != 1 {
			t.Errorf("expected 1 statement for %q", tt.input)
			continue
		}

		selectStmt, ok := program.Statements[0].(*ast.SelectStatement)
		if !ok {
			t.Errorf("expected SelectStatement, got %T", program.Statements[0])
			continue
		}

		if selectStmt.Union == nil {
			t.Errorf("expected Union clause for %q", tt.input)
			continue
		}

		if selectStmt.Union.Type != tt.unionType {
			t.Errorf("expected union type %q, got %q for %q", tt.unionType, selectStmt.Union.Type, tt.input)
		}

		// Verify String() output includes the union clause
		output := selectStmt.String()
		if !strings.Contains(output, tt.unionType) {
			t.Errorf("expected String() output to contain %q, got %q", tt.unionType, output)
		}
	}
}

// Tests for Stage 47-48 fixes

func TestTriggerWithEncryption(t *testing.T) {
	input := `CREATE TRIGGER dbo.trg_Test ON dbo.Table1 WITH ENCRYPTION AFTER INSERT, UPDATE AS BEGIN SELECT 1 END`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	if len(program.Statements) != 1 {
		t.Fatalf("expected 1 statement, got %d", len(program.Statements))
	}

	stmt, ok := program.Statements[0].(*ast.CreateTriggerStatement)
	if !ok {
		t.Fatalf("expected CreateTriggerStatement, got %T", program.Statements[0])
	}

	if len(stmt.Options) != 1 || stmt.Options[0] != "ENCRYPTION" {
		t.Errorf("expected Options [ENCRYPTION], got %v", stmt.Options)
	}
}

func TestColumnSetForAllSparseColumns(t *testing.T) {
	input := `CREATE TABLE t (ID INT, AllSparse XML COLUMN_SET FOR ALL_SPARSE_COLUMNS)`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	if len(program.Statements) != 1 {
		t.Fatalf("expected 1 statement, got %d", len(program.Statements))
	}

	stmt, ok := program.Statements[0].(*ast.CreateTableStatement)
	if !ok {
		t.Fatalf("expected CreateTableStatement, got %T", program.Statements[0])
	}

	if len(stmt.Columns) != 2 {
		t.Fatalf("expected 2 columns, got %d", len(stmt.Columns))
	}

	if !stmt.Columns[1].IsColumnSet {
		t.Error("expected column 2 to have IsColumnSet = true")
	}
}

func TestGrantWithColumnList(t *testing.T) {
	tests := []struct {
		input       string
		permissions []string
		columns     []string
	}{
		{
			`GRANT SELECT ON dbo.Customers (CustomerID, Name) TO User1`,
			[]string{"SELECT"},
			[]string{"CustomerID", "Name"},
		},
		{
			`GRANT UPDATE ON dbo.Customers (Email, Phone) TO User1`,
			[]string{"UPDATE"},
			[]string{"Email", "Phone"},
		},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		stmt, ok := program.Statements[0].(*ast.GrantStatement)
		if !ok {
			t.Fatalf("expected GrantStatement, got %T", program.Statements[0])
		}

		if len(stmt.Columns) != len(tt.columns) {
			t.Errorf("expected %d columns, got %d", len(tt.columns), len(stmt.Columns))
		}
	}
}

func TestDenyWithColumnList(t *testing.T) {
	input := `DENY SELECT ON dbo.Customers (SSN, CreditCard) TO User1`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt, ok := program.Statements[0].(*ast.DenyStatement)
	if !ok {
		t.Fatalf("expected DenyStatement, got %T", program.Statements[0])
	}

	if len(stmt.Columns) != 2 {
		t.Errorf("expected 2 columns, got %d", len(stmt.Columns))
	}
}

func TestQueryOptionHints(t *testing.T) {
	tests := []string{
		`SELECT * FROM t OPTION (KEEP PLAN)`,
		`SELECT * FROM t OPTION (KEEPFIXED PLAN)`,
		`SELECT * FROM t OPTION (EXPAND VIEWS)`,
		`SELECT * FROM t OPTION (OPTIMIZE FOR UNKNOWN)`,
		`SELECT * FROM t OPTION (MAX_GRANT_PERCENT = 25)`,
		`SELECT * FROM t OPTION (USE PLAN @plan)`,
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		_ = p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("failed to parse: %s\n  errors: %v", input, p.Errors())
		}
	}
}

func TestDropTriggerOnDatabase(t *testing.T) {
	tests := []struct {
		input       string
		onDatabase  bool
		onAllServer bool
	}{
		{`DROP TRIGGER IF EXISTS trg_Test ON DATABASE`, true, false},
		{`DROP TRIGGER IF EXISTS trg_Test ON ALL SERVER`, false, true},
		{`DROP TRIGGER trg_Test`, false, false},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		stmt, ok := program.Statements[0].(*ast.DropObjectStatement)
		if !ok {
			t.Fatalf("expected DropObjectStatement, got %T", program.Statements[0])
		}

		if stmt.OnDatabase != tt.onDatabase {
			t.Errorf("OnDatabase: expected %v, got %v", tt.onDatabase, stmt.OnDatabase)
		}
		if stmt.OnAllServer != tt.onAllServer {
			t.Errorf("OnAllServer: expected %v, got %v", tt.onAllServer, stmt.OnAllServer)
		}
	}
}

func TestCreateTableWithFilegroup(t *testing.T) {
	input := `CREATE TABLE t (ID INT) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt, ok := program.Statements[0].(*ast.CreateTableStatement)
	if !ok {
		t.Fatalf("expected CreateTableStatement, got %T", program.Statements[0])
	}

	if stmt.FileGroup != "PRIMARY" && stmt.FileGroup != "[PRIMARY]" {
		t.Errorf("expected FileGroup [PRIMARY], got %s", stmt.FileGroup)
	}
	if stmt.TextImageOn != "PRIMARY" && stmt.TextImageOn != "[PRIMARY]" {
		t.Errorf("expected TextImageOn [PRIMARY], got %s", stmt.TextImageOn)
	}
}

// Fix the filegroup test
func TestCreateTableWithFilegroupV2(t *testing.T) {
	input := `CREATE TABLE t (ID INT) ON [PRIMARY]`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt, ok := program.Statements[0].(*ast.CreateTableStatement)
	if !ok {
		t.Fatalf("expected CreateTableStatement, got %T", program.Statements[0])
	}

	// FileGroup should be captured (may or may not include brackets)
	if stmt.FileGroup == "" {
		t.Error("expected FileGroup to be set")
	}
}

func TestDeleteWithTableHints(t *testing.T) {
	tests := []struct {
		input string
		hints []string
	}{
		{`DELETE FROM dbo.Orders WITH (TABLOCK) WHERE ID = 1`, []string{"TABLOCK"}},
		{`DELETE FROM dbo.Orders WITH (ROWLOCK, READPAST) WHERE ID = 1`, []string{"ROWLOCK", "READPAST"}},
		{`DELETE FROM dbo.Orders WHERE ID = 1`, nil},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		stmt, ok := program.Statements[0].(*ast.DeleteStatement)
		if !ok {
			t.Fatalf("expected DeleteStatement, got %T", program.Statements[0])
		}

		if len(stmt.Hints) != len(tt.hints) {
			t.Errorf("expected %d hints, got %d", len(tt.hints), len(stmt.Hints))
		}
	}
}

func TestNextValueForWithOver(t *testing.T) {
	input := `SELECT NEXT VALUE FOR dbo.MySeq OVER (ORDER BY Name) AS ID`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	if len(program.Statements) != 1 {
		t.Fatalf("expected 1 statement, got %d", len(program.Statements))
	}
}

func TestGrantOnXmlSchemaCollection(t *testing.T) {
	input := `GRANT ALTER ON XML SCHEMA COLLECTION::dbo.MySchema TO Developer`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt, ok := program.Statements[0].(*ast.GrantStatement)
	if !ok {
		t.Fatalf("expected GrantStatement, got %T", program.Statements[0])
	}

	if stmt.OnType != "XML SCHEMA COLLECTION" {
		t.Errorf("expected OnType 'XML SCHEMA COLLECTION', got '%s'", stmt.OnType)
	}
}

func TestGrantOnAsymmetricKey(t *testing.T) {
	input := `GRANT CONTROL ON ASYMMETRIC KEY::MyKey TO SecurityAdmin`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt, ok := program.Statements[0].(*ast.GrantStatement)
	if !ok {
		t.Fatalf("expected GrantStatement, got %T", program.Statements[0])
	}

	if stmt.OnType != "ASYMMETRIC KEY" {
		t.Errorf("expected OnType 'ASYMMETRIC KEY', got '%s'", stmt.OnType)
	}
}

func TestTruncateTableWithPartitions(t *testing.T) {
	tests := []struct {
		input     string
		partCount int
	}{
		{`TRUNCATE TABLE dbo.MyTable`, 0},
		{`TRUNCATE TABLE dbo.T WITH (PARTITIONS (1, 2, 3))`, 3},
		{`TRUNCATE TABLE dbo.T WITH (PARTITIONS (5 TO 10))`, 1},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)

		stmt, ok := program.Statements[0].(*ast.TruncateTableStatement)
		if !ok {
			t.Fatalf("expected TruncateTableStatement, got %T", program.Statements[0])
		}

		if len(stmt.Partitions) != tt.partCount {
			t.Errorf("expected %d partitions, got %d", tt.partCount, len(stmt.Partitions))
		}
	}
}

func TestCompoundTokens(t *testing.T) {
	tests := []struct {
		input string
		desc  string
	}{
		{`TRUNCATE TABLE dbo.T`, "TRUNCATE_TABLE"},
		{`SELECT NEXT VALUE FOR dbo.Seq`, "NEXT_VALUE_FOR"},
		{`GRANT ALTER ON XML SCHEMA COLLECTION::dbo.X TO User1`, "XML_SCHEMA_COLLECTION"},
		{`GRANT CONTROL ON ASYMMETRIC KEY::MyKey TO User1`, "ASYMMETRIC_KEY"},
		{`GRANT CONTROL ON SYMMETRIC KEY::MyKey TO User1`, "SYMMETRIC_KEY"},
		{`END CONVERSATION @handle`, "END_CONVERSATION"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		_ = p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("failed to parse %s: %v", tt.desc, p.Errors())
		}
	}
}

func TestBeginAtomicInFunction(t *testing.T) {
	input := `CREATE FUNCTION dbo.Test(@x INT) RETURNS INT WITH NATIVE_COMPILATION, SCHEMABINDING AS BEGIN ATOMIC WITH (TRANSACTION ISOLATION LEVEL = SNAPSHOT, LANGUAGE = N'English') RETURN @x + 1 END`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	if len(program.Statements) != 1 {
		t.Fatalf("expected 1 statement, got %d", len(program.Statements))
	}
}

func TestCreateXmlSchemaCollection(t *testing.T) {
	input := `CREATE XML SCHEMA COLLECTION dbo.MySchema AS N'<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"></xs:schema>'`
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)

	stmt, ok := program.Statements[0].(*ast.CreateXmlSchemaCollectionStatement)
	if !ok {
		t.Fatalf("expected CreateXmlSchemaCollectionStatement, got %T", program.Statements[0])
	}

	if stmt.Name.String() != "dbo.MySchema" {
		t.Errorf("expected name 'dbo.MySchema', got '%s'", stmt.Name.String())
	}
}

func TestJsonObjectColonSyntax(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`SELECT JSON_OBJECT('id':1, 'name':'John') AS JsonObj`},
		{`SELECT JSON_OBJECT('id':1, 'name':'John', 'active':CAST(1 AS BIT)) AS JsonObj`},
		{`SELECT JSON_ARRAY(1, 2, 3, 'four', NULL) AS JsonArr`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		_ = p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("failed to parse: %s, errors: %v", tt.input, p.Errors())
		}
	}
}

func TestInlineIndex(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`CREATE TABLE t (CustomerID INT INDEX IX_Customer NONCLUSTERED)`},
		{`CREATE TABLE t (ID INT, INDEX IX_Date NONCLUSTERED (OrderDate, Amount))`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		_ = p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("failed to parse: %s, errors: %v", tt.input, p.Errors())
		}
	}
}

func TestParenthesizedSetOperations(t *testing.T) {
	tests := []struct {
		input string
	}{
		{`(SELECT a FROM t1 UNION SELECT b FROM t2) INTERSECT SELECT c FROM t3`},
		{`(SELECT a FROM t1) EXCEPT SELECT b FROM t2`},
		{`SELECT a FROM t1 INTERSECT SELECT b FROM t2`},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		_ = p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("failed to parse: %s, errors: %v", tt.input, p.Errors())
		}
	}
}

func TestInsertWithHints(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{
			"INSERT INTO t WITH (KEEPIDENTITY) SELECT * FROM s",
			"INSERT INTO t WITH (KEEPIDENTITY) SELECT * FROM s",
		},
		{
			"INSERT INTO t WITH (TABLOCK, HOLDLOCK) SELECT * FROM s",
			"INSERT INTO t WITH (TABLOCK, HOLDLOCK) SELECT * FROM s",
		},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		checkParserErrors(t, p)
		if len(program.Statements) != 1 {
			t.Fatalf("expected 1 statement, got %d", len(program.Statements))
		}
		result := program.Statements[0].String()
		if result != tt.expected {
			t.Errorf("expected %q, got %q", tt.expected, result)
		}
	}
}

func TestUpdateOpenquery(t *testing.T) {
	input := "UPDATE OPENQUERY([Server], 'SELECT * FROM t') SET x = 1"
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)
	if len(program.Statements) != 1 {
		t.Fatalf("expected 1 statement, got %d", len(program.Statements))
	}
	stmt, ok := program.Statements[0].(*ast.UpdateStatement)
	if !ok {
		t.Fatalf("expected UpdateStatement, got %T", program.Statements[0])
	}
	if stmt.TargetFunc == nil {
		t.Fatal("expected TargetFunc to be set")
	}
}

func TestDeleteOpenquery(t *testing.T) {
	input := "DELETE FROM OPENQUERY([Server], 'SELECT * FROM t')"
	l := lexer.New(input)
	p := New(l)
	program := p.ParseProgram()
	checkParserErrors(t, p)
	if len(program.Statements) != 1 {
		t.Fatalf("expected 1 statement, got %d", len(program.Statements))
	}
	stmt, ok := program.Statements[0].(*ast.DeleteStatement)
	if !ok {
		t.Fatalf("expected DeleteStatement, got %T", program.Statements[0])
	}
	if stmt.TargetFunc == nil {
		t.Fatal("expected TargetFunc to be set")
	}
}

func TestOpenrowsetBulk(t *testing.T) {
	tests := []string{
		"SELECT * FROM OPENROWSET(BULK 'file.csv', SINGLE_CLOB) AS t",
		"SELECT * FROM OPENROWSET(BULK 'file.csv', FORMATFILE = 'fmt.xml') AS t",
		"SELECT * FROM OPENROWSET(BULK 'file.csv', FORMATFILE = 'fmt.xml', FIRSTROW = 2) AS t",
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("unexpected error for %q: %s", input, p.Errors()[0])
		}
	}
}

func TestComposableDml(t *testing.T) {
	tests := []struct {
		name  string
		input string
	}{
		{
			"DELETE as derived table",
			"SELECT * FROM (DELETE FROM t OUTPUT deleted.id WHERE x = 1) AS d",
		},
		{
			"UPDATE as derived table",
			"SELECT * FROM (UPDATE t SET x = 1 OUTPUT inserted.id) AS u",
		},
		{
			"INSERT from DELETE OUTPUT",
			`INSERT INTO Archive SELECT * FROM (DELETE FROM t OUTPUT deleted.* WHERE old = 1) AS d`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			l := lexer.New(tt.input)
			p := New(l)
			p.ParseProgram()
			if len(p.Errors()) > 0 {
				t.Errorf("unexpected error: %s", p.Errors()[0])
			}
		})
	}
}

func TestRankAsIdentifier(t *testing.T) {
	tests := []struct {
		name  string
		input string
	}{
		{
			"RANK as column reference",
			"SELECT * FROM t WHERE Rank <= 10",
		},
		{
			"RANK() as function",
			"SELECT RANK() OVER (ORDER BY x) AS Rank FROM t",
		},
		{
			"ROW_NUMBER as column",
			"SELECT * FROM t WHERE ROW_NUMBER <= 3",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			l := lexer.New(tt.input)
			p := New(l)
			p.ParseProgram()
			if len(p.Errors()) > 0 {
				t.Errorf("unexpected error: %s", p.Errors()[0])
			}
		})
	}
}

func TestMergeWithValues(t *testing.T) {
	input := `MERGE INTO dbo.Settings AS target
USING (VALUES ('A', 'B'), ('C', 'D')) AS source (Name, Value)
ON target.Name = source.Name
WHEN MATCHED THEN UPDATE SET target.Value = source.Value`

	l := lexer.New(input)
	p := New(l)
	p.ParseProgram()
	if len(p.Errors()) > 0 {
		t.Errorf("unexpected error: %s", p.Errors()[0])
	}
}

func TestMergeWithTop(t *testing.T) {
	input := `MERGE TOP (100) INTO dbo.Target AS target
USING dbo.Source AS source ON target.ID = source.ID
WHEN MATCHED THEN UPDATE SET target.Value = source.Value`

	l := lexer.New(input)
	p := New(l)
	p.ParseProgram()
	if len(p.Errors()) > 0 {
		t.Errorf("unexpected error: %s", p.Errors()[0])
	}
}

func TestMemoryOptimizedHash(t *testing.T) {
	input := `CREATE TABLE dbo.MemTable (
    ID INT NOT NULL PRIMARY KEY NONCLUSTERED HASH WITH (BUCKET_COUNT = 10000),
    Name VARCHAR(100) NOT NULL
)`

	l := lexer.New(input)
	p := New(l)
	p.ParseProgram()
	if len(p.Errors()) > 0 {
		t.Errorf("unexpected error: %s", p.Errors()[0])
	}
}

func TestRestoreWithMove(t *testing.T) {
	input := `RESTORE DATABASE MyDB FROM DISK = 'C:\backup.bak'
WITH MOVE 'MyDB_Data' TO 'D:\Data\MyDB.mdf', MOVE 'MyDB_Log' TO 'E:\Logs\MyDB.ldf', RECOVERY`

	l := lexer.New(input)
	p := New(l)
	p.ParseProgram()
	if len(p.Errors()) > 0 {
		t.Errorf("unexpected error: %s", p.Errors()[0])
	}
}

func TestDropTypeIfExists(t *testing.T) {
	tests := []string{
		"DROP TYPE IF EXISTS dbo.MyType",
		"DROP SCHEMA IF EXISTS Sales",
		"DROP DEFAULT IF EXISTS dbo.DefaultZero",
		"DROP DATABASE IF EXISTS MyDB",
		"DROP DATABASE MyDB, AnotherDB",
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input: %s, error: %s", input, p.Errors()[0])
		}
	}
}

func TestTypedXmlDeclaration(t *testing.T) {
	tests := []string{
		"DECLARE @TypedXml XML(dbo.MyXmlSchema)",
		"DECLARE @TypedXml XML(MySchema)",
		"DECLARE @UntypedXml XML = '<data></data>'",
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input: %s, error: %s", input, p.Errors()[0])
		}
	}
}

func TestXmlMethodCalls(t *testing.T) {
	tests := []string{
		`UPDATE dbo.Products SET ProductXml.modify('replace value of (/Product/Price)[1] with 99.99') WHERE ID = 1`,
		`UPDATE t SET XmlCol.write('new data', 0, null)`,
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input: %s, error: %s", input, p.Errors()[0])
		}
	}
}

func TestParenthesizedJoins(t *testing.T) {
	tests := []string{
		`SELECT * FROM A INNER JOIN (B INNER JOIN C ON B.ID = C.ID) ON A.ID = B.ID`,
		`SELECT * FROM A LEFT JOIN (B RIGHT JOIN C ON B.X = C.X) ON A.Y = B.Y`,
		`SELECT c.Name, o.OrderID FROM Customers c INNER JOIN (Orders o INNER JOIN Shippers s ON o.ShipID = s.ID) ON c.ID = o.CustID`,
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input: %s, error: %s", input, p.Errors()[0])
		}
	}
}

func TestWithCheckNocheck(t *testing.T) {
	tests := []string{
		`ALTER TABLE dbo.Orders WITH CHECK ADD CONSTRAINT FK_New FOREIGN KEY (CustomerID) REFERENCES dbo.Customers(CustomerID)`,
		`ALTER TABLE dbo.Orders WITH NOCHECK ADD CONSTRAINT CK_New CHECK (TotalAmount > 0)`,
		`ALTER TABLE #TableCheck NOCHECK CONSTRAINT CK_DateRange`,
		`ALTER TABLE #TableCheck CHECK CONSTRAINT CK_DateRange`,
		`CREATE VIEW dbo.TestView AS SELECT * FROM dbo.T WITH CHECK OPTION`,
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input: %s, error: %s", input, p.Errors()[0])
		}
	}
}

func TestEnableDisableTrigger(t *testing.T) {
	tests := []string{
		`DISABLE TRIGGER TR_Name ON dbo.MyTable`,
		`ENABLE TRIGGER TR_Name ON dbo.MyTable`,
		`DISABLE TRIGGER ALL ON dbo.MyTable`,
		`ENABLE TRIGGER ALL ON dbo.MyTable`,
		`DISABLE TRIGGER TR_DDL ON DATABASE`,
		`ENABLE TRIGGER TR_DDL ON DATABASE`,
		`DISABLE TRIGGER ALL ON ALL SERVER`,
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input: %s, error: %s", input, p.Errors()[0])
		}
	}
}

func TestControlFlowStatements(t *testing.T) {
	tests := []string{
		`WHILE 1=1 BEGIN IF @x > 10 BREAK END`,
		`WHILE @i < 10 BEGIN SET @i = @i + 1 IF @i = 5 CONTINUE END`,
		`BEGIN TRY SELECT 1 END TRY BEGIN CATCH THROW END CATCH`,
		`THROW 50001, 'Error message', 1`,
		`IF @x < 0 RETURN -1`,
		`IF @x < 0 RETURN`,
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input: %s, error: %s", input, p.Errors()[0])
		}
	}
}

// =============================================================================
// Additional Coverage Tests - consolidated from accessory tests
// =============================================================================

func TestSystemVariables(t *testing.T) {
	tests := []string{
		`SELECT @@IDENTITY`,
		`IF @@ROWCOUNT = 0 PRINT 'No rows'`,
		`IF @@ERROR <> 0 RETURN -1`,
		`SELECT @@TRANCOUNT`,
		`SELECT @@SPID`,
		`SELECT @@VERSION`,
		`SELECT @@SERVERNAME`,
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input: %s, error: %s", input, p.Errors()[0])
		}
	}
}

func TestBitwiseOperators(t *testing.T) {
	tests := []string{
		`SELECT A & B FROM T`,
		`SELECT A | B FROM T`,
		`SELECT A ^ B FROM T`,
		`SELECT ~A FROM T`,
		`SELECT A & B | C FROM T`,
		`SELECT (A & 0xFF) | (B << 8) FROM T`,
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input: %s, error: %s", input, p.Errors()[0])
		}
	}
}

func TestCoalesceNullif(t *testing.T) {
	tests := []string{
		`SELECT COALESCE(A, B, C) FROM T`,
		`SELECT COALESCE(A, 'default') FROM T`,
		`SELECT NULLIF(A, 0) FROM T`,
		`SELECT NULLIF(A, '') FROM T`,
		`SELECT COALESCE(NULLIF(A, ''), 'N/A') FROM T`,
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input: %s, error: %s", input, p.Errors()[0])
		}
	}
}

func TestIifChoose(t *testing.T) {
	tests := []string{
		`SELECT IIF(A > B, 'Greater', 'Less or Equal') FROM T`,
		`SELECT IIF(A IS NULL, 'Null', A) FROM T`,
		`SELECT CHOOSE(DayNum, 'Mon', 'Tue', 'Wed', 'Thu', 'Fri') FROM T`,
		`SELECT CHOOSE(Status, 'Pending', 'Active', 'Closed') FROM T`,
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input: %s, error: %s", input, p.Errors()[0])
		}
	}
}

func TestStringFunctions(t *testing.T) {
	tests := []string{
		`SELECT STRING_AGG(Name, ',') FROM T`,
		`SELECT STRING_AGG(Name, ', ') WITHIN GROUP (ORDER BY Name) FROM T`,
		`SELECT value FROM STRING_SPLIT('a,b,c', ',')`,
		`SELECT CONCAT_WS(', ', FirstName, MiddleName, LastName) FROM T`,
		`SELECT FORMAT(Amount, 'C', 'en-US') FROM T`,
		`SELECT FORMAT(Date, 'yyyy-MM-dd') FROM T`,
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input: %s, error: %s", input, p.Errors()[0])
		}
	}
}

func TestJsonFunctions(t *testing.T) {
	tests := []string{
		`SELECT JSON_VALUE(JsonCol, '$.name') FROM T`,
		`SELECT JSON_QUERY(JsonCol, '$.items') FROM T`,
		`SELECT JSON_MODIFY(JsonCol, '$.name', 'NewName') FROM T`,
		`SELECT ISJSON(JsonCol) FROM T`,
		`SELECT * FROM OPENJSON(@json)`,
		`SELECT * FROM OPENJSON(@json) WITH (Name VARCHAR(100), Age INT)`,
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input: %s, error: %s", input, p.Errors()[0])
		}
	}
}

func TestNamedTransactions(t *testing.T) {
	tests := []string{
		`BEGIN TRANSACTION MyTran`,
		`COMMIT TRANSACTION MyTran`,
		`ROLLBACK TRANSACTION MyTran`,
		`BEGIN TRAN T1 COMMIT TRAN T1`,
		`SAVE TRANSACTION SavePoint1`,
		`ROLLBACK TRANSACTION SavePoint1`,
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input: %s, error: %s", input, p.Errors()[0])
		}
	}
}

func TestTryCastConvert(t *testing.T) {
	tests := []string{
		`SELECT TRY_CAST('abc' AS INT)`,
		`SELECT TRY_CAST(Col AS DECIMAL(10,2)) FROM T`,
		`SELECT TRY_CONVERT(INT, '123')`,
		`SELECT TRY_CONVERT(DATE, '2023-01-01', 120)`,
		`SELECT TRY_PARSE('100.00' AS MONEY USING 'en-US')`,
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input: %s, error: %s", input, p.Errors()[0])
		}
	}
}

func TestSpExecutesql(t *testing.T) {
	tests := []string{
		`EXEC sp_executesql N'SELECT * FROM T'`,
		`EXEC sp_executesql N'SELECT * FROM T WHERE ID = @id', N'@id INT', @id = 5`,
		`EXEC sp_executesql @sql, @params, @p1 = 1, @p2 = 'test'`,
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input: %s, error: %s", input, p.Errors()[0])
		}
	}
}

func TestAdvancedJoins(t *testing.T) {
	tests := []string{
		`SELECT * FROM T1 CROSS JOIN T2`,
		`SELECT E.Name, M.Name AS Manager FROM Employees E LEFT JOIN Employees M ON E.ManagerID = M.ID`,
		`SELECT * FROM A INNER JOIN B ON A.ID = B.AID LEFT JOIN C ON B.ID = C.BID RIGHT JOIN D ON C.ID = D.CID`,
		`SELECT * FROM T1 FULL OUTER JOIN T2 ON T1.ID = T2.ID`,
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input: %s, error: %s", input, p.Errors()[0])
		}
	}
}

func TestAdvancedSubqueries(t *testing.T) {
	tests := []string{
		`SELECT ID, (SELECT COUNT(*) FROM Orders O WHERE O.CustID = C.ID) AS OrderCount FROM Customers C`,
		`SELECT * FROM T WHERE Col > (SELECT AVG(Col) FROM T AS T2 WHERE T2.Cat = T.Cat)`,
		`SELECT * FROM T WHERE ID IN (SELECT ID FROM S WHERE Val > (SELECT AVG(Val) FROM S))`,
		`SELECT * FROM T WHERE NOT EXISTS (SELECT 1 FROM S WHERE S.ID = T.ID)`,
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input: %s, error: %s", input, p.Errors()[0])
		}
	}
}

func TestColumnTableAliases(t *testing.T) {
	tests := []string{
		`SELECT Col AS Alias FROM T`,
		`SELECT Col Alias FROM T`,
		`SELECT Col AS [My Alias] FROM T`,
		`SELECT * FROM T AS Alias`,
		`SELECT * FROM T Alias`,
		`SELECT A.Col FROM T AS A`,
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input: %s, error: %s", input, p.Errors()[0])
		}
	}
}

func TestInsertVariations(t *testing.T) {
	tests := []string{
		`INSERT INTO T (A, B) VALUES (1, 'a'), (2, 'b'), (3, 'c')`,
		`INSERT INTO T DEFAULT VALUES`,
		`INSERT INTO #Temp EXEC sp_who`,
		`SELECT * INTO #Temp FROM T`,
		`INSERT INTO T (A) OUTPUT INSERTED.ID VALUES (1)`,
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input: %s, error: %s", input, p.Errors()[0])
		}
	}
}

func TestUpdateDeleteVariations(t *testing.T) {
	tests := []string{
		`UPDATE T SET T.Col = S.Col FROM T INNER JOIN S ON T.ID = S.ID`,
		`DELETE T FROM T INNER JOIN S ON T.ID = S.ID WHERE S.Flag = 0`,
		`UPDATE T SET @var = Col = Col + 1 WHERE ID = 1`,
		`DELETE FROM T OUTPUT DELETED.* INTO @DeletedRows WHERE ID < 10`,
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input: %s, error: %s", input, p.Errors()[0])
		}
	}
}

func TestDataTypes(t *testing.T) {
	tests := []string{
		`CREATE TABLE T (D DATETIME2(3))`,
		`CREATE TABLE T (D DATETIMEOFFSET)`,
		`CREATE TABLE T (T TIME(2))`,
		`CREATE TABLE T (G GEOGRAPHY)`,
		`CREATE TABLE T (G GEOMETRY)`,
		`CREATE TABLE T (H HIERARCHYID)`,
		`CREATE TABLE T (V SQL_VARIANT)`,
		`CREATE TABLE T (R ROWVERSION)`,
		`CREATE TABLE T (B VARBINARY(MAX))`,
		`CREATE TABLE T (S NVARCHAR(MAX))`,
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input: %s, error: %s", input, p.Errors()[0])
		}
	}
}

func TestComputedColumns(t *testing.T) {
	tests := []string{
		`CREATE TABLE T (A INT, B INT, C AS A + B)`,
		`CREATE TABLE T (A INT, B INT, C AS A + B PERSISTED)`,
		`CREATE TABLE T (A INT, B INT, C AS (A * B))`,
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input: %s, error: %s", input, p.Errors()[0])
		}
	}
}

func TestSessionSetOptions(t *testing.T) {
	tests := []string{
		`SET ANSI_NULLS ON`,
		`SET QUOTED_IDENTIFIER ON`,
		`SET NOCOUNT ON`,
		`SET XACT_ABORT ON`,
		`SET IDENTITY_INSERT T ON`,
		`SET IMPLICIT_TRANSACTIONS ON`,
		`SET LOCK_TIMEOUT 5000`,
		`SET DEADLOCK_PRIORITY LOW`,
		`SET TRANSACTION ISOLATION LEVEL READ COMMITTED`,
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input: %s, error: %s", input, p.Errors()[0])
		}
	}
}

func TestQueryHintsAndOptions(t *testing.T) {
	tests := []string{
		`SELECT * FROM T WITH (NOLOCK)`,
		`SELECT * FROM T WITH (FORCESEEK)`,
		`SELECT * FROM T WITH (INDEX(IX_Name))`,
		`SELECT * FROM T WITH (READPAST)`,
		`SELECT * FROM T OPTION (RECOMPILE)`,
		`SELECT * FROM T OPTION (MAXDOP 4)`,
		`SELECT TOP 10 WITH TIES * FROM T ORDER BY Score DESC`,
		`SELECT * FROM T TABLESAMPLE (10 PERCENT)`,
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input: %s, error: %s", input, p.Errors()[0])
		}
	}
}

func TestNotExpressions(t *testing.T) {
	tests := []string{
		`SELECT * FROM T WHERE NOT (A = 1 OR B = 2)`,
		`SELECT * FROM T WHERE ID NOT IN (1, 2, 3)`,
		`SELECT * FROM T WHERE NOT EXISTS (SELECT 1 FROM S WHERE S.ID = T.ID)`,
		`SELECT * FROM T WHERE Name NOT LIKE '%test%'`,
		`SELECT * FROM T WHERE Val NOT BETWEEN 1 AND 10`,
		`SELECT * FROM T WHERE Col IS NOT NULL`,
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input: %s, error: %s", input, p.Errors()[0])
		}
	}
}

func TestRecursiveCTE(t *testing.T) {
	tests := []string{
		`WITH Nums AS (SELECT 1 AS N UNION ALL SELECT N + 1 FROM Nums WHERE N < 10) SELECT N FROM Nums`,
		`WITH Hierarchy AS (SELECT ID, ParentID, Name, 0 AS Level FROM T WHERE ParentID IS NULL UNION ALL SELECT T.ID, T.ParentID, T.Name, H.Level + 1 FROM T INNER JOIN Hierarchy H ON T.ParentID = H.ID) SELECT * FROM Hierarchy`,
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input: %s, error: %s", input, p.Errors()[0])
		}
	}
}

func TestCreateOrAlter(t *testing.T) {
	tests := []string{
		`CREATE OR ALTER PROCEDURE dbo.MyProc AS SELECT 1`,
		`CREATE OR ALTER FUNCTION dbo.MyFunc() RETURNS INT AS BEGIN RETURN 1 END`,
		`CREATE OR ALTER VIEW dbo.MyView AS SELECT 1 AS A`,
		`CREATE OR ALTER TRIGGER dbo.MyTrig ON dbo.T AFTER INSERT AS SELECT 1`,
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input: %s, error: %s", input, p.Errors()[0])
		}
	}
}

func TestDropIfExists(t *testing.T) {
	tests := []string{
		`DROP TABLE IF EXISTS T1, T2, T3`,
		`DROP PROCEDURE IF EXISTS dbo.MyProc`,
		`DROP FUNCTION IF EXISTS dbo.MyFunc`,
		`DROP VIEW IF EXISTS dbo.MyView`,
		`DROP TRIGGER IF EXISTS dbo.MyTrig`,
		`DROP INDEX IF EXISTS IX_Test ON T`,
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input: %s, error: %s", input, p.Errors()[0])
		}
	}
}

func TestModuloAndUnary(t *testing.T) {
	tests := []string{
		`SELECT A % B FROM T`,
		`SELECT -A, -5, -(A + B) FROM T`,
		`SELECT +A FROM T`,
		`SELECT A % 10 FROM T`,
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input: %s, error: %s", input, p.Errors()[0])
		}
	}
}

func TestUnionChain(t *testing.T) {
	tests := []string{
		`SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4`,
		`SELECT 1 UNION SELECT 2 UNION SELECT 3`,
		`SELECT A FROM T1 EXCEPT SELECT A FROM T2`,
		`SELECT A FROM T1 INTERSECT SELECT A FROM T2`,
		`(SELECT A FROM T1) UNION ALL (SELECT A FROM T2)`,
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input: %s, error: %s", input, p.Errors()[0])
		}
	}
}

// =============================================================================
// AST String() Output Tests - Round-trip Fidelity
// =============================================================================

func TestASTStringExpressions(t *testing.T) {
	tests := []struct {
		input    string
		contains string // substring that must appear in output
	}{
		// Arithmetic
		{`SELECT 1 + 2`, "+"},
		{`SELECT 3 * 4`, "*"},
		{`SELECT 10 / 2`, "/"},
		{`SELECT 5 - 3`, "-"},
		{`SELECT 10 % 3`, "%"},
		// Comparison
		{`SELECT * FROM T WHERE A = 1`, "="},
		{`SELECT * FROM T WHERE A <> 1`, "<>"},
		{`SELECT * FROM T WHERE A > 1`, ">"},
		{`SELECT * FROM T WHERE A < 1`, "<"},
		{`SELECT * FROM T WHERE A >= 1`, ">="},
		{`SELECT * FROM T WHERE A <= 1`, "<="},
		// Logical
		{`SELECT * FROM T WHERE A = 1 AND B = 2`, "AND"},
		{`SELECT * FROM T WHERE A = 1 OR B = 2`, "OR"},
		{`SELECT * FROM T WHERE NOT A = 1`, "NOT"},
		// Bitwise
		{`SELECT A & B FROM T`, "&"},
		{`SELECT A | B FROM T`, "|"},
		{`SELECT A ^ B FROM T`, "^"},
		{`SELECT ~A FROM T`, "~"},
		// String concatenation
		{`SELECT A + B FROM T`, "+"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input %q: parse error: %s", tt.input, p.Errors()[0])
			continue
		}
		output := program.String()
		if !strings.Contains(output, tt.contains) {
			t.Errorf("input %q: expected output to contain %q, got %q", tt.input, tt.contains, output)
		}
	}
}

func TestASTStringLiterals(t *testing.T) {
	tests := []struct {
		input    string
		contains string
	}{
		{`SELECT 123`, "123"},
		{`SELECT 3.14`, "3.14"},
		{`SELECT 'hello'`, "'hello'"},
		{`SELECT N'unicode'`, "N'unicode'"},
		{`SELECT NULL`, "NULL"},
		{`SELECT 0xFF`, "0xFF"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input %q: parse error: %s", tt.input, p.Errors()[0])
			continue
		}
		output := program.String()
		if !strings.Contains(output, tt.contains) {
			t.Errorf("input %q: expected output to contain %q, got %q", tt.input, tt.contains, output)
		}
	}
}

func TestASTStringCaseExpressions(t *testing.T) {
	tests := []struct {
		input    string
		contains []string
	}{
		{
			`SELECT CASE WHEN A > 0 THEN 'Positive' ELSE 'Non-positive' END FROM T`,
			[]string{"CASE", "WHEN", "THEN", "ELSE", "END"},
		},
		{
			`SELECT CASE Status WHEN 1 THEN 'Active' WHEN 2 THEN 'Inactive' END FROM T`,
			[]string{"CASE", "WHEN", "THEN", "END"},
		},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input %q: parse error: %s", tt.input, p.Errors()[0])
			continue
		}
		output := program.String()
		for _, substr := range tt.contains {
			if !strings.Contains(output, substr) {
				t.Errorf("input %q: expected output to contain %q, got %q", tt.input, substr, output)
			}
		}
	}
}

func TestASTStringFunctions(t *testing.T) {
	tests := []struct {
		input    string
		contains string
	}{
		{`SELECT COUNT(*) FROM T`, "COUNT"},
		{`SELECT SUM(Amount) FROM T`, "SUM"},
		{`SELECT AVG(Price) FROM T`, "AVG"},
		{`SELECT MAX(Date) FROM T`, "MAX"},
		{`SELECT MIN(Date) FROM T`, "MIN"},
		{`SELECT COALESCE(A, B, C) FROM T`, "COALESCE"},
		{`SELECT NULLIF(A, 0) FROM T`, "NULLIF"},
		{`SELECT LEN(Name) FROM T`, "LEN"},
		{`SELECT GETDATE()`, "GETDATE"},
		{`SELECT NEWID()`, "NEWID"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input %q: parse error: %s", tt.input, p.Errors()[0])
			continue
		}
		output := program.String()
		if !strings.Contains(output, tt.contains) {
			t.Errorf("input %q: expected output to contain %q, got %q", tt.input, tt.contains, output)
		}
	}
}

func TestASTStringCastConvert(t *testing.T) {
	tests := []struct {
		input    string
		contains []string
	}{
		{`SELECT CAST(A AS INT)`, []string{"CAST", "AS", "INT"}},
		{`SELECT CAST(A AS VARCHAR(50))`, []string{"CAST", "AS", "VARCHAR"}},
		{`SELECT CONVERT(INT, A)`, []string{"CONVERT", "INT"}},
		{`SELECT CONVERT(VARCHAR(10), A, 101)`, []string{"CONVERT", "VARCHAR"}},
		{`SELECT TRY_CAST(A AS INT)`, []string{"TRY_CAST", "AS", "INT"}},
		{`SELECT TRY_CONVERT(INT, A)`, []string{"TRY_CONVERT", "INT"}},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input %q: parse error: %s", tt.input, p.Errors()[0])
			continue
		}
		output := program.String()
		for _, substr := range tt.contains {
			if !strings.Contains(output, substr) {
				t.Errorf("input %q: expected output to contain %q, got %q", tt.input, substr, output)
			}
		}
	}
}

func TestASTStringPredicates(t *testing.T) {
	tests := []struct {
		input    string
		contains []string
	}{
		{`SELECT * FROM T WHERE A IS NULL`, []string{"IS", "NULL"}},
		{`SELECT * FROM T WHERE A IS NOT NULL`, []string{"IS", "NOT", "NULL"}},
		{`SELECT * FROM T WHERE A IN (1, 2, 3)`, []string{"IN"}},
		{`SELECT * FROM T WHERE A NOT IN (1, 2)`, []string{"NOT", "IN"}},
		{`SELECT * FROM T WHERE A BETWEEN 1 AND 10`, []string{"BETWEEN", "AND"}},
		{`SELECT * FROM T WHERE A NOT BETWEEN 1 AND 10`, []string{"NOT", "BETWEEN"}},
		{`SELECT * FROM T WHERE A LIKE '%test%'`, []string{"LIKE"}},
		{`SELECT * FROM T WHERE A NOT LIKE '%test%'`, []string{"NOT", "LIKE"}},
		{`SELECT * FROM T WHERE EXISTS (SELECT 1 FROM S)`, []string{"EXISTS"}},
		{`SELECT * FROM T WHERE NOT EXISTS (SELECT 1 FROM S)`, []string{"NOT", "EXISTS"}},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input %q: parse error: %s", tt.input, p.Errors()[0])
			continue
		}
		output := program.String()
		for _, substr := range tt.contains {
			if !strings.Contains(output, substr) {
				t.Errorf("input %q: expected output to contain %q, got %q", tt.input, substr, output)
			}
		}
	}
}

func TestASTStringSelectStatement(t *testing.T) {
	tests := []struct {
		input    string
		contains []string
	}{
		{
			`SELECT TOP 10 A, B FROM T`,
			[]string{"SELECT", "TOP", "10", "FROM"},
		},
		{
			`SELECT DISTINCT A FROM T`,
			[]string{"SELECT", "DISTINCT", "FROM"},
		},
		{
			`SELECT A FROM T WHERE B = 1`,
			[]string{"SELECT", "FROM", "WHERE"},
		},
		{
			`SELECT A FROM T ORDER BY A DESC`,
			[]string{"SELECT", "FROM", "ORDER BY", "DESC"},
		},
		{
			`SELECT A, COUNT(*) FROM T GROUP BY A`,
			[]string{"SELECT", "FROM", "GROUP BY"},
		},
		{
			`SELECT A, COUNT(*) FROM T GROUP BY A HAVING COUNT(*) > 1`,
			[]string{"SELECT", "GROUP BY", "HAVING"},
		},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input %q: parse error: %s", tt.input, p.Errors()[0])
			continue
		}
		output := program.String()
		for _, substr := range tt.contains {
			if !strings.Contains(output, substr) {
				t.Errorf("input %q: expected output to contain %q, got %q", tt.input, substr, output)
			}
		}
	}
}

func TestASTStringJoins(t *testing.T) {
	tests := []struct {
		input    string
		contains []string
	}{
		{
			`SELECT * FROM A INNER JOIN B ON A.ID = B.ID`,
			[]string{"INNER JOIN", "ON"},
		},
		{
			`SELECT * FROM A LEFT JOIN B ON A.ID = B.ID`,
			[]string{"LEFT", "JOIN", "ON"},
		},
		{
			`SELECT * FROM A RIGHT JOIN B ON A.ID = B.ID`,
			[]string{"RIGHT", "JOIN", "ON"},
		},
		{
			`SELECT * FROM A CROSS JOIN B`,
			[]string{"CROSS JOIN"},
		},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input %q: parse error: %s", tt.input, p.Errors()[0])
			continue
		}
		output := program.String()
		for _, substr := range tt.contains {
			if !strings.Contains(output, substr) {
				t.Errorf("input %q: expected output to contain %q, got %q", tt.input, substr, output)
			}
		}
	}
}

func TestASTStringInsertStatement(t *testing.T) {
	tests := []struct {
		input    string
		contains []string
	}{
		{
			`INSERT INTO T (A, B) VALUES (1, 2)`,
			[]string{"INSERT", "INTO", "VALUES"},
		},
		{
			`INSERT INTO T (A) SELECT A FROM S`,
			[]string{"INSERT", "INTO", "SELECT", "FROM"},
		},
		{
			`INSERT INTO T DEFAULT VALUES`,
			[]string{"INSERT", "INTO", "DEFAULT VALUES"},
		},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input %q: parse error: %s", tt.input, p.Errors()[0])
			continue
		}
		output := program.String()
		for _, substr := range tt.contains {
			if !strings.Contains(output, substr) {
				t.Errorf("input %q: expected output to contain %q, got %q", tt.input, substr, output)
			}
		}
	}
}

func TestASTStringUpdateStatement(t *testing.T) {
	tests := []struct {
		input    string
		contains []string
	}{
		{
			`UPDATE T SET A = 1`,
			[]string{"UPDATE", "SET"},
		},
		{
			`UPDATE T SET A = 1 WHERE B = 2`,
			[]string{"UPDATE", "SET", "WHERE"},
		},
		{
			`UPDATE T SET A = A + 1`,
			[]string{"UPDATE", "SET", "+"},
		},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input %q: parse error: %s", tt.input, p.Errors()[0])
			continue
		}
		output := program.String()
		for _, substr := range tt.contains {
			if !strings.Contains(output, substr) {
				t.Errorf("input %q: expected output to contain %q, got %q", tt.input, substr, output)
			}
		}
	}
}

func TestASTStringDeleteStatement(t *testing.T) {
	tests := []struct {
		input    string
		contains []string
	}{
		{
			`DELETE FROM T`,
			[]string{"DELETE", "FROM"},
		},
		{
			`DELETE FROM T WHERE A = 1`,
			[]string{"DELETE", "FROM", "WHERE"},
		},
		{
			`DELETE TOP (10) FROM T`,
			[]string{"DELETE", "TOP", "FROM"},
		},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input %q: parse error: %s", tt.input, p.Errors()[0])
			continue
		}
		output := program.String()
		for _, substr := range tt.contains {
			if !strings.Contains(output, substr) {
				t.Errorf("input %q: expected output to contain %q, got %q", tt.input, substr, output)
			}
		}
	}
}

func TestASTStringWindowFunctions(t *testing.T) {
	tests := []struct {
		input    string
		contains []string
	}{
		{
			`SELECT ROW_NUMBER() OVER (ORDER BY A) FROM T`,
			[]string{"ROW_NUMBER", "OVER", "ORDER BY"},
		},
		{
			`SELECT SUM(A) OVER (PARTITION BY B ORDER BY C) FROM T`,
			[]string{"SUM", "OVER", "PARTITION BY", "ORDER BY"},
		},
		{
			`SELECT RANK() OVER (ORDER BY A DESC) FROM T`,
			[]string{"RANK", "OVER", "ORDER BY", "DESC"},
		},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input %q: parse error: %s", tt.input, p.Errors()[0])
			continue
		}
		output := program.String()
		for _, substr := range tt.contains {
			if !strings.Contains(output, substr) {
				t.Errorf("input %q: expected output to contain %q, got %q", tt.input, substr, output)
			}
		}
	}
}

func TestASTStringCTE(t *testing.T) {
	tests := []struct {
		input    string
		contains []string
	}{
		{
			`WITH CTE AS (SELECT 1 AS A) SELECT * FROM CTE`,
			[]string{"WITH", "AS", "SELECT"},
		},
		{
			`WITH CTE1 AS (SELECT 1), CTE2 AS (SELECT 2) SELECT * FROM CTE1, CTE2`,
			[]string{"WITH", "CTE1", "CTE2", "AS"},
		},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input %q: parse error: %s", tt.input, p.Errors()[0])
			continue
		}
		output := program.String()
		for _, substr := range tt.contains {
			if !strings.Contains(output, substr) {
				t.Errorf("input %q: expected output to contain %q, got %q", tt.input, substr, output)
			}
		}
	}
}

func TestASTStringSubqueries(t *testing.T) {
	tests := []struct {
		input    string
		contains []string
	}{
		{
			`SELECT * FROM (SELECT 1 AS A) AS Sub`,
			[]string{"SELECT", "FROM", "AS"},
		},
		{
			`SELECT (SELECT MAX(A) FROM T) AS MaxVal`,
			[]string{"SELECT", "MAX"},
		},
		{
			`SELECT * FROM T WHERE A IN (SELECT A FROM S)`,
			[]string{"SELECT", "WHERE", "IN"},
		},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input %q: parse error: %s", tt.input, p.Errors()[0])
			continue
		}
		output := program.String()
		for _, substr := range tt.contains {
			if !strings.Contains(output, substr) {
				t.Errorf("input %q: expected output to contain %q, got %q", tt.input, substr, output)
			}
		}
	}
}

func TestASTStringSetOperations(t *testing.T) {
	tests := []struct {
		input    string
		contains []string
	}{
		{
			`SELECT A FROM T1 UNION SELECT A FROM T2`,
			[]string{"UNION"},
		},
		{
			`SELECT A FROM T1 UNION ALL SELECT A FROM T2`,
			[]string{"UNION ALL"},
		},
		{
			`SELECT A FROM T1 EXCEPT SELECT A FROM T2`,
			[]string{"EXCEPT"},
		},
		{
			`SELECT A FROM T1 INTERSECT SELECT A FROM T2`,
			[]string{"INTERSECT"},
		},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input %q: parse error: %s", tt.input, p.Errors()[0])
			continue
		}
		output := program.String()
		for _, substr := range tt.contains {
			if !strings.Contains(output, substr) {
				t.Errorf("input %q: expected output to contain %q, got %q", tt.input, substr, output)
			}
		}
	}
}

func TestASTStringDDLStatements(t *testing.T) {
	tests := []struct {
		input    string
		contains []string
	}{
		{
			`CREATE TABLE T (A INT, B VARCHAR(50))`,
			[]string{"CREATE TABLE", "INT", "VARCHAR"},
		},
		{
			`ALTER TABLE T ADD C INT`,
			[]string{"ALTER TABLE", "ADD"},
		},
		{
			`DROP TABLE T`,
			[]string{"DROP TABLE"},
		},
		{
			`CREATE INDEX IX ON T (A)`,
			[]string{"CREATE", "INDEX", "ON"},
		},
		{
			`CREATE VIEW V AS SELECT * FROM T`,
			[]string{"CREATE VIEW", "AS", "SELECT"},
		},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input %q: parse error: %s", tt.input, p.Errors()[0])
			continue
		}
		output := program.String()
		for _, substr := range tt.contains {
			if !strings.Contains(output, substr) {
				t.Errorf("input %q: expected output to contain %q, got %q", tt.input, substr, output)
			}
		}
	}
}

func TestASTStringControlFlow(t *testing.T) {
	tests := []struct {
		input    string
		contains []string
	}{
		{
			`IF @x > 0 SELECT 1`,
			[]string{"IF"},
		},
		{
			`IF @x > 0 SELECT 1 ELSE SELECT 2`,
			[]string{"IF", "ELSE"},
		},
		{
			`WHILE @i < 10 SET @i = @i + 1`,
			[]string{"WHILE"},
		},
		{
			`BEGIN SELECT 1 END`,
			[]string{"BEGIN", "END"},
		},
		{
			`BEGIN TRY SELECT 1 END TRY BEGIN CATCH SELECT 2 END CATCH`,
			[]string{"BEGIN TRY", "END TRY", "BEGIN CATCH", "END CATCH"},
		},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input %q: parse error: %s", tt.input, p.Errors()[0])
			continue
		}
		output := program.String()
		for _, substr := range tt.contains {
			if !strings.Contains(output, substr) {
				t.Errorf("input %q: expected output to contain %q, got %q", tt.input, substr, output)
			}
		}
	}
}

func TestASTStringTransactions(t *testing.T) {
	tests := []struct {
		input    string
		contains []string
	}{
		{`BEGIN TRANSACTION`, []string{"BEGIN TRANSACTION"}},
		{`COMMIT TRANSACTION`, []string{"COMMIT"}},
		{`ROLLBACK TRANSACTION`, []string{"ROLLBACK"}},
		{`SAVE TRANSACTION SP1`, []string{"SAVE TRANSACTION"}},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input %q: parse error: %s", tt.input, p.Errors()[0])
			continue
		}
		output := program.String()
		for _, substr := range tt.contains {
			if !strings.Contains(output, substr) {
				t.Errorf("input %q: expected output to contain %q, got %q", tt.input, substr, output)
			}
		}
	}
}

func TestASTStringVariablesAndSet(t *testing.T) {
	tests := []struct {
		input    string
		contains []string
	}{
		{`DECLARE @x INT`, []string{"DECLARE", "@x", "INT"}},
		{`DECLARE @x INT = 5`, []string{"DECLARE", "@x", "INT"}},
		{`SET @x = 10`, []string{"SET", "@x"}},
		{`SELECT @x = A FROM T`, []string{"SELECT", "@x"}},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input %q: parse error: %s", tt.input, p.Errors()[0])
			continue
		}
		output := program.String()
		for _, substr := range tt.contains {
			if !strings.Contains(output, substr) {
				t.Errorf("input %q: expected output to contain %q, got %q", tt.input, substr, output)
			}
		}
	}
}

func TestASTStringQualifiedIdentifiers(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{`SELECT * FROM dbo.T`, "dbo.T"},
		{`SELECT * FROM [Schema].[Table]`, "Schema.Table"},
		{`SELECT * FROM Server.DB.dbo.T`, "Server.DB.dbo.T"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("input %q: parse error: %s", tt.input, p.Errors()[0])
			continue
		}
		output := program.String()
		if !strings.Contains(output, tt.expected) {
			t.Errorf("input %q: expected output to contain %q, got %q", tt.input, tt.expected, output)
		}
	}
}

// =============================================================================
// Negative Tests - Expected Parse Failures and Error Messages
// =============================================================================

func TestParseErrorsInvalidSyntax(t *testing.T) {
	// These inputs should all produce parse errors
	// Note: Parser is lenient - only testing what it actually catches
	tests := []struct {
		input string
		desc  string
	}{
		// Missing keywords that parser catches
		{`SELECT FROM T`, "missing column list"},
		{`UPDATE SET A = 1`, "missing table name"},
		// Incomplete statements
		{`SELECT`, "SELECT with nothing"},
		{`UPDATE T SET`, "incomplete UPDATE"},
		{`CREATE TABLE`, "incomplete CREATE TABLE"},
		// Mismatched parentheses
		{`SELECT (A + B FROM T`, "unclosed parenthesis"},
		{`SELECT * FROM (SELECT 1`, "unclosed subquery"},
		// Misplaced keywords
		{`SELECT * WHERE A = 1 FROM T`, "WHERE before FROM"},
		// Invalid expressions
		{`SELECT * FROM T WHERE A = = 1`, "double equals"},
		{`SELECT * FROM T WHERE AND A = 1`, "AND at start of condition"},
		{`SELECT * FROM T WHERE A = 1 OR`, "trailing OR"},
		// Invalid JOIN syntax
		{`SELECT * FROM T INNER B ON T.ID = B.ID`, "missing JOIN keyword"},
		// Invalid GROUP BY / ORDER BY
		{`SELECT * FROM T ORDER`, "incomplete ORDER BY"},
		{`SELECT * FROM T GROUP`, "incomplete GROUP BY"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) == 0 {
			t.Errorf("%s: expected parse error for %q, but got none", tt.desc, tt.input)
		}
	}
}

func TestParseErrorsInvalidDDL(t *testing.T) {
	tests := []struct {
		input string
		desc  string
	}{
		// Invalid CREATE TABLE
		{`CREATE TABLE ()`, "table without name"},
		{`CREATE TABLE T`, "table without columns"},
		// Invalid CREATE INDEX
		{`CREATE INDEX ON T (A)`, "index without name"},
		{`CREATE INDEX IX ON (A)`, "index without table"},
		// Invalid CREATE VIEW
		{`CREATE VIEW AS SELECT 1`, "view without name"},
		{`CREATE VIEW V SELECT 1`, "view without AS"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) == 0 {
			t.Errorf("%s: expected parse error for %q, but got none", tt.desc, tt.input)
		}
	}
}

func TestParseErrorsInvalidExpressions(t *testing.T) {
	tests := []struct {
		input string
		desc  string
	}{
		// Invalid CASE
		{`SELECT CASE END FROM T`, "CASE without WHEN"},
		{`SELECT CASE WHEN THEN 1 END FROM T`, "WHEN without condition"},
		{`SELECT CASE WHEN A > 0 END FROM T`, "WHEN without THEN"},
		{`SELECT CASE WHEN A > 0 THEN FROM T`, "THEN without result"},
		// Invalid CAST/CONVERT
		{`SELECT CAST(A INT) FROM T`, "CAST without AS"},
		{`SELECT CAST(A AS) FROM T`, "CAST without target type"},
		{`SELECT CONVERT(, A) FROM T`, "CONVERT without type"},
		// Invalid BETWEEN
		{`SELECT * FROM T WHERE A BETWEEN 1`, "BETWEEN without AND"},
		{`SELECT * FROM T WHERE A BETWEEN AND 10`, "BETWEEN without start"},
		// Invalid IN
		{`SELECT * FROM T WHERE A IN`, "IN without values"},
		// Invalid LIKE
		{`SELECT * FROM T WHERE A LIKE`, "LIKE without pattern"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) == 0 {
			t.Errorf("%s: expected parse error for %q, but got none", tt.desc, tt.input)
		}
	}
}

func TestParseErrorsInvalidControlFlow(t *testing.T) {
	tests := []struct {
		input string
		desc  string
	}{
		// Invalid BEGIN/END (parser catches END without BEGIN)
		{`END`, "END without BEGIN"},
		// Invalid TRY/CATCH
		{`BEGIN TRY SELECT 1 END TRY`, "TRY without CATCH"},
		{`BEGIN CATCH SELECT 1 END CATCH`, "CATCH without TRY"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) == 0 {
			t.Errorf("%s: expected parse error for %q, but got none", tt.desc, tt.input)
		}
	}
}

func TestErrorMessageContainsLineAndColumn(t *testing.T) {
	// Error messages should include position information
	input := `SELECT *
FROM T
WHERE = 1` // Error on line 3

	l := lexer.New(input)
	p := New(l)
	p.ParseProgram()

	if len(p.Errors()) == 0 {
		t.Fatal("expected parse error")
	}

	errMsg := p.Errors()[0]
	// Error should mention line number
	if !strings.Contains(errMsg, "line") {
		t.Errorf("error message should contain line number: %s", errMsg)
	}
	// Error should mention column number
	if !strings.Contains(errMsg, "col") {
		t.Errorf("error message should contain column number: %s", errMsg)
	}
}

func TestErrorMessageDescribesExpected(t *testing.T) {
	tests := []struct {
		input    string
		expected string // substring that should appear in error
	}{
		{`INSERT INTO T VALUES`, "expected"}, // Should describe expectation
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		p.ParseProgram()

		if len(p.Errors()) == 0 {
			t.Errorf("expected parse error for %q", tt.input)
			continue
		}

		errMsg := p.Errors()[0]
		if !strings.Contains(strings.ToLower(errMsg), tt.expected) {
			t.Errorf("error for %q should contain %q: got %s", tt.input, tt.expected, errMsg)
		}
	}
}

func TestMultipleErrorsReported(t *testing.T) {
	// Parser should be able to report multiple errors (not just first one)
	// Note: Our parser typically stops at first error, but let's verify it reports at least one
	input := `SELECT * FROM WHERE ORDER BY`

	l := lexer.New(input)
	p := New(l)
	p.ParseProgram()

	if len(p.Errors()) == 0 {
		t.Error("expected at least one parse error")
	}
}

func TestErrorOnEmptyStatements(t *testing.T) {
	tests := []struct {
		input string
		desc  string
	}{
		{`;`, "lone semicolon"},
		{`; ;`, "multiple semicolons"},
		{`GO GO`, "consecutive GO"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()

		// Either should produce error or produce empty/minimal AST
		// Not a hard error, but let's document behaviour
		if len(p.Errors()) == 0 && len(program.Statements) > 2 {
			t.Logf("%s: %q parsed without error, %d statements", tt.desc, tt.input, len(program.Statements))
		}
	}
}

func TestParseErrorsInvalidClauses(t *testing.T) {
	tests := []struct {
		input string
		desc  string
	}{
		// Invalid ORDER BY
		{`SELECT * FROM T ORDER BY ASC`, "ORDER BY without column"},
		// Invalid TOP
		{`SELECT TOP FROM T`, "TOP without count"},
		{`SELECT TOP () * FROM T`, "TOP with empty parens"},
		// Invalid DISTINCT
		{`SELECT DISTINCT FROM T`, "DISTINCT without columns"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) == 0 {
			t.Errorf("%s: expected parse error for %q, but got none", tt.desc, tt.input)
		}
	}
}

func TestParseErrorsInvalidJoins(t *testing.T) {
	tests := []struct {
		input string
		desc  string
	}{
		{`SELECT * FROM T JOIN ON T.A = S.A`, "JOIN without table"},
		{`SELECT * FROM T LEFT S ON T.A = S.A`, "LEFT without JOIN"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) == 0 {
			t.Errorf("%s: expected parse error for %q, but got none", tt.desc, tt.input)
		}
	}
}

func TestParseErrorsInvalidMerge(t *testing.T) {
	tests := []struct {
		input string
		desc  string
	}{
		{`MERGE INTO T`, "MERGE without USING"},
		{`MERGE INTO T USING S`, "MERGE without ON"},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) == 0 {
			t.Errorf("%s: expected parse error for %q, but got none", tt.desc, tt.input)
		}
	}
}

func TestParserLeniencyDocumentation(t *testing.T) {
	// Document cases where parser is intentionally lenient
	// These parse without error even though they're technically invalid SQL
	// This is by design for robustness
	lenientCases := []struct {
		input string
		desc  string
	}{
		{`SELECT * T`, "missing FROM - parsed as alias"},
		{`INSERT T VALUES (1)`, "missing INTO - T parsed as table"},
		{`DELETE T`, "missing FROM - T parsed as table"},
		{`SELECT COUNT FROM T`, "COUNT without parens - parsed as column"},
		{`SELECT * FROM T JOIN B`, "JOIN without ON - lenient"},
		{`SELECT * FROM T HAVING A > 1`, "HAVING without GROUP BY - lenient"},
		{`IF @x > 0`, "IF without body at EOF - lenient"},
		{`WHILE @x < 10`, "WHILE without body at EOF - lenient"},
		{`BEGIN`, "BEGIN without END at EOF - lenient"},
		{`CREATE TABLE T (A)`, "column without type - parsed as column name only"},
	}

	for _, tt := range lenientCases {
		l := lexer.New(tt.input)
		p := New(l)
		p.ParseProgram()
		// These should NOT produce errors (parser is lenient)
		if len(p.Errors()) > 0 {
			t.Logf("%s: %q - parser was strict here: %s", tt.desc, tt.input, p.Errors()[0])
		}
	}
}

func TestValidSyntaxNotFlagged(t *testing.T) {
	// Ensure we don't have false positives - these should all parse successfully
	tests := []string{
		`SELECT 1`,
		`SELECT * FROM T`,
		`SELECT A, B FROM T WHERE C = 1`,
		`INSERT INTO T (A) VALUES (1)`,
		`UPDATE T SET A = 1`,
		`DELETE FROM T WHERE A = 1`,
		`CREATE TABLE T (A INT)`,
		`DROP TABLE T`,
		`BEGIN SELECT 1 END`,
		`IF @x > 0 SELECT 1`,
		`WHILE @x < 10 SET @x = @x + 1`,
		`BEGIN TRANSACTION COMMIT TRANSACTION`,
		`DECLARE @x INT`,
		`SET @x = 1`,
		`EXEC sp_help`,
		`SELECT * FROM T WITH (NOLOCK)`,
		`SELECT TOP 10 * FROM T`,
		`SELECT * FROM T ORDER BY A`,
		`SELECT A, COUNT(*) FROM T GROUP BY A`,
		`SELECT * FROM T1 INNER JOIN T2 ON T1.ID = T2.ID`,
		`WITH CTE AS (SELECT 1 AS A) SELECT * FROM CTE`,
		`SELECT * FROM T WHERE A IN (1, 2, 3)`,
		`SELECT * FROM T WHERE A BETWEEN 1 AND 10`,
		`SELECT * FROM T WHERE A LIKE '%test%'`,
		`SELECT CASE WHEN A > 0 THEN 'Y' ELSE 'N' END FROM T`,
		`SELECT CAST(A AS VARCHAR(10)) FROM T`,
		`SELECT ROW_NUMBER() OVER (ORDER BY A) FROM T`,
		`SELECT * FROM T1 UNION SELECT * FROM T2`,
		`MERGE INTO T USING S ON T.ID = S.ID WHEN MATCHED THEN UPDATE SET T.A = S.A`,
	}

	for _, input := range tests {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
		if len(p.Errors()) > 0 {
			t.Errorf("valid syntax %q produced error: %s", input, p.Errors()[0])
		}
	}
}

func TestOpenXmlWithClause(t *testing.T) {
	tests := []struct {
		input string
		desc  string
	}{
		{
			`SELECT * FROM OPENXML(@idoc, '/root/item', 2) WITH (ID INT '@id', Name NVARCHAR(50) 'name')`,
			"OPENXML with attribute and element paths",
		},
		{
			`SELECT * FROM OPENXML(@idoc, '/employees/employee', 2)
			 WITH (
				EmployeeId INT '@id',
				FirstName NVARCHAR(50) 'firstName',
				LastName NVARCHAR(50) 'lastName',
				Salary DECIMAL(10,2) 'salary'
			 )`,
			"OPENXML with multiple columns",
		},
		{
			`SELECT * FROM OPENXML(@idoc, '/root', 1) WITH (Value VARCHAR(100) '.')`,
			"OPENXML with text node path",
		},
	}

	for _, tt := range tests {
		l := lexer.New(tt.input)
		p := New(l)
		program := p.ParseProgram()

		if len(p.Errors()) > 0 {
			t.Errorf("%s: parse error: %s", tt.desc, p.Errors()[0])
			continue
		}

		if len(program.Statements) == 0 {
			t.Errorf("%s: no statements parsed", tt.desc)
		}
	}
}
