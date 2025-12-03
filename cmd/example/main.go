// Example: Parsing and analyzing T-SQL stored procedures
package main

import (
	"fmt"

	"github.com/ha1tch/tsqlparser"
	"github.com/ha1tch/tsqlparser/ast"
)

func main() {
	// Example T-SQL stored procedure
	tsql := `
CREATE PROCEDURE dbo.GetCustomerOrders
    @CustomerID INT,
    @StartDate DATETIME = NULL,
    @EndDate DATETIME = NULL,
    @TotalOrders INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    -- Validate parameters
    IF @CustomerID IS NULL
    BEGIN
        RAISERROR('CustomerID cannot be NULL', 16, 1);
        RETURN -1;
    END

    -- Set defaults
    IF @StartDate IS NULL
        SET @StartDate = DATEADD(YEAR, -1, GETDATE());

    IF @EndDate IS NULL
        SET @EndDate = GETDATE();

    BEGIN TRY
        -- Get order count
        SELECT @TotalOrders = COUNT(*)
        FROM Orders
        WHERE CustomerID = @CustomerID
          AND OrderDate BETWEEN @StartDate AND @EndDate;

        -- Return order details
        SELECT 
            o.OrderID,
            o.OrderDate,
            o.TotalAmount,
            c.CustomerName,
            CASE 
                WHEN o.TotalAmount > 1000 THEN 'High Value'
                WHEN o.TotalAmount > 500 THEN 'Medium Value'
                ELSE 'Standard'
            END AS OrderCategory
        FROM Orders o
        INNER JOIN Customers c ON o.CustomerID = c.CustomerID
        WHERE o.CustomerID = @CustomerID
          AND o.OrderDate BETWEEN @StartDate AND @EndDate
        ORDER BY o.OrderDate DESC;

        RETURN 0;
    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrorMessage, 16, 1);
        RETURN -1;
    END CATCH
END
GO
`

	fmt.Println("=== T-SQL Parser Demo ===")
	fmt.Println()

	// Parse the T-SQL
	program, errors := tsqlparser.Parse(tsql)

	if len(errors) > 0 {
		fmt.Println("Parse errors:")
		for _, err := range errors {
			fmt.Printf("  - %s\n", err)
		}
		fmt.Println()
	}

	fmt.Printf("Parsed %d statements\n\n", len(program.Statements))

	// Analyze the parsed AST
	for i, stmt := range program.Statements {
		fmt.Printf("Statement %d: %T\n", i+1, stmt)

		switch s := stmt.(type) {
		case *ast.CreateProcedureStatement:
			analyzeProcedure(s)
		case *ast.GoStatement:
			fmt.Println("  Batch separator (GO)")
		}
	}

	// Use the Inspector to find specific elements
	fmt.Println("\n=== Using Inspector ===")
	inspector := tsqlparser.NewInspector(program)

	vars := inspector.FindVariables()
	fmt.Printf("\nFound %d variable references:\n", len(vars))
	seen := make(map[string]bool)
	for _, v := range vars {
		if !seen[v.Name] {
			seen[v.Name] = true
			fmt.Printf("  - %s\n", v.Name)
		}
	}

	selects := inspector.FindSelectStatements()
	fmt.Printf("\nFound %d SELECT statements\n", len(selects))

	funcs := inspector.FindFunctionCalls()
	fmt.Printf("\nFound %d function calls:\n", len(funcs))
	seenFn := make(map[string]bool)
	for _, f := range funcs {
		name := f.Function.String()
		if !seenFn[name] {
			seenFn[name] = true
			fmt.Printf("  - %s()\n", name)
		}
	}

	// Demo: Parse a simple SELECT
	fmt.Println("\n=== Simple SELECT Demo ===")
	simpleSQL := `
SELECT TOP 10
    e.EmployeeID,
    e.FirstName + ' ' + e.LastName AS FullName,
    d.DepartmentName,
    COUNT(*) OVER (PARTITION BY d.DepartmentID) AS DeptCount
FROM Employees e
LEFT JOIN Departments d ON e.DepartmentID = d.DepartmentID
WHERE e.IsActive = 1
  AND e.HireDate > '2020-01-01'
ORDER BY e.LastName, e.FirstName
`

	prog, errs := tsqlparser.Parse(simpleSQL)
	if len(errs) > 0 {
		fmt.Println("Errors:", errs)
	}

	if len(prog.Statements) > 0 {
		if sel, ok := prog.Statements[0].(*ast.SelectStatement); ok {
			fmt.Printf("Columns: %d\n", len(sel.Columns))
			for i, col := range sel.Columns {
				alias := ""
				if col.Alias != nil {
					alias = " AS " + col.Alias.Value
				}
				fmt.Printf("  %d: %s%s\n", i+1, col.Expression.String(), alias)
			}

			if sel.From != nil {
				fmt.Printf("From: %d table references\n", len(sel.From.Tables))
			}

			if sel.Where != nil {
				fmt.Printf("Where clause present: %s\n", sel.Where.String())
			}

			fmt.Printf("Order by: %d items\n", len(sel.OrderBy))
		}
	}
}

func analyzeProcedure(proc *ast.CreateProcedureStatement) {
	fmt.Printf("  Procedure: %s\n", proc.Name.String())
	fmt.Printf("  Parameters: %d\n", len(proc.Parameters))

	for _, param := range proc.Parameters {
		output := ""
		if param.Output {
			output = " OUTPUT"
		}
		defaultVal := ""
		if param.Default != nil {
			defaultVal = " = " + param.Default.String()
		}
		fmt.Printf("    - %s %s%s%s\n", param.Name, param.DataType.String(), defaultVal, output)
	}

	if proc.Body != nil {
		fmt.Printf("  Body statements: %d\n", len(proc.Body.Statements))

		// Count statement types
		counts := make(map[string]int)
		countStatements(proc.Body.Statements, counts)

		fmt.Println("  Statement breakdown:")
		for typ, count := range counts {
			fmt.Printf("    - %s: %d\n", typ, count)
		}
	}
}

func countStatements(stmts []ast.Statement, counts map[string]int) {
	for _, stmt := range stmts {
		switch s := stmt.(type) {
		case *ast.SetStatement:
			counts["SET"]++
		case *ast.IfStatement:
			counts["IF"]++
			if block, ok := s.Consequence.(*ast.BeginEndBlock); ok {
				countStatements(block.Statements, counts)
			}
			if s.Alternative != nil {
				if block, ok := s.Alternative.(*ast.BeginEndBlock); ok {
					countStatements(block.Statements, counts)
				}
			}
		case *ast.SelectStatement:
			counts["SELECT"]++
		case *ast.DeclareStatement:
			counts["DECLARE"]++
		case *ast.ReturnStatement:
			counts["RETURN"]++
		case *ast.TryCatchStatement:
			counts["TRY/CATCH"]++
			countStatements(s.TryBlock.Statements, counts)
			countStatements(s.CatchBlock.Statements, counts)
		case *ast.RaiserrorStatement:
			counts["RAISERROR"]++
		case *ast.BeginEndBlock:
			countStatements(s.Statements, counts)
		}
	}
}
