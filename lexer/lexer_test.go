package lexer

import (
	"testing"

	"github.com/ha1tch/tsqlparser/token"
)

func TestKeywordRecognition(t *testing.T) {
	tests := []struct {
		input    string
		expected token.Type
	}{
		{"SELECT", token.SELECT},
		{"NOCOUNT", token.NOCOUNT},
		{"SET", token.SET},
		{"ON", token.ON},
	}

	for _, tt := range tests {
		l := New(tt.input)
		tok := l.NextToken()
		if tok.Type != tt.expected {
			t.Errorf("input %q: expected token type %v, got %v (literal: %q)",
				tt.input, tt.expected, tok.Type, tok.Literal)
		}
	}
}

func TestSetNocount(t *testing.T) {
	input := "SET NOCOUNT ON"
	l := New(input)

	expected := []struct {
		typ     token.Type
		literal string
	}{
		{token.SET, "SET"},
		{token.NOCOUNT, "NOCOUNT"},
		{token.ON, "ON"},
		{token.EOF, ""},
	}

	for i, e := range expected {
		tok := l.NextToken()
		if tok.Type != e.typ {
			t.Errorf("token %d: expected type %v, got %v", i, e.typ, tok.Type)
		}
		if tok.Literal != e.literal {
			t.Errorf("token %d: expected literal %q, got %q", i, e.literal, tok.Literal)
		}
	}
}

func TestVariableTokens(t *testing.T) {
	input := "@x @@ROWCOUNT"
	l := New(input)

	tok := l.NextToken()
	if tok.Type != token.VARIABLE {
		t.Errorf("expected VARIABLE, got %v", tok.Type)
	}
	if tok.Literal != "@x" {
		t.Errorf("expected @x, got %q", tok.Literal)
	}

	tok = l.NextToken()
	if tok.Type != token.TEMPVAR {
		t.Errorf("expected TEMPVAR, got %v", tok.Type)
	}
	if tok.Literal != "@@ROWCOUNT" {
		t.Errorf("expected @@ROWCOUNT, got %q", tok.Literal)
	}
}

func TestStringLiterals(t *testing.T) {
	tests := []struct {
		input    string
		expected string
		unicode  bool
	}{
		{"'hello'", "hello", false},
		{"'it''s'", "it's", false},
		{"N'unicode'", "unicode", true},
	}

	for _, tt := range tests {
		l := New(tt.input)
		tok := l.NextToken()

		expectedType := token.STRING
		if tt.unicode {
			expectedType = token.NSTRING
		}

		if tok.Type != expectedType {
			t.Errorf("input %q: expected type %v, got %v", tt.input, expectedType, tok.Type)
		}
		if tok.Literal != tt.expected {
			t.Errorf("input %q: expected literal %q, got %q", tt.input, tt.expected, tok.Literal)
		}
	}
}

func TestOperators(t *testing.T) {
	input := "+ - * / = <> < > <= >= += -= != AND OR"
	l := New(input)

	expected := []token.Type{
		token.PLUS, token.MINUS, token.ASTERISK, token.SLASH,
		token.EQ, token.NEQ, token.LT, token.GT, token.LTE, token.GTE,
		token.PLUSEQ, token.MINUSEQ, token.NEQ, token.AND, token.OR,
	}

	for i, e := range expected {
		tok := l.NextToken()
		if tok.Type != e {
			t.Errorf("operator %d: expected %v, got %v (literal: %q)", i, e, tok.Type, tok.Literal)
		}
	}
}

func TestComments(t *testing.T) {
	input := `SELECT 1 -- line comment
/* block
comment */ SELECT 2`
	l := New(input)

	// SELECT
	tok := l.NextToken()
	if tok.Type != token.SELECT {
		t.Errorf("expected SELECT, got %v", tok.Type)
	}

	// 1
	tok = l.NextToken()
	if tok.Type != token.INT {
		t.Errorf("expected INT, got %v", tok.Type)
	}

	// Comment (line)
	tok = l.NextToken()
	if tok.Type != token.COMMENT {
		t.Errorf("expected COMMENT, got %v", tok.Type)
	}

	// Comment (block)
	tok = l.NextToken()
	if tok.Type != token.COMMENT {
		t.Errorf("expected COMMENT, got %v", tok.Type)
	}

	// SELECT
	tok = l.NextToken()
	if tok.Type != token.SELECT {
		t.Errorf("expected SELECT, got %v", tok.Type)
	}
}

