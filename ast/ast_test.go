package ast

import (
	"strings"
	"testing"

	"github.com/ha1tch/tsqlparser/token"
)

// TestProgramMethods tests Program methods
func TestProgramMethods(t *testing.T) {
	// Empty program
	prog := &Program{}
	if prog.TokenLiteral() != "" {
		t.Errorf("empty program should return empty TokenLiteral")
	}
	if prog.String() != "" {
		t.Errorf("empty program should return empty String")
	}

	// Program with statement
	prog = &Program{
		Statements: []Statement{
			&SelectStatement{Token: token.Token{Literal: "SELECT"}},
		},
	}
	if prog.TokenLiteral() != "SELECT" {
		t.Errorf("expected SELECT, got %s", prog.TokenLiteral())
	}
}

// TestIdentifierMethods tests Identifier methods
func TestIdentifierMethods(t *testing.T) {
	id := &Identifier{
		Token: token.Token{Type: token.IDENT, Literal: "MyColumn"},
		Value: "MyColumn",
	}

	id.expressionNode()

	if id.TokenLiteral() != "MyColumn" {
		t.Errorf("expected MyColumn, got %s", id.TokenLiteral())
	}
	if id.String() != "MyColumn" {
		t.Errorf("expected MyColumn, got %s", id.String())
	}
}

// TestQualifiedIdentifierMethods tests QualifiedIdentifier methods
func TestQualifiedIdentifierMethods(t *testing.T) {
	// Empty
	empty := &QualifiedIdentifier{}
	empty.expressionNode()
	if empty.TokenLiteral() != "" {
		t.Errorf("empty QualifiedIdentifier should return empty TokenLiteral")
	}

	// With parts
	qi := &QualifiedIdentifier{
		Parts: []*Identifier{
			{Token: token.Token{Literal: "schema"}, Value: "schema"},
			{Token: token.Token{Literal: "table"}, Value: "table"},
		},
	}
	if qi.String() != "schema.table" {
		t.Errorf("expected schema.table, got %s", qi.String())
	}
	if qi.TokenLiteral() != "schema" {
		t.Errorf("expected schema, got %s", qi.TokenLiteral())
	}
}

// TestVariableMethods tests Variable methods
func TestVariableMethods(t *testing.T) {
	v := &Variable{
		Token: token.Token{Type: token.VARIABLE, Literal: "@x"},
		Name:  "@x",
	}

	v.expressionNode()

	if v.TokenLiteral() != "@x" {
		t.Errorf("expected @x, got %s", v.TokenLiteral())
	}
	if v.String() != "@x" {
		t.Errorf("expected @x, got %s", v.String())
	}
}

// TestLiteralMethods tests various literal types
func TestLiteralMethods(t *testing.T) {
	// Integer
	il := &IntegerLiteral{Token: token.Token{Literal: "42"}, Value: 42}
	il.expressionNode()
	if il.TokenLiteral() != "42" {
		t.Error("IntegerLiteral TokenLiteral failed")
	}

	// Float
	fl := &FloatLiteral{Token: token.Token{Literal: "3.14"}, Value: 3.14}
	fl.expressionNode()
	if fl.TokenLiteral() != "3.14" {
		t.Error("FloatLiteral TokenLiteral failed")
	}

	// String
	sl := &StringLiteral{Token: token.Token{Literal: "'hello'"}, Value: "hello"}
	sl.expressionNode()
	if !strings.Contains(sl.String(), "hello") {
		t.Error("StringLiteral String failed")
	}

	// Unicode String
	us := &StringLiteral{Token: token.Token{Literal: "N'hello'"}, Value: "hello", Unicode: true}
	if !strings.HasPrefix(us.String(), "N'") {
		t.Error("Unicode StringLiteral String failed")
	}

	// Null
	nl := &NullLiteral{Token: token.Token{Literal: "NULL"}}
	nl.expressionNode()
	if nl.String() != "NULL" {
		t.Error("NullLiteral String failed")
	}

	// Binary
	bl := &BinaryLiteral{Token: token.Token{Literal: "0xDEAD"}, Value: "0xDEAD"}
	bl.expressionNode()
	if bl.String() != "0xDEAD" {
		t.Error("BinaryLiteral String failed")
	}

	// Money
	ml := &MoneyLiteral{Token: token.Token{Literal: "$100"}, Value: "$100"}
	ml.expressionNode()
	if ml.String() != "$100" {
		t.Error("MoneyLiteral String failed")
	}
}

