// Package tsqlparser provides a parser for Microsoft T-SQL.
//
// This package can be used to parse T-SQL stored procedures and other
// T-SQL statements into an Abstract Syntax Tree (AST) that can be
// analyzed and interpreted in Go.
//
// Example usage:
//
//	program, errors := tsqlparser.Parse(tsqlCode)
//	if len(errors) > 0 {
//	    // handle errors
//	}
//	// work with program.Statements
package tsqlparser

import (
	"github.com/ha1tch/tsqlparser/ast"
	"github.com/ha1tch/tsqlparser/lexer"
	"github.com/ha1tch/tsqlparser/parser"
	"github.com/ha1tch/tsqlparser/token"
)

// Parse parses T-SQL code and returns the AST and any errors.
func Parse(input string) (*ast.Program, []string) {
	l := lexer.New(input)
	p := parser.New(l)
	program := p.ParseProgram()
	return program, p.Errors()
}

// Tokenize returns all tokens from the input.
func Tokenize(input string) []token.Token {
	return lexer.Tokenize(input)
}

// Re-export types for convenience
type (
	Program    = ast.Program
	Statement  = ast.Statement
	Expression = ast.Expression
	Token      = token.Token
)

// Statement types
type (
	SelectStatement              = ast.SelectStatement
	InsertStatement              = ast.InsertStatement
	UpdateStatement              = ast.UpdateStatement
	DeleteStatement              = ast.DeleteStatement
	DeclareStatement             = ast.DeclareStatement
	SetStatement                 = ast.SetStatement
	IfStatement                  = ast.IfStatement
	WhileStatement               = ast.WhileStatement
	BeginEndBlock                = ast.BeginEndBlock
	TryCatchStatement            = ast.TryCatchStatement
	ReturnStatement              = ast.ReturnStatement
	BreakStatement               = ast.BreakStatement
	ContinueStatement            = ast.ContinueStatement
	PrintStatement               = ast.PrintStatement
	ExecStatement                = ast.ExecStatement
	CreateProcedureStatement     = ast.CreateProcedureStatement
	ThrowStatement               = ast.ThrowStatement
	RaiserrorStatement           = ast.RaiserrorStatement
	BeginTransactionStatement    = ast.BeginTransactionStatement
	CommitTransactionStatement   = ast.CommitTransactionStatement
	RollbackTransactionStatement = ast.RollbackTransactionStatement
	WithStatement                = ast.WithStatement
	GoStatement                  = ast.GoStatement
	// Stage 1: Table Infrastructure
	CreateTableStatement   = ast.CreateTableStatement
	DropTableStatement     = ast.DropTableStatement
	TruncateTableStatement = ast.TruncateTableStatement
	AlterTableStatement    = ast.AlterTableStatement
	// Stage 2: Cursor Support
	DeclareCursorStatement    = ast.DeclareCursorStatement
	OpenCursorStatement       = ast.OpenCursorStatement
	FetchStatement            = ast.FetchStatement
	CloseCursorStatement      = ast.CloseCursorStatement
	DeallocateCursorStatement = ast.DeallocateCursorStatement
)

// Expression types
type (
	Identifier          = ast.Identifier
	QualifiedIdentifier = ast.QualifiedIdentifier
	Variable            = ast.Variable
	IntegerLiteral      = ast.IntegerLiteral
	FloatLiteral        = ast.FloatLiteral
	StringLiteral       = ast.StringLiteral
	NullLiteral         = ast.NullLiteral
	BinaryLiteral       = ast.BinaryLiteral
	PrefixExpression    = ast.PrefixExpression
	InfixExpression     = ast.InfixExpression
	BetweenExpression   = ast.BetweenExpression
	InExpression        = ast.InExpression
	LikeExpression      = ast.LikeExpression
	IsNullExpression    = ast.IsNullExpression
	ExistsExpression    = ast.ExistsExpression
	CaseExpression      = ast.CaseExpression
	FunctionCall        = ast.FunctionCall
	SubqueryExpression  = ast.SubqueryExpression
)