// =============================================================================
// Extended Lexer Tests - Comprehensive Edge Case Coverage
// =============================================================================

func TestKeywordsComprehensive(t *testing.T) {
	// Test a broad sample of T-SQL keywords across categories
	tests := []struct {
		input    string
		expected token.Type
	}{
		// DML
		{"SELECT", token.SELECT},
		{"INSERT", token.INSERT},
		{"UPDATE", token.UPDATE},
		{"DELETE", token.DELETE},
		{"MERGE", token.MERGE},
		{"TRUNCATE", token.TRUNCATE},
		// DDL
		{"CREATE", token.CREATE},
		{"ALTER", token.ALTER},
		{"DROP", token.DROP},
		{"TABLE", token.TABLE},
		{"INDEX", token.INDEX},
		{"VIEW", token.VIEW},
		{"PROCEDURE", token.PROCEDURE},
		{"FUNCTION", token.FUNCTION},
		{"TRIGGER", token.TRIGGER},
		{"DATABASE", token.DATABASE},
		{"SCHEMA", token.SCHEMA},
		// Clauses
		{"FROM", token.FROM},
		{"WHERE", token.WHERE},
		{"ORDER", token.ORDER},
		{"GROUP", token.GROUP},
		{"HAVING", token.HAVING},
		{"JOIN", token.JOIN},
		{"INNER", token.INNER},
		{"LEFT", token.LEFT},
		{"RIGHT", token.RIGHT},
		{"OUTER", token.OUTER},
		{"CROSS", token.CROSS},
		{"UNION", token.UNION},
		{"EXCEPT", token.EXCEPT},
		{"INTERSECT", token.INTERSECT},
		// Control flow
		{"IF", token.IF},
		{"ELSE", token.ELSE},
		{"WHILE", token.WHILE},
		{"BEGIN", token.BEGIN},
		{"END", token.END},
		{"RETURN", token.RETURN},
		{"BREAK", token.BREAK},
		{"CONTINUE", token.CONTINUE},
		{"GOTO", token.GOTO},
		{"TRY", token.TRY},
		{"CATCH", token.CATCH},
		{"THROW", token.THROW},
		// Transactions
		{"TRANSACTION", token.TRANSACTION},
		{"COMMIT", token.COMMIT},
		{"ROLLBACK", token.ROLLBACK},
		// Expressions
		{"AND", token.AND},
		{"OR", token.OR},
		{"NOT", token.NOT},
		{"IN", token.IN},
		{"EXISTS", token.EXISTS},
		{"BETWEEN", token.BETWEEN},
		{"LIKE", token.LIKE},
		{"IS", token.IS},
		{"NULL", token.NULL},
		{"CASE", token.CASE},
		{"WHEN", token.WHEN},
		{"THEN", token.THEN},
		{"CAST", token.CAST},
		{"CONVERT", token.CONVERT},
		// Data types
		{"INT", token.INT_TYPE},
		{"VARCHAR", token.VARCHAR},
		{"NVARCHAR", token.NVARCHAR},
		{"DATETIME", token.DATETIME},
		{"DECIMAL", token.DECIMAL},
		{"FLOAT", token.FLOAT_TYPE},
		{"BIT", token.BIT},
		{"UNIQUEIDENTIFIER", token.UNIQUEIDENTIFIER},
		{"XML", token.XML},
		// Constraints
		{"PRIMARY", token.PRIMARY},
		{"FOREIGN", token.FOREIGN},
		{"REFERENCES", token.REFERENCES},
		{"UNIQUE", token.UNIQUE},
		{"CHECK", token.CHECK},
		{"CONSTRAINT", token.CONSTRAINT},
		// Case insensitivity
		{"select", token.SELECT},
		{"Select", token.SELECT},
		{"sElEcT", token.SELECT},
	}

	for _, tt := range tests {
		l := New(tt.input)
		tok := l.NextToken()
		if tok.Type != tt.expected {
			t.Errorf("input %q: expected %v, got %v", tt.input, tt.expected, tok.Type)
		}
	}
}

