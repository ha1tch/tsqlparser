// Package ast defines the Abstract Syntax Tree nodes for T-SQL.
package ast

import (
	"fmt"
	"strings"

	"github.com/ha1tch/tsqlparser/token"
)

// Node represents a node in the AST.
type Node interface {
	TokenLiteral() string
	String() string
}

// Statement represents a statement node.
type Statement interface {
	Node
	statementNode()
}

// Expression represents an expression node.
type Expression interface {
	Node
	expressionNode()
}

// Program is the root node of every AST.
type Program struct {
	Statements []Statement
}

func (p *Program) TokenLiteral() string {
	if len(p.Statements) > 0 {
		return p.Statements[0].TokenLiteral()
	}
	return ""
}

func (p *Program) String() string {
	var out strings.Builder
	for _, s := range p.Statements {
		out.WriteString(s.String())
		out.WriteString("\n")
	}
	return out.String()
}

// -----------------------------------------------------------------------------
// Identifiers and Literals
// -----------------------------------------------------------------------------

// Identifier represents an identifier (table name, column name, etc.).
type Identifier struct {
	Token token.Token
	Value string
}

func (i *Identifier) expressionNode()      {}
func (i *Identifier) TokenLiteral() string { return i.Token.Literal }
func (i *Identifier) String() string       { return i.Value }

// QualifiedIdentifier represents a multi-part identifier (schema.table, etc.).
type QualifiedIdentifier struct {
	Parts []*Identifier
}

func (q *QualifiedIdentifier) expressionNode() {}
func (q *QualifiedIdentifier) TokenLiteral() string {
	if len(q.Parts) > 0 {
		return q.Parts[0].TokenLiteral()
	}
	return ""
}
func (q *QualifiedIdentifier) String() string {
	var parts []string
	for _, p := range q.Parts {
		parts = append(parts, p.Value)
	}
	return strings.Join(parts, ".")
}

// Variable represents a T-SQL variable (@var or @@globalvar).
type Variable struct {
	Token token.Token
	Name  string
}

func (v *Variable) expressionNode()      {}
func (v *Variable) TokenLiteral() string { return v.Token.Literal }
func (v *Variable) String() string       { return v.Name }

// IntegerLiteral represents an integer literal.
type IntegerLiteral struct {
	Token token.Token
	Value int64
}

func (il *IntegerLiteral) expressionNode()      {}
func (il *IntegerLiteral) TokenLiteral() string { return il.Token.Literal }
func (il *IntegerLiteral) String() string       { return il.Token.Literal }

// FloatLiteral represents a floating-point literal.
type FloatLiteral struct {
	Token token.Token
	Value float64
}

func (fl *FloatLiteral) expressionNode()      {}
func (fl *FloatLiteral) TokenLiteral() string { return fl.Token.Literal }
func (fl *FloatLiteral) String() string       { return fl.Token.Literal }

// MoneyLiteral represents a money literal (e.g., $123.45).
type MoneyLiteral struct {
	Token token.Token
	Value string // Store as string to preserve format
}

func (ml *MoneyLiteral) expressionNode()      {}
func (ml *MoneyLiteral) TokenLiteral() string { return ml.Token.Literal }
func (ml *MoneyLiteral) String() string       { return ml.Value }

// StringLiteral represents a string literal.
type StringLiteral struct {
	Token   token.Token
	Value   string
	Unicode bool // N'...' prefix
}

func (sl *StringLiteral) expressionNode()      {}
func (sl *StringLiteral) TokenLiteral() string { return sl.Token.Literal }
func (sl *StringLiteral) String() string {
	if sl.Unicode {
		return "N'" + sl.Value + "'"
	}
	return "'" + sl.Value + "'"
}

// NullLiteral represents a NULL literal.
type NullLiteral struct {
	Token token.Token
}

func (nl *NullLiteral) expressionNode()      {}
func (nl *NullLiteral) TokenLiteral() string { return nl.Token.Literal }
func (nl *NullLiteral) String() string       { return "NULL" }

// BinaryLiteral represents a binary literal (0x...).
type BinaryLiteral struct {
	Token token.Token
	Value string
}

func (bl *BinaryLiteral) expressionNode()      {}
func (bl *BinaryLiteral) TokenLiteral() string { return bl.Token.Literal }
func (bl *BinaryLiteral) String() string       { return bl.Value }

// -----------------------------------------------------------------------------
// Expressions
// -----------------------------------------------------------------------------

// PrefixExpression represents a prefix expression (NOT, -, ~).
type PrefixExpression struct {
	Token    token.Token
	Operator string
	Right    Expression
}

func (pe *PrefixExpression) expressionNode()      {}
func (pe *PrefixExpression) TokenLiteral() string { return pe.Token.Literal }
func (pe *PrefixExpression) String() string {
	return "(" + pe.Operator + " " + pe.Right.String() + ")"
}

// InfixExpression represents an infix expression (a + b, a AND b, etc.).
type InfixExpression struct {
	Token    token.Token
	Left     Expression
	Operator string
	Right    Expression
}

func (ie *InfixExpression) expressionNode()      {}
func (ie *InfixExpression) TokenLiteral() string { return ie.Token.Literal }
func (ie *InfixExpression) String() string {
	return "(" + ie.Left.String() + " " + ie.Operator + " " + ie.Right.String() + ")"
}

// CollateExpression represents expr COLLATE collation_name
type CollateExpression struct {
	Token     token.Token
	Expr      Expression
	Collation string
}

func (ce *CollateExpression) expressionNode()      {}
func (ce *CollateExpression) TokenLiteral() string { return ce.Token.Literal }
func (ce *CollateExpression) String() string {
	return ce.Expr.String() + " COLLATE " + ce.Collation
}

// AtTimeZoneExpression represents expr AT TIME ZONE timezone
type AtTimeZoneExpression struct {
	Token    token.Token
	Expr     Expression
	TimeZone Expression // String literal or expression for timezone
}

func (atz *AtTimeZoneExpression) expressionNode()      {}
func (atz *AtTimeZoneExpression) TokenLiteral() string { return atz.Token.Literal }
func (atz *AtTimeZoneExpression) String() string {
	return atz.Expr.String() + " AT TIME ZONE " + atz.TimeZone.String()
}

// BetweenExpression represents a BETWEEN expression.
type BetweenExpression struct {
	Token token.Token
	Expr  Expression
	Not   bool
	Low   Expression
	High  Expression
}

func (be *BetweenExpression) expressionNode()      {}
func (be *BetweenExpression) TokenLiteral() string { return be.Token.Literal }
func (be *BetweenExpression) String() string {
	not := ""
	if be.Not {
		not = "NOT "
	}
	return be.Expr.String() + " " + not + "BETWEEN " + be.Low.String() + " AND " + be.High.String()
}

// InExpression represents an IN expression.
type InExpression struct {
	Token    token.Token
	Expr     Expression
	Not      bool
	Values   []Expression
	Subquery *SelectStatement
}

func (ie *InExpression) expressionNode()      {}
func (ie *InExpression) TokenLiteral() string { return ie.Token.Literal }
func (ie *InExpression) String() string {
	not := ""
	if ie.Not {
		not = "NOT "
	}
	if ie.Subquery != nil {
		return ie.Expr.String() + " " + not + "IN (" + ie.Subquery.String() + ")"
	}
	var vals []string
	for _, v := range ie.Values {
		vals = append(vals, v.String())
	}
	return ie.Expr.String() + " " + not + "IN (" + strings.Join(vals, ", ") + ")"
}

// LikeExpression represents a LIKE expression.
type LikeExpression struct {
	Token   token.Token
	Expr    Expression
	Not     bool
	Pattern Expression
	Escape  Expression
}

func (le *LikeExpression) expressionNode()      {}
func (le *LikeExpression) TokenLiteral() string { return le.Token.Literal }
func (le *LikeExpression) String() string {
	not := ""
	if le.Not {
		not = "NOT "
	}
	result := le.Expr.String() + " " + not + "LIKE " + le.Pattern.String()
	if le.Escape != nil {
		result += " ESCAPE " + le.Escape.String()
	}
	return result
}

// IsNullExpression represents an IS NULL or IS NOT NULL expression.
type IsNullExpression struct {
	Token token.Token
	Expr  Expression
	Not   bool
}

func (in *IsNullExpression) expressionNode()      {}
func (in *IsNullExpression) TokenLiteral() string { return in.Token.Literal }
func (in *IsNullExpression) String() string {
	if in.Not {
		return in.Expr.String() + " IS NOT NULL"
	}
	return in.Expr.String() + " IS NULL"
}

// IsDistinctFromExpression represents IS [NOT] DISTINCT FROM expression (SQL Server 2022+)
type IsDistinctFromExpression struct {
	Token token.Token
	Left  Expression
	Right Expression
	Not   bool // true for IS NOT DISTINCT FROM
}

func (id *IsDistinctFromExpression) expressionNode()      {}
func (id *IsDistinctFromExpression) TokenLiteral() string { return id.Token.Literal }
func (id *IsDistinctFromExpression) String() string {
	if id.Not {
		return id.Left.String() + " IS NOT DISTINCT FROM " + id.Right.String()
	}
	return id.Left.String() + " IS DISTINCT FROM " + id.Right.String()
}

// ExistsExpression represents an EXISTS expression.
type ExistsExpression struct {
	Token    token.Token
	Subquery *SelectStatement
}

func (ee *ExistsExpression) expressionNode()      {}
func (ee *ExistsExpression) TokenLiteral() string { return ee.Token.Literal }
func (ee *ExistsExpression) String() string {
	return "EXISTS (" + ee.Subquery.String() + ")"
}

// CaseExpression represents a CASE expression.
type CaseExpression struct {
	Token       token.Token
	Operand     Expression // Optional: CASE operand WHEN ...
	WhenClauses []*WhenClause
	ElseClause  Expression
}

type WhenClause struct {
	Condition Expression
	Result    Expression
}

func (ce *CaseExpression) expressionNode()      {}
func (ce *CaseExpression) TokenLiteral() string { return ce.Token.Literal }
func (ce *CaseExpression) String() string {
	var out strings.Builder
	out.WriteString("CASE")
	if ce.Operand != nil {
		out.WriteString(" ")
		out.WriteString(ce.Operand.String())
	}
	for _, wc := range ce.WhenClauses {
		out.WriteString(" WHEN ")
		out.WriteString(wc.Condition.String())
		out.WriteString(" THEN ")
		out.WriteString(wc.Result.String())
	}
	if ce.ElseClause != nil {
		out.WriteString(" ELSE ")
		out.WriteString(ce.ElseClause.String())
	}
	out.WriteString(" END")
	return out.String()
}

// CastExpression represents CAST(expr AS type) or TRY_CAST(expr AS type)
type CastExpression struct {
	Token      token.Token
	Expression Expression
	TargetType *DataType
	IsTry      bool // true for TRY_CAST
}

func (ce *CastExpression) expressionNode()      {}
func (ce *CastExpression) TokenLiteral() string { return ce.Token.Literal }
func (ce *CastExpression) String() string {
	funcName := "CAST"
	if ce.IsTry {
		funcName = "TRY_CAST"
	}
	return funcName + "(" + ce.Expression.String() + " AS " + ce.TargetType.String() + ")"
}

// TrimExpression represents a TRIM function call with SQL standard syntax
// TRIM([LEADING|TRAILING|BOTH] [characters FROM] string)
type TrimExpression struct {
	Token      token.Token
	TrimSpec   string     // LEADING, TRAILING, BOTH, or empty
	Characters Expression // characters to trim, or nil for default (spaces)
	Expression Expression // string to trim from
}

func (te *TrimExpression) expressionNode()      {}
func (te *TrimExpression) TokenLiteral() string { return te.Token.Literal }
func (te *TrimExpression) String() string {
	var result string
	result = "TRIM("
	if te.TrimSpec != "" {
		result += te.TrimSpec + " "
	}
	if te.Characters != nil {
		result += te.Characters.String() + " FROM "
	}
	result += te.Expression.String() + ")"
	return result
}

// CursorExpression represents CURSOR [options] FOR select_statement
type CursorExpression struct {
	Token     token.Token
	Options   *CursorOptions
	ForSelect *SelectStatement
}

func (ce *CursorExpression) expressionNode()      {}
func (ce *CursorExpression) TokenLiteral() string { return ce.Token.Literal }
func (ce *CursorExpression) String() string {
	result := "CURSOR"
	if ce.Options != nil {
		optStr := ce.Options.String()
		if optStr != "" {
			result += " " + optStr
		}
	}
	if ce.ForSelect != nil {
		result += " FOR " + ce.ForSelect.String()
	}
	return result
}

// NextValueForExpression represents NEXT VALUE FOR sequence_name
type NextValueForExpression struct {
	Token        token.Token
	SequenceName *QualifiedIdentifier
	Over         *OverClause // Optional OVER (ORDER BY ...) clause
}

func (nv *NextValueForExpression) expressionNode()      {}
func (nv *NextValueForExpression) TokenLiteral() string { return nv.Token.Literal }
func (nv *NextValueForExpression) String() string {
	result := "NEXT VALUE FOR " + nv.SequenceName.String()
	if nv.Over != nil {
		result += " " + nv.Over.String()
	}
	return result
}

// ParseExpression represents PARSE/TRY_PARSE(expr AS type [USING culture])
type ParseExpression struct {
	Token      token.Token
	Expression Expression
	TargetType *DataType
	Culture    Expression // optional USING culture
	IsTry      bool       // true for TRY_PARSE
}

func (pe *ParseExpression) expressionNode()      {}
func (pe *ParseExpression) TokenLiteral() string { return pe.Token.Literal }
func (pe *ParseExpression) String() string {
	funcName := "PARSE"
	if pe.IsTry {
		funcName = "TRY_PARSE"
	}
	result := funcName + "(" + pe.Expression.String() + " AS " + pe.TargetType.String()
	if pe.Culture != nil {
		result += " USING " + pe.Culture.String()
	}
	result += ")"
	return result
}

// ConvertExpression represents CONVERT(type, expr [, style]) or TRY_CONVERT(type, expr [, style])
type ConvertExpression struct {
	Token      token.Token
	TargetType *DataType
	Expression Expression
	Style      Expression // optional style parameter
	IsTry      bool       // true for TRY_CONVERT
}

func (ce *ConvertExpression) expressionNode()      {}
func (ce *ConvertExpression) TokenLiteral() string { return ce.Token.Literal }
func (ce *ConvertExpression) String() string {
	funcName := "CONVERT"
	if ce.IsTry {
		funcName = "TRY_CONVERT"
	}
	result := funcName + "(" + ce.TargetType.String() + ", " + ce.Expression.String()
	if ce.Style != nil {
		result += ", " + ce.Style.String()
	}
	result += ")"
	return result
}

// FunctionCall represents a function call.
type FunctionCall struct {
	Token       token.Token
	Function    Expression
	Arguments   []Expression
	WithinGroup []*OrderByItem // For WITHIN GROUP (ORDER BY ...) - ordered-set aggregates
	Over        *OverClause
}

func (fc *FunctionCall) expressionNode()      {}
func (fc *FunctionCall) TokenLiteral() string { return fc.Token.Literal }
func (fc *FunctionCall) String() string {
	var args []string
	for _, a := range fc.Arguments {
		args = append(args, a.String())
	}
	result := fc.Function.String() + "(" + strings.Join(args, ", ") + ")"
	if len(fc.WithinGroup) > 0 {
		result += " WITHIN GROUP (ORDER BY "
		var orderParts []string
		for _, o := range fc.WithinGroup {
			orderParts = append(orderParts, o.String())
		}
		result += strings.Join(orderParts, ", ") + ")"
	}
	if fc.Over != nil {
		result += " " + fc.Over.String()
	}
	return result
}

// MethodCallExpression represents a method call on an object (e.g., @xml.value('xpath', 'type'))
type MethodCallExpression struct {
	Token      token.Token
	Object     Expression // The object being called on
	MethodName string     // value, nodes, query, exist, modify
	Arguments  []Expression
}

func (mc *MethodCallExpression) expressionNode()      {}
func (mc *MethodCallExpression) TokenLiteral() string { return mc.Token.Literal }
func (mc *MethodCallExpression) String() string {
	var args []string
	for _, a := range mc.Arguments {
		args = append(args, a.String())
	}
	return mc.Object.String() + "." + mc.MethodName + "(" + strings.Join(args, ", ") + ")"
}

// StaticMethodCall represents a static method call (e.g., GEOGRAPHY::Point(...))
type StaticMethodCall struct {
	Token      token.Token
	TypeName   string // GEOGRAPHY, GEOMETRY, SCHEMA, OBJECT, etc.
	MethodName string // Point, STGeomFromText, etc.
	Arguments  []Expression
}

func (sm *StaticMethodCall) expressionNode()      {}
func (sm *StaticMethodCall) TokenLiteral() string { return sm.Token.Literal }
func (sm *StaticMethodCall) String() string {
	if sm.Arguments == nil {
		// Non-function case like SCHEMA::SchemaName
		return sm.TypeName + "::" + sm.MethodName
	}
	var args []string
	for _, a := range sm.Arguments {
		args = append(args, a.String())
	}
	return sm.TypeName + "::" + sm.MethodName + "(" + strings.Join(args, ", ") + ")"
}

// OverClause represents an OVER clause for window functions.
type OverClause struct {
	Token       token.Token
	WindowRef   string // Named window reference (e.g., OVER w)
	PartitionBy []Expression
	OrderBy     []*OrderByItem
	Frame       *WindowFrame
}

func (oc *OverClause) String() string {
	var out strings.Builder

	if oc.WindowRef != "" {
		out.WriteString("OVER ")
		out.WriteString(oc.WindowRef)
		return out.String()
	}

	out.WriteString("OVER (")

	if len(oc.PartitionBy) > 0 {
		out.WriteString("PARTITION BY ")
		var parts []string
		for _, p := range oc.PartitionBy {
			parts = append(parts, p.String())
		}
		out.WriteString(strings.Join(parts, ", "))
	}

	if len(oc.OrderBy) > 0 {
		if len(oc.PartitionBy) > 0 {
			out.WriteString(" ")
		}
		out.WriteString("ORDER BY ")
		var items []string
		for _, o := range oc.OrderBy {
			items = append(items, o.String())
		}
		out.WriteString(strings.Join(items, ", "))
	}

	if oc.Frame != nil {
		out.WriteString(" ")
		out.WriteString(oc.Frame.String())
	}

	out.WriteString(")")
	return out.String()
}

// WindowFrame represents a window frame specification (ROWS/RANGE BETWEEN).
type WindowFrame struct {
	Type  string // ROWS or RANGE
	Start *FrameBound
	End   *FrameBound // nil if not BETWEEN
}

func (wf *WindowFrame) String() string {
	var out strings.Builder
	out.WriteString(wf.Type)
	if wf.End != nil {
		out.WriteString(" BETWEEN ")
		out.WriteString(wf.Start.String())
		out.WriteString(" AND ")
		out.WriteString(wf.End.String())
	} else {
		out.WriteString(" ")
		out.WriteString(wf.Start.String())
	}
	return out.String()
}

// FrameBound represents a window frame bound.
type FrameBound struct {
	Type   string     // UNBOUNDED PRECEDING, UNBOUNDED FOLLOWING, CURRENT ROW, n PRECEDING, n FOLLOWING
	Offset Expression // for n PRECEDING/FOLLOWING
}

func (fb *FrameBound) String() string {
	if fb.Offset != nil {
		return fb.Offset.String() + " " + fb.Type
	}
	return fb.Type
}

// SubqueryExpression represents a subquery as an expression.
type SubqueryExpression struct {
	Token    token.Token
	Subquery *SelectStatement
}

func (se *SubqueryExpression) expressionNode()      {}
func (se *SubqueryExpression) TokenLiteral() string { return se.Token.Literal }
func (se *SubqueryExpression) String() string {
	return "(" + se.Subquery.String() + ")"
}

// TupleExpression represents a tuple/list of expressions (e.g., (a, b) or () in GROUPING SETS).
type TupleExpression struct {
	Token    token.Token
	Elements []Expression
}

func (te *TupleExpression) expressionNode()      {}
func (te *TupleExpression) TokenLiteral() string { return te.Token.Literal }
func (te *TupleExpression) String() string {
	if len(te.Elements) == 0 {
		return "()"
	}
	var parts []string
	for _, e := range te.Elements {
		parts = append(parts, e.String())
	}
	return "(" + strings.Join(parts, ", ") + ")"
}

// GroupingSetsExpression represents a GROUPING SETS expression in GROUP BY
type GroupingSetsExpression struct {
	Token token.Token
	Sets  []Expression // Each element is a TupleExpression or single column
}

func (gse *GroupingSetsExpression) expressionNode()      {}
func (gse *GroupingSetsExpression) TokenLiteral() string { return gse.Token.Literal }
func (gse *GroupingSetsExpression) String() string {
	var parts []string
	for _, s := range gse.Sets {
		parts = append(parts, s.String())
	}
	return "GROUPING SETS (" + strings.Join(parts, ", ") + ")"
}

// CubeExpression represents a CUBE expression in GROUP BY
type CubeExpression struct {
	Token   token.Token
	Columns []Expression
}

func (ce *CubeExpression) expressionNode()      {}
func (ce *CubeExpression) TokenLiteral() string { return ce.Token.Literal }
func (ce *CubeExpression) String() string {
	var parts []string
	for _, c := range ce.Columns {
		parts = append(parts, c.String())
	}
	return "CUBE(" + strings.Join(parts, ", ") + ")"
}

// RollupExpression represents a ROLLUP expression in GROUP BY
type RollupExpression struct {
	Token   token.Token
	Columns []Expression
}

func (re *RollupExpression) expressionNode()      {}
func (re *RollupExpression) TokenLiteral() string { return re.Token.Literal }
func (re *RollupExpression) String() string {
	var parts []string
	for _, c := range re.Columns {
		parts = append(parts, c.String())
	}
	return "ROLLUP(" + strings.Join(parts, ", ") + ")"
}

// JsonKeyValuePair represents 'key':value syntax in JSON_OBJECT
type JsonKeyValuePair struct {
	Token token.Token
	Key   Expression
	Value Expression
}

func (jkv *JsonKeyValuePair) expressionNode()      {}
func (jkv *JsonKeyValuePair) TokenLiteral() string { return jkv.Token.Literal }
func (jkv *JsonKeyValuePair) String() string {
	return jkv.Key.String() + ":" + jkv.Value.String()
}

// -----------------------------------------------------------------------------
// SELECT Statement
// -----------------------------------------------------------------------------

// SelectStatement represents a SELECT statement.
type SelectStatement struct {
	Token         token.Token
	Distinct      bool
	Top           *TopClause
	Columns       []SelectColumn
	Into          *QualifiedIdentifier
	IntoFilegroup *Identifier // ON [filegroup] for SELECT INTO
	From          *FromClause
	Where         Expression
	GroupBy       []Expression
	Having        Expression
	WindowDefs    []*WindowDefinition // WINDOW w AS (...)
	OrderBy       []*OrderByItem
	Union         *UnionClause
	Offset        Expression
	Fetch         Expression
	ForClause     *ForClause
	Options       []*QueryOption // OPTION (RECOMPILE, MAXDOP 4, etc.)
}

// WindowDefinition represents a named window: WINDOW w AS (PARTITION BY ... ORDER BY ...)
type WindowDefinition struct {
	Name string
	Spec *OverClause
}

