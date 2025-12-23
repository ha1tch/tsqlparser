.PHONY: test test-all test-quick test-parser test-lexer test-integration test-benchmark bench clean fmt lint vet coverage help

# Run all tests (default)
test:
	go test ./...

# Verbose test output
test-v:
	go test -v ./...

# Alias for test
test-all: test

# Quick smoke test for fast feedback
test-quick:
	go test -v ./parser/... -run "TestSelectStatement|TestJoinClause|TestTableHints" -count=1

# Parser tests only
test-parser:
	go test -v ./parser/...

# Lexer tests only
test-lexer:
	go test -v ./lexer/...

# Integration tests (parse all testdata files)
test-integration:
	go test -v ./parser/... -run TestIntegration

# Table hints tests (comprehensive)
test-hints:
	go test -v ./parser/... -run "TestTableHints"

# Run benchmarks
bench:
	go test -bench=. -benchmem ./parser/...

test-benchmark: bench

# Run benchmarks with comparison baseline
bench-baseline:
	go test -bench=. -benchmem ./parser/... | tee bench.txt

bench-compare:
	go test -bench=. -benchmem ./parser/... | tee bench-new.txt
	@echo "Compare with: benchstat bench.txt bench-new.txt"

# Test coverage
coverage:
	go test -coverprofile=coverage.out ./...
	go tool cover -html=coverage.out -o coverage.html
	@echo "Coverage report: coverage.html"

coverage-func:
	go test -coverprofile=coverage.out ./...
	go tool cover -func=coverage.out

# Format code
fmt:
	go fmt ./...
	gofmt -s -w .

# Lint
lint: vet
	@echo "Lint complete"

vet:
	go vet ./...

# Clean generated files
clean:
	rm -f coverage.out coverage.html
	rm -f bench.txt bench-new.txt

# Parse a single file (usage: make parse FILE=testdata/001_error_handler_sp.sql)
parse:
	@if [ -z "$(FILE)" ]; then \
		echo "Usage: make parse FILE=path/to/file.sql"; \
		exit 1; \
	fi
	go run cmd/example/main.go "$(FILE)"

# Parse all testdata files and report success/failure counts
parse-all:
	@echo "Parsing all testdata files..."
	@pass=0; fail=0; \
	for f in testdata/*.sql; do \
		if go run cmd/example/main.go "$$f" > /dev/null 2>&1; then \
			pass=$$((pass + 1)); \
		else \
			echo "FAIL: $$f"; \
			fail=$$((fail + 1)); \
		fi; \
	done; \
	echo ""; \
	echo "Results: $$pass passed, $$fail failed"

# Count lines of code
loc:
	@echo "Lines of code by package:"
	@wc -l ast/ast.go | awk '{print "  ast:    " $$1}'
	@wc -l lexer/lexer.go | awk '{print "  lexer:  " $$1}'
	@wc -l parser/parser.go | awk '{print "  parser: " $$1}'
	@wc -l token/token.go | awk '{print "  token:  " $$1}'
	@echo ""
	@echo "Test files:"
	@wc -l parser/*_test.go | tail -1 | awk '{print "  parser tests: " $$1}'
	@wc -l lexer/*_test.go | tail -1 | awk '{print "  lexer tests:  " $$1}'
	@echo ""
	@echo "Testdata SQL files: $$(ls -1 testdata/*.sql 2>/dev/null | wc -l)"

# Show help
help:
	@echo "tsqlparser - T-SQL Parser for Go"
	@echo ""
	@echo "Testing:"
	@echo "  make test             Run all tests (default)"
	@echo "  make test-v           Run all tests with verbose output"
	@echo "  make test-quick       Quick smoke test (~3 tests)"
	@echo "  make test-parser      Run parser tests only"
	@echo "  make test-lexer       Run lexer tests only"
	@echo "  make test-integration Run integration tests (parse testdata)"
	@echo "  make test-hints       Run table hints tests"
	@echo ""
	@echo "Benchmarks:"
	@echo "  make bench            Run benchmarks"
	@echo "  make bench-baseline   Run benchmarks and save to bench.txt"
	@echo "  make bench-compare    Run benchmarks and compare with baseline"
	@echo ""
	@echo "Coverage:"
	@echo "  make coverage         Generate HTML coverage report"
	@echo "  make coverage-func    Show coverage by function"
	@echo ""
	@echo "Code Quality:"
	@echo "  make fmt              Format Go code"
	@echo "  make lint             Run go vet"
	@echo ""
	@echo "Utilities:"
	@echo "  make parse FILE=x.sql Parse a single SQL file"
	@echo "  make parse-all        Parse all testdata files"
	@echo "  make loc              Count lines of code"
	@echo "  make clean            Remove generated files"