func TestNumericLiterals(t *testing.T) {
	tests := []struct {
		input       string
		expectedTyp token.Type
		expectedLit string
	}{
		// Integers
		{"0", token.INT, "0"},
		{"123", token.INT, "123"},
		{"999999999", token.INT, "999999999"},
		// Floats
		{"3.14", token.FLOAT, "3.14"},
		{"0.5", token.FLOAT, "0.5"},
		{".5", token.FLOAT, ".5"},
		{"123.456", token.FLOAT, "123.456"},
		// Scientific notation
		{"1e10", token.FLOAT, "1e10"},
		{"1E10", token.FLOAT, "1E10"},
		{"1.5e-3", token.FLOAT, "1.5e-3"},
		{"2.5E+10", token.FLOAT, "2.5E+10"},
		// Hex/binary literals
		{"0x1A", token.BINARY, "0x1A"},
		{"0xFF", token.BINARY, "0xFF"},
		{"0x0", token.BINARY, "0x0"},
		{"0xDEADBEEF", token.BINARY, "0xDEADBEEF"},
		// Money literals
		{"$100", token.MONEY_LIT, "$100"},
		{"$99.99", token.MONEY_LIT, "$99.99"},
		{"$0.01", token.MONEY_LIT, "$0.01"},
	}

	for _, tt := range tests {
		l := New(tt.input)
		tok := l.NextToken()
		if tok.Type != tt.expectedTyp {
			t.Errorf("input %q: expected type %v, got %v", tt.input, tt.expectedTyp, tok.Type)
		}
		if tok.Literal != tt.expectedLit {
			t.Errorf("input %q: expected literal %q, got %q", tt.input, tt.expectedLit, tok.Literal)
		}
	}
}

func TestBracketedIdentifiers(t *testing.T) {
	tests := []struct {
		input       string
		expectedLit string
	}{
		{"[TableName]", "TableName"},
		{"[Column Name]", "Column Name"},
		{"[SELECT]", "SELECT"},           // Reserved word as identifier
		{"[My Table!@#]", "My Table!@#"}, // Special characters
		{"[123Start]", "123Start"},       // Starts with number
		{"[]", ""},                       // Empty (edge case)
	}

	for _, tt := range tests {
		l := New(tt.input)
		tok := l.NextToken()
		if tok.Type != token.IDENT {
			t.Errorf("input %q: expected IDENT, got %v", tt.input, tok.Type)
		}
		if tok.Literal != tt.expectedLit {
			t.Errorf("input %q: expected literal %q, got %q", tt.input, tt.expectedLit, tok.Literal)
		}
	}
}

func TestQuotedIdentifiers(t *testing.T) {
	tests := []struct {
		input       string
		expectedLit string
	}{
		{`"TableName"`, "TableName"},
		{`"Column Name"`, "Column Name"},
		{`"SELECT"`, "SELECT"},
	}

	for _, tt := range tests {
		l := New(tt.input)
		tok := l.NextToken()
		if tok.Type != token.IDENT {
			t.Errorf("input %q: expected IDENT, got %v", tt.input, tok.Type)
		}
		if tok.Literal != tt.expectedLit {
			t.Errorf("input %q: expected literal %q, got %q", tt.input, tt.expectedLit, tok.Literal)
		}
	}
}