func (ss *SelectStatement) statementNode()       {}
func (ss *SelectStatement) expressionNode()      {} // Can be used as subquery
func (ss *SelectStatement) TokenLiteral() string { return ss.Token.Literal }
func (ss *SelectStatement) String() string {
	var out strings.Builder
	out.WriteString("SELECT")

	if ss.Distinct {
		out.WriteString(" DISTINCT")
	}

	if ss.Top != nil {
		out.WriteString(" ")
		out.WriteString(ss.Top.String())
	}

	var cols []string
	for _, c := range ss.Columns {
		cols = append(cols, c.String())
	}
	out.WriteString(" ")
	out.WriteString(strings.Join(cols, ", "))

	if ss.Into != nil {
		out.WriteString(" INTO ")
		out.WriteString(ss.Into.String())
		if ss.IntoFilegroup != nil {
			out.WriteString(" ON ")
			out.WriteString(ss.IntoFilegroup.Value)
		}
	}

	if ss.From != nil {
		out.WriteString(" ")
		out.WriteString(ss.From.String())
	}

	if ss.Where != nil {
		out.WriteString(" WHERE ")
		out.WriteString(ss.Where.String())
	}

	if len(ss.GroupBy) > 0 {
		out.WriteString(" GROUP BY ")
		var groups []string
		for _, g := range ss.GroupBy {
			groups = append(groups, g.String())
		}
		out.WriteString(strings.Join(groups, ", "))
	}

	if ss.Having != nil {
		out.WriteString(" HAVING ")
		out.WriteString(ss.Having.String())
	}

	if len(ss.OrderBy) > 0 {
		out.WriteString(" ORDER BY ")
		var orders []string
		for _, o := range ss.OrderBy {
			orders = append(orders, o.String())
		}
		out.WriteString(strings.Join(orders, ", "))
	}

	if ss.Offset != nil {
		out.WriteString(" OFFSET ")
		out.WriteString(ss.Offset.String())
		out.WriteString(" ROWS")
	}

	if ss.Fetch != nil {
		out.WriteString(" FETCH NEXT ")
		out.WriteString(ss.Fetch.String())
		out.WriteString(" ROWS ONLY")
	}

	if ss.ForClause != nil {
		out.WriteString(" ")
		out.WriteString(ss.ForClause.String())
	}

	if len(ss.Options) > 0 {
		out.WriteString(" OPTION (")
		for i, opt := range ss.Options {
			if i > 0 {
				out.WriteString(", ")
			}
			out.WriteString(opt.String())
		}
		out.WriteString(")")
	}

	if ss.Union != nil {
		out.WriteString(" ")
		out.WriteString(ss.Union.String())
	}

	return out.String()
}

// QueryOption represents a query hint in OPTION clause
type QueryOption struct {
	Name        string             // RECOMPILE, MAXDOP, HASH JOIN, USE HINT, OPTIMIZE FOR, etc.
	Value       Expression         // Optional value (e.g., 4 for MAXDOP 4)
	Hints       []string           // For USE HINT('hint1', 'hint2')
	OptimizeFor []*OptimizeForHint // For OPTIMIZE FOR (@var = value, @var UNKNOWN)
}

// OptimizeForHint represents a single OPTIMIZE FOR hint binding
type OptimizeForHint struct {
	Variable string
	Value    Expression // nil if UNKNOWN
	Unknown  bool       // true if UNKNOWN
}

func (qo *QueryOption) String() string {
	if qo.Name == "USE HINT" && len(qo.Hints) > 0 {
		hints := make([]string, len(qo.Hints))
		for i, h := range qo.Hints {
			hints[i] = "'" + h + "'"
		}
		return "USE HINT(" + strings.Join(hints, ", ") + ")"
	}
	if qo.Name == "OPTIMIZE FOR" && len(qo.OptimizeFor) > 0 {
		var bindings []string
		for _, h := range qo.OptimizeFor {
			if h.Unknown {
				bindings = append(bindings, h.Variable+" UNKNOWN")
			} else {
				bindings = append(bindings, h.Variable+" = "+h.Value.String())
			}
		}
		return "OPTIMIZE FOR (" + strings.Join(bindings, ", ") + ")"
	}
	if qo.Value != nil {
		return qo.Name + " " + qo.Value.String()
	}
	return qo.Name
}

// SelectColumn represents a column in a SELECT list.
type SelectColumn struct {
	Expression Expression
	Alias      *Identifier
	AllColumns bool      // SELECT *
	Variable   *Variable // For SELECT @var = expr
}

func (sc SelectColumn) String() string {
	if sc.AllColumns {
		return "*"
	}
	if sc.Variable != nil {
		return sc.Variable.Name + " = " + sc.Expression.String()
	}
	result := sc.Expression.String()
	if sc.Alias != nil {
		result += " AS " + sc.Alias.Value
	}
	return result
}

// ForClause represents FOR XML or FOR JSON clause
type ForClause struct {
	Token               token.Token
	ForType             string // "XML" or "JSON"
	Mode                string // RAW, AUTO, PATH, EXPLICIT
	ElementName         string // Optional element name for RAW/PATH
	Elements            bool   // ELEMENTS option (XML)
	Type                bool   // TYPE option (returns xml type)
	Root                string // ROOT('name') option
	WithoutArrayWrapper bool   // WITHOUT_ARRAY_WRAPPER (JSON)
	IncludeNullValues   bool   // INCLUDE_NULL_VALUES (JSON)
}

func (fc *ForClause) String() string {
	var out strings.Builder
	out.WriteString("FOR ")
	out.WriteString(fc.ForType)
	out.WriteString(" ")
	out.WriteString(fc.Mode)

	if fc.ElementName != "" {
		out.WriteString("('")
		out.WriteString(fc.ElementName)
		out.WriteString("')")
	}

	if fc.Elements {
		out.WriteString(", ELEMENTS")
	}
	if fc.Type {
		out.WriteString(", TYPE")
	}
	if fc.Root != "" {
		out.WriteString(", ROOT('")
		out.WriteString(fc.Root)
		out.WriteString("')")
	}
	if fc.WithoutArrayWrapper {
		out.WriteString(", WITHOUT_ARRAY_WRAPPER")
	}
	if fc.IncludeNullValues {
		out.WriteString(", INCLUDE_NULL_VALUES")
	}

	return out.String()
}

// TopClause represents a TOP clause.
type TopClause struct {
	Count    Expression
	Percent  bool
	WithTies bool
}

func (tc *TopClause) String() string {
	result := "TOP " + tc.Count.String()
	if tc.Percent {
		result += " PERCENT"
	}
	if tc.WithTies {
		result += " WITH TIES"
	}
	return result
}

// FromClause represents a FROM clause.
type FromClause struct {
	Token  token.Token
	Tables []TableReference
}

func (fc *FromClause) String() string {
	var tables []string
	for _, t := range fc.Tables {
		tables = append(tables, t.String())
	}
	return "FROM " + strings.Join(tables, ", ")
}

// TableReference represents a table reference (can be table, join, subquery).
type TableReference interface {
	Node
	tableRefNode()
}

// TableName represents a simple table reference.
type TableName struct {
	Token          token.Token
	Name           *QualifiedIdentifier
	Alias          *Identifier
	Hints          []string
	TemporalClause *TemporalClause
	TableSample    *TableSampleClause
}

// TableSampleClause represents TABLESAMPLE (n PERCENT) or TABLESAMPLE (n ROWS)
type TableSampleClause struct {
	Token     token.Token
	System    bool       // TABLESAMPLE SYSTEM vs regular TABLESAMPLE
	Value     Expression // The sample value (number)
	IsPercent bool       // true for PERCENT, false for ROWS
	IsRows    bool       // true for ROWS
	Seed      Expression // For REPEATABLE (seed)
}

func (ts *TableSampleClause) String() string {
	var out strings.Builder
	out.WriteString("TABLESAMPLE")
	if ts.System {
		out.WriteString(" SYSTEM")
	}
	out.WriteString(" (")
	out.WriteString(ts.Value.String())
	if ts.IsPercent {
		out.WriteString(" PERCENT")
	} else if ts.IsRows {
		out.WriteString(" ROWS")
	}
	out.WriteString(")")
	if ts.Seed != nil {
		out.WriteString(" REPEATABLE (")
		out.WriteString(ts.Seed.String())
		out.WriteString(")")
	}
	return out.String()
}

func (tn *TableName) tableRefNode()        {}
func (tn *TableName) TokenLiteral() string { return tn.Token.Literal }
func (tn *TableName) String() string {
	result := tn.Name.String()
	if tn.TableSample != nil {
		result += " " + tn.TableSample.String()
	}
	if len(tn.Hints) > 0 {
		result += " WITH (" + strings.Join(tn.Hints, ", ") + ")"
	}
	if tn.TemporalClause != nil {
		result += " " + tn.TemporalClause.String()
	}
	if tn.Alias != nil {
		result += " AS " + tn.Alias.Value
	}
	return result
}

// TemporalClause represents a FOR SYSTEM_TIME clause for temporal tables.
type TemporalClause struct {
	Token     token.Token
	Type      string     // AS OF, BETWEEN...AND, FROM...TO, CONTAINED IN, ALL
	StartTime Expression // Start time/date
	EndTime   Expression // End time/date (for BETWEEN, FROM...TO, CONTAINED IN)
}

func (tc *TemporalClause) String() string {
	switch tc.Type {
	case "AS OF":
		return "FOR SYSTEM_TIME AS OF " + tc.StartTime.String()
	case "BETWEEN":
		return "FOR SYSTEM_TIME BETWEEN " + tc.StartTime.String() + " AND " + tc.EndTime.String()
	case "FROM":
		return "FOR SYSTEM_TIME FROM " + tc.StartTime.String() + " TO " + tc.EndTime.String()
	case "CONTAINED IN":
		return "FOR SYSTEM_TIME CONTAINED IN (" + tc.StartTime.String() + ", " + tc.EndTime.String() + ")"
	case "ALL":
		return "FOR SYSTEM_TIME ALL"
	}
	return "FOR SYSTEM_TIME"
}

// DerivedTable represents a subquery in the FROM clause.
type DerivedTable struct {
	Token         token.Token
	Subquery      *SelectStatement
	Alias         *Identifier
	ColumnAliases []*Identifier // Column names like AS T(c1, c2)
}

func (dt *DerivedTable) tableRefNode()        {}
func (dt *DerivedTable) TokenLiteral() string { return dt.Token.Literal }
func (dt *DerivedTable) String() string {
	result := "(" + dt.Subquery.String() + ")"
	if dt.Alias != nil {
		result += " AS " + dt.Alias.Value
		if len(dt.ColumnAliases) > 0 {
			result += "("
			for i, col := range dt.ColumnAliases {
				if i > 0 {
					result += ", "
				}
				result += col.Value
			}
			result += ")"
		}
	}
	return result
}

// DmlDerivedTable represents composable DML: FROM (DELETE/UPDATE/MERGE ... OUTPUT ...) AS alias
type DmlDerivedTable struct {
	Token         token.Token
	Statement     Statement // DELETE, UPDATE, or MERGE statement with OUTPUT
	Alias         *Identifier
	ColumnAliases []*Identifier
}

// ParenthesizedTableRef represents a parenthesized table reference with joins: (t1 JOIN t2 ON ...)
type ParenthesizedTableRef struct {
	Token token.Token
	Inner TableReference // The table reference (possibly with joins) inside the parentheses
}

func (ptr *ParenthesizedTableRef) tableRefNode()        {}
func (ptr *ParenthesizedTableRef) TokenLiteral() string { return ptr.Token.Literal }
func (ptr *ParenthesizedTableRef) String() string {
	return "(" + ptr.Inner.String() + ")"
}

func (ddt *DmlDerivedTable) tableRefNode()        {}
func (ddt *DmlDerivedTable) TokenLiteral() string { return ddt.Token.Literal }
func (ddt *DmlDerivedTable) String() string {
	result := "(" + ddt.Statement.String() + ")"
	if ddt.Alias != nil {
		result += " AS " + ddt.Alias.Value
		if len(ddt.ColumnAliases) > 0 {
			result += "("
			for i, col := range ddt.ColumnAliases {
				if i > 0 {
					result += ", "
				}
				result += col.Value
			}
			result += ")"
		}
	}
	return result
}

// ValuesTable represents VALUES ((row1), (row2), ...) AS alias(columns)
type ValuesTable struct {
	Token   token.Token
	Rows    [][]Expression // Each row is a list of expressions
	Alias   *Identifier
	Columns []*Identifier // Column names
}

func (vt *ValuesTable) tableRefNode()        {}
func (vt *ValuesTable) TokenLiteral() string { return vt.Token.Literal }
func (vt *ValuesTable) String() string {
	var out strings.Builder
	out.WriteString("(VALUES ")
	for i, row := range vt.Rows {
		if i > 0 {
			out.WriteString(", ")
		}
		out.WriteString("(")
		for j, expr := range row {
			if j > 0 {
				out.WriteString(", ")
			}
			out.WriteString(expr.String())
		}
		out.WriteString(")")
	}
	out.WriteString(")")
	if vt.Alias != nil {
		out.WriteString(" AS ")
		out.WriteString(vt.Alias.Value)
		if len(vt.Columns) > 0 {
			out.WriteString("(")
			for i, col := range vt.Columns {
				if i > 0 {
					out.WriteString(", ")
				}
				out.WriteString(col.Value)
			}
			out.WriteString(")")
		}
	}
	return out.String()
}

// TableValuedFunction represents a table-valued function call in FROM/APPLY.
type TableValuedFunction struct {
	Token           token.Token
	Function        *QualifiedIdentifier
	Arguments       []Expression
	Alias           *Identifier
	ColumnAliases   []*Identifier     // Column names like AS T(c)
	OpenJsonColumns []*OpenJsonColumn // For OPENJSON WITH clause
}

func (tvf *TableValuedFunction) tableRefNode()        {}
func (tvf *TableValuedFunction) TokenLiteral() string { return tvf.Token.Literal }
func (tvf *TableValuedFunction) String() string {
	var out strings.Builder
	out.WriteString(tvf.Function.String())
	out.WriteString("(")
	for i, arg := range tvf.Arguments {
		if i > 0 {
			out.WriteString(", ")
		}
		out.WriteString(arg.String())
	}
	out.WriteString(")")
	if len(tvf.OpenJsonColumns) > 0 {
		out.WriteString(" WITH (")
		for i, col := range tvf.OpenJsonColumns {
			if i > 0 {
				out.WriteString(", ")
			}
			out.WriteString(col.String())
		}
		out.WriteString(")")
	}
	if tvf.Alias != nil {
		out.WriteString(" AS ")
		out.WriteString(tvf.Alias.Value)
		if len(tvf.ColumnAliases) > 0 {
			out.WriteString("(")
			for i, col := range tvf.ColumnAliases {
				if i > 0 {
					out.WriteString(", ")
				}
				out.WriteString(col.Value)
			}
			out.WriteString(")")
		}
	}
	return out.String()
}

// PivotTable represents a PIVOT table operation.
// Syntax: source PIVOT (aggregate(value_col) FOR pivot_col IN ([v1], [v2], ...)) AS alias
type PivotTable struct {
	Token         token.Token
	Source        TableReference
	AggregateFunc string        // SUM, COUNT, AVG, etc.
	ValueColumn   Expression    // Column being aggregated
	PivotColumn   *Identifier   // Column whose values become columns
	PivotValues   []*Identifier // Values that become column names
	Alias         *Identifier
}

func (pt *PivotTable) tableRefNode()        {}
func (pt *PivotTable) TokenLiteral() string { return pt.Token.Literal }
func (pt *PivotTable) String() string {
	var out strings.Builder
	out.WriteString(pt.Source.String())
	out.WriteString(" PIVOT (")
	out.WriteString(pt.AggregateFunc)
	out.WriteString("(")
	out.WriteString(pt.ValueColumn.String())
	out.WriteString(") FOR ")
	out.WriteString(pt.PivotColumn.Value)
	out.WriteString(" IN (")
	for i, v := range pt.PivotValues {
		if i > 0 {
			out.WriteString(", ")
		}
		out.WriteString("[")
		out.WriteString(v.Value)
		out.WriteString("]")
	}
	out.WriteString("))")
	if pt.Alias != nil {
		out.WriteString(" AS ")
		out.WriteString(pt.Alias.Value)
	}
	return out.String()
}

// UnpivotTable represents an UNPIVOT table operation.
// Syntax: source UNPIVOT (value_col FOR pivot_col IN ([c1], [c2], ...)) AS alias
type UnpivotTable struct {
	Token         token.Token
	Source        TableReference
	ValueColumn   *Identifier   // New column to hold values
	PivotColumn   *Identifier   // New column to hold original column names
	SourceColumns []*Identifier // Columns being unpivoted
	Alias         *Identifier
}

func (ut *UnpivotTable) tableRefNode()        {}
func (ut *UnpivotTable) TokenLiteral() string { return ut.Token.Literal }
func (ut *UnpivotTable) String() string {
	var out strings.Builder
	out.WriteString(ut.Source.String())
	out.WriteString(" UNPIVOT (")
	out.WriteString(ut.ValueColumn.Value)
	out.WriteString(" FOR ")
	out.WriteString(ut.PivotColumn.Value)
	out.WriteString(" IN (")
	for i, c := range ut.SourceColumns {
		if i > 0 {
			out.WriteString(", ")
		}
		out.WriteString("[")
		out.WriteString(c.Value)
		out.WriteString("]")
	}
	out.WriteString("))")
	if ut.Alias != nil {
		out.WriteString(" AS ")
		out.WriteString(ut.Alias.Value)
	}
	return out.String()
}

// JoinClause represents a JOIN clause.
type JoinClause struct {
	Token     token.Token
	Type      string // INNER, LEFT, RIGHT, FULL, CROSS
	Hint      string // HASH, MERGE, LOOP, REMOTE
	Left      TableReference
	Right     TableReference
	Condition Expression
}

func (jc *JoinClause) tableRefNode()        {}
func (jc *JoinClause) TokenLiteral() string { return jc.Token.Literal }
func (jc *JoinClause) String() string {
	var result string
	// APPLY operators don't use JOIN keyword
	if jc.Type == "CROSS APPLY" || jc.Type == "OUTER APPLY" {
		result = jc.Left.String() + " " + jc.Type + " " + jc.Right.String()
	} else {
		joinStr := jc.Type
		if jc.Hint != "" {
			joinStr += " " + jc.Hint
		}
		joinStr += " JOIN"
		result = jc.Left.String() + " " + joinStr + " " + jc.Right.String()
		if jc.Condition != nil {
			result += " ON " + jc.Condition.String()
		}
	}
	return result
}

// OrderByItem represents an item in an ORDER BY clause.
type OrderByItem struct {
	Expression Expression
	Descending bool
	NullsFirst *bool
}

func (ob *OrderByItem) String() string {
	result := ob.Expression.String()
	if ob.Descending {
		result += " DESC"
	} else {
		result += " ASC"
	}
	return result
}

// UnionClause represents a UNION, INTERSECT, or EXCEPT clause.
type UnionClause struct {
	Type  string // UNION, INTERSECT, EXCEPT
	All   bool
	Right *SelectStatement
}

func (uc *UnionClause) String() string {
	var out strings.Builder
	out.WriteString(uc.Type)
	if uc.All {
		out.WriteString(" ALL")
	}
	if uc.Right != nil {
		out.WriteString(" ")
		out.WriteString(uc.Right.String())
	}
	return out.String()
}

// -----------------------------------------------------------------------------
// DML Statements
// -----------------------------------------------------------------------------

// InsertStatement represents an INSERT statement.
type InsertStatement struct {
	Token         token.Token
	Top           Expression
	TopPercent    bool
	Table         *QualifiedIdentifier
	Hints         []string // Table hints: WITH (KEEPIDENTITY), WITH (TABLOCK), etc.
	Columns       []*Identifier
	Values        [][]Expression
	Select        *SelectStatement
	Output        *OutputClause
	DefaultValues bool // INSERT ... DEFAULT VALUES
}

func (is *InsertStatement) statementNode()       {}
func (is *InsertStatement) TokenLiteral() string { return is.Token.Literal }
func (is *InsertStatement) String() string {
	var out strings.Builder
	out.WriteString("INSERT ")

	if is.Top != nil {
		out.WriteString("TOP (")
		out.WriteString(is.Top.String())
		out.WriteString(")")
		if is.TopPercent {
			out.WriteString(" PERCENT")
		}
		out.WriteString(" ")
	}

	out.WriteString("INTO ")
	out.WriteString(is.Table.String())

	if len(is.Hints) > 0 {
		out.WriteString(" WITH (")
		out.WriteString(strings.Join(is.Hints, ", "))
		out.WriteString(")")
	}

	if len(is.Columns) > 0 {
		out.WriteString(" (")
		var cols []string
		for _, c := range is.Columns {
			cols = append(cols, c.Value)
		}
		out.WriteString(strings.Join(cols, ", "))
		out.WriteString(")")
	}

	if is.Output != nil {
		out.WriteString(" ")
		out.WriteString(is.Output.String())
	}

	if is.Select != nil {
		out.WriteString(" ")
		out.WriteString(is.Select.String())
	} else if is.DefaultValues {
		out.WriteString(" DEFAULT VALUES")
	} else if len(is.Values) > 0 {
		out.WriteString(" VALUES ")
		var rows []string
		for _, row := range is.Values {
			var vals []string
			for _, v := range row {
				vals = append(vals, v.String())
			}
			rows = append(rows, "("+strings.Join(vals, ", ")+")")
		}
		out.WriteString(strings.Join(rows, ", "))
	}

	return out.String()
}

// UpdateStatement represents an UPDATE statement.
type UpdateStatement struct {
	Token           token.Token
	Top             *TopClause
	Table           *QualifiedIdentifier
	TargetFunc      *FunctionCall // For UPDATE OPENQUERY(...), UPDATE OPENROWSET(...)
	Hints           []string
	Alias           *Identifier
	SetClauses      []*SetClause
	From            *FromClause
	Where           Expression
	CurrentOfCursor *Identifier // WHERE CURRENT OF cursor_name
	Output          *OutputClause
}

type SetClause struct {
	Column       *QualifiedIdentifier
	Operator     string // "=" or "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^="
	Value        Expression
	IsMethodCall bool         // For XML method calls like column.modify(...)
	MethodArgs   []Expression // Arguments for method calls
}

func (us *UpdateStatement) statementNode()       {}
func (us *UpdateStatement) TokenLiteral() string { return us.Token.Literal }
func (us *UpdateStatement) String() string {
	var out strings.Builder
	out.WriteString("UPDATE ")
	if us.Top != nil {
		out.WriteString(us.Top.String())
		out.WriteString(" ")
	}
	if us.TargetFunc != nil {
		out.WriteString(us.TargetFunc.String())
	} else {
		out.WriteString(us.Table.String())
	}
	if len(us.Hints) > 0 {
		out.WriteString(" WITH (")
		out.WriteString(strings.Join(us.Hints, ", "))
		out.WriteString(")")
	}
	if us.Alias != nil {
		out.WriteString(" ")
		out.WriteString(us.Alias.Value)
	}
	out.WriteString(" SET ")

	var sets []string
	for _, s := range us.SetClauses {
		op := s.Operator
		if op == "" {
			op = "="
		}
		sets = append(sets, s.Column.String()+" "+op+" "+s.Value.String())
	}
	out.WriteString(strings.Join(sets, ", "))

	if us.Output != nil {
		out.WriteString(" ")
		out.WriteString(us.Output.String())
	}

	if us.From != nil {
		out.WriteString(" ")
		out.WriteString(us.From.String())
	}

	if us.Where != nil {
		out.WriteString(" WHERE ")
		out.WriteString(us.Where.String())
	} else if us.CurrentOfCursor != nil {
		out.WriteString(" WHERE CURRENT OF ")
		out.WriteString(us.CurrentOfCursor.String())
	}

	return out.String()
}

