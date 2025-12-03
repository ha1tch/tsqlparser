package parser

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"

	"github.com/ha1tch/tsqlparser/lexer"
)

// =============================================================================
// PART 1: Library Micro-Benchmarks
// =============================================================================
// These benchmark individual parsing operations to measure raw performance
// and identify bottlenecks in specific constructs.

// --- Lexer Benchmarks ---

func BenchmarkLexerSimple(b *testing.B) {
	input := `SELECT CustomerID, FirstName, LastName FROM Customers WHERE Status = 'Active'`
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		l := lexer.New(input)
		for {
			tok := l.NextToken()
			if tok.Type.String() == "EOF" {
				break
			}
		}
	}
}

func BenchmarkLexerComplex(b *testing.B) {
	input := `
		WITH RegionalSales AS (
			SELECT Region, SUM(Amount) AS TotalSales
			FROM Orders
			WHERE OrderDate >= '2023-01-01'
			GROUP BY Region
		),
		TopRegions AS (
			SELECT Region, TotalSales,
				   ROW_NUMBER() OVER (ORDER BY TotalSales DESC) AS Rank
			FROM RegionalSales
			WHERE TotalSales > 100000
		)
		SELECT r.Region, r.TotalSales, c.CustomerName, o.OrderID
		FROM TopRegions r
		INNER JOIN Customers c ON c.Region = r.Region
		LEFT JOIN Orders o ON o.CustomerID = c.CustomerID
		WHERE r.Rank <= 5
		ORDER BY r.Rank, o.OrderDate DESC
	`
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		l := lexer.New(input)
		for {
			tok := l.NextToken()
			if tok.Type.String() == "EOF" {
				break
			}
		}
	}
}

func BenchmarkLexerManyTokens(b *testing.B) {
	// 100 columns
	cols := make([]string, 100)
	for i := 0; i < 100; i++ {
		cols[i] = fmt.Sprintf("Column%d", i)
	}
	input := "SELECT " + strings.Join(cols, ", ") + " FROM LargeTable"
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		l := lexer.New(input)
		for {
			tok := l.NextToken()
			if tok.Type.String() == "EOF" {
				break
			}
		}
	}
}

// --- Parser: Simple Statements ---

func BenchmarkParseSimpleSelect(b *testing.B) {
	input := `SELECT * FROM Customers`
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
	}
}

func BenchmarkParseSelectWithWhere(b *testing.B) {
	input := `SELECT CustomerID, Name, Email FROM Customers WHERE Status = 'Active' AND CreatedDate > '2023-01-01'`
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
	}
}

func BenchmarkParseInsert(b *testing.B) {
	input := `INSERT INTO Customers (FirstName, LastName, Email, Phone, Address, City, Country) VALUES ('John', 'Doe', 'john@example.com', '555-1234', '123 Main St', 'New York', 'USA')`
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
	}
}

func BenchmarkParseUpdate(b *testing.B) {
	input := `UPDATE Customers SET Status = 'Inactive', ModifiedDate = GETDATE(), ModifiedBy = 'system' WHERE LastLoginDate < '2022-01-01'`
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
	}
}

func BenchmarkParseDelete(b *testing.B) {
	input := `DELETE FROM AuditLog WHERE CreatedDate < DATEADD(year, -1, GETDATE())`
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
	}
}

// --- Parser: Complex Queries ---

func BenchmarkParseJoins(b *testing.B) {
	input := `
		SELECT c.CustomerID, c.Name, o.OrderID, o.Amount, p.ProductName
		FROM Customers c
		INNER JOIN Orders o ON c.CustomerID = o.CustomerID
		LEFT JOIN OrderItems oi ON o.OrderID = oi.OrderID
		LEFT JOIN Products p ON oi.ProductID = p.ProductID
		WHERE c.Status = 'Active'
	`
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
	}
}