func TestStringLiteralsExtended(t *testing.T) {
	tests := []struct {
		input       string
		expectedTyp token.Type
		expectedLit string
	}{
		// Basic strings
		{"'hello'", token.STRING, "hello"},
		{"''", token.STRING, ""},       // Empty string
		{"'   '", token.STRING, "   "}, // Whitespace only
		// Escaped quotes
		{"'it''s'", token.STRING, "it's"},
		{"'don''t'", token.STRING, "don't"},
		{"''''", token.STRING, "'"},          // Just an escaped quote
		{"'a''b''c'", token.STRING, "a'b'c"}, // Multiple escapes
		// Unicode strings
		{"N'hello'", token.NSTRING, "hello"},
		{"N''", token.NSTRING, ""},
		{"N'café'", token.NSTRING, "café"},
		{"N'日本語'", token.NSTRING, "日本語"},
		{"N'it''s'", token.NSTRING, "it's"},
		// Case variations
		{"n'unicode'", token.NSTRING, "unicode"},
	}

	for _, tt := range tests {
		l := New(tt.input)
		tok := l.NextToken()
		if tok.Type != tt.expectedTyp {
			t.Errorf("input %q: expected type %v, got %v", tt.input, tt.expectedTyp, tok.Type)
		}
		if tok.Literal != tt.expectedLit {
			t.Errorf("input %q: expected literal %q, got %q", tt.input, tt.expectedLit, tok.Literal)
		}
	}
}

func TestBinaryLiterals(t *testing.T) {
	tests := []struct {
		input       string
		expectedLit string
	}{
		{"0x00", "0x00"},
		{"0xFF", "0xFF"},
		{"0xDEADBEEF", "0xDEADBEEF"},
		{"0x0123456789ABCDEF", "0x0123456789ABCDEF"},
	}

	for _, tt := range tests {
		l := New(tt.input)
		tok := l.NextToken()
		if tok.Type != token.BINARY {
			t.Errorf("input %q: expected BINARY, got %v", tt.input, tok.Type)
		}
		if tok.Literal != tt.expectedLit {
			t.Errorf("input %q: expected literal %q, got %q", tt.input, tt.expectedLit, tok.Literal)
		}
	}
}

func TestBitwiseOperators(t *testing.T) {
	input := "& | ^ ~"
	l := New(input)

	expected := []struct {
		typ     token.Type
		literal string
	}{
		{token.AMPERSAND, "&"},
		{token.PIPE, "|"},
		{token.CARET, "^"},
		{token.TILDE, "~"},
	}

	for i, e := range expected {
		tok := l.NextToken()
		if tok.Type != e.typ {
			t.Errorf("token %d: expected %v, got %v", i, e.typ, tok.Type)
		}
		if tok.Literal != e.literal {
			t.Errorf("token %d: expected %q, got %q", i, e.literal, tok.Literal)
		}
	}
}

func TestCompoundOperators(t *testing.T) {
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
		{"<>", token.NEQ},
		{"!=", token.NEQ},
		{"<=", token.LTE},
		{">=", token.GTE},
		{"::", token.SCOPE},
	}

	for _, tt := range tests {
		l := New(tt.input)
		tok := l.NextToken()
		if tok.Type != tt.expected {
			t.Errorf("input %q: expected %v, got %v", tt.input, tt.expected, tok.Type)
		}
	}
}

func TestPunctuation(t *testing.T) {
	input := "( ) , ; . : ="
	l := New(input)

	expected := []token.Type{
		token.LPAREN, token.RPAREN,
		token.COMMA, token.SEMICOLON,
		token.DOT, token.COLON, token.EQ,
	}

	for i, e := range expected {
		tok := l.NextToken()
		if tok.Type != e {
			t.Errorf("token %d: expected %v, got %v (literal: %q)", i, e, tok.Type, tok.Literal)
		}
	}
}

func TestVariablesExtended(t *testing.T) {
	tests := []struct {
		input       string
		expectedTyp token.Type
		expectedLit string
	}{
		// Local variables
		{"@x", token.VARIABLE, "@x"},
		{"@MyVar", token.VARIABLE, "@MyVar"},
		{"@my_var", token.VARIABLE, "@my_var"},
		{"@var123", token.VARIABLE, "@var123"},
		{"@_underscore", token.VARIABLE, "@_underscore"},
		// System variables
		{"@@ROWCOUNT", token.TEMPVAR, "@@ROWCOUNT"},
		{"@@IDENTITY", token.TEMPVAR, "@@IDENTITY"},
		{"@@ERROR", token.TEMPVAR, "@@ERROR"},
		{"@@TRANCOUNT", token.TEMPVAR, "@@TRANCOUNT"},
		{"@@SPID", token.TEMPVAR, "@@SPID"},
		{"@@VERSION", token.TEMPVAR, "@@VERSION"},
		{"@@FETCH_STATUS", token.TEMPVAR, "@@FETCH_STATUS"},
	}

	for _, tt := range tests {
		l := New(tt.input)
		tok := l.NextToken()
		if tok.Type != tt.expectedTyp {
			t.Errorf("input %q: expected type %v, got %v", tt.input, tt.expectedTyp, tok.Type)
		}
		if tok.Literal != tt.expectedLit {
			t.Errorf("input %q: expected literal %q, got %q", tt.input, tt.expectedLit, tok.Literal)
		}
	}
}