// TestPrefixExpressionMethods tests PrefixExpression methods
func TestPrefixExpressionMethods(t *testing.T) {
	pe := &PrefixExpression{
		Token:    token.Token{Literal: "-"},
		Operator: "-",
		Right:    &IntegerLiteral{Token: token.Token{Literal: "5"}, Value: 5},
	}

	pe.expressionNode()

	if pe.TokenLiteral() != "-" {
		t.Error("PrefixExpression TokenLiteral failed")
	}
	if !strings.Contains(pe.String(), "-") {
		t.Error("PrefixExpression String failed")
	}
}

// TestInfixExpressionMethods tests InfixExpression methods
func TestInfixExpressionMethods(t *testing.T) {
	ie := &InfixExpression{
		Token:    token.Token{Literal: "+"},
		Left:     &IntegerLiteral{Token: token.Token{Literal: "1"}, Value: 1},
		Operator: "+",
		Right:    &IntegerLiteral{Token: token.Token{Literal: "2"}, Value: 2},
	}

	ie.expressionNode()

	if ie.TokenLiteral() != "+" {
		t.Error("InfixExpression TokenLiteral failed")
	}
	result := ie.String()
	if !strings.Contains(result, "+") {
		t.Error("InfixExpression String failed")
	}
}

// TestBetweenExpressionMethods tests BetweenExpression methods
func TestBetweenExpressionMethods(t *testing.T) {
	be := &BetweenExpression{
		Token: token.Token{Literal: "BETWEEN"},
		Expr:  &Identifier{Value: "x"},
		Low:   &IntegerLiteral{Token: token.Token{Literal: "1"}, Value: 1},
		High:  &IntegerLiteral{Token: token.Token{Literal: "10"}, Value: 10},
		Not:   false,
	}

	be.expressionNode()

	if be.TokenLiteral() != "BETWEEN" {
		t.Error("BetweenExpression TokenLiteral failed")
	}
	if !strings.Contains(be.String(), "BETWEEN") {
		t.Error("BetweenExpression String failed")
	}

	// NOT BETWEEN
	be.Not = true
	if !strings.Contains(be.String(), "NOT") {
		t.Error("BetweenExpression NOT String failed")
	}
}

// TestInExpressionMethods tests InExpression methods
func TestInExpressionMethods(t *testing.T) {
	// With values
	ie := &InExpression{
		Token: token.Token{Literal: "IN"},
		Expr:  &Identifier{Value: "status"},
		Values: []Expression{
			&StringLiteral{Token: token.Token{Literal: "'A'"}, Value: "A"},
		},
		Not: false,
	}

	ie.expressionNode()

	if ie.TokenLiteral() != "IN" {
		t.Error("InExpression TokenLiteral failed")
	}
	if !strings.Contains(ie.String(), "IN") {
		t.Error("InExpression String failed")
	}

	// NOT IN
	ie.Not = true
	if !strings.Contains(ie.String(), "NOT") {
		t.Error("InExpression NOT String failed")
	}

	// With subquery
	ie2 := &InExpression{
		Token: token.Token{Literal: "IN"},
		Expr:  &Identifier{Value: "id"},
		Subquery: &SelectStatement{
			Token:   token.Token{Literal: "SELECT"},
			Columns: []SelectColumn{{Expression: &Identifier{Value: "x"}}},
		},
	}
	if !strings.Contains(ie2.String(), "IN") {
		t.Error("InExpression with subquery String failed")
	}
}

// TestLikeExpressionMethods tests LikeExpression methods
func TestLikeExpressionMethods(t *testing.T) {
	le := &LikeExpression{
		Token:   token.Token{Literal: "LIKE"},
		Expr:    &Identifier{Value: "name"},
		Pattern: &StringLiteral{Token: token.Token{Literal: "'%test%'"}, Value: "%test%"},
		Not:     false,
	}

	le.expressionNode()

	if le.TokenLiteral() != "LIKE" {
		t.Error("LikeExpression TokenLiteral failed")
	}
	if !strings.Contains(le.String(), "LIKE") {
		t.Error("LikeExpression String failed")
	}

	// With ESCAPE
	le.Escape = &StringLiteral{Token: token.Token{Literal: "'\\'"}, Value: "\\"}
	if !strings.Contains(le.String(), "ESCAPE") {
		t.Error("LikeExpression ESCAPE String failed")
	}

	// NOT LIKE
	le.Not = true
	le.Escape = nil
	if !strings.Contains(le.String(), "NOT") {
		t.Error("LikeExpression NOT String failed")
	}
}

// TestIsNullExpressionMethods tests IsNullExpression methods
func TestIsNullExpressionMethods(t *testing.T) {
	ine := &IsNullExpression{
		Token: token.Token{Literal: "IS"},
		Expr:  &Identifier{Value: "x"},
		Not:   false,
	}

	ine.expressionNode()

	if ine.TokenLiteral() != "IS" {
		t.Error("IsNullExpression TokenLiteral failed")
	}
	if !strings.Contains(ine.String(), "NULL") {
		t.Error("IsNullExpression String failed")
	}

	// IS NOT NULL
	ine.Not = true
	if !strings.Contains(ine.String(), "NOT") {
		t.Error("IsNullExpression NOT String failed")
	}
}