func BenchmarkParseCTE(b *testing.B) {
	input := `
		WITH OrderTotals AS (
			SELECT CustomerID, SUM(Amount) AS Total
			FROM Orders
			GROUP BY CustomerID
		),
		CustomerRank AS (
			SELECT CustomerID, Total,
				   RANK() OVER (ORDER BY Total DESC) AS Ranking
			FROM OrderTotals
		)
		SELECT c.Name, cr.Total, cr.Ranking
		FROM CustomerRank cr
		JOIN Customers c ON c.CustomerID = cr.CustomerID
		WHERE cr.Ranking <= 10
	`
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
	}
}

func BenchmarkParseWindowFunctions(b *testing.B) {
	input := `
		SELECT 
			CustomerID,
			OrderDate,
			Amount,
			SUM(Amount) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS RunningTotal,
			AVG(Amount) OVER (PARTITION BY CustomerID) AS AvgAmount,
			ROW_NUMBER() OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS RowNum,
			LAG(Amount, 1) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS PrevAmount,
			LEAD(Amount, 1) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS NextAmount
		FROM Orders
	`
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
	}
}

func BenchmarkParseSubqueries(b *testing.B) {
	input := `
		SELECT c.CustomerID, c.Name,
			(SELECT COUNT(*) FROM Orders o WHERE o.CustomerID = c.CustomerID) AS OrderCount,
			(SELECT MAX(Amount) FROM Orders o WHERE o.CustomerID = c.CustomerID) AS MaxOrder
		FROM Customers c
		WHERE c.CustomerID IN (
			SELECT CustomerID FROM Orders WHERE Amount > 1000
		)
		AND EXISTS (
			SELECT 1 FROM Subscriptions s WHERE s.CustomerID = c.CustomerID AND s.Status = 'Active'
		)
	`
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
	}
}

func BenchmarkParseMerge(b *testing.B) {
	input := `
		MERGE INTO TargetTable AS t
		USING SourceTable AS s ON t.ID = s.ID
		WHEN MATCHED AND s.ModifiedDate > t.ModifiedDate THEN
			UPDATE SET t.Name = s.Name, t.Value = s.Value, t.ModifiedDate = s.ModifiedDate
		WHEN NOT MATCHED BY TARGET THEN
			INSERT (ID, Name, Value, ModifiedDate) VALUES (s.ID, s.Name, s.Value, s.ModifiedDate)
		WHEN NOT MATCHED BY SOURCE THEN
			DELETE;
	`
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
	}
}

// --- Parser: DDL ---

func BenchmarkParseCreateTable(b *testing.B) {
	input := `
		CREATE TABLE Customers (
			CustomerID INT IDENTITY(1,1) PRIMARY KEY,
			FirstName NVARCHAR(50) NOT NULL,
			LastName NVARCHAR(50) NOT NULL,
			Email NVARCHAR(100) UNIQUE,
			Phone VARCHAR(20),
			Address NVARCHAR(200),
			City NVARCHAR(50),
			Country NVARCHAR(50) DEFAULT 'USA',
			CreatedDate DATETIME2 DEFAULT GETDATE(),
			ModifiedDate DATETIME2,
			Status VARCHAR(20) CHECK (Status IN ('Active', 'Inactive', 'Pending')),
			CONSTRAINT CK_Email CHECK (Email LIKE '%@%.%')
		)
	`
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
	}
}

func BenchmarkParseCreateProcedure(b *testing.B) {
	input := `
		CREATE PROCEDURE GetCustomerOrders
			@CustomerID INT,
			@StartDate DATE = NULL,
			@EndDate DATE = NULL
		AS
		BEGIN
			SET NOCOUNT ON;
			
			SELECT o.OrderID, o.OrderDate, o.Amount, o.Status
			FROM Orders o
			WHERE o.CustomerID = @CustomerID
			  AND (@StartDate IS NULL OR o.OrderDate >= @StartDate)
			  AND (@EndDate IS NULL OR o.OrderDate <= @EndDate)
			ORDER BY o.OrderDate DESC;
		END
	`
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
	}
}

// --- Parser: Expression Complexity ---

func BenchmarkParseDeepExpression(b *testing.B) {
	// Deeply nested expression: ((((a + b) * c) - d) / e)
	input := `SELECT ((((A + B) * C) - D) / E) AS Result FROM T`
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
	}
}