func TestTempTableIdentifiers(t *testing.T) {
	tests := []struct {
		input       string
		expectedLit string
	}{
		{"#temp", "#temp"},
		{"#MyTempTable", "#MyTempTable"},
		{"##GlobalTemp", "##GlobalTemp"},
		{"#temp_table_1", "#temp_table_1"},
	}

	for _, tt := range tests {
		l := New(tt.input)
		tok := l.NextToken()
		if tok.Type != token.IDENT {
			t.Errorf("input %q: expected IDENT, got %v", tt.input, tok.Type)
		}
		if tok.Literal != tt.expectedLit {
			t.Errorf("input %q: expected literal %q, got %q", tt.input, tt.expectedLit, tok.Literal)
		}
	}
}

func TestCompoundKeywords(t *testing.T) {
	// Test that multi-word constructs tokenise correctly
	// Note: Most T-SQL doesn't use compound tokens - parser handles combinations
	tests := []struct {
		input    string
		expected []token.Type
	}{
		{"IS NULL", []token.Type{token.IS, token.NULL}},
		{"IS NOT NULL", []token.Type{token.IS, token.NOT, token.NULL}},
		{"NOT IN", []token.Type{token.NOT, token.IN}},
		{"NOT LIKE", []token.Type{token.NOT, token.LIKE}},
		{"NOT EXISTS", []token.Type{token.NOT, token.EXISTS}},
		{"NOT BETWEEN", []token.Type{token.NOT, token.BETWEEN}},
		{"LEFT OUTER JOIN", []token.Type{token.LEFT, token.OUTER, token.JOIN}},
		{"INNER JOIN", []token.Type{token.INNER, token.JOIN}},
		{"GROUP BY", []token.Type{token.GROUP, token.BY}},
		{"ORDER BY", []token.Type{token.ORDER, token.BY}},
	}

	for _, tt := range tests {
		l := New(tt.input)
		for i, expectedType := range tt.expected {
			tok := l.NextToken()
			if tok.Type != expectedType {
				t.Errorf("input %q token %d: expected %v, got %v", tt.input, i, expectedType, tok.Type)
			}
		}
	}
}

func TestLineColumnTracking(t *testing.T) {
	input := `SELECT
  col1,
  col2
FROM t`
	l := New(input)

	expected := []struct {
		typ  token.Type
		line int
		col  int
	}{
		{token.SELECT, 1, 1},
		{token.IDENT, 2, 3}, // col1
		{token.COMMA, 2, 7},
		{token.IDENT, 3, 3}, // col2
		{token.FROM, 4, 1},
		{token.IDENT, 4, 6}, // t
	}

	for i, e := range expected {
		tok := l.NextToken()
		if tok.Type != e.typ {
			t.Errorf("token %d: expected type %v, got %v", i, e.typ, tok.Type)
		}
		if tok.Line != e.line {
			t.Errorf("token %d (%v): expected line %d, got %d", i, tok.Literal, e.line, tok.Line)
		}
		if tok.Column != e.col {
			t.Errorf("token %d (%v): expected column %d, got %d", i, tok.Literal, e.col, tok.Column)
		}
	}
}

func TestNestedComments(t *testing.T) {
	input := `/* outer /* inner */ still outer */ SELECT`
	l := New(input)

	tok := l.NextToken()
	if tok.Type != token.COMMENT {
		t.Errorf("expected COMMENT, got %v", tok.Type)
	}

	tok = l.NextToken()
	if tok.Type != token.SELECT {
		t.Errorf("expected SELECT after nested comment, got %v", tok.Type)
	}
}

