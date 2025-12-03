# tsqlparser

A T-SQL parser written in Go. Parses Microsoft SQL Server T-SQL syntax into an abstract syntax tree (AST).

## Features

- Parses T-SQL DDL and DML statements
- Supports stored procedures, functions, triggers, and views
- Handles complex queries with CTEs, window functions, subqueries
- Full support for JOINs, PIVOT/UNPIVOT, MERGE, and set operations
- Control flow statements (IF/ELSE, WHILE, TRY/CATCH)
- Transaction handling
- XML and JSON operations
- 96% pass rate on a corpus of 201 real-world T-SQL samples

## Installation

```bash
go get github.com/ha1tch/tsqlparser
```

## Usage

```go
package main

import (
    "fmt"
    "github.com/ha1tch/tsqlparser"
)

func main() {
    input := `SELECT CustomerID, Name FROM Customers WHERE Status = 'Active'`
    
    program, errors := tsqlparser.Parse(input)
    if len(errors) > 0 {
        for _, err := range errors {
            fmt.Println("Error:", err)
        }
        return
    }
    
    fmt.Println(program.String())
}
```

## Supported Statements

### DML
- SELECT (with all clauses, JOINs, subqueries, CTEs, window functions)
- INSERT (single row, multi-row, SELECT, EXEC, DEFAULT VALUES)
- UPDATE (with FROM, OUTPUT)
- DELETE (with FROM, OUTPUT)
- MERGE (all WHEN clauses)
- TRUNCATE TABLE

### DDL
- CREATE/ALTER/DROP TABLE
- CREATE/ALTER/DROP INDEX
- CREATE/ALTER/DROP VIEW
- CREATE/ALTER/DROP PROCEDURE
- CREATE/ALTER/DROP FUNCTION
- CREATE/ALTER/DROP TRIGGER
- CREATE/ALTER/DROP DATABASE
- CREATE/ALTER/DROP SCHEMA

### Control Flow
- IF/ELSE
- WHILE
- BEGIN/END
- TRY/CATCH
- GOTO
- RETURN
- BREAK/CONTINUE
- WAITFOR

### Transactions
- BEGIN/COMMIT/ROLLBACK TRANSACTION
- SAVE TRANSACTION

### Other
- DECLARE variables
- SET statements
- EXECUTE/EXEC
- Cursors (DECLARE, OPEN, FETCH, CLOSE, DEALLOCATE)
- GRANT/DENY/REVOKE
- BACKUP/RESTORE
- DBCC commands
- BULK INSERT

## Project Structure

```
tsqlparser/
├── token/          # Token types and keywords
├── lexer/          # Lexical analysis
├── ast/            # Abstract syntax tree nodes
├── parser/         # Recursive descent parser
├── testdata/       # 201 T-SQL sample files for integration testing
├── cmd/example/    # Example usage
├── tsqlparser.go   # Main API
└── go.mod
```

## Testing

Run all tests:

```bash
go test ./...
```

Run integration tests against the T-SQL corpus:

```bash
go test ./parser -run TestCorpusIntegration -v
```

Run a specific sample file:

```bash
go test ./parser -run TestCorpusSamples/001_error_handler -v
```

Run benchmarks:

```bash
go test ./parser -bench=.
```

Run corpus benchmarks:

```bash
go test ./parser -bench=Corpus -benchtime=1s
```

## Performance

- Simple SELECT: ~23 μs
- Complex query with JOINs: ~34 μs
- Full corpus (201 files, 1.6 MB): ~27 MB/s throughput

## License

Copyright (C) 2025 haitch

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

See <https://www.gnu.org/licenses/gpl-3.0.html> for the full license text.

## Contact

h@ual.fi