// DeleteStatement represents a DELETE statement.
type DeleteStatement struct {
	Token           token.Token
	Top             *TopClause
	Table           *QualifiedIdentifier
	TargetFunc      *FunctionCall // For DELETE FROM OPENQUERY(...), DELETE FROM OPENROWSET(...)
	Hints           []string      // Table hints: WITH (TABLOCK), etc.
	Alias           *Identifier
	From            *FromClause
	Where           Expression
	CurrentOfCursor *Identifier // WHERE CURRENT OF cursor_name
	Output          *OutputClause
}

func (ds *DeleteStatement) statementNode()       {}
func (ds *DeleteStatement) TokenLiteral() string { return ds.Token.Literal }
func (ds *DeleteStatement) String() string {
	var out strings.Builder
	out.WriteString("DELETE")

	if ds.Top != nil {
		out.WriteString(" ")
		out.WriteString(ds.Top.String())
	}

	if ds.Alias != nil {
		out.WriteString(" ")
		out.WriteString(ds.Alias.Value)
	} else if ds.TargetFunc != nil {
		out.WriteString(" FROM ")
		out.WriteString(ds.TargetFunc.String())
	} else if ds.Table != nil {
		out.WriteString(" FROM ")
		out.WriteString(ds.Table.String())
	}

	if len(ds.Hints) > 0 {
		out.WriteString(" WITH (")
		out.WriteString(strings.Join(ds.Hints, ", "))
		out.WriteString(")")
	}

	if ds.Output != nil {
		out.WriteString(" ")
		out.WriteString(ds.Output.String())
	}

	if ds.From != nil {
		out.WriteString(" ")
		out.WriteString(ds.From.String())
	}

	if ds.Where != nil {
		out.WriteString(" WHERE ")
		out.WriteString(ds.Where.String())
	} else if ds.CurrentOfCursor != nil {
		out.WriteString(" WHERE CURRENT OF ")
		out.WriteString(ds.CurrentOfCursor.String())
	}

	return out.String()
}

// OutputClause represents an OUTPUT clause.
type OutputClause struct {
	Columns      []SelectColumn
	Into         *QualifiedIdentifier // INTO table
	IntoVariable *Variable            // INTO @variable
	IntoColumns  []*Identifier        // Column list: INTO @table(col1, col2)
}

func (oc *OutputClause) String() string {
	var out strings.Builder
	out.WriteString("OUTPUT ")
	var cols []string
	for _, c := range oc.Columns {
		cols = append(cols, c.String())
	}
	out.WriteString(strings.Join(cols, ", "))
	if oc.Into != nil {
		out.WriteString(" INTO ")
		out.WriteString(oc.Into.String())
	} else if oc.IntoVariable != nil {
		out.WriteString(" INTO ")
		out.WriteString(oc.IntoVariable.Name)
	}
	if len(oc.IntoColumns) > 0 {
		out.WriteString("(")
		var colNames []string
		for _, c := range oc.IntoColumns {
			colNames = append(colNames, c.Value)
		}
		out.WriteString(strings.Join(colNames, ", "))
		out.WriteString(")")
	}
	return out.String()
}

// -----------------------------------------------------------------------------
// MERGE Statement
// -----------------------------------------------------------------------------

// MergeActionType represents the type of action in a WHEN clause.
type MergeActionType int

const (
	MergeActionUpdate MergeActionType = iota
	MergeActionDelete
	MergeActionInsert
)

// MergeWhenType represents the type of WHEN clause.
type MergeWhenType int

const (
	MergeWhenMatched MergeWhenType = iota
	MergeWhenNotMatchedByTarget
	MergeWhenNotMatchedBySource
)

// MergeStatement represents a MERGE statement.
type MergeStatement struct {
	Token       token.Token
	Target      *QualifiedIdentifier
	TargetAlias *Identifier
	Source      TableReference // Can be table, subquery, etc.
	SourceAlias *Identifier
	OnCondition Expression
	WhenClauses []*MergeWhenClause
	Output      *OutputClause
}

func (ms *MergeStatement) statementNode()       {}
func (ms *MergeStatement) TokenLiteral() string { return ms.Token.Literal }
func (ms *MergeStatement) String() string {
	var out strings.Builder
	out.WriteString("MERGE INTO ")
	out.WriteString(ms.Target.String())
	if ms.TargetAlias != nil {
		out.WriteString(" AS ")
		out.WriteString(ms.TargetAlias.Value)
	}
	out.WriteString(" USING ")
	out.WriteString(ms.Source.String())
	if ms.SourceAlias != nil {
		out.WriteString(" AS ")
		out.WriteString(ms.SourceAlias.Value)
	}
	out.WriteString(" ON ")
	out.WriteString(ms.OnCondition.String())

	for _, when := range ms.WhenClauses {
		out.WriteString(" ")
		out.WriteString(when.String())
	}

	if ms.Output != nil {
		out.WriteString(" ")
		out.WriteString(ms.Output.String())
	}

	return out.String()
}

// MergeWhenClause represents a WHEN clause in a MERGE statement.
type MergeWhenClause struct {
	Type       MergeWhenType
	Condition  Expression // Optional AND condition
	Action     MergeActionType
	SetClauses []*SetClause  // For UPDATE
	Columns    []*Identifier // For INSERT
	Values     []Expression  // For INSERT
}

func (mw *MergeWhenClause) String() string {
	var out strings.Builder

	switch mw.Type {
	case MergeWhenMatched:
		out.WriteString("WHEN MATCHED")
	case MergeWhenNotMatchedByTarget:
		out.WriteString("WHEN NOT MATCHED")
	case MergeWhenNotMatchedBySource:
		out.WriteString("WHEN NOT MATCHED BY SOURCE")
	}

	if mw.Condition != nil {
		out.WriteString(" AND ")
		out.WriteString(mw.Condition.String())
	}

	out.WriteString(" THEN ")

	switch mw.Action {
	case MergeActionUpdate:
		out.WriteString("UPDATE SET ")
		var sets []string
		for _, s := range mw.SetClauses {
			sets = append(sets, s.Column.String()+" = "+s.Value.String())
		}
		out.WriteString(strings.Join(sets, ", "))
	case MergeActionDelete:
		out.WriteString("DELETE")
	case MergeActionInsert:
		out.WriteString("INSERT")
		if len(mw.Columns) > 0 {
			out.WriteString(" (")
			var cols []string
			for _, c := range mw.Columns {
				cols = append(cols, c.Value)
			}
			out.WriteString(strings.Join(cols, ", "))
			out.WriteString(")")
		}
		out.WriteString(" VALUES (")
		var vals []string
		for _, v := range mw.Values {
			vals = append(vals, v.String())
		}
		out.WriteString(strings.Join(vals, ", "))
		out.WriteString(")")
	}

	return out.String()
}

// -----------------------------------------------------------------------------
// Stored Procedure Statements
// -----------------------------------------------------------------------------

// CreateProcedureStatement represents a CREATE PROCEDURE statement.
type CreateProcedureStatement struct {
	Token      token.Token
	Name       *QualifiedIdentifier
	Parameters []*ParameterDef
	Body       *BeginEndBlock
	Options    []string
}

func (cp *CreateProcedureStatement) statementNode()       {}
func (cp *CreateProcedureStatement) TokenLiteral() string { return cp.Token.Literal }
func (cp *CreateProcedureStatement) String() string {
	var out strings.Builder
	out.WriteString("CREATE PROCEDURE ")
	out.WriteString(cp.Name.String())

	if len(cp.Parameters) > 0 {
		out.WriteString("\n")
		var params []string
		for _, p := range cp.Parameters {
			params = append(params, p.String())
		}
		out.WriteString(strings.Join(params, ",\n"))
	}

	out.WriteString("\nAS\n")
	out.WriteString(cp.Body.String())

	return out.String()
}

// ParameterDef represents a parameter definition.
type ParameterDef struct {
	Name     string
	DataType *DataType
	Default  Expression
	Output   bool
	ReadOnly bool
}

func (pd *ParameterDef) String() string {
	result := pd.Name + " " + pd.DataType.String()
	if pd.Default != nil {
		result += " = " + pd.Default.String()
	}
	if pd.Output {
		result += " OUTPUT"
	}
	if pd.ReadOnly {
		result += " READONLY"
	}
	return result
}

// DataType represents a T-SQL data type.
type DataType struct {
	Name      string
	Length    *int
	Precision *int
	Scale     *int
	Max       bool
	XmlSchema string // For typed XML: XML(schema_name)
}

func (dt *DataType) String() string {
	result := dt.Name
	if dt.XmlSchema != "" {
		result += "(" + dt.XmlSchema + ")"
	} else if dt.Max {
		result += "(MAX)"
	} else if dt.Precision != nil && dt.Scale != nil {
		result += "(" + itoa(*dt.Precision) + ", " + itoa(*dt.Scale) + ")"
	} else if dt.Length != nil {
		result += "(" + itoa(*dt.Length) + ")"
	} else if dt.Precision != nil {
		result += "(" + itoa(*dt.Precision) + ")"
	}
	return result
}

func itoa(i int) string {
	return fmt.Sprintf("%d", i)
}

// -----------------------------------------------------------------------------
// Control Flow Statements
// -----------------------------------------------------------------------------

// DeclareStatement represents a DECLARE statement.
type DeclareStatement struct {
	Token     token.Token
	Variables []*VariableDef
}

type VariableDef struct {
	Name      string
	DataType  *DataType
	TableType *TableTypeDefinition // For DECLARE @t TABLE (...)
	Value     Expression
}

func (ds *DeclareStatement) statementNode()       {}
func (ds *DeclareStatement) TokenLiteral() string { return ds.Token.Literal }
func (ds *DeclareStatement) String() string {
	var out strings.Builder
	out.WriteString("DECLARE ")
	var vars []string
	for _, v := range ds.Variables {
		var def string
		if v.TableType != nil {
			def = v.Name + " " + v.TableType.String()
		} else {
			def = v.Name + " " + v.DataType.String()
			if v.Value != nil {
				def += " = " + v.Value.String()
			}
		}
		vars = append(vars, def)
	}
	out.WriteString(strings.Join(vars, ", "))
	return out.String()
}

// SetStatement represents a SET statement.
type SetStatement struct {
	Token    token.Token
	Variable Expression
	Value    Expression
	Option   string // For SET options like NOCOUNT, etc.
	OnOff    string // ON or OFF for SET options
}

func (ss *SetStatement) statementNode()       {}
func (ss *SetStatement) TokenLiteral() string { return ss.Token.Literal }
func (ss *SetStatement) String() string {
	if ss.Option != "" {
		return "SET " + ss.Option + " " + ss.OnOff
	}
	// For method calls like @xml.modify(...), no value assignment
	if ss.Value == nil {
		return "SET " + ss.Variable.String()
	}
	return "SET " + ss.Variable.String() + " = " + ss.Value.String()
}

// IfStatement represents an IF statement.
type IfStatement struct {
	Token       token.Token
	Condition   Expression
	Consequence Statement
	Alternative Statement
}

func (is *IfStatement) statementNode()       {}
func (is *IfStatement) TokenLiteral() string { return is.Token.Literal }
func (is *IfStatement) String() string {
	var out strings.Builder
	out.WriteString("IF ")
	out.WriteString(is.Condition.String())
	out.WriteString("\n")
	out.WriteString(is.Consequence.String())
	if is.Alternative != nil {
		out.WriteString("\nELSE\n")
		out.WriteString(is.Alternative.String())
	}
	return out.String()
}

// WhileStatement represents a WHILE statement.
type WhileStatement struct {
	Token     token.Token
	Condition Expression
	Body      Statement
}

func (ws *WhileStatement) statementNode()       {}
func (ws *WhileStatement) TokenLiteral() string { return ws.Token.Literal }
func (ws *WhileStatement) String() string {
	var out strings.Builder
	out.WriteString("WHILE ")
	out.WriteString(ws.Condition.String())
	out.WriteString("\n")
	out.WriteString(ws.Body.String())
	return out.String()
}

// BeginEndBlock represents a BEGIN...END block.
type BeginEndBlock struct {
	Token      token.Token
	Statements []Statement
}

func (be *BeginEndBlock) statementNode()       {}
func (be *BeginEndBlock) TokenLiteral() string { return be.Token.Literal }
func (be *BeginEndBlock) String() string {
	var out strings.Builder
	out.WriteString("BEGIN\n")
	for _, s := range be.Statements {
		out.WriteString("    ")
		out.WriteString(s.String())
		out.WriteString("\n")
	}
	out.WriteString("END")
	return out.String()
}

// TryCatchStatement represents a TRY...CATCH block.
type TryCatchStatement struct {
	Token      token.Token
	TryBlock   *BeginEndBlock
	CatchBlock *BeginEndBlock
}

func (tc *TryCatchStatement) statementNode()       {}
func (tc *TryCatchStatement) TokenLiteral() string { return tc.Token.Literal }
func (tc *TryCatchStatement) String() string {
	var out strings.Builder
	out.WriteString("BEGIN TRY\n")
	for _, s := range tc.TryBlock.Statements {
		out.WriteString("    ")
		out.WriteString(s.String())
		out.WriteString("\n")
	}
	out.WriteString("END TRY\nBEGIN CATCH\n")
	for _, s := range tc.CatchBlock.Statements {
		out.WriteString("    ")
		out.WriteString(s.String())
		out.WriteString("\n")
	}
	out.WriteString("END CATCH")
	return out.String()
}

// ReturnStatement represents a RETURN statement.
type ReturnStatement struct {
	Token token.Token
	Value Expression
}

func (rs *ReturnStatement) statementNode()       {}
func (rs *ReturnStatement) TokenLiteral() string { return rs.Token.Literal }
func (rs *ReturnStatement) String() string {
	if rs.Value != nil {
		return "RETURN " + rs.Value.String()
	}
	return "RETURN"
}

// BreakStatement represents a BREAK statement.
type BreakStatement struct {
	Token token.Token
}

func (bs *BreakStatement) statementNode()       {}
func (bs *BreakStatement) TokenLiteral() string { return bs.Token.Literal }
func (bs *BreakStatement) String() string       { return "BREAK" }

// ContinueStatement represents a CONTINUE statement.
type ContinueStatement struct {
	Token token.Token
}

func (cs *ContinueStatement) statementNode()       {}
func (cs *ContinueStatement) TokenLiteral() string { return cs.Token.Literal }
func (cs *ContinueStatement) String() string       { return "CONTINUE" }

// PrintStatement represents a PRINT statement.
type PrintStatement struct {
	Token      token.Token
	Expression Expression
}

func (ps *PrintStatement) statementNode()       {}
func (ps *PrintStatement) TokenLiteral() string { return ps.Token.Literal }
func (ps *PrintStatement) String() string {
	return "PRINT " + ps.Expression.String()
}

// ExecStatement represents an EXEC/EXECUTE statement.
type ExecStatement struct {
	Token          token.Token
	ReturnVariable *Identifier // @ReturnCode = ...
	Procedure      *QualifiedIdentifier
	Parameters     []*ExecParameter
	DynamicSQL     Expression             // For EXEC('dynamic sql')
	AtServer       *Identifier            // For EXEC(...) AT LinkedServer
	Recompile      bool                   // WITH RECOMPILE
	ResultSets     []*ResultSetDefinition // WITH RESULT SETS ((...), (...))
	ResultSetsMode string                 // "UNDEFINED" or "NONE" for WITH RESULT SETS UNDEFINED/NONE
}

// ResultSetDefinition represents a result set column definition in EXEC WITH RESULT SETS
type ResultSetDefinition struct {
	Columns []*ResultSetColumn
}

// ResultSetColumn represents a column in a result set definition
type ResultSetColumn struct {
	Name     string
	DataType *DataType
	Nullable bool // true = NULL, false = NOT NULL or unspecified
	HasNull  bool // whether NULL/NOT NULL was specified
}

type ExecParameter struct {
	Name   string
	Value  Expression
	Output bool
}

func (es *ExecStatement) statementNode()       {}
func (es *ExecStatement) TokenLiteral() string { return es.Token.Literal }
func (es *ExecStatement) String() string {
	if es.DynamicSQL != nil {
		result := "EXEC(" + es.DynamicSQL.String() + ")"
		if es.AtServer != nil {
			result += " AT " + es.AtServer.String()
		}
		return result
	}
	var out strings.Builder
	out.WriteString("EXEC ")
	if es.ReturnVariable != nil {
		out.WriteString(es.ReturnVariable.String())
		out.WriteString(" = ")
	}
	out.WriteString(es.Procedure.String())

	if len(es.Parameters) > 0 {
		out.WriteString(" ")
		var params []string
		for _, p := range es.Parameters {
			param := p.Value.String()
			if p.Name != "" {
				param = p.Name + " = " + param
			}
			if p.Output {
				param += " OUTPUT"
			}
			params = append(params, param)
		}
		out.WriteString(strings.Join(params, ", "))
	}

	if len(es.ResultSets) > 0 {
		out.WriteString(" WITH RESULT SETS (")
		var sets []string
		for _, rs := range es.ResultSets {
			var cols []string
			for _, col := range rs.Columns {
				colDef := col.Name + " " + col.DataType.String()
				cols = append(cols, colDef)
			}
			sets = append(sets, "("+strings.Join(cols, ", ")+")")
		}
		out.WriteString(strings.Join(sets, ", "))
		out.WriteString(")")
	}

	return out.String()
}

// ThrowStatement represents a THROW statement.
type ThrowStatement struct {
	Token    token.Token
	ErrorNum Expression
	Message  Expression
	State    Expression
}

func (ts *ThrowStatement) statementNode()       {}
func (ts *ThrowStatement) TokenLiteral() string { return ts.Token.Literal }
func (ts *ThrowStatement) String() string {
	if ts.ErrorNum == nil {
		return "THROW"
	}
	return "THROW " + ts.ErrorNum.String() + ", " + ts.Message.String() + ", " + ts.State.String()
}

// RaiserrorStatement represents a RAISERROR statement.
type RaiserrorStatement struct {
	Token    token.Token
	Message  Expression
	Severity Expression
	State    Expression
	Args     []Expression // Additional format arguments
	Options  []string
}

func (rs *RaiserrorStatement) statementNode()       {}
func (rs *RaiserrorStatement) TokenLiteral() string { return rs.Token.Literal }
func (rs *RaiserrorStatement) String() string {
	var out strings.Builder
	out.WriteString("RAISERROR(")
	out.WriteString(rs.Message.String())
	out.WriteString(", ")
	out.WriteString(rs.Severity.String())
	out.WriteString(", ")
	out.WriteString(rs.State.String())
	for _, arg := range rs.Args {
		out.WriteString(", ")
		out.WriteString(arg.String())
	}
	out.WriteString(")")
	if len(rs.Options) > 0 {
		out.WriteString(" WITH ")
		out.WriteString(strings.Join(rs.Options, ", "))
	}
	return out.String()
}

// -----------------------------------------------------------------------------
// Transaction Statements
// -----------------------------------------------------------------------------

// BeginTransactionStatement represents BEGIN TRANSACTION.
type BeginTransactionStatement struct {
	Token token.Token
	Name  *Identifier
	Mark  string // WITH MARK 'description'
}

func (bt *BeginTransactionStatement) statementNode()       {}
func (bt *BeginTransactionStatement) TokenLiteral() string { return bt.Token.Literal }
func (bt *BeginTransactionStatement) String() string {
	if bt.Name != nil {
		return "BEGIN TRANSACTION " + bt.Name.Value
	}
	return "BEGIN TRANSACTION"
}

// CommitTransactionStatement represents COMMIT TRANSACTION.
type CommitTransactionStatement struct {
	Token token.Token
	Name  *Identifier
}

func (ct *CommitTransactionStatement) statementNode()       {}
func (ct *CommitTransactionStatement) TokenLiteral() string { return ct.Token.Literal }
func (ct *CommitTransactionStatement) String() string {
	if ct.Name != nil {
		return "COMMIT TRANSACTION " + ct.Name.Value
	}
	return "COMMIT TRANSACTION"
}

// RollbackTransactionStatement represents ROLLBACK TRANSACTION.
type RollbackTransactionStatement struct {
	Token token.Token
	Name  *Identifier
}

func (rt *RollbackTransactionStatement) statementNode()       {}
func (rt *RollbackTransactionStatement) TokenLiteral() string { return rt.Token.Literal }
func (rt *RollbackTransactionStatement) String() string {
	if rt.Name != nil {
		return "ROLLBACK TRANSACTION " + rt.Name.Value
	}
	return "ROLLBACK TRANSACTION"
}

// -----------------------------------------------------------------------------
// CTE (Common Table Expression)
// -----------------------------------------------------------------------------

// WithStatement represents a WITH (CTE) statement.
type WithStatement struct {
	Token token.Token
	CTEs  []*CTEDef
	Query Statement // The main query following the CTEs
}

type CTEDef struct {
	Name    *Identifier
	Columns []*Identifier
	Query   *SelectStatement
}

// WithXmlnamespacesStatement represents WITH XMLNAMESPACES (...) SELECT ...
type WithXmlnamespacesStatement struct {
	Token      token.Token
	Namespaces []*XmlNamespaceDef
	Query      Statement
}

func (w *WithXmlnamespacesStatement) statementNode()       {}
func (w *WithXmlnamespacesStatement) TokenLiteral() string { return w.Token.Literal }
func (w *WithXmlnamespacesStatement) String() string {
	var out strings.Builder
	out.WriteString("WITH XMLNAMESPACES (")
	for i, ns := range w.Namespaces {
		if i > 0 {
			out.WriteString(", ")
		}
		out.WriteString(ns.String())
	}
	out.WriteString(") ")
	if w.Query != nil {
		out.WriteString(w.Query.String())
	}
	return out.String()
}

// XmlNamespaceDef represents a single namespace declaration
type XmlNamespaceDef struct {
	URI       string
	Prefix    string // empty for DEFAULT namespace
	IsDefault bool
}

func (x *XmlNamespaceDef) String() string {
	if x.IsDefault {
		return "DEFAULT '" + x.URI + "'"
	}
	return "'" + x.URI + "' AS " + x.Prefix
}

func (ws *WithStatement) statementNode()       {}
func (ws *WithStatement) TokenLiteral() string { return ws.Token.Literal }
func (ws *WithStatement) String() string {
	var out strings.Builder
	out.WriteString("WITH ")

	var ctes []string
	for _, cte := range ws.CTEs {
		def := cte.Name.Value
		if len(cte.Columns) > 0 {
			var cols []string
			for _, c := range cte.Columns {
				cols = append(cols, c.Value)
			}
			def += " (" + strings.Join(cols, ", ") + ")"
		}
		def += " AS (" + cte.Query.String() + ")"
		ctes = append(ctes, def)
	}
	out.WriteString(strings.Join(ctes, ", "))
	out.WriteString("\n")
	out.WriteString(ws.Query.String())

	return out.String()
}

// GoStatement represents a GO batch separator.
type GoStatement struct {
	Token token.Token
	Count *int
}

func (gs *GoStatement) statementNode()       {}
func (gs *GoStatement) TokenLiteral() string { return gs.Token.Literal }
func (gs *GoStatement) String() string {
	if gs.Count != nil {
		return "GO " + itoa(*gs.Count)
	}
	return "GO"
}

// EnableDisableTriggerStatement represents ENABLE/DISABLE TRIGGER statements
type EnableDisableTriggerStatement struct {
	Token       token.Token
	Enable      bool                 // true = ENABLE, false = DISABLE
	TriggerName *Identifier          // nil if AllTriggers is true
	AllTriggers bool                 // ENABLE/DISABLE TRIGGER ALL
	TableName   *QualifiedIdentifier // Target table
	OnDatabase  bool                 // ON DATABASE
	OnAllServer bool                 // ON ALL SERVER
}