func BenchmarkParseManyColumns(b *testing.B) {
	// 50 columns with expressions
	cols := make([]string, 50)
	for i := 0; i < 50; i++ {
		cols[i] = fmt.Sprintf("Col%d * 2 AS Calc%d", i, i)
	}
	input := "SELECT " + strings.Join(cols, ", ") + " FROM LargeTable"
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
	}
}

func BenchmarkParseCaseExpression(b *testing.B) {
	input := `
		SELECT 
			CASE 
				WHEN Status = 'A' THEN 'Active'
				WHEN Status = 'I' THEN 'Inactive'
				WHEN Status = 'P' THEN 'Pending'
				WHEN Status = 'S' THEN 'Suspended'
				WHEN Status = 'D' THEN 'Deleted'
				ELSE 'Unknown'
			END AS StatusName,
			CASE Priority
				WHEN 1 THEN 'Critical'
				WHEN 2 THEN 'High'
				WHEN 3 THEN 'Medium'
				WHEN 4 THEN 'Low'
				ELSE 'None'
			END AS PriorityName
		FROM Tasks
	`
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
	}
}

// --- Parser: Multi-Statement Batch ---

func BenchmarkParseMultiStatement(b *testing.B) {
	input := `
		DECLARE @CustomerID INT = 100;
		DECLARE @Total DECIMAL(18,2);
		
		SELECT @Total = SUM(Amount)
		FROM Orders
		WHERE CustomerID = @CustomerID;
		
		IF @Total > 10000
		BEGIN
			UPDATE Customers SET Tier = 'Gold' WHERE CustomerID = @CustomerID;
			INSERT INTO AuditLog (Action, CustomerID, Value) VALUES ('Tier Upgrade', @CustomerID, @Total);
		END
		ELSE
		BEGIN
			UPDATE Customers SET Tier = 'Silver' WHERE CustomerID = @CustomerID;
		END
		
		SELECT * FROM Customers WHERE CustomerID = @CustomerID;
	`
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
	}
}

// =============================================================================
// PART 2: Corpus Benchmarks
// =============================================================================
// These benchmark parsing against the real-world sample corpus to measure
// overall throughput and identify performance characteristics.

const corpusPath = "../testdata"

// BenchmarkCorpusAll parses all sample files in sequence
func BenchmarkCorpusAll(b *testing.B) {
	files, err := filepath.Glob(filepath.Join(corpusPath, "*.sql"))
	if err != nil || len(files) == 0 {
		b.Skip("corpus not available")
	}

	// Pre-load all files into memory
	contents := make([]string, len(files))
	totalBytes := 0
	for i, f := range files {
		data, err := os.ReadFile(f)
		if err != nil {
			b.Fatalf("failed to read %s: %v", f, err)
		}
		contents[i] = string(data)
		totalBytes += len(data)
	}

	b.ResetTimer()
	b.SetBytes(int64(totalBytes))

	for i := 0; i < b.N; i++ {
		for _, content := range contents {
			l := lexer.New(content)
			p := New(l)
			p.ParseProgram()
		}
	}
}

// BenchmarkCorpusParallel tests parallel parsing performance
func BenchmarkCorpusParallel(b *testing.B) {
	files, err := filepath.Glob(filepath.Join(corpusPath, "*.sql"))
	if err != nil || len(files) == 0 {
		b.Skip("corpus not available")
	}

	contents := make([]string, len(files))
	for i, f := range files {
		data, err := os.ReadFile(f)
		if err != nil {
			b.Fatalf("failed to read %s: %v", f, err)
		}
		contents[i] = string(data)
	}

	b.ResetTimer()
	b.RunParallel(func(pb *testing.PB) {
		idx := 0
		for pb.Next() {
			content := contents[idx%len(contents)]
			l := lexer.New(content)
			p := New(l)
			p.ParseProgram()
			idx++
		}
	})
}