// TestCaseExpressionMethods tests CaseExpression methods
func TestCaseExpressionMethods(t *testing.T) {
	ce := &CaseExpression{
		Token: token.Token{Literal: "CASE"},
		WhenClauses: []*WhenClause{
			{
				Condition: &Identifier{Value: "cond"},
				Result:    &StringLiteral{Token: token.Token{Literal: "'one'"}, Value: "one"},
			},
		},
		ElseClause: &StringLiteral{Token: token.Token{Literal: "'other'"}, Value: "other"},
	}

	ce.expressionNode()

	if ce.TokenLiteral() != "CASE" {
		t.Error("CaseExpression TokenLiteral failed")
	}
	result := ce.String()
	if !strings.Contains(result, "CASE") {
		t.Error("CaseExpression String missing CASE")
	}
	if !strings.Contains(result, "WHEN") {
		t.Error("CaseExpression String missing WHEN")
	}
	if !strings.Contains(result, "END") {
		t.Error("CaseExpression String missing END")
	}

	// With operand
	ce.Operand = &Identifier{Value: "status"}
	result = ce.String()
	if !strings.Contains(result, "status") {
		t.Error("CaseExpression with operand String failed")
	}
}

// TestFunctionCallMethods tests FunctionCall methods
func TestFunctionCallMethods(t *testing.T) {
	fc := &FunctionCall{
		Token:    token.Token{Literal: "COUNT"},
		Function: &Identifier{Value: "COUNT"},
		Arguments: []Expression{
			&Identifier{Value: "*"},
		},
	}

	fc.expressionNode()

	if fc.TokenLiteral() != "COUNT" {
		t.Error("FunctionCall TokenLiteral failed")
	}
	if !strings.Contains(fc.String(), "COUNT") {
		t.Error("FunctionCall String failed")
	}
}

// TestSelectStatementMethods tests SelectStatement methods
func TestSelectStatementMethods(t *testing.T) {
	stmt := &SelectStatement{
		Token: token.Token{Type: token.SELECT, Literal: "SELECT"},
		Columns: []SelectColumn{
			{Expression: &Identifier{Value: "a"}},
		},
	}

	stmt.statementNode()

	if stmt.TokenLiteral() != "SELECT" {
		t.Error("SelectStatement TokenLiteral failed")
	}
	if !strings.Contains(stmt.String(), "SELECT") {
		t.Error("SelectStatement String failed")
	}
}

// TestTableNameMethods tests TableName methods
func TestTableNameMethods(t *testing.T) {
	tn := &TableName{
		Token: token.Token{Literal: "users"},
		Name:  &QualifiedIdentifier{Parts: []*Identifier{{Value: "users"}}},
		Alias: &Identifier{Value: "u"},
		Hints: []string{"NOLOCK"},
	}

	tn.tableRefNode()

	if tn.TokenLiteral() != "users" {
		t.Error("TableName TokenLiteral failed")
	}
	result := tn.String()
	if !strings.Contains(result, "users") {
		t.Error("TableName String missing table name")
	}
	if !strings.Contains(result, "NOLOCK") {
		t.Error("TableName String missing hint")
	}
}

// TestJoinClauseMethods tests JoinClause methods
func TestJoinClauseMethods(t *testing.T) {
	jc := &JoinClause{
		Token: token.Token{Literal: "JOIN"},
		Type:  "INNER",
		Left: &TableName{
			Name: &QualifiedIdentifier{Parts: []*Identifier{{Value: "a"}}},
		},
		Right: &TableName{
			Name: &QualifiedIdentifier{Parts: []*Identifier{{Value: "b"}}},
		},
		Condition: &Identifier{Value: "cond"},
	}

	jc.tableRefNode()

	if jc.TokenLiteral() != "JOIN" {
		t.Error("JoinClause TokenLiteral failed")
	}
	result := jc.String()
	if !strings.Contains(result, "JOIN") {
		t.Error("JoinClause String missing JOIN")
	}
}

// TestDerivedTableMethods tests DerivedTable methods
func TestDerivedTableMethods(t *testing.T) {
	dt := &DerivedTable{
		Token: token.Token{Literal: "("},
		Subquery: &SelectStatement{
			Token:   token.Token{Literal: "SELECT"},
			Columns: []SelectColumn{{Expression: &Identifier{Value: "*"}}},
		},
		Alias: &Identifier{Value: "sub"},
	}

	dt.tableRefNode()

	if dt.TokenLiteral() != "(" {
		t.Error("DerivedTable TokenLiteral failed")
	}
	if !strings.Contains(dt.String(), "SELECT") {
		t.Error("DerivedTable String failed")
	}
}