func (s *EnableDisableTriggerStatement) statementNode()       {}
func (s *EnableDisableTriggerStatement) TokenLiteral() string { return s.Token.Literal }
func (s *EnableDisableTriggerStatement) String() string {
	var out strings.Builder
	if s.Enable {
		out.WriteString("ENABLE TRIGGER ")
	} else {
		out.WriteString("DISABLE TRIGGER ")
	}
	if s.AllTriggers {
		out.WriteString("ALL")
	} else if s.TriggerName != nil {
		out.WriteString(s.TriggerName.Value)
	}
	out.WriteString(" ON ")
	if s.OnDatabase {
		out.WriteString("DATABASE")
	} else if s.OnAllServer {
		out.WriteString("ALL SERVER")
	} else if s.TableName != nil {
		out.WriteString(s.TableName.String())
	}
	return out.String()
}

// ExpressionStatement wraps an expression as a statement.
type ExpressionStatement struct {
	Token      token.Token
	Expression Expression
}

func (es *ExpressionStatement) statementNode()       {}
func (es *ExpressionStatement) TokenLiteral() string { return es.Token.Literal }
func (es *ExpressionStatement) String() string {
	if es.Expression != nil {
		return es.Expression.String()
	}
	return ""
}

// -----------------------------------------------------------------------------
// Stage 1: Table Infrastructure
// -----------------------------------------------------------------------------

// ColumnDefinition represents a column definition in CREATE TABLE or table variable.
type ColumnDefinition struct {
	Token           token.Token
	Name            *Identifier
	DataType        *DataType
	Nullable        *bool // nil = not specified, true = NULL, false = NOT NULL
	Default         Expression
	Identity        *IdentitySpec
	IsRowGuidCol    bool // ROWGUIDCOL
	IsSparse        bool // SPARSE
	IsColumnSet     bool // COLUMN_SET FOR ALL_SPARSE_COLUMNS
	Collation       string
	Computed        Expression          // For computed columns: AS (expression)
	IsPersisted     bool                // PERSISTED for computed columns
	Constraints     []*ColumnConstraint // Inline constraints
	GeneratedAlways string              // "ROW START" or "ROW END" for temporal tables
	InlineIndex     *InlineIndex        // INDEX index_name [CLUSTERED|NONCLUSTERED]
}

// InlineIndex represents an inline index definition on a column
type InlineIndex struct {
	Name      string
	Clustered *bool // nil = not specified, true = CLUSTERED, false = NONCLUSTERED
}

func (cd *ColumnDefinition) String() string {
	var out strings.Builder
	out.WriteString(cd.Name.Value)

	if cd.Computed != nil {
		out.WriteString(" AS (")
		out.WriteString(cd.Computed.String())
		out.WriteString(")")
		if cd.IsPersisted {
			out.WriteString(" PERSISTED")
		}
	} else {
		out.WriteString(" ")
		out.WriteString(cd.DataType.String())
	}

	if cd.Collation != "" {
		out.WriteString(" COLLATE ")
		out.WriteString(cd.Collation)
	}

	if cd.Nullable != nil {
		if *cd.Nullable {
			out.WriteString(" NULL")
		} else {
			out.WriteString(" NOT NULL")
		}
	}

	if cd.Identity != nil {
		out.WriteString(" ")
		out.WriteString(cd.Identity.String())
	}

	if cd.IsRowGuidCol {
		out.WriteString(" ROWGUIDCOL")
	}

	if cd.IsSparse {
		out.WriteString(" SPARSE")
	}

	if cd.IsColumnSet {
		out.WriteString(" COLUMN_SET FOR ALL_SPARSE_COLUMNS")
	}

	if cd.Default != nil {
		out.WriteString(" DEFAULT ")
		out.WriteString(cd.Default.String())
	}

	if cd.InlineIndex != nil {
		out.WriteString(" INDEX ")
		out.WriteString(cd.InlineIndex.Name)
		if cd.InlineIndex.Clustered != nil {
			if *cd.InlineIndex.Clustered {
				out.WriteString(" CLUSTERED")
			} else {
				out.WriteString(" NONCLUSTERED")
			}
		}
	}

	for _, c := range cd.Constraints {
		out.WriteString(" ")
		out.WriteString(c.String())
	}

	return out.String()
}

// IdentitySpec represents IDENTITY(seed, increment) specification.
type IdentitySpec struct {
	Seed      int64
	Increment int64
}

func (is *IdentitySpec) String() string {
	return fmt.Sprintf("IDENTITY(%d, %d)", is.Seed, is.Increment)
}

// ColumnConstraint represents an inline constraint on a column.
type ColumnConstraint struct {
	Name              string // Optional constraint name
	Type              ConstraintType
	IsPrimaryKey      bool
	IsClustered       *bool // nil = not specified
	ReferencesTable   *QualifiedIdentifier
	ReferencesColumns []*Identifier
	CheckExpression   Expression
	OnDelete          string // CASCADE, SET NULL, SET DEFAULT, NO ACTION
	OnUpdate          string
}

type ConstraintType int

const (
	ConstraintPrimaryKey ConstraintType = iota
	ConstraintForeignKey
	ConstraintUnique
	ConstraintCheck
	ConstraintDefault
	ConstraintPeriod // PERIOD FOR SYSTEM_TIME
	ConstraintIndex  // INDEX ix_name (columns)
)

func (cc *ColumnConstraint) String() string {
	var out strings.Builder

	if cc.Name != "" {
		out.WriteString("CONSTRAINT ")
		out.WriteString(cc.Name)
		out.WriteString(" ")
	}

	switch cc.Type {
	case ConstraintPrimaryKey:
		out.WriteString("PRIMARY KEY")
		if cc.IsClustered != nil {
			if *cc.IsClustered {
				out.WriteString(" CLUSTERED")
			} else {
				out.WriteString(" NONCLUSTERED")
			}
		}
	case ConstraintUnique:
		out.WriteString("UNIQUE")
	case ConstraintCheck:
		out.WriteString("CHECK (")
		out.WriteString(cc.CheckExpression.String())
		out.WriteString(")")
	case ConstraintForeignKey:
		out.WriteString("REFERENCES ")
		out.WriteString(cc.ReferencesTable.String())
		if len(cc.ReferencesColumns) > 0 {
			out.WriteString(" (")
			for i, col := range cc.ReferencesColumns {
				if i > 0 {
					out.WriteString(", ")
				}
				out.WriteString(col.Value)
			}
			out.WriteString(")")
		}
		if cc.OnDelete != "" {
			out.WriteString(" ON DELETE ")
			out.WriteString(cc.OnDelete)
		}
		if cc.OnUpdate != "" {
			out.WriteString(" ON UPDATE ")
			out.WriteString(cc.OnUpdate)
		}
	}

	return out.String()
}

// TableConstraint represents a table-level constraint in CREATE TABLE.
type TableConstraint struct {
	Token             token.Token
	Name              string
	Type              ConstraintType
	Columns           []*IndexColumn // For PK, UNIQUE, FK
	IsClustered       *bool
	IndexOptions      string // WITH (FILLFACTOR = 90, etc.)
	ReferencesTable   *QualifiedIdentifier
	ReferencesColumns []*Identifier
	CheckExpression   Expression
	DefaultExpression Expression  // For DEFAULT constraints
	ForColumn         *Identifier // For DEFAULT ... FOR column
	OnDelete          string
	OnUpdate          string
}

func (tc *TableConstraint) String() string {
	var out strings.Builder

	if tc.Name != "" {
		out.WriteString("CONSTRAINT ")
		out.WriteString(tc.Name)
		out.WriteString(" ")
	}

	switch tc.Type {
	case ConstraintPrimaryKey:
		out.WriteString("PRIMARY KEY")
		if tc.IsClustered != nil {
			if *tc.IsClustered {
				out.WriteString(" CLUSTERED")
			} else {
				out.WriteString(" NONCLUSTERED")
			}
		}
		out.WriteString(" (")
		for i, col := range tc.Columns {
			if i > 0 {
				out.WriteString(", ")
			}
			out.WriteString(col.String())
		}
		out.WriteString(")")
		if tc.IndexOptions != "" {
			out.WriteString(" WITH (")
			out.WriteString(tc.IndexOptions)
			out.WriteString(")")
		}

	case ConstraintUnique:
		out.WriteString("UNIQUE")
		if tc.IsClustered != nil {
			if *tc.IsClustered {
				out.WriteString(" CLUSTERED")
			} else {
				out.WriteString(" NONCLUSTERED")
			}
		}
		out.WriteString(" (")
		for i, col := range tc.Columns {
			if i > 0 {
				out.WriteString(", ")
			}
			out.WriteString(col.String())
		}
		out.WriteString(")")
		if tc.IndexOptions != "" {
			out.WriteString(" WITH (")
			out.WriteString(tc.IndexOptions)
			out.WriteString(")")
		}

	case ConstraintForeignKey:
		out.WriteString("FOREIGN KEY (")
		for i, col := range tc.Columns {
			if i > 0 {
				out.WriteString(", ")
			}
			out.WriteString(col.Name.Value)
		}
		out.WriteString(") REFERENCES ")
		out.WriteString(tc.ReferencesTable.String())
		out.WriteString(" (")
		for i, col := range tc.ReferencesColumns {
			if i > 0 {
				out.WriteString(", ")
			}
			out.WriteString(col.Value)
		}
		out.WriteString(")")
		if tc.OnDelete != "" {
			out.WriteString(" ON DELETE ")
			out.WriteString(tc.OnDelete)
		}
		if tc.OnUpdate != "" {
			out.WriteString(" ON UPDATE ")
			out.WriteString(tc.OnUpdate)
		}

	case ConstraintCheck:
		out.WriteString("CHECK (")
		out.WriteString(tc.CheckExpression.String())
		out.WriteString(")")

	case ConstraintDefault:
		out.WriteString("DEFAULT ")
		if tc.DefaultExpression != nil {
			out.WriteString("(")
			out.WriteString(tc.DefaultExpression.String())
			out.WriteString(")")
		}
		if tc.ForColumn != nil {
			out.WriteString(" FOR ")
			out.WriteString(tc.ForColumn.Value)
		}

	case ConstraintPeriod:
		out.WriteString("PERIOD FOR SYSTEM_TIME (")
		for i, col := range tc.Columns {
			if i > 0 {
				out.WriteString(", ")
			}
			out.WriteString(col.Name.Value)
		}
		out.WriteString(")")

	case ConstraintIndex:
		out.WriteString("INDEX ")
		out.WriteString(tc.Name)
		if tc.IsClustered != nil {
			if *tc.IsClustered {
				out.WriteString(" CLUSTERED")
			} else {
				out.WriteString(" NONCLUSTERED")
			}
		}
		out.WriteString(" (")
		for i, col := range tc.Columns {
			if i > 0 {
				out.WriteString(", ")
			}
			out.WriteString(col.String())
		}
		out.WriteString(")")
	}

	return out.String()
}

// IndexColumn represents a column in an index or constraint with optional ordering.
type IndexColumn struct {
	Name       *Identifier
	Descending bool
}

func (ic *IndexColumn) String() string {
	if ic.Descending {
		return ic.Name.Value + " DESC"
	}
	return ic.Name.Value
}

// CreateTableStatement represents a CREATE TABLE statement.
type CreateTableStatement struct {
	Token       token.Token
	Name        *QualifiedIdentifier
	IsTemporary bool // #temp or ##global
	Columns     []*ColumnDefinition
	Constraints []*TableConstraint
	AsSelect    *SelectStatement // CREATE TABLE ... AS SELECT
	FileGroup   string           // ON [filegroup]
	TextImageOn string           // TEXTIMAGE_ON [filegroup]
}

func (ct *CreateTableStatement) statementNode()       {}
func (ct *CreateTableStatement) TokenLiteral() string { return ct.Token.Literal }
func (ct *CreateTableStatement) String() string {
	var out strings.Builder
	out.WriteString("CREATE TABLE ")
	out.WriteString(ct.Name.String())
	out.WriteString(" (\n")

	for i, col := range ct.Columns {
		out.WriteString("    ")
		out.WriteString(col.String())
		if i < len(ct.Columns)-1 || len(ct.Constraints) > 0 {
			out.WriteString(",")
		}
		out.WriteString("\n")
	}

	for i, con := range ct.Constraints {
		out.WriteString("    ")
		out.WriteString(con.String())
		if i < len(ct.Constraints)-1 {
			out.WriteString(",")
		}
		out.WriteString("\n")
	}

	out.WriteString(")")
	if ct.FileGroup != "" {
		out.WriteString(" ON ")
		out.WriteString(ct.FileGroup)
	}
	if ct.TextImageOn != "" {
		out.WriteString(" TEXTIMAGE_ON ")
		out.WriteString(ct.TextImageOn)
	}
	return out.String()
}

// DropTableStatement represents a DROP TABLE statement.
type DropTableStatement struct {
	Token    token.Token
	IfExists bool
	Tables   []*QualifiedIdentifier
}

func (dt *DropTableStatement) statementNode()       {}
func (dt *DropTableStatement) TokenLiteral() string { return dt.Token.Literal }
func (dt *DropTableStatement) String() string {
	var out strings.Builder
	out.WriteString("DROP TABLE ")
	if dt.IfExists {
		out.WriteString("IF EXISTS ")
	}
	for i, t := range dt.Tables {
		if i > 0 {
			out.WriteString(", ")
		}
		out.WriteString(t.String())
	}
	return out.String()
}

// TruncateTableStatement represents a TRUNCATE TABLE statement.
type TruncateTableStatement struct {
	Token      token.Token
	Table      *QualifiedIdentifier
	Partitions []PartitionRange // WITH (PARTITIONS (1, 2, 3)) or (5 TO 10)
}

// PartitionRange represents a partition number or range
type PartitionRange struct {
	Start int
	End   int // 0 if single partition, non-zero if range (TO)
}

func (tt *TruncateTableStatement) statementNode()       {}
func (tt *TruncateTableStatement) TokenLiteral() string { return tt.Token.Literal }
func (tt *TruncateTableStatement) String() string {
	result := "TRUNCATE TABLE " + tt.Table.String()
	if len(tt.Partitions) > 0 {
		result += " WITH (PARTITIONS ("
		for i, p := range tt.Partitions {
			if i > 0 {
				result += ", "
			}
			if p.End > 0 {
				result += fmt.Sprintf("%d TO %d", p.Start, p.End)
			} else {
				result += fmt.Sprintf("%d", p.Start)
			}
		}
		result += "))"
	}
	return result
}

// AlterTableStatement represents an ALTER TABLE statement.
type AlterTableStatement struct {
	Token       token.Token
	Table       *QualifiedIdentifier
	Actions     []*AlterTableAction
	WithCheck   bool // WITH CHECK modifier
	WithNoCheck bool // WITH NOCHECK modifier
}

func (at *AlterTableStatement) statementNode()       {}
func (at *AlterTableStatement) TokenLiteral() string { return at.Token.Literal }
func (at *AlterTableStatement) String() string {
	var out strings.Builder
	out.WriteString("ALTER TABLE ")
	out.WriteString(at.Table.String())
	for _, action := range at.Actions {
		out.WriteString(" ")
		out.WriteString(action.String())
	}
	return out.String()
}

// AlterTableAction represents an action in ALTER TABLE.
type AlterTableAction struct {
	Type           AlterActionType
	Column         *ColumnDefinition
	Columns        []*ColumnDefinition // For ADD with multiple columns
	ColumnName     *Identifier
	NewDataType    *DataType
	Constraint     *TableConstraint
	ConstraintName string
	NewColumnName  *Identifier
	TriggerName    string            // For ENABLE/DISABLE TRIGGER
	AllTriggers    bool              // For ENABLE/DISABLE TRIGGER ALL
	AllConstraints bool              // For CHECK/NOCHECK CONSTRAINT ALL
	Options        map[string]string // For SET (option = value)
	RawOptions     string            // For SWITCH, REBUILD, etc.
}

type AlterActionType int

const (
	AlterAddColumn AlterActionType = iota
	AlterDropColumn
	AlterAlterColumn
	AlterAddConstraint
	AlterDropConstraint
	AlterRenameColumn
	AlterEnableTrigger
	AlterDisableTrigger
	AlterSetOption
	AlterCheckConstraint   // CHECK CONSTRAINT name
	AlterNoCheckConstraint // NOCHECK CONSTRAINT name
	AlterSwitch            // SWITCH [PARTITION n] TO target [PARTITION n]
	AlterRebuild           // REBUILD
)

func (aa *AlterTableAction) String() string {
	switch aa.Type {
	case AlterAddColumn:
		return "ADD " + aa.Column.String()
	case AlterDropColumn:
		return "DROP COLUMN " + aa.ColumnName.Value
	case AlterAlterColumn:
		return "ALTER COLUMN " + aa.ColumnName.Value + " " + aa.NewDataType.String()
	case AlterAddConstraint:
		return "ADD " + aa.Constraint.String()
	case AlterDropConstraint:
		return "DROP CONSTRAINT " + aa.ConstraintName
	case AlterRenameColumn:
		return "RENAME COLUMN " + aa.ColumnName.Value + " TO " + aa.NewColumnName.Value
	case AlterEnableTrigger:
		if aa.AllTriggers {
			return "ENABLE TRIGGER ALL"
		}
		return "ENABLE TRIGGER " + aa.TriggerName
	case AlterDisableTrigger:
		if aa.AllTriggers {
			return "DISABLE TRIGGER ALL"
		}
		return "DISABLE TRIGGER " + aa.TriggerName
	case AlterSetOption:
		var parts []string
		for k, v := range aa.Options {
			parts = append(parts, k+" = "+v)
		}
		return "SET (" + strings.Join(parts, ", ") + ")"
	case AlterCheckConstraint:
		if aa.AllConstraints {
			return "CHECK CONSTRAINT ALL"
		}
		return "CHECK CONSTRAINT " + aa.ConstraintName
	case AlterNoCheckConstraint:
		if aa.AllConstraints {
			return "NOCHECK CONSTRAINT ALL"
		}
		return "NOCHECK CONSTRAINT " + aa.ConstraintName
	case AlterSwitch:
		return "SWITCH " + aa.RawOptions
	case AlterRebuild:
		if aa.RawOptions != "" {
			return "REBUILD " + aa.RawOptions
		}
		return "REBUILD"
	}
	return ""
}

// TableTypeDefinition represents a TABLE type for table variables.
type TableTypeDefinition struct {
	Columns     []*ColumnDefinition
	Constraints []*TableConstraint
}

func (tt *TableTypeDefinition) String() string {
	var out strings.Builder
	out.WriteString("TABLE (")

	for i, col := range tt.Columns {
		if i > 0 {
			out.WriteString(", ")
		}
		out.WriteString(col.String())
	}

	for i, con := range tt.Constraints {
		if i > 0 || len(tt.Columns) > 0 {
			out.WriteString(", ")
		}
		out.WriteString(con.String())
	}

	out.WriteString(")")
	return out.String()
}

// -----------------------------------------------------------------------------
// Stage 2: Cursor Support
// -----------------------------------------------------------------------------

// DeclareCursorStatement represents DECLARE cursor_name CURSOR ... FOR SELECT.
type DeclareCursorStatement struct {
	Token            token.Token
	Name             *Identifier
	Options          *CursorOptions
	ForSelect        *SelectStatement
	ForUpdateColumns []string // FOR UPDATE OF col1, col2
}

func (dc *DeclareCursorStatement) statementNode()       {}
func (dc *DeclareCursorStatement) TokenLiteral() string { return dc.Token.Literal }
func (dc *DeclareCursorStatement) String() string {
	var out strings.Builder
	out.WriteString("DECLARE ")
	out.WriteString(dc.Name.Value)
	out.WriteString(" CURSOR")
	if dc.Options != nil {
		out.WriteString(dc.Options.String())
	}
	if dc.ForSelect != nil {
		out.WriteString("\nFOR ")
		out.WriteString(dc.ForSelect.String())
	}
	return out.String()
}

// CursorOptions represents cursor declaration options.
type CursorOptions struct {
	Local       bool // LOCAL vs GLOBAL
	Global      bool
	ForwardOnly bool // FORWARD_ONLY vs SCROLL
	Scroll      bool
	Static      bool // STATIC, KEYSET, DYNAMIC, FAST_FORWARD
	Keyset      bool
	Dynamic     bool
	FastForward bool
	ReadOnly    bool // READ_ONLY, SCROLL_LOCKS, OPTIMISTIC
	ScrollLocks bool
	Optimistic  bool
	TypeWarning bool // TYPE_WARNING
}

func (co *CursorOptions) String() string {
	var parts []string
	if co.Local {
		parts = append(parts, "LOCAL")
	}
	if co.Global {
		parts = append(parts, "GLOBAL")
	}
	if co.ForwardOnly {
		parts = append(parts, "FORWARD_ONLY")
	}
	if co.Scroll {
		parts = append(parts, "SCROLL")
	}
	if co.Static {
		parts = append(parts, "STATIC")
	}
	if co.Keyset {
		parts = append(parts, "KEYSET")
	}
	if co.Dynamic {
		parts = append(parts, "DYNAMIC")
	}
	if co.FastForward {
		parts = append(parts, "FAST_FORWARD")
	}
	if co.ReadOnly {
		parts = append(parts, "READ_ONLY")
	}
	if co.ScrollLocks {
		parts = append(parts, "SCROLL_LOCKS")
	}
	if co.Optimistic {
		parts = append(parts, "OPTIMISTIC")
	}
	if co.TypeWarning {
		parts = append(parts, "TYPE_WARNING")
	}
	if len(parts) == 0 {
		return ""
	}
	return " " + strings.Join(parts, " ")
}

// OpenCursorStatement represents OPEN cursor_name.
type OpenCursorStatement struct {
	Token      token.Token
	CursorName *Identifier
}

func (oc *OpenCursorStatement) statementNode()       {}
func (oc *OpenCursorStatement) TokenLiteral() string { return oc.Token.Literal }
func (oc *OpenCursorStatement) String() string {
	return "OPEN " + oc.CursorName.Value
}

// FetchStatement represents FETCH [NEXT|PRIOR|FIRST|LAST|ABSOLUTE|RELATIVE] FROM cursor INTO vars.
type FetchStatement struct {
	Token      token.Token
	Direction  string     // NEXT, PRIOR, FIRST, LAST, ABSOLUTE, RELATIVE
	Offset     Expression // For ABSOLUTE n or RELATIVE n
	CursorName *Identifier
	IntoVars   []*Variable
}

func (fs *FetchStatement) statementNode()       {}
func (fs *FetchStatement) TokenLiteral() string { return fs.Token.Literal }
func (fs *FetchStatement) String() string {
	var out strings.Builder
	out.WriteString("FETCH ")
	if fs.Direction != "" {
		out.WriteString(fs.Direction)
		if fs.Offset != nil {
			out.WriteString(" ")
			out.WriteString(fs.Offset.String())
		}
		out.WriteString(" ")
	}
	out.WriteString("FROM ")
	out.WriteString(fs.CursorName.Value)
	if len(fs.IntoVars) > 0 {
		out.WriteString(" INTO ")
		for i, v := range fs.IntoVars {
			if i > 0 {
				out.WriteString(", ")
			}
			out.WriteString(v.Name)
		}
	}
	return out.String()
}

// CloseCursorStatement represents CLOSE cursor_name.
type CloseCursorStatement struct {
	Token      token.Token
	CursorName *Identifier
}

func (cc *CloseCursorStatement) statementNode()       {}
func (cc *CloseCursorStatement) TokenLiteral() string { return cc.Token.Literal }
func (cc *CloseCursorStatement) String() string {
	return "CLOSE " + cc.CursorName.Value
}