// BenchmarkCorpusBySize benchmarks files grouped by size
func BenchmarkCorpusBySize(b *testing.B) {
	files, err := filepath.Glob(filepath.Join(corpusPath, "*.sql"))
	if err != nil || len(files) == 0 {
		b.Skip("corpus not available")
	}

	type fileInfo struct {
		name    string
		content string
		size    int
	}

	var allFiles []fileInfo
	for _, f := range files {
		data, err := os.ReadFile(f)
		if err != nil {
			continue
		}
		allFiles = append(allFiles, fileInfo{
			name:    filepath.Base(f),
			content: string(data),
			size:    len(data),
		})
	}

	// Sort by size
	sort.Slice(allFiles, func(i, j int) bool {
		return allFiles[i].size < allFiles[j].size
	})

	// Group: small (bottom 25%), medium (middle 50%), large (top 25%)
	n := len(allFiles)
	small := allFiles[:n/4]
	medium := allFiles[n/4 : 3*n/4]
	large := allFiles[3*n/4:]

	b.Run("Small", func(b *testing.B) {
		totalBytes := 0
		for _, f := range small {
			totalBytes += f.size
		}
		b.SetBytes(int64(totalBytes))
		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			for _, f := range small {
				l := lexer.New(f.content)
				p := New(l)
				p.ParseProgram()
			}
		}
	})

	b.Run("Medium", func(b *testing.B) {
		totalBytes := 0
		for _, f := range medium {
			totalBytes += f.size
		}
		b.SetBytes(int64(totalBytes))
		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			for _, f := range medium {
				l := lexer.New(f.content)
				p := New(l)
				p.ParseProgram()
			}
		}
	})

	b.Run("Large", func(b *testing.B) {
		totalBytes := 0
		for _, f := range large {
			totalBytes += f.size
		}
		b.SetBytes(int64(totalBytes))
		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			for _, f := range large {
				l := lexer.New(f.content)
				p := New(l)
				p.ParseProgram()
			}
		}
	})
}

// BenchmarkCorpusLargestFiles benchmarks the 5 largest files individually
func BenchmarkCorpusLargestFiles(b *testing.B) {
	files, err := filepath.Glob(filepath.Join(corpusPath, "*.sql"))
	if err != nil || len(files) == 0 {
		b.Skip("corpus not available")
	}

	type fileInfo struct {
		name    string
		content string
		size    int
	}

	var allFiles []fileInfo
	for _, f := range files {
		data, err := os.ReadFile(f)
		if err != nil {
			continue
		}
		allFiles = append(allFiles, fileInfo{
			name:    filepath.Base(f),
			content: string(data),
			size:    len(data),
		})
	}

	// Sort by size descending
	sort.Slice(allFiles, func(i, j int) bool {
		return allFiles[i].size > allFiles[j].size
	})

	// Benchmark top 5
	for i := 0; i < 5 && i < len(allFiles); i++ {
		f := allFiles[i]
		b.Run(f.name, func(b *testing.B) {
			b.SetBytes(int64(f.size))
			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				l := lexer.New(f.content)
				p := New(l)
				p.ParseProgram()
			}
		})
	}
}

// =============================================================================
// PART 3: Memory Allocation Benchmarks
// =============================================================================

func BenchmarkAllocSimpleSelect(b *testing.B) {
	input := `SELECT * FROM Customers WHERE ID = 1`
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
	}
}

func BenchmarkAllocComplexQuery(b *testing.B) {
	input := `
		WITH CTE AS (SELECT ID, Name FROM T WHERE Status = 'A')
		SELECT c.ID, c.Name, COUNT(*) AS Total
		FROM CTE c
		INNER JOIN Orders o ON c.ID = o.CustomerID
		WHERE o.Amount > 100
		GROUP BY c.ID, c.Name
		HAVING COUNT(*) > 5
		ORDER BY Total DESC
	`
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
	}
}

func BenchmarkAllocLargeStatement(b *testing.B) {
	// Generate a large INSERT with many rows
	var sb strings.Builder
	sb.WriteString("INSERT INTO T (A, B, C, D, E) VALUES ")
	for i := 0; i < 100; i++ {
		if i > 0 {
			sb.WriteString(", ")
		}
		sb.WriteString(fmt.Sprintf("(%d, 'value%d', %d.5, GETDATE(), NULL)", i, i, i))
	}
	input := sb.String()

	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		l := lexer.New(input)
		p := New(l)
		p.ParseProgram()
	}
}