func TestLabelSyntax(t *testing.T) {
	// Labels are identifier followed by colon - parser combines them
	input := `MyLabel: GOTO MyLabel`
	l := New(input)

	// Label identifier
	tok := l.NextToken()
	if tok.Type != token.IDENT {
		t.Errorf("expected IDENT, got %v", tok.Type)
	}
	if tok.Literal != "MyLabel" {
		t.Errorf("expected literal 'MyLabel', got %q", tok.Literal)
	}

	// Colon
	tok = l.NextToken()
	if tok.Type != token.COLON {
		t.Errorf("expected COLON, got %v", tok.Type)
	}

	// GOTO
	tok = l.NextToken()
	if tok.Type != token.GOTO {
		t.Errorf("expected GOTO, got %v", tok.Type)
	}

	// Target (identifier)
	tok = l.NextToken()
	if tok.Type != token.IDENT {
		t.Errorf("expected IDENT, got %v", tok.Type)
	}
}

func TestWhitespaceHandling(t *testing.T) {
	// Various whitespace: space, tab, newline, carriage return
	input := "SELECT\t\t1\r\n,\n2"
	l := New(input)

	expected := []token.Type{
		token.SELECT, token.INT, token.COMMA, token.INT,
	}

	for i, e := range expected {
		tok := l.NextToken()
		if tok.Type != e {
			t.Errorf("token %d: expected %v, got %v", i, e, tok.Type)
		}
	}
}

func TestSpecialCasesEdgeCases(t *testing.T) {
	tests := []struct {
		input string
		desc  string
		check func(t *testing.T, tok token.Token)
	}{
		{
			"...",
			"Multiple dots",
			func(t *testing.T, tok token.Token) {
				if tok.Type != token.DOT {
					t.Errorf("expected DOT, got %v", tok.Type)
				}
			},
		},
		{
			"N'test'",
			"Unicode string prefix",
			func(t *testing.T, tok token.Token) {
				if tok.Type != token.NSTRING {
					t.Errorf("expected NSTRING, got %v", tok.Type)
				}
			},
		},
		{
			"GO",
			"Batch separator",
			func(t *testing.T, tok token.Token) {
				if tok.Type != token.GO {
					t.Errorf("expected GO, got %v", tok.Type)
				}
			},
		},
	}

	for _, tt := range tests {
		l := New(tt.input)
		tok := l.NextToken()
		tt.check(t, tok)
	}
}

func TestCompleteStatement(t *testing.T) {
	input := `SELECT TOP 10 c.CustomerID, c.Name, SUM(o.Amount) AS Total
FROM Customers c
INNER JOIN Orders o ON c.CustomerID = o.CustomerID
WHERE o.OrderDate >= '2023-01-01'
GROUP BY c.CustomerID, c.Name
HAVING SUM(o.Amount) > 1000
ORDER BY Total DESC;`

	l := New(input)

	// Just verify we can tokenise the whole thing without errors
	tokenCount := 0
	for {
		tok := l.NextToken()
		if tok.Type == token.EOF {
			break
		}
		if tok.Type == token.ILLEGAL {
			t.Errorf("unexpected ILLEGAL token at position %d: %q", tokenCount, tok.Literal)
		}
		tokenCount++
	}

	if tokenCount < 40 {
		t.Errorf("expected at least 40 tokens, got %d", tokenCount)
	}
}

func TestEmptyInput(t *testing.T) {
	l := New("")
	tok := l.NextToken()
	if tok.Type != token.EOF {
		t.Errorf("expected EOF for empty input, got %v", tok.Type)
	}
}

func TestWhitespaceOnlyInput(t *testing.T) {
	l := New("   \t\n\r\n   ")
	tok := l.NextToken()
	if tok.Type != token.EOF {
		t.Errorf("expected EOF for whitespace-only input, got %v", tok.Type)
	}
}

func TestCommentOnlyInput(t *testing.T) {
	l := New("-- just a comment")
	tok := l.NextToken()
	if tok.Type != token.COMMENT {
		t.Errorf("expected COMMENT, got %v", tok.Type)
	}
	tok = l.NextToken()
	if tok.Type != token.EOF {
		t.Errorf("expected EOF after comment, got %v", tok.Type)
	}
}