// DeallocateCursorStatement represents DEALLOCATE cursor_name.
type DeallocateCursorStatement struct {
	Token      token.Token
	CursorName *Identifier
}

func (dc *DeallocateCursorStatement) statementNode()       {}
func (dc *DeallocateCursorStatement) TokenLiteral() string { return dc.Token.Literal }
func (dc *DeallocateCursorStatement) String() string {
	return "DEALLOCATE " + dc.CursorName.Value
}

// -----------------------------------------------------------------------------
// Additional DDL Statements (Stage 5)
// -----------------------------------------------------------------------------

// CreateViewStatement represents a CREATE VIEW statement.
type CreateViewStatement struct {
	Token       token.Token
	Name        *QualifiedIdentifier
	Columns     []*Identifier // Optional column list
	Options     []string      // WITH SCHEMABINDING, etc.
	AsSelect    Statement     // Can be SelectStatement or WithStatement (CTE)
	CheckOption bool          // WITH CHECK OPTION
}

func (cv *CreateViewStatement) statementNode()       {}
func (cv *CreateViewStatement) TokenLiteral() string { return cv.Token.Literal }
func (cv *CreateViewStatement) String() string {
	var out strings.Builder
	out.WriteString("CREATE VIEW ")
	out.WriteString(cv.Name.String())
	if len(cv.Columns) > 0 {
		out.WriteString(" (")
		for i, col := range cv.Columns {
			if i > 0 {
				out.WriteString(", ")
			}
			out.WriteString(col.Value)
		}
		out.WriteString(")")
	}
	if len(cv.Options) > 0 {
		out.WriteString(" WITH ")
		out.WriteString(strings.Join(cv.Options, ", "))
	}
	out.WriteString(" AS ")
	out.WriteString(cv.AsSelect.String())
	return out.String()
}

// AlterViewStatement represents an ALTER VIEW statement.
type AlterViewStatement struct {
	Token    token.Token
	Name     *QualifiedIdentifier
	Columns  []*Identifier
	Options  []string
	AsSelect Statement // Can be SelectStatement or WithStatement (CTE)
}

func (av *AlterViewStatement) statementNode()       {}
func (av *AlterViewStatement) TokenLiteral() string { return av.Token.Literal }
func (av *AlterViewStatement) String() string {
	var out strings.Builder
	out.WriteString("ALTER VIEW ")
	out.WriteString(av.Name.String())
	if len(av.Columns) > 0 {
		out.WriteString(" (")
		for i, col := range av.Columns {
			if i > 0 {
				out.WriteString(", ")
			}
			out.WriteString(col.Value)
		}
		out.WriteString(")")
	}
	out.WriteString(" AS ")
	out.WriteString(av.AsSelect.String())
	return out.String()
}

// CreateIndexStatement represents a CREATE INDEX statement.
type CreateIndexStatement struct {
	Token          token.Token
	IsUnique       bool
	IsClustered    *bool // nil = not specified, true = CLUSTERED, false = NONCLUSTERED
	Name           *Identifier
	Table          *QualifiedIdentifier
	Columns        []*IndexColumn
	IncludeColumns []*Identifier
	Where          Expression
	Options        []string    // WITH (options)
	Filegroup      *Identifier // ON [filegroup]
}

func (ci *CreateIndexStatement) statementNode()       {}
func (ci *CreateIndexStatement) TokenLiteral() string { return ci.Token.Literal }
func (ci *CreateIndexStatement) String() string {
	var out strings.Builder
	out.WriteString("CREATE ")
	if ci.IsUnique {
		out.WriteString("UNIQUE ")
	}
	if ci.IsClustered != nil {
		if *ci.IsClustered {
			out.WriteString("CLUSTERED ")
		} else {
			out.WriteString("NONCLUSTERED ")
		}
	}
	out.WriteString("INDEX ")
	out.WriteString(ci.Name.Value)
	out.WriteString(" ON ")
	out.WriteString(ci.Table.String())
	out.WriteString(" (")
	for i, col := range ci.Columns {
		if i > 0 {
			out.WriteString(", ")
		}
		out.WriteString(col.String())
	}
	out.WriteString(")")
	if len(ci.IncludeColumns) > 0 {
		out.WriteString(" INCLUDE (")
		for i, col := range ci.IncludeColumns {
			if i > 0 {
				out.WriteString(", ")
			}
			out.WriteString(col.Value)
		}
		out.WriteString(")")
	}
	if ci.Where != nil {
		out.WriteString(" WHERE ")
		out.WriteString(ci.Where.String())
	}
	if ci.Filegroup != nil {
		out.WriteString(" ON ")
		out.WriteString(ci.Filegroup.Value)
	}
	return out.String()
}

// CreateXmlIndexStatement represents a CREATE PRIMARY/SECONDARY XML INDEX statement.
type CreateXmlIndexStatement struct {
	Token     token.Token
	IsPrimary bool
	Name      *Identifier
	Table     *QualifiedIdentifier
	Column    *Identifier
}

func (xi *CreateXmlIndexStatement) statementNode()       {}
func (xi *CreateXmlIndexStatement) TokenLiteral() string { return xi.Token.Literal }
func (xi *CreateXmlIndexStatement) String() string {
	var out strings.Builder
	out.WriteString("CREATE ")
	if xi.IsPrimary {
		out.WriteString("PRIMARY ")
	}
	out.WriteString("XML INDEX ")
	out.WriteString(xi.Name.Value)
	out.WriteString(" ON ")
	out.WriteString(xi.Table.String())
	out.WriteString("(")
	out.WriteString(xi.Column.Value)
	out.WriteString(")")
	return out.String()
}

// DropIndexStatement represents a DROP INDEX statement.
type DropIndexStatement struct {
	Token    token.Token
	IfExists bool
	Name     *Identifier
	Table    *QualifiedIdentifier
}

func (di *DropIndexStatement) statementNode()       {}
func (di *DropIndexStatement) TokenLiteral() string { return di.Token.Literal }
func (di *DropIndexStatement) String() string {
	var out strings.Builder
	out.WriteString("DROP INDEX ")
	if di.IfExists {
		out.WriteString("IF EXISTS ")
	}
	out.WriteString(di.Name.Value)
	out.WriteString(" ON ")
	out.WriteString(di.Table.String())
	return out.String()
}

// AlterIndexStatement represents an ALTER INDEX statement.
type AlterIndexStatement struct {
	Token   token.Token
	Name    *Identifier          // Index name or ALL
	Table   *QualifiedIdentifier // Table name
	Action  string               // REBUILD, REORGANIZE, DISABLE, etc.
	Options []string             // WITH options
}

func (ai *AlterIndexStatement) statementNode()       {}
func (ai *AlterIndexStatement) TokenLiteral() string { return ai.Token.Literal }
func (ai *AlterIndexStatement) String() string {
	var out strings.Builder
	out.WriteString("ALTER INDEX ")
	out.WriteString(ai.Name.Value)
	out.WriteString(" ON ")
	out.WriteString(ai.Table.String())
	out.WriteString(" ")
	out.WriteString(ai.Action)
	if len(ai.Options) > 0 {
		out.WriteString(" WITH (")
		out.WriteString(strings.Join(ai.Options, ", "))
		out.WriteString(")")
	}
	return out.String()
}

// BulkInsertStatement represents a BULK INSERT statement.
type BulkInsertStatement struct {
	Token    token.Token
	Table    *QualifiedIdentifier
	DataFile string
	Options  map[string]string
}

func (bi *BulkInsertStatement) statementNode()       {}
func (bi *BulkInsertStatement) TokenLiteral() string { return bi.Token.Literal }
func (bi *BulkInsertStatement) String() string {
	var out strings.Builder
	out.WriteString("BULK INSERT ")
	out.WriteString(bi.Table.String())
	out.WriteString(" FROM '")
	out.WriteString(bi.DataFile)
	out.WriteString("'")
	if len(bi.Options) > 0 {
		out.WriteString(" WITH (")
		var opts []string
		for k, v := range bi.Options {
			opts = append(opts, k+" = "+v)
		}
		out.WriteString(strings.Join(opts, ", "))
		out.WriteString(")")
	}
	return out.String()
}

// CreateTypeStatement represents a CREATE TYPE statement.
// Can be either an alias type (FROM base_type) or a table type (AS TABLE).
type CreateTypeStatement struct {
	Token       token.Token
	Name        *QualifiedIdentifier
	IsTableType bool                 // true for AS TABLE
	BaseType    *DataType            // For alias types: FROM base_type
	Nullable    *bool                // For alias types: NULL/NOT NULL
	TableDef    *TableTypeDefinition // For table types: AS TABLE (...)
}

func (ct *CreateTypeStatement) statementNode()       {}
func (ct *CreateTypeStatement) TokenLiteral() string { return ct.Token.Literal }
func (ct *CreateTypeStatement) String() string {
	var out strings.Builder
	out.WriteString("CREATE TYPE ")
	out.WriteString(ct.Name.String())
	if ct.IsTableType {
		out.WriteString(" AS TABLE (")
		// Table definition would be added here
		out.WriteString("...)")
	} else {
		out.WriteString(" FROM ")
		out.WriteString(ct.BaseType.String())
		if ct.Nullable != nil {
			if *ct.Nullable {
				out.WriteString(" NULL")
			} else {
				out.WriteString(" NOT NULL")
			}
		}
	}
	return out.String()
}

// FunctionType represents the type of function.
type FunctionType int

const (
	FunctionScalar FunctionType = iota
	FunctionInlineTable
	FunctionMultiStatementTable
)

// CreateFunctionStatement represents a CREATE FUNCTION statement.
type CreateFunctionStatement struct {
	Token        token.Token
	Name         *QualifiedIdentifier
	Parameters   []*ParameterDef
	ReturnType   *DataType            // For scalar functions
	ReturnsTable bool                 // For inline TVF: RETURNS TABLE
	TableDef     *TableTypeDefinition // For multi-statement TVF: RETURNS @var TABLE (...)
	TableVar     string               // Variable name for multi-statement TVF
	Options      []string             // WITH SCHEMABINDING, etc.
	AsReturn     Expression           // For inline TVF: AS RETURN (SELECT...)
	Body         *BeginEndBlock       // For scalar and multi-statement
}

func (cf *CreateFunctionStatement) statementNode()       {}
func (cf *CreateFunctionStatement) TokenLiteral() string { return cf.Token.Literal }
func (cf *CreateFunctionStatement) String() string {
	var out strings.Builder
	out.WriteString("CREATE FUNCTION ")
	out.WriteString(cf.Name.String())
	out.WriteString("(")
	for i, p := range cf.Parameters {
		if i > 0 {
			out.WriteString(", ")
		}
		out.WriteString(p.String())
	}
	out.WriteString(") RETURNS ")
	if cf.ReturnsTable {
		out.WriteString("TABLE")
	} else if cf.TableDef != nil {
		out.WriteString(cf.TableVar)
		out.WriteString(" TABLE (...)")
	} else if cf.ReturnType != nil {
		out.WriteString(cf.ReturnType.String())
	}
	out.WriteString(" AS ")
	if cf.Body != nil {
		out.WriteString(cf.Body.String())
	}
	return out.String()
}

// AlterFunctionStatement represents an ALTER FUNCTION statement.
type AlterFunctionStatement struct {
	Token        token.Token
	Name         *QualifiedIdentifier
	Parameters   []*ParameterDef
	ReturnType   *DataType
	ReturnsTable bool
	TableDef     *TableTypeDefinition
	TableVar     string
	Options      []string
	AsReturn     Expression
	Body         *BeginEndBlock
}

func (af *AlterFunctionStatement) statementNode()       {}
func (af *AlterFunctionStatement) TokenLiteral() string { return af.Token.Literal }
func (af *AlterFunctionStatement) String() string {
	var out strings.Builder
	out.WriteString("ALTER FUNCTION ")
	out.WriteString(af.Name.String())
	out.WriteString("(...)")
	return out.String()
}

// TriggerTiming represents when a trigger fires.
type TriggerTiming int

const (
	TriggerAfter TriggerTiming = iota
	TriggerInsteadOf
	TriggerFor
)

// CreateTriggerStatement represents a CREATE TRIGGER statement.
type CreateTriggerStatement struct {
	Token             token.Token
	Name              *QualifiedIdentifier
	Table             *QualifiedIdentifier
	OnDatabase        bool          // ON DATABASE
	OnAllServer       bool          // ON ALL SERVER
	Timing            TriggerTiming // AFTER, INSTEAD OF, FOR
	Events            []string      // INSERT, UPDATE, DELETE or DDL event types
	NotForReplication bool          // NOT FOR REPLICATION
	Body              *BeginEndBlock
	Options           []string
}

func (ct *CreateTriggerStatement) statementNode()       {}
func (ct *CreateTriggerStatement) TokenLiteral() string { return ct.Token.Literal }
func (ct *CreateTriggerStatement) String() string {
	var out strings.Builder
	out.WriteString("CREATE TRIGGER ")
	out.WriteString(ct.Name.String())
	out.WriteString(" ON ")
	if ct.OnDatabase {
		out.WriteString("DATABASE")
	} else if ct.OnAllServer {
		out.WriteString("ALL SERVER")
	} else if ct.Table != nil {
		out.WriteString(ct.Table.String())
	}
	if len(ct.Options) > 0 {
		out.WriteString(" WITH ")
		out.WriteString(strings.Join(ct.Options, ", "))
	}
	switch ct.Timing {
	case TriggerAfter:
		out.WriteString(" AFTER ")
	case TriggerInsteadOf:
		out.WriteString(" INSTEAD OF ")
	case TriggerFor:
		out.WriteString(" FOR ")
	}
	out.WriteString(strings.Join(ct.Events, ", "))
	out.WriteString(" AS ")
	if ct.Body != nil {
		out.WriteString(ct.Body.String())
	}
	return out.String()
}

// AlterTriggerStatement represents an ALTER TRIGGER statement.
type AlterTriggerStatement struct {
	Token  token.Token
	Name   *QualifiedIdentifier
	Table  *QualifiedIdentifier
	Timing TriggerTiming
	Events []string
	Body   *BeginEndBlock
}

func (at *AlterTriggerStatement) statementNode()       {}
func (at *AlterTriggerStatement) TokenLiteral() string { return at.Token.Literal }
func (at *AlterTriggerStatement) String() string {
	var out strings.Builder
	out.WriteString("ALTER TRIGGER ")
	out.WriteString(at.Name.String())
	out.WriteString(" ON ")
	out.WriteString(at.Table.String())
	return out.String()
}

// AlterProcedureStatement represents an ALTER PROCEDURE statement.
type AlterProcedureStatement struct {
	Token      token.Token
	Name       *QualifiedIdentifier
	Parameters []*ParameterDef
	Body       *BeginEndBlock
	Options    []string
}

func (ap *AlterProcedureStatement) statementNode()       {}
func (ap *AlterProcedureStatement) TokenLiteral() string { return ap.Token.Literal }
func (ap *AlterProcedureStatement) String() string {
	var out strings.Builder
	out.WriteString("ALTER PROCEDURE ")
	out.WriteString(ap.Name.String())
	return out.String()
}

// CreateDefaultStatement represents CREATE DEFAULT (deprecated T-SQL syntax)
type CreateDefaultStatement struct {
	Token token.Token
	Name  *QualifiedIdentifier
	Value Expression
}

func (cd *CreateDefaultStatement) statementNode()       {}
func (cd *CreateDefaultStatement) TokenLiteral() string { return cd.Token.Literal }
func (cd *CreateDefaultStatement) String() string {
	return "CREATE DEFAULT " + cd.Name.String() + " AS " + cd.Value.String()
}

// CreateRuleStatement represents CREATE RULE name AS condition
type CreateRuleStatement struct {
	Token     token.Token
	Name      *QualifiedIdentifier
	Condition Expression
}

func (cr *CreateRuleStatement) statementNode()       {}
func (cr *CreateRuleStatement) TokenLiteral() string { return cr.Token.Literal }
func (cr *CreateRuleStatement) String() string {
	return "CREATE RULE " + cr.Name.String() + " AS " + cr.Condition.String()
}

// DropObjectStatement represents a generic DROP statement for various object types.
type DropObjectStatement struct {
	Token      token.Token
	ObjectType string // VIEW, FUNCTION, PROCEDURE, TRIGGER, INDEX
	IfExists   bool
	Names      []*QualifiedIdentifier
	// For DROP INDEX: index name and table
	IndexName *Identifier
	TableName *QualifiedIdentifier
	// For DROP TRIGGER: scope
	OnDatabase  bool // ON DATABASE
	OnAllServer bool // ON ALL SERVER
}

func (do *DropObjectStatement) statementNode()       {}
func (do *DropObjectStatement) TokenLiteral() string { return do.Token.Literal }
func (do *DropObjectStatement) String() string {
	var out strings.Builder
	out.WriteString("DROP ")
	out.WriteString(do.ObjectType)
	if do.IfExists {
		out.WriteString(" IF EXISTS")
	}
	if do.IndexName != nil {
		out.WriteString(" ")
		out.WriteString(do.IndexName.Value)
		out.WriteString(" ON ")
		out.WriteString(do.TableName.String())
	} else {
		for i, name := range do.Names {
			if i > 0 {
				out.WriteString(", ")
			}
			out.WriteString(" ")
			out.WriteString(name.String())
		}
	}
	if do.OnDatabase {
		out.WriteString(" ON DATABASE")
	}
	if do.OnAllServer {
		out.WriteString(" ON ALL SERVER")
	}
	return out.String()
}

// -----------------------------------------------------------------------------
// Stage 7a: Quick Wins - Additional Statement Types
// -----------------------------------------------------------------------------

// UseStatement represents a USE database statement.
type UseStatement struct {
	Token    token.Token
	Database *Identifier
}

func (us *UseStatement) statementNode()       {}
func (us *UseStatement) TokenLiteral() string { return us.Token.Literal }
func (us *UseStatement) String() string {
	return "USE " + us.Database.Value
}

// WaitforStatement represents a WAITFOR DELAY/TIME statement.
type WaitforStatement struct {
	Token    token.Token
	Type     string     // "DELAY" or "TIME"
	Duration Expression // String literal or variable
}

func (ws *WaitforStatement) statementNode()       {}
func (ws *WaitforStatement) TokenLiteral() string { return ws.Token.Literal }
func (ws *WaitforStatement) String() string {
	return "WAITFOR " + ws.Type + " " + ws.Duration.String()
}

// SaveTransactionStatement represents a SAVE TRANSACTION statement.
type SaveTransactionStatement struct {
	Token         token.Token
	SavepointName *Identifier
}

func (st *SaveTransactionStatement) statementNode()       {}
func (st *SaveTransactionStatement) TokenLiteral() string { return st.Token.Literal }
func (st *SaveTransactionStatement) String() string {
	return "SAVE TRANSACTION " + st.SavepointName.Value
}

// GotoStatement represents a GOTO label statement.
type GotoStatement struct {
	Token token.Token
	Label *Identifier
}

func (gs *GotoStatement) statementNode()       {}
func (gs *GotoStatement) TokenLiteral() string { return gs.Token.Literal }
func (gs *GotoStatement) String() string {
	return "GOTO " + gs.Label.Value
}

// LabelStatement represents a label definition (LabelName:).
type LabelStatement struct {
	Token token.Token
	Name  *Identifier
}

func (ls *LabelStatement) statementNode()       {}
func (ls *LabelStatement) TokenLiteral() string { return ls.Token.Literal }
func (ls *LabelStatement) String() string {
	return ls.Name.Value + ":"
}

// SetOptionStatement represents various SET option statements.
type SetOptionStatement struct {
	Token  token.Token
	Option string               // IDENTITY_INSERT, ROWCOUNT, LANGUAGE, etc.
	Table  *QualifiedIdentifier // For IDENTITY_INSERT
	Value  Expression           // The value (ON/OFF, number, identifier)
}

func (so *SetOptionStatement) statementNode()       {}
func (so *SetOptionStatement) TokenLiteral() string { return so.Token.Literal }
func (so *SetOptionStatement) String() string {
	var out strings.Builder
	out.WriteString("SET ")
	out.WriteString(so.Option)
	if so.Table != nil {
		out.WriteString(" ")
		out.WriteString(so.Table.String())
	}
	if so.Value != nil {
		out.WriteString(" ")
		out.WriteString(so.Value.String())
	}
	return out.String()
}

// SetTransactionIsolationStatement represents SET TRANSACTION ISOLATION LEVEL.
type SetTransactionIsolationStatement struct {
	Token token.Token
	Level string // READ UNCOMMITTED, READ COMMITTED, REPEATABLE READ, SERIALIZABLE, SNAPSHOT
}

func (si *SetTransactionIsolationStatement) statementNode()       {}
func (si *SetTransactionIsolationStatement) TokenLiteral() string { return si.Token.Literal }
func (si *SetTransactionIsolationStatement) String() string {
	return "SET TRANSACTION ISOLATION LEVEL " + si.Level
}

// -----------------------------------------------------------------------------
// Stage 3: Synonyms, EXECUTE AS, OPENJSON
// -----------------------------------------------------------------------------

// CreateSynonymStatement represents CREATE SYNONYM name FOR target.
type CreateSynonymStatement struct {
	Token  token.Token
	Name   *QualifiedIdentifier
	Target *QualifiedIdentifier
}

func (cs *CreateSynonymStatement) statementNode()       {}
func (cs *CreateSynonymStatement) TokenLiteral() string { return cs.Token.Literal }
func (cs *CreateSynonymStatement) String() string {
	return "CREATE SYNONYM " + cs.Name.String() + " FOR " + cs.Target.String()
}

// DropSynonymStatement represents DROP SYNONYM name.
type DropSynonymStatement struct {
	Token    token.Token
	IfExists bool
	Name     *QualifiedIdentifier
}

func (ds *DropSynonymStatement) statementNode()       {}
func (ds *DropSynonymStatement) TokenLiteral() string { return ds.Token.Literal }
func (ds *DropSynonymStatement) String() string {
	var out strings.Builder
	out.WriteString("DROP SYNONYM ")
	if ds.IfExists {
		out.WriteString("IF EXISTS ")
	}
	out.WriteString(ds.Name.String())
	return out.String()
}

// ExecuteAsStatement represents EXECUTE AS { CALLER | SELF | OWNER | USER = 'name' }.
type ExecuteAsStatement struct {
	Token     token.Token
	Type      string // CALLER, SELF, OWNER, USER, LOGIN
	UserName  string // For USER = 'name' or LOGIN = 'name'
	CookieVar string // For WITH COOKIE INTO @var
}

func (ea *ExecuteAsStatement) statementNode()       {}
func (ea *ExecuteAsStatement) TokenLiteral() string { return ea.Token.Literal }
func (ea *ExecuteAsStatement) String() string {
	var result string
	if ea.UserName != "" {
		result = "EXECUTE AS " + ea.Type + " = '" + ea.UserName + "'"
	} else {
		result = "EXECUTE AS " + ea.Type
	}
	if ea.CookieVar != "" {
		result += " WITH COOKIE INTO " + ea.CookieVar
	}
	return result
}

// RevertStatement represents REVERT.
type RevertStatement struct {
	Token  token.Token
	Cookie Expression // Optional: WITH COOKIE = @cookie
}

func (rs *RevertStatement) statementNode()       {}
func (rs *RevertStatement) TokenLiteral() string { return rs.Token.Literal }
func (rs *RevertStatement) String() string {
	if rs.Cookie != nil {
		return "REVERT WITH COOKIE = " + rs.Cookie.String()
	}
	return "REVERT"
}

// ReconfigureStatement represents RECONFIGURE statement.
type ReconfigureStatement struct {
	Token        token.Token
	WithOverride bool // RECONFIGURE WITH OVERRIDE
}