// Helper types
type (
	DataType      = ast.DataType
	ParameterDef  = ast.ParameterDef
	VariableDef   = ast.VariableDef
	SelectColumn  = ast.SelectColumn
	TableName     = ast.TableName
	DerivedTable  = ast.DerivedTable
	JoinClause    = ast.JoinClause
	OrderByItem   = ast.OrderByItem
	SetClause     = ast.SetClause
	OverClause    = ast.OverClause
	WhenClause    = ast.WhenClause
	CTEDef        = ast.CTEDef
	FromClause    = ast.FromClause
	TopClause     = ast.TopClause
	ExecParameter = ast.ExecParameter
	// Stage 1: Table Infrastructure
	ColumnDefinition    = ast.ColumnDefinition
	TableConstraint     = ast.TableConstraint
	ColumnConstraint    = ast.ColumnConstraint
	IndexColumn         = ast.IndexColumn
	IdentitySpec        = ast.IdentitySpec
	AlterTableAction    = ast.AlterTableAction
	TableTypeDefinition = ast.TableTypeDefinition
	// Stage 2: Cursor Support
	CursorOptions = ast.CursorOptions
	// Stage 3: Query Enhancements
	WindowFrame         = ast.WindowFrame
	FrameBound          = ast.FrameBound
	TableValuedFunction = ast.TableValuedFunction
	// Stage 4a: OUTPUT and DML Enhancements
	OutputClause = ast.OutputClause
	// Stage 4b: MERGE Statement
	MergeStatement  = ast.MergeStatement
	MergeWhenClause = ast.MergeWhenClause
	MergeActionType = ast.MergeActionType
	MergeWhenType   = ast.MergeWhenType
	// Stage 5: DDL Completion
	CreateViewStatement     = ast.CreateViewStatement
	AlterViewStatement      = ast.AlterViewStatement
	CreateIndexStatement    = ast.CreateIndexStatement
	DropIndexStatement      = ast.DropIndexStatement
	CreateFunctionStatement = ast.CreateFunctionStatement
	AlterFunctionStatement  = ast.AlterFunctionStatement
	CreateTriggerStatement  = ast.CreateTriggerStatement
	AlterTriggerStatement   = ast.AlterTriggerStatement
	AlterProcedureStatement = ast.AlterProcedureStatement
	DropObjectStatement     = ast.DropObjectStatement
	TriggerTiming           = ast.TriggerTiming
	FunctionType            = ast.FunctionType
	// Stage 6: Set Operations & Grouping
	UnionClause     = ast.UnionClause
	TupleExpression = ast.TupleExpression
	// Stage 7a: Quick Wins
	UseStatement                     = ast.UseStatement
	WaitforStatement                 = ast.WaitforStatement
	SaveTransactionStatement         = ast.SaveTransactionStatement
	GotoStatement                    = ast.GotoStatement
	LabelStatement                   = ast.LabelStatement
	SetOptionStatement               = ast.SetOptionStatement
	SetTransactionIsolationStatement = ast.SetTransactionIsolationStatement

	// Type conversion
	CastExpression    = ast.CastExpression
	ConvertExpression = ast.ConvertExpression

	// FOR XML/JSON
	ForClause = ast.ForClause

	// PIVOT/UNPIVOT
	PivotTable   = ast.PivotTable
	UnpivotTable = ast.UnpivotTable

	// ALTER INDEX / BULK INSERT
	AlterIndexStatement = ast.AlterIndexStatement
	BulkInsertStatement = ast.BulkInsertStatement

	// COLLATE and OPTION
	CollateExpression = ast.CollateExpression
	QueryOption       = ast.QueryOption

	// Stage 10 additions
	NextValueForExpression = ast.NextValueForExpression
	ParseExpression        = ast.ParseExpression
	ValuesTable            = ast.ValuesTable
)

// Visitor defines an interface for AST visitors.
type Visitor interface {
	Visit(node ast.Node) Visitor
}

