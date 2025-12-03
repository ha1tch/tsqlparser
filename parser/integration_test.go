package parser

import (
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"

	"github.com/ha1tch/tsqlparser/lexer"
)

// TestCorpusIntegration runs the parser against all T-SQL sample files
// in the testdata directory. This is an integration test that verifies
// the parser handles real-world T-SQL patterns correctly.
func TestCorpusIntegration(t *testing.T) {
	corpusDir := "../testdata"
	
	files, err := filepath.Glob(filepath.Join(corpusDir, "*.sql"))
	if err != nil {
		t.Fatalf("failed to glob corpus directory: %v", err)
	}
	
	if len(files) == 0 {
		t.Skip("no corpus files found in testdata/")
	}
	
	sort.Strings(files)
	
	var passed, failed int
	var failures []string
	
	for _, file := range files {
		name := filepath.Base(file)
		
		content, err := os.ReadFile(file)
		if err != nil {
			t.Errorf("failed to read %s: %v", name, err)
			failed++
			continue
		}
		
		l := lexer.New(string(content))
		p := New(l)
		p.ParseProgram()
		
		if len(p.Errors()) > 0 {
			failed++
			failures = append(failures, name+": "+p.Errors()[0])
		} else {
			passed++
		}
	}
	
	total := passed + failed
	passRate := float64(passed) / float64(total) * 100
	
	t.Logf("Corpus Integration Test Results:")
	t.Logf("  Passed: %d/%d (%.1f%%)", passed, total, passRate)
	t.Logf("  Failed: %d", failed)
	
	if len(failures) > 0 {
		t.Logf("  Failures:")
		for _, f := range failures {
			t.Logf("    - %s", f)
		}
	}
	
	// We expect at least 95% pass rate
	if passRate < 95.0 {
		t.Errorf("pass rate %.1f%% is below 95%% threshold", passRate)
	}
}

// TestCorpusSamples runs individual subtests for each corpus file.
// This allows running specific files with -run flag:
//   go test -run TestCorpusSamples/001_error_handler
func TestCorpusSamples(t *testing.T) {
	// Known failures - these are documented edge cases
	knownFailures := map[string]bool{
		"110_unicode_identifiers.sql": true,
		"118_result_sets.sql":         true,
		"119_four_part_names.sql":     true,
		"120_fulltext_search.sql":     true,
		"122_openxml.sql":             true,
		"142_waitfor.sql":             true,
		"193_schema_operations.sql":   true,
		"198_identifiers.sql":         true,
	}
	
	corpusDir := "../testdata"
	
	files, err := filepath.Glob(filepath.Join(corpusDir, "*.sql"))
	if err != nil {
		t.Fatalf("failed to glob corpus directory: %v", err)
	}
	
	if len(files) == 0 {
		t.Skip("no corpus files found in testdata/")
	}
	
	sort.Strings(files)
	
	for _, file := range files {
		name := filepath.Base(file)
		testName := strings.TrimSuffix(name, ".sql")
		
		t.Run(testName, func(t *testing.T) {
			content, err := os.ReadFile(file)
			if err != nil {
				t.Fatalf("failed to read file: %v", err)
			}
			
			l := lexer.New(string(content))
			p := New(l)
			program := p.ParseProgram()
			
			if len(p.Errors()) > 0 {
				if knownFailures[name] {
					t.Skipf("known failure: %s", p.Errors()[0])
				}
				t.Errorf("parse error: %s", p.Errors()[0])
				return
			}
			
			// Verify we got at least one statement
			if len(program.Statements) == 0 {
				t.Error("parsed zero statements")
			}
		})
	}
}

// TestCorpusKnownFailures documents files that are expected to fail.
// These are edge cases or specialised features not yet supported.
func TestCorpusKnownFailures(t *testing.T) {
	knownFailures := map[string]string{
		"110_unicode_identifiers.sql": "bracket escaping [x]]y]",
		"118_result_sets.sql":         "EXEC RESULT SETS with COLLATE",
		"119_four_part_names.sql":     "EXEC AT with parameters",
		"120_fulltext_search.sql":     "CONTAINS PROPERTY syntax",
		"122_openxml.sql":             "OPENXML WITH schema",
		"142_waitfor.sql":             "Service Broker RECEIVE",
		"193_schema_operations.sql":   "CREATE SCHEMA inline objects",
		"198_identifiers.sql":         "bracket escaping",
	}
	
	corpusDir := "../testdata"
	
	for filename, reason := range knownFailures {
		t.Run(filename, func(t *testing.T) {
			path := filepath.Join(corpusDir, filename)
			
			content, err := os.ReadFile(path)
			if err != nil {
				t.Skipf("file not found: %s", filename)
				return
			}
			
			l := lexer.New(string(content))
			p := New(l)
			p.ParseProgram()
			
			if len(p.Errors()) == 0 {
				t.Logf("FIXED: %s now parses successfully (was: %s)", filename, reason)
			} else {
				t.Logf("Expected failure: %s - %s", reason, p.Errors()[0])
			}
		})
	}
}