func (rs *ReconfigureStatement) statementNode()       {}
func (rs *ReconfigureStatement) TokenLiteral() string { return rs.Token.Literal }
func (rs *ReconfigureStatement) String() string {
	if rs.WithOverride {
		return "RECONFIGURE WITH OVERRIDE"
	}
	return "RECONFIGURE"
}

// GrantStatement represents GRANT permissions statement.
type GrantStatement struct {
	Token           token.Token
	Permissions     []string // SELECT, INSERT, UPDATE, DELETE, EXECUTE, etc.
	OnType          string   // OBJECT, SCHEMA, DATABASE, or empty for object-level
	OnObject        *QualifiedIdentifier
	Columns         []string // Column-level permissions (col1, col2, ...)
	ToPrincipals    []string // Users, roles, logins
	WithGrantOption bool     // WITH GRANT OPTION
}

func (gs *GrantStatement) statementNode()       {}
func (gs *GrantStatement) TokenLiteral() string { return gs.Token.Literal }
func (gs *GrantStatement) String() string {
	var out strings.Builder
	out.WriteString("GRANT ")
	out.WriteString(strings.Join(gs.Permissions, ", "))
	if gs.OnObject != nil {
		out.WriteString(" ON ")
		if gs.OnType != "" {
			out.WriteString(gs.OnType + "::")
		}
		out.WriteString(gs.OnObject.String())
	}
	if len(gs.Columns) > 0 {
		out.WriteString(" (")
		out.WriteString(strings.Join(gs.Columns, ", "))
		out.WriteString(")")
	}
	out.WriteString(" TO ")
	out.WriteString(strings.Join(gs.ToPrincipals, ", "))
	if gs.WithGrantOption {
		out.WriteString(" WITH GRANT OPTION")
	}
	return out.String()
}

// RevokeStatement represents REVOKE permissions statement.
type RevokeStatement struct {
	Token          token.Token
	GrantOptionFor bool     // GRANT OPTION FOR
	Permissions    []string // SELECT, INSERT, UPDATE, DELETE, EXECUTE, etc.
	OnType         string   // OBJECT, SCHEMA, DATABASE, or empty
	OnObject       *QualifiedIdentifier
	Columns        []string // Column-level permissions (col1, col2, ...)
	FromPrincipals []string // Users, roles, logins
	Cascade        bool     // CASCADE
}

func (rs *RevokeStatement) statementNode()       {}
func (rs *RevokeStatement) TokenLiteral() string { return rs.Token.Literal }
func (rs *RevokeStatement) String() string {
	var out strings.Builder
	out.WriteString("REVOKE ")
	if rs.GrantOptionFor {
		out.WriteString("GRANT OPTION FOR ")
	}
	out.WriteString(strings.Join(rs.Permissions, ", "))
	if rs.OnObject != nil {
		out.WriteString(" ON ")
		if rs.OnType != "" {
			out.WriteString(rs.OnType + "::")
		}
		out.WriteString(rs.OnObject.String())
	}
	if len(rs.Columns) > 0 {
		out.WriteString(" (")
		out.WriteString(strings.Join(rs.Columns, ", "))
		out.WriteString(")")
	}
	out.WriteString(" FROM ")
	out.WriteString(strings.Join(rs.FromPrincipals, ", "))
	if rs.Cascade {
		out.WriteString(" CASCADE")
	}
	return out.String()
}

// DenyStatement represents DENY permissions statement.
type DenyStatement struct {
	Token        token.Token
	Permissions  []string // SELECT, INSERT, UPDATE, DELETE, EXECUTE, etc.
	OnType       string   // OBJECT, SCHEMA, DATABASE, or empty
	OnObject     *QualifiedIdentifier
	Columns      []string // Column-level permissions (col1, col2, ...)
	ToPrincipals []string // Users, roles, logins
	Cascade      bool     // CASCADE
}

func (ds *DenyStatement) statementNode()       {}
func (ds *DenyStatement) TokenLiteral() string { return ds.Token.Literal }
func (ds *DenyStatement) String() string {
	var out strings.Builder
	out.WriteString("DENY ")
	out.WriteString(strings.Join(ds.Permissions, ", "))
	if ds.OnObject != nil {
		out.WriteString(" ON ")
		if ds.OnType != "" {
			out.WriteString(ds.OnType + "::")
		}
		out.WriteString(ds.OnObject.String())
	}
	if len(ds.Columns) > 0 {
		out.WriteString(" (")
		out.WriteString(strings.Join(ds.Columns, ", "))
		out.WriteString(")")
	}
	out.WriteString(" TO ")
	out.WriteString(strings.Join(ds.ToPrincipals, ", "))
	if ds.Cascade {
		out.WriteString(" CASCADE")
	}
	return out.String()
}

// CreateLoginStatement represents CREATE LOGIN statement.
type CreateLoginStatement struct {
	Token       token.Token
	Name        string
	FromWindows bool   // FROM WINDOWS
	Password    string // WITH PASSWORD = 'xxx'
	DefaultDB   string // WITH DEFAULT_DATABASE = xxx
	DefaultLang string // WITH DEFAULT_LANGUAGE = xxx
	CheckPolicy *bool  // WITH CHECK_POLICY = ON/OFF
	CheckExpiry *bool  // WITH CHECK_EXPIRATION = ON/OFF
}

func (cls *CreateLoginStatement) statementNode()       {}
func (cls *CreateLoginStatement) TokenLiteral() string { return cls.Token.Literal }
func (cls *CreateLoginStatement) String() string {
	var out strings.Builder
	out.WriteString("CREATE LOGIN ")
	out.WriteString(cls.Name)
	if cls.FromWindows {
		out.WriteString(" FROM WINDOWS")
	}
	if cls.Password != "" {
		out.WriteString(" WITH PASSWORD = '")
		out.WriteString(cls.Password)
		out.WriteString("'")
	}
	return out.String()
}

// AlterLoginStatement represents ALTER LOGIN statement.
type AlterLoginStatement struct {
	Token       token.Token
	Name        string
	Enable      bool
	Disable     bool
	Password    string
	OldPassword string
}

func (als *AlterLoginStatement) statementNode()       {}
func (als *AlterLoginStatement) TokenLiteral() string { return als.Token.Literal }
func (als *AlterLoginStatement) String() string {
	var out strings.Builder
	out.WriteString("ALTER LOGIN ")
	out.WriteString(als.Name)
	if als.Enable {
		out.WriteString(" ENABLE")
	} else if als.Disable {
		out.WriteString(" DISABLE")
	} else if als.Password != "" {
		out.WriteString(" WITH PASSWORD = '")
		out.WriteString(als.Password)
		out.WriteString("'")
	}
	return out.String()
}

// CreateUserStatement represents CREATE USER statement.
type CreateUserStatement struct {
	Token         token.Token
	Name          string
	ForLogin      string // FOR LOGIN xxx
	WithoutLogin  bool   // WITHOUT LOGIN
	DefaultSchema string // WITH DEFAULT_SCHEMA = xxx
}

func (cus *CreateUserStatement) statementNode()       {}
func (cus *CreateUserStatement) TokenLiteral() string { return cus.Token.Literal }
func (cus *CreateUserStatement) String() string {
	var out strings.Builder
	out.WriteString("CREATE USER ")
	out.WriteString(cus.Name)
	if cus.ForLogin != "" {
		out.WriteString(" FOR LOGIN ")
		out.WriteString(cus.ForLogin)
	}
	if cus.WithoutLogin {
		out.WriteString(" WITHOUT LOGIN")
	}
	if cus.DefaultSchema != "" {
		out.WriteString(" WITH DEFAULT_SCHEMA = ")
		out.WriteString(cus.DefaultSchema)
	}
	return out.String()
}

// AlterUserStatement represents ALTER USER statement.
type AlterUserStatement struct {
	Token         token.Token
	Name          string
	NewName       string // WITH NAME = xxx
	DefaultSchema string // WITH DEFAULT_SCHEMA = xxx
	Login         string // WITH LOGIN = xxx
}

func (aus *AlterUserStatement) statementNode()       {}
func (aus *AlterUserStatement) TokenLiteral() string { return aus.Token.Literal }
func (aus *AlterUserStatement) String() string {
	var out strings.Builder
	out.WriteString("ALTER USER ")
	out.WriteString(aus.Name)
	if aus.DefaultSchema != "" {
		out.WriteString(" WITH DEFAULT_SCHEMA = ")
		out.WriteString(aus.DefaultSchema)
	}
	if aus.NewName != "" {
		out.WriteString(" WITH NAME = ")
		out.WriteString(aus.NewName)
	}
	return out.String()
}

// CreateRoleStatement represents CREATE ROLE statement.
type CreateRoleStatement struct {
	Token         token.Token
	Name          string
	Authorization string // AUTHORIZATION owner_name
}

func (crs *CreateRoleStatement) statementNode()       {}
func (crs *CreateRoleStatement) TokenLiteral() string { return crs.Token.Literal }
func (crs *CreateRoleStatement) String() string {
	var out strings.Builder
	out.WriteString("CREATE ROLE ")
	out.WriteString(crs.Name)
	if crs.Authorization != "" {
		out.WriteString(" AUTHORIZATION ")
		out.WriteString(crs.Authorization)
	}
	return out.String()
}

// CreateApplicationRoleStatement represents CREATE APPLICATION ROLE
type CreateApplicationRoleStatement struct {
	Token    token.Token
	Name     string
	Password string
	Schema   string
}

func (c *CreateApplicationRoleStatement) statementNode()       {}
func (c *CreateApplicationRoleStatement) TokenLiteral() string { return c.Token.Literal }
func (c *CreateApplicationRoleStatement) String() string {
	var out strings.Builder
	out.WriteString("CREATE APPLICATION ROLE ")
	out.WriteString(c.Name)
	if c.Password != "" || c.Schema != "" {
		out.WriteString(" WITH ")
		if c.Password != "" {
			out.WriteString("PASSWORD = '")
			out.WriteString(c.Password)
			out.WriteString("'")
		}
		if c.Schema != "" {
			if c.Password != "" {
				out.WriteString(", ")
			}
			out.WriteString("DEFAULT_SCHEMA = ")
			out.WriteString(c.Schema)
		}
	}
	return out.String()
}

// CreateServerRoleStatement represents CREATE SERVER ROLE
type CreateServerRoleStatement struct {
	Token         token.Token
	Name          string
	Authorization string
}

func (c *CreateServerRoleStatement) statementNode()       {}
func (c *CreateServerRoleStatement) TokenLiteral() string { return c.Token.Literal }
func (c *CreateServerRoleStatement) String() string {
	var out strings.Builder
	out.WriteString("CREATE SERVER ROLE ")
	out.WriteString(c.Name)
	if c.Authorization != "" {
		out.WriteString(" AUTHORIZATION ")
		out.WriteString(c.Authorization)
	}
	return out.String()
}

// CreateCredentialStatement represents CREATE CREDENTIAL
type CreateCredentialStatement struct {
	Token    token.Token
	Name     string
	Identity string
	Secret   string
}

func (c *CreateCredentialStatement) statementNode()       {}
func (c *CreateCredentialStatement) TokenLiteral() string { return c.Token.Literal }
func (c *CreateCredentialStatement) String() string {
	var out strings.Builder
	out.WriteString("CREATE CREDENTIAL ")
	out.WriteString(c.Name)
	out.WriteString(" WITH IDENTITY = '")
	out.WriteString(c.Identity)
	out.WriteString("'")
	if c.Secret != "" {
		out.WriteString(", SECRET = '")
		out.WriteString(c.Secret)
		out.WriteString("'")
	}
	return out.String()
}

// CreateDatabaseScopedCredentialStatement represents CREATE DATABASE SCOPED CREDENTIAL
type CreateDatabaseScopedCredentialStatement struct {
	Token    token.Token
	Name     string
	Identity string
	Secret   string
}

func (c *CreateDatabaseScopedCredentialStatement) statementNode()       {}
func (c *CreateDatabaseScopedCredentialStatement) TokenLiteral() string { return c.Token.Literal }
func (c *CreateDatabaseScopedCredentialStatement) String() string {
	var out strings.Builder
	out.WriteString("CREATE DATABASE SCOPED CREDENTIAL ")
	out.WriteString(c.Name)
	out.WriteString(" WITH IDENTITY = '")
	out.WriteString(c.Identity)
	out.WriteString("'")
	if c.Secret != "" {
		out.WriteString(", SECRET = '")
		out.WriteString(c.Secret)
		out.WriteString("'")
	}
	return out.String()
}

// CreateSchemaStatement represents CREATE SCHEMA statement.
type CreateSchemaStatement struct {
	Token         token.Token
	Name          string
	Authorization string // AUTHORIZATION owner_name
}

func (css *CreateSchemaStatement) statementNode()       {}
func (css *CreateSchemaStatement) TokenLiteral() string { return css.Token.Literal }
func (css *CreateSchemaStatement) String() string {
	var out strings.Builder
	out.WriteString("CREATE SCHEMA ")
	out.WriteString(css.Name)
	if css.Authorization != "" {
		out.WriteString(" AUTHORIZATION ")
		out.WriteString(css.Authorization)
	}
	return out.String()
}

// AlterRoleStatement represents ALTER ROLE statement.
type AlterRoleStatement struct {
	Token      token.Token
	Name       string
	AddMember  string // ADD MEMBER user_name
	DropMember string // DROP MEMBER user_name
	NewName    string // WITH NAME = new_name
}

func (ars *AlterRoleStatement) statementNode()       {}
func (ars *AlterRoleStatement) TokenLiteral() string { return ars.Token.Literal }
func (ars *AlterRoleStatement) String() string {
	var out strings.Builder
	out.WriteString("ALTER ROLE ")
	out.WriteString(ars.Name)
	if ars.AddMember != "" {
		out.WriteString(" ADD MEMBER ")
		out.WriteString(ars.AddMember)
	}
	if ars.DropMember != "" {
		out.WriteString(" DROP MEMBER ")
		out.WriteString(ars.DropMember)
	}
	if ars.NewName != "" {
		out.WriteString(" WITH NAME = ")
		out.WriteString(ars.NewName)
	}
	return out.String()
}

// AlterApplicationRoleStatement represents ALTER APPLICATION ROLE
type AlterApplicationRoleStatement struct {
	Token    token.Token
	Name     string
	Password string
	Schema   string
	NewName  string
}

func (a *AlterApplicationRoleStatement) statementNode()       {}
func (a *AlterApplicationRoleStatement) TokenLiteral() string { return a.Token.Literal }
func (a *AlterApplicationRoleStatement) String() string {
	var out strings.Builder
	out.WriteString("ALTER APPLICATION ROLE ")
	out.WriteString(a.Name)
	out.WriteString(" WITH")
	first := true
	if a.Password != "" {
		out.WriteString(" PASSWORD = '")
		out.WriteString(a.Password)
		out.WriteString("'")
		first = false
	}
	if a.Schema != "" {
		if !first {
			out.WriteString(",")
		}
		out.WriteString(" DEFAULT_SCHEMA = ")
		out.WriteString(a.Schema)
		first = false
	}
	if a.NewName != "" {
		if !first {
			out.WriteString(",")
		}
		out.WriteString(" NAME = ")
		out.WriteString(a.NewName)
	}
	return out.String()
}

// AlterServerRoleStatement represents ALTER SERVER ROLE
type AlterServerRoleStatement struct {
	Token      token.Token
	Name       string
	AddMember  string
	DropMember string
	NewName    string
}

func (a *AlterServerRoleStatement) statementNode()       {}
func (a *AlterServerRoleStatement) TokenLiteral() string { return a.Token.Literal }
func (a *AlterServerRoleStatement) String() string {
	var out strings.Builder
	out.WriteString("ALTER SERVER ROLE ")
	out.WriteString(a.Name)
	if a.AddMember != "" {
		out.WriteString(" ADD MEMBER ")
		out.WriteString(a.AddMember)
	}
	if a.DropMember != "" {
		out.WriteString(" DROP MEMBER ")
		out.WriteString(a.DropMember)
	}
	if a.NewName != "" {
		out.WriteString(" WITH NAME = ")
		out.WriteString(a.NewName)
	}
	return out.String()
}

// -----------------------------------------------------------------------------
// Stage 7: Backup & Restore
// -----------------------------------------------------------------------------

// BackupStatement represents BACKUP DATABASE/LOG statement.
type BackupStatement struct {
	Token        token.Token
	BackupType   string            // DATABASE, LOG, CERTIFICATE
	DatabaseName string            // Database or certificate name
	ToLocations  []*BackupLocation // TO DISK/URL = 'path', ...
	WithOptions  []*BackupOption   // WITH option = value, ...
}

// BackupLocation represents a backup destination.
type BackupLocation struct {
	Type string // DISK, URL
	Path string // File path or URL
}

// BackupOption represents a WITH option for BACKUP.
type BackupOption struct {
	Name  string // COMPRESSION, INIT, COPY_ONLY, etc.
	Value string // Optional value
}

func (bs *BackupStatement) statementNode()       {}
func (bs *BackupStatement) TokenLiteral() string { return bs.Token.Literal }
func (bs *BackupStatement) String() string {
	var out strings.Builder
	out.WriteString("BACKUP ")
	out.WriteString(bs.BackupType)
	out.WriteString(" ")
	out.WriteString(bs.DatabaseName)

	if len(bs.ToLocations) > 0 {
		out.WriteString(" TO ")
		for i, loc := range bs.ToLocations {
			if i > 0 {
				out.WriteString(", ")
			}
			out.WriteString(loc.Type)
			out.WriteString(" = '")
			out.WriteString(loc.Path)
			out.WriteString("'")
		}
	}

	if len(bs.WithOptions) > 0 {
		out.WriteString(" WITH ")
		for i, opt := range bs.WithOptions {
			if i > 0 {
				out.WriteString(", ")
			}
			out.WriteString(opt.Name)
			if opt.Value != "" {
				out.WriteString(" = ")
				out.WriteString(opt.Value)
			}
		}
	}

	return out.String()
}

// RestoreStatement represents RESTORE DATABASE/LOG/FILELISTONLY/HEADERONLY statement.
type RestoreStatement struct {
	Token         token.Token
	RestoreType   string            // DATABASE, LOG, FILELISTONLY, HEADERONLY, VERIFYONLY
	DatabaseName  string            // Database name (empty for FILELISTONLY/HEADERONLY)
	FromLocations []*BackupLocation // FROM DISK/URL = 'path', ...
	WithOptions   []*BackupOption   // WITH option = value, ...
}

func (rs *RestoreStatement) statementNode()       {}
func (rs *RestoreStatement) TokenLiteral() string { return rs.Token.Literal }
func (rs *RestoreStatement) String() string {
	var out strings.Builder
	out.WriteString("RESTORE ")
	out.WriteString(rs.RestoreType)

	if rs.DatabaseName != "" {
		out.WriteString(" ")
		out.WriteString(rs.DatabaseName)
	}

	if len(rs.FromLocations) > 0 {
		out.WriteString(" FROM ")
		for i, loc := range rs.FromLocations {
			if i > 0 {
				out.WriteString(", ")
			}
			out.WriteString(loc.Type)
			out.WriteString(" = '")
			out.WriteString(loc.Path)
			out.WriteString("'")
		}
	}

	if len(rs.WithOptions) > 0 {
		out.WriteString(" WITH ")
		for i, opt := range rs.WithOptions {
			if i > 0 {
				out.WriteString(", ")
			}
			out.WriteString(opt.Name)
			if opt.Value != "" {
				out.WriteString(" = ")
				out.WriteString(opt.Value)
			}
		}
	}

	return out.String()
}

// -----------------------------------------------------------------------------
// Stage 8: Cryptography & CLR
// -----------------------------------------------------------------------------

// CreateMasterKeyStatement represents CREATE MASTER KEY statement.
type CreateMasterKeyStatement struct {
	Token    token.Token
	Password string // ENCRYPTION BY PASSWORD = 'xxx'
}

func (cmk *CreateMasterKeyStatement) statementNode()       {}
func (cmk *CreateMasterKeyStatement) TokenLiteral() string { return cmk.Token.Literal }
func (cmk *CreateMasterKeyStatement) String() string {
	var out strings.Builder
	out.WriteString("CREATE MASTER KEY ENCRYPTION BY PASSWORD = '")
	out.WriteString(cmk.Password)
	out.WriteString("'")
	return out.String()
}

// CreateCertificateStatement represents CREATE CERTIFICATE statement.
type CreateCertificateStatement struct {
	Token        token.Token
	Name         string
	Subject      string // WITH SUBJECT = 'xxx'
	FromFile     string // FROM FILE = 'path' (optional)
	EncryptByPwd string // ENCRYPTION BY PASSWORD = 'xxx' (optional)
	DecryptByPwd string // DECRYPTION BY PASSWORD = 'xxx' (optional)
}

func (cc *CreateCertificateStatement) statementNode()       {}
func (cc *CreateCertificateStatement) TokenLiteral() string { return cc.Token.Literal }
func (cc *CreateCertificateStatement) String() string {
	var out strings.Builder
	out.WriteString("CREATE CERTIFICATE ")
	out.WriteString(cc.Name)
	if cc.FromFile != "" {
		out.WriteString(" FROM FILE = '")
		out.WriteString(cc.FromFile)
		out.WriteString("'")
	}
	if cc.Subject != "" {
		out.WriteString(" WITH SUBJECT = '")
		out.WriteString(cc.Subject)
		out.WriteString("'")
	}
	return out.String()
}

// CreateSymmetricKeyStatement represents CREATE SYMMETRIC KEY statement.
type CreateSymmetricKeyStatement struct {
	Token         token.Token
	Name          string
	Algorithm     string // WITH ALGORITHM = AES_256, etc.
	EncryptByCert string // ENCRYPTION BY CERTIFICATE name
	EncryptByKey  string // ENCRYPTION BY SYMMETRIC KEY name
	EncryptByPwd  string // ENCRYPTION BY PASSWORD = 'xxx'
}

func (csk *CreateSymmetricKeyStatement) statementNode()       {}
func (csk *CreateSymmetricKeyStatement) TokenLiteral() string { return csk.Token.Literal }
func (csk *CreateSymmetricKeyStatement) String() string {
	var out strings.Builder
	out.WriteString("CREATE SYMMETRIC KEY ")
	out.WriteString(csk.Name)
	if csk.Algorithm != "" {
		out.WriteString(" WITH ALGORITHM = ")
		out.WriteString(csk.Algorithm)
	}
	if csk.EncryptByCert != "" {
		out.WriteString(" ENCRYPTION BY CERTIFICATE ")
		out.WriteString(csk.EncryptByCert)
	}
	if csk.EncryptByKey != "" {
		out.WriteString(" ENCRYPTION BY SYMMETRIC KEY ")
		out.WriteString(csk.EncryptByKey)
	}
	return out.String()
}

// CreateAsymmetricKeyStatement represents CREATE ASYMMETRIC KEY statement.
type CreateAsymmetricKeyStatement struct {
	Token        token.Token
	Name         string
	FromFile     string // FROM FILE = 'path'
	FromAssembly string // FROM ASSEMBLY name
	Algorithm    string // WITH ALGORITHM = RSA_2048, etc.
	EncryptByPwd string // ENCRYPTION BY PASSWORD = 'xxx'
}