// TestCollateExpressionMethods tests CollateExpression methods
func TestCollateExpressionMethods(t *testing.T) {
	ce := &CollateExpression{
		Token:     token.Token{Literal: "COLLATE"},
		Expr:      &Identifier{Value: "name"},
		Collation: "Latin1_General_CI_AS",
	}

	ce.expressionNode()

	if ce.TokenLiteral() != "COLLATE" {
		t.Error("CollateExpression TokenLiteral failed")
	}
	result := ce.String()
	if !strings.Contains(result, "COLLATE") {
		t.Error("CollateExpression String missing COLLATE")
	}
	if !strings.Contains(result, "Latin1_General_CI_AS") {
		t.Error("CollateExpression String missing collation")
	}
}

// TestAtTimeZoneExpressionMethods tests AtTimeZoneExpression methods
func TestAtTimeZoneExpressionMethods(t *testing.T) {
	atz := &AtTimeZoneExpression{
		Token:    token.Token{Literal: "AT TIME ZONE"},
		Expr:     &Identifier{Value: "created_at"},
		TimeZone: &StringLiteral{Token: token.Token{Literal: "'UTC'"}, Value: "UTC"},
	}

	atz.expressionNode()

	if atz.TokenLiteral() != "AT TIME ZONE" {
		t.Error("AtTimeZoneExpression TokenLiteral failed")
	}
	if !strings.Contains(atz.String(), "AT TIME ZONE") {
		t.Error("AtTimeZoneExpression String failed")
	}
}

// TestExistsExpressionMethods tests ExistsExpression methods
func TestExistsExpressionMethods(t *testing.T) {
	ee := &ExistsExpression{
		Token: token.Token{Literal: "EXISTS"},
		Subquery: &SelectStatement{
			Token:   token.Token{Literal: "SELECT"},
			Columns: []SelectColumn{{Expression: &IntegerLiteral{Token: token.Token{Literal: "1"}, Value: 1}}},
		},
	}

	ee.expressionNode()

	if ee.TokenLiteral() != "EXISTS" {
		t.Error("ExistsExpression TokenLiteral failed")
	}
	if !strings.Contains(ee.String(), "EXISTS") {
		t.Error("ExistsExpression String failed")
	}
}

// TestCastExpressionMethods tests CastExpression methods
func TestCastExpressionMethods(t *testing.T) {
	ce := &CastExpression{
		Token:      token.Token{Literal: "CAST"},
		Expression: &Identifier{Value: "price"},
		TargetType: &DataType{Name: "DECIMAL"},
	}

	ce.expressionNode()

	if ce.TokenLiteral() != "CAST" {
		t.Error("CastExpression TokenLiteral failed")
	}
	if !strings.Contains(ce.String(), "CAST") {
		t.Error("CastExpression String failed")
	}
}

// TestConvertExpressionMethods tests ConvertExpression methods
func TestConvertExpressionMethods(t *testing.T) {
	ce := &ConvertExpression{
		Token:      token.Token{Literal: "CONVERT"},
		TargetType: &DataType{Name: "VARCHAR"},
		Expression: &Identifier{Value: "value"},
	}

	ce.expressionNode()

	if ce.TokenLiteral() != "CONVERT" {
		t.Error("ConvertExpression TokenLiteral failed")
	}
	if !strings.Contains(ce.String(), "CONVERT") {
		t.Error("ConvertExpression String failed")
	}

	// With style
	ce.Style = &IntegerLiteral{Token: token.Token{Literal: "121"}, Value: 121}
	if !strings.Contains(ce.String(), "121") {
		t.Error("ConvertExpression with style String failed")
	}
}

// TestDataTypeMethods tests DataType methods
func TestDataTypeMethods(t *testing.T) {
	dt := &DataType{Name: "VARCHAR"}
	if dt.String() != "VARCHAR" {
		t.Error("DataType String failed for simple type")
	}

	// With length
	length := 100
	dt.Length = &length
	if !strings.Contains(dt.String(), "100") {
		t.Error("DataType String failed for type with length")
	}

	// MAX
	dt.Max = true
	dt.Length = nil
	if !strings.Contains(dt.String(), "MAX") {
		t.Error("DataType String failed for MAX")
	}

	// With precision and scale
	dt2 := &DataType{Name: "DECIMAL"}
	prec, scale := 10, 2
	dt2.Precision = &prec
	dt2.Scale = &scale
	result := dt2.String()
	if !strings.Contains(result, "10") || !strings.Contains(result, "2") {
		t.Error("DataType String failed for precision/scale")
	}
}