// Walk traverses an AST in depth-first order.
func Walk(v Visitor, node ast.Node) {
	if v = v.Visit(node); v == nil {
		return
	}

	switch n := node.(type) {
	case *ast.Program:
		for _, stmt := range n.Statements {
			Walk(v, stmt)
		}
	case *ast.SelectStatement:
		for _, col := range n.Columns {
			if col.Expression != nil {
				Walk(v, col.Expression)
			}
		}
		if n.Where != nil {
			Walk(v, n.Where)
		}
		for _, g := range n.GroupBy {
			Walk(v, g)
		}
		if n.Having != nil {
			Walk(v, n.Having)
		}
	case *ast.InsertStatement:
		if n.Select != nil {
			Walk(v, n.Select)
		}
		for _, row := range n.Values {
			for _, val := range row {
				Walk(v, val)
			}
		}
	case *ast.UpdateStatement:
		for _, sc := range n.SetClauses {
			Walk(v, sc.Value)
		}
		if n.Where != nil {
			Walk(v, n.Where)
		}
	case *ast.DeleteStatement:
		if n.Where != nil {
			Walk(v, n.Where)
		}
	case *ast.IfStatement:
		Walk(v, n.Condition)
		Walk(v, n.Consequence)
		if n.Alternative != nil {
			Walk(v, n.Alternative)
		}
	case *ast.WhileStatement:
		Walk(v, n.Condition)
		Walk(v, n.Body)
	case *ast.BeginEndBlock:
		for _, stmt := range n.Statements {
			Walk(v, stmt)
		}
	case *ast.TryCatchStatement:
		Walk(v, n.TryBlock)
		Walk(v, n.CatchBlock)
	case *ast.CreateProcedureStatement:
		if n.Body != nil {
			Walk(v, n.Body)
		}
	case *ast.InfixExpression:
		Walk(v, n.Left)
		Walk(v, n.Right)
	case *ast.PrefixExpression:
		Walk(v, n.Right)
	case *ast.FunctionCall:
		for _, arg := range n.Arguments {
			Walk(v, arg)
		}
	case *ast.CaseExpression:
		if n.Operand != nil {
			Walk(v, n.Operand)
		}
		for _, wc := range n.WhenClauses {
			Walk(v, wc.Condition)
			Walk(v, wc.Result)
		}
		if n.ElseClause != nil {
			Walk(v, n.ElseClause)
		}
	}
}

// Inspector provides a convenient way to inspect AST nodes.
type Inspector struct {
	nodes []ast.Node
}

// NewInspector creates a new Inspector for the given program.
func NewInspector(program *ast.Program) *Inspector {
	insp := &Inspector{}
	insp.collect(program)
	return insp
}

func (insp *Inspector) collect(node ast.Node) {
	insp.nodes = append(insp.nodes, node)

	switch n := node.(type) {
	case *ast.Program:
		for _, stmt := range n.Statements {
			insp.collect(stmt)
		}
	case *ast.SelectStatement:
		for _, col := range n.Columns {
			if col.Expression != nil {
				insp.collect(col.Expression)
			}
		}
		if n.Where != nil {
			insp.collect(n.Where)
		}
	case *ast.BeginEndBlock:
		for _, stmt := range n.Statements {
			insp.collect(stmt)
		}
	case *ast.IfStatement:
		insp.collect(n.Condition)
		insp.collect(n.Consequence)
		if n.Alternative != nil {
			insp.collect(n.Alternative)
		}
	case *ast.WhileStatement:
		insp.collect(n.Condition)
		insp.collect(n.Body)
	case *ast.TryCatchStatement:
		insp.collect(n.TryBlock)
		insp.collect(n.CatchBlock)
	case *ast.CreateProcedureStatement:
		if n.Body != nil {
			insp.collect(n.Body)
		}
	case *ast.InfixExpression:
		insp.collect(n.Left)
		insp.collect(n.Right)
	case *ast.PrefixExpression:
		insp.collect(n.Right)
	case *ast.FunctionCall:
		for _, arg := range n.Arguments {
			insp.collect(arg)
		}
	}
}

// FindVariables returns all variable references in the AST.
func (insp *Inspector) FindVariables() []*ast.Variable {
	var vars []*ast.Variable
	for _, node := range insp.nodes {
		if v, ok := node.(*ast.Variable); ok {
			vars = append(vars, v)
		}
	}
	return vars
}

// FindFunctionCalls returns all function calls in the AST.
func (insp *Inspector) FindFunctionCalls() []*ast.FunctionCall {
	var calls []*ast.FunctionCall
	for _, node := range insp.nodes {
		if fc, ok := node.(*ast.FunctionCall); ok {
			calls = append(calls, fc)
		}
	}
	return calls
}

// FindSelectStatements returns all SELECT statements in the AST.
func (insp *Inspector) FindSelectStatements() []*ast.SelectStatement {
	var stmts []*ast.SelectStatement
	for _, node := range insp.nodes {
		if ss, ok := node.(*ast.SelectStatement); ok {
			stmts = append(stmts, ss)
		}
	}
	return stmts
}