func (cak *CreateAsymmetricKeyStatement) statementNode()       {}
func (cak *CreateAsymmetricKeyStatement) TokenLiteral() string { return cak.Token.Literal }
func (cak *CreateAsymmetricKeyStatement) String() string {
	var out strings.Builder
	out.WriteString("CREATE ASYMMETRIC KEY ")
	out.WriteString(cak.Name)
	if cak.FromFile != "" {
		out.WriteString(" FROM FILE = '")
		out.WriteString(cak.FromFile)
		out.WriteString("'")
	}
	if cak.FromAssembly != "" {
		out.WriteString(" FROM ASSEMBLY ")
		out.WriteString(cak.FromAssembly)
	}
	if cak.Algorithm != "" {
		out.WriteString(" WITH ALGORITHM = ")
		out.WriteString(cak.Algorithm)
	}
	return out.String()
}

// OpenSymmetricKeyStatement represents OPEN SYMMETRIC KEY statement.
type OpenSymmetricKeyStatement struct {
	Token         token.Token
	KeyName       string
	DecryptByCert string // DECRYPTION BY CERTIFICATE name
	DecryptByKey  string // DECRYPTION BY SYMMETRIC KEY name
	DecryptByPwd  string // DECRYPTION BY PASSWORD = 'xxx'
}

func (osk *OpenSymmetricKeyStatement) statementNode()       {}
func (osk *OpenSymmetricKeyStatement) TokenLiteral() string { return osk.Token.Literal }
func (osk *OpenSymmetricKeyStatement) String() string {
	var out strings.Builder
	out.WriteString("OPEN SYMMETRIC KEY ")
	out.WriteString(osk.KeyName)
	if osk.DecryptByCert != "" {
		out.WriteString(" DECRYPTION BY CERTIFICATE ")
		out.WriteString(osk.DecryptByCert)
	}
	if osk.DecryptByKey != "" {
		out.WriteString(" DECRYPTION BY SYMMETRIC KEY ")
		out.WriteString(osk.DecryptByKey)
	}
	return out.String()
}

// CloseSymmetricKeyStatement represents CLOSE SYMMETRIC KEY statement.
type CloseSymmetricKeyStatement struct {
	Token   token.Token
	KeyName string // empty if CLOSE ALL SYMMETRIC KEYS
	All     bool   // CLOSE ALL SYMMETRIC KEYS
}

func (csk *CloseSymmetricKeyStatement) statementNode()       {}
func (csk *CloseSymmetricKeyStatement) TokenLiteral() string { return csk.Token.Literal }
func (csk *CloseSymmetricKeyStatement) String() string {
	if csk.All {
		return "CLOSE ALL SYMMETRIC KEYS"
	}
	return "CLOSE SYMMETRIC KEY " + csk.KeyName
}

// CreateAssemblyStatement represents CREATE ASSEMBLY statement.
type CreateAssemblyStatement struct {
	Token         token.Token
	Name          string
	FromPath      string // FROM 'path'
	FromBinary    string // FROM 0x... (hex binary)
	PermissionSet string // WITH PERMISSION_SET = SAFE|EXTERNAL_ACCESS|UNSAFE
}

func (ca *CreateAssemblyStatement) statementNode()       {}
func (ca *CreateAssemblyStatement) TokenLiteral() string { return ca.Token.Literal }
func (ca *CreateAssemblyStatement) String() string {
	var out strings.Builder
	out.WriteString("CREATE ASSEMBLY ")
	out.WriteString(ca.Name)
	if ca.FromPath != "" {
		out.WriteString(" FROM '")
		out.WriteString(ca.FromPath)
		out.WriteString("'")
	}
	if ca.FromBinary != "" {
		out.WriteString(" FROM ")
		out.WriteString(ca.FromBinary)
	}
	if ca.PermissionSet != "" {
		out.WriteString(" WITH PERMISSION_SET = ")
		out.WriteString(ca.PermissionSet)
	}
	return out.String()
}

// AlterAssemblyStatement represents ALTER ASSEMBLY statement.
type AlterAssemblyStatement struct {
	Token         token.Token
	Name          string
	FromPath      string // FROM 'path'
	FromBinary    string // FROM 0x...
	PermissionSet string // WITH PERMISSION_SET = ...
}

func (aa *AlterAssemblyStatement) statementNode()       {}
func (aa *AlterAssemblyStatement) TokenLiteral() string { return aa.Token.Literal }
func (aa *AlterAssemblyStatement) String() string {
	var out strings.Builder
	out.WriteString("ALTER ASSEMBLY ")
	out.WriteString(aa.Name)
	if aa.FromPath != "" {
		out.WriteString(" FROM '")
		out.WriteString(aa.FromPath)
		out.WriteString("'")
	}
	if aa.PermissionSet != "" {
		out.WriteString(" WITH PERMISSION_SET = ")
		out.WriteString(aa.PermissionSet)
	}
	return out.String()
}

// -----------------------------------------------------------------------------
// Stage 9: Partitioning
// -----------------------------------------------------------------------------

// CreatePartitionFunctionStatement represents CREATE PARTITION FUNCTION statement.
type CreatePartitionFunctionStatement struct {
	Token          token.Token
	Name           string
	InputType      *DataType    // Parameter type
	RangeType      string       // LEFT or RIGHT
	BoundaryValues []Expression // Values list
}

func (cpf *CreatePartitionFunctionStatement) statementNode()       {}
func (cpf *CreatePartitionFunctionStatement) TokenLiteral() string { return cpf.Token.Literal }
func (cpf *CreatePartitionFunctionStatement) String() string {
	var out strings.Builder
	out.WriteString("CREATE PARTITION FUNCTION ")
	out.WriteString(cpf.Name)
	out.WriteString("(")
	if cpf.InputType != nil {
		out.WriteString(cpf.InputType.String())
	}
	out.WriteString(") AS RANGE ")
	out.WriteString(cpf.RangeType)
	out.WriteString(" FOR VALUES (")
	for i, v := range cpf.BoundaryValues {
		if i > 0 {
			out.WriteString(", ")
		}
		out.WriteString(v.String())
	}
	out.WriteString(")")
	return out.String()
}

// AlterPartitionFunctionStatement represents ALTER PARTITION FUNCTION statement.
type AlterPartitionFunctionStatement struct {
	Token      token.Token
	Name       string
	Action     string     // SPLIT or MERGE
	RangeValue Expression // The boundary value
}

func (apf *AlterPartitionFunctionStatement) statementNode()       {}
func (apf *AlterPartitionFunctionStatement) TokenLiteral() string { return apf.Token.Literal }
func (apf *AlterPartitionFunctionStatement) String() string {
	var out strings.Builder
	out.WriteString("ALTER PARTITION FUNCTION ")
	out.WriteString(apf.Name)
	out.WriteString("() ")
	out.WriteString(apf.Action)
	out.WriteString(" RANGE (")
	if apf.RangeValue != nil {
		out.WriteString(apf.RangeValue.String())
	}
	out.WriteString(")")
	return out.String()
}

// CreatePartitionSchemeStatement represents CREATE PARTITION SCHEME statement.
type CreatePartitionSchemeStatement struct {
	Token        token.Token
	Name         string
	FunctionName string   // AS PARTITION function_name
	AllTo        string   // ALL TO ([filegroup]) - single filegroup for all
	FileGroups   []string // Individual filegroups if not ALL TO
}

func (cps *CreatePartitionSchemeStatement) statementNode()       {}
func (cps *CreatePartitionSchemeStatement) TokenLiteral() string { return cps.Token.Literal }
func (cps *CreatePartitionSchemeStatement) String() string {
	var out strings.Builder
	out.WriteString("CREATE PARTITION SCHEME ")
	out.WriteString(cps.Name)
	out.WriteString(" AS PARTITION ")
	out.WriteString(cps.FunctionName)
	if cps.AllTo != "" {
		out.WriteString(" ALL TO (")
		out.WriteString(cps.AllTo)
		out.WriteString(")")
	} else if len(cps.FileGroups) > 0 {
		out.WriteString(" TO (")
		for i, fg := range cps.FileGroups {
			if i > 0 {
				out.WriteString(", ")
			}
			out.WriteString(fg)
		}
		out.WriteString(")")
	}
	return out.String()
}

// AlterPartitionSchemeStatement represents ALTER PARTITION SCHEME statement.
type AlterPartitionSchemeStatement struct {
	Token    token.Token
	Name     string
	NextUsed string // NEXT USED filegroup
}

func (aps *AlterPartitionSchemeStatement) statementNode()       {}
func (aps *AlterPartitionSchemeStatement) TokenLiteral() string { return aps.Token.Literal }
func (aps *AlterPartitionSchemeStatement) String() string {
	var out strings.Builder
	out.WriteString("ALTER PARTITION SCHEME ")
	out.WriteString(aps.Name)
	out.WriteString(" NEXT USED ")
	out.WriteString(aps.NextUsed)
	return out.String()
}

// -----------------------------------------------------------------------------
// Stage 10: Full-Text Search
// -----------------------------------------------------------------------------

// ContainsExpression represents the CONTAINS predicate.
type ContainsExpression struct {
	Token      token.Token
	Columns    []string   // Column(s) to search, or * for all
	SearchTerm Expression // Search condition
	Language   string     // Optional LANGUAGE value
}

func (ce *ContainsExpression) expressionNode()      {}
func (ce *ContainsExpression) TokenLiteral() string { return ce.Token.Literal }
func (ce *ContainsExpression) String() string {
	var out strings.Builder
	out.WriteString("CONTAINS(")
	if len(ce.Columns) == 1 {
		out.WriteString(ce.Columns[0])
	} else if len(ce.Columns) > 1 {
		out.WriteString("(")
		for i, col := range ce.Columns {
			if i > 0 {
				out.WriteString(", ")
			}
			out.WriteString(col)
		}
		out.WriteString(")")
	}
	out.WriteString(", ")
	if ce.SearchTerm != nil {
		out.WriteString(ce.SearchTerm.String())
	}
	out.WriteString(")")
	return out.String()
}

// FreetextExpression represents the FREETEXT predicate.
type FreetextExpression struct {
	Token      token.Token
	Columns    []string   // Column(s) to search, or * for all
	SearchTerm Expression // Search text
	Language   string     // Optional LANGUAGE value
}

func (fe *FreetextExpression) expressionNode()      {}
func (fe *FreetextExpression) TokenLiteral() string { return fe.Token.Literal }
func (fe *FreetextExpression) String() string {
	var out strings.Builder
	out.WriteString("FREETEXT(")
	if len(fe.Columns) == 1 {
		out.WriteString(fe.Columns[0])
	} else if len(fe.Columns) > 1 {
		out.WriteString("(")
		for i, col := range fe.Columns {
			if i > 0 {
				out.WriteString(", ")
			}
			out.WriteString(col)
		}
		out.WriteString(")")
	}
	out.WriteString(", ")
	if fe.SearchTerm != nil {
		out.WriteString(fe.SearchTerm.String())
	}
	out.WriteString(")")
	return out.String()
}

// ContainsTableExpression represents CONTAINSTABLE function.
type ContainsTableExpression struct {
	Token      token.Token
	TableName  string
	Columns    []string   // Column(s) to search, or * for all
	SearchTerm Expression // Search condition
	TopN       Expression // Optional TOP n_hits
	Language   string     // Optional LANGUAGE value
}

func (ct *ContainsTableExpression) expressionNode()      {}
func (ct *ContainsTableExpression) TokenLiteral() string { return ct.Token.Literal }
func (ct *ContainsTableExpression) String() string {
	var out strings.Builder
	out.WriteString("CONTAINSTABLE(")
	out.WriteString(ct.TableName)
	out.WriteString(", ")
	if len(ct.Columns) == 1 {
		out.WriteString(ct.Columns[0])
	} else if len(ct.Columns) > 1 {
		out.WriteString("(")
		for i, col := range ct.Columns {
			if i > 0 {
				out.WriteString(", ")
			}
			out.WriteString(col)
		}
		out.WriteString(")")
	}
	out.WriteString(", ")
	if ct.SearchTerm != nil {
		out.WriteString(ct.SearchTerm.String())
	}
	out.WriteString(")")
	return out.String()
}

// FreetextTableExpression represents FREETEXTTABLE function.
type FreetextTableExpression struct {
	Token      token.Token
	TableName  string
	Columns    []string   // Column(s) to search, or * for all
	SearchTerm Expression // Search text
	TopN       Expression // Optional TOP n_hits
	Language   string     // Optional LANGUAGE value
}

func (ft *FreetextTableExpression) expressionNode()      {}
func (ft *FreetextTableExpression) TokenLiteral() string { return ft.Token.Literal }
func (ft *FreetextTableExpression) String() string {
	var out strings.Builder
	out.WriteString("FREETEXTTABLE(")
	out.WriteString(ft.TableName)
	out.WriteString(", ")
	if len(ft.Columns) == 1 {
		out.WriteString(ft.Columns[0])
	} else if len(ft.Columns) > 1 {
		out.WriteString("(")
		for i, col := range ft.Columns {
			if i > 0 {
				out.WriteString(", ")
			}
			out.WriteString(col)
		}
		out.WriteString(")")
	}
	out.WriteString(", ")
	if ft.SearchTerm != nil {
		out.WriteString(ft.SearchTerm.String())
	}
	out.WriteString(")")
	return out.String()
}

// CreateFulltextCatalogStatement represents CREATE FULLTEXT CATALOG.
type CreateFulltextCatalogStatement struct {
	Token         token.Token
	Name          string
	OnFilegroup   string // ON FILEGROUP filegroup
	InPath        string // IN PATH 'rootpath'
	AsDefault     bool   // AS DEFAULT
	Authorization string // AUTHORIZATION owner
	AccentOn      *bool  // ACCENT_SENSITIVITY = ON/OFF
}

func (cfc *CreateFulltextCatalogStatement) statementNode()       {}
func (cfc *CreateFulltextCatalogStatement) TokenLiteral() string { return cfc.Token.Literal }
func (cfc *CreateFulltextCatalogStatement) String() string {
	var out strings.Builder
	out.WriteString("CREATE FULLTEXT CATALOG ")
	out.WriteString(cfc.Name)
	if cfc.OnFilegroup != "" {
		out.WriteString(" ON FILEGROUP ")
		out.WriteString(cfc.OnFilegroup)
	}
	if cfc.AsDefault {
		out.WriteString(" AS DEFAULT")
	}
	if cfc.Authorization != "" {
		out.WriteString(" AUTHORIZATION ")
		out.WriteString(cfc.Authorization)
	}
	return out.String()
}

// CreateFulltextIndexStatement represents CREATE FULLTEXT INDEX ON table.
type CreateFulltextIndexStatement struct {
	Token       token.Token
	TableName   *QualifiedIdentifier
	Columns     []*FulltextColumn // Column definitions
	KeyIndex    string            // KEY INDEX index_name
	OnCatalog   string            // ON catalog_name
	WithOptions []string          // WITH options
}

// FulltextColumn represents a column in a fulltext index.
type FulltextColumn struct {
	Name                 string
	TypeColumn           string // TYPE COLUMN type_column_name
	Language             string // LANGUAGE language_term
	StatisticalSemantics bool   // STATISTICAL_SEMANTICS
}

func (fic *FulltextColumn) String() string {
	var out strings.Builder
	out.WriteString(fic.Name)
	if fic.TypeColumn != "" {
		out.WriteString(" TYPE COLUMN ")
		out.WriteString(fic.TypeColumn)
	}
	if fic.Language != "" {
		out.WriteString(" LANGUAGE ")
		out.WriteString(fic.Language)
	}
	return out.String()
}

func (cfi *CreateFulltextIndexStatement) statementNode()       {}
func (cfi *CreateFulltextIndexStatement) TokenLiteral() string { return cfi.Token.Literal }
func (cfi *CreateFulltextIndexStatement) String() string {
	var out strings.Builder
	out.WriteString("CREATE FULLTEXT INDEX ON ")
	out.WriteString(cfi.TableName.String())
	out.WriteString("(")
	for i, col := range cfi.Columns {
		if i > 0 {
			out.WriteString(", ")
		}
		out.WriteString(col.String())
	}
	out.WriteString(")")
	if cfi.KeyIndex != "" {
		out.WriteString(" KEY INDEX ")
		out.WriteString(cfi.KeyIndex)
	}
	if cfi.OnCatalog != "" {
		out.WriteString(" ON ")
		out.WriteString(cfi.OnCatalog)
	}
	return out.String()
}

// AlterFulltextIndexStatement represents ALTER FULLTEXT INDEX ON table.
type AlterFulltextIndexStatement struct {
	Token     token.Token
	TableName *QualifiedIdentifier
	Action    string            // ADD, DROP, ENABLE, DISABLE, START/STOP POPULATION, etc.
	Columns   []*FulltextColumn // Columns for ADD/DROP
}

func (afi *AlterFulltextIndexStatement) statementNode()       {}
func (afi *AlterFulltextIndexStatement) TokenLiteral() string { return afi.Token.Literal }
func (afi *AlterFulltextIndexStatement) String() string {
	var out strings.Builder
	out.WriteString("ALTER FULLTEXT INDEX ON ")
	out.WriteString(afi.TableName.String())
	out.WriteString(" ")
	out.WriteString(afi.Action)
	if len(afi.Columns) > 0 {
		out.WriteString(" (")
		for i, col := range afi.Columns {
			if i > 0 {
				out.WriteString(", ")
			}
			out.WriteString(col.String())
		}
		out.WriteString(")")
	}
	return out.String()
}

// DropFulltextIndexStatement represents DROP FULLTEXT INDEX ON table.
type DropFulltextIndexStatement struct {
	Token     token.Token
	TableName *QualifiedIdentifier
}

func (dfi *DropFulltextIndexStatement) statementNode()       {}
func (dfi *DropFulltextIndexStatement) TokenLiteral() string { return dfi.Token.Literal }
func (dfi *DropFulltextIndexStatement) String() string {
	return "DROP FULLTEXT INDEX ON " + dfi.TableName.String()
}

// DropFulltextCatalogStatement represents DROP FULLTEXT CATALOG.
type DropFulltextCatalogStatement struct {
	Token token.Token
	Name  string
}

func (dfc *DropFulltextCatalogStatement) statementNode()       {}
func (dfc *DropFulltextCatalogStatement) TokenLiteral() string { return dfc.Token.Literal }
func (dfc *DropFulltextCatalogStatement) String() string {
	return "DROP FULLTEXT CATALOG " + dfc.Name
}

// -----------------------------------------------------------------------------
// Stage 11: Resource Governor & Availability Groups
// -----------------------------------------------------------------------------

// CreateResourcePoolStatement represents CREATE RESOURCE POOL.
type CreateResourcePoolStatement struct {
	Token   token.Token
	Name    string
	Options map[string]string // WITH options like MAX_CPU_PERCENT, MAX_MEMORY_PERCENT
}

func (crp *CreateResourcePoolStatement) statementNode()       {}
func (crp *CreateResourcePoolStatement) TokenLiteral() string { return crp.Token.Literal }
func (crp *CreateResourcePoolStatement) String() string {
	var out strings.Builder
	out.WriteString("CREATE RESOURCE POOL ")
	out.WriteString(crp.Name)
	if len(crp.Options) > 0 {
		out.WriteString(" WITH (")
		first := true
		for k, v := range crp.Options {
			if !first {
				out.WriteString(", ")
			}
			out.WriteString(k)
			out.WriteString(" = ")
			out.WriteString(v)
			first = false
		}
		out.WriteString(")")
	}
	return out.String()
}

// AlterResourcePoolStatement represents ALTER RESOURCE POOL.
type AlterResourcePoolStatement struct {
	Token   token.Token
	Name    string
	Options map[string]string
}

func (arp *AlterResourcePoolStatement) statementNode()       {}
func (arp *AlterResourcePoolStatement) TokenLiteral() string { return arp.Token.Literal }
func (arp *AlterResourcePoolStatement) String() string {
	var out strings.Builder
	out.WriteString("ALTER RESOURCE POOL ")
	out.WriteString(arp.Name)
	if len(arp.Options) > 0 {
		out.WriteString(" WITH (")
		first := true
		for k, v := range arp.Options {
			if !first {
				out.WriteString(", ")
			}
			out.WriteString(k)
			out.WriteString(" = ")
			out.WriteString(v)
			first = false
		}
		out.WriteString(")")
	}
	return out.String()
}

// DropResourcePoolStatement represents DROP RESOURCE POOL.
type DropResourcePoolStatement struct {
	Token token.Token
	Name  string
}

func (drp *DropResourcePoolStatement) statementNode()       {}
func (drp *DropResourcePoolStatement) TokenLiteral() string { return drp.Token.Literal }
func (drp *DropResourcePoolStatement) String() string {
	return "DROP RESOURCE POOL " + drp.Name
}

// CreateWorkloadGroupStatement represents CREATE WORKLOAD GROUP.
type CreateWorkloadGroupStatement struct {
	Token            token.Token
	Name             string
	Options          map[string]string // WITH options
	PoolName         string            // USING pool_name
	ExternalPoolName string            // EXTERNAL external_pool_name
}

func (cwg *CreateWorkloadGroupStatement) statementNode()       {}
func (cwg *CreateWorkloadGroupStatement) TokenLiteral() string { return cwg.Token.Literal }
func (cwg *CreateWorkloadGroupStatement) String() string {
	var out strings.Builder
	out.WriteString("CREATE WORKLOAD GROUP ")
	out.WriteString(cwg.Name)
	if len(cwg.Options) > 0 {
		out.WriteString(" WITH (")
		first := true
		for k, v := range cwg.Options {
			if !first {
				out.WriteString(", ")
			}
			out.WriteString(k)
			out.WriteString(" = ")
			out.WriteString(v)
			first = false
		}
		out.WriteString(")")
	}
	if cwg.PoolName != "" {
		out.WriteString(" USING ")
		out.WriteString(cwg.PoolName)
	}
	return out.String()
}

// AlterWorkloadGroupStatement represents ALTER WORKLOAD GROUP.
type AlterWorkloadGroupStatement struct {
	Token    token.Token
	Name     string
	Options  map[string]string
	PoolName string
}

func (awg *AlterWorkloadGroupStatement) statementNode()       {}
func (awg *AlterWorkloadGroupStatement) TokenLiteral() string { return awg.Token.Literal }
func (awg *AlterWorkloadGroupStatement) String() string {
	var out strings.Builder
	out.WriteString("ALTER WORKLOAD GROUP ")
	out.WriteString(awg.Name)
	if len(awg.Options) > 0 {
		out.WriteString(" WITH (")
		first := true
		for k, v := range awg.Options {
			if !first {
				out.WriteString(", ")
			}
			out.WriteString(k)
			out.WriteString(" = ")
			out.WriteString(v)
			first = false
		}
		out.WriteString(")")
	}
	if awg.PoolName != "" {
		out.WriteString(" USING ")
		out.WriteString(awg.PoolName)
	}
	return out.String()
}

// DropWorkloadGroupStatement represents DROP WORKLOAD GROUP.
type DropWorkloadGroupStatement struct {
	Token token.Token
	Name  string
}

func (dwg *DropWorkloadGroupStatement) statementNode()       {}
func (dwg *DropWorkloadGroupStatement) TokenLiteral() string { return dwg.Token.Literal }
func (dwg *DropWorkloadGroupStatement) String() string {
	return "DROP WORKLOAD GROUP " + dwg.Name
}

// AlterResourceGovernorStatement represents ALTER RESOURCE GOVERNOR.
type AlterResourceGovernorStatement struct {
	Token              token.Token
	Action             string // RECONFIGURE, DISABLE, RESET STATISTICS
	ClassifierFunction string // CLASSIFIER_FUNCTION = schema.function or NULL
}

func (arg *AlterResourceGovernorStatement) statementNode()       {}
func (arg *AlterResourceGovernorStatement) TokenLiteral() string { return arg.Token.Literal }
func (arg *AlterResourceGovernorStatement) String() string {
	var out strings.Builder
	out.WriteString("ALTER RESOURCE GOVERNOR ")
	if arg.ClassifierFunction != "" {
		out.WriteString("WITH (CLASSIFIER_FUNCTION = ")
		out.WriteString(arg.ClassifierFunction)
		out.WriteString(")")
	} else if arg.Action != "" {
		out.WriteString(arg.Action)
	}
	return out.String()
}

// CreateAvailabilityGroupStatement represents CREATE AVAILABILITY GROUP.
type CreateAvailabilityGroupStatement struct {
	Token     token.Token
	Name      string
	Databases []string // FOR DATABASE db1, db2
	Replicas  []*AvailabilityReplica
}

// AvailabilityReplica represents a replica definition in an availability group.
type AvailabilityReplica struct {
	ServerName       string
	EndpointURL      string
	AvailabilityMode string // SYNCHRONOUS_COMMIT or ASYNCHRONOUS_COMMIT
	FailoverMode     string // AUTOMATIC or MANUAL
	Options          map[string]string
}

func (ar *AvailabilityReplica) String() string {
	var out strings.Builder
	out.WriteString("'")
	out.WriteString(ar.ServerName)
	out.WriteString("' WITH (")
	parts := []string{}
	if ar.EndpointURL != "" {
		parts = append(parts, "ENDPOINT_URL = '"+ar.EndpointURL+"'")
	}
	if ar.AvailabilityMode != "" {
		parts = append(parts, "AVAILABILITY_MODE = "+ar.AvailabilityMode)
	}
	if ar.FailoverMode != "" {
		parts = append(parts, "FAILOVER_MODE = "+ar.FailoverMode)
	}
	for k, v := range ar.Options {
		parts = append(parts, k+" = "+v)
	}
	out.WriteString(strings.Join(parts, ", "))
	out.WriteString(")")
	return out.String()
}

func (cag *CreateAvailabilityGroupStatement) statementNode()       {}
func (cag *CreateAvailabilityGroupStatement) TokenLiteral() string { return cag.Token.Literal }
func (cag *CreateAvailabilityGroupStatement) String() string {
	var out strings.Builder
	out.WriteString("CREATE AVAILABILITY GROUP ")
	out.WriteString(cag.Name)
	if len(cag.Databases) > 0 {
		out.WriteString(" FOR DATABASE ")
		out.WriteString(strings.Join(cag.Databases, ", "))
	}
	for _, replica := range cag.Replicas {
		out.WriteString(" REPLICA ON ")
		out.WriteString(replica.String())
	}
	return out.String()
}

// AlterAvailabilityGroupStatement represents ALTER AVAILABILITY GROUP.
type AlterAvailabilityGroupStatement struct {
	Token     token.Token
	Name      string
	Action    string                 // ADD DATABASE, REMOVE DATABASE, FAILOVER, FORCE_FAILOVER_ALLOW_DATA_LOSS, etc.
	Databases []string               // For ADD/REMOVE DATABASE
	Replicas  []*AvailabilityReplica // For ADD/MODIFY REPLICA
}

func (aag *AlterAvailabilityGroupStatement) statementNode()       {}
func (aag *AlterAvailabilityGroupStatement) TokenLiteral() string { return aag.Token.Literal }
func (aag *AlterAvailabilityGroupStatement) String() string {
	var out strings.Builder
	out.WriteString("ALTER AVAILABILITY GROUP ")
	out.WriteString(aag.Name)
	out.WriteString(" ")
	out.WriteString(aag.Action)
	if len(aag.Databases) > 0 {
		out.WriteString(" ")
		out.WriteString(strings.Join(aag.Databases, ", "))
	}
	return out.String()
}

// DropAvailabilityGroupStatement represents DROP AVAILABILITY GROUP.
type DropAvailabilityGroupStatement struct {
	Token token.Token
	Name  string
}

func (dag *DropAvailabilityGroupStatement) statementNode()       {}
func (dag *DropAvailabilityGroupStatement) TokenLiteral() string { return dag.Token.Literal }
func (dag *DropAvailabilityGroupStatement) String() string {
	return "DROP AVAILABILITY GROUP " + dag.Name
}

// -----------------------------------------------------------------------------
// Stage 12: Service Broker
// -----------------------------------------------------------------------------

// CreateMessageTypeStatement represents CREATE MESSAGE TYPE.
type CreateMessageTypeStatement struct {
	Token         token.Token
	Name          string
	Validation    string // NONE, EMPTY, WELL_FORMED_XML, VALID_XML WITH SCHEMA COLLECTION
	Authorization string
}

func (cmt *CreateMessageTypeStatement) statementNode()       {}
func (cmt *CreateMessageTypeStatement) TokenLiteral() string { return cmt.Token.Literal }
func (cmt *CreateMessageTypeStatement) String() string {
	var out strings.Builder
	out.WriteString("CREATE MESSAGE TYPE ")
	out.WriteString(cmt.Name)
	if cmt.Validation != "" {
		out.WriteString(" VALIDATION = ")
		out.WriteString(cmt.Validation)
	}
	return out.String()
}

// CreateContractStatement represents CREATE CONTRACT.
type CreateContractStatement struct {
	Token         token.Token
	Name          string
	Authorization string
	Messages      []*ContractMessage // Message types with SENT BY
}

// ContractMessage represents a message type in a contract.
type ContractMessage struct {
	MessageType string
	SentBy      string // INITIATOR, TARGET, ANY
}

func (cm *ContractMessage) String() string {
	return cm.MessageType + " SENT BY " + cm.SentBy
}

func (cc *CreateContractStatement) statementNode()       {}
func (cc *CreateContractStatement) TokenLiteral() string { return cc.Token.Literal }
func (cc *CreateContractStatement) String() string {
	var out strings.Builder
	out.WriteString("CREATE CONTRACT ")
	out.WriteString(cc.Name)
	if len(cc.Messages) > 0 {
		out.WriteString(" (")
		for i, msg := range cc.Messages {
			if i > 0 {
				out.WriteString(", ")
			}
			out.WriteString(msg.String())
		}
		out.WriteString(")")
	}
	return out.String()
}

// CreateQueueStatement represents CREATE QUEUE.
type CreateQueueStatement struct {
	Token       token.Token
	Name        *QualifiedIdentifier
	Options     map[string]string // WITH options: STATUS, RETENTION, ACTIVATION, POISON_MESSAGE_HANDLING
	OnFilegroup string
}

func (cq *CreateQueueStatement) statementNode()       {}
func (cq *CreateQueueStatement) TokenLiteral() string { return cq.Token.Literal }
func (cq *CreateQueueStatement) String() string {
	var out strings.Builder
	out.WriteString("CREATE QUEUE ")
	out.WriteString(cq.Name.String())
	if len(cq.Options) > 0 {
		out.WriteString(" WITH (")
		first := true
		for k, v := range cq.Options {
			if !first {
				out.WriteString(", ")
			}
			out.WriteString(k)
			out.WriteString(" = ")
			out.WriteString(v)
			first = false
		}
		out.WriteString(")")
	}
	return out.String()
}

// AlterQueueStatement represents ALTER QUEUE.
type AlterQueueStatement struct {
	Token   token.Token
	Name    *QualifiedIdentifier
	Options map[string]string
}

func (aq *AlterQueueStatement) statementNode()       {}
func (aq *AlterQueueStatement) TokenLiteral() string { return aq.Token.Literal }
func (aq *AlterQueueStatement) String() string {
	var out strings.Builder
	out.WriteString("ALTER QUEUE ")
	out.WriteString(aq.Name.String())
	if len(aq.Options) > 0 {
		out.WriteString(" WITH (")
		first := true
		for k, v := range aq.Options {
			if !first {
				out.WriteString(", ")
			}
			out.WriteString(k)
			out.WriteString(" = ")
			out.WriteString(v)
			first = false
		}
		out.WriteString(")")
	}
	return out.String()
}

// CreateServiceStatement represents CREATE SERVICE.
type CreateServiceStatement struct {
	Token         token.Token
	Name          string
	OnQueue       string
	Contracts     []string
	Authorization string
}

func (cs *CreateServiceStatement) statementNode()       {}
func (cs *CreateServiceStatement) TokenLiteral() string { return cs.Token.Literal }
func (cs *CreateServiceStatement) String() string {
	var out strings.Builder
	out.WriteString("CREATE SERVICE ")
	out.WriteString(cs.Name)
	out.WriteString(" ON QUEUE ")
	out.WriteString(cs.OnQueue)
	if len(cs.Contracts) > 0 {
		out.WriteString(" (")
		out.WriteString(strings.Join(cs.Contracts, ", "))
		out.WriteString(")")
	}
	return out.String()
}

// BeginDialogStatement represents BEGIN DIALOG CONVERSATION.
type BeginDialogStatement struct {
	Token        token.Token
	DialogHandle string // Variable to receive handle
	FromService  string
	ToService    string
	OnContract   string
	WithOptions  map[string]string // ENCRYPTION, LIFETIME, RELATED_CONVERSATION, etc.
}

func (bd *BeginDialogStatement) statementNode()       {}
func (bd *BeginDialogStatement) TokenLiteral() string { return bd.Token.Literal }
func (bd *BeginDialogStatement) String() string {
	var out strings.Builder
	out.WriteString("BEGIN DIALOG ")
	out.WriteString(bd.DialogHandle)
	out.WriteString(" FROM SERVICE ")
	out.WriteString(bd.FromService)
	out.WriteString(" TO SERVICE '")
	out.WriteString(bd.ToService)
	out.WriteString("'")
	if bd.OnContract != "" {
		out.WriteString(" ON CONTRACT ")
		out.WriteString(bd.OnContract)
	}
	return out.String()
}

// SendOnConversationStatement represents SEND ON CONVERSATION.
type SendOnConversationStatement struct {
	Token              token.Token
	ConversationHandle string // Variable or expression
	MessageType        string
	MessageBody        Expression
}

func (soc *SendOnConversationStatement) statementNode()       {}
func (soc *SendOnConversationStatement) TokenLiteral() string { return soc.Token.Literal }
func (soc *SendOnConversationStatement) String() string {
	var out strings.Builder
	out.WriteString("SEND ON CONVERSATION ")
	out.WriteString(soc.ConversationHandle)
	if soc.MessageType != "" {
		out.WriteString(" MESSAGE TYPE ")
		out.WriteString(soc.MessageType)
	}
	if soc.MessageBody != nil {
		out.WriteString(" (")
		out.WriteString(soc.MessageBody.String())
		out.WriteString(")")
	}
	return out.String()
}

// ReceiveStatement represents RECEIVE FROM queue.
type ReceiveStatement struct {
	Token     token.Token
	Top       Expression       // TOP(n)
	Columns   []*ReceiveColumn // Column assignments
	FromQueue *QualifiedIdentifier
	Into      string // INTO table_variable
	Where     Expression
	Timeout   Expression // WAITFOR with timeout
}

// ReceiveColumn represents a column in RECEIVE statement.
type ReceiveColumn struct {
	Variable   string // @var =
	ColumnName string // column_name
}

func (rc *ReceiveColumn) String() string {
	if rc.Variable != "" {
		return rc.Variable + " = " + rc.ColumnName
	}
	return rc.ColumnName
}

func (rs *ReceiveStatement) statementNode()       {}
func (rs *ReceiveStatement) TokenLiteral() string { return rs.Token.Literal }
func (rs *ReceiveStatement) String() string {
	var out strings.Builder
	out.WriteString("RECEIVE ")
	if rs.Top != nil {
		out.WriteString("TOP(")
		out.WriteString(rs.Top.String())
		out.WriteString(") ")
	}
	for i, col := range rs.Columns {
		if i > 0 {
			out.WriteString(", ")
		}
		out.WriteString(col.String())
	}
	out.WriteString(" FROM ")
	out.WriteString(rs.FromQueue.String())
	return out.String()
}

// EndConversationStatement represents END CONVERSATION.
type EndConversationStatement struct {
	Token              token.Token
	ConversationHandle string
	WithCleanup        bool
	WithError          Expression
	ErrorDescription   Expression
}

func (ec *EndConversationStatement) statementNode()       {}
func (ec *EndConversationStatement) TokenLiteral() string { return ec.Token.Literal }
func (ec *EndConversationStatement) String() string {
	var out strings.Builder
	out.WriteString("END CONVERSATION ")
	out.WriteString(ec.ConversationHandle)
	if ec.WithCleanup {
		out.WriteString(" WITH CLEANUP")
	}
	return out.String()
}

// GetConversationGroupStatement represents GET CONVERSATION GROUP.
type GetConversationGroupStatement struct {
	Token     token.Token
	GroupId   string // Variable to receive group ID
	FromQueue *QualifiedIdentifier
	Timeout   Expression
}

func (gcg *GetConversationGroupStatement) statementNode()       {}
func (gcg *GetConversationGroupStatement) TokenLiteral() string { return gcg.Token.Literal }
func (gcg *GetConversationGroupStatement) String() string {
	var out strings.Builder
	out.WriteString("GET CONVERSATION GROUP ")
	out.WriteString(gcg.GroupId)
	out.WriteString(" FROM ")
	out.WriteString(gcg.FromQueue.String())
	return out.String()
}

// MoveConversationStatement represents MOVE CONVERSATION.
type MoveConversationStatement struct {
	Token              token.Token
	ConversationHandle string
	ToGroupId          string
}

func (mc *MoveConversationStatement) statementNode()       {}
func (mc *MoveConversationStatement) TokenLiteral() string { return mc.Token.Literal }
func (mc *MoveConversationStatement) String() string {
	return "MOVE CONVERSATION " + mc.ConversationHandle + " TO " + mc.ToGroupId
}

// OpenJsonColumn represents a column definition in OPENJSON WITH clause.

type OpenJsonColumn struct {
	Name     string
	DataType *DataType
	Path     string // JSON path like '$.name'
	AsJson   bool   // AS JSON modifier
}

func (oc *OpenJsonColumn) String() string {
	var out strings.Builder
	out.WriteString(oc.Name)
	out.WriteString(" ")
	out.WriteString(oc.DataType.String())
	if oc.Path != "" {
		out.WriteString(" '")
		out.WriteString(oc.Path)
		out.WriteString("'")
	}
	if oc.AsJson {
		out.WriteString(" AS JSON")
	}
	return out.String()
}

// -----------------------------------------------------------------------------
// Stage 4: Sequences, Statistics, DBCC
// -----------------------------------------------------------------------------

// CreateSequenceStatement represents CREATE SEQUENCE.
type CreateSequenceStatement struct {
	Token       token.Token
	Name        *QualifiedIdentifier
	DataType    *DataType  // Optional: AS datatype
	StartWith   Expression // START WITH n
	IncrementBy Expression // INCREMENT BY n
	MinValue    Expression // MINVALUE n or NO MINVALUE
	MaxValue    Expression // MAXVALUE n or NO MAXVALUE
	NoMinValue  bool
	NoMaxValue  bool
	Cycle       bool // CYCLE or NO CYCLE
	NoCycle     bool
	Cache       Expression // CACHE n or NO CACHE
	NoCache     bool
}

func (cs *CreateSequenceStatement) statementNode()       {}
func (cs *CreateSequenceStatement) TokenLiteral() string { return cs.Token.Literal }
func (cs *CreateSequenceStatement) String() string {
	var out strings.Builder
	out.WriteString("CREATE SEQUENCE ")
	out.WriteString(cs.Name.String())
	if cs.DataType != nil {
		out.WriteString(" AS ")
		out.WriteString(cs.DataType.String())
	}
	if cs.StartWith != nil {
		out.WriteString(" START WITH ")
		out.WriteString(cs.StartWith.String())
	}
	if cs.IncrementBy != nil {
		out.WriteString(" INCREMENT BY ")
		out.WriteString(cs.IncrementBy.String())
	}
	if cs.NoMinValue {
		out.WriteString(" NO MINVALUE")
	} else if cs.MinValue != nil {
		out.WriteString(" MINVALUE ")
		out.WriteString(cs.MinValue.String())
	}
	if cs.NoMaxValue {
		out.WriteString(" NO MAXVALUE")
	} else if cs.MaxValue != nil {
		out.WriteString(" MAXVALUE ")
		out.WriteString(cs.MaxValue.String())
	}
	if cs.NoCycle {
		out.WriteString(" NO CYCLE")
	} else if cs.Cycle {
		out.WriteString(" CYCLE")
	}
	if cs.NoCache {
		out.WriteString(" NO CACHE")
	} else if cs.Cache != nil {
		out.WriteString(" CACHE ")
		out.WriteString(cs.Cache.String())
	}
	return out.String()
}

// CreateXmlSchemaCollectionStatement represents CREATE XML SCHEMA COLLECTION name AS N'...'
type CreateXmlSchemaCollectionStatement struct {
	Token      token.Token
	Name       *QualifiedIdentifier
	SchemaData string // The XML schema content
}

func (cs *CreateXmlSchemaCollectionStatement) statementNode()       {}
func (cs *CreateXmlSchemaCollectionStatement) TokenLiteral() string { return cs.Token.Literal }
func (cs *CreateXmlSchemaCollectionStatement) String() string {
	var out strings.Builder
	out.WriteString("CREATE XML SCHEMA COLLECTION ")
	out.WriteString(cs.Name.String())
	out.WriteString(" AS ")
	out.WriteString(cs.SchemaData)
	return out.String()
}

// AlterDatabaseStatement represents ALTER DATABASE.
type AlterDatabaseStatement struct {
	Token   token.Token
	Name    *Identifier
	Options string // Raw options (SET SINGLE_USER WITH ROLLBACK IMMEDIATE, etc.)
}

func (ad *AlterDatabaseStatement) statementNode()       {}
func (ad *AlterDatabaseStatement) TokenLiteral() string { return ad.Token.Literal }
func (ad *AlterDatabaseStatement) String() string {
	var out strings.Builder
	out.WriteString("ALTER DATABASE ")
	out.WriteString(ad.Name.Value)
	if ad.Options != "" {
		out.WriteString(" ")
		out.WriteString(ad.Options)
	}
	return out.String()
}

// AlterSequenceStatement represents ALTER SEQUENCE.
type AlterSequenceStatement struct {
	Token       token.Token
	Name        *QualifiedIdentifier
	RestartWith Expression // RESTART WITH n
	IncrementBy Expression
	MinValue    Expression
	MaxValue    Expression
	NoMinValue  bool
	NoMaxValue  bool
	Cycle       bool
	NoCycle     bool
	Cache       Expression
	NoCache     bool
}

func (as *AlterSequenceStatement) statementNode()       {}
func (as *AlterSequenceStatement) TokenLiteral() string { return as.Token.Literal }
func (as *AlterSequenceStatement) String() string {
	var out strings.Builder
	out.WriteString("ALTER SEQUENCE ")
	out.WriteString(as.Name.String())
	if as.RestartWith != nil {
		out.WriteString(" RESTART WITH ")
		out.WriteString(as.RestartWith.String())
	}
	if as.IncrementBy != nil {
		out.WriteString(" INCREMENT BY ")
		out.WriteString(as.IncrementBy.String())
	}
	if as.NoMinValue {
		out.WriteString(" NO MINVALUE")
	} else if as.MinValue != nil {
		out.WriteString(" MINVALUE ")
		out.WriteString(as.MinValue.String())
	}
	if as.NoMaxValue {
		out.WriteString(" NO MAXVALUE")
	} else if as.MaxValue != nil {
		out.WriteString(" MAXVALUE ")
		out.WriteString(as.MaxValue.String())
	}
	if as.NoCycle {
		out.WriteString(" NO CYCLE")
	} else if as.Cycle {
		out.WriteString(" CYCLE")
	}
	if as.NoCache {
		out.WriteString(" NO CACHE")
	} else if as.Cache != nil {
		out.WriteString(" CACHE ")
		out.WriteString(as.Cache.String())
	}
	return out.String()
}

// DropSequenceStatement represents DROP SEQUENCE.
type DropSequenceStatement struct {
	Token    token.Token
	IfExists bool
	Name     *QualifiedIdentifier
}

func (ds *DropSequenceStatement) statementNode()       {}
func (ds *DropSequenceStatement) TokenLiteral() string { return ds.Token.Literal }
func (ds *DropSequenceStatement) String() string {
	var out strings.Builder
	out.WriteString("DROP SEQUENCE ")
	if ds.IfExists {
		out.WriteString("IF EXISTS ")
	}
	out.WriteString(ds.Name.String())
	return out.String()
}

// CreateStatisticsStatement represents CREATE STATISTICS.
type CreateStatisticsStatement struct {
	Token       token.Token
	Name        string
	Table       *QualifiedIdentifier
	Columns     []*Identifier
	WithOptions []string // FULLSCAN, SAMPLE n PERCENT, NORECOMPUTE, etc.
}

func (cs *CreateStatisticsStatement) statementNode()       {}
func (cs *CreateStatisticsStatement) TokenLiteral() string { return cs.Token.Literal }
func (cs *CreateStatisticsStatement) String() string {
	var out strings.Builder
	out.WriteString("CREATE STATISTICS ")
	out.WriteString(cs.Name)
	out.WriteString(" ON ")
	out.WriteString(cs.Table.String())
	out.WriteString("(")
	for i, col := range cs.Columns {
		if i > 0 {
			out.WriteString(", ")
		}
		out.WriteString(col.Value)
	}
	out.WriteString(")")
	if len(cs.WithOptions) > 0 {
		out.WriteString(" WITH ")
		out.WriteString(strings.Join(cs.WithOptions, ", "))
	}
	return out.String()
}

// UpdateStatisticsStatement represents UPDATE STATISTICS.
type UpdateStatisticsStatement struct {
	Token       token.Token
	Table       *QualifiedIdentifier
	StatsName   string   // Optional specific stats name
	WithOptions []string // FULLSCAN, SAMPLE, RESAMPLE, etc.
}

func (us *UpdateStatisticsStatement) statementNode()       {}
func (us *UpdateStatisticsStatement) TokenLiteral() string { return us.Token.Literal }
func (us *UpdateStatisticsStatement) String() string {
	var out strings.Builder
	out.WriteString("UPDATE STATISTICS ")
	out.WriteString(us.Table.String())
	if us.StatsName != "" {
		out.WriteString(" ")
		out.WriteString(us.StatsName)
	}
	if len(us.WithOptions) > 0 {
		out.WriteString(" WITH ")
		out.WriteString(strings.Join(us.WithOptions, ", "))
	}
	return out.String()
}

// DropStatisticsStatement represents DROP STATISTICS.
type DropStatisticsStatement struct {
	Token token.Token
	Names []string // table.stats_name format
}

func (ds *DropStatisticsStatement) statementNode()       {}
func (ds *DropStatisticsStatement) TokenLiteral() string { return ds.Token.Literal }
func (ds *DropStatisticsStatement) String() string {
	return "DROP STATISTICS " + strings.Join(ds.Names, ", ")
}

// DbccStatement represents DBCC commands.
type DbccStatement struct {
	Token       token.Token
	Command     string       // CHECKDB, SHRINKFILE, FREEPROCCACHE, etc.
	Arguments   []Expression // Arguments in parentheses
	WithOptions []string     // WITH options
}

func (ds *DbccStatement) statementNode()       {}
func (ds *DbccStatement) TokenLiteral() string { return ds.Token.Literal }
func (ds *DbccStatement) String() string {
	var out strings.Builder
	out.WriteString("DBCC ")
	out.WriteString(ds.Command)
	if len(ds.Arguments) > 0 {
		out.WriteString("(")
		for i, arg := range ds.Arguments {
			if i > 0 {
				out.WriteString(", ")
			}
			out.WriteString(arg.String())
		}
		out.WriteString(")")
	}
	if len(ds.WithOptions) > 0 {
		out.WriteString(" WITH ")
		out.WriteString(strings.Join(ds.WithOptions, ", "))
	}
	return out.String()
}
