// Package parser implements a parser for T-SQL.
package parser

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/ha1tch/tsqlparser/ast"
	"github.com/ha1tch/tsqlparser/lexer"
	"github.com/ha1tch/tsqlparser/token"
)

// Operator precedence levels
const (
	_ int = iota
	LOWEST
	OR_PREC      // OR
	AND_PREC     // AND
	NOT_PREC     // NOT
	COMPARE      // =, <>, <, >, <=, >=
	BETWEEN_PREC // BETWEEN, IN, LIKE
	BITOR        // |
	BITXOR       // ^
	BITAND       // &
	SHIFT        // <<, >>
	SUM          // +, -
	PRODUCT      // *, /, %
	PREFIX       // -X, ~X
	CALL         // function()
	INDEX        // table.column
)

var precedences = map[token.Type]int{
	token.OR:                   OR_PREC,
	token.AND:                  AND_PREC,
	token.NOT:                  BETWEEN_PREC, // For NOT IN, NOT LIKE, NOT BETWEEN
	token.EQ:                   COMPARE,
	token.NEQ:                  COMPARE,
	token.LT:                   COMPARE,
	token.GT:                   COMPARE,
	token.LTE:                  COMPARE,
	token.GTE:                  COMPARE,
	token.NOT_LT:               COMPARE,
	token.NOT_GT:               COMPARE,
	token.IS:                   COMPARE,
	token.IS_DISTINCT_FROM:     COMPARE,
	token.IS_NOT_DISTINCT_FROM: COMPARE,
	token.LIKE:                 BETWEEN_PREC,
	token.BETWEEN:              BETWEEN_PREC,
	token.IN:                   BETWEEN_PREC,
	token.COLLATE:              CALL, // High precedence, binds tightly
	token.AT:                   CALL, // AT TIME ZONE - high precedence like COLLATE
	token.PIPE:                 BITOR,
	token.CARET:                BITXOR,
	token.AMPERSAND:            BITAND,
	token.LSHIFT:               SHIFT,
	token.RSHIFT:               SHIFT,
	token.PLUS:                 SUM,
	token.MINUS:                SUM,
	token.ASTERISK:             PRODUCT,
	token.SLASH:                PRODUCT,
	token.PERCENT:              PRODUCT,
	token.LPAREN:               CALL,
	token.DOT:                  INDEX,
	token.SCOPE:                INDEX,
}

type (
	prefixParseFn func() ast.Expression
	infixParseFn  func(ast.Expression) ast.Expression
)

// Parser represents a T-SQL parser.
type Parser struct {
	l      *lexer.Lexer
	errors []string

	curToken      token.Token
	peekToken     token.Token
	peekPeekToken token.Token // Second look-ahead for special cases

	prefixParseFns map[token.Type]prefixParseFn
	infixParseFns  map[token.Type]infixParseFn
}

// New creates a new Parser.
func New(l *lexer.Lexer) *Parser {
	p := &Parser{
		l:      l,
		errors: []string{},
	}

	p.prefixParseFns = make(map[token.Type]prefixParseFn)
	p.registerPrefix(token.IDENT, p.parseIdentifier)
	p.registerPrefix(token.VARIABLE, p.parseVariable)
	p.registerPrefix(token.TEMPVAR, p.parseVariable)
	p.registerPrefix(token.SYSVAR, p.parseSysVar)
	p.registerPrefix(token.INT, p.parseIntegerLiteral)
	p.registerPrefix(token.FLOAT, p.parseFloatLiteral)
	p.registerPrefix(token.MONEY_LIT, p.parseMoneyLiteral)
	p.registerPrefix(token.STRING, p.parseStringLiteral)
	p.registerPrefix(token.NSTRING, p.parseNStringLiteral)
	p.registerPrefix(token.NULL, p.parseNullLiteral)
	p.registerPrefix(token.BINARY, p.parseBinaryLiteral)
	p.registerPrefix(token.NOT, p.parsePrefixExpression)
	p.registerPrefix(token.MINUS, p.parsePrefixExpression)
	p.registerPrefix(token.PLUS, p.parsePrefixExpression)
	p.registerPrefix(token.TILDE, p.parsePrefixExpression)
	p.registerPrefix(token.LPAREN, p.parseGroupedExpression)
	p.registerPrefix(token.CASE, p.parseCaseExpression)
	p.registerPrefix(token.EXISTS, p.parseExistsExpression)
	p.registerPrefix(token.SELECT, p.parseSubqueryExpression)
	p.registerPrefix(token.ASTERISK, p.parseAsterisk)

	// Type conversion functions with special syntax
	p.registerPrefix(token.CAST, p.parseCastExpression)
	p.registerPrefix(token.TRY_CAST, p.parseCastExpression)
	p.registerPrefix(token.CONVERT, p.parseConvertExpression)
	p.registerPrefix(token.TRY_CONVERT, p.parseConvertExpression)
	p.registerPrefix(token.PARSE, p.parseParseExpression)
	p.registerPrefix(token.TRY_PARSE, p.parseParseExpression)
	p.registerPrefix(token.TRIM, p.parseTrimExpression)
	p.registerPrefix(token.CURSOR, p.parseCursorExpression)
	p.registerPrefix(token.NEXT, p.parseNextValueFor)
	p.registerPrefix(token.NEXT_VALUE_FOR, p.parseNextValueForCompound)
	p.registerPrefix(token.ALL, p.parseAllExpression)

	// Register full-text search predicates
	p.registerPrefix(token.CONTAINS, p.parseContainsExpression)
	p.registerPrefix(token.FREETEXT, p.parseFreetextExpression)
	p.registerPrefix(token.CONTAINSTABLE, p.parseContainsTableExpression)
	p.registerPrefix(token.FREETEXTTABLE, p.parseFreetextTableExpression)

	// Register function names as prefix parsers
	for _, fn := range []token.Type{
		token.COUNT, token.SUM, token.AVG, token.MIN, token.MAX,
		token.COALESCE, token.NULLIF, token.IIF,
		token.ROW_NUMBER, token.RANK, token.DENSE_RANK, token.NTILE,
		token.LAG, token.LEAD, token.FIRST_VALUE, token.LAST_VALUE,
		token.CONTEXT_INFO,
	} {
		p.registerPrefix(fn, p.parseFunctionLiteral)
	}

	// Register data type keywords that can be used as column names
	// These are treated as identifiers when used in expression context
	for _, dt := range []token.Type{
		token.DATE, token.TIME, token.DATETIME, token.DATETIME2,
		token.TEXT, token.NTEXT, token.IMAGE,
		token.MONEY, token.SMALLMONEY,
		token.REAL,
		token.XML,
		token.KEY, token.LEFT, token.RIGHT,
		// Window frame keywords that can also be identifiers
		token.ROWS, token.RANGE, token.ROW,
		token.CURRENT, token.UNBOUNDED, token.PRECEDING, token.FOLLOWING,
		// DEFAULT can appear in VALUES clauses
		token.DEFAULT_KW,
		// SETS and RESULT can be identifiers (GROUPING SETS, RESULT column names)
		token.SETS, token.RESULT,
		// GROUPING, CUBE, ROLLUP can be used as functions (GROUPING(col), etc.)
		token.GROUPING, token.CUBE, token.ROLLUP,
		// MERGE keywords that are commonly used as table aliases
		token.TARGET, token.SOURCE, token.MATCHED,
		// Common column names that are also keywords
		token.VALUE, token.LEVEL, token.TYPE_WARNING,
		token.ACTION, token.PATH, token.LOG,
		// Data types used as column names
		token.CHAR, token.VARCHAR, token.NCHAR, token.NVARCHAR, token.INT_TYPE,
		// JOIN keywords sometimes used as aliases
		token.INNER, token.OUTER, token.CROSS, token.APPLY,
		// Misc keywords used as identifiers
		token.PERCENT_KW, token.MESSAGE, token.CONVERSATION,
		// EXECUTE AS keywords
		token.OWNER_KW, token.CALLER,
		// SET options and query hints
		token.NOCOUNT, token.OPTION,
		// Index keywords and data types often used as column names
		token.CLUSTERED, token.NONCLUSTERED, token.TIMESTAMP,
		token.CHECKSUM, token.COLLATE,
		// More common identifier conflicts
		token.INDEX, token.STATS, token.MEMBER, token.SUBJECT,
		token.RESOURCE, token.PRIMARY,
		// Spatial data types
		token.GEOGRAPHY, token.GEOMETRY, token.HIERARCHYID,
		// Additional keywords commonly used as column names or aliases
		token.CYCLE, token.ROLE, token.ADD, token.BULK, token.RECOVERY,
		token.PARTITION, token.ALGORITHM, token.AFTER, token.SNAPSHOT,
		token.OUTPUT, token.LANGUAGE, token.ISOLATION, token.AUTO,
		token.GET, token.INCREMENT, token.SELF, token.IDENTITY,
		token.INIT, token.COMPRESSION, token.PERIOD, token.ENCRYPTION,
		token.AUTHORIZATION, token.LOCAL, token.GLOBAL,
		token.DATABASE, token.NONE_KW, token.DISK, token.FUNCTION,
		token.CONSTRAINT, token.CHECK, token.FOREIGN, token.REFERENCES,
		// Sequence keywords often used as column names (MaxValue, MinValue)
		token.MAXVALUE, token.MINVALUE,
		token.CERTIFICATE, token.QUEUE, token.RECEIVE, token.UPDATE,
		token.TRANSACTION, token.DELETE, token.INSERT,
		// Hint keywords as identifiers
		token.HASH, token.LOOP, token.REMOTE, token.MERGE,
	} {
		p.registerPrefix(dt, p.parseKeywordAsIdentifier)
	}

	p.infixParseFns = make(map[token.Type]infixParseFn)
	p.registerInfix(token.PLUS, p.parseInfixExpression)
	p.registerInfix(token.MINUS, p.parseInfixExpression)
	p.registerInfix(token.SLASH, p.parseInfixExpression)
	p.registerInfix(token.ASTERISK, p.parseInfixExpression)
	p.registerInfix(token.PERCENT, p.parseInfixExpression)
	p.registerInfix(token.EQ, p.parseInfixExpression)
	p.registerInfix(token.NEQ, p.parseInfixExpression)
	p.registerInfix(token.LT, p.parseInfixExpression)
	p.registerInfix(token.GT, p.parseInfixExpression)
	p.registerInfix(token.LTE, p.parseInfixExpression)
	p.registerInfix(token.GTE, p.parseInfixExpression)
	p.registerInfix(token.NOT_LT, p.parseInfixExpression)
	p.registerInfix(token.NOT_GT, p.parseInfixExpression)
	p.registerInfix(token.AND, p.parseInfixExpression)
	p.registerInfix(token.OR, p.parseInfixExpression)
	p.registerInfix(token.AMPERSAND, p.parseInfixExpression)
	p.registerInfix(token.PIPE, p.parseInfixExpression)
	p.registerInfix(token.CARET, p.parseInfixExpression)
	p.registerInfix(token.LSHIFT, p.parseInfixExpression)
	p.registerInfix(token.RSHIFT, p.parseInfixExpression)
	p.registerInfix(token.LPAREN, p.parseCallExpression)
	p.registerInfix(token.DOT, p.parseDotExpression)
	p.registerInfix(token.SCOPE, p.parseScopeExpression)
	p.registerInfix(token.LIKE, p.parseLikeExpression)
	p.registerInfix(token.BETWEEN, p.parseBetweenExpression)
	p.registerInfix(token.IN, p.parseInExpression)
	p.registerInfix(token.IS, p.parseIsNullExpression)
	p.registerInfix(token.IS_DISTINCT_FROM, p.parseDistinctFromExpression)
	p.registerInfix(token.IS_NOT_DISTINCT_FROM, p.parseDistinctFromExpression)
	p.registerInfix(token.NOT, p.parseNotInfixExpression)
	p.registerInfix(token.COLLATE, p.parseCollateExpression)
	p.registerInfix(token.AT, p.parseAtTimeZoneExpression)

	// Read three tokens to initialize curToken, peekToken, and peekPeekToken
	p.nextToken()
	p.nextToken()
	p.nextToken()

	return p
}

func (p *Parser) registerPrefix(tokenType token.Type, fn prefixParseFn) {
	p.prefixParseFns[tokenType] = fn
}

func (p *Parser) registerInfix(tokenType token.Type, fn infixParseFn) {
	p.infixParseFns[tokenType] = fn
}

// Errors returns the parser errors.
func (p *Parser) Errors() []string {
	return p.errors
}

func (p *Parser) peekError(t token.Type) {
	msg := fmt.Sprintf("line %d, col %d: expected %s, got %s",
		p.peekToken.Line, p.peekToken.Column, t, p.peekToken.Type)
	p.errors = append(p.errors, msg)
}

func (p *Parser) nextToken() {
	p.curToken = p.peekToken
	p.peekToken = p.peekPeekToken
	p.peekPeekToken = p.l.NextToken()
	// Skip comments
	for p.peekPeekToken.Type == token.COMMENT {
		p.peekPeekToken = p.l.NextToken()
	}
}

func (p *Parser) curTokenIs(t token.Type) bool {
	return p.curToken.Type == t
}

func (p *Parser) peekTokenIs(t token.Type) bool {
	return p.peekToken.Type == t
}

func (p *Parser) peekPeekTokenIs(t token.Type) bool {
	return p.peekPeekToken.Type == t
}

func (p *Parser) expectPeek(t token.Type) bool {
	if p.peekTokenIs(t) {
		p.nextToken()
		return true
	}
	p.peekError(t)
	return false
}

func (p *Parser) peekPrecedence() int {
	if p, ok := precedences[p.peekToken.Type]; ok {
		return p
	}
	return LOWEST
}

func (p *Parser) curPrecedence() int {
	if p, ok := precedences[p.curToken.Type]; ok {
		return p
	}
	return LOWEST
}

// ParseProgram parses the entire program.
func (p *Parser) ParseProgram() *ast.Program {
	program := &ast.Program{}
	program.Statements = []ast.Statement{}

	for !p.curTokenIs(token.EOF) {
		stmt := p.parseStatement()
		if stmt != nil {
			program.Statements = append(program.Statements, stmt)
		}
		p.nextToken()
	}

	return program
}

func (p *Parser) parseStatement() ast.Statement {
	// Skip semicolons
	for p.curTokenIs(token.SEMICOLON) {
		p.nextToken()
	}

	switch p.curToken.Type {
	case token.SELECT:
		return p.parseSelectStatement()
	case token.INSERT:
		return p.parseInsertStatement()
	case token.UPDATE:
		// Check for UPDATE STATISTICS
		if p.peekTokenIs(token.STATISTICS) {
			p.nextToken() // move to STATISTICS
			return p.parseUpdateStatisticsStatement()
		}
		return p.parseUpdateStatement()
	case token.DELETE:
		return p.parseDeleteStatement()
	case token.MERGE:
		return p.parseMergeStatement()
	case token.DECLARE:
		return p.parseDeclareStatement()
	case token.SET:
		return p.parseSetStatement()
	case token.IF:
		return p.parseIfStatement()
	case token.WHILE:
		return p.parseWhileStatement()
	case token.BEGIN:
		return p.parseBeginStatement()
	case token.RETURN:
		return p.parseReturnStatement()
	case token.BREAK:
		return p.parseBreakStatement()
	case token.CONTINUE:
		return p.parseContinueStatement()
	case token.PRINT:
		return p.parsePrintStatement()
	case token.EXEC, token.EXECUTE:
		return p.parseExecStatement()
	case token.CREATE:
		return p.parseCreateStatement()
	case token.CREATE_RULE:
		return p.parseCreateRuleStatement()
	case token.DROP:
		return p.parseDropStatement()
	case token.TRUNCATE:
		return p.parseTruncateStatement()
	case token.TRUNCATE_TABLE:
		return p.parseTruncateTableCompound()
	case token.ALTER:
		return p.parseAlterStatement()
	case token.THROW:
		return p.parseThrowStatement()
	case token.RAISERROR:
		return p.parseRaiserrorStatement()
	case token.COMMIT:
		return p.parseCommitStatement()
	case token.ROLLBACK:
		return p.parseRollbackStatement()
	case token.WITH:
		return p.parseWithStatement()
	case token.WITH_XMLNAMESPACES:
		return p.parseWithXmlnamespacesStatement()
	case token.GO:
		return p.parseGoStatement()
	case token.ENABLE:
		return p.parseEnableDisableTriggerStatement(true)
	case token.DISABLE:
		return p.parseEnableDisableTriggerStatement(false)
	// Stage 2: Cursor statements
	case token.OPEN:
		return p.parseOpenCursorStatement()
	case token.CLOSE:
		return p.parseCloseCursorStatement()
	case token.FETCH_KW:
		return p.parseFetchStatement()
	case token.DEALLOCATE:
		return p.parseDeallocateCursorStatement()
	// Stage 7a: Quick wins
	case token.USE:
		return p.parseUseStatement()
	case token.WAITFOR:
		return p.parseWaitforStatement()
	case token.SAVE:
		return p.parseSaveTransactionStatement()
	case token.GOTO:
		return p.parseGotoStatement()
	case token.BULK:
		return p.parseBulkInsertStatement()
	case token.REVERT:
		return p.parseRevertStatement()
	case token.RECONFIGURE:
		return p.parseReconfigureStatement()
	case token.DBCC:
		return p.parseDbccStatement()
	case token.GRANT:
		return p.parseGrantStatement()
	case token.REVOKE:
		return p.parseRevokeStatement()
	case token.DENY:
		return p.parseDenyStatement()
	case token.BACKUP:
		return p.parseBackupStatement()
	case token.RESTORE:
		return p.parseRestoreStatement()
	case token.SEND:
		return p.parseSendOnConversationStatement()
	case token.RECEIVE:
		return p.parseReceiveStatement()
	case token.MOVE:
		return p.parseMoveConversationStatement()
	case token.END_CONVERSATION:
		return p.parseEndConversationStatement()
	case token.GET:
		// GET CONVERSATION GROUP
		return p.parseGetConversationGroupStatement()
	case token.LPAREN:
		// Parenthesized SELECT for set operations: (SELECT ...) UNION/INTERSECT/EXCEPT SELECT ...
		return p.parseParenthesizedSelectStatement()
	case token.EOF:
		return nil
	default:
		// Check for label definition (identifier followed by colon)
		if p.curTokenIs(token.IDENT) && p.peekTokenIs(token.COLON) {
			return p.parseLabelStatement()
		}
		return p.parseExpressionStatement()
	}
}

// -----------------------------------------------------------------------------
// Expression Parsing
// -----------------------------------------------------------------------------

func (p *Parser) parseExpression(precedence int) ast.Expression {
	prefix := p.prefixParseFns[p.curToken.Type]
	if prefix == nil {
		p.noPrefixParseFnError(p.curToken.Type)
		return nil
	}
	leftExp := prefix()

	for !p.peekTokenIs(token.SEMICOLON) && precedence < p.peekPrecedence() {
		infix := p.infixParseFns[p.peekToken.Type]
		if infix == nil {
			return leftExp
		}

		p.nextToken()
		leftExp = infix(leftExp)
	}

	return leftExp
}

func (p *Parser) noPrefixParseFnError(t token.Type) {
	msg := fmt.Sprintf("line %d, col %d: no prefix parse function for %s found",
		p.curToken.Line, p.curToken.Column, t)
	p.errors = append(p.errors, msg)
}

func (p *Parser) parseIdentifier() ast.Expression {
	return &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
}

func (p *Parser) parseVariable() ast.Expression {
	return &ast.Variable{Token: p.curToken, Name: p.curToken.Literal}
}

func (p *Parser) parseSysVar() ast.Expression {
	// $action, $identity, etc. - treat as identifier
	return &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
}

// parseKeywordAsIdentifier treats a keyword token as an identifier
// This allows data type keywords like DATE, TIME to be used as column names
func (p *Parser) parseKeywordAsIdentifier() ast.Expression {
	return &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
}

func (p *Parser) parseIntegerLiteral() ast.Expression {
	lit := &ast.IntegerLiteral{Token: p.curToken}
	value, err := strconv.ParseInt(p.curToken.Literal, 10, 64)
	if err != nil {
		// Check if this is a valid uint64 that overflows int64
		// This handles cases like 9223372036854775808 which is valid in SQL
		// when used with unary minus
		uvalue, uerr := strconv.ParseUint(p.curToken.Literal, 10, 64)
		if uerr == nil {
			// Store as the unsigned value cast to int64
			// The sign will be applied by the prefix expression
			lit.Value = int64(uvalue)
			return lit
		}
		// For very large numbers (like DECIMAL(38,0)), we can't fit in int64/uint64
		// Just store 0 and rely on Token.Literal for the actual value
		// String() method already returns Token.Literal
		lit.Value = 0
		return lit
	}
	lit.Value = value
	return lit
}

func (p *Parser) parseFloatLiteral() ast.Expression {
	lit := &ast.FloatLiteral{Token: p.curToken}
	value, err := strconv.ParseFloat(p.curToken.Literal, 64)
	if err != nil {
		msg := fmt.Sprintf("could not parse %q as float", p.curToken.Literal)
		p.errors = append(p.errors, msg)
		return nil
	}
	lit.Value = value
	return lit
}

func (p *Parser) parseMoneyLiteral() ast.Expression {
	return &ast.MoneyLiteral{Token: p.curToken, Value: p.curToken.Literal}
}

func (p *Parser) parseStringLiteral() ast.Expression {
	return &ast.StringLiteral{Token: p.curToken, Value: p.curToken.Literal, Unicode: false}
}

func (p *Parser) parseNStringLiteral() ast.Expression {
	return &ast.StringLiteral{Token: p.curToken, Value: p.curToken.Literal, Unicode: true}
}

func (p *Parser) parseNullLiteral() ast.Expression {
	return &ast.NullLiteral{Token: p.curToken}
}

func (p *Parser) parseBinaryLiteral() ast.Expression {
	return &ast.BinaryLiteral{Token: p.curToken, Value: p.curToken.Literal}
}

func (p *Parser) parseAsterisk() ast.Expression {
	return &ast.Identifier{Token: p.curToken, Value: "*"}
}

func (p *Parser) parsePrefixExpression() ast.Expression {
	expression := &ast.PrefixExpression{
		Token:    p.curToken,
		Operator: p.curToken.Literal,
	}
	p.nextToken()
	expression.Right = p.parseExpression(PREFIX)
	return expression
}

func (p *Parser) parseInfixExpression(left ast.Expression) ast.Expression {
	expression := &ast.InfixExpression{
		Token:    p.curToken,
		Operator: strings.ToUpper(p.curToken.Literal),
		Left:     left,
	}
	precedence := p.curPrecedence()
	p.nextToken()
	expression.Right = p.parseExpression(precedence)
	return expression
}

func (p *Parser) parseGroupedExpression() ast.Expression {
	tok := p.curToken
	p.nextToken()

	// Check for empty tuple () - used in GROUPING SETS
	if p.curTokenIs(token.RPAREN) {
		return &ast.TupleExpression{Token: tok, Elements: []ast.Expression{}}
	}

	// Check if this is a subquery
	if p.curTokenIs(token.SELECT) {
		subq := p.parseSelectStatement()
		if !p.expectPeek(token.RPAREN) {
			return nil
		}
		return &ast.SubqueryExpression{Token: p.curToken, Subquery: subq}
	}

	exp := p.parseExpression(LOWEST)
	if !p.expectPeek(token.RPAREN) {
		return nil
	}
	return exp
}

func (p *Parser) parseDotExpression(left ast.Expression) ast.Expression {
	dotToken := p.curToken
	p.nextToken()

	// Get the method/property name
	methodName := p.curToken.Literal

	// Check if this is a method call (followed by parentheses)
	if p.peekTokenIs(token.LPAREN) {
		// This is a method call like @xml.value('xpath', 'type')
		mc := &ast.MethodCallExpression{
			Token:      dotToken,
			Object:     left,
			MethodName: methodName,
		}
		p.nextToken() // move to (
		mc.Arguments = p.parseExpressionList(token.RPAREN)
		return mc
	}

	// Not a method call, build qualified identifier as before
	right := &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}

	parts := []*ast.Identifier{}

	// Unpack left side if it's already a qualified identifier
	if qi, ok := left.(*ast.QualifiedIdentifier); ok {
		parts = append(parts, qi.Parts...)
	} else if id, ok := left.(*ast.Identifier); ok {
		parts = append(parts, id)
	}

	parts = append(parts, right)

	return &ast.QualifiedIdentifier{Parts: parts}
}

// parseScopeExpression handles static method calls like GEOGRAPHY::Point(...)
func (p *Parser) parseScopeExpression(left ast.Expression) ast.Expression {
	scopeToken := p.curToken

	// Get the type name from the left expression
	var typeName string
	if id, ok := left.(*ast.Identifier); ok {
		typeName = id.Value
	} else if qi, ok := left.(*ast.QualifiedIdentifier); ok {
		typeName = qi.String()
	} else {
		typeName = left.String()
	}

	p.nextToken() // move past ::

	// Get the method name
	methodName := p.curToken.Literal

	// Check for function call
	if p.peekTokenIs(token.LPAREN) {
		sm := &ast.StaticMethodCall{
			Token:      scopeToken,
			TypeName:   typeName,
			MethodName: methodName,
		}
		p.nextToken() // move to (
		sm.Arguments = p.parseExpressionList(token.RPAREN)
		return sm
	}

	// Not a function call - treat as a qualified name (e.g., SCHEMA::SchemaName)
	sm := &ast.StaticMethodCall{
		Token:      scopeToken,
		TypeName:   typeName,
		MethodName: methodName,
		Arguments:  nil,
	}
	return sm
}

func (p *Parser) parseCallExpression(function ast.Expression) ast.Expression {
	exp := &ast.FunctionCall{Token: p.curToken, Function: function}
	exp.Arguments = p.parseExpressionList(token.RPAREN)

	// Check for WITHIN GROUP clause (for ordered-set aggregate functions)
	if p.peekTokenIs(token.WITHIN) {
		p.nextToken() // consume WITHIN
		if !p.expectPeek(token.GROUP) {
			return nil
		}
		if !p.expectPeek(token.LPAREN) {
			return nil
		}
		if !p.expectPeek(token.ORDER) {
			return nil
		}
		if !p.expectPeek(token.BY) {
			return nil
		}
		p.nextToken()
		exp.WithinGroup = p.parseOrderByItems()
		if !p.expectPeek(token.RPAREN) {
			return nil
		}
	}

	// Check for OVER clause
	if p.peekTokenIs(token.OVER) {
		p.nextToken()
		exp.Over = p.parseOverClause()
	}

	return exp
}

func (p *Parser) parseExpressionList(end token.Type) []ast.Expression {
	list := []ast.Expression{}

	if p.peekTokenIs(end) {
		p.nextToken()
		return list
	}

	p.nextToken()

	// Handle DISTINCT in aggregate functions
	if p.curTokenIs(token.DISTINCT) {
		p.nextToken()
	}

	expr := p.parseExpression(LOWEST)

	// Check for JSON key:value syntax (e.g., JSON_OBJECT('id':1))
	if p.peekTokenIs(token.COLON) {
		p.nextToken() // consume :
		p.nextToken() // move to value
		value := p.parseExpression(LOWEST)
		expr = &ast.JsonKeyValuePair{
			Token: p.curToken,
			Key:   expr,
			Value: value,
		}
	}

	list = append(list, expr)

	for p.peekTokenIs(token.COMMA) {
		p.nextToken()
		p.nextToken()
		expr := p.parseExpression(LOWEST)

		// Check for JSON key:value syntax
		if p.peekTokenIs(token.COLON) {
			p.nextToken() // consume :
			p.nextToken() // move to value
			value := p.parseExpression(LOWEST)
			expr = &ast.JsonKeyValuePair{
				Token: p.curToken,
				Key:   expr,
				Value: value,
			}
		}

		list = append(list, expr)
	}

	if !p.expectPeek(end) {
		return nil
	}

	return list
}

func (p *Parser) parseFunctionLiteral() ast.Expression {
	ident := &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
	// If not followed by (, treat as identifier (e.g., RANK used as column alias)
	if !p.peekTokenIs(token.LPAREN) {
		return ident
	}
	p.nextToken() // consume (
	return p.parseCallExpression(ident)
}

func (p *Parser) parseCaseExpression() ast.Expression {
	expr := &ast.CaseExpression{Token: p.curToken}
	p.nextToken()

	// Check for simple CASE operand
	if !p.curTokenIs(token.WHEN) {
		expr.Operand = p.parseExpression(LOWEST)
		p.nextToken()
	}

	// Parse WHEN clauses
	for p.curTokenIs(token.WHEN) {
		when := &ast.WhenClause{}
		p.nextToken()
		when.Condition = p.parseExpression(LOWEST)

		if !p.expectPeek(token.THEN) {
			return nil
		}
		p.nextToken()
		when.Result = p.parseExpression(LOWEST)
		expr.WhenClauses = append(expr.WhenClauses, when)
		p.nextToken()
	}

	// Parse ELSE clause
	if p.curTokenIs(token.ELSE) {
		p.nextToken()
		expr.ElseClause = p.parseExpression(LOWEST)
		p.nextToken()
	}

	// Expect END
	if !p.curTokenIs(token.END) {
		p.errors = append(p.errors, "expected END in CASE expression")
		return nil
	}

	return expr
}

// parseCastExpression parses CAST(expr AS type) or TRY_CAST(expr AS type)
func (p *Parser) parseCastExpression() ast.Expression {
	expr := &ast.CastExpression{Token: p.curToken}
	expr.IsTry = p.curToken.Type == token.TRY_CAST

	if !p.expectPeek(token.LPAREN) {
		return nil
	}
	p.nextToken()

	// Parse the expression to be cast
	expr.Expression = p.parseExpression(LOWEST)

	// Expect AS keyword
	if !p.expectPeek(token.AS) {
		return nil
	}
	p.nextToken()

	// Parse target data type
	expr.TargetType = p.parseDataType()

	// Expect closing paren
	if !p.expectPeek(token.RPAREN) {
		return nil
	}

	return expr
}

// parseConvertExpression parses CONVERT(type, expr [, style]) or TRY_CONVERT(type, expr [, style])
func (p *Parser) parseConvertExpression() ast.Expression {
	expr := &ast.ConvertExpression{Token: p.curToken}
	expr.IsTry = p.curToken.Type == token.TRY_CONVERT

	if !p.expectPeek(token.LPAREN) {
		return nil
	}
	p.nextToken()

	// Parse target data type (first argument)
	expr.TargetType = p.parseDataType()

	// Expect comma
	if !p.expectPeek(token.COMMA) {
		return nil
	}
	p.nextToken()

	// Parse the expression to convert
	expr.Expression = p.parseExpression(LOWEST)

	// Check for optional style parameter
	if p.peekTokenIs(token.COMMA) {
		p.nextToken() // consume comma
		p.nextToken() // move to style
		expr.Style = p.parseExpression(LOWEST)
	}

	// Expect closing paren
	if !p.expectPeek(token.RPAREN) {
		return nil
	}

	return expr
}

// parseParseExpression parses PARSE(expr AS type [USING culture]) or TRY_PARSE(...)
func (p *Parser) parseParseExpression() ast.Expression {
	expr := &ast.ParseExpression{Token: p.curToken}
	expr.IsTry = p.curToken.Type == token.TRY_PARSE

	if !p.expectPeek(token.LPAREN) {
		return nil
	}
	p.nextToken()

	// Parse the expression to parse
	expr.Expression = p.parseExpression(LOWEST)

	// Expect AS keyword
	if !p.expectPeek(token.AS) {
		return nil
	}
	p.nextToken()

	// Parse target data type
	expr.TargetType = p.parseDataType()

	// Check for optional USING culture
	if p.peekTokenIs(token.USING) {
		p.nextToken() // consume USING
		p.nextToken() // move to culture expression
		expr.Culture = p.parseExpression(LOWEST)
	}

	// Expect closing paren
	if !p.expectPeek(token.RPAREN) {
		return nil
	}

	return expr
}

// parseTrimExpression parses TRIM([LEADING|TRAILING|BOTH] [chars FROM] expr)
func (p *Parser) parseTrimExpression() ast.Expression {
	expr := &ast.TrimExpression{Token: p.curToken}

	if !p.expectPeek(token.LPAREN) {
		return nil
	}
	p.nextToken()

	// Check for LEADING, TRAILING, or BOTH
	if p.curToken.Literal == "LEADING" || p.curToken.Literal == "TRAILING" || p.curToken.Literal == "BOTH" {
		expr.TrimSpec = p.curToken.Literal
		p.nextToken()
	}

	// Parse first expression (could be characters to trim or the string itself)
	firstExpr := p.parseExpression(LOWEST)

	// Check if there's a FROM keyword
	if p.peekTokenIs(token.FROM) {
		// First expression is the characters to trim
		expr.Characters = firstExpr
		p.nextToken() // consume FROM
		p.nextToken()
		expr.Expression = p.parseExpression(LOWEST)
	} else {
		// No FROM, so first expression is the string to trim
		expr.Expression = firstExpr
	}

	// Expect closing paren
	if !p.expectPeek(token.RPAREN) {
		return nil
	}

	return expr
}

// parseCursorExpression parses CURSOR [options] FOR select_statement
func (p *Parser) parseCursorExpression() ast.Expression {
	expr := &ast.CursorExpression{Token: p.curToken}
	p.nextToken() // move past CURSOR

	// Parse cursor options
	expr.Options = p.parseCursorOptions()

	// Expect FOR
	if p.curTokenIs(token.FOR) {
		p.nextToken()
		expr.ForSelect = p.parseSelectStatement()
	}

	return expr
}

// parseNextValueFor parses NEXT VALUE FOR sequence_name
func (p *Parser) parseNextValueFor() ast.Expression {
	expr := &ast.NextValueForExpression{Token: p.curToken}

	// Expect VALUE
	if !p.expectPeek(token.VALUE) {
		return nil
	}

	// Expect FOR
	if !p.expectPeek(token.FOR) {
		return nil
	}
	p.nextToken()

	// Parse sequence name (qualified identifier)
	expr.SequenceName = p.parseQualifiedIdentifier()

	return expr
}

// parseNextValueForCompound handles the NEXT_VALUE_FOR compound token
func (p *Parser) parseNextValueForCompound() ast.Expression {
	expr := &ast.NextValueForExpression{Token: p.curToken}
	p.nextToken() // move past NEXT VALUE FOR

	// Parse sequence name (qualified identifier)
	expr.SequenceName = p.parseQualifiedIdentifier()

	// Check for OVER clause: NEXT VALUE FOR seq OVER (ORDER BY ...)
	if p.peekTokenIs(token.OVER) {
		p.nextToken() // consume OVER
		expr.Over = p.parseOverClause()
	}

	return expr
}

func (p *Parser) parseExistsExpression() ast.Expression {
	expr := &ast.ExistsExpression{Token: p.curToken}
	if !p.expectPeek(token.LPAREN) {
		return nil
	}
	p.nextToken()
	expr.Subquery = p.parseSelectStatement()
	if !p.expectPeek(token.RPAREN) {
		return nil
	}
	return expr
}

func (p *Parser) parseAllExpression() ast.Expression {
	// ALL (subquery) - used in comparisons like: Col > ALL (SELECT Val FROM T)
	expr := &ast.FunctionCall{
		Token:    p.curToken,
		Function: &ast.Identifier{Token: p.curToken, Value: "ALL"},
	}
	if !p.expectPeek(token.LPAREN) {
		return nil
	}
	p.nextToken()
	// Parse the subquery as an argument
	subquery := p.parseSelectStatement()
	expr.Arguments = []ast.Expression{&ast.SubqueryExpression{Subquery: subquery}}
	if !p.expectPeek(token.RPAREN) {
		return nil
	}
	return expr
}

func (p *Parser) parseSubqueryExpression() ast.Expression {
	subq := p.parseSelectStatement()
	return &ast.SubqueryExpression{Token: p.curToken, Subquery: subq}
}

func (p *Parser) parseLikeExpression(left ast.Expression) ast.Expression {
	expr := &ast.LikeExpression{Token: p.curToken, Expr: left}

	// Check for NOT
	if strings.ToUpper(p.curToken.Literal) == "NOT" {
		expr.Not = true
		p.nextToken()
	}

	p.nextToken()
	expr.Pattern = p.parseExpression(LOWEST)

	// Check for ESCAPE clause
	if p.peekTokenIs(token.ESCAPE) {
		p.nextToken()
		p.nextToken()
		expr.Escape = p.parseExpression(LOWEST)
	}

	return expr
}

func (p *Parser) parseCollateExpression(left ast.Expression) ast.Expression {
	expr := &ast.CollateExpression{Token: p.curToken, Expr: left}
	p.nextToken()
	expr.Collation = p.curToken.Literal
	return expr
}

func (p *Parser) parseAtTimeZoneExpression(left ast.Expression) ast.Expression {
	// Only parse as AT TIME ZONE if TIME actually follows
	// Otherwise, return just the left expression (AT will be handled by caller)
	if !p.peekTokenIs(token.TIME) {
		return left
	}

	expr := &ast.AtTimeZoneExpression{Token: p.curToken, Expr: left}

	// Expect TIME
	if !p.expectPeek(token.TIME) {
		return nil
	}

	// Expect ZONE
	if !p.expectPeek(token.ZONE) {
		return nil
	}

	p.nextToken()
	// Parse timezone with CALL precedence to avoid consuming comparison operators
	expr.TimeZone = p.parseExpression(CALL)

	return expr
}

func (p *Parser) parseBetweenExpression(left ast.Expression) ast.Expression {
	expr := &ast.BetweenExpression{Token: p.curToken, Expr: left}

	p.nextToken()
	// Parse low bound with precedence higher than AND to prevent AND from being consumed
	expr.Low = p.parseExpression(AND_PREC)

	if !p.expectPeek(token.AND) {
		return nil
	}
	p.nextToken()
	// Parse high bound normally
	expr.High = p.parseExpression(BETWEEN_PREC)

	return expr
}

func (p *Parser) parseInExpression(left ast.Expression) ast.Expression {
	expr := &ast.InExpression{Token: p.curToken, Expr: left}

	if !p.expectPeek(token.LPAREN) {
		return nil
	}
	p.nextToken()

	// Check if it's a subquery
	if p.curTokenIs(token.SELECT) {
		expr.Subquery = p.parseSelectStatement()
	} else {
		// Parse value list
		expr.Values = []ast.Expression{p.parseExpression(LOWEST)}
		for p.peekTokenIs(token.COMMA) {
			p.nextToken()
			p.nextToken()
			expr.Values = append(expr.Values, p.parseExpression(LOWEST))
		}
	}

	if !p.expectPeek(token.RPAREN) {
		return nil
	}

	return expr
}

func (p *Parser) parseIsNullExpression(left ast.Expression) ast.Expression {
	expr := &ast.IsNullExpression{Token: p.curToken, Expr: left}
	p.nextToken()

	if p.curTokenIs(token.NOT) {
		expr.Not = true
		p.nextToken()
	}

	if !p.curTokenIs(token.NULL) {
		p.errors = append(p.errors, "expected NULL after IS")
		return nil
	}

	return expr
}

// parseDistinctFromExpression handles IS [NOT] DISTINCT FROM expressions
func (p *Parser) parseDistinctFromExpression(left ast.Expression) ast.Expression {
	expr := &ast.IsDistinctFromExpression{Token: p.curToken, Left: left}

	// Check if this is IS NOT DISTINCT FROM
	if p.curTokenIs(token.IS_NOT_DISTINCT_FROM) {
		expr.Not = true
	}

	p.nextToken() // move past IS [NOT] DISTINCT FROM

	expr.Right = p.parseExpression(COMPARE)

	return expr
}

func (p *Parser) parseNotInfixExpression(left ast.Expression) ast.Expression {
	// Handle NOT IN, NOT LIKE, NOT BETWEEN
	p.nextToken()

	switch p.curToken.Type {
	case token.IN:
		expr := &ast.InExpression{Token: p.curToken, Expr: left, Not: true}
		if !p.expectPeek(token.LPAREN) {
			return nil
		}
		p.nextToken()

		if p.curTokenIs(token.SELECT) {
			expr.Subquery = p.parseSelectStatement()
		} else {
			expr.Values = []ast.Expression{p.parseExpression(LOWEST)}
			for p.peekTokenIs(token.COMMA) {
				p.nextToken()
				p.nextToken()
				expr.Values = append(expr.Values, p.parseExpression(LOWEST))
			}
		}

		if !p.expectPeek(token.RPAREN) {
			return nil
		}
		return expr

	case token.LIKE:
		expr := &ast.LikeExpression{Token: p.curToken, Expr: left, Not: true}
		p.nextToken()
		expr.Pattern = p.parseExpression(LOWEST)
		if p.peekTokenIs(token.ESCAPE) {
			p.nextToken()
			p.nextToken()
			expr.Escape = p.parseExpression(LOWEST)
		}
		return expr

	case token.BETWEEN:
		expr := &ast.BetweenExpression{Token: p.curToken, Expr: left, Not: true}
		p.nextToken()
		expr.Low = p.parseExpression(AND_PREC)
		if !p.expectPeek(token.AND) {
			return nil
		}
		p.nextToken()
		expr.High = p.parseExpression(BETWEEN_PREC)
		return expr

	default:
		// Just a regular NOT - shouldn't happen in infix position
		p.errors = append(p.errors, fmt.Sprintf("unexpected token after NOT: %s", p.curToken.Type))
		return nil
	}
}

func (p *Parser) parseOverClause() *ast.OverClause {
	over := &ast.OverClause{Token: p.curToken}

	// Check for named window reference: OVER w
	if p.peekTokenIs(token.IDENT) {
		p.nextToken()
		over.WindowRef = p.curToken.Literal
		return over
	}

	if !p.expectPeek(token.LPAREN) {
		return nil
	}
	p.nextToken()

	// Parse PARTITION BY
	if p.curTokenIs(token.PARTITION) {
		if !p.expectPeek(token.BY) {
			return nil
		}
		p.nextToken()
		over.PartitionBy = append(over.PartitionBy, p.parseExpression(LOWEST))
		for p.peekTokenIs(token.COMMA) {
			p.nextToken()
			p.nextToken()
			over.PartitionBy = append(over.PartitionBy, p.parseExpression(LOWEST))
		}
		p.nextToken()
	}

	// Parse ORDER BY
	if p.curTokenIs(token.ORDER) {
		if !p.expectPeek(token.BY) {
			return nil
		}
		p.nextToken()
		over.OrderBy = p.parseOrderByItems()
		// After parsing ORDER BY items, advance if we're not at the OVER clause terminator
		// Handle case where expression ends with ) like (SELECT NULL) which could be
		// confused with the OVER clause closing paren
		if p.curTokenIs(token.RPAREN) && p.peekTokenIs(token.RPAREN) {
			// Current ) is from subquery, advance to OVER's closing )
			p.nextToken()
		} else if !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.ROWS) && !p.curTokenIs(token.RANGE) {
			p.nextToken()
		}
	}

	// Parse window frame (ROWS or RANGE)
	if p.curTokenIs(token.ROWS) || p.curTokenIs(token.RANGE) {
		over.Frame = p.parseWindowFrame()
	}

	if !p.curTokenIs(token.RPAREN) {
		if !p.expectPeek(token.RPAREN) {
			return nil
		}
	}

	return over
}

func (p *Parser) parseWindowDefinitions() []*ast.WindowDefinition {
	var defs []*ast.WindowDefinition

	for {
		p.nextToken() // move to window name
		def := &ast.WindowDefinition{Name: p.curToken.Literal}

		if !p.expectPeek(token.AS) {
			return defs
		}

		if !p.expectPeek(token.LPAREN) {
			return defs
		}

		// Create an OverClause to reuse parsing logic
		over := &ast.OverClause{Token: p.curToken}
		p.nextToken()

		// Parse PARTITION BY
		if p.curTokenIs(token.PARTITION) {
			if p.peekTokenIs(token.BY) {
				p.nextToken()
				p.nextToken()
				over.PartitionBy = append(over.PartitionBy, p.parseExpression(LOWEST))
				for p.peekTokenIs(token.COMMA) {
					p.nextToken()
					p.nextToken()
					over.PartitionBy = append(over.PartitionBy, p.parseExpression(LOWEST))
				}
				p.nextToken()
			}
		}

		// Parse ORDER BY
		if p.curTokenIs(token.ORDER) {
			if p.peekTokenIs(token.BY) {
				p.nextToken()
				p.nextToken()
				over.OrderBy = p.parseOrderByItems()
			}
		}

		// Skip to closing paren
		for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
			p.nextToken()
		}

		def.Spec = over
		defs = append(defs, def)

		// Check for more window definitions (comma-separated)
		if !p.peekTokenIs(token.COMMA) {
			break
		}
		p.nextToken() // consume comma
	}

	return defs
}

func (p *Parser) parseWindowFrame() *ast.WindowFrame {
	frame := &ast.WindowFrame{}

	if p.curTokenIs(token.ROWS) {
		frame.Type = "ROWS"
	} else {
		frame.Type = "RANGE"
	}
	p.nextToken()

	// Check for BETWEEN
	if p.curTokenIs(token.BETWEEN) {
		p.nextToken()
		frame.Start = p.parseFrameBound()
		if !p.expectPeek(token.AND) {
			return frame
		}
		p.nextToken()
		frame.End = p.parseFrameBound()
	} else {
		frame.Start = p.parseFrameBound()
	}

	return frame
}

func (p *Parser) parseFrameBound() *ast.FrameBound {
	bound := &ast.FrameBound{}

	switch {
	case p.curTokenIs(token.UNBOUNDED):
		p.nextToken()
		if p.curTokenIs(token.PRECEDING) {
			bound.Type = "UNBOUNDED PRECEDING"
		} else if p.curTokenIs(token.FOLLOWING) {
			bound.Type = "UNBOUNDED FOLLOWING"
		}
	case p.curTokenIs(token.CURRENT):
		p.nextToken() // skip CURRENT
		// expect ROW
		if p.curTokenIs(token.ROW) {
			bound.Type = "CURRENT ROW"
		}
	default:
		// n PRECEDING or n FOLLOWING
		bound.Offset = p.parseExpression(LOWEST)
		p.nextToken()
		if p.curTokenIs(token.PRECEDING) {
			bound.Type = "PRECEDING"
		} else if p.curTokenIs(token.FOLLOWING) {
			bound.Type = "FOLLOWING"
		}
	}

	return bound
}

// -----------------------------------------------------------------------------
// SELECT Statement
// -----------------------------------------------------------------------------

// parseParenthesizedSelectStatement handles (SELECT ...) UNION/INTERSECT/EXCEPT SELECT ...
func (p *Parser) parseParenthesizedSelectStatement() ast.Statement {
	// We're at the opening (
	p.nextToken() // move past (

	// Parse the inner SELECT
	if !p.curTokenIs(token.SELECT) {
		// Not a SELECT inside parens, fall back to expression statement
		// Backtrack is complex, so just parse as expression
		return p.parseExpressionStatement()
	}

	innerSelect := p.parseSelectStatement()

	// Expect closing )
	if !p.expectPeek(token.RPAREN) {
		return nil
	}

	// Now check for set operation: UNION, INTERSECT, EXCEPT
	if p.peekTokenIs(token.UNION) || p.peekTokenIs(token.INTERSECT) || p.peekTokenIs(token.EXCEPT) {
		p.nextToken() // consume set operator
		opToken := p.curToken

		// Check for ALL
		isAll := false
		if p.peekTokenIs(token.ALL) {
			p.nextToken()
			isAll = true
		}

		p.nextToken() // move to next SELECT
		if !p.curTokenIs(token.SELECT) && !p.curTokenIs(token.LPAREN) {
			return innerSelect
		}

		var rightSelect *ast.SelectStatement
		if p.curTokenIs(token.LPAREN) {
			// Recursive parenthesized select
			rightStmt := p.parseParenthesizedSelectStatement()
			if rs, ok := rightStmt.(*ast.SelectStatement); ok {
				rightSelect = rs
			}
		} else {
			rightSelect = p.parseSelectStatement()
		}

		// Create a UnionClause (also used for INTERSECT/EXCEPT)
		innerSelect.Union = &ast.UnionClause{
			Type:  strings.ToUpper(opToken.Literal),
			All:   isAll,
			Right: rightSelect,
		}
	}

	return innerSelect
}

func (p *Parser) parseSelectStatement() *ast.SelectStatement {
	stmt := &ast.SelectStatement{Token: p.curToken}
	p.nextToken()

	// Parse DISTINCT
	if p.curTokenIs(token.DISTINCT) {
		stmt.Distinct = true
		p.nextToken()
	} else if p.curTokenIs(token.ALL) {
		p.nextToken()
	}

	// Parse TOP
	if p.curTokenIs(token.TOP) {
		stmt.Top = p.parseTopClause()
		p.nextToken()
	}

	// Parse column list
	stmt.Columns = p.parseSelectColumns()

	// Parse INTO
	if p.peekTokenIs(token.INTO) {
		p.nextToken()
		p.nextToken()
		stmt.Into = p.parseQualifiedIdentifier()
		// Parse optional ON [filegroup] or ON PartitionScheme(column)
		if p.peekTokenIs(token.ON) {
			p.nextToken() // consume ON
			p.nextToken() // move to filegroup name
			stmt.IntoFilegroup = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
			// Check for partition scheme column
			if p.peekTokenIs(token.LPAREN) {
				p.nextToken() // consume (
				p.nextToken() // move to column
				for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
					p.nextToken()
				}
			}
		}
	}

	// Parse FROM
	if p.peekTokenIs(token.FROM) {
		p.nextToken()
		stmt.From = p.parseFromClause()
	}

	// Parse WHERE
	if p.peekTokenIs(token.WHERE) {
		p.nextToken()
		p.nextToken()
		stmt.Where = p.parseExpression(LOWEST)
	}

	// Parse GROUP BY
	if p.peekTokenIs(token.GROUP) {
		p.nextToken()
		if !p.expectPeek(token.BY) {
			return nil
		}
		p.nextToken()
		stmt.GroupBy = p.parseGroupByItems()
	}

	// Parse HAVING
	if p.peekTokenIs(token.HAVING) {
		p.nextToken()
		p.nextToken()
		stmt.Having = p.parseExpression(LOWEST)
	}

	// Parse WINDOW clause: WINDOW w AS (...)
	if p.peekTokenIs(token.WINDOW) {
		p.nextToken()
		stmt.WindowDefs = p.parseWindowDefinitions()
	}

	// Parse ORDER BY
	if p.peekTokenIs(token.ORDER) {
		p.nextToken()
		if !p.expectPeek(token.BY) {
			return nil
		}
		p.nextToken()
		stmt.OrderBy = p.parseOrderByItems()
	}

	// Parse OFFSET
	if p.peekTokenIs(token.OFFSET) {
		p.nextToken()
		p.nextToken()
		stmt.Offset = p.parseExpression(LOWEST)
		// Skip ROWS/ROW
		if p.peekTokenIs(token.ROWS) || p.peekTokenIs(token.ROW) {
			p.nextToken()
		}
	}

	// Parse FETCH
	if p.peekTokenIs(token.FETCH_KW) {
		p.nextToken()
		// Skip NEXT or FIRST
		if p.peekTokenIs(token.NEXT) || p.peekTokenIs(token.FIRST) {
			p.nextToken()
		}
		p.nextToken()
		stmt.Fetch = p.parseExpression(LOWEST)
		// Skip ROWS/ROW
		if p.peekTokenIs(token.ROWS) || p.peekTokenIs(token.ROW) {
			p.nextToken()
		}
		// Skip ONLY
		if p.peekTokenIs(token.ONLY) {
			p.nextToken()
		}
	}

	// Parse FOR XML / FOR JSON (but not FOR SYSTEM_TIME which is handled in table parsing)
	// Also don't consume FOR UPDATE (used in cursor declarations)
	if p.peekTokenIs(token.FOR) {
		// Look ahead - need to check if next-next is XML or JSON
		if p.peekPeekTokenIs(token.XML) || p.peekPeekTokenIs(token.JSON) {
			p.nextToken() // move to FOR
			// curToken is now FOR, parseForClause expects this
			stmt.ForClause = p.parseForClause()
		}
		// If it's FOR UPDATE, leave it for the cursor parser
	}

	// Parse OPTION clause
	if p.peekTokenIs(token.OPTION) {
		p.nextToken() // consume OPTION
		stmt.Options = p.parseOptionClause()
	}

	// Parse UNION, INTERSECT, EXCEPT
	if p.peekTokenIs(token.UNION) || p.peekTokenIs(token.INTERSECT) || p.peekTokenIs(token.EXCEPT) {
		p.nextToken()
		stmt.Union = p.parseUnionClause()
	}

	return stmt
}

// parseForClause parses FOR XML or FOR JSON clause
func (p *Parser) parseForClause() *ast.ForClause {
	clause := &ast.ForClause{Token: p.curToken}

	// Expect XML or JSON
	if p.peekTokenIs(token.XML) {
		p.nextToken()
	} else if p.peekTokenIs(token.JSON) {
		p.nextToken()
	} else {
		p.errors = append(p.errors, "expected XML or JSON after FOR")
		return nil
	}

	clause.ForType = p.curToken.Literal

	// Parse mode: RAW, AUTO, PATH, EXPLICIT
	if p.peekTokenIs(token.RAW) || p.peekTokenIs(token.AUTO) || p.peekTokenIs(token.PATH) || p.peekTokenIs(token.EXPLICIT) {
		p.nextToken()
		clause.Mode = p.curToken.Literal

		// Check for optional element name: RAW('name') or PATH('name')
		if p.peekTokenIs(token.LPAREN) {
			p.nextToken() // consume (
			p.nextToken() // move to string literal
			if p.curToken.Type == token.STRING {
				clause.ElementName = p.curToken.Literal
			}
			if !p.expectPeek(token.RPAREN) {
				return nil
			}
		}
	}

	// Parse options (comma-separated)
	for p.peekTokenIs(token.COMMA) {
		p.nextToken() // consume comma
		p.nextToken() // move to option

		switch p.curToken.Type {
		case token.ELEMENTS:
			clause.Elements = true
		case token.IDENT:
			// Handle TYPE as identifier since it conflicts with cursor option
			if strings.ToUpper(p.curToken.Literal) == "TYPE" {
				clause.Type = true
			}
		case token.TYPE_WARNING:
			// TYPE keyword (used by cursor options, also valid in FOR XML)
			clause.Type = true
		case token.ROOT:
			// ROOT('name')
			if p.peekTokenIs(token.LPAREN) {
				p.nextToken() // consume (
				p.nextToken() // move to string literal
				if p.curToken.Type == token.STRING {
					clause.Root = p.curToken.Literal
				}
				if !p.expectPeek(token.RPAREN) {
					return nil
				}
			}
		case token.WITHOUT_ARRAY_WRAPPER:
			clause.WithoutArrayWrapper = true
		case token.INCLUDE_NULL_VALUES:
			clause.IncludeNullValues = true
		}
	}

	return clause
}

// parseOptionClause parses OPTION (hint, hint, ...)
func (p *Parser) parseOptionClause() []*ast.QueryOption {
	var options []*ast.QueryOption

	// Expect (
	if !p.expectPeek(token.LPAREN) {
		return nil
	}
	p.nextToken()

	// Parse options
	for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
		opt := &ast.QueryOption{Name: strings.ToUpper(p.curToken.Literal)}

		// Check for USE HINT
		if p.curTokenIs(token.USE) && p.peekTokenIs(token.HINT) {
			p.nextToken() // consume HINT
			opt.Name = "USE HINT"
			if p.expectPeek(token.LPAREN) {
				opt.Hints = []string{}
				p.nextToken() // move to first hint
				for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
					// Expect string literal
					if p.curTokenIs(token.STRING) || p.curTokenIs(token.NSTRING) {
						opt.Hints = append(opt.Hints, p.curToken.Literal)
					}
					if p.peekTokenIs(token.COMMA) {
						p.nextToken() // consume comma
						p.nextToken() // move to next hint
					} else {
						break
					}
				}
				p.expectPeek(token.RPAREN) // consume inner closing paren
			}
			options = append(options, opt)
			// After USE HINT, check for comma to continue or break
			if p.peekTokenIs(token.COMMA) {
				p.nextToken() // consume comma
				p.nextToken() // move to next option
				continue
			}
			break // no comma means we're done with options
		}

		// Check for USE PLAN @variable or USE PLAN N'xml'
		if p.curTokenIs(token.USE) && p.peekToken.Type == token.IDENT && strings.ToUpper(p.peekToken.Literal) == "PLAN" {
			p.nextToken() // consume PLAN
			opt.Name = "USE PLAN"
			p.nextToken() // move to plan value (variable or string)
			if p.curTokenIs(token.VARIABLE) || p.curTokenIs(token.STRING) || p.curTokenIs(token.NSTRING) {
				opt.Value = p.parseExpression(LOWEST)
			}
			options = append(options, opt)
			if p.peekTokenIs(token.COMMA) {
				p.nextToken() // consume comma
				p.nextToken() // move to next option
				continue
			}
			break
		}

		// Check for OPTIMIZE FOR (@var = value, @var UNKNOWN) or OPTIMIZE FOR UNKNOWN
		if strings.ToUpper(p.curToken.Literal) == "OPTIMIZE" && p.peekTokenIs(token.FOR) {
			p.nextToken() // consume FOR
			opt.Name = "OPTIMIZE FOR"

			// Check for shorthand OPTIMIZE FOR UNKNOWN (without parentheses)
			if p.peekToken.Type == token.IDENT && strings.ToUpper(p.peekToken.Literal) == "UNKNOWN" {
				p.nextToken() // consume UNKNOWN
				opt.Name = "OPTIMIZE FOR UNKNOWN"
				options = append(options, opt)
				if p.peekTokenIs(token.COMMA) {
					p.nextToken() // consume comma
					p.nextToken() // move to next option
					continue
				}
				break
			}

			if p.expectPeek(token.LPAREN) {
				opt.OptimizeFor = []*ast.OptimizeForHint{}
				p.nextToken() // move to first variable
				for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
					hint := &ast.OptimizeForHint{}
					if p.curTokenIs(token.VARIABLE) {
						hint.Variable = p.curToken.Literal
					}
					// Check for = value or UNKNOWN
					if p.peekTokenIs(token.EQ) {
						p.nextToken() // consume =
						p.nextToken() // move to value
						hint.Value = p.parseExpression(LOWEST)
					} else if p.peekToken.Type == token.IDENT && strings.ToUpper(p.peekToken.Literal) == "UNKNOWN" {
						p.nextToken() // consume UNKNOWN (as IDENT)
						hint.Unknown = true
					}
					opt.OptimizeFor = append(opt.OptimizeFor, hint)
					if p.peekTokenIs(token.COMMA) {
						p.nextToken() // consume comma
						p.nextToken() // move to next variable
					} else {
						break
					}
				}
				p.expectPeek(token.RPAREN) // consume inner closing paren
			}
			options = append(options, opt)
			if p.peekTokenIs(token.COMMA) {
				p.nextToken() // consume comma
				p.nextToken() // move to next option
				continue
			}
			break
		}

		// Check for multi-word hints like HASH JOIN, MERGE JOIN, LOOP JOIN, FORCE ORDER, KEEP PLAN
		switch {
		case p.peekTokenIs(token.JOIN):
			p.nextToken()
			opt.Name += " " + strings.ToUpper(p.curToken.Literal)
		case p.peekTokenIs(token.UNION):
			p.nextToken()
			opt.Name += " " + strings.ToUpper(p.curToken.Literal)
		case p.peekTokenIs(token.ORDER):
			p.nextToken()
			opt.Name += " " + strings.ToUpper(p.curToken.Literal)
		case p.peekTokenIs(token.GROUP):
			p.nextToken()
			opt.Name += " " + strings.ToUpper(p.curToken.Literal)
		case p.peekToken.Type == token.IDENT && strings.ToUpper(p.peekToken.Literal) == "PLAN":
			// KEEP PLAN, KEEPFIXED PLAN
			p.nextToken()
			opt.Name += " " + strings.ToUpper(p.curToken.Literal)
		case p.peekToken.Type == token.IDENT && strings.ToUpper(p.peekToken.Literal) == "VIEWS":
			// EXPAND VIEWS
			p.nextToken()
			opt.Name += " " + strings.ToUpper(p.curToken.Literal)
		case p.peekToken.Type == token.IDENT && strings.ToUpper(p.peekToken.Literal) == "UNKNOWN":
			// OPTIMIZE FOR UNKNOWN (without variable binding)
			p.nextToken()
			opt.Name += " " + strings.ToUpper(p.curToken.Literal)
		}

		// Check for value (e.g., MAXDOP 4, QUERYTRACEON 1234)
		if p.peekToken.Type == token.INT {
			p.nextToken()
			opt.Value = p.parseExpression(LOWEST)
		}

		// Check for = value (e.g., MAX_GRANT_PERCENT = 25)
		if p.peekTokenIs(token.EQ) {
			p.nextToken() // consume =
			p.nextToken() // move to value
			opt.Value = p.parseExpression(LOWEST)
		}

		options = append(options, opt)

		if p.peekTokenIs(token.COMMA) {
			p.nextToken() // consume comma
			p.nextToken() // move to next option
		} else {
			break
		}
	}

	// Expect outer )
	if p.curTokenIs(token.RPAREN) {
		// Already on a RPAREN, check if peek is also RPAREN (nested case)
		if p.peekTokenIs(token.RPAREN) {
			p.nextToken() // move to outer RPAREN
		}
	} else {
		p.expectPeek(token.RPAREN)
	}

	return options
}

func (p *Parser) parseUnionClause() *ast.UnionClause {
	clause := &ast.UnionClause{}
	clause.Type = p.curToken.Literal

	// Check for ALL
	if p.peekTokenIs(token.ALL) {
		p.nextToken()
		clause.All = true
	}

	// Parse the right side SELECT
	if !p.expectPeek(token.SELECT) {
		return nil
	}
	clause.Right = p.parseSelectStatement()

	return clause
}

func (p *Parser) parseTopClause() *ast.TopClause {
	top := &ast.TopClause{}
	p.nextToken()

	// Handle parenthesized expression
	if p.curTokenIs(token.LPAREN) {
		p.nextToken()
		top.Count = p.parseExpression(LOWEST)
		p.expectPeek(token.RPAREN)
	} else {
		// For non-parenthesized TOP, only accept literals and variables
		// to avoid consuming * as multiplication
		switch p.curToken.Type {
		case token.INT:
			top.Count = p.parseIntegerLiteral()
		case token.VARIABLE:
			top.Count = p.parseVariable()
		default:
			top.Count = p.parseExpression(CALL) // High precedence to avoid operators
		}
	}

	// Check for PERCENT
	if p.peekTokenIs(token.PERCENT_KW) {
		top.Percent = true
		p.nextToken()
	}

	// Check for WITH TIES
	if p.peekTokenIs(token.WITH) {
		p.nextToken()
		if p.expectPeek(token.TIES) {
			top.WithTies = true
		}
	}

	return top
}

func (p *Parser) parseSelectColumns() []ast.SelectColumn {
	columns := []ast.SelectColumn{}

	col := p.parseSelectColumn()
	columns = append(columns, col)

	for p.peekTokenIs(token.COMMA) {
		p.nextToken()
		p.nextToken()
		col = p.parseSelectColumn()
		columns = append(columns, col)
	}

	return columns
}

func (p *Parser) parseSelectColumn() ast.SelectColumn {
	col := ast.SelectColumn{}

	if p.curTokenIs(token.ASTERISK) {
		col.AllColumns = true
		return col
	}

	// Check for variable assignment: @var = expression
	if p.curTokenIs(token.VARIABLE) && p.peekTokenIs(token.EQ) {
		col.Variable = &ast.Variable{Token: p.curToken, Name: p.curToken.Literal}
		p.nextToken() // skip variable
		p.nextToken() // skip =
		col.Expression = p.parseExpression(LOWEST)
		return col
	}

	col.Expression = p.parseExpression(LOWEST)

	// Check for alias
	if p.peekTokenIs(token.AS) {
		p.nextToken()
		p.nextToken()
		col.Alias = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
	} else if p.peekTokenIs(token.IDENT) {
		p.nextToken()
		col.Alias = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
	}

	return col
}

func (p *Parser) parseFromClause() *ast.FromClause {
	from := &ast.FromClause{Token: p.curToken}
	p.nextToken()

	table := p.parseTableReference()
	from.Tables = []ast.TableReference{table}

	// Parse joins
	for p.isJoinKeyword() {
		from.Tables[0] = p.parseJoinClause(from.Tables[0])
	}

	// Parse additional tables (comma-separated)
	for p.peekTokenIs(token.COMMA) {
		p.nextToken()
		p.nextToken()
		table = p.parseTableReference()
		from.Tables = append(from.Tables, table)
	}

	return from
}

func (p *Parser) isJoinKeyword() bool {
	return p.peekTokenIs(token.JOIN) ||
		p.peekTokenIs(token.INNER) ||
		p.peekTokenIs(token.LEFT) ||
		p.peekTokenIs(token.RIGHT) ||
		p.peekTokenIs(token.FULL) ||
		p.peekTokenIs(token.CROSS) ||
		p.peekTokenIs(token.OUTER) ||
		p.peekTokenIs(token.APPLY)
}

// canPeekBeAlias returns true if the peek token can be used as a table/column alias.
// This includes IDENT plus many keywords that T-SQL allows as identifiers.
func (p *Parser) canPeekBeAlias() bool {
	if p.peekTokenIs(token.IDENT) {
		return true
	}
	// Keywords commonly used as aliases in T-SQL
	switch p.peekToken.Type {
	case token.TARGET, token.SOURCE, token.VALUE, token.KEY,
		token.LEVEL, token.PATH, token.ROLE, token.USER, token.LOGIN, token.PASSWORD,
		token.DATE, token.TIME, token.ZONE,
		token.FIRST, token.LAST, token.NEXT, token.PRIOR, token.ABSOLUTE, token.RELATIVE,
		token.OUTPUT, token.ROWS, token.RANGE,
		token.HASH, token.MERGE, token.LOOP, token.REMOTE,
		token.MEMBER, token.TYPE_WARNING, token.ACTION, token.RESULT:
		return true
	}
	return false
}

// isLegacyTableHint checks if peek is LPAREN followed by a known table hint keyword
// This helps distinguish legacy hint syntax FROM table (NOLOCK) from function calls
func (p *Parser) isLegacyTableHint() bool {
	if !p.peekTokenIs(token.LPAREN) {
		return false
	}
	// Look at what follows the LPAREN
	switch p.peekPeekToken.Type {
	case token.NOLOCK, token.HOLDLOCK, token.UPDLOCK, token.ROWLOCK, token.TABLOCK, token.TABLOCKX,
		token.READUNCOMMITTED, token.NOWAIT, token.INDEX:
		return true
	}
	return false
}

func (p *Parser) parseTableReference() ast.TableReference {
	var tableRef ast.TableReference

	// Check for subquery (derived table) or VALUES
	if p.curTokenIs(token.LPAREN) {
		startToken := p.curToken
		p.nextToken()
		if p.curTokenIs(token.SELECT) {
			subq := p.parseSelectStatement()
			p.expectPeek(token.RPAREN)

			derived := &ast.DerivedTable{
				Token:    startToken,
				Subquery: subq,
			}

			// Parse alias (required for derived tables, but we'll be lenient)
			if p.peekTokenIs(token.AS) {
				p.nextToken()
				p.nextToken()
				derived.Alias = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
				// Parse column aliases: AS T(c1, c2)
				if p.peekTokenIs(token.LPAREN) {
					p.nextToken() // consume (
					derived.ColumnAliases = p.parseColumnNameList()
				}
			} else if p.canPeekBeAlias() && !p.isJoinKeyword() && !p.peekTokenIs(token.WHERE) &&
				!p.peekTokenIs(token.ORDER) && !p.peekTokenIs(token.GROUP) && !p.peekTokenIs(token.PIVOT) && !p.peekTokenIs(token.UNPIVOT) {
				p.nextToken()
				derived.Alias = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
				// Parse column aliases: AS T(c1, c2)
				if p.peekTokenIs(token.LPAREN) {
					p.nextToken() // consume (
					derived.ColumnAliases = p.parseColumnNameList()
				}
			}

			tableRef = derived
		} else if p.curTokenIs(token.VALUES) {
			// VALUES table constructor: (VALUES (row1), (row2), ...) AS alias(columns)
			valuesTable := &ast.ValuesTable{Token: startToken}
			valuesTable.Rows = p.parseValuesRows()
			p.expectPeek(token.RPAREN)

			// Parse alias (required) and column names
			if p.peekTokenIs(token.AS) {
				p.nextToken()
				p.nextToken()
				valuesTable.Alias = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
				// Parse column names if present
				if p.peekTokenIs(token.LPAREN) {
					p.nextToken() // consume (
					valuesTable.Columns = p.parseColumnNameList()
				}
			} else if p.canPeekBeAlias() && !p.isJoinKeyword() {
				p.nextToken()
				valuesTable.Alias = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
				if p.peekTokenIs(token.LPAREN) {
					p.nextToken()
					valuesTable.Columns = p.parseColumnNameList()
				}
			}

			tableRef = valuesTable
		} else if p.curTokenIs(token.DELETE) {
			// Composable DML: FROM (DELETE ... OUTPUT ...) AS alias
			dmlDerived := &ast.DmlDerivedTable{Token: startToken}
			dmlDerived.Statement = p.parseDeleteStatement()
			p.expectPeek(token.RPAREN)

			// Parse alias (required for derived tables)
			if p.peekTokenIs(token.AS) {
				p.nextToken()
				p.nextToken()
				dmlDerived.Alias = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
				if p.peekTokenIs(token.LPAREN) {
					p.nextToken()
					dmlDerived.ColumnAliases = p.parseColumnNameList()
				}
			} else if p.canPeekBeAlias() && !p.isJoinKeyword() {
				p.nextToken()
				dmlDerived.Alias = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
				if p.peekTokenIs(token.LPAREN) {
					p.nextToken()
					dmlDerived.ColumnAliases = p.parseColumnNameList()
				}
			}

			tableRef = dmlDerived
		} else if p.curTokenIs(token.UPDATE) {
			// Composable DML: FROM (UPDATE ... OUTPUT ...) AS alias
			dmlDerived := &ast.DmlDerivedTable{Token: startToken}
			dmlDerived.Statement = p.parseUpdateStatement()
			p.expectPeek(token.RPAREN)

			if p.peekTokenIs(token.AS) {
				p.nextToken()
				p.nextToken()
				dmlDerived.Alias = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
				if p.peekTokenIs(token.LPAREN) {
					p.nextToken()
					dmlDerived.ColumnAliases = p.parseColumnNameList()
				}
			} else if p.canPeekBeAlias() && !p.isJoinKeyword() {
				p.nextToken()
				dmlDerived.Alias = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
				if p.peekTokenIs(token.LPAREN) {
					p.nextToken()
					dmlDerived.ColumnAliases = p.parseColumnNameList()
				}
			}

			tableRef = dmlDerived
		} else if p.curTokenIs(token.MERGE) {
			// Composable DML: FROM (MERGE ... OUTPUT ...) AS alias
			dmlDerived := &ast.DmlDerivedTable{Token: startToken}
			dmlDerived.Statement = p.parseMergeStatement()
			p.expectPeek(token.RPAREN)

			if p.peekTokenIs(token.AS) {
				p.nextToken()
				p.nextToken()
				dmlDerived.Alias = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
				if p.peekTokenIs(token.LPAREN) {
					p.nextToken()
					dmlDerived.ColumnAliases = p.parseColumnNameList()
				}
			} else if p.canPeekBeAlias() && !p.isJoinKeyword() {
				p.nextToken()
				dmlDerived.Alias = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
				if p.peekTokenIs(token.LPAREN) {
					p.nextToken()
					dmlDerived.ColumnAliases = p.parseColumnNameList()
				}
			}

			tableRef = dmlDerived
		} else {
			// Parenthesized join group: (table1 JOIN table2 ON ...)
			// Parse the inner table reference with its joins
			innerTable := p.parseTableReference()

			// Parse any joins within the parentheses
			for p.isJoinKeyword() {
				innerTable = p.parseJoinClause(innerTable)
			}

			if !p.expectPeek(token.RPAREN) {
				return nil
			}

			// Wrap in a parenthesized table reference
			tableRef = &ast.ParenthesizedTableRef{
				Token: startToken,
				Inner: innerTable,
			}
		}
	}

	if tableRef == nil {
		startToken := p.curToken
		name := p.parseQualifiedIdentifier()

		// Check for table-valued function (name followed by parentheses with arguments)
		// But NOT if it's legacy hint syntax (NOLOCK) etc.
		if p.peekTokenIs(token.LPAREN) && !p.isLegacyTableHint() {
			p.nextToken() // consume (
			tvf := &ast.TableValuedFunction{
				Token:    startToken,
				Function: name,
			}

			// Check function name for special handling
			funcName := ""
			if len(name.Parts) > 0 {
				funcName = strings.ToUpper(name.Parts[len(name.Parts)-1].Value)
			}

			// Special handling for OPENROWSET BULK syntax
			if funcName == "OPENROWSET" && p.peekTokenIs(token.BULK) {
				p.nextToken() // consume BULK
				// Create a special argument to represent BULK mode
				bulkIdent := &ast.Identifier{Token: p.curToken, Value: "BULK"}
				tvf.Arguments = append(tvf.Arguments, bulkIdent)

				// Parse file path
				if p.peekTokenIs(token.STRING) || p.peekTokenIs(token.NSTRING) {
					p.nextToken()
					tvf.Arguments = append(tvf.Arguments, &ast.StringLiteral{Token: p.curToken, Value: p.curToken.Literal})
				}

				// Parse options (comma-separated): FORMATFILE = 'x', FIRSTROW = 2, SINGLE_CLOB, etc.
				for p.peekTokenIs(token.COMMA) {
					p.nextToken() // consume comma
					p.nextToken() // move to option

					// Check for keyword options (SINGLE_CLOB, SINGLE_BLOB, SINGLE_NCLOB) or assignment options
					optToken := p.curToken
					optName := strings.ToUpper(optToken.Literal)

					if p.peekTokenIs(token.EQ) {
						// Assignment option: FORMATFILE = 'path', FIRSTROW = 2
						p.nextToken() // consume =
						p.nextToken() // move to value
						// Create key-value pair as identifier = expression
						keyIdent := &ast.Identifier{Token: optToken, Value: optName}
						value := p.parseExpression(LOWEST)
						// Store as a special expression or just append both
						tvf.Arguments = append(tvf.Arguments, keyIdent)
						tvf.Arguments = append(tvf.Arguments, value)
					} else {
						// Standalone keyword option like SINGLE_CLOB
						tvf.Arguments = append(tvf.Arguments, &ast.Identifier{Token: optToken, Value: optName})
					}
				}
				p.expectPeek(token.RPAREN)
			} else {
				// Normal argument parsing
				if !p.peekTokenIs(token.RPAREN) {
					p.nextToken()
					tvf.Arguments = append(tvf.Arguments, p.parseExpression(LOWEST))
					for p.peekTokenIs(token.COMMA) {
						p.nextToken()
						p.nextToken()
						tvf.Arguments = append(tvf.Arguments, p.parseExpression(LOWEST))
					}
				}
				p.expectPeek(token.RPAREN)
			}

			// Check for OPENJSON/OPENXML WITH schema clause
			isOpenJsonOrXml := funcName == "OPENJSON" || funcName == "OPENXML"
			if isOpenJsonOrXml && p.peekTokenIs(token.WITH) {
				p.nextToken() // consume WITH
				if p.expectPeek(token.LPAREN) {
					tvf.OpenJsonColumns = p.parseOpenJsonColumns()
				}
			}

			// Parse alias
			if p.peekTokenIs(token.AS) {
				p.nextToken()
				p.nextToken()
				tvf.Alias = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
				// Parse column aliases: AS T(c1, c2)
				if p.peekTokenIs(token.LPAREN) {
					p.nextToken() // consume (
					tvf.ColumnAliases = p.parseColumnNameList()
				}
			} else if p.canPeekBeAlias() && !p.isJoinKeyword() && !p.peekTokenIs(token.WHERE) &&
				!p.peekTokenIs(token.ORDER) && !p.peekTokenIs(token.GROUP) && !p.peekTokenIs(token.PIVOT) && !p.peekTokenIs(token.UNPIVOT) {
				p.nextToken()
				tvf.Alias = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
				// Parse column aliases: AS T(c1, c2)
				if p.peekTokenIs(token.LPAREN) {
					p.nextToken() // consume (
					tvf.ColumnAliases = p.parseColumnNameList()
				}
			}

			tableRef = tvf
		} else {
			table := &ast.TableName{Token: startToken}
			table.Name = name

			// Parse TABLESAMPLE clause
			if p.peekTokenIs(token.TABLESAMPLE) {
				p.nextToken() // consume TABLESAMPLE
				table.TableSample = p.parseTableSample()
			}

			// Parse table hints (WITH keyword or legacy syntax with just parentheses)
			// But NOT if this is WITH CHECK OPTION (view syntax)
			if p.peekTokenIs(token.WITH) && !p.peekPeekTokenIs(token.CHECK) {
				p.nextToken()
				if p.expectPeek(token.LPAREN) {
					table.Hints = p.parseTableHints()
				}
			} else if p.peekTokenIs(token.LPAREN) {
				// Check for legacy hint syntax: FROM table (NOLOCK)
				// We need to distinguish from function calls or subqueries
				// Legacy hints are typically single keywords like NOLOCK, HOLDLOCK, etc.
				if p.isLegacyTableHint() {
					p.nextToken() // consume (
					table.Hints = p.parseTableHints()
				}
			}

			// Check for FOR SYSTEM_TIME (temporal query)
			// Use two-token look-ahead to avoid consuming FOR if it's FOR XML/JSON
			if p.peekTokenIs(token.FOR) && p.peekPeekTokenIs(token.SYSTEM_TIME) {
				p.nextToken() // consume FOR
				p.nextToken() // consume SYSTEM_TIME
				table.TemporalClause = p.parseTemporalClause()
			}

			// Parse alias (but not if PIVOT/UNPIVOT follows)
			if p.peekTokenIs(token.AS) {
				p.nextToken()
				p.nextToken()
				table.Alias = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
			} else if p.canPeekBeAlias() && !p.isJoinKeyword() && !p.peekTokenIs(token.WHERE) &&
				!p.peekTokenIs(token.ORDER) && !p.peekTokenIs(token.GROUP) && !p.peekTokenIs(token.PIVOT) && !p.peekTokenIs(token.UNPIVOT) {
				p.nextToken()
				table.Alias = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
			}

			// Parse table hints after alias: FROM table alias WITH (hints)
			// But NOT if this is WITH CHECK OPTION (view syntax)
			if p.peekTokenIs(token.WITH) && !p.peekPeekTokenIs(token.CHECK) {
				p.nextToken() // consume WITH
				if p.expectPeek(token.LPAREN) {
					table.Hints = p.parseTableHints()
				}
			} else if p.peekTokenIs(token.LPAREN) {
				// Check for legacy hint syntax after alias: FROM table alias (NOLOCK)
				// We need to distinguish from other uses of parentheses
				if p.isLegacyTableHint() {
					p.nextToken() // consume (
					table.Hints = p.parseTableHints()
				}
			}

			tableRef = table
		}
	}

	// Check for PIVOT or UNPIVOT
	if p.peekTokenIs(token.PIVOT) {
		p.nextToken()
		tableRef = p.parsePivotTable(tableRef)
	} else if p.peekTokenIs(token.UNPIVOT) {
		p.nextToken()
		tableRef = p.parseUnpivotTable(tableRef)
	}

	return tableRef
}

// parsePivotTable parses PIVOT (aggregate(col) FOR pivot_col IN (values)) AS alias
func (p *Parser) parsePivotTable(source ast.TableReference) *ast.PivotTable {
	pivot := &ast.PivotTable{
		Token:  p.curToken,
		Source: source,
	}

	// Expect (
	if !p.expectPeek(token.LPAREN) {
		return nil
	}
	p.nextToken()

	// Parse aggregate function name (SUM, COUNT, AVG, etc.)
	pivot.AggregateFunc = strings.ToUpper(p.curToken.Literal)

	// Expect ( for aggregate arguments
	if !p.expectPeek(token.LPAREN) {
		return nil
	}
	p.nextToken()

	// Parse value column
	pivot.ValueColumn = p.parseExpression(LOWEST)

	// Expect )
	if !p.expectPeek(token.RPAREN) {
		return nil
	}

	// Expect FOR
	if !p.expectPeek(token.FOR) {
		return nil
	}
	p.nextToken()

	// Parse pivot column
	pivot.PivotColumn = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}

	// Expect IN
	if !p.expectPeek(token.IN) {
		return nil
	}

	// Expect (
	if !p.expectPeek(token.LPAREN) {
		return nil
	}
	p.nextToken()

	// Parse pivot values (bracketed identifiers)
	pivot.PivotValues = p.parsePivotValueList()

	// Expect )
	if !p.expectPeek(token.RPAREN) {
		return nil
	}

	// Expect ) to close PIVOT
	if !p.expectPeek(token.RPAREN) {
		return nil
	}

	// Parse alias (required for PIVOT)
	if p.peekTokenIs(token.AS) {
		p.nextToken()
		p.nextToken()
		pivot.Alias = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
	} else if p.peekTokenIs(token.IDENT) {
		p.nextToken()
		pivot.Alias = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
	}

	return pivot
}

// parseUnpivotTable parses UNPIVOT (value_col FOR pivot_col IN (columns)) AS alias
func (p *Parser) parseUnpivotTable(source ast.TableReference) *ast.UnpivotTable {
	unpivot := &ast.UnpivotTable{
		Token:  p.curToken,
		Source: source,
	}

	// Expect (
	if !p.expectPeek(token.LPAREN) {
		return nil
	}
	p.nextToken()

	// Parse value column (new column to hold values)
	unpivot.ValueColumn = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}

	// Expect FOR
	if !p.expectPeek(token.FOR) {
		return nil
	}
	p.nextToken()

	// Parse pivot column (new column to hold original column names)
	unpivot.PivotColumn = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}

	// Expect IN
	if !p.expectPeek(token.IN) {
		return nil
	}

	// Expect (
	if !p.expectPeek(token.LPAREN) {
		return nil
	}
	p.nextToken()

	// Parse source columns (bracketed identifiers)
	unpivot.SourceColumns = p.parsePivotValueList()

	// Expect )
	if !p.expectPeek(token.RPAREN) {
		return nil
	}

	// Expect ) to close UNPIVOT
	if !p.expectPeek(token.RPAREN) {
		return nil
	}

	// Parse alias (required for UNPIVOT)
	if p.peekTokenIs(token.AS) {
		p.nextToken()
		p.nextToken()
		unpivot.Alias = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
	} else if p.peekTokenIs(token.IDENT) {
		p.nextToken()
		unpivot.Alias = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
	}

	return unpivot
}

// parsePivotValueList parses a list of bracketed identifiers: [v1], [v2], ...
func (p *Parser) parsePivotValueList() []*ast.Identifier {
	var values []*ast.Identifier

	// Parse first value
	if p.curTokenIs(token.LBRACKET) {
		p.nextToken() // move to identifier
		values = append(values, &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal})
		p.expectPeek(token.RBRACKET)
	} else {
		// Handle unbracketed identifiers
		values = append(values, &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal})
	}

	// Parse remaining values
	for p.peekTokenIs(token.COMMA) {
		p.nextToken() // consume comma
		p.nextToken() // move to next value
		if p.curTokenIs(token.LBRACKET) {
			p.nextToken() // move to identifier
			values = append(values, &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal})
			p.expectPeek(token.RBRACKET)
		} else {
			values = append(values, &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal})
		}
	}

	return values
}

// parseTemporalClause parses FOR SYSTEM_TIME AS OF/BETWEEN/FROM/CONTAINED IN/ALL
func (p *Parser) parseTemporalClause() *ast.TemporalClause {
	clause := &ast.TemporalClause{Token: p.curToken}

	// Already consumed SYSTEM_TIME, now parse the type
	if p.peekTokenIs(token.AS) {
		p.nextToken() // consume AS
		if p.peekTokenIs(token.OF) {
			p.nextToken() // consume OF
			clause.Type = "AS OF"
			p.nextToken()
			clause.StartTime = p.parseExpression(LOWEST)
		}
	} else if p.peekTokenIs(token.BETWEEN) {
		p.nextToken() // consume BETWEEN
		clause.Type = "BETWEEN"
		p.nextToken()
		clause.StartTime = p.parseExpression(AND_PREC) // Use AND_PREC to stop before AND
		if p.peekTokenIs(token.AND) {
			p.nextToken() // consume AND
			p.nextToken()
			clause.EndTime = p.parseExpression(AND_PREC)
		}
	} else if p.peekTokenIs(token.FROM) {
		p.nextToken() // consume FROM
		clause.Type = "FROM"
		p.nextToken()
		clause.StartTime = p.parseExpression(LOWEST)
		if p.peekTokenIs(token.TO) {
			p.nextToken() // consume TO
			p.nextToken()
			clause.EndTime = p.parseExpression(LOWEST)
		}
	} else if p.peekTokenIs(token.CONTAINED) {
		p.nextToken() // consume CONTAINED
		if p.peekTokenIs(token.IN) {
			p.nextToken() // consume IN
		}
		clause.Type = "CONTAINED IN"
		if p.expectPeek(token.LPAREN) {
			p.nextToken()
			clause.StartTime = p.parseExpression(LOWEST)
			if p.peekTokenIs(token.COMMA) {
				p.nextToken() // consume comma
				p.nextToken()
				clause.EndTime = p.parseExpression(LOWEST)
			}
			p.expectPeek(token.RPAREN)
		}
	} else if p.peekTokenIs(token.ALL) {
		p.nextToken() // consume ALL
		clause.Type = "ALL"
	}

	return clause
}

// parseValuesRows parses (expr, ...), (expr, ...), ... for VALUES table constructor
func (p *Parser) parseValuesRows() [][]ast.Expression {
	var rows [][]ast.Expression

	for {
		if !p.expectPeek(token.LPAREN) {
			return nil
		}
		p.nextToken()

		var row []ast.Expression
		row = append(row, p.parseExpression(LOWEST))
		for p.peekTokenIs(token.COMMA) {
			p.nextToken()
			p.nextToken()
			row = append(row, p.parseExpression(LOWEST))
		}
		rows = append(rows, row)

		if !p.expectPeek(token.RPAREN) {
			return nil
		}

		// Check for more rows
		if !p.peekTokenIs(token.COMMA) {
			break
		}
		p.nextToken() // consume comma
	}

	return rows
}

// parseColumnNameList parses (col1, col2, ...) for VALUES alias column names
func (p *Parser) parseColumnNameList() []*ast.Identifier {
	var cols []*ast.Identifier
	p.nextToken()

	cols = append(cols, &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal})

	for p.peekTokenIs(token.COMMA) {
		p.nextToken()
		p.nextToken()
		cols = append(cols, &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal})
	}

	p.expectPeek(token.RPAREN)
	return cols
}

func (p *Parser) parseTableHints() []string {
	hints := []string{}
	p.nextToken()

	for {
		hint := strings.ToUpper(p.curToken.Literal)

		// Check for INDEX(name) or INDEX(name, name2) syntax
		if hint == "INDEX" && p.peekTokenIs(token.LPAREN) {
			p.nextToken() // consume (
			var indexNames []string
			p.nextToken() // move to first index name
			indexNames = append(indexNames, p.curToken.Literal)
			for p.peekTokenIs(token.COMMA) {
				p.nextToken() // consume comma
				p.nextToken() // move to next index name
				indexNames = append(indexNames, p.curToken.Literal)
			}
			p.expectPeek(token.RPAREN)
			hint = "INDEX(" + strings.Join(indexNames, ", ") + ")"
		} else if hint == "INDEX" && p.peekTokenIs(token.EQ) {
			// Legacy INDEX = n syntax
			p.nextToken() // consume =
			p.nextToken() // move to index number/name
			hint = "INDEX(" + p.curToken.Literal + ")"
		}

		// Check for FORCESEEK or FORCESCAN with optional (index(columns)) syntax
		if (hint == "FORCESEEK" || hint == "FORCESCAN") && p.peekTokenIs(token.LPAREN) {
			p.nextToken() // consume (
			p.nextToken() // move to index name
			indexName := p.curToken.Literal

			// Check for nested (columns) list
			if p.peekTokenIs(token.LPAREN) {
				p.nextToken() // consume (
				var columns []string
				p.nextToken() // move to first column
				columns = append(columns, p.curToken.Literal)
				for p.peekTokenIs(token.COMMA) {
					p.nextToken() // consume comma
					p.nextToken() // move to next column
					columns = append(columns, p.curToken.Literal)
				}
				p.expectPeek(token.RPAREN) // consume inner )
				hint = hint + "(" + indexName + "(" + strings.Join(columns, ", ") + "))"
			} else {
				hint = hint + "(" + indexName + ")"
			}
			p.expectPeek(token.RPAREN) // consume outer )
		}

		hints = append(hints, hint)

		if !p.peekTokenIs(token.COMMA) {
			break
		}
		p.nextToken() // consume comma
		p.nextToken() // move to next hint
	}

	p.expectPeek(token.RPAREN)
	return hints
}

// parseTableSample parses TABLESAMPLE [SYSTEM] (n PERCENT|ROWS) [REPEATABLE (seed)]
func (p *Parser) parseTableSample() *ast.TableSampleClause {
	ts := &ast.TableSampleClause{Token: p.curToken}

	// Check for optional SYSTEM keyword
	if p.peekTokenIs(token.IDENT) && strings.ToUpper(p.peekToken.Literal) == "SYSTEM" {
		p.nextToken()
		ts.System = true
	}

	// Expect (
	if !p.expectPeek(token.LPAREN) {
		return nil
	}
	p.nextToken()

	// Parse sample value
	ts.Value = p.parseExpression(LOWEST)

	// Check for PERCENT or ROWS
	if p.peekTokenIs(token.PERCENT_KW) {
		p.nextToken()
		ts.IsPercent = true
	} else if p.peekTokenIs(token.ROWS) {
		p.nextToken()
		ts.IsRows = true
	}

	// Expect )
	if !p.expectPeek(token.RPAREN) {
		return nil
	}

	// Check for REPEATABLE (seed)
	if p.peekTokenIs(token.IDENT) && strings.ToUpper(p.peekToken.Literal) == "REPEATABLE" {
		p.nextToken() // consume REPEATABLE
		if p.expectPeek(token.LPAREN) {
			p.nextToken()
			ts.Seed = p.parseExpression(LOWEST)
			p.expectPeek(token.RPAREN)
		}
	}

	return ts
}

// parseOpenJsonColumns parses the column definitions in OPENJSON/OPENXML WITH clause
// OPENJSON syntax: col_name datatype ['$.path'] [AS JSON], ...
// OPENXML syntax: col_name datatype ['@attr' or 'element'], ...
func (p *Parser) parseOpenJsonColumns() []*ast.OpenJsonColumn {
	var columns []*ast.OpenJsonColumn

	p.nextToken() // move to first column name
	for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
		col := &ast.OpenJsonColumn{}

		// Column name
		col.Name = p.curToken.Literal
		p.nextToken()

		// Data type
		col.DataType = p.parseDataType()

		// Optional JSON path (string literal starting with $)
		if p.peekTokenIs(token.STRING) || p.peekTokenIs(token.NSTRING) {
			p.nextToken()
			col.Path = p.curToken.Literal
		}

		// Optional AS JSON
		if p.peekTokenIs(token.AS) {
			p.nextToken() // consume AS
			if p.peekTokenIs(token.JSON) {
				p.nextToken() // consume JSON
				col.AsJson = true
			}
		}

		columns = append(columns, col)

		if p.peekTokenIs(token.COMMA) {
			p.nextToken() // consume comma
			p.nextToken() // move to next column name
		} else {
			break
		}
	}

	p.expectPeek(token.RPAREN)
	return columns
}

func (p *Parser) parseJoinClause(left ast.TableReference) ast.TableReference {
	join := &ast.JoinClause{Left: left}
	p.nextToken()

	// Determine join type
	switch p.curToken.Type {
	case token.INNER:
		join.Type = "INNER"
		p.nextToken()
		// Check for join hint (HASH, MERGE, LOOP, REMOTE)
		join.Hint = p.parseJoinHint()
	case token.LEFT:
		join.Type = "LEFT"
		p.nextToken()
		if p.curTokenIs(token.OUTER) {
			p.nextToken()
		}
		// Check for join hint
		join.Hint = p.parseJoinHint()
	case token.RIGHT:
		join.Type = "RIGHT"
		p.nextToken()
		if p.curTokenIs(token.OUTER) {
			p.nextToken()
		}
		// Check for join hint
		join.Hint = p.parseJoinHint()
	case token.FULL:
		join.Type = "FULL"
		p.nextToken()
		if p.curTokenIs(token.OUTER) {
			p.nextToken()
		}
		// Check for join hint
		join.Hint = p.parseJoinHint()
	case token.CROSS:
		p.nextToken()
		if p.curTokenIs(token.APPLY) {
			join.Type = "CROSS APPLY"
			join.Token = p.curToken
			p.nextToken()
			join.Right = p.parseTableReference()
			return join
		}
		join.Type = "CROSS"
	case token.OUTER:
		p.nextToken()
		if p.curTokenIs(token.APPLY) {
			join.Type = "OUTER APPLY"
			join.Token = p.curToken
			p.nextToken()
			join.Right = p.parseTableReference()
			return join
		}
		// OUTER without APPLY - fallback to FULL OUTER
		join.Type = "FULL"
	case token.JOIN:
		join.Type = "INNER"
	}

	join.Token = p.curToken
	p.nextToken()
	join.Right = p.parseTableReference()

	// Parse ON condition (not for CROSS JOIN)
	if p.peekTokenIs(token.ON) {
		p.nextToken()
		p.nextToken()
		join.Condition = p.parseExpression(LOWEST)
	}

	return join
}

// parseJoinHint checks for and returns a join hint (HASH, MERGE, LOOP, REMOTE)
func (p *Parser) parseJoinHint() string {
	switch p.curToken.Type {
	case token.HASH:
		p.nextToken()
		return "HASH"
	case token.MERGE:
		p.nextToken()
		return "MERGE"
	case token.LOOP:
		p.nextToken()
		return "LOOP"
	case token.REMOTE:
		p.nextToken()
		return "REMOTE"
	}
	return ""
}

func (p *Parser) parseQualifiedIdentifier() *ast.QualifiedIdentifier {
	qi := &ast.QualifiedIdentifier{}
	qi.Parts = append(qi.Parts, &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal})

	for p.peekTokenIs(token.DOT) {
		p.nextToken()
		p.nextToken()
		qi.Parts = append(qi.Parts, &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal})
	}

	return qi
}

// parseGroupByItems parses GROUP BY items including GROUPING SETS, CUBE, and ROLLUP
func (p *Parser) parseGroupByItems() []ast.Expression {
	items := []ast.Expression{}

	item := p.parseGroupByItem()
	items = append(items, item)

	for p.peekTokenIs(token.COMMA) {
		p.nextToken()
		p.nextToken()
		item = p.parseGroupByItem()
		items = append(items, item)
	}

	return items
}

// parseGroupByItem parses a single GROUP BY item (column, GROUPING SETS, CUBE, or ROLLUP)
func (p *Parser) parseGroupByItem() ast.Expression {
	// Check for GROUPING SETS
	if p.curTokenIs(token.GROUPING) && p.peekTokenIs(token.SETS) {
		return p.parseGroupingSets()
	}

	// Check for CUBE
	if p.curTokenIs(token.CUBE) {
		return p.parseCube()
	}

	// Check for ROLLUP
	if p.curTokenIs(token.ROLLUP) {
		return p.parseRollup()
	}

	// Regular expression
	return p.parseExpression(LOWEST)
}

// parseGroupingSets parses GROUPING SETS ((col1, col2), (col1), ())
func (p *Parser) parseGroupingSets() ast.Expression {
	expr := &ast.GroupingSetsExpression{Token: p.curToken}
	p.nextToken() // consume GROUPING
	p.nextToken() // consume SETS

	if !p.curTokenIs(token.LPAREN) {
		return nil
	}
	p.nextToken() // consume (

	// Parse sets
	for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
		set := p.parseGroupingSet()
		expr.Sets = append(expr.Sets, set)

		if p.peekTokenIs(token.COMMA) {
			p.nextToken() // consume ,
			p.nextToken() // move to next set
		} else {
			break
		}
	}

	if p.peekTokenIs(token.RPAREN) {
		p.nextToken() // consume )
	}

	return expr
}

// parseGroupingSet parses a single set like (col1, col2) or ()
func (p *Parser) parseGroupingSet() ast.Expression {
	if p.curTokenIs(token.LPAREN) {
		// This is a tuple like (col1, col2) or ()
		tuple := &ast.TupleExpression{Token: p.curToken}
		p.nextToken() // consume (

		// Check for empty tuple ()
		if p.curTokenIs(token.RPAREN) {
			// Empty tuple
			return tuple
		}

		// Parse elements
		elem := p.parseExpression(LOWEST)
		tuple.Elements = append(tuple.Elements, elem)

		for p.peekTokenIs(token.COMMA) {
			p.nextToken() // consume ,
			p.nextToken() // move to next element
			elem = p.parseExpression(LOWEST)
			tuple.Elements = append(tuple.Elements, elem)
		}

		if p.peekTokenIs(token.RPAREN) {
			p.nextToken() // consume )
		}

		return tuple
	}

	// Single column without parentheses
	return p.parseExpression(LOWEST)
}

// parseCube parses CUBE(col1, col2)
func (p *Parser) parseCube() ast.Expression {
	expr := &ast.CubeExpression{Token: p.curToken}

	if !p.expectPeek(token.LPAREN) {
		return nil
	}
	p.nextToken() // move past (

	// Parse columns
	for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
		col := p.parseExpression(LOWEST)
		expr.Columns = append(expr.Columns, col)

		if p.peekTokenIs(token.COMMA) {
			p.nextToken() // consume ,
			p.nextToken() // move to next column
		} else {
			break
		}
	}

	if p.peekTokenIs(token.RPAREN) {
		p.nextToken() // consume )
	}

	return expr
}

// parseRollup parses ROLLUP(col1, col2)
func (p *Parser) parseRollup() ast.Expression {
	expr := &ast.RollupExpression{Token: p.curToken}

	if !p.expectPeek(token.LPAREN) {
		return nil
	}
	p.nextToken() // move past (

	// Parse columns
	for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
		col := p.parseExpression(LOWEST)
		expr.Columns = append(expr.Columns, col)

		if p.peekTokenIs(token.COMMA) {
			p.nextToken() // consume ,
			p.nextToken() // move to next column
		} else {
			break
		}
	}

	if p.peekTokenIs(token.RPAREN) {
		p.nextToken() // consume )
	}

	return expr
}

func (p *Parser) parseOrderByItems() []*ast.OrderByItem {
	items := []*ast.OrderByItem{}

	item := &ast.OrderByItem{Expression: p.parseExpression(LOWEST)}
	if p.peekTokenIs(token.ASC) {
		p.nextToken()
	} else if p.peekTokenIs(token.DESC) {
		p.nextToken()
		item.Descending = true
	}
	items = append(items, item)

	for p.peekTokenIs(token.COMMA) {
		p.nextToken()
		p.nextToken()
		item = &ast.OrderByItem{Expression: p.parseExpression(LOWEST)}
		if p.peekTokenIs(token.ASC) {
			p.nextToken()
		} else if p.peekTokenIs(token.DESC) {
			p.nextToken()
			item.Descending = true
		}
		items = append(items, item)
	}

	return items
}

// -----------------------------------------------------------------------------
// DML Statements
// -----------------------------------------------------------------------------

func (p *Parser) parseInsertStatement() ast.Statement {
	stmt := &ast.InsertStatement{Token: p.curToken}

	// TOP clause (INSERT TOP (n) INTO ...)
	if p.peekTokenIs(token.TOP) {
		p.nextToken() // consume TOP
		if p.peekTokenIs(token.LPAREN) {
			p.nextToken() // consume (
			p.nextToken() // move to expression
			stmt.Top = p.parseExpression(LOWEST)
			p.expectPeek(token.RPAREN)
		} else {
			p.nextToken()
			stmt.Top = p.parseExpression(LOWEST)
		}
		// Check for PERCENT
		if p.peekTokenIs(token.PERCENT_KW) {
			p.nextToken()
			stmt.TopPercent = true
		}
	}

	// INTO is optional in T-SQL
	if p.peekTokenIs(token.INTO) {
		p.nextToken()
	}
	p.nextToken()

	stmt.Table = p.parseQualifiedIdentifier()

	// Parse table hints WITH (KEEPIDENTITY), WITH (TABLOCK), etc.
	if p.peekTokenIs(token.WITH) {
		p.nextToken() // consume WITH
		if p.expectPeek(token.LPAREN) {
			stmt.Hints = p.parseTableHints()
		}
	}

	// Parse column list
	if p.peekTokenIs(token.LPAREN) {
		p.nextToken()
		stmt.Columns = p.parseIdentifierList()
	}

	// Parse OUTPUT clause
	if p.peekTokenIs(token.OUTPUT) {
		p.nextToken()
		stmt.Output = p.parseOutputClause()
	}

	// Parse VALUES or SELECT or DEFAULT VALUES
	if p.peekTokenIs(token.DEFAULT_KW) {
		p.nextToken() // consume DEFAULT
		if p.peekTokenIs(token.VALUES) {
			p.nextToken() // consume VALUES
			stmt.DefaultValues = true
		}
	} else if p.peekTokenIs(token.VALUES) {
		p.nextToken()
		stmt.Values = p.parseValuesList()
	} else if p.peekTokenIs(token.SELECT) {
		p.nextToken()
		stmt.Select = p.parseSelectStatement()
	}

	return stmt
}

func (p *Parser) parseOutputClause() *ast.OutputClause {
	output := &ast.OutputClause{}
	p.nextToken()

	// Parse column list (inserted.*, deleted.col, etc.)
	output.Columns = p.parseOutputColumns()

	// Parse INTO
	if p.peekTokenIs(token.INTO) {
		p.nextToken()
		p.nextToken()
		if p.curTokenIs(token.VARIABLE) {
			output.IntoVariable = &ast.Variable{Token: p.curToken, Name: p.curToken.Literal}
		} else {
			output.Into = p.parseQualifiedIdentifier()
		}
		// Check for column list in parentheses: INTO @table(col1, col2)
		if p.peekTokenIs(token.LPAREN) {
			p.nextToken() // consume (
			output.IntoColumns = p.parseIdentifierList()
		}
	}

	return output
}

func (p *Parser) parseOutputColumns() []ast.SelectColumn {
	columns := []ast.SelectColumn{}

	col := p.parseOutputColumn()
	columns = append(columns, col)

	for p.peekTokenIs(token.COMMA) {
		p.nextToken()
		p.nextToken()
		col = p.parseOutputColumn()
		columns = append(columns, col)
	}

	return columns
}

func (p *Parser) parseOutputColumn() ast.SelectColumn {
	col := ast.SelectColumn{}

	// Handle inserted.*, deleted.*, or column expressions
	col.Expression = p.parseExpression(LOWEST)

	// Check for alias
	if p.peekTokenIs(token.AS) {
		p.nextToken()
		p.nextToken()
		col.Alias = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
	} else if p.peekTokenIs(token.IDENT) && !p.peekTokenIs(token.INTO) && !p.peekTokenIs(token.VALUES) &&
		!p.peekTokenIs(token.FROM) && !p.peekTokenIs(token.WHERE) {
		p.nextToken()
		col.Alias = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
	}

	return col
}

func (p *Parser) parseIdentifierList() []*ast.Identifier {
	list := []*ast.Identifier{}
	p.nextToken()

	list = append(list, &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal})

	for p.peekTokenIs(token.COMMA) {
		p.nextToken()
		p.nextToken()
		list = append(list, &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal})
	}

	p.expectPeek(token.RPAREN)
	return list
}

func (p *Parser) parseValuesList() [][]ast.Expression {
	values := [][]ast.Expression{}

	if !p.expectPeek(token.LPAREN) {
		return nil
	}

	row := p.parseExpressionList(token.RPAREN)
	values = append(values, row)

	for p.peekTokenIs(token.COMMA) {
		p.nextToken()
		if !p.expectPeek(token.LPAREN) {
			return nil
		}
		row = p.parseExpressionList(token.RPAREN)
		values = append(values, row)
	}

	return values
}

func (p *Parser) parseUpdateStatement() ast.Statement {
	stmt := &ast.UpdateStatement{Token: p.curToken}
	p.nextToken()

	// Parse optional TOP clause
	if p.curTokenIs(token.TOP) {
		stmt.Top = p.parseTopClause()
		p.nextToken()
	}

	// Check if target is a function call (OPENQUERY, OPENROWSET, etc.)
	if p.curTokenIs(token.IDENT) && p.peekTokenIs(token.LPAREN) {
		funcToken := p.curToken
		funcName := p.curToken.Literal
		p.nextToken() // move to (
		// parseExpressionList expects to be positioned at ( and will call nextToken internally
		args := p.parseExpressionList(token.RPAREN)
		stmt.TargetFunc = &ast.FunctionCall{
			Token:     funcToken,
			Function:  &ast.Identifier{Token: funcToken, Value: funcName},
			Arguments: args,
		}
	} else {
		stmt.Table = p.parseQualifiedIdentifier()
	}

	// Parse table hints WITH (NOLOCK), WITH (TABLOCK), etc.
	if p.peekTokenIs(token.WITH) {
		p.nextToken() // consume WITH
		if p.expectPeek(token.LPAREN) {
			stmt.Hints = p.parseTableHints()
		}
	}

	// Parse alias
	if p.peekTokenIs(token.AS) {
		p.nextToken()
		p.nextToken()
		stmt.Alias = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
	}

	if !p.expectPeek(token.SET) {
		return nil
	}

	stmt.SetClauses = p.parseSetClauses()

	// Parse OUTPUT
	if p.peekTokenIs(token.OUTPUT) {
		p.nextToken()
		stmt.Output = p.parseOutputClause()
	}

	// Parse FROM
	if p.peekTokenIs(token.FROM) {
		p.nextToken()
		stmt.From = p.parseFromClause()
	}

	// Parse WHERE or WHERE CURRENT OF
	if p.peekTokenIs(token.WHERE) {
		p.nextToken()
		p.nextToken()
		// Check for CURRENT OF cursor_name
		if p.curTokenIs(token.CURRENT) && p.peekTokenIs(token.OF) {
			p.nextToken() // consume OF
			p.nextToken() // move to cursor name
			stmt.CurrentOfCursor = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
		} else {
			stmt.Where = p.parseExpression(LOWEST)
		}
	}

	return stmt
}

func (p *Parser) parseSetClauses() []*ast.SetClause {
	clauses := []*ast.SetClause{}
	p.nextToken()

	clause := p.parseSetClause()
	if clause == nil {
		return nil
	}
	clauses = append(clauses, clause)

	for p.peekTokenIs(token.COMMA) {
		p.nextToken()
		p.nextToken()
		clause = p.parseSetClause()
		if clause == nil {
			return nil
		}
		clauses = append(clauses, clause)
	}

	return clauses
}

func (p *Parser) parseSetClause() *ast.SetClause {
	clause := &ast.SetClause{}

	// Parse the column (might be qualified like dbo.Table.Column)
	clause.Column = p.parseQualifiedIdentifier()

	// Check for XML method call: column.method(args)
	// In this case, parseQualifiedIdentifier consumed "ProductXml.modify"
	// and the next token is (
	if p.peekTokenIs(token.LPAREN) {
		// This is an XML method call like column.modify('...')
		// The column already contains the method name as the last part
		// We need to parse the arguments
		p.nextToken() // consume (
		p.nextToken() // move to first argument

		// Parse the method argument (usually a string)
		var args []ast.Expression
		if !p.curTokenIs(token.RPAREN) {
			args = append(args, p.parseExpression(LOWEST))
			for p.peekTokenIs(token.COMMA) {
				p.nextToken()
				p.nextToken()
				args = append(args, p.parseExpression(LOWEST))
			}
		}

		if !p.expectPeek(token.RPAREN) {
			return nil
		}

		clause.IsMethodCall = true
		clause.MethodArgs = args
		return clause
	}

	// Accept = or compound assignment operators
	clause.Operator = p.peekToken.Literal
	if p.peekTokenIs(token.EQ) ||
		p.peekTokenIs(token.PLUSEQ) || p.peekTokenIs(token.MINUSEQ) ||
		p.peekTokenIs(token.MULEQ) || p.peekTokenIs(token.DIVEQ) ||
		p.peekTokenIs(token.MODEQ) || p.peekTokenIs(token.ANDEQ) ||
		p.peekTokenIs(token.OREQ) || p.peekTokenIs(token.XOREQ) {
		p.nextToken()
	} else {
		p.peekError(token.EQ)
		return nil
	}
	p.nextToken()
	clause.Value = p.parseExpression(LOWEST)
	return clause
}

func (p *Parser) parseDeleteStatement() ast.Statement {
	stmt := &ast.DeleteStatement{Token: p.curToken}
	p.nextToken()

	// Parse optional TOP clause
	if p.curTokenIs(token.TOP) {
		stmt.Top = p.parseTopClause()
		p.nextToken()
	}

	// Check what follows DELETE:
	// DELETE FROM table - standard
	// DELETE FROM OPENQUERY(...) - function target
	// DELETE alias FROM table alias - delete with join
	// DELETE FROM alias FROM table alias - also valid
	// DELETE alias OUTPUT ... FROM table alias - with output

	hasFirstFrom := false
	if p.curTokenIs(token.FROM) {
		hasFirstFrom = true
		p.nextToken()
	}

	// Check if target is a function call (OPENQUERY, OPENROWSET, etc.)
	if p.curTokenIs(token.IDENT) && p.peekTokenIs(token.LPAREN) {
		funcToken := p.curToken
		funcName := p.curToken.Literal
		p.nextToken() // move to (
		args := p.parseExpressionList(token.RPAREN)
		stmt.TargetFunc = &ast.FunctionCall{
			Token:     funcToken,
			Function:  &ast.Identifier{Token: funcToken, Value: funcName},
			Arguments: args,
		}
		// Continue to parse WHERE, etc.
	} else {
		// Parse table name or alias
		firstIdent := p.parseQualifiedIdentifier()

		// Check for OUTPUT before determining if firstIdent is alias or table
		if p.peekTokenIs(token.OUTPUT) {
			// DELETE alias OUTPUT ... FROM table
			stmt.Alias = &ast.Identifier{Token: firstIdent.Parts[0].Token, Value: firstIdent.Parts[0].Value}
			p.nextToken()
			stmt.Output = p.parseOutputClause()
			// After OUTPUT, expect FROM
			if p.peekTokenIs(token.FROM) {
				p.nextToken()
				stmt.From = p.parseFromClause()
			}
		} else if p.peekTokenIs(token.FROM) {
			// DELETE alias FROM table or DELETE FROM alias FROM table
			if hasFirstFrom {
				// DELETE FROM alias FROM table
				stmt.Alias = &ast.Identifier{Token: firstIdent.Parts[0].Token, Value: firstIdent.Parts[0].Value}
			} else {
				// DELETE alias FROM table
				stmt.Alias = &ast.Identifier{Token: firstIdent.Parts[0].Token, Value: firstIdent.Parts[0].Value}
			}
			p.nextToken()
			stmt.From = p.parseFromClause()
		} else if p.peekTokenIs(token.WITH) || p.peekTokenIs(token.WHERE) || p.peekTokenIs(token.SEMICOLON) || p.peekTokenIs(token.EOF) || p.curTokenIs(token.EOF) {
			// DELETE FROM table [WITH (hints)] [WHERE ...]
			stmt.Table = firstIdent
		} else {
			// Default: treat as table
			stmt.Table = firstIdent
		}
	}

	// Parse table hints WITH (TABLOCK), WITH (ROWLOCK, READPAST), etc.
	if p.peekTokenIs(token.WITH) {
		p.nextToken() // consume WITH
		if p.expectPeek(token.LPAREN) {
			stmt.Hints = p.parseTableHints()
		}
	}

	// Parse OUTPUT if not already parsed (for DELETE FROM table OUTPUT ...)
	if stmt.Output == nil && p.peekTokenIs(token.OUTPUT) {
		p.nextToken()
		stmt.Output = p.parseOutputClause()
	}

	// Parse WHERE or WHERE CURRENT OF
	if p.peekTokenIs(token.WHERE) {
		p.nextToken()
		p.nextToken()
		// Check for CURRENT OF cursor_name
		if p.curTokenIs(token.CURRENT) && p.peekTokenIs(token.OF) {
			p.nextToken() // consume OF
			p.nextToken() // move to cursor name
			stmt.CurrentOfCursor = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
		} else {
			stmt.Where = p.parseExpression(LOWEST)
		}
	}

	return stmt
}

// -----------------------------------------------------------------------------
// MERGE Statement
// -----------------------------------------------------------------------------

func (p *Parser) parseMergeStatement() ast.Statement {
	stmt := &ast.MergeStatement{Token: p.curToken}

	// MERGE [TOP (n)] [INTO] target
	if p.peekTokenIs(token.TOP) {
		p.nextToken() // consume TOP
		if p.peekTokenIs(token.LPAREN) {
			p.nextToken() // consume (
			p.nextToken() // move to value
			// Skip the TOP value
			for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
				p.nextToken()
			}
			// Now on ), move past it
		}
	}

	if p.peekTokenIs(token.INTO) {
		p.nextToken()
	}
	p.nextToken()

	stmt.Target = p.parseQualifiedIdentifier()

	// Optional WITH (hints) after target table
	if p.peekTokenIs(token.WITH) {
		p.nextToken() // consume WITH
		if p.peekTokenIs(token.LPAREN) {
			p.nextToken()           // consume (
			_ = p.parseTableHints() // parse and discard hints for now
		}
	}

	// Optional AS alias or just alias
	if p.peekTokenIs(token.AS) {
		p.nextToken()
		p.nextToken()
		stmt.TargetAlias = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
	} else if p.peekTokenIs(token.IDENT) && !p.peekTokenIs(token.USING) {
		p.nextToken()
		stmt.TargetAlias = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
	}

	// USING source
	if !p.expectPeek(token.USING) {
		return nil
	}
	p.nextToken()

	// Source can be a table, subquery in parentheses, VALUES, or qualified identifier
	if p.curTokenIs(token.LPAREN) {
		startToken := p.curToken
		p.nextToken()
		if p.curTokenIs(token.SELECT) {
			// Subquery source
			subquery := p.parseSelectStatement()
			if !p.expectPeek(token.RPAREN) {
				return nil
			}
			stmt.Source = &ast.DerivedTable{Token: startToken, Subquery: subquery}
		} else if p.curTokenIs(token.VALUES) {
			// VALUES table constructor: (VALUES (row1), (row2), ...) AS alias(columns)
			valuesTable := &ast.ValuesTable{Token: startToken}
			valuesTable.Rows = p.parseValuesRows()
			if !p.expectPeek(token.RPAREN) {
				return nil
			}
			stmt.Source = valuesTable
		} else {
			// Could be parenthesized table reference, just skip to matching )
			depth := 1
			for depth > 0 && !p.curTokenIs(token.EOF) {
				p.nextToken()
				if p.curTokenIs(token.LPAREN) {
					depth++
				} else if p.curTokenIs(token.RPAREN) {
					depth--
				}
			}
		}
	} else {
		// Table source
		stmt.Source = &ast.TableName{Name: p.parseQualifiedIdentifier()}
	}

	// Optional AS alias or just alias
	if p.peekTokenIs(token.AS) {
		p.nextToken()
		p.nextToken()
		stmt.SourceAlias = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
	} else if p.peekTokenIs(token.IDENT) && !p.peekTokenIs(token.ON) {
		p.nextToken()
		stmt.SourceAlias = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
	}

	// Check for column list after alias: AS source (col1, col2, ...)
	if p.peekTokenIs(token.LPAREN) {
		p.nextToken()               // consume (
		_ = p.parseIdentifierList() // parse and discard column list for now
	}

	// ON condition
	if !p.expectPeek(token.ON) {
		return nil
	}
	p.nextToken()
	stmt.OnCondition = p.parseExpression(LOWEST)

	// Parse WHEN clauses
	for p.peekTokenIs(token.WHEN) {
		p.nextToken()
		whenClause := p.parseMergeWhenClause()
		if whenClause != nil {
			stmt.WhenClauses = append(stmt.WhenClauses, whenClause)
		}
	}

	// Parse OUTPUT clause
	if p.peekTokenIs(token.OUTPUT) {
		p.nextToken()
		stmt.Output = p.parseOutputClause()
	}

	return stmt
}

func (p *Parser) parseMergeWhenClause() *ast.MergeWhenClause {
	clause := &ast.MergeWhenClause{}

	// Determine the type: MATCHED, NOT MATCHED [BY TARGET], NOT MATCHED BY SOURCE
	if p.peekTokenIs(token.MATCHED) {
		p.nextToken()
		clause.Type = ast.MergeWhenMatched
	} else if p.peekTokenIs(token.NOT) {
		p.nextToken() // consume NOT
		if !p.expectPeek(token.MATCHED) {
			return nil
		}
		// Check for BY TARGET or BY SOURCE
		if p.peekTokenIs(token.BY) {
			p.nextToken() // consume BY
			p.nextToken() // consume TARGET or SOURCE
			if p.curToken.Literal == "SOURCE" || p.curTokenIs(token.SOURCE) {
				clause.Type = ast.MergeWhenNotMatchedBySource
			} else {
				clause.Type = ast.MergeWhenNotMatchedByTarget
			}
		} else {
			clause.Type = ast.MergeWhenNotMatchedByTarget
		}
	} else {
		return nil
	}

	// Optional AND condition
	if p.peekTokenIs(token.AND) {
		p.nextToken()
		p.nextToken()
		clause.Condition = p.parseExpression(LOWEST)
	}

	// THEN
	if !p.expectPeek(token.THEN) {
		return nil
	}
	p.nextToken()

	// Action: UPDATE, DELETE, or INSERT
	if p.curTokenIs(token.UPDATE) {
		clause.Action = ast.MergeActionUpdate
		if !p.expectPeek(token.SET) {
			return nil
		}
		clause.SetClauses = p.parseSetClauses()
	} else if p.curTokenIs(token.DELETE) {
		clause.Action = ast.MergeActionDelete
	} else if p.curTokenIs(token.INSERT) {
		clause.Action = ast.MergeActionInsert
		// Optional column list
		if p.peekTokenIs(token.LPAREN) {
			p.nextToken()
			clause.Columns = p.parseIdentifierList()
		}
		// VALUES
		if !p.expectPeek(token.VALUES) {
			return nil
		}
		if !p.expectPeek(token.LPAREN) {
			return nil
		}
		clause.Values = p.parseExpressionList(token.RPAREN)
	}

	return clause
}

// -----------------------------------------------------------------------------
// Control Flow Statements
// -----------------------------------------------------------------------------

func (p *Parser) parseDeclareStatement() ast.Statement {
	declareToken := p.curToken
	p.nextToken()

	// Check for DECLARE cursor_name CURSOR syntax
	// Cursor names are identifiers (not variables starting with @)
	if p.curTokenIs(token.IDENT) && p.peekTokenIs(token.CURSOR) {
		return p.parseDeclareCursorStatement(declareToken)
	}

	stmt := &ast.DeclareStatement{Token: declareToken}

	varDef := p.parseVariableDef()
	stmt.Variables = append(stmt.Variables, varDef)

	for p.peekTokenIs(token.COMMA) {
		p.nextToken()
		p.nextToken()
		varDef = p.parseVariableDef()
		stmt.Variables = append(stmt.Variables, varDef)
	}

	return stmt
}

func (p *Parser) parseDeclareCursorStatement(declareToken token.Token) ast.Statement {
	stmt := &ast.DeclareCursorStatement{Token: declareToken}

	// Parse cursor name
	stmt.Name = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}

	// Skip past CURSOR
	p.nextToken() // now on CURSOR
	p.nextToken() // now on first option or FOR

	// Parse cursor options
	stmt.Options = p.parseCursorOptions()

	// Expect FOR
	if p.curTokenIs(token.FOR) {
		p.nextToken()
		stmt.ForSelect = p.parseSelectStatement()
	}

	// FOR UPDATE OF columns (optional)
	if p.peekTokenIs(token.FOR) {
		p.nextToken() // consume FOR
		if p.peekTokenIs(token.UPDATE) {
			p.nextToken() // consume UPDATE
			if p.peekTokenIs(token.OF) {
				p.nextToken() // consume OF
				p.nextToken() // move to first column
				// Parse column list
				for !p.curTokenIs(token.SEMICOLON) && !p.curTokenIs(token.EOF) && !p.curTokenIs(token.GO) {
					stmt.ForUpdateColumns = append(stmt.ForUpdateColumns, p.curToken.Literal)
					if p.peekTokenIs(token.COMMA) {
						p.nextToken()
						p.nextToken()
					} else {
						break
					}
				}
			}
		}
	}

	return stmt
}

func (p *Parser) parseCursorOptions() *ast.CursorOptions {
	opts := &ast.CursorOptions{}

	for !p.curTokenIs(token.FOR) && !p.curTokenIs(token.EOF) {
		switch p.curToken.Type {
		case token.LOCAL:
			opts.Local = true
		case token.GLOBAL:
			opts.Global = true
		case token.FORWARD_ONLY:
			opts.ForwardOnly = true
		case token.SCROLL:
			opts.Scroll = true
		case token.STATIC:
			opts.Static = true
		case token.KEYSET:
			opts.Keyset = true
		case token.DYNAMIC:
			opts.Dynamic = true
		case token.FAST_FORWARD:
			opts.FastForward = true
		case token.READ_ONLY:
			opts.ReadOnly = true
		case token.SCROLL_LOCKS:
			opts.ScrollLocks = true
		case token.OPTIMISTIC:
			opts.Optimistic = true
		case token.TYPE_WARNING:
			opts.TypeWarning = true
		default:
			// Unknown token, stop parsing options
			return opts
		}
		p.nextToken()
	}

	return opts
}

func (p *Parser) parseVariableDef() *ast.VariableDef {
	varDef := &ast.VariableDef{Name: p.curToken.Literal}
	p.nextToken()

	// Check for TABLE type
	if p.curTokenIs(token.TABLE) {
		varDef.TableType = p.parseTableTypeDefinition()
		return varDef
	}

	varDef.DataType = p.parseDataType()

	// Check for initialization
	if p.peekTokenIs(token.EQ) {
		p.nextToken()
		p.nextToken()
		varDef.Value = p.parseExpression(LOWEST)
	}

	return varDef
}

func (p *Parser) parseTableTypeDefinition() *ast.TableTypeDefinition {
	tableDef := &ast.TableTypeDefinition{}

	if !p.expectPeek(token.LPAREN) {
		return nil
	}
	p.nextToken()

	// Parse column definitions and constraints
	for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
		if p.isTableConstraintStart() {
			constraint := p.parseTableConstraint()
			if constraint != nil {
				tableDef.Constraints = append(tableDef.Constraints, constraint)
			}
		} else {
			col := p.parseColumnDefinition()
			if col != nil {
				tableDef.Columns = append(tableDef.Columns, col)
			}
		}

		if p.peekTokenIs(token.COMMA) {
			p.nextToken()
			p.nextToken()
		} else if p.peekTokenIs(token.RPAREN) {
			p.nextToken()
			break
		} else {
			break
		}
	}

	return tableDef
}

func (p *Parser) parseDataType() *ast.DataType {
	dt := &ast.DataType{Name: strings.ToUpper(p.curToken.Literal)}

	// Check for qualified type name (e.g., dbo.MyType)
	for p.peekTokenIs(token.DOT) {
		p.nextToken() // consume dot
		p.nextToken() // move to next part
		dt.Name += "." + p.curToken.Literal
	}

	// Check for length/precision or typed XML schema
	if p.peekTokenIs(token.LPAREN) {
		p.nextToken()
		p.nextToken()

		// Special case: XML(schema_name) - typed XML
		if dt.Name == "XML" {
			// Parse schema name which can be qualified (dbo.MySchema)
			schemaName := p.curToken.Literal
			for p.peekTokenIs(token.DOT) {
				p.nextToken() // consume dot
				p.nextToken() // move to next part
				schemaName += "." + p.curToken.Literal
			}
			dt.XmlSchema = schemaName
			p.expectPeek(token.RPAREN)
		} else if strings.ToUpper(p.curToken.Literal) == "MAX" {
			dt.Max = true
			p.expectPeek(token.RPAREN)
		} else {
			val, _ := strconv.Atoi(p.curToken.Literal)
			dt.Precision = &val

			if p.peekTokenIs(token.COMMA) {
				p.nextToken()
				p.nextToken()
				scale, _ := strconv.Atoi(p.curToken.Literal)
				dt.Scale = &scale
			}

			p.expectPeek(token.RPAREN)
		}
	}

	return dt
}

func (p *Parser) parseSetStatement() ast.Statement {
	setToken := p.curToken
	p.nextToken()

	// Check for SET TRANSACTION ISOLATION LEVEL
	if p.curTokenIs(token.TRANSACTION) {
		return p.parseSetTransactionIsolation(setToken)
	}

	// Check for SET STATISTICS IO/TIME/PROFILE/XML ON/OFF
	if p.curTokenIs(token.STATISTICS) {
		return p.parseSetStatistics(setToken)
	}

	// Check for SET DEADLOCK_PRIORITY LOW/NORMAL/HIGH/<number>
	if p.curTokenIs(token.DEADLOCK_PRIORITY) {
		return p.parseSetDeadlockPriority(setToken)
	}

	// Check for SET CONTEXT_INFO 0x...
	if p.curTokenIs(token.CONTEXT_INFO) {
		return p.parseSetContextInfo(setToken)
	}

	// Check for SET OFFSETS keyword_list ON/OFF (deprecated)
	if p.curTokenIs(token.OFFSETS) {
		stmt := &ast.SetStatement{Token: setToken}
		stmt.Option = "OFFSETS"
		p.nextToken() // move past OFFSETS
		// Skip the keyword list until ON/OFF
		for !p.curTokenIs(token.ON) && strings.ToUpper(p.curToken.Literal) != "OFF" && !p.curTokenIs(token.EOF) {
			p.nextToken()
		}
		stmt.OnOff = strings.ToUpper(p.curToken.Literal)
		return stmt
	}

	// Check for SET options with ON/OFF values
	// Handle both single options (SET NOCOUNT ON) and comma-separated (SET XACT_ABORT, NOCOUNT ON)
	if p.curTokenIs(token.NOCOUNT) || p.curTokenIs(token.XACT_ABORT) ||
		p.curTokenIs(token.ANSI_NULLS) || p.curTokenIs(token.QUOTED_IDENTIFIER) ||
		p.curTokenIs(token.ANSI_WARNINGS) || p.curTokenIs(token.ARITHABORT) ||
		p.curTokenIs(token.ARITHIGNORE) || p.curTokenIs(token.ANSI_DEFAULTS) ||
		p.curTokenIs(token.CONCAT_NULL_YIELDS_NULL) || p.curTokenIs(token.NUMERIC_ROUNDABORT) ||
		p.curTokenIs(token.ANSI_PADDING) || p.curTokenIs(token.ANSI_NULL_DFLT_ON) ||
		p.curTokenIs(token.CURSOR_CLOSE_ON_COMMIT) || p.curTokenIs(token.IMPLICIT_TRANSACTIONS) ||
		p.curTokenIs(token.FMTONLY) || p.curTokenIs(token.PARSEONLY) ||
		p.curTokenIs(token.FORCEPLAN) || p.curTokenIs(token.SHOWPLAN_TEXT) ||
		p.curTokenIs(token.SHOWPLAN_ALL) || p.curTokenIs(token.SHOWPLAN_XML) ||
		p.curTokenIs(token.NOEXEC) || p.curTokenIs(token.REMOTE_PROC_TRANSACTIONS) {
		stmt := &ast.SetStatement{Token: setToken}
		// Collect all comma-separated options
		options := []string{strings.ToUpper(p.curToken.Literal)}
		for p.peekTokenIs(token.COMMA) {
			p.nextToken() // consume comma
			p.nextToken() // move to next option
			options = append(options, strings.ToUpper(p.curToken.Literal))
		}
		stmt.Option = strings.Join(options, ", ")
		p.nextToken()
		stmt.OnOff = strings.ToUpper(p.curToken.Literal)
		return stmt
	}

	// Check for SET option value patterns (IDENTITY_INSERT, ROWCOUNT, LANGUAGE, etc.)
	optionName := strings.ToUpper(p.curToken.Literal)
	switch optionName {
	case "IDENTITY_INSERT":
		return p.parseSetIdentityInsert(setToken)
	case "ROWCOUNT", "LOCK_TIMEOUT", "QUERY_GOVERNOR_COST_LIMIT", "DATEFIRST", "TEXTSIZE":
		return p.parseSetNumericOption(setToken, optionName)
	case "LANGUAGE", "DATEFORMAT":
		return p.parseSetStringOption(setToken, optionName)
	}

	// For variable assignment
	stmt := &ast.SetStatement{Token: setToken}

	// For variable assignment, parse the variable/expression
	if p.curTokenIs(token.VARIABLE) || p.curTokenIs(token.TEMPVAR) {
		// Check if this is a method call like @xml.modify(...)
		if p.peekTokenIs(token.DOT) {
			// Parse as expression to capture method call
			stmt.Variable = p.parseExpression(LOWEST)
			// If it's a method call (like .modify()), no assignment needed
			if _, isMethod := stmt.Variable.(*ast.MethodCallExpression); isMethod {
				return stmt
			}
		} else {
			stmt.Variable = &ast.Variable{Token: p.curToken, Name: p.curToken.Literal}
		}
	} else {
		// Handle other cases like SET @var.property = value
		stmt.Variable = p.parseExpression(CALL) // Use high precedence to avoid = being consumed
	}

	// Check for compound assignment operators
	switch p.peekToken.Type {
	case token.PLUSEQ, token.MINUSEQ, token.MULEQ, token.DIVEQ, token.MODEQ,
		token.ANDEQ, token.OREQ, token.XOREQ:
		p.nextToken() // consume operator
		p.nextToken() // move to value
		stmt.Value = p.parseExpression(LOWEST)
		return stmt
	}

	if !p.expectPeek(token.EQ) {
		return nil
	}
	p.nextToken()
	stmt.Value = p.parseExpression(LOWEST)

	return stmt
}

func (p *Parser) parseSetStatistics(setToken token.Token) ast.Statement {
	stmt := &ast.SetStatement{Token: setToken}
	p.nextToken() // move past STATISTICS
	// STATISTICS IO/TIME/PROFILE/XML
	stmt.Option = "STATISTICS " + strings.ToUpper(p.curToken.Literal)
	p.nextToken()
	stmt.OnOff = strings.ToUpper(p.curToken.Literal)
	return stmt
}

func (p *Parser) parseSetDeadlockPriority(setToken token.Token) ast.Statement {
	stmt := &ast.SetStatement{Token: setToken}
	stmt.Option = "DEADLOCK_PRIORITY"
	p.nextToken() // move past DEADLOCK_PRIORITY
	// Can be LOW, NORMAL, HIGH, or a number -10 to 10
	stmt.OnOff = strings.ToUpper(p.curToken.Literal)
	return stmt
}

func (p *Parser) parseSetContextInfo(setToken token.Token) ast.Statement {
	stmt := &ast.SetStatement{Token: setToken}
	stmt.Option = "CONTEXT_INFO"
	p.nextToken() // move past CONTEXT_INFO
	// Expect binary value like 0x01020304
	stmt.OnOff = p.curToken.Literal
	return stmt
}

func (p *Parser) parseSetTransactionIsolation(setToken token.Token) ast.Statement {
	stmt := &ast.SetTransactionIsolationStatement{Token: setToken}

	// Skip TRANSACTION ISOLATION LEVEL
	if !p.expectPeek(token.ISOLATION) {
		return nil
	}
	if !p.expectPeek(token.LEVEL) {
		return nil
	}
	p.nextToken()

	// Parse level: READ UNCOMMITTED, READ COMMITTED, REPEATABLE READ, SERIALIZABLE, SNAPSHOT
	var level string
	switch strings.ToUpper(p.curToken.Literal) {
	case "READ":
		p.nextToken()
		level = "READ " + strings.ToUpper(p.curToken.Literal)
	case "REPEATABLE":
		p.nextToken()
		level = "REPEATABLE " + strings.ToUpper(p.curToken.Literal)
	case "SERIALIZABLE", "SNAPSHOT":
		level = strings.ToUpper(p.curToken.Literal)
	default:
		level = strings.ToUpper(p.curToken.Literal)
	}
	stmt.Level = level
	return stmt
}

func (p *Parser) parseSetIdentityInsert(setToken token.Token) ast.Statement {
	stmt := &ast.SetOptionStatement{Token: setToken, Option: "IDENTITY_INSERT"}
	p.nextToken() // move past IDENTITY_INSERT

	stmt.Table = p.parseQualifiedIdentifier()
	p.nextToken()

	// ON or OFF
	stmt.Value = &ast.Identifier{Token: p.curToken, Value: strings.ToUpper(p.curToken.Literal)}
	return stmt
}

func (p *Parser) parseSetNumericOption(setToken token.Token, option string) ast.Statement {
	stmt := &ast.SetOptionStatement{Token: setToken, Option: option}
	p.nextToken() // move past option name

	stmt.Value = p.parseExpression(LOWEST)
	return stmt
}

func (p *Parser) parseSetStringOption(setToken token.Token, option string) ast.Statement {
	stmt := &ast.SetOptionStatement{Token: setToken, Option: option}
	p.nextToken() // move past option name

	stmt.Value = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
	return stmt
}

func (p *Parser) parseIfStatement() ast.Statement {
	stmt := &ast.IfStatement{Token: p.curToken}
	p.nextToken()

	stmt.Condition = p.parseExpression(LOWEST)
	p.nextToken()

	stmt.Consequence = p.parseStatement()

	// After parsing consequence, advance past any semicolons to check for ELSE
	// First, advance to peek position (the token after the last token of consequence)
	if p.peekTokenIs(token.SEMICOLON) {
		p.nextToken() // now at semicolon
	}
	// Skip any semicolons
	for p.peekTokenIs(token.SEMICOLON) {
		p.nextToken()
	}

	if p.peekTokenIs(token.ELSE) {
		p.nextToken() // move to ELSE
		p.nextToken() // move past ELSE to the alternative statement
		stmt.Alternative = p.parseStatement()
	}

	return stmt
}

func (p *Parser) parseWhileStatement() ast.Statement {
	stmt := &ast.WhileStatement{Token: p.curToken}
	p.nextToken()

	stmt.Condition = p.parseExpression(LOWEST)
	p.nextToken()

	stmt.Body = p.parseStatement()

	return stmt
}

func (p *Parser) parseBeginStatement() ast.Statement {
	// Check for BEGIN TRY or BEGIN CATCH or BEGIN TRANSACTION or BEGIN DIALOG
	if p.peekTokenIs(token.TRY) {
		return p.parseTryCatchStatement()
	}
	if p.peekTokenIs(token.TRANSACTION) || p.peekTokenIs(token.TRAN) {
		return p.parseBeginTransactionStatement()
	}
	if p.peekTokenIs(token.DIALOG) {
		return p.parseBeginDialogStatement()
	}

	return p.parseBeginEndBlock()
}

func (p *Parser) parseBeginEndBlock() *ast.BeginEndBlock {
	block := &ast.BeginEndBlock{Token: p.curToken}
	p.nextToken()

	for !p.isBlockEndingEnd() && !p.curTokenIs(token.EOF) {
		// Skip semicolons
		for p.curTokenIs(token.SEMICOLON) {
			p.nextToken()
		}
		// Check again after skipping semicolons
		if p.isBlockEndingEnd() || p.curTokenIs(token.EOF) {
			break
		}
		stmt := p.parseStatement()
		if stmt != nil {
			block.Statements = append(block.Statements, stmt)
		}
		p.nextToken()
	}

	return block
}

// parseBeginAtomicBlock handles BEGIN ATOMIC WITH (...) blocks for natively compiled procs
func (p *Parser) parseBeginAtomicBlock() *ast.BeginEndBlock {
	block := &ast.BeginEndBlock{Token: p.curToken}
	p.nextToken() // move past BEGIN ATOMIC

	// Handle WITH clause: WITH (TRANSACTION ISOLATION LEVEL = ..., LANGUAGE = ...)
	if p.curTokenIs(token.WITH) {
		p.nextToken() // move past WITH
		if p.curTokenIs(token.LPAREN) {
			// Skip the entire WITH (...) clause by matching parens
			depth := 1
			p.nextToken()
			for depth > 0 && !p.curTokenIs(token.EOF) {
				if p.curTokenIs(token.LPAREN) {
					depth++
				} else if p.curTokenIs(token.RPAREN) {
					depth--
				}
				if depth > 0 {
					p.nextToken()
				}
			}
			p.nextToken() // move past final )
		}
	}

	// Parse body like normal BEGIN/END block
	for !p.isBlockEndingEnd() && !p.curTokenIs(token.EOF) {
		for p.curTokenIs(token.SEMICOLON) {
			p.nextToken()
		}
		if p.isBlockEndingEnd() || p.curTokenIs(token.EOF) {
			break
		}
		stmt := p.parseStatement()
		if stmt != nil {
			block.Statements = append(block.Statements, stmt)
		}
		p.nextToken()
	}

	return block
}

// isBlockEndingEnd returns true if current END token ends a BEGIN block
func (p *Parser) isBlockEndingEnd() bool {
	return p.curTokenIs(token.END)
}

func (p *Parser) parseTryCatchStatement() ast.Statement {
	stmt := &ast.TryCatchStatement{Token: p.curToken}
	p.nextToken() // consume TRY

	stmt.TryBlock = p.parseBeginEndBlock()

	// Expect END TRY
	if !p.curTokenIs(token.END) {
		return nil
	}
	if !p.expectPeek(token.TRY) {
		return nil
	}

	// Expect BEGIN CATCH
	if !p.expectPeek(token.BEGIN) {
		return nil
	}
	if !p.expectPeek(token.CATCH) {
		return nil
	}

	stmt.CatchBlock = p.parseBeginEndBlock()

	// Expect END CATCH
	if !p.curTokenIs(token.END) {
		return nil
	}
	p.expectPeek(token.CATCH)

	return stmt
}

func (p *Parser) parseBeginTransactionStatement() ast.Statement {
	stmt := &ast.BeginTransactionStatement{Token: p.curToken}
	p.nextToken() // consume TRANSACTION or TRAN

	if p.peekTokenIs(token.IDENT) {
		p.nextToken()
		stmt.Name = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
	}

	// WITH MARK 'description'
	if p.peekTokenIs(token.WITH) {
		p.nextToken() // consume WITH
		if p.peekTokenIs(token.IDENT) && strings.ToUpper(p.peekToken.Literal) == "MARK" {
			p.nextToken() // consume MARK
			if p.peekTokenIs(token.STRING) {
				p.nextToken()
				stmt.Mark = p.curToken.Literal
			}
		}
	}

	return stmt
}

func (p *Parser) parseReturnStatement() ast.Statement {
	stmt := &ast.ReturnStatement{Token: p.curToken}

	if !p.peekTokenIs(token.SEMICOLON) && !p.peekTokenIs(token.EOF) &&
		!p.peekTokenIs(token.END) {
		p.nextToken()
		stmt.Value = p.parseExpression(LOWEST)
	}

	return stmt
}

func (p *Parser) parseBreakStatement() ast.Statement {
	return &ast.BreakStatement{Token: p.curToken}
}

func (p *Parser) parseContinueStatement() ast.Statement {
	return &ast.ContinueStatement{Token: p.curToken}
}

func (p *Parser) parsePrintStatement() ast.Statement {
	stmt := &ast.PrintStatement{Token: p.curToken}
	p.nextToken()
	stmt.Expression = p.parseExpression(LOWEST)
	return stmt
}

func (p *Parser) parseExecStatement() ast.Statement {
	execToken := p.curToken
	p.nextToken()

	// Check for EXECUTE AS (impersonation context)
	if p.curTokenIs(token.AS) {
		return p.parseExecuteAsStatement(execToken)
	}

	stmt := &ast.ExecStatement{Token: execToken}

	// Check for dynamic SQL: EXEC('sql')
	if p.curTokenIs(token.LPAREN) {
		p.nextToken()
		stmt.DynamicSQL = p.parseExpression(LOWEST)
		p.expectPeek(token.RPAREN)

		// Check for AT linked_server
		if p.peekTokenIs(token.AT) {
			p.nextToken() // consume AT
			p.nextToken() // move to server name
			stmt.AtServer = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
		}

		return stmt
	}

	// Check for return variable: EXEC @ReturnCode = procedure
	if p.curTokenIs(token.VARIABLE) && p.peekTokenIs(token.EQ) {
		stmt.ReturnVariable = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
		p.nextToken() // move to =
		p.nextToken() // move to procedure name
	}

	stmt.Procedure = p.parseQualifiedIdentifier()

	// Check for WITH RECOMPILE (can come before or after parameters)
	if p.peekTokenIs(token.WITH) {
		p.nextToken()
		if p.peekTokenIs(token.RECOMPILE) {
			p.nextToken()
			stmt.Recompile = true
		} else if p.peekTokenIs(token.RESULT) {
			// Handle WITH RESULT SETS here
			p.nextToken() // move to RESULT
			if p.peekTokenIs(token.SETS) {
				p.nextToken() // move to SETS
				// Check for UNDEFINED or NONE
				if p.peekTokenIs(token.UNDEFINED) {
					p.nextToken()
					stmt.ResultSetsMode = "UNDEFINED"
				} else if p.peekTokenIs(token.NONE_KW) {
					p.nextToken()
					stmt.ResultSetsMode = "NONE"
				} else {
					stmt.ResultSets = p.parseResultSets()
				}
			}
			return stmt
		}
	}

	// Parse parameters
	if !p.peekTokenIs(token.SEMICOLON) && !p.peekTokenIs(token.EOF) &&
		!p.peekTokenIs(token.END) && !p.peekTokenIs(token.GO) &&
		!p.peekTokenIs(token.WITH) {
		p.nextToken()
		stmt.Parameters = p.parseExecParameters()
	}

	// Check for WITH RECOMPILE or WITH RESULT SETS after parameters
	if p.peekTokenIs(token.WITH) {
		p.nextToken()
		if p.peekTokenIs(token.RECOMPILE) {
			p.nextToken()
			stmt.Recompile = true
		} else if p.peekTokenIs(token.RESULT) {
			p.nextToken() // move to RESULT
			if p.peekTokenIs(token.SETS) {
				p.nextToken() // move to SETS
				// Check for UNDEFINED or NONE
				if p.peekTokenIs(token.UNDEFINED) {
					p.nextToken()
					stmt.ResultSetsMode = "UNDEFINED"
				} else if p.peekTokenIs(token.NONE_KW) {
					p.nextToken()
					stmt.ResultSetsMode = "NONE"
				} else {
					stmt.ResultSets = p.parseResultSets()
				}
			}
		}
	}

	// Check for AT linked_server (can come after parameters or WITH)
	if p.peekTokenIs(token.AT) {
		p.nextToken() // consume AT
		p.nextToken() // move to server name
		stmt.AtServer = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
	}

	return stmt
}

// parseResultSets parses WITH RESULT SETS ((...), (...))
func (p *Parser) parseResultSets() []*ast.ResultSetDefinition {
	var sets []*ast.ResultSetDefinition

	// Expect opening paren for the RESULT SETS clause
	if !p.expectPeek(token.LPAREN) {
		return nil
	}

	for {
		// Each result set is enclosed in parentheses
		if !p.expectPeek(token.LPAREN) {
			break
		}

		rs := &ast.ResultSetDefinition{}
		p.nextToken() // move past opening paren

		// Parse columns: name datatype [NULL|NOT NULL], name datatype, ...
		for {
			col := &ast.ResultSetColumn{}

			// Column name
			col.Name = p.curToken.Literal
			p.nextToken()

			// Data type
			col.DataType = p.parseDataType()

			// Check for NULL or NOT NULL
			if p.peekTokenIs(token.NULL) {
				p.nextToken()
				col.Nullable = true
				col.HasNull = true
			} else if p.peekTokenIs(token.NOT) {
				p.nextToken() // consume NOT
				if p.peekTokenIs(token.NULL) {
					p.nextToken() // consume NULL
					col.Nullable = false
					col.HasNull = true
				}
			}

			rs.Columns = append(rs.Columns, col)

			// Check for comma (more columns) or closing paren
			if p.peekTokenIs(token.COMMA) {
				p.nextToken() // consume comma
				p.nextToken() // move to next column name
			} else {
				break
			}
		}

		if !p.expectPeek(token.RPAREN) {
			break
		}
		sets = append(sets, rs)

		// Check for comma (more result sets) or closing paren
		if p.peekTokenIs(token.COMMA) {
			p.nextToken() // consume comma
		} else {
			break
		}
	}

	// Expect closing paren for RESULT SETS clause
	p.expectPeek(token.RPAREN)

	return sets
}

func (p *Parser) parseExecuteAsStatement(execToken token.Token) ast.Statement {
	stmt := &ast.ExecuteAsStatement{Token: execToken}
	p.nextToken() // move past AS

	switch p.curToken.Type {
	case token.CALLER:
		stmt.Type = "CALLER"
	case token.SELF:
		stmt.Type = "SELF"
	case token.OWNER_KW:
		stmt.Type = "OWNER"
	case token.USER:
		stmt.Type = "USER"
		if p.peekTokenIs(token.EQ) {
			p.nextToken() // consume =
			p.nextToken() // move to user name
			if p.curTokenIs(token.STRING) || p.curTokenIs(token.NSTRING) {
				stmt.UserName = p.curToken.Literal
			}
		}
	case token.LOGIN:
		stmt.Type = "LOGIN"
		if p.peekTokenIs(token.EQ) {
			p.nextToken() // consume =
			p.nextToken() // move to login name
			if p.curTokenIs(token.STRING) || p.curTokenIs(token.NSTRING) {
				stmt.UserName = p.curToken.Literal
			}
		}
	case token.IDENT:
		// Handle other identifiers if needed
		break
	}

	// Check for WITH COOKIE INTO @var
	if p.peekTokenIs(token.WITH) {
		p.nextToken() // consume WITH
		p.nextToken() // should be COOKIE (as IDENT)
		if strings.ToUpper(p.curToken.Literal) == "COOKIE" {
			if p.peekTokenIs(token.INTO) {
				p.nextToken() // consume INTO
				p.nextToken() // move to variable
				if p.curTokenIs(token.VARIABLE) {
					stmt.CookieVar = p.curToken.Literal
				}
			}
		}
	}

	return stmt
}

func (p *Parser) parseRevertStatement() ast.Statement {
	stmt := &ast.RevertStatement{Token: p.curToken}

	// Check for WITH COOKIE = @cookie
	if p.peekTokenIs(token.WITH) {
		p.nextToken() // consume WITH
		if p.peekTokenIs(token.IDENT) && strings.ToUpper(p.peekToken.Literal) == "COOKIE" {
			p.nextToken() // consume COOKIE
			if p.peekTokenIs(token.EQ) {
				p.nextToken() // consume =
				p.nextToken() // move to cookie variable
				stmt.Cookie = p.parseExpression(LOWEST)
			}
		}
	}

	return stmt
}

func (p *Parser) parseReconfigureStatement() ast.Statement {
	stmt := &ast.ReconfigureStatement{Token: p.curToken}

	// Check for WITH OVERRIDE
	if p.peekTokenIs(token.WITH) {
		p.nextToken() // consume WITH
		if p.peekTokenIs(token.IDENT) && strings.ToUpper(p.peekToken.Literal) == "OVERRIDE" {
			p.nextToken() // consume OVERRIDE
			stmt.WithOverride = true
		}
	}

	return stmt
}

func (p *Parser) parseExecParameters() []*ast.ExecParameter {
	params := []*ast.ExecParameter{}

	param := p.parseExecParameter()
	params = append(params, param)

	for p.peekTokenIs(token.COMMA) {
		p.nextToken()
		p.nextToken()
		param = p.parseExecParameter()
		params = append(params, param)
	}

	return params
}

func (p *Parser) parseExecParameter() *ast.ExecParameter {
	param := &ast.ExecParameter{}

	// Check for named parameter
	if p.curTokenIs(token.VARIABLE) && p.peekTokenIs(token.EQ) {
		param.Name = p.curToken.Literal
		p.nextToken() // consume =
		p.nextToken()
	}

	param.Value = p.parseExpression(LOWEST)

	// Check for OUTPUT
	if p.peekTokenIs(token.OUTPUT) {
		p.nextToken()
		param.Output = true
	}

	return param
}

func (p *Parser) parseCreateStatement() ast.Statement {
	createToken := p.curToken
	p.nextToken()

	switch p.curToken.Type {
	case token.PROCEDURE, token.PROC:
		return p.parseCreateProcedureStatement()
	case token.TABLE:
		return p.parseCreateTableStatement()
	case token.VIEW:
		return p.parseCreateViewStatement(createToken)
	case token.INDEX:
		return p.parseCreateIndexStatement(createToken, false, nil)
	case token.UNIQUE:
		// CREATE UNIQUE INDEX or CREATE UNIQUE CLUSTERED/NONCLUSTERED INDEX
		p.nextToken()
		if p.curTokenIs(token.CLUSTERED) {
			clustered := true
			p.nextToken() // move past CLUSTERED
			if p.curTokenIs(token.INDEX) {
				return p.parseCreateIndexStatement(createToken, true, &clustered)
			}
		} else if p.curTokenIs(token.NONCLUSTERED) {
			clustered := false
			p.nextToken() // move past NONCLUSTERED
			if p.curTokenIs(token.INDEX) {
				return p.parseCreateIndexStatement(createToken, true, &clustered)
			}
		} else if p.curTokenIs(token.INDEX) {
			return p.parseCreateIndexStatement(createToken, true, nil)
		}
		return nil
	case token.CLUSTERED:
		clustered := true
		p.nextToken()
		if p.curTokenIs(token.INDEX) {
			return p.parseCreateIndexStatement(createToken, false, &clustered)
		} else if p.curTokenIs(token.IDENT) && strings.ToUpper(p.curToken.Literal) == "COLUMNSTORE" {
			// CLUSTERED COLUMNSTORE INDEX
			p.nextToken() // move past COLUMNSTORE
			if p.curTokenIs(token.INDEX) {
				return p.parseCreateIndexStatement(createToken, false, &clustered)
			}
		}
		return nil
	case token.NONCLUSTERED:
		clustered := false
		p.nextToken()
		if p.curTokenIs(token.INDEX) {
			return p.parseCreateIndexStatement(createToken, false, &clustered)
		} else if p.curTokenIs(token.IDENT) && strings.ToUpper(p.curToken.Literal) == "COLUMNSTORE" {
			// NONCLUSTERED COLUMNSTORE INDEX
			p.nextToken() // move past COLUMNSTORE
			if p.curTokenIs(token.INDEX) {
				return p.parseCreateIndexStatement(createToken, false, &clustered)
			}
		}
		return nil
	case token.FUNCTION:
		return p.parseCreateFunctionStatement(createToken)
	case token.DEFAULT_KW:
		return p.parseCreateDefaultStatement(createToken)
	case token.PRIMARY:
		// CREATE PRIMARY XML INDEX
		if p.peekTokenIs(token.XML) {
			p.nextToken() // consume XML
			if p.peekTokenIs(token.INDEX) {
				p.nextToken() // consume INDEX
				return p.parseCreateXmlIndexStatement(createToken, true)
			}
		}
		return nil
	case token.XML:
		// CREATE XML INDEX (secondary)
		if p.peekTokenIs(token.INDEX) {
			p.nextToken() // consume INDEX
			return p.parseCreateXmlIndexStatement(createToken, false)
		}
		return nil
	case token.XML_SCHEMA_COLLECTION:
		// CREATE XML SCHEMA COLLECTION name AS N'...'
		return p.parseCreateXmlSchemaCollectionStatement(createToken)
	case token.TRIGGER:
		return p.parseCreateTriggerStatement(createToken)
	case token.TYPE_WARNING:
		return p.parseCreateTypeStatement(createToken)
	case token.SYNONYM:
		return p.parseCreateSynonymStatement(createToken)
	case token.SEQUENCE:
		return p.parseCreateSequenceStatement(createToken)
	case token.STATISTICS:
		return p.parseCreateStatisticsStatement(createToken)
	case token.LOGIN:
		return p.parseCreateLoginStatement(createToken)
	case token.USER:
		return p.parseCreateUserStatement(createToken)
	case token.ROLE:
		return p.parseCreateRoleStatement(createToken)
	case token.MASTER:
		return p.parseCreateMasterKeyStatement(createToken)
	case token.CERTIFICATE:
		return p.parseCreateCertificateStatement(createToken)
	case token.SYMMETRIC:
		return p.parseCreateSymmetricKeyStatement(createToken)
	case token.ASYMMETRIC:
		return p.parseCreateAsymmetricKeyStatement(createToken)
	case token.ASSEMBLY:
		return p.parseCreateAssemblyStatement(createToken)
	case token.PARTITION:
		return p.parseCreatePartitionStatement(createToken)
	case token.FULLTEXT:
		return p.parseCreateFulltextStatement(createToken)
	case token.RESOURCE:
		return p.parseCreateResourcePoolStatement(createToken)
	case token.WORKLOAD:
		return p.parseCreateWorkloadGroupStatement(createToken)
	case token.AVAILABILITY:
		return p.parseCreateAvailabilityGroupStatement(createToken)
	case token.MESSAGE:
		return p.parseCreateMessageTypeStatement(createToken)
	case token.CONTRACT:
		return p.parseCreateContractStatement(createToken)
	case token.QUEUE:
		return p.parseCreateQueueStatement(createToken)
	case token.SERVICE:
		return p.parseCreateServiceStatement(createToken)
	case token.SCHEMA:
		return p.parseCreateSchemaStatement(createToken)
	case token.SERVER:
		// CREATE SERVER ROLE or CREATE SERVER AUDIT
		if p.peekTokenIs(token.ROLE) {
			p.nextToken() // move to ROLE
			return p.parseCreateServerRoleStatement(createToken)
		}
		return nil
	case token.DATABASE:
		// CREATE DATABASE or CREATE DATABASE SCOPED CREDENTIAL
		return p.parseCreateDatabaseOrScopedCredential(createToken)
	case token.IDENT:
		// Handle APPLICATION ROLE, CREDENTIAL, SPATIAL INDEX, and other identifier-based creates
		upper := strings.ToUpper(p.curToken.Literal)
		if upper == "APPLICATION" && p.peekTokenIs(token.ROLE) {
			p.nextToken() // move to ROLE
			return p.parseCreateApplicationRoleStatement(createToken)
		}
		if upper == "CREDENTIAL" {
			return p.parseCreateCredentialStatement(createToken)
		}
		if upper == "SPATIAL" && p.peekTokenIs(token.INDEX) {
			p.nextToken() // move to INDEX
			return p.parseCreateIndexStatement(createToken, false, nil)
		}
		return nil
	default:
		// Skip other CREATE statements for now
		return nil
	}
}

func (p *Parser) parseCreateTableStatement() ast.Statement {
	stmt := &ast.CreateTableStatement{Token: p.curToken}
	p.nextToken()

	stmt.Name = p.parseQualifiedIdentifier()

	// Check for temporary table
	if len(stmt.Name.Parts) > 0 {
		name := stmt.Name.Parts[len(stmt.Name.Parts)-1].Value
		if len(name) > 0 && name[0] == '#' {
			stmt.IsTemporary = true
		}
	}

	// Check for CREATE TABLE name AS FILETABLE
	if p.peekTokenIs(token.AS) {
		p.nextToken() // consume AS
		p.nextToken() // move to FILETABLE or other
		if strings.ToUpper(p.curToken.Literal) == "FILETABLE" {
			// FILETABLE doesn't have column definitions, just WITH options
			if p.peekTokenIs(token.WITH) {
				p.nextToken() // consume WITH
				if p.peekTokenIs(token.LPAREN) {
					p.nextToken() // consume (
					// Skip to matching )
					depth := 1
					for depth > 0 && !p.curTokenIs(token.EOF) {
						p.nextToken()
						if p.curTokenIs(token.LPAREN) {
							depth++
						} else if p.curTokenIs(token.RPAREN) {
							depth--
						}
					}
				}
			}
			return stmt
		}
		// Handle other AS cases (NODE, EDGE) - but those come after column defs
	}

	if !p.expectPeek(token.LPAREN) {
		return nil
	}
	p.nextToken()

	// Parse column definitions and table constraints
	for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
		// Check if this is a table constraint (starts with CONSTRAINT, PRIMARY, FOREIGN, UNIQUE, CHECK)
		if p.isTableConstraintStart() {
			constraint := p.parseTableConstraint()
			if constraint != nil {
				stmt.Constraints = append(stmt.Constraints, constraint)
			}
		} else {
			// Parse column definition
			col := p.parseColumnDefinition()
			if col != nil {
				stmt.Columns = append(stmt.Columns, col)
			}
		}

		// Check for comma or end
		if p.peekTokenIs(token.COMMA) {
			p.nextToken()
			p.nextToken()
		} else if p.peekTokenIs(token.RPAREN) {
			p.nextToken()
			break
		} else {
			break
		}
	}

	// Check for WITH clause (e.g., WITH (SYSTEM_VERSIONING = ON))
	if p.peekTokenIs(token.WITH) {
		p.nextToken() // consume WITH
		if p.peekTokenIs(token.LPAREN) {
			p.nextToken() // consume (
			p.nextToken() // move to first option
			// Parse options until matching ) - handle nested parentheses
			depth := 1
			for depth > 0 && !p.curTokenIs(token.EOF) {
				if p.curTokenIs(token.LPAREN) {
					depth++
				} else if p.curTokenIs(token.RPAREN) {
					depth--
					if depth == 0 {
						break
					}
				}
				p.nextToken()
			}
		}
	}

	// Check for ON filegroup or partition scheme
	if p.peekTokenIs(token.ON) {
		p.nextToken() // consume ON
		p.nextToken() // move to filegroup/scheme name
		stmt.FileGroup = p.curToken.Literal
		// Check for partition scheme column: ON PartitionScheme(column)
		if p.peekTokenIs(token.LPAREN) {
			p.nextToken() // consume (
			p.nextToken() // move to column name
			// Just consume the column name and )
			if !p.curTokenIs(token.RPAREN) {
				stmt.FileGroup += "(" + p.curToken.Literal + ")"
				p.expectPeek(token.RPAREN)
			}
		}
	}

	// Check for TEXTIMAGE_ON filegroup
	if p.peekToken.Type == token.IDENT && strings.ToUpper(p.peekToken.Literal) == "TEXTIMAGE_ON" {
		p.nextToken() // consume TEXTIMAGE_ON
		p.nextToken() // move to filegroup name
		stmt.TextImageOn = p.curToken.Literal
	}

	// Check for AS NODE or AS EDGE (graph tables)
	if p.peekTokenIs(token.AS) {
		p.nextToken() // consume AS
		p.nextToken() // move to NODE/EDGE
		// Just consume it - we're not storing it for now
	}

	return stmt
}

func (p *Parser) isTableConstraintStart() bool {
	// PERIOD is only a constraint if followed by FOR (PERIOD FOR SYSTEM_TIME)
	if p.curTokenIs(token.PERIOD) {
		return p.peekTokenIs(token.FOR)
	}
	return p.curTokenIs(token.CONSTRAINT) ||
		p.curTokenIs(token.PRIMARY) ||
		p.curTokenIs(token.FOREIGN) ||
		p.curTokenIs(token.UNIQUE) ||
		p.curTokenIs(token.CHECK) ||
		p.curTokenIs(token.INDEX)
}

func (p *Parser) parseColumnDefinition() *ast.ColumnDefinition {
	col := &ast.ColumnDefinition{Token: p.curToken}
	col.Name = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
	p.nextToken()

	// Check for computed column (AS expression)
	if p.curTokenIs(token.AS) {
		p.nextToken()
		if p.curTokenIs(token.LPAREN) {
			p.nextToken()
			col.Computed = p.parseExpression(LOWEST)
			p.expectPeek(token.RPAREN)
		} else {
			col.Computed = p.parseExpression(LOWEST)
		}
		// Check for PERSISTED
		if p.peekTokenIs(token.PERSISTED) {
			p.nextToken()
			col.IsPersisted = true
		}
		return col
	}

	// Parse data type
	col.DataType = p.parseDataType()

	// Parse column options
	for {
		if p.peekTokenIs(token.COLLATE) {
			p.nextToken()
			p.nextToken()
			col.Collation = p.curToken.Literal
		} else if p.peekTokenIs(token.NULL) {
			p.nextToken()
			nullable := true
			col.Nullable = &nullable
		} else if p.peekTokenIs(token.NOT) {
			p.nextToken()
			if p.expectPeek(token.NULL) {
				nullable := false
				col.Nullable = &nullable
			}
		} else if p.peekTokenIs(token.IDENTITY) {
			p.nextToken()
			col.Identity = p.parseIdentitySpec()
		} else if p.peekTokenIs(token.ROWGUIDCOL) {
			p.nextToken()
			col.IsRowGuidCol = true
		} else if p.peekTokenIs(token.SPARSE) {
			p.nextToken()
			col.IsSparse = true
		} else if p.peekToken.Type == token.IDENT && strings.ToUpper(p.peekToken.Literal) == "COLUMN_SET" {
			p.nextToken() // consume COLUMN_SET
			// Expect FOR ALL_SPARSE_COLUMNS
			if p.peekTokenIs(token.FOR) {
				p.nextToken() // consume FOR
				// Next should be ALL_SPARSE_COLUMNS as identifier
				if p.peekToken.Type == token.IDENT && strings.ToUpper(p.peekToken.Literal) == "ALL_SPARSE_COLUMNS" {
					p.nextToken() // consume ALL_SPARSE_COLUMNS
					col.IsColumnSet = true
				}
			}
		} else if p.peekTokenIs(token.DEFAULT_KW) {
			p.nextToken()
			p.nextToken()
			col.Default = p.parseExpression(LOWEST)
		} else if p.peekTokenIs(token.PRIMARY) {
			p.nextToken()
			constraint := p.parseInlineConstraint(ast.ConstraintPrimaryKey)
			col.Constraints = append(col.Constraints, constraint)
		} else if p.peekTokenIs(token.UNIQUE) {
			p.nextToken()
			constraint := &ast.ColumnConstraint{Type: ast.ConstraintUnique}
			col.Constraints = append(col.Constraints, constraint)
		} else if p.peekTokenIs(token.REFERENCES) {
			p.nextToken()
			constraint := p.parseInlineReferencesConstraint()
			col.Constraints = append(col.Constraints, constraint)
		} else if p.peekTokenIs(token.FOREIGN) {
			// FOREIGN KEY REFERENCES at column level
			p.nextToken() // consume FOREIGN
			if p.peekTokenIs(token.KEY) {
				p.nextToken() // consume KEY
			}
			if p.peekTokenIs(token.REFERENCES) {
				p.nextToken() // move to REFERENCES
				constraint := p.parseInlineReferencesConstraint()
				col.Constraints = append(col.Constraints, constraint)
			}
		} else if p.peekTokenIs(token.CHECK) {
			p.nextToken()
			constraint := p.parseInlineCheckConstraint()
			col.Constraints = append(col.Constraints, constraint)
		} else if p.peekTokenIs(token.GENERATED) {
			// GENERATED ALWAYS AS ROW START/END
			p.nextToken() // consume GENERATED
			if p.peekTokenIs(token.ALWAYS) {
				p.nextToken() // consume ALWAYS
			}
			if p.peekTokenIs(token.AS) {
				p.nextToken() // consume AS
			}
			if p.peekTokenIs(token.ROW) {
				p.nextToken() // consume ROW
				if p.peekTokenIs(token.START) {
					p.nextToken()
					col.GeneratedAlways = "ROW START"
				} else if p.peekTokenIs(token.END) {
					p.nextToken()
					col.GeneratedAlways = "ROW END"
				}
			}
		} else if p.peekTokenIs(token.CONSTRAINT) {
			p.nextToken()
			p.nextToken()
			constraintName := p.curToken.Literal
			p.nextToken()
			var constraint *ast.ColumnConstraint
			if p.curTokenIs(token.PRIMARY) {
				constraint = p.parseInlineConstraint(ast.ConstraintPrimaryKey)
			} else if p.curTokenIs(token.UNIQUE) {
				constraint = &ast.ColumnConstraint{Type: ast.ConstraintUnique}
			} else if p.curTokenIs(token.REFERENCES) {
				constraint = p.parseInlineReferencesConstraint()
			} else if p.curTokenIs(token.FOREIGN) {
				// CONSTRAINT name FOREIGN KEY REFERENCES
				if p.peekTokenIs(token.KEY) {
					p.nextToken() // consume KEY
				}
				if p.peekTokenIs(token.REFERENCES) {
					p.nextToken() // move to REFERENCES
					constraint = p.parseInlineReferencesConstraint()
				}
			} else if p.curTokenIs(token.CHECK) {
				constraint = p.parseInlineCheckConstraint()
			} else if p.curTokenIs(token.DEFAULT_KW) {
				p.nextToken()
				col.Default = p.parseExpression(LOWEST)
				continue
			}
			if constraint != nil {
				constraint.Name = constraintName
				col.Constraints = append(col.Constraints, constraint)
			}
		} else if p.peekTokenIs(token.INDEX) {
			// Inline index: INDEX index_name [CLUSTERED|NONCLUSTERED] [HASH] [WITH (...)]
			p.nextToken() // consume INDEX
			p.nextToken() // move to index name
			col.InlineIndex = &ast.InlineIndex{Name: p.curToken.Literal}
			// Check for CLUSTERED/NONCLUSTERED
			if p.peekTokenIs(token.CLUSTERED) {
				p.nextToken()
				clustered := true
				col.InlineIndex.Clustered = &clustered
			} else if p.peekTokenIs(token.NONCLUSTERED) {
				p.nextToken()
				clustered := false
				col.InlineIndex.Clustered = &clustered
			}
			// Check for HASH (memory-optimized)
			if p.peekTokenIs(token.HASH) {
				p.nextToken() // consume HASH
			}
			// Check for WITH (options)
			if p.peekTokenIs(token.WITH) {
				p.nextToken() // consume WITH
				if p.peekTokenIs(token.LPAREN) {
					p.nextToken() // consume (
					// Skip to matching )
					depth := 1
					for depth > 0 && !p.curTokenIs(token.EOF) {
						p.nextToken()
						if p.curTokenIs(token.LPAREN) {
							depth++
						} else if p.curTokenIs(token.RPAREN) {
							depth--
						}
					}
				}
			}
		} else if p.peekTokenIs(token.IDENT) && strings.ToUpper(p.peekToken.Literal) == "MASKED" {
			// Dynamic Data Masking: MASKED WITH (FUNCTION = '...')
			p.nextToken() // consume MASKED
			if p.peekTokenIs(token.WITH) {
				p.nextToken() // consume WITH
				if p.peekTokenIs(token.LPAREN) {
					p.nextToken() // consume (
					// Skip to matching )
					depth := 1
					for depth > 0 && !p.curTokenIs(token.EOF) {
						p.nextToken()
						if p.curTokenIs(token.LPAREN) {
							depth++
						} else if p.curTokenIs(token.RPAREN) {
							depth--
						}
					}
				}
			}
		} else if p.peekTokenIs(token.IDENT) && strings.ToUpper(p.peekToken.Literal) == "ENCRYPTED" {
			// Always Encrypted: ENCRYPTED WITH (COLUMN_ENCRYPTION_KEY = ..., ...)
			p.nextToken() // consume ENCRYPTED
			if p.peekTokenIs(token.WITH) {
				p.nextToken() // consume WITH
				if p.peekTokenIs(token.LPAREN) {
					p.nextToken() // consume (
					// Skip to matching )
					depth := 1
					for depth > 0 && !p.curTokenIs(token.EOF) {
						p.nextToken()
						if p.curTokenIs(token.LPAREN) {
							depth++
						} else if p.curTokenIs(token.RPAREN) {
							depth--
						}
					}
				}
			}
		} else {
			break
		}
	}

	return col
}

func (p *Parser) parseIdentitySpec() *ast.IdentitySpec {
	spec := &ast.IdentitySpec{Seed: 1, Increment: 1}

	if p.peekTokenIs(token.LPAREN) {
		p.nextToken()
		p.nextToken()

		// Parse seed (may be negative)
		negative := false
		if p.curTokenIs(token.MINUS) {
			negative = true
			p.nextToken()
		}
		if p.curTokenIs(token.INT) {
			seed, _ := strconv.ParseInt(p.curToken.Literal, 10, 64)
			if negative {
				seed = -seed
			}
			spec.Seed = seed
		}

		if p.peekTokenIs(token.COMMA) {
			p.nextToken()
			p.nextToken()

			// Parse increment (may be negative)
			negative = false
			if p.curTokenIs(token.MINUS) {
				negative = true
				p.nextToken()
			}
			if p.curTokenIs(token.INT) {
				inc, _ := strconv.ParseInt(p.curToken.Literal, 10, 64)
				if negative {
					inc = -inc
				}
				spec.Increment = inc
			}
		}
		p.expectPeek(token.RPAREN)
	}

	return spec
}

func (p *Parser) parseInlineConstraint(ctype ast.ConstraintType) *ast.ColumnConstraint {
	constraint := &ast.ColumnConstraint{Type: ctype}

	if ctype == ast.ConstraintPrimaryKey {
		p.expectPeek(token.KEY)
		constraint.IsPrimaryKey = true

		if p.peekTokenIs(token.CLUSTERED) {
			p.nextToken()
			clustered := true
			constraint.IsClustered = &clustered
		} else if p.peekTokenIs(token.NONCLUSTERED) {
			p.nextToken()
			clustered := false
			constraint.IsClustered = &clustered
		}

		// Check for HASH (memory-optimized tables)
		if p.peekTokenIs(token.HASH) {
			p.nextToken() // consume HASH
			// Parse WITH (BUCKET_COUNT = n)
			if p.peekTokenIs(token.WITH) {
				p.nextToken() // consume WITH
				if p.peekTokenIs(token.LPAREN) {
					p.nextToken() // consume (
					// Skip to matching )
					depth := 1
					for depth > 0 && !p.curTokenIs(token.EOF) {
						p.nextToken()
						if p.curTokenIs(token.LPAREN) {
							depth++
						} else if p.curTokenIs(token.RPAREN) {
							depth--
						}
					}
				}
			}
		}
	}

	return constraint
}

func (p *Parser) parseInlineReferencesConstraint() *ast.ColumnConstraint {
	constraint := &ast.ColumnConstraint{Type: ast.ConstraintForeignKey}
	p.nextToken()

	constraint.ReferencesTable = p.parseQualifiedIdentifier()

	if p.peekTokenIs(token.LPAREN) {
		p.nextToken()
		constraint.ReferencesColumns = p.parseIdentifierList()
	}

	// Parse ON DELETE / ON UPDATE
	for p.peekTokenIs(token.ON) {
		p.nextToken()
		p.nextToken()
		action := strings.ToUpper(p.curToken.Literal)
		p.nextToken()

		var actionValue string
		if p.curTokenIs(token.CASCADE) {
			actionValue = "CASCADE"
		} else if p.curTokenIs(token.RESTRICT) {
			actionValue = "RESTRICT"
		} else if strings.ToUpper(p.curToken.Literal) == "NO" {
			p.nextToken() // ACTION
			actionValue = "NO ACTION"
		} else if p.curTokenIs(token.SET) {
			p.nextToken()
			if p.curTokenIs(token.NULL) {
				actionValue = "SET NULL"
			} else if p.curTokenIs(token.DEFAULT_KW) {
				actionValue = "SET DEFAULT"
			}
		}

		if action == "DELETE" {
			constraint.OnDelete = actionValue
		} else if action == "UPDATE" {
			constraint.OnUpdate = actionValue
		}
	}

	return constraint
}

func (p *Parser) parseInlineCheckConstraint() *ast.ColumnConstraint {
	constraint := &ast.ColumnConstraint{Type: ast.ConstraintCheck}
	p.expectPeek(token.LPAREN)
	p.nextToken()
	constraint.CheckExpression = p.parseExpression(LOWEST)
	p.expectPeek(token.RPAREN)
	return constraint
}

func (p *Parser) parseTableConstraint() *ast.TableConstraint {
	constraint := &ast.TableConstraint{Token: p.curToken}

	// Check for CONSTRAINT name
	if p.curTokenIs(token.CONSTRAINT) {
		p.nextToken()
		constraint.Name = p.curToken.Literal
		p.nextToken()
	}

	switch p.curToken.Type {
	case token.PRIMARY:
		constraint.Type = ast.ConstraintPrimaryKey
		p.expectPeek(token.KEY)
		if p.peekTokenIs(token.CLUSTERED) {
			p.nextToken()
			clustered := true
			constraint.IsClustered = &clustered
		} else if p.peekTokenIs(token.NONCLUSTERED) {
			p.nextToken()
			clustered := false
			constraint.IsClustered = &clustered
		}
		p.expectPeek(token.LPAREN)
		constraint.Columns = p.parseIndexColumns()
		// Parse optional WITH (index options)
		if p.peekTokenIs(token.WITH) {
			p.nextToken() // consume WITH
			if p.peekTokenIs(token.LPAREN) {
				p.nextToken() // consume (
				var opts []string
				depth := 1
				for depth > 0 && !p.curTokenIs(token.EOF) {
					p.nextToken()
					if p.curTokenIs(token.LPAREN) {
						depth++
						opts = append(opts, "(")
					} else if p.curTokenIs(token.RPAREN) {
						depth--
						if depth > 0 {
							opts = append(opts, ")")
						}
					} else {
						opts = append(opts, p.curToken.Literal)
					}
				}
				constraint.IndexOptions = strings.Join(opts, " ")
			}
		}

	case token.UNIQUE:
		constraint.Type = ast.ConstraintUnique
		if p.peekTokenIs(token.CLUSTERED) {
			p.nextToken()
			clustered := true
			constraint.IsClustered = &clustered
		} else if p.peekTokenIs(token.NONCLUSTERED) {
			p.nextToken()
			clustered := false
			constraint.IsClustered = &clustered
		}
		p.expectPeek(token.LPAREN)
		constraint.Columns = p.parseIndexColumns()
		// Parse optional WITH (index options)
		if p.peekTokenIs(token.WITH) {
			p.nextToken() // consume WITH
			if p.peekTokenIs(token.LPAREN) {
				p.nextToken() // consume (
				var opts []string
				depth := 1
				for depth > 0 && !p.curTokenIs(token.EOF) {
					p.nextToken()
					if p.curTokenIs(token.LPAREN) {
						depth++
						opts = append(opts, "(")
					} else if p.curTokenIs(token.RPAREN) {
						depth--
						if depth > 0 {
							opts = append(opts, ")")
						}
					} else {
						opts = append(opts, p.curToken.Literal)
					}
				}
				constraint.IndexOptions = strings.Join(opts, " ")
			}
		}

	case token.FOREIGN:
		constraint.Type = ast.ConstraintForeignKey
		p.expectPeek(token.KEY)
		p.expectPeek(token.LPAREN)
		constraint.Columns = p.parseIndexColumns()
		p.expectPeek(token.REFERENCES)
		p.nextToken()
		constraint.ReferencesTable = p.parseQualifiedIdentifier()
		p.expectPeek(token.LPAREN)
		constraint.ReferencesColumns = p.parseIdentifierList()

		// Parse ON DELETE / ON UPDATE
		for p.peekTokenIs(token.ON) {
			p.nextToken()
			p.nextToken()
			action := strings.ToUpper(p.curToken.Literal)
			p.nextToken()

			var actionValue string
			if p.curTokenIs(token.CASCADE) {
				actionValue = "CASCADE"
			} else if p.curTokenIs(token.RESTRICT) {
				actionValue = "RESTRICT"
			} else if strings.ToUpper(p.curToken.Literal) == "NO" {
				p.nextToken()
				actionValue = "NO ACTION"
			} else if p.curTokenIs(token.SET) {
				p.nextToken()
				if p.curTokenIs(token.NULL) {
					actionValue = "SET NULL"
				} else if p.curTokenIs(token.DEFAULT_KW) {
					actionValue = "SET DEFAULT"
				}
			}

			if action == "DELETE" {
				constraint.OnDelete = actionValue
			} else if action == "UPDATE" {
				constraint.OnUpdate = actionValue
			}
		}

	case token.CHECK:
		constraint.Type = ast.ConstraintCheck
		p.expectPeek(token.LPAREN)
		p.nextToken()
		constraint.CheckExpression = p.parseExpression(LOWEST)
		p.expectPeek(token.RPAREN)

	case token.DEFAULT_KW:
		constraint.Type = ast.ConstraintDefault
		// DEFAULT (expr) FOR column or DEFAULT expr FOR column
		if p.peekTokenIs(token.LPAREN) {
			p.nextToken() // consume (
			p.nextToken() // move to expression
			constraint.DefaultExpression = p.parseExpression(LOWEST)
			p.expectPeek(token.RPAREN)
		} else {
			p.nextToken()
			constraint.DefaultExpression = p.parseExpression(LOWEST)
		}
		// FOR column
		if p.peekTokenIs(token.FOR) {
			p.nextToken() // consume FOR
			p.nextToken() // move to column name
			constraint.ForColumn = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
		}

	case token.PERIOD:
		// PERIOD FOR SYSTEM_TIME (StartCol, EndCol)
		constraint.Type = ast.ConstraintPeriod
		if p.peekTokenIs(token.FOR) {
			p.nextToken() // consume FOR
		}
		if p.peekTokenIs(token.SYSTEM_TIME) {
			p.nextToken() // consume SYSTEM_TIME
		}
		p.expectPeek(token.LPAREN)
		constraint.Columns = p.parseIndexColumns()

	case token.INDEX:
		// INDEX ix_name [CLUSTERED|NONCLUSTERED] (columns)
		constraint.Type = ast.ConstraintIndex
		p.nextToken() // move to index name
		constraint.Name = p.curToken.Literal
		// Check for CLUSTERED or NONCLUSTERED
		if p.peekTokenIs(token.CLUSTERED) {
			p.nextToken()
			clustered := true
			constraint.IsClustered = &clustered
		} else if p.peekTokenIs(token.NONCLUSTERED) {
			p.nextToken()
			clustered := false
			constraint.IsClustered = &clustered
		}
		p.expectPeek(token.LPAREN)
		constraint.Columns = p.parseIndexColumns()
	}

	return constraint
}

func (p *Parser) parseIndexColumns() []*ast.IndexColumn {
	var columns []*ast.IndexColumn
	p.nextToken()

	col := &ast.IndexColumn{Name: &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}}
	if p.peekTokenIs(token.ASC) {
		p.nextToken()
	} else if p.peekTokenIs(token.DESC) {
		p.nextToken()
		col.Descending = true
	}
	columns = append(columns, col)

	for p.peekTokenIs(token.COMMA) {
		p.nextToken()
		p.nextToken()
		col = &ast.IndexColumn{Name: &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}}
		if p.peekTokenIs(token.ASC) {
			p.nextToken()
		} else if p.peekTokenIs(token.DESC) {
			p.nextToken()
			col.Descending = true
		}
		columns = append(columns, col)
	}

	p.expectPeek(token.RPAREN)
	return columns
}

func (p *Parser) parseDropStatement() ast.Statement {
	dropToken := p.curToken
	p.nextToken()

	switch p.curToken.Type {
	case token.TABLE:
		return p.parseDropTableStatement()
	case token.VIEW, token.FUNCTION, token.PROCEDURE, token.PROC, token.TRIGGER, token.SYNONYM, token.LOGIN, token.USER, token.ROLE, token.ASSEMBLY, token.CERTIFICATE, token.SCHEMA, token.TYPE_WARNING, token.DEFAULT_KW:
		return p.parseDropObjectStatement(dropToken)
	case token.INDEX:
		return p.parseDropIndexStatement(dropToken)
	case token.SEQUENCE:
		return p.parseDropSequenceStatement(dropToken)
	case token.STATISTICS:
		return p.parseDropStatisticsStatement(dropToken)
	case token.SYMMETRIC, token.ASYMMETRIC, token.MASTER:
		// DROP SYMMETRIC KEY, DROP ASYMMETRIC KEY, DROP MASTER KEY
		return p.parseDropKeyStatement(dropToken)
	case token.FULLTEXT:
		return p.parseDropFulltextStatement(dropToken)
	case token.RESOURCE:
		return p.parseDropResourcePoolStatement(dropToken)
	case token.WORKLOAD:
		return p.parseDropWorkloadGroupStatement(dropToken)
	case token.AVAILABILITY:
		return p.parseDropAvailabilityGroupStatement(dropToken)
	case token.MESSAGE:
		return p.parseDropServiceBrokerObject(dropToken, "MESSAGE TYPE")
	case token.CONTRACT:
		return p.parseDropServiceBrokerObject(dropToken, "CONTRACT")
	case token.QUEUE:
		return p.parseDropServiceBrokerObject(dropToken, "QUEUE")
	case token.SERVICE:
		return p.parseDropServiceBrokerObject(dropToken, "SERVICE")
	case token.SERVER:
		// DROP SERVER ROLE
		if p.peekTokenIs(token.ROLE) {
			p.nextToken() // move to ROLE
			return p.parseDropObjectStatement(dropToken)
		}
		return nil
	case token.DATABASE:
		// DROP DATABASE [IF EXISTS] name [, name, ...] or DROP DATABASE SCOPED CREDENTIAL
		// Check for SCOPED first
		if p.peekTokenIs(token.IDENT) && strings.ToUpper(p.peekToken.Literal) == "SCOPED" {
			p.nextToken() // move to SCOPED
			p.nextToken() // move past SCOPED
			if p.curTokenIs(token.IDENT) && strings.ToUpper(p.curToken.Literal) == "CREDENTIAL" {
				return p.parseDropObjectStatement(dropToken)
			}
		}
		// Regular DROP DATABASE
		return p.parseDropObjectStatement(dropToken)
	case token.IDENT:
		// DROP APPLICATION ROLE, DROP CREDENTIAL, or DROP RULE
		upper := strings.ToUpper(p.curToken.Literal)
		if upper == "APPLICATION" && p.peekTokenIs(token.ROLE) {
			p.nextToken() // move to ROLE
			return p.parseDropObjectStatement(dropToken)
		}
		if upper == "CREDENTIAL" || upper == "RULE" {
			return p.parseDropObjectStatement(dropToken)
		}
		return nil
	default:
		return nil
	}
}

func (p *Parser) parseDropObjectStatement(dropToken token.Token) ast.Statement {
	stmt := &ast.DropObjectStatement{Token: dropToken}
	stmt.ObjectType = p.curToken.Literal
	p.nextToken()

	// Check for IF EXISTS
	if p.curTokenIs(token.IF) {
		p.nextToken() // EXISTS
		if strings.ToUpper(p.curToken.Literal) == "EXISTS" {
			stmt.IfExists = true
			p.nextToken()
		}
	}

	// Parse object names
	stmt.Names = append(stmt.Names, p.parseQualifiedIdentifier())

	for p.peekTokenIs(token.COMMA) {
		p.nextToken()
		p.nextToken()
		stmt.Names = append(stmt.Names, p.parseQualifiedIdentifier())
	}

	// For DROP TRIGGER: check for ON DATABASE or ON ALL SERVER
	if strings.ToUpper(stmt.ObjectType) == "TRIGGER" {
		if p.peekTokenIs(token.ON) {
			p.nextToken() // consume ON
			if p.peekTokenIs(token.DATABASE) {
				p.nextToken()
				stmt.OnDatabase = true
			} else if p.peekTokenIs(token.ALL) {
				p.nextToken() // consume ALL
				if p.peekTokenIs(token.SERVER) {
					p.nextToken()
					stmt.OnAllServer = true
				}
			}
		}
	}

	return stmt
}

func (p *Parser) parseDropIndexStatement(dropToken token.Token) ast.Statement {
	stmt := &ast.DropIndexStatement{Token: dropToken}
	p.nextToken()

	// Check for IF EXISTS
	if p.curTokenIs(token.IF) {
		p.nextToken() // EXISTS
		if strings.ToUpper(p.curToken.Literal) == "EXISTS" {
			stmt.IfExists = true
			p.nextToken()
		}
	}

	// Parse index name
	stmt.Name = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}

	// ON table
	if !p.expectPeek(token.ON) {
		return nil
	}
	p.nextToken()
	stmt.Table = p.parseQualifiedIdentifier()

	// Check for additional indexes (comma-separated): IX_Name ON table, IX_Name2 ON table2
	for p.peekTokenIs(token.COMMA) {
		p.nextToken() // consume comma
		p.nextToken() // move to next index name
		// Just skip the additional indexes for now (the AST only stores one)
		// Skip index name
		p.nextToken() // consume ON
		if p.curTokenIs(token.ON) {
			p.nextToken()                // move to table name
			p.parseQualifiedIdentifier() // consume table name
		}
	}

	return stmt
}

func (p *Parser) parseDropSequenceStatement(dropToken token.Token) ast.Statement {
	stmt := &ast.DropSequenceStatement{Token: dropToken}
	p.nextToken() // move past SEQUENCE

	// Check for IF EXISTS
	if p.curTokenIs(token.IF) {
		p.nextToken() // EXISTS
		if strings.ToUpper(p.curToken.Literal) == "EXISTS" {
			stmt.IfExists = true
			p.nextToken()
		}
	}

	stmt.Name = p.parseQualifiedIdentifier()
	return stmt
}

func (p *Parser) parseDropTableStatement() ast.Statement {
	stmt := &ast.DropTableStatement{Token: p.curToken}
	p.nextToken()

	// Check for IF EXISTS
	if p.curTokenIs(token.IF) {
		p.nextToken() // EXISTS
		if strings.ToUpper(p.curToken.Literal) == "EXISTS" {
			stmt.IfExists = true
			p.nextToken()
		}
	}

	// Parse table names
	stmt.Tables = append(stmt.Tables, p.parseQualifiedIdentifier())

	for p.peekTokenIs(token.COMMA) {
		p.nextToken()
		p.nextToken()
		stmt.Tables = append(stmt.Tables, p.parseQualifiedIdentifier())
	}

	return stmt
}

func (p *Parser) parseTruncateStatement() ast.Statement {
	stmt := &ast.TruncateTableStatement{Token: p.curToken}

	if !p.expectPeek(token.TABLE) {
		return nil
	}
	p.nextToken()

	stmt.Table = p.parseQualifiedIdentifier()
	return stmt
}

// parseTruncateTableCompound handles TRUNCATE_TABLE compound token
func (p *Parser) parseTruncateTableCompound() ast.Statement {
	stmt := &ast.TruncateTableStatement{Token: p.curToken}
	p.nextToken() // move past TRUNCATE TABLE

	stmt.Table = p.parseQualifiedIdentifier()

	// Check for WITH_PARTITIONS
	if p.peekTokenIs(token.WITH_PARTITIONS) {
		p.nextToken() // consume WITH_PARTITIONS
		// Now we're at the inner ( after PARTITIONS
		if p.expectPeek(token.LPAREN) {
			p.nextToken() // move to first partition number
			stmt.Partitions = p.parsePartitionList()
			p.expectPeek(token.RPAREN) // closing ) of partition list
		}
		p.expectPeek(token.RPAREN) // closing ) of WITH (...)
	}

	return stmt
}

// parsePartitionList parses: 1, 2, 3 or 5 TO 10 or mixed
func (p *Parser) parsePartitionList() []ast.PartitionRange {
	var partitions []ast.PartitionRange

	for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
		if p.curTokenIs(token.INT) {
			start := p.parseIntLiteral()
			pr := ast.PartitionRange{Start: int(start)}

			// Check for TO (range)
			if p.peekTokenIs(token.TO) {
				p.nextToken() // consume TO
				p.nextToken() // move to end number
				if p.curTokenIs(token.INT) {
					end := p.parseIntLiteral()
					pr.End = int(end)
				}
			}
			partitions = append(partitions, pr)
		}

		if p.peekTokenIs(token.COMMA) {
			p.nextToken() // consume comma
			p.nextToken() // move to next number
		} else {
			break
		}
	}

	return partitions
}

func (p *Parser) parseIntLiteral() int64 {
	val, _ := strconv.ParseInt(p.curToken.Literal, 10, 64)
	return val
}

func (p *Parser) parseAlterStatement() ast.Statement {
	alterToken := p.curToken
	p.nextToken()

	switch p.curToken.Type {
	case token.TABLE:
		return p.parseAlterTableStatement()
	case token.VIEW:
		return p.parseAlterViewStatement(alterToken)
	case token.FUNCTION:
		return p.parseAlterFunctionStatement(alterToken)
	case token.TRIGGER:
		return p.parseAlterTriggerStatement(alterToken)
	case token.PROCEDURE, token.PROC:
		return p.parseAlterProcedureStatement(alterToken)
	case token.INDEX:
		return p.parseAlterIndexStatement(alterToken)
	case token.SEQUENCE:
		return p.parseAlterSequenceStatement(alterToken)
	case token.LOGIN:
		return p.parseAlterLoginStatement(alterToken)
	case token.USER:
		return p.parseAlterUserStatement(alterToken)
	case token.ROLE:
		return p.parseAlterRoleStatement(alterToken)
	case token.ASSEMBLY:
		return p.parseAlterAssemblyStatement(alterToken)
	case token.PARTITION:
		return p.parseAlterPartitionStatement(alterToken)
	case token.FULLTEXT:
		return p.parseAlterFulltextStatement(alterToken)
	case token.RESOURCE:
		return p.parseAlterResourceStatement(alterToken)
	case token.WORKLOAD:
		return p.parseAlterWorkloadGroupStatement(alterToken)
	case token.AVAILABILITY:
		return p.parseAlterAvailabilityGroupStatement(alterToken)
	case token.QUEUE:
		return p.parseAlterQueueStatement(alterToken)
	case token.DATABASE:
		return p.parseAlterDatabaseStatement(alterToken)
	case token.SERVER:
		// ALTER SERVER ROLE
		if p.peekTokenIs(token.ROLE) {
			p.nextToken() // move to ROLE
			return p.parseAlterServerRoleStatement(alterToken)
		}
		return nil
	case token.IDENT:
		// Handle ALTER APPLICATION ROLE
		upper := strings.ToUpper(p.curToken.Literal)
		if upper == "APPLICATION" && p.peekTokenIs(token.ROLE) {
			p.nextToken() // move to ROLE
			return p.parseAlterApplicationRoleStatement(alterToken)
		}
		return nil
	default:
		return nil
	}
}

func (p *Parser) parseAlterViewStatement(alterToken token.Token) ast.Statement {
	stmt := &ast.AlterViewStatement{Token: alterToken}
	p.nextToken() // move past VIEW

	stmt.Name = p.parseQualifiedIdentifier()

	// Optional column list
	if p.peekTokenIs(token.LPAREN) {
		p.nextToken()
		p.nextToken()
		for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
			stmt.Columns = append(stmt.Columns, &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal})
			if p.peekTokenIs(token.COMMA) {
				p.nextToken()
				p.nextToken()
			} else {
				break
			}
		}
		if p.peekTokenIs(token.RPAREN) {
			p.nextToken()
		}
	}

	// Optional WITH SCHEMABINDING, ENCRYPTION, VIEW_METADATA
	if p.peekTokenIs(token.WITH) {
		p.nextToken() // consume WITH
		// Skip options until AS
		for !p.peekTokenIs(token.AS) && !p.peekTokenIs(token.EOF) {
			p.nextToken()
			if p.peekTokenIs(token.COMMA) {
				p.nextToken()
			}
		}
	}

	// AS SELECT or AS WITH (CTE)
	if !p.expectPeek(token.AS) {
		return nil
	}
	p.nextToken()

	if p.curTokenIs(token.SELECT) {
		stmt.AsSelect = p.parseSelectStatement()
	} else if p.curTokenIs(token.WITH) {
		stmt.AsSelect = p.parseWithStatement()
	} else {
		return nil
	}
	return stmt
}

func (p *Parser) parseAlterFunctionStatement(alterToken token.Token) ast.Statement {
	stmt := &ast.AlterFunctionStatement{Token: alterToken}
	p.nextToken() // move past FUNCTION

	stmt.Name = p.parseQualifiedIdentifier()

	// Parameters
	if !p.expectPeek(token.LPAREN) {
		return nil
	}

	if !p.peekTokenIs(token.RPAREN) {
		p.nextToken()
		stmt.Parameters = p.parseParameterDefs()
	}

	// Consume RPAREN
	if !p.expectPeek(token.RPAREN) {
		return nil
	}

	// RETURNS
	if !p.expectPeek(token.RETURNS) {
		return nil
	}
	p.nextToken()

	// Check return type
	if p.curTokenIs(token.TABLE) {
		stmt.ReturnsTable = true
	} else if p.curTokenIs(token.VARIABLE) {
		stmt.TableVar = p.curToken.Literal
		p.nextToken() // TABLE
	} else {
		stmt.ReturnType = p.parseDataType()
	}

	// Skip to AS BEGIN...END
	for !p.curTokenIs(token.AS) && !p.curTokenIs(token.EOF) {
		p.nextToken()
	}
	if p.peekTokenIs(token.BEGIN) {
		p.nextToken()
		stmt.Body = p.parseBeginEndBlock()
	}

	return stmt
}

func (p *Parser) parseAlterTriggerStatement(alterToken token.Token) ast.Statement {
	stmt := &ast.AlterTriggerStatement{Token: alterToken}
	p.nextToken() // move past TRIGGER

	stmt.Name = p.parseQualifiedIdentifier()

	// ON table
	if !p.expectPeek(token.ON) {
		return nil
	}
	p.nextToken()
	stmt.Table = p.parseQualifiedIdentifier()

	// Trigger timing
	if p.peekTokenIs(token.AFTER) {
		p.nextToken()
		stmt.Timing = ast.TriggerAfter
	} else if p.peekTokenIs(token.INSTEAD) {
		p.nextToken()
		if p.peekTokenIs(token.OF) {
			p.nextToken()
		}
		stmt.Timing = ast.TriggerInsteadOf
	} else if p.peekTokenIs(token.FOR) {
		p.nextToken()
		stmt.Timing = ast.TriggerFor
	}
	p.nextToken()

	// Events
	for {
		stmt.Events = append(stmt.Events, p.curToken.Literal)
		if p.peekTokenIs(token.COMMA) {
			p.nextToken()
			p.nextToken()
		} else {
			break
		}
	}

	// AS BEGIN...END
	if p.peekTokenIs(token.AS) {
		p.nextToken()
	}
	if p.peekTokenIs(token.BEGIN) {
		p.nextToken()
		stmt.Body = p.parseBeginEndBlock()
	}

	return stmt
}

func (p *Parser) parseAlterProcedureStatement(alterToken token.Token) ast.Statement {
	stmt := &ast.AlterProcedureStatement{Token: alterToken}
	p.nextToken() // move past PROCEDURE/PROC

	stmt.Name = p.parseQualifiedIdentifier()

	// Parse parameters
	if p.peekTokenIs(token.VARIABLE) || p.peekTokenIs(token.LPAREN) {
		if p.peekTokenIs(token.LPAREN) {
			p.nextToken()
		}
		p.nextToken()
		stmt.Parameters = p.parseParameterDefs()
	}

	// Skip to AS
	for !p.curTokenIs(token.AS) && !p.curTokenIs(token.EOF) {
		p.nextToken()
	}
	p.nextToken()

	// Parse body
	if p.curTokenIs(token.BEGIN) {
		stmt.Body = p.parseBeginEndBlock()
	} else {
		// Single or multiple statements without BEGIN/END
		block := &ast.BeginEndBlock{Token: p.curToken}
		for !p.curTokenIs(token.EOF) && !p.curTokenIs(token.GO) {
			s := p.parseStatement()
			if s != nil {
				block.Statements = append(block.Statements, s)
			}
			if p.peekTokenIs(token.SEMICOLON) {
				p.nextToken()
			}
			if p.peekTokenIs(token.EOF) || p.peekTokenIs(token.GO) {
				break
			}
			p.nextToken()
		}
		stmt.Body = block
	}

	return stmt
}

func (p *Parser) parseAlterTableStatement() ast.Statement {
	stmt := &ast.AlterTableStatement{Token: p.curToken}
	p.nextToken()

	stmt.Table = p.parseQualifiedIdentifier()
	p.nextToken()

	// Handle WITH CHECK or WITH NOCHECK before actions (compound tokens)
	if p.curTokenIs(token.WITH_CHECK) {
		stmt.WithCheck = true
		p.nextToken()
	} else if p.curTokenIs(token.WITH_NOCHECK) {
		stmt.WithNoCheck = true
		p.nextToken()
	}

	// Also handle NOCHECK CONSTRAINT (without WITH) for disabling constraint checking
	if p.curTokenIs(token.NOCHECK) {
		p.nextToken()
		// Expect CONSTRAINT
		if p.curTokenIs(token.CONSTRAINT) {
			p.nextToken()
			// This is ALTER TABLE t NOCHECK CONSTRAINT constraint_name
			action := &ast.AlterTableAction{
				Type:           ast.AlterNoCheckConstraint,
				ConstraintName: p.curToken.Literal,
			}
			stmt.Actions = append(stmt.Actions, action)
			return stmt
		}
	}

	// Also handle CHECK CONSTRAINT for re-enabling constraint checking
	if p.curTokenIs(token.CHECK) {
		p.nextToken()
		if p.curTokenIs(token.CONSTRAINT) {
			p.nextToken()
			// This is ALTER TABLE t CHECK CONSTRAINT constraint_name
			action := &ast.AlterTableAction{
				Type:           ast.AlterCheckConstraint,
				ConstraintName: p.curToken.Literal,
			}
			stmt.Actions = append(stmt.Actions, action)
			return stmt
		}
	}

	// Parse actions
	for !p.curTokenIs(token.EOF) && !p.curTokenIs(token.SEMICOLON) && !p.curTokenIs(token.GO) {
		action := p.parseAlterTableAction()
		if action != nil {
			stmt.Actions = append(stmt.Actions, action)
		}

		if p.peekTokenIs(token.COMMA) {
			p.nextToken()
			p.nextToken()
		} else {
			break
		}
	}

	return stmt
}

func (p *Parser) parseAlterTableAction() *ast.AlterTableAction {
	action := &ast.AlterTableAction{}

	switch p.curToken.Type {
	case token.ADD:
		p.nextToken()
		// Could be ADD column or ADD CONSTRAINT
		if p.curTokenIs(token.CONSTRAINT) || p.curTokenIs(token.PRIMARY) ||
			p.curTokenIs(token.FOREIGN) || p.curTokenIs(token.UNIQUE) || p.curTokenIs(token.CHECK) {
			action.Type = ast.AlterAddConstraint
			action.Constraint = p.parseTableConstraint()
		} else {
			action.Type = ast.AlterAddColumn
			// Parse first column
			col := p.parseColumnDefinition()
			action.Columns = append(action.Columns, col)

			// Check for additional columns (comma-separated)
			for p.peekTokenIs(token.COMMA) {
				p.nextToken() // consume comma
				p.nextToken() // move to next column name
				// Make sure we're not hitting a new ALTER TABLE action keyword
				if p.curTokenIs(token.ADD) || p.curTokenIs(token.DROP) || p.curTokenIs(token.ALTER) ||
					p.curTokenIs(token.ENABLE) || p.curTokenIs(token.DISABLE) || p.curTokenIs(token.SET) ||
					p.curTokenIs(token.CONSTRAINT) || p.curTokenIs(token.PRIMARY) ||
					p.curTokenIs(token.FOREIGN) || p.curTokenIs(token.UNIQUE) || p.curTokenIs(token.CHECK) {
					// This comma was separating actions, not columns - back up
					break
				}
				col := p.parseColumnDefinition()
				action.Columns = append(action.Columns, col)
			}
			// For backwards compatibility, set Column to first column
			if len(action.Columns) > 0 {
				action.Column = action.Columns[0]
			}
		}

	case token.DROP:
		p.nextToken()
		if p.curTokenIs(token.COLUMN) {
			action.Type = ast.AlterDropColumn
			p.nextToken()
			action.ColumnName = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
		} else if p.curTokenIs(token.CONSTRAINT) {
			action.Type = ast.AlterDropConstraint
			p.nextToken()
			action.ConstraintName = p.curToken.Literal
		}

	case token.ALTER:
		p.nextToken()
		if p.curTokenIs(token.COLUMN) {
			action.Type = ast.AlterAlterColumn
			p.nextToken()
			action.ColumnName = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
			p.nextToken()
			action.NewDataType = p.parseDataType()
		}

	case token.ENABLE:
		action.Type = ast.AlterEnableTrigger
		p.nextToken() // move past ENABLE
		if p.curTokenIs(token.TRIGGER) {
			p.nextToken() // move past TRIGGER
			if p.curTokenIs(token.ALL) {
				action.AllTriggers = true
			} else {
				action.TriggerName = p.curToken.Literal
			}
		}

	case token.DISABLE:
		action.Type = ast.AlterDisableTrigger
		p.nextToken() // move past DISABLE
		if p.curTokenIs(token.TRIGGER) {
			p.nextToken() // move past TRIGGER
			if p.curTokenIs(token.ALL) {
				action.AllTriggers = true
			} else {
				action.TriggerName = p.curToken.Literal
			}
		}

	case token.SET:
		action.Type = ast.AlterSetOption
		action.Options = make(map[string]string)
		p.nextToken() // move past SET
		if p.curTokenIs(token.LPAREN) {
			p.nextToken() // move past (
			// Parse option = value pairs
			for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
				optionName := p.curToken.Literal
				p.nextToken() // move past option name
				if p.curTokenIs(token.EQ) || (p.curToken.Type == token.IDENT && p.curToken.Literal == "=") {
					p.nextToken() // move past =
				}
				optionValue := p.curToken.Literal
				action.Options[optionName] = optionValue
				p.nextToken()
				if p.curTokenIs(token.COMMA) {
					p.nextToken()
				}
			}
		}

	case token.NOCHECK:
		action.Type = ast.AlterNoCheckConstraint
		p.nextToken() // move past NOCHECK
		if p.curTokenIs(token.CONSTRAINT) {
			p.nextToken() // move past CONSTRAINT
			if p.curTokenIs(token.ALL) {
				action.AllConstraints = true
			} else {
				action.ConstraintName = p.curToken.Literal
			}
		}

	case token.CHECK:
		// CHECK CONSTRAINT name - different from ADD CHECK constraint
		action.Type = ast.AlterCheckConstraint
		p.nextToken() // move past CHECK
		if p.curTokenIs(token.CONSTRAINT) {
			p.nextToken() // move past CONSTRAINT
			if p.curTokenIs(token.ALL) {
				action.AllConstraints = true
			} else {
				action.ConstraintName = p.curToken.Literal
			}
		}

	case token.IDENT:
		upper := strings.ToUpper(p.curToken.Literal)
		if upper == "SWITCH" {
			action.Type = ast.AlterSwitch
			// Collect remaining tokens until end of statement
			var opts []string
			for !p.peekTokenIs(token.SEMICOLON) && !p.peekTokenIs(token.GO) && !p.peekTokenIs(token.EOF) {
				p.nextToken()
				opts = append(opts, p.curToken.Literal)
			}
			action.RawOptions = strings.Join(opts, " ")
		} else {
			return nil
		}

	case token.REBUILD:
		action.Type = ast.AlterRebuild
		// Collect optional WITH clause and other options
		var opts []string
		for !p.peekTokenIs(token.SEMICOLON) && !p.peekTokenIs(token.GO) && !p.peekTokenIs(token.EOF) {
			p.nextToken()
			opts = append(opts, p.curToken.Literal)
		}
		action.RawOptions = strings.Join(opts, " ")

	default:
		return nil
	}

	return action
}

// -----------------------------------------------------------------------------
// Stage 5: Additional DDL Parsers
// -----------------------------------------------------------------------------

func (p *Parser) parseCreateViewStatement(createToken token.Token) ast.Statement {
	stmt := &ast.CreateViewStatement{Token: createToken}
	p.nextToken() // move past VIEW

	stmt.Name = p.parseQualifiedIdentifier()

	// Optional column list
	if p.peekTokenIs(token.LPAREN) {
		p.nextToken()
		p.nextToken()
		for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
			stmt.Columns = append(stmt.Columns, &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal})
			if p.peekTokenIs(token.COMMA) {
				p.nextToken()
				p.nextToken()
			} else {
				break
			}
		}
		if p.peekTokenIs(token.RPAREN) {
			p.nextToken()
		}
	}

	// WITH options
	if p.peekTokenIs(token.WITH) {
		p.nextToken()
		p.nextToken()
		for {
			stmt.Options = append(stmt.Options, p.curToken.Literal)
			if p.peekTokenIs(token.COMMA) {
				p.nextToken()
				p.nextToken()
			} else {
				break
			}
		}
	}

	// AS SELECT or AS WITH (CTE)
	if !p.expectPeek(token.AS) {
		return nil
	}
	p.nextToken()

	if p.curTokenIs(token.SELECT) {
		stmt.AsSelect = p.parseSelectStatement()
	} else if p.curTokenIs(token.WITH) {
		stmt.AsSelect = p.parseWithStatement()
	} else {
		return nil
	}

	// WITH CHECK OPTION (at the end)
	if p.peekTokenIs(token.WITH) {
		p.nextToken() // consume WITH
		if p.peekTokenIs(token.CHECK) {
			p.nextToken() // consume CHECK
			if p.peekTokenIs(token.OPTION) {
				p.nextToken() // consume OPTION
				stmt.CheckOption = true
			}
		}
	}

	return stmt
}

func (p *Parser) parseCreateIndexStatement(createToken token.Token, isUnique bool, isClustered *bool) ast.Statement {
	stmt := &ast.CreateIndexStatement{Token: createToken}
	stmt.IsUnique = isUnique
	stmt.IsClustered = isClustered
	p.nextToken() // move past INDEX

	// Index name
	stmt.Name = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}

	// ON table
	if !p.expectPeek(token.ON) {
		return nil
	}
	p.nextToken()
	stmt.Table = p.parseQualifiedIdentifier()

	// Column list (optional for clustered columnstore indexes)
	if p.peekTokenIs(token.LPAREN) {
		p.nextToken() // consume (
		p.nextToken()

		for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
			col := &ast.IndexColumn{}
			col.Name = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
			if p.peekTokenIs(token.ASC) {
				p.nextToken()
				col.Descending = false
			} else if p.peekTokenIs(token.DESC) {
				p.nextToken()
				col.Descending = true
			}
			stmt.Columns = append(stmt.Columns, col)

			if p.peekTokenIs(token.COMMA) {
				p.nextToken()
				p.nextToken()
			} else {
				break
			}
		}
		if p.peekTokenIs(token.RPAREN) {
			p.nextToken()
		}
	}

	// INCLUDE columns
	if p.peekTokenIs(token.INCLUDE) {
		p.nextToken()
		if !p.expectPeek(token.LPAREN) {
			return nil
		}
		p.nextToken()
		for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
			stmt.IncludeColumns = append(stmt.IncludeColumns, &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal})
			if p.peekTokenIs(token.COMMA) {
				p.nextToken()
				p.nextToken()
			} else {
				break
			}
		}
		if p.peekTokenIs(token.RPAREN) {
			p.nextToken()
		}
	}

	// WITH clause (FILLFACTOR, PAD_INDEX, etc.)
	if p.peekTokenIs(token.WITH) {
		p.nextToken() // consume WITH
		if p.peekTokenIs(token.LPAREN) {
			p.nextToken() // consume (
			// Skip options until matching )
			depth := 1
			for depth > 0 && !p.curTokenIs(token.EOF) {
				p.nextToken()
				if p.curTokenIs(token.LPAREN) {
					depth++
				} else if p.curTokenIs(token.RPAREN) {
					depth--
				}
			}
		}
	}

	// WHERE clause (filtered index)
	if p.peekTokenIs(token.WHERE) {
		p.nextToken()
		p.nextToken()
		stmt.Where = p.parseExpression(LOWEST)
	}

	// ON [filegroup] or ON PartitionScheme(column) - note: this is a second ON after the column list
	if p.peekTokenIs(token.ON) {
		p.nextToken() // consume ON
		p.nextToken() // move to filegroup/partition scheme name
		stmt.Filegroup = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
		// Check for partition scheme column: ON PartitionScheme(column)
		if p.peekTokenIs(token.LPAREN) {
			p.nextToken() // consume (
			p.nextToken() // move to column name
			// Skip to closing paren
			for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
				p.nextToken()
			}
		}
	}

	// USING clause (for spatial indexes: USING GEOGRAPHY_AUTO_GRID)
	if p.peekTokenIs(token.USING) {
		// Skip USING options until WITH or end of statement
		for !p.peekTokenIs(token.WITH) && !p.peekTokenIs(token.SEMICOLON) && !p.peekTokenIs(token.GO) && !p.peekTokenIs(token.EOF) {
			p.nextToken()
		}
		// Parse optional WITH clause for spatial indexes
		if p.peekTokenIs(token.WITH) {
			p.nextToken() // consume WITH
			if p.peekTokenIs(token.LPAREN) {
				p.nextToken() // consume (
				// Skip options until matching )
				depth := 1
				for depth > 0 && !p.curTokenIs(token.EOF) {
					p.nextToken()
					if p.curTokenIs(token.LPAREN) {
						depth++
					} else if p.curTokenIs(token.RPAREN) {
						depth--
					}
				}
			}
		}
	}

	return stmt
}

func (p *Parser) parseCreateXmlIndexStatement(createToken token.Token, isPrimary bool) ast.Statement {
	stmt := &ast.CreateXmlIndexStatement{Token: createToken, IsPrimary: isPrimary}
	p.nextToken() // move past INDEX

	// Index name
	stmt.Name = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}

	// ON table
	if !p.expectPeek(token.ON) {
		return nil
	}
	p.nextToken()
	stmt.Table = p.parseQualifiedIdentifier()

	// (column)
	if !p.expectPeek(token.LPAREN) {
		return nil
	}
	p.nextToken()
	stmt.Column = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
	p.expectPeek(token.RPAREN)

	// USING XML INDEX ... FOR PATH/VALUE/PROPERTY (secondary indexes)
	if p.peekTokenIs(token.USING) {
		// Skip USING XML INDEX name FOR type
		for !p.peekTokenIs(token.SEMICOLON) && !p.peekTokenIs(token.GO) && !p.peekTokenIs(token.EOF) {
			p.nextToken()
		}
	}

	return stmt
}

func (p *Parser) parseCreateDefaultStatement(createToken token.Token) ast.Statement {
	stmt := &ast.CreateDefaultStatement{Token: createToken}
	p.nextToken() // move past DEFAULT

	stmt.Name = p.parseQualifiedIdentifier()

	if !p.expectPeek(token.AS) {
		return nil
	}
	p.nextToken()

	stmt.Value = p.parseExpression(LOWEST)

	return stmt
}

// parseCreateRuleStatement handles CREATE_RULE compound token
func (p *Parser) parseCreateRuleStatement() ast.Statement {
	stmt := &ast.CreateRuleStatement{Token: p.curToken}
	p.nextToken() // move past CREATE RULE

	stmt.Name = p.parseQualifiedIdentifier()

	if !p.expectPeek(token.AS) {
		return nil
	}
	p.nextToken()

	stmt.Condition = p.parseExpression(LOWEST)

	return stmt
}

func (p *Parser) parseCreateFunctionStatement(createToken token.Token) ast.Statement {
	stmt := &ast.CreateFunctionStatement{Token: createToken}
	p.nextToken() // move past FUNCTION

	stmt.Name = p.parseQualifiedIdentifier()

	// Parameters
	if !p.expectPeek(token.LPAREN) {
		return nil
	}

	if !p.peekTokenIs(token.RPAREN) {
		p.nextToken()
		stmt.Parameters = p.parseParameterDefs()
	}

	// Consume RPAREN
	if !p.expectPeek(token.RPAREN) {
		return nil
	}

	// RETURNS
	if !p.expectPeek(token.RETURNS) {
		return nil
	}
	p.nextToken()

	// Check return type
	if p.curTokenIs(token.TABLE) {
		stmt.ReturnsTable = true
		// Check for WITH clause (e.g., WITH EXECUTE AS CALLER)
		if p.peekTokenIs(token.WITH) {
			p.nextToken() // consume WITH
			// Skip WITH options - handle EXECUTE AS specially
			for !p.curTokenIs(token.EOF) {
				// If we see AS next and it's NOT after EXECUTE, we're at body start
				if p.peekTokenIs(token.AS) && !p.curTokenIs(token.EXECUTE) {
					break
				}
				p.nextToken()
			}
		}
		// Check for inline vs multi-statement TVF
		if p.peekTokenIs(token.AS) {
			// Inline TVF: RETURNS TABLE AS RETURN (SELECT...) or RETURNS TABLE AS RETURN SELECT...
			p.nextToken() // AS
			if !p.expectPeek(token.RETURN) {
				return nil
			}
			p.nextToken() // move past RETURN
			// Handle optional parentheses around the SELECT
			hasParens := false
			if p.curTokenIs(token.LPAREN) {
				hasParens = true
				p.nextToken() // move past (
			}
			if p.curTokenIs(token.SELECT) {
				selectStmt := p.parseSelectStatement()
				stmt.AsReturn = selectStmt
			}
			// Consume closing paren if we had opening paren
			if hasParens && p.peekTokenIs(token.RPAREN) {
				p.nextToken()
			}
		}
	} else if p.curTokenIs(token.VARIABLE) {
		// Multi-statement TVF: RETURNS @var TABLE (...)
		stmt.TableVar = p.curToken.Literal
		p.nextToken() // TABLE
		if p.curTokenIs(token.TABLE) {
			// Parse table definition - parseTableTypeDefinition expects peekToken to be LPAREN
			stmt.TableDef = p.parseTableTypeDefinition()
		}
	} else {
		// Scalar function
		stmt.ReturnType = p.parseDataType()
	}

	// WITH options (may include EXECUTE AS ...)
	if p.peekTokenIs(token.WITH) {
		p.nextToken() // consume WITH
		// Skip WITH options - handle EXECUTE AS specially
		for !p.curTokenIs(token.EOF) {
			// If we see AS next and it's NOT after EXECUTE, we're at body start
			if p.peekTokenIs(token.AS) && !p.curTokenIs(token.EXECUTE) {
				break
			}
			// Store non-EXECUTE options
			if !p.curTokenIs(token.EXECUTE) && !p.curTokenIs(token.AS) && !p.curTokenIs(token.WITH) {
				stmt.Options = append(stmt.Options, p.curToken.Literal)
			}
			p.nextToken()
		}
	}

	// AS BEGIN...END or AS BEGIN ATOMIC...END
	if p.peekTokenIs(token.AS) {
		p.nextToken()
	}
	if p.peekTokenIs(token.BEGIN) {
		p.nextToken()
		stmt.Body = p.parseBeginEndBlock()
	} else if p.peekTokenIs(token.BEGIN_ATOMIC) {
		p.nextToken()
		stmt.Body = p.parseBeginAtomicBlock()
	}

	return stmt
}

func (p *Parser) parseCreateTriggerStatement(createToken token.Token) ast.Statement {
	stmt := &ast.CreateTriggerStatement{Token: createToken}
	p.nextToken() // move past TRIGGER

	stmt.Name = p.parseQualifiedIdentifier()

	// ON table or ON DATABASE or ON ALL SERVER
	if !p.expectPeek(token.ON) {
		return nil
	}
	p.nextToken()

	// Check for DDL trigger scope
	if p.curTokenIs(token.DATABASE) {
		stmt.OnDatabase = true
	} else if p.curTokenIs(token.ALL) {
		// ON ALL SERVER
		stmt.OnAllServer = true
		if p.peekTokenIs(token.SERVER) {
			p.nextToken() // consume SERVER
		}
	} else {
		stmt.Table = p.parseQualifiedIdentifier()
	}

	// Check for WITH options (ENCRYPTION, EXECUTE AS, etc.) before timing
	if p.peekTokenIs(token.WITH) {
		p.nextToken() // consume WITH
		p.nextToken() // move to option
		for {
			if p.curTokenIs(token.ENCRYPTION) {
				stmt.Options = append(stmt.Options, "ENCRYPTION")
			} else if p.curToken.Type == token.IDENT && strings.ToUpper(p.curToken.Literal) == "ENCRYPTION" {
				stmt.Options = append(stmt.Options, "ENCRYPTION")
			} else if p.curTokenIs(token.EXECUTE) || p.curToken.Literal == "EXECUTE" {
				// EXECUTE AS clause - skip for now
				for !p.peekTokenIs(token.AFTER) && !p.peekTokenIs(token.INSTEAD) && !p.peekTokenIs(token.FOR) && !p.peekTokenIs(token.EOF) {
					p.nextToken()
				}
				break
			}
			if p.peekTokenIs(token.COMMA) {
				p.nextToken()
				p.nextToken()
			} else {
				break
			}
		}
	}

	// Trigger timing: AFTER, INSTEAD OF, FOR
	if p.peekTokenIs(token.AFTER) {
		p.nextToken()
		stmt.Timing = ast.TriggerAfter
	} else if p.peekTokenIs(token.INSTEAD) {
		p.nextToken()
		if p.peekTokenIs(token.OF) {
			p.nextToken()
		}
		stmt.Timing = ast.TriggerInsteadOf
	} else if p.peekTokenIs(token.FOR) {
		p.nextToken()
		stmt.Timing = ast.TriggerFor
	}
	p.nextToken()

	// Events: INSERT, UPDATE, DELETE
	for {
		stmt.Events = append(stmt.Events, p.curToken.Literal)
		if p.peekTokenIs(token.COMMA) {
			p.nextToken()
			p.nextToken()
		} else {
			break
		}
	}

	// NOT FOR REPLICATION
	if p.peekTokenIs(token.NOT) {
		p.nextToken() // consume NOT
		if p.peekTokenIs(token.FOR) {
			p.nextToken() // consume FOR
			if p.peekTokenIs(token.REPLICATION) {
				p.nextToken() // consume REPLICATION
				stmt.NotForReplication = true
			}
		}
	}

	// AS BEGIN...END
	if p.peekTokenIs(token.AS) {
		p.nextToken()
	}
	if p.peekTokenIs(token.BEGIN) {
		p.nextToken()
		stmt.Body = p.parseBeginEndBlock()
	}

	return stmt
}

// parseCreateTypeStatement parses CREATE TYPE name FROM base_type or CREATE TYPE name AS TABLE (...)
func (p *Parser) parseCreateTypeStatement(createToken token.Token) ast.Statement {
	stmt := &ast.CreateTypeStatement{Token: createToken}
	p.nextToken() // move past TYPE

	stmt.Name = p.parseQualifiedIdentifier()

	// Check for AS TABLE (table type) or FROM (alias type)
	if p.peekTokenIs(token.AS) {
		p.nextToken() // consume AS
		if p.peekTokenIs(token.TABLE) {
			p.nextToken() // consume TABLE
			stmt.IsTableType = true
			// Parse table definition - parseTableTypeDefinition expects to call expectPeek(LPAREN)
			stmt.TableDef = p.parseTableTypeDefinition()

			// Check for WITH clause (e.g., WITH (MEMORY_OPTIMIZED = ON))
			if p.peekTokenIs(token.WITH) {
				p.nextToken() // consume WITH
				if p.peekTokenIs(token.LPAREN) {
					p.nextToken() // consume (
					// Skip to matching )
					depth := 1
					for depth > 0 && !p.curTokenIs(token.EOF) {
						p.nextToken()
						if p.curTokenIs(token.LPAREN) {
							depth++
						} else if p.curTokenIs(token.RPAREN) {
							depth--
						}
					}
				}
			}
		}
	} else if p.peekTokenIs(token.FROM) {
		p.nextToken() // consume FROM
		p.nextToken()
		stmt.BaseType = p.parseDataType()

		// Parse NULL/NOT NULL
		if p.peekTokenIs(token.NOT) {
			p.nextToken()
			if p.peekTokenIs(token.NULL) {
				p.nextToken()
				notNull := false
				stmt.Nullable = &notNull
			}
		} else if p.peekTokenIs(token.NULL) {
			p.nextToken()
			nullable := true
			stmt.Nullable = &nullable
		}
	}

	return stmt
}

func (p *Parser) parseCreateSynonymStatement(createToken token.Token) ast.Statement {
	stmt := &ast.CreateSynonymStatement{Token: createToken}
	p.nextToken() // move past SYNONYM

	stmt.Name = p.parseQualifiedIdentifier()

	// Expect FOR
	if p.peekTokenIs(token.FOR) {
		p.nextToken() // consume FOR
		p.nextToken() // move to target
		stmt.Target = p.parseQualifiedIdentifier()
	}

	return stmt
}

func (p *Parser) parseCreateXmlSchemaCollectionStatement(createToken token.Token) ast.Statement {
	stmt := &ast.CreateXmlSchemaCollectionStatement{Token: createToken}
	p.nextToken() // move past XML SCHEMA COLLECTION

	stmt.Name = p.parseQualifiedIdentifier()

	// AS
	if !p.expectPeek(token.AS) {
		return nil
	}
	p.nextToken() // move past AS

	// Consume the schema content (string literal, typically N'...')
	if p.curTokenIs(token.STRING) || p.curTokenIs(token.NSTRING) {
		stmt.SchemaData = p.curToken.Literal
	} else {
		// Try to consume any expression as the schema data
		expr := p.parseExpression(LOWEST)
		if expr != nil {
			stmt.SchemaData = expr.String()
		}
	}

	return stmt
}

func (p *Parser) parseCreateSequenceStatement(createToken token.Token) ast.Statement {
	stmt := &ast.CreateSequenceStatement{Token: createToken}
	p.nextToken() // move past SEQUENCE

	stmt.Name = p.parseQualifiedIdentifier()

	// Parse sequence options
	for !p.peekTokenIs(token.SEMICOLON) && !p.peekTokenIs(token.EOF) && !p.peekTokenIs(token.GO) {
		p.nextToken()

		switch p.curToken.Type {
		case token.AS:
			p.nextToken()
			stmt.DataType = p.parseDataType()
		case token.START:
			if p.peekTokenIs(token.WITH) {
				p.nextToken() // consume WITH
			}
			p.nextToken()
			stmt.StartWith = p.parseExpression(LOWEST)
		case token.INCREMENT:
			if p.peekTokenIs(token.BY) {
				p.nextToken() // consume BY
			}
			p.nextToken()
			stmt.IncrementBy = p.parseExpression(LOWEST)
		case token.MINVALUE:
			p.nextToken()
			stmt.MinValue = p.parseExpression(LOWEST)
		case token.MAXVALUE:
			p.nextToken()
			stmt.MaxValue = p.parseExpression(LOWEST)
		case token.CYCLE:
			stmt.Cycle = true
		case token.CACHE_KW:
			p.nextToken()
			stmt.Cache = p.parseExpression(LOWEST)
		case token.IDENT:
			if strings.ToUpper(p.curToken.Literal) == "NO" {
				p.nextToken()
				switch p.curToken.Type {
				case token.MINVALUE:
					stmt.NoMinValue = true
				case token.MAXVALUE:
					stmt.NoMaxValue = true
				case token.CYCLE:
					stmt.NoCycle = true
				case token.CACHE_KW:
					stmt.NoCache = true
				}
			} else {
				return stmt
			}
		default:
			// Unknown option, stop parsing
			return stmt
		}
	}

	return stmt
}

func (p *Parser) parseAlterDatabaseStatement(alterToken token.Token) ast.Statement {
	stmt := &ast.AlterDatabaseStatement{Token: alterToken}
	p.nextToken() // move past DATABASE

	stmt.Name = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}

	// Collect remaining tokens as options until statement end
	var options []string
	for !p.peekTokenIs(token.SEMICOLON) && !p.peekTokenIs(token.GO) && !p.peekTokenIs(token.EOF) {
		p.nextToken()
		options = append(options, p.curToken.Literal)
	}
	stmt.Options = strings.Join(options, " ")

	return stmt
}

func (p *Parser) parseAlterSequenceStatement(alterToken token.Token) ast.Statement {
	stmt := &ast.AlterSequenceStatement{Token: alterToken}
	p.nextToken() // move past SEQUENCE

	stmt.Name = p.parseQualifiedIdentifier()

	// Parse sequence options
	for !p.peekTokenIs(token.SEMICOLON) && !p.peekTokenIs(token.EOF) && !p.peekTokenIs(token.GO) {
		p.nextToken()

		switch p.curToken.Type {
		case token.IDENT:
			upperLit := strings.ToUpper(p.curToken.Literal)
			if upperLit == "RESTART" {
				if p.peekTokenIs(token.WITH) {
					p.nextToken() // consume WITH
				}
				p.nextToken()
				stmt.RestartWith = p.parseExpression(LOWEST)
			} else if upperLit == "NO" {
				p.nextToken()
				switch p.curToken.Type {
				case token.MINVALUE:
					stmt.NoMinValue = true
				case token.MAXVALUE:
					stmt.NoMaxValue = true
				case token.CYCLE:
					stmt.NoCycle = true
				case token.CACHE_KW:
					stmt.NoCache = true
				}
			} else {
				return stmt
			}
		case token.INCREMENT:
			if p.peekTokenIs(token.BY) {
				p.nextToken() // consume BY
			}
			p.nextToken()
			stmt.IncrementBy = p.parseExpression(LOWEST)
		case token.MINVALUE:
			p.nextToken()
			stmt.MinValue = p.parseExpression(LOWEST)
		case token.MAXVALUE:
			p.nextToken()
			stmt.MaxValue = p.parseExpression(LOWEST)
		case token.CYCLE:
			stmt.Cycle = true
		case token.CACHE_KW:
			p.nextToken()
			stmt.Cache = p.parseExpression(LOWEST)
		default:
			return stmt
		}
	}

	return stmt
}

func (p *Parser) parseCreateStatisticsStatement(createToken token.Token) ast.Statement {
	stmt := &ast.CreateStatisticsStatement{Token: createToken}
	p.nextToken() // move past STATISTICS

	stmt.Name = p.curToken.Literal
	p.nextToken() // move past stats name

	// Expect ON
	if p.curTokenIs(token.ON) {
		p.nextToken()
		stmt.Table = p.parseQualifiedIdentifier()
	}

	// Parse column list
	if p.peekTokenIs(token.LPAREN) {
		p.nextToken() // consume (
		p.nextToken() // move to first column
		for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
			stmt.Columns = append(stmt.Columns, &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal})
			if p.peekTokenIs(token.COMMA) {
				p.nextToken() // consume comma
				p.nextToken() // move to next column
			} else {
				break
			}
		}
		p.expectPeek(token.RPAREN)
	}

	// Parse WITH options
	if p.peekTokenIs(token.WITH) {
		p.nextToken() // consume WITH
		stmt.WithOptions = p.parseStatisticsWithOptions()
	}

	return stmt
}

func (p *Parser) parseStatisticsWithOptions() []string {
	var options []string
	p.nextToken()

	for !p.curTokenIs(token.SEMICOLON) && !p.curTokenIs(token.EOF) && !p.curTokenIs(token.GO) {
		opt := strings.ToUpper(p.curToken.Literal)

		// Handle multi-word options like SAMPLE n PERCENT
		if opt == "SAMPLE" {
			p.nextToken() // get number
			opt += " " + p.curToken.Literal
			if p.peekTokenIs(token.PERCENT_KW) || (p.peekTokenIs(token.IDENT) && strings.ToUpper(p.peekToken.Literal) == "PERCENT") {
				p.nextToken()
				opt += " PERCENT"
			} else if p.peekTokenIs(token.ROWS) {
				p.nextToken()
				opt += " ROWS"
			}
		}

		options = append(options, opt)

		if p.peekTokenIs(token.COMMA) {
			p.nextToken() // consume comma
			p.nextToken() // move to next option
		} else {
			break
		}
	}

	return options
}

func (p *Parser) parseUpdateStatisticsStatement() ast.Statement {
	stmt := &ast.UpdateStatisticsStatement{Token: p.curToken}
	p.nextToken() // move past STATISTICS

	stmt.Table = p.parseQualifiedIdentifier()

	// Optional stats name
	if p.peekTokenIs(token.IDENT) {
		p.nextToken()
		stmt.StatsName = p.curToken.Literal
	}

	// Parse WITH options
	if p.peekTokenIs(token.WITH) {
		p.nextToken() // consume WITH
		stmt.WithOptions = p.parseStatisticsWithOptions()
	}

	return stmt
}

func (p *Parser) parseDropStatisticsStatement(dropToken token.Token) ast.Statement {
	stmt := &ast.DropStatisticsStatement{Token: dropToken}

	p.nextToken() // move past STATISTICS

	// Parse table.stats_name format (can be schema.table.stats_name)
	for {
		var parts []string
		parts = append(parts, p.curToken.Literal)
		for p.peekTokenIs(token.DOT) {
			p.nextToken() // consume .
			p.nextToken() // move to next part
			parts = append(parts, p.curToken.Literal)
		}
		stmt.Names = append(stmt.Names, strings.Join(parts, "."))

		if p.peekTokenIs(token.COMMA) {
			p.nextToken() // consume comma
			p.nextToken() // move to next
		} else {
			break
		}
	}

	return stmt
}

func (p *Parser) parseDbccStatement() ast.Statement {
	stmt := &ast.DbccStatement{Token: p.curToken}
	p.nextToken() // move past DBCC

	stmt.Command = strings.ToUpper(p.curToken.Literal)

	// Parse arguments in parentheses
	if p.peekTokenIs(token.LPAREN) {
		p.nextToken() // consume (
		p.nextToken() // move to first arg

		for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
			stmt.Arguments = append(stmt.Arguments, p.parseExpression(LOWEST))
			if p.peekTokenIs(token.COMMA) {
				p.nextToken() // consume comma
				p.nextToken() // move to next arg
			} else {
				break
			}
		}
		p.expectPeek(token.RPAREN)
	}

	// Parse WITH options
	if p.peekTokenIs(token.WITH) {
		p.nextToken() // consume WITH
		p.nextToken() // move to first option

		for !p.curTokenIs(token.SEMICOLON) && !p.curTokenIs(token.EOF) && !p.curTokenIs(token.GO) {
			stmt.WithOptions = append(stmt.WithOptions, strings.ToUpper(p.curToken.Literal))
			if p.peekTokenIs(token.COMMA) {
				p.nextToken() // consume comma
				p.nextToken() // move to next option
			} else {
				break
			}
		}
	}

	return stmt
}

// parseGrantStatement parses GRANT permission ON object TO principal
func (p *Parser) parseGrantStatement() ast.Statement {
	stmt := &ast.GrantStatement{Token: p.curToken}
	p.nextToken() // move past GRANT

	// Parse permissions (can be multiple separated by commas)
	stmt.Permissions = p.parsePermissionList()

	// Parse ON clause
	if p.curTokenIs(token.ON) {
		p.nextToken() // move past ON

		// Check for securable type (OBJECT::, SCHEMA::, DATABASE::, etc.)
		if p.peekTokenIs(token.SCOPE) {
			stmt.OnType = strings.ToUpper(p.curToken.Literal)
			p.nextToken() // move to ::
			p.nextToken() // move past :: to object name
		}

		stmt.OnObject = p.parseQualifiedIdentifier()

		// Check for column list: (col1, col2, ...)
		if p.peekTokenIs(token.LPAREN) {
			p.nextToken() // consume (
			p.nextToken() // move to first column
			for {
				if p.curTokenIs(token.IDENT) || p.curToken.Type == token.IDENT {
					stmt.Columns = append(stmt.Columns, p.curToken.Literal)
				}
				if p.peekTokenIs(token.COMMA) {
					p.nextToken() // consume comma
					p.nextToken() // move to next column
				} else {
					break
				}
			}
			p.expectPeek(token.RPAREN)
		}

		p.nextToken() // move past object or )
	}

	// Parse TO clause
	if p.curTokenIs(token.TO) {
		p.nextToken() // move past TO
		stmt.ToPrincipals = p.parsePrincipalList()
	}

	// Parse WITH GRANT OPTION
	if p.curTokenIs(token.WITH) {
		p.nextToken() // move past WITH
		if p.curTokenIs(token.GRANT) {
			p.nextToken() // move past GRANT
			if p.curTokenIs(token.OPTION) {
				stmt.WithGrantOption = true
				p.nextToken()
			}
		}
	}

	return stmt
}

// parseRevokeStatement parses REVOKE [GRANT OPTION FOR] permission ON object FROM principal [CASCADE]
func (p *Parser) parseRevokeStatement() ast.Statement {
	stmt := &ast.RevokeStatement{Token: p.curToken}
	p.nextToken() // move past REVOKE

	// Check for GRANT OPTION FOR
	if p.curTokenIs(token.GRANT) {
		p.nextToken() // move past GRANT
		if p.curTokenIs(token.OPTION) {
			p.nextToken() // move past OPTION
			if p.curTokenIs(token.FOR) {
				stmt.GrantOptionFor = true
				p.nextToken() // move past FOR
			}
		}
	}

	// Parse permissions
	stmt.Permissions = p.parsePermissionList()

	// Parse ON clause
	if p.curTokenIs(token.ON) {
		p.nextToken() // move past ON

		// Check for securable type
		if p.peekTokenIs(token.SCOPE) {
			stmt.OnType = strings.ToUpper(p.curToken.Literal)
			p.nextToken() // move to ::
			p.nextToken() // move past :: to object name
		}

		stmt.OnObject = p.parseQualifiedIdentifier()

		// Check for column list: (col1, col2, ...)
		if p.peekTokenIs(token.LPAREN) {
			p.nextToken() // consume (
			p.nextToken() // move to first column
			for {
				if p.curTokenIs(token.IDENT) || p.curToken.Type == token.IDENT {
					stmt.Columns = append(stmt.Columns, p.curToken.Literal)
				}
				if p.peekTokenIs(token.COMMA) {
					p.nextToken() // consume comma
					p.nextToken() // move to next column
				} else {
					break
				}
			}
			p.expectPeek(token.RPAREN)
		}

		p.nextToken() // move past object or )
	}

	// Parse FROM clause
	if p.curTokenIs(token.FROM) {
		p.nextToken() // move past FROM
		stmt.FromPrincipals = p.parsePrincipalList()
	}

	// Check for CASCADE
	if p.curTokenIs(token.CASCADE) {
		stmt.Cascade = true
		p.nextToken()
	}

	return stmt
}

// parseDenyStatement parses DENY permission ON object TO principal [CASCADE]
func (p *Parser) parseDenyStatement() ast.Statement {
	stmt := &ast.DenyStatement{Token: p.curToken}
	p.nextToken() // move past DENY

	// Parse permissions
	stmt.Permissions = p.parsePermissionList()

	// Parse ON clause
	if p.curTokenIs(token.ON) {
		p.nextToken() // move past ON

		// Check for securable type
		if p.peekTokenIs(token.SCOPE) {
			stmt.OnType = strings.ToUpper(p.curToken.Literal)
			p.nextToken() // move to ::
			p.nextToken() // move past :: to object name
		}

		stmt.OnObject = p.parseQualifiedIdentifier()

		// Check for column list: (col1, col2, ...)
		if p.peekTokenIs(token.LPAREN) {
			p.nextToken() // consume (
			p.nextToken() // move to first column
			for {
				if p.curTokenIs(token.IDENT) || p.curToken.Type == token.IDENT {
					stmt.Columns = append(stmt.Columns, p.curToken.Literal)
				}
				if p.peekTokenIs(token.COMMA) {
					p.nextToken() // consume comma
					p.nextToken() // move to next column
				} else {
					break
				}
			}
			p.expectPeek(token.RPAREN)
		}

		p.nextToken() // move past object or )
	}

	// Parse TO clause
	if p.curTokenIs(token.TO) {
		p.nextToken() // move past TO
		stmt.ToPrincipals = p.parsePrincipalList()
	}

	// Check for CASCADE
	if p.curTokenIs(token.CASCADE) {
		stmt.Cascade = true
		p.nextToken()
	}

	return stmt
}

// parsePermissionList parses a comma-separated list of permissions until ON/TO/FROM
func (p *Parser) parsePermissionList() []string {
	var perms []string

	for {
		// Permissions can be multi-word like VIEW DEFINITION, ALTER ANY DATABASE
		var perm strings.Builder
		for !p.curTokenIs(token.COMMA) && !p.curTokenIs(token.ON) &&
			!p.curTokenIs(token.TO) && !p.curTokenIs(token.FROM) &&
			!p.curTokenIs(token.EOF) && !p.curTokenIs(token.SEMICOLON) {
			if perm.Len() > 0 {
				perm.WriteString(" ")
			}
			perm.WriteString(strings.ToUpper(p.curToken.Literal))
			p.nextToken()
		}
		if perm.Len() > 0 {
			perms = append(perms, perm.String())
		}

		if p.curTokenIs(token.COMMA) {
			p.nextToken() // consume comma
		} else {
			break
		}
	}

	return perms
}

// parsePrincipalList parses a comma-separated list of principals (users, roles)
func (p *Parser) parsePrincipalList() []string {
	var principals []string

	for {
		// Principal name - can be [bracketed] or plain
		name := p.curToken.Literal
		principals = append(principals, name)
		p.nextToken()

		if p.curTokenIs(token.COMMA) {
			p.nextToken() // consume comma
		} else {
			break
		}
	}

	return principals
}

// parseCreateLoginStatement parses CREATE LOGIN name WITH PASSWORD = 'xxx' or FROM WINDOWS
func (p *Parser) parseCreateLoginStatement(createToken token.Token) ast.Statement {
	stmt := &ast.CreateLoginStatement{Token: createToken}
	p.nextToken() // move past LOGIN

	// Login name - may be bracketed like [DOMAIN\User]
	stmt.Name = p.curToken.Literal
	p.nextToken()

	// Check for FROM WINDOWS/CERTIFICATE/ASYMMETRIC KEY or WITH PASSWORD
	if p.curTokenIs(token.FROM) {
		p.nextToken() // move past FROM
		if p.curTokenIs(token.WINDOWS) {
			stmt.FromWindows = true
			p.nextToken()
			// Handle optional WITH after FROM WINDOWS
			if p.curTokenIs(token.WITH) {
				p.nextToken() // move past WITH
				p.parseLoginOptions(stmt)
			}
		} else if p.curTokenIs(token.CERTIFICATE) || p.curTokenIs(token.IDENT) {
			// FROM CERTIFICATE name or FROM ASYMMETRIC KEY name
			p.nextToken() // skip certificate/key name
			if p.curTokenIs(token.IDENT) {
				p.nextToken()
			}
		}
	} else if p.curTokenIs(token.WITH) {
		p.nextToken() // move past WITH
		p.parseLoginOptions(stmt)
	}

	return stmt
}

// parseLoginOptions parses the WITH clause options for CREATE/ALTER LOGIN
func (p *Parser) parseLoginOptions(stmt *ast.CreateLoginStatement) {
	for !p.curTokenIs(token.EOF) && !p.curTokenIs(token.SEMICOLON) && !p.curTokenIs(token.GO) {
		optName := strings.ToUpper(p.curToken.Literal)

		if p.peekTokenIs(token.EQ) {
			p.nextToken() // move past option name to =
			p.nextToken() // move past = to value

			// Consume the value (string, number, identifier, hex, etc.)
			p.nextToken()

			// Consume any modifiers like HASHED, MUST_CHANGE, etc.
			for p.curTokenIs(token.IDENT) {
				upper := strings.ToUpper(p.curToken.Literal)
				if upper == "HASHED" || upper == "MUST_CHANGE" || upper == "UNLOCK" {
					p.nextToken()
				} else {
					break
				}
			}
			_ = optName // suppress unused warning
		} else {
			// Options without = like CHECK_POLICY, CHECK_EXPIRATION (which still need = ON/OFF)
			// or standalone options
			p.nextToken()
		}

		if p.curTokenIs(token.COMMA) {
			p.nextToken()
		} else {
			break
		}
	}
}

// parseAlterLoginStatement parses ALTER LOGIN name ENABLE/DISABLE/WITH PASSWORD = 'xxx'
func (p *Parser) parseAlterLoginStatement(alterToken token.Token) ast.Statement {
	stmt := &ast.AlterLoginStatement{Token: alterToken}
	p.nextToken() // move past LOGIN

	stmt.Name = p.curToken.Literal
	p.nextToken()

	// Check for ENABLE, DISABLE, or WITH
	if p.curTokenIs(token.ENABLE) {
		stmt.Enable = true
		p.nextToken()
	} else if p.curTokenIs(token.DISABLE) {
		stmt.Disable = true
		p.nextToken()
	} else if p.curTokenIs(token.WITH) {
		p.nextToken() // move past WITH
		for !p.curTokenIs(token.EOF) && !p.curTokenIs(token.SEMICOLON) && !p.curTokenIs(token.GO) {
			optName := strings.ToUpper(p.curToken.Literal)

			// Handle "NO CREDENTIAL" special case
			if optName == "NO" {
				p.nextToken() // skip NO
				if strings.ToUpper(p.curToken.Literal) == "CREDENTIAL" {
					p.nextToken() // skip CREDENTIAL
				}
				continue
			}

			if p.peekTokenIs(token.EQ) {
				p.nextToken() // move past option name to =
				p.nextToken() // move past = to value

				if optName == "PASSWORD" {
					if p.curTokenIs(token.STRING) || p.curTokenIs(token.NSTRING) {
						stmt.Password = p.curToken.Literal
					}
				}
				p.nextToken() // move past value

				// Handle modifiers like OLD_PASSWORD = ..., MUST_CHANGE, UNLOCK, HASHED
				for p.curTokenIs(token.IDENT) && !p.curTokenIs(token.EOF) {
					upper := strings.ToUpper(p.curToken.Literal)
					if upper == "OLD_PASSWORD" || upper == "MUST_CHANGE" || upper == "UNLOCK" || upper == "HASHED" {
						if p.peekTokenIs(token.EQ) {
							// It's another option like OLD_PASSWORD = 'xxx'
							p.nextToken() // move to =
							p.nextToken() // move to value
							p.nextToken() // move past value
						} else {
							// It's a standalone modifier
							p.nextToken()
						}
					} else {
						break
					}
				}
			} else {
				p.nextToken()
			}

			if p.curTokenIs(token.COMMA) {
				p.nextToken()
			} else {
				break
			}
		}
	}

	return stmt
}

// parseCreateUserStatement parses CREATE USER name FOR LOGIN xxx / WITHOUT LOGIN
func (p *Parser) parseCreateUserStatement(createToken token.Token) ast.Statement {
	stmt := &ast.CreateUserStatement{Token: createToken}
	p.nextToken() // move past USER

	stmt.Name = p.curToken.Literal
	p.nextToken()

	// Check for FOR LOGIN, WITHOUT LOGIN, or WITH
	if p.curTokenIs(token.FOR) {
		p.nextToken() // move past FOR
		if p.curTokenIs(token.LOGIN) {
			p.nextToken() // move past LOGIN
			stmt.ForLogin = p.curToken.Literal
			p.nextToken()
		}
	}

	if p.curTokenIs(token.WITHOUT) {
		p.nextToken() // move past WITHOUT
		if p.curTokenIs(token.LOGIN) {
			stmt.WithoutLogin = true
			p.nextToken()
		}
	}

	if p.curTokenIs(token.WITH) {
		p.nextToken() // move past WITH
		for !p.curTokenIs(token.EOF) && !p.curTokenIs(token.SEMICOLON) {
			optName := strings.ToUpper(p.curToken.Literal)
			if p.peekTokenIs(token.EQ) {
				p.nextToken() // consume =
				p.nextToken() // move to value
				if optName == "DEFAULT_SCHEMA" {
					stmt.DefaultSchema = p.curToken.Literal
				}
				p.nextToken()
			} else {
				p.nextToken()
			}
			if p.curTokenIs(token.COMMA) {
				p.nextToken()
			} else {
				break
			}
		}
	}

	return stmt
}

// parseAlterUserStatement parses ALTER USER name WITH DEFAULT_SCHEMA = xxx
func (p *Parser) parseAlterUserStatement(alterToken token.Token) ast.Statement {
	stmt := &ast.AlterUserStatement{Token: alterToken}
	p.nextToken() // move past USER

	stmt.Name = p.curToken.Literal
	p.nextToken()

	if p.curTokenIs(token.WITH) {
		p.nextToken() // move past WITH
		for !p.curTokenIs(token.EOF) && !p.curTokenIs(token.SEMICOLON) {
			optName := strings.ToUpper(p.curToken.Literal)
			if p.peekTokenIs(token.EQ) {
				p.nextToken() // consume =
				p.nextToken() // move to value
				switch optName {
				case "DEFAULT_SCHEMA":
					stmt.DefaultSchema = p.curToken.Literal
				case "NAME":
					stmt.NewName = p.curToken.Literal
				case "LOGIN":
					stmt.Login = p.curToken.Literal
				}
				p.nextToken()
			} else {
				p.nextToken()
			}
			if p.curTokenIs(token.COMMA) {
				p.nextToken()
			} else {
				break
			}
		}
	}

	return stmt
}

// parseCreateRoleStatement parses CREATE ROLE name [AUTHORIZATION owner]
func (p *Parser) parseCreateRoleStatement(createToken token.Token) ast.Statement {
	stmt := &ast.CreateRoleStatement{Token: createToken}
	p.nextToken() // move past ROLE

	stmt.Name = p.curToken.Literal
	p.nextToken()

	if p.curTokenIs(token.AUTHORIZATION) {
		p.nextToken() // move past AUTHORIZATION
		stmt.Authorization = p.curToken.Literal
		p.nextToken()
	}

	return stmt
}

// parseCreateApplicationRoleStatement parses CREATE APPLICATION ROLE name WITH PASSWORD = 'xxx'
func (p *Parser) parseCreateApplicationRoleStatement(createToken token.Token) ast.Statement {
	stmt := &ast.CreateApplicationRoleStatement{Token: createToken}
	p.nextToken() // move past ROLE

	stmt.Name = p.curToken.Literal
	p.nextToken()

	// Parse WITH clause
	if p.curTokenIs(token.WITH) {
		p.nextToken() // move past WITH
		for !p.curTokenIs(token.EOF) && !p.curTokenIs(token.SEMICOLON) && !p.curTokenIs(token.GO) {
			optName := strings.ToUpper(p.curToken.Literal)
			if p.peekTokenIs(token.EQ) {
				p.nextToken() // move to =
				p.nextToken() // move to value
				switch optName {
				case "PASSWORD":
					if p.curTokenIs(token.STRING) || p.curTokenIs(token.NSTRING) {
						stmt.Password = p.curToken.Literal
					}
				case "DEFAULT_SCHEMA":
					stmt.Schema = p.curToken.Literal
				}
				p.nextToken()
			} else {
				p.nextToken()
			}
			if p.curTokenIs(token.COMMA) {
				p.nextToken()
			} else {
				break
			}
		}
	}

	return stmt
}

// parseCreateServerRoleStatement parses CREATE SERVER ROLE name [AUTHORIZATION owner]
func (p *Parser) parseCreateServerRoleStatement(createToken token.Token) ast.Statement {
	stmt := &ast.CreateServerRoleStatement{Token: createToken}
	p.nextToken() // move past ROLE

	stmt.Name = p.curToken.Literal
	p.nextToken()

	if p.curTokenIs(token.AUTHORIZATION) {
		p.nextToken() // move past AUTHORIZATION
		stmt.Authorization = p.curToken.Literal
		p.nextToken()
	}

	return stmt
}

// parseCreateCredentialStatement parses CREATE CREDENTIAL name WITH IDENTITY = '...', SECRET = '...'
func (p *Parser) parseCreateCredentialStatement(createToken token.Token) ast.Statement {
	stmt := &ast.CreateCredentialStatement{Token: createToken}
	p.nextToken() // move past CREDENTIAL (which is the name in this context)

	// Wait, the current token is CREDENTIAL as IDENT, and we need the name after it
	// Actually, when we get here, curToken is "CREDENTIAL" identifier, so the name follows
	stmt.Name = p.curToken.Literal
	p.nextToken()

	// Parse WITH clause
	if p.curTokenIs(token.WITH) {
		p.nextToken() // move past WITH
		for !p.curTokenIs(token.EOF) && !p.curTokenIs(token.SEMICOLON) && !p.curTokenIs(token.GO) {
			optName := strings.ToUpper(p.curToken.Literal)
			if p.peekTokenIs(token.EQ) {
				p.nextToken() // move to =
				p.nextToken() // move to value
				switch optName {
				case "IDENTITY":
					if p.curTokenIs(token.STRING) || p.curTokenIs(token.NSTRING) {
						stmt.Identity = p.curToken.Literal
					}
				case "SECRET":
					if p.curTokenIs(token.STRING) || p.curTokenIs(token.NSTRING) {
						stmt.Secret = p.curToken.Literal
					}
				}
				p.nextToken()
			} else {
				p.nextToken()
			}
			if p.curTokenIs(token.COMMA) {
				p.nextToken()
			} else {
				break
			}
		}
	}

	return stmt
}

// parseCreateDatabaseOrScopedCredential handles CREATE DATABASE and CREATE DATABASE SCOPED CREDENTIAL
func (p *Parser) parseCreateDatabaseOrScopedCredential(createToken token.Token) ast.Statement {
	p.nextToken() // move past DATABASE

	// Check if next is SCOPED (as IDENT)
	if p.curTokenIs(token.IDENT) && strings.ToUpper(p.curToken.Literal) == "SCOPED" {
		p.nextToken() // move past SCOPED
		// Check for CREDENTIAL
		if p.curTokenIs(token.IDENT) && strings.ToUpper(p.curToken.Literal) == "CREDENTIAL" {
			return p.parseCreateDatabaseScopedCredentialStatement(createToken)
		}
	}

	// Otherwise it's CREATE DATABASE - skip to semicolon for now
	// (CREATE DATABASE has complex syntax we don't fully support yet)
	for !p.curTokenIs(token.EOF) && !p.curTokenIs(token.SEMICOLON) && !p.curTokenIs(token.GO) {
		p.nextToken()
	}
	return nil
}

// parseCreateDatabaseScopedCredentialStatement parses CREATE DATABASE SCOPED CREDENTIAL
func (p *Parser) parseCreateDatabaseScopedCredentialStatement(createToken token.Token) ast.Statement {
	stmt := &ast.CreateDatabaseScopedCredentialStatement{Token: createToken}
	p.nextToken() // move past CREDENTIAL

	stmt.Name = p.curToken.Literal
	p.nextToken()

	// Parse WITH clause
	if p.curTokenIs(token.WITH) {
		p.nextToken() // move past WITH
		for !p.curTokenIs(token.EOF) && !p.curTokenIs(token.SEMICOLON) && !p.curTokenIs(token.GO) {
			optName := strings.ToUpper(p.curToken.Literal)
			if p.peekTokenIs(token.EQ) {
				p.nextToken() // move to =
				p.nextToken() // move to value
				switch optName {
				case "IDENTITY":
					if p.curTokenIs(token.STRING) || p.curTokenIs(token.NSTRING) {
						stmt.Identity = p.curToken.Literal
					}
				case "SECRET":
					if p.curTokenIs(token.STRING) || p.curTokenIs(token.NSTRING) {
						stmt.Secret = p.curToken.Literal
					}
				}
				p.nextToken()
			} else {
				p.nextToken()
			}
			if p.curTokenIs(token.COMMA) {
				p.nextToken()
			} else {
				break
			}
		}
	}

	return stmt
}

func (p *Parser) parseCreateSchemaStatement(createToken token.Token) ast.Statement {
	stmt := &ast.CreateSchemaStatement{Token: createToken}
	p.nextToken() // move past SCHEMA

	stmt.Name = p.curToken.Literal
	p.nextToken()

	if p.curTokenIs(token.AUTHORIZATION) {
		p.nextToken() // move past AUTHORIZATION
		stmt.Authorization = p.curToken.Literal
		p.nextToken()
	}

	return stmt
}

// parseAlterRoleStatement parses ALTER ROLE name ADD/DROP MEMBER user
func (p *Parser) parseAlterRoleStatement(alterToken token.Token) ast.Statement {
	stmt := &ast.AlterRoleStatement{Token: alterToken}
	p.nextToken() // move past ROLE

	stmt.Name = p.curToken.Literal
	p.nextToken()

	// Check for ADD MEMBER, DROP MEMBER, or WITH NAME
	if p.curTokenIs(token.ADD) {
		p.nextToken() // move past ADD
		if p.curTokenIs(token.MEMBER) {
			p.nextToken() // move past MEMBER
			stmt.AddMember = p.curToken.Literal
			p.nextToken()
		}
	} else if p.curTokenIs(token.DROP) {
		p.nextToken() // move past DROP
		if p.curTokenIs(token.MEMBER) {
			p.nextToken() // move past MEMBER
			stmt.DropMember = p.curToken.Literal
			p.nextToken()
		}
	} else if p.curTokenIs(token.WITH) {
		p.nextToken() // move past WITH
		if strings.ToUpper(p.curToken.Literal) == "NAME" && p.peekTokenIs(token.EQ) {
			p.nextToken() // consume =
			p.nextToken() // move to value
			stmt.NewName = p.curToken.Literal
			p.nextToken()
		}
	}

	return stmt
}

// parseAlterApplicationRoleStatement parses ALTER APPLICATION ROLE name WITH ...
func (p *Parser) parseAlterApplicationRoleStatement(alterToken token.Token) ast.Statement {
	stmt := &ast.AlterApplicationRoleStatement{Token: alterToken}
	p.nextToken() // move past ROLE

	stmt.Name = p.curToken.Literal
	p.nextToken()

	// Parse WITH clause
	if p.curTokenIs(token.WITH) {
		p.nextToken() // move past WITH
		for !p.curTokenIs(token.EOF) && !p.curTokenIs(token.SEMICOLON) && !p.curTokenIs(token.GO) {
			optName := strings.ToUpper(p.curToken.Literal)
			if p.peekTokenIs(token.EQ) {
				p.nextToken() // move to =
				p.nextToken() // move to value
				switch optName {
				case "PASSWORD":
					if p.curTokenIs(token.STRING) || p.curTokenIs(token.NSTRING) {
						stmt.Password = p.curToken.Literal
					}
				case "DEFAULT_SCHEMA":
					stmt.Schema = p.curToken.Literal
				case "NAME":
					stmt.NewName = p.curToken.Literal
				}
				p.nextToken()
			} else {
				p.nextToken()
			}
			if p.curTokenIs(token.COMMA) {
				p.nextToken()
			} else {
				break
			}
		}
	}

	return stmt
}

// parseAlterServerRoleStatement parses ALTER SERVER ROLE name ADD/DROP MEMBER or WITH NAME
func (p *Parser) parseAlterServerRoleStatement(alterToken token.Token) ast.Statement {
	stmt := &ast.AlterServerRoleStatement{Token: alterToken}
	p.nextToken() // move past ROLE

	stmt.Name = p.curToken.Literal
	p.nextToken()

	// Check for ADD MEMBER, DROP MEMBER, or WITH NAME
	if p.curTokenIs(token.ADD) {
		p.nextToken() // move past ADD
		if p.curTokenIs(token.MEMBER) {
			p.nextToken() // move past MEMBER
			stmt.AddMember = p.curToken.Literal
			p.nextToken()
		}
	} else if p.curTokenIs(token.DROP) {
		p.nextToken() // move past DROP
		if p.curTokenIs(token.MEMBER) {
			p.nextToken() // move past MEMBER
			stmt.DropMember = p.curToken.Literal
			p.nextToken()
		}
	} else if p.curTokenIs(token.WITH) {
		p.nextToken() // move past WITH
		if strings.ToUpper(p.curToken.Literal) == "NAME" && p.peekTokenIs(token.EQ) {
			p.nextToken() // move to =
			p.nextToken() // move to value
			stmt.NewName = p.curToken.Literal
			p.nextToken()
		}
	}

	return stmt
}

// -----------------------------------------------------------------------------
// Stage 7: Backup & Restore
// -----------------------------------------------------------------------------

// parseBackupStatement parses BACKUP DATABASE/LOG statement
func (p *Parser) parseBackupStatement() ast.Statement {
	stmt := &ast.BackupStatement{Token: p.curToken}
	p.nextToken() // move past BACKUP

	// Parse backup type: DATABASE, LOG, or CERTIFICATE
	switch p.curToken.Type {
	case token.DATABASE:
		stmt.BackupType = "DATABASE"
	case token.LOG:
		stmt.BackupType = "LOG"
	case token.CERTIFICATE:
		stmt.BackupType = "CERTIFICATE"
	default:
		stmt.BackupType = strings.ToUpper(p.curToken.Literal)
	}
	p.nextToken()

	// Parse database/certificate name
	stmt.DatabaseName = p.curToken.Literal
	p.nextToken()

	// Skip FILE/FILEGROUP clauses if present (before TO)
	for p.curTokenIs(token.IDENT) && (strings.ToUpper(p.curToken.Literal) == "FILE" ||
		strings.ToUpper(p.curToken.Literal) == "FILEGROUP") {
		p.nextToken() // skip FILE/FILEGROUP
		if p.curTokenIs(token.EQ) {
			p.nextToken() // skip =
			p.nextToken() // skip value
		}
		if p.curTokenIs(token.COMMA) {
			p.nextToken() // skip comma
		}
	}

	// Parse TO clause
	if p.curTokenIs(token.TO) {
		p.nextToken() // move past TO
		stmt.ToLocations = p.parseBackupLocations()
	}

	// Parse MIRROR TO clause(s)
	for p.curTokenIs(token.IDENT) && strings.ToUpper(p.curToken.Literal) == "MIRROR" {
		p.nextToken() // move past MIRROR
		if p.curTokenIs(token.TO) {
			p.nextToken() // move past TO
			mirrorLocs := p.parseBackupLocations()
			stmt.ToLocations = append(stmt.ToLocations, mirrorLocs...)
		}
	}

	// Parse WITH clause
	if p.curTokenIs(token.WITH) {
		p.nextToken() // move past WITH
		stmt.WithOptions = p.parseBackupOptions()
	}

	return stmt
}

// parseRestoreStatement parses RESTORE DATABASE/LOG/FILELISTONLY/HEADERONLY statement
func (p *Parser) parseRestoreStatement() ast.Statement {
	stmt := &ast.RestoreStatement{Token: p.curToken}
	p.nextToken() // move past RESTORE

	// Parse restore type
	switch p.curToken.Type {
	case token.DATABASE:
		stmt.RestoreType = "DATABASE"
		p.nextToken()
		stmt.DatabaseName = p.curToken.Literal
		p.nextToken()
	case token.LOG:
		stmt.RestoreType = "LOG"
		p.nextToken()
		stmt.DatabaseName = p.curToken.Literal
		p.nextToken()
	case token.FILELISTONLY:
		stmt.RestoreType = "FILELISTONLY"
		p.nextToken()
	case token.HEADERONLY:
		stmt.RestoreType = "HEADERONLY"
		p.nextToken()
	default:
		// Handle VERIFYONLY and other types as identifiers
		stmt.RestoreType = strings.ToUpper(p.curToken.Literal)
		p.nextToken()
		// Check if next token is a database name (not FROM)
		if !p.curTokenIs(token.FROM) && !p.curTokenIs(token.WITH) {
			stmt.DatabaseName = p.curToken.Literal
			p.nextToken()
		}
	}

	// Skip FILE/FILEGROUP/PAGE clauses if present (before FROM)
	for p.curTokenIs(token.IDENT) && (strings.ToUpper(p.curToken.Literal) == "FILE" ||
		strings.ToUpper(p.curToken.Literal) == "FILEGROUP" ||
		strings.ToUpper(p.curToken.Literal) == "PAGE") {
		p.nextToken() // skip FILE/FILEGROUP/PAGE
		if p.curTokenIs(token.EQ) {
			p.nextToken() // skip =
			p.nextToken() // skip value
		}
		if p.curTokenIs(token.COMMA) {
			p.nextToken() // skip comma
		}
	}

	// Parse FROM clause
	if p.curTokenIs(token.FROM) {
		p.nextToken() // move past FROM
		stmt.FromLocations = p.parseBackupLocations()
	}

	// Parse WITH clause
	if p.curTokenIs(token.WITH) {
		p.nextToken() // move past WITH
		stmt.WithOptions = p.parseBackupOptions()
	}

	return stmt
}

// parseBackupLocations parses DISK = 'path', URL = 'path', ...
func (p *Parser) parseBackupLocations() []*ast.BackupLocation {
	var locations []*ast.BackupLocation

	for {
		loc := &ast.BackupLocation{}

		// Get location type (DISK, URL)
		loc.Type = strings.ToUpper(p.curToken.Literal)
		p.nextToken()

		// Expect =
		if p.curTokenIs(token.EQ) {
			p.nextToken() // move past =
		}

		// Get path
		if p.curTokenIs(token.STRING) || p.curTokenIs(token.NSTRING) {
			loc.Path = p.curToken.Literal
			p.nextToken()
		}

		locations = append(locations, loc)

		// Check for comma (more locations)
		if p.curTokenIs(token.COMMA) {
			p.nextToken()
		} else {
			break
		}
	}

	return locations
}

// parseBackupOptions parses WITH option, option = value, ...
func (p *Parser) parseBackupOptions() []*ast.BackupOption {
	var options []*ast.BackupOption

	for {
		opt := &ast.BackupOption{}

		// Get option name
		opt.Name = strings.ToUpper(p.curToken.Literal)
		p.nextToken()

		// Handle special cases
		if opt.Name == "MOVE" {
			// MOVE 'logical_name' TO 'os_file_name'
			if p.curTokenIs(token.STRING) || p.curTokenIs(token.NSTRING) {
				logicalName := p.curToken.Literal
				p.nextToken() // move past logical name
				if p.curTokenIs(token.TO) {
					p.nextToken() // move past TO
					if p.curTokenIs(token.STRING) || p.curTokenIs(token.NSTRING) {
						opt.Value = logicalName + " TO " + p.curToken.Literal
						p.nextToken() // move past file path
					}
				}
			}
		} else if opt.Name == "STOPAT" || opt.Name == "STOPATMARK" || opt.Name == "STOPBEFOREMARK" {
			// STOPAT = 'datetime' or STOPATMARK = 'mark'
			if p.curTokenIs(token.EQ) {
				p.nextToken() // move past =
				opt.Value = p.curToken.Literal
				p.nextToken()
			}
		} else if p.curTokenIs(token.EQ) {
			// Check for = value
			p.nextToken() // move past =
			// Get value (could be string, number, or identifier)
			if p.curTokenIs(token.STRING) || p.curTokenIs(token.NSTRING) {
				opt.Value = p.curToken.Literal
			} else {
				opt.Value = p.curToken.Literal
			}
			p.nextToken()
		} else if p.curTokenIs(token.LPAREN) {
			// Handle ENCRYPTION (...), MIRROR TO (...), etc.
			var parts []string
			depth := 1
			for depth > 0 && !p.curTokenIs(token.EOF) {
				p.nextToken()
				if p.curTokenIs(token.LPAREN) {
					depth++
					parts = append(parts, "(")
				} else if p.curTokenIs(token.RPAREN) {
					depth--
					if depth > 0 {
						parts = append(parts, ")")
					}
				} else {
					parts = append(parts, p.curToken.Literal)
				}
			}
			opt.Value = "(" + strings.Join(parts, " ") + ")"
			p.nextToken() // move past final )
		}

		options = append(options, opt)

		// Check for comma (more options)
		if p.curTokenIs(token.COMMA) {
			p.nextToken()
		} else {
			break
		}
	}

	return options
}

// -----------------------------------------------------------------------------
// Stage 8: Cryptography & CLR
// -----------------------------------------------------------------------------

// parseCreateMasterKeyStatement parses CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'xxx'
func (p *Parser) parseCreateMasterKeyStatement(createToken token.Token) ast.Statement {
	stmt := &ast.CreateMasterKeyStatement{Token: createToken}
	p.nextToken() // move past MASTER

	// Expect KEY
	if p.curTokenIs(token.KEY) {
		p.nextToken()
	}

	// Expect ENCRYPTION BY PASSWORD = 'xxx'
	if p.curTokenIs(token.ENCRYPTION) {
		p.nextToken() // move past ENCRYPTION
	}
	if p.curTokenIs(token.BY) {
		p.nextToken() // move past BY
	}
	if p.curTokenIs(token.PASSWORD) {
		p.nextToken() // move past PASSWORD
	}
	if p.curTokenIs(token.EQ) {
		p.nextToken() // move past =
	}
	if p.curTokenIs(token.STRING) || p.curTokenIs(token.NSTRING) {
		stmt.Password = p.curToken.Literal
		p.nextToken()
	}

	return stmt
}

// parseCreateCertificateStatement parses CREATE CERTIFICATE name WITH SUBJECT = 'xxx'
func (p *Parser) parseCreateCertificateStatement(createToken token.Token) ast.Statement {
	stmt := &ast.CreateCertificateStatement{Token: createToken}
	p.nextToken() // move past CERTIFICATE

	stmt.Name = p.curToken.Literal
	p.nextToken()

	// Parse optional clauses: FROM FILE, WITH SUBJECT, ENCRYPTION BY PASSWORD, etc.
	for !p.curTokenIs(token.EOF) && !p.curTokenIs(token.SEMICOLON) {
		if p.curTokenIs(token.FROM) {
			p.nextToken() // move past FROM
			if strings.ToUpper(p.curToken.Literal) == "FILE" {
				p.nextToken() // move past FILE
				if p.curTokenIs(token.EQ) {
					p.nextToken() // move past =
				}
				if p.curTokenIs(token.STRING) || p.curTokenIs(token.NSTRING) {
					stmt.FromFile = p.curToken.Literal
					p.nextToken()
				}
			}
		} else if p.curTokenIs(token.WITH) {
			p.nextToken() // move past WITH
			for !p.curTokenIs(token.EOF) && !p.curTokenIs(token.SEMICOLON) {
				optName := strings.ToUpper(p.curToken.Literal)
				if p.peekTokenIs(token.EQ) {
					p.nextToken() // consume =
					p.nextToken() // move to value
					if optName == "SUBJECT" {
						if p.curTokenIs(token.STRING) || p.curTokenIs(token.NSTRING) {
							stmt.Subject = p.curToken.Literal
						}
					}
					p.nextToken()
				} else {
					p.nextToken()
				}
				if p.curTokenIs(token.COMMA) {
					p.nextToken()
				} else {
					break
				}
			}
			break
		} else {
			break
		}
	}

	return stmt
}

// parseCreateSymmetricKeyStatement parses CREATE SYMMETRIC KEY name WITH ALGORITHM = xxx ENCRYPTION BY CERTIFICATE xxx
func (p *Parser) parseCreateSymmetricKeyStatement(createToken token.Token) ast.Statement {
	stmt := &ast.CreateSymmetricKeyStatement{Token: createToken}
	p.nextToken() // move past SYMMETRIC

	// Expect KEY
	if p.curTokenIs(token.KEY) {
		p.nextToken()
	}

	stmt.Name = p.curToken.Literal
	p.nextToken()

	// Parse WITH ALGORITHM and ENCRYPTION BY clauses
	for !p.curTokenIs(token.EOF) && !p.curTokenIs(token.SEMICOLON) {
		if p.curTokenIs(token.WITH) {
			p.nextToken() // move past WITH
			if p.curTokenIs(token.ALGORITHM) {
				p.nextToken() // move past ALGORITHM
				if p.curTokenIs(token.EQ) {
					p.nextToken() // move past =
				}
				stmt.Algorithm = p.curToken.Literal
				p.nextToken()
			}
		} else if p.curTokenIs(token.ENCRYPTION) {
			p.nextToken() // move past ENCRYPTION
			if p.curTokenIs(token.BY) {
				p.nextToken() // move past BY
				if p.curTokenIs(token.CERTIFICATE) {
					p.nextToken() // move past CERTIFICATE
					stmt.EncryptByCert = p.curToken.Literal
					p.nextToken()
				} else if p.curTokenIs(token.SYMMETRIC) {
					p.nextToken() // move past SYMMETRIC
					if p.curTokenIs(token.KEY) {
						p.nextToken() // move past KEY
					}
					stmt.EncryptByKey = p.curToken.Literal
					p.nextToken()
				} else if p.curTokenIs(token.PASSWORD) {
					p.nextToken() // move past PASSWORD
					if p.curTokenIs(token.EQ) {
						p.nextToken() // move past =
					}
					if p.curTokenIs(token.STRING) || p.curTokenIs(token.NSTRING) {
						stmt.EncryptByPwd = p.curToken.Literal
						p.nextToken()
					}
				}
			}
		} else {
			break
		}
	}

	return stmt
}

// parseCreateAsymmetricKeyStatement parses CREATE ASYMMETRIC KEY name FROM FILE = 'path'
func (p *Parser) parseCreateAsymmetricKeyStatement(createToken token.Token) ast.Statement {
	stmt := &ast.CreateAsymmetricKeyStatement{Token: createToken}
	p.nextToken() // move past ASYMMETRIC

	// Expect KEY
	if p.curTokenIs(token.KEY) {
		p.nextToken()
	}

	stmt.Name = p.curToken.Literal
	p.nextToken()

	// Parse FROM FILE or FROM ASSEMBLY or WITH ALGORITHM
	for !p.curTokenIs(token.EOF) && !p.curTokenIs(token.SEMICOLON) {
		if p.curTokenIs(token.FROM) {
			p.nextToken() // move past FROM
			if strings.ToUpper(p.curToken.Literal) == "FILE" {
				p.nextToken() // move past FILE
				if p.curTokenIs(token.EQ) {
					p.nextToken() // move past =
				}
				if p.curTokenIs(token.STRING) || p.curTokenIs(token.NSTRING) {
					stmt.FromFile = p.curToken.Literal
					p.nextToken()
				}
			} else if p.curTokenIs(token.ASSEMBLY) {
				p.nextToken() // move past ASSEMBLY
				stmt.FromAssembly = p.curToken.Literal
				p.nextToken()
			}
		} else if p.curTokenIs(token.WITH) {
			p.nextToken() // move past WITH
			if p.curTokenIs(token.ALGORITHM) {
				p.nextToken() // move past ALGORITHM
				if p.curTokenIs(token.EQ) {
					p.nextToken() // move past =
				}
				stmt.Algorithm = p.curToken.Literal
				p.nextToken()
			}
		} else {
			break
		}
	}

	return stmt
}

// parseOpenStatement handles OPEN SYMMETRIC KEY
// parseOpenSymmetricKeyStatement parses OPEN SYMMETRIC KEY name DECRYPTION BY CERTIFICATE xxx
func (p *Parser) parseOpenSymmetricKeyStatement(openToken token.Token) ast.Statement {
	stmt := &ast.OpenSymmetricKeyStatement{Token: openToken}
	p.nextToken() // move past SYMMETRIC

	// Expect KEY
	if p.curTokenIs(token.KEY) {
		p.nextToken()
	}

	stmt.KeyName = p.curToken.Literal
	p.nextToken()

	// Parse DECRYPTION BY clause
	if p.curTokenIs(token.DECRYPTION) {
		p.nextToken() // move past DECRYPTION
		if p.curTokenIs(token.BY) {
			p.nextToken() // move past BY
			if p.curTokenIs(token.CERTIFICATE) {
				p.nextToken() // move past CERTIFICATE
				stmt.DecryptByCert = p.curToken.Literal
				p.nextToken()
			} else if p.curTokenIs(token.SYMMETRIC) {
				p.nextToken() // move past SYMMETRIC
				if p.curTokenIs(token.KEY) {
					p.nextToken() // move past KEY
				}
				stmt.DecryptByKey = p.curToken.Literal
				p.nextToken()
			} else if p.curTokenIs(token.PASSWORD) {
				p.nextToken() // move past PASSWORD
				if p.curTokenIs(token.EQ) {
					p.nextToken() // move past =
				}
				if p.curTokenIs(token.STRING) || p.curTokenIs(token.NSTRING) {
					stmt.DecryptByPwd = p.curToken.Literal
					p.nextToken()
				}
			}
		}
	}

	return stmt
}

// parseCreateAssemblyStatement parses CREATE ASSEMBLY name FROM 'path' WITH PERMISSION_SET = SAFE
func (p *Parser) parseCreateAssemblyStatement(createToken token.Token) ast.Statement {
	stmt := &ast.CreateAssemblyStatement{Token: createToken}
	p.nextToken() // move past ASSEMBLY

	stmt.Name = p.curToken.Literal
	p.nextToken()

	// Parse FROM clause
	if p.curTokenIs(token.FROM) {
		p.nextToken() // move past FROM
		if p.curTokenIs(token.STRING) || p.curTokenIs(token.NSTRING) {
			stmt.FromPath = p.curToken.Literal
			p.nextToken()
		} else {
			// Could be binary 0x...
			stmt.FromBinary = p.curToken.Literal
			p.nextToken()
		}
	}

	// Parse WITH PERMISSION_SET clause
	if p.curTokenIs(token.WITH) {
		p.nextToken() // move past WITH
		if p.curTokenIs(token.PERMISSION_SET) {
			p.nextToken() // move past PERMISSION_SET
			if p.curTokenIs(token.EQ) {
				p.nextToken() // move past =
			}
			stmt.PermissionSet = strings.ToUpper(p.curToken.Literal)
			p.nextToken()
		}
	}

	return stmt
}

// parseAlterAssemblyStatement parses ALTER ASSEMBLY name FROM 'path'
func (p *Parser) parseAlterAssemblyStatement(alterToken token.Token) ast.Statement {
	stmt := &ast.AlterAssemblyStatement{Token: alterToken}
	p.nextToken() // move past ASSEMBLY

	stmt.Name = p.curToken.Literal
	p.nextToken()

	// Parse FROM clause
	if p.curTokenIs(token.FROM) {
		p.nextToken() // move past FROM
		if p.curTokenIs(token.STRING) || p.curTokenIs(token.NSTRING) {
			stmt.FromPath = p.curToken.Literal
			p.nextToken()
		} else {
			stmt.FromBinary = p.curToken.Literal
			p.nextToken()
		}
	}

	// Parse WITH PERMISSION_SET clause
	if p.curTokenIs(token.WITH) {
		p.nextToken() // move past WITH
		if p.curTokenIs(token.PERMISSION_SET) {
			p.nextToken() // move past PERMISSION_SET
			if p.curTokenIs(token.EQ) {
				p.nextToken() // move past =
			}
			stmt.PermissionSet = strings.ToUpper(p.curToken.Literal)
			p.nextToken()
		}
	}

	return stmt
}

// -----------------------------------------------------------------------------
// Stage 9: Partitioning
// -----------------------------------------------------------------------------

// parseCreatePartitionStatement handles CREATE PARTITION FUNCTION/SCHEME
func (p *Parser) parseCreatePartitionStatement(createToken token.Token) ast.Statement {
	p.nextToken() // move past PARTITION

	if p.curTokenIs(token.FUNCTION) {
		return p.parseCreatePartitionFunctionStatement(createToken)
	} else if p.curTokenIs(token.SCHEME) {
		return p.parseCreatePartitionSchemeStatement(createToken)
	}

	return nil
}

// parseCreatePartitionFunctionStatement parses CREATE PARTITION FUNCTION name(type) AS RANGE LEFT/RIGHT FOR VALUES (...)
func (p *Parser) parseCreatePartitionFunctionStatement(createToken token.Token) ast.Statement {
	stmt := &ast.CreatePartitionFunctionStatement{Token: createToken}
	p.nextToken() // move past FUNCTION

	stmt.Name = p.curToken.Literal
	p.nextToken()

	// Expect (type)
	if p.curTokenIs(token.LPAREN) {
		p.nextToken() // move past (
		stmt.InputType = p.parseDataType()
		p.nextToken() // move past the data type
		if p.curTokenIs(token.RPAREN) {
			p.nextToken() // move past )
		}
	}

	// Expect AS RANGE LEFT/RIGHT
	if p.curTokenIs(token.AS) {
		p.nextToken() // move past AS
	}
	if p.curTokenIs(token.RANGE) {
		p.nextToken() // move past RANGE
		// LEFT or RIGHT
		stmt.RangeType = strings.ToUpper(p.curToken.Literal)
		p.nextToken()
	}

	// Expect FOR VALUES (...)
	if p.curTokenIs(token.FOR) {
		p.nextToken() // move past FOR
	}
	if p.curTokenIs(token.VALUES) {
		p.nextToken() // move past VALUES
	}

	// Parse boundary values list
	if p.curTokenIs(token.LPAREN) {
		p.nextToken() // move past (
		for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
			val := p.parseExpression(LOWEST)
			stmt.BoundaryValues = append(stmt.BoundaryValues, val)
			if p.peekTokenIs(token.COMMA) {
				p.nextToken() // move to comma
				p.nextToken() // move past comma
			} else if p.peekTokenIs(token.RPAREN) {
				p.nextToken() // move to )
			} else {
				break
			}
		}
		if p.curTokenIs(token.RPAREN) {
			p.nextToken() // move past )
		}
	}

	return stmt
}

// parseCreatePartitionSchemeStatement parses CREATE PARTITION SCHEME name AS PARTITION func ALL TO (...) or TO (fg1, fg2, ...)
func (p *Parser) parseCreatePartitionSchemeStatement(createToken token.Token) ast.Statement {
	stmt := &ast.CreatePartitionSchemeStatement{Token: createToken}
	p.nextToken() // move past SCHEME

	stmt.Name = p.curToken.Literal
	p.nextToken()

	// Expect AS PARTITION function_name
	if p.curTokenIs(token.AS) {
		p.nextToken() // move past AS
	}
	if p.curTokenIs(token.PARTITION) {
		p.nextToken() // move past PARTITION
	}
	stmt.FunctionName = p.curToken.Literal
	p.nextToken()

	// Check for ALL TO or just TO
	if p.curTokenIs(token.ALL) {
		p.nextToken() // move past ALL
		if p.curTokenIs(token.TO) {
			p.nextToken() // move past TO
		}
		if p.curTokenIs(token.LPAREN) {
			p.nextToken() // move past (
			// Get filegroup name (lexer already handles brackets)
			stmt.AllTo = p.curToken.Literal
			p.nextToken()
			if p.curTokenIs(token.RPAREN) {
				p.nextToken()
			}
		}
	} else if p.curTokenIs(token.TO) {
		p.nextToken() // move past TO
		if p.curTokenIs(token.LPAREN) {
			p.nextToken() // move past (
			for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
				fg := p.curToken.Literal
				stmt.FileGroups = append(stmt.FileGroups, fg)
				p.nextToken()
				if p.curTokenIs(token.COMMA) {
					p.nextToken()
				}
			}
		}
	}

	return stmt
}

// parseAlterPartitionStatement handles ALTER PARTITION FUNCTION/SCHEME
func (p *Parser) parseAlterPartitionStatement(alterToken token.Token) ast.Statement {
	p.nextToken() // move past PARTITION

	if p.curTokenIs(token.FUNCTION) {
		return p.parseAlterPartitionFunctionStatement(alterToken)
	} else if p.curTokenIs(token.SCHEME) {
		return p.parseAlterPartitionSchemeStatement(alterToken)
	}

	return nil
}

// parseAlterPartitionFunctionStatement parses ALTER PARTITION FUNCTION name() SPLIT/MERGE RANGE (value)
func (p *Parser) parseAlterPartitionFunctionStatement(alterToken token.Token) ast.Statement {
	stmt := &ast.AlterPartitionFunctionStatement{Token: alterToken}
	p.nextToken() // move past FUNCTION

	stmt.Name = p.curToken.Literal
	p.nextToken()

	// Expect empty parens ()
	if p.curTokenIs(token.LPAREN) {
		p.nextToken() // move past (
		if p.curTokenIs(token.RPAREN) {
			p.nextToken() // move past )
		}
	}

	// Expect SPLIT or MERGE
	if p.curTokenIs(token.SPLIT) {
		stmt.Action = "SPLIT"
		p.nextToken()
	} else if p.curTokenIs(token.MERGE) {
		stmt.Action = "MERGE"
		p.nextToken()
	}

	// Expect RANGE (value)
	if p.curTokenIs(token.RANGE) {
		p.nextToken() // move past RANGE
	}
	if p.curTokenIs(token.LPAREN) {
		p.nextToken() // move past (
		stmt.RangeValue = p.parseExpression(LOWEST)
		if p.peekTokenIs(token.RPAREN) {
			p.nextToken()
		}
	}

	return stmt
}

// parseAlterPartitionSchemeStatement parses ALTER PARTITION SCHEME name NEXT USED filegroup
func (p *Parser) parseAlterPartitionSchemeStatement(alterToken token.Token) ast.Statement {
	stmt := &ast.AlterPartitionSchemeStatement{Token: alterToken}
	p.nextToken() // move past SCHEME

	stmt.Name = p.curToken.Literal
	p.nextToken()

	// Expect NEXT USED
	if p.curTokenIs(token.NEXT) {
		p.nextToken() // move past NEXT
	}
	if p.curTokenIs(token.USED) {
		p.nextToken() // move past USED
	}

	// Get filegroup name (lexer handles brackets)
	stmt.NextUsed = p.curToken.Literal
	p.nextToken()

	return stmt
}

// -----------------------------------------------------------------------------
// Stage 10: Full-Text Search
// -----------------------------------------------------------------------------

// parseContainsExpression parses CONTAINS(column, 'search term')
func (p *Parser) parseContainsExpression() ast.Expression {
	expr := &ast.ContainsExpression{Token: p.curToken}

	if !p.expectPeek(token.LPAREN) {
		return nil
	}
	p.nextToken() // move past (

	// Parse column(s) - could be single column, (col1, col2), or *
	if p.curTokenIs(token.ASTERISK) {
		expr.Columns = []string{"*"}
		p.nextToken()
	} else if p.curTokenIs(token.LPAREN) {
		// Multiple columns
		p.nextToken() // move past (
		for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
			expr.Columns = append(expr.Columns, p.curToken.Literal)
			p.nextToken()
			if p.curTokenIs(token.COMMA) {
				p.nextToken()
			}
		}
		p.nextToken() // move past )
	} else {
		// Single column
		expr.Columns = []string{p.curToken.Literal}
		p.nextToken()
	}

	// Expect comma
	if p.curTokenIs(token.COMMA) {
		p.nextToken()
	}

	// Parse search term
	expr.SearchTerm = p.parseExpression(LOWEST)

	// Check for LANGUAGE option
	if p.peekTokenIs(token.COMMA) {
		p.nextToken() // move to comma
		p.nextToken() // move past comma
		if p.curTokenIs(token.LANGUAGE) {
			p.nextToken() // move past LANGUAGE
			expr.Language = p.curToken.Literal
		}
	}

	if p.peekTokenIs(token.RPAREN) {
		p.nextToken()
	}

	return expr
}

// parseFreetextExpression parses FREETEXT(column, 'search term')
func (p *Parser) parseFreetextExpression() ast.Expression {
	expr := &ast.FreetextExpression{Token: p.curToken}

	if !p.expectPeek(token.LPAREN) {
		return nil
	}
	p.nextToken() // move past (

	// Parse column(s) - could be single column, (col1, col2), or *
	if p.curTokenIs(token.ASTERISK) {
		expr.Columns = []string{"*"}
		p.nextToken()
	} else if p.curTokenIs(token.LPAREN) {
		// Multiple columns
		p.nextToken() // move past (
		for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
			expr.Columns = append(expr.Columns, p.curToken.Literal)
			p.nextToken()
			if p.curTokenIs(token.COMMA) {
				p.nextToken()
			}
		}
		p.nextToken() // move past )
	} else {
		// Single column
		expr.Columns = []string{p.curToken.Literal}
		p.nextToken()
	}

	// Expect comma
	if p.curTokenIs(token.COMMA) {
		p.nextToken()
	}

	// Parse search term
	expr.SearchTerm = p.parseExpression(LOWEST)

	// Check for LANGUAGE option
	if p.peekTokenIs(token.COMMA) {
		p.nextToken() // move to comma
		p.nextToken() // move past comma
		if p.curTokenIs(token.LANGUAGE) {
			p.nextToken() // move past LANGUAGE
			expr.Language = p.curToken.Literal
		}
	}

	if p.peekTokenIs(token.RPAREN) {
		p.nextToken()
	}

	return expr
}

// parseContainsTableExpression parses CONTAINSTABLE(table, column, 'search term')
func (p *Parser) parseContainsTableExpression() ast.Expression {
	expr := &ast.ContainsTableExpression{Token: p.curToken}

	if !p.expectPeek(token.LPAREN) {
		return nil
	}
	p.nextToken() // move past (

	// Parse table name
	expr.TableName = p.curToken.Literal
	p.nextToken()

	// Expect comma
	if p.curTokenIs(token.COMMA) {
		p.nextToken()
	}

	// Parse column(s)
	if p.curTokenIs(token.ASTERISK) {
		expr.Columns = []string{"*"}
		p.nextToken()
	} else if p.curTokenIs(token.LPAREN) {
		p.nextToken()
		for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
			expr.Columns = append(expr.Columns, p.curToken.Literal)
			p.nextToken()
			if p.curTokenIs(token.COMMA) {
				p.nextToken()
			}
		}
		p.nextToken()
	} else {
		expr.Columns = []string{p.curToken.Literal}
		p.nextToken()
	}

	// Expect comma
	if p.curTokenIs(token.COMMA) {
		p.nextToken()
	}

	// Parse search term
	expr.SearchTerm = p.parseExpression(LOWEST)

	if p.peekTokenIs(token.RPAREN) {
		p.nextToken()
	}

	return expr
}

// parseFreetextTableExpression parses FREETEXTTABLE(table, column, 'search term')
func (p *Parser) parseFreetextTableExpression() ast.Expression {
	expr := &ast.FreetextTableExpression{Token: p.curToken}

	if !p.expectPeek(token.LPAREN) {
		return nil
	}
	p.nextToken() // move past (

	// Parse table name
	expr.TableName = p.curToken.Literal
	p.nextToken()

	// Expect comma
	if p.curTokenIs(token.COMMA) {
		p.nextToken()
	}

	// Parse column(s)
	if p.curTokenIs(token.ASTERISK) {
		expr.Columns = []string{"*"}
		p.nextToken()
	} else if p.curTokenIs(token.LPAREN) {
		p.nextToken()
		for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
			expr.Columns = append(expr.Columns, p.curToken.Literal)
			p.nextToken()
			if p.curTokenIs(token.COMMA) {
				p.nextToken()
			}
		}
		p.nextToken()
	} else {
		expr.Columns = []string{p.curToken.Literal}
		p.nextToken()
	}

	// Expect comma
	if p.curTokenIs(token.COMMA) {
		p.nextToken()
	}

	// Parse search term
	expr.SearchTerm = p.parseExpression(LOWEST)

	if p.peekTokenIs(token.RPAREN) {
		p.nextToken()
	}

	return expr
}

// parseCreateFulltextStatement handles CREATE FULLTEXT CATALOG/INDEX
func (p *Parser) parseCreateFulltextStatement(createToken token.Token) ast.Statement {
	p.nextToken() // move past FULLTEXT

	if p.curTokenIs(token.CATALOG) {
		return p.parseCreateFulltextCatalogStatement(createToken)
	} else if p.curTokenIs(token.INDEX) {
		return p.parseCreateFulltextIndexStatement(createToken)
	}

	return nil
}

// parseCreateFulltextCatalogStatement parses CREATE FULLTEXT CATALOG name
func (p *Parser) parseCreateFulltextCatalogStatement(createToken token.Token) ast.Statement {
	stmt := &ast.CreateFulltextCatalogStatement{Token: createToken}
	p.nextToken() // move past CATALOG

	stmt.Name = p.curToken.Literal
	p.nextToken()

	// Parse optional clauses
	for !p.curTokenIs(token.EOF) && !p.curTokenIs(token.SEMICOLON) {
		if p.curTokenIs(token.ON) {
			p.nextToken() // move past ON
			if strings.ToUpper(p.curToken.Literal) == "FILEGROUP" {
				p.nextToken() // move past FILEGROUP
				stmt.OnFilegroup = p.curToken.Literal
				p.nextToken()
			}
		} else if p.curTokenIs(token.AS) {
			p.nextToken() // move past AS
			if p.curTokenIs(token.DEFAULT_KW) {
				stmt.AsDefault = true
				p.nextToken()
			}
		} else if p.curTokenIs(token.AUTHORIZATION) {
			p.nextToken() // move past AUTHORIZATION
			stmt.Authorization = p.curToken.Literal
			p.nextToken()
		} else {
			break
		}
	}

	return stmt
}

// parseCreateFulltextIndexStatement parses CREATE FULLTEXT INDEX ON table(columns) KEY INDEX idx
func (p *Parser) parseCreateFulltextIndexStatement(createToken token.Token) ast.Statement {
	stmt := &ast.CreateFulltextIndexStatement{Token: createToken}
	p.nextToken() // move past INDEX

	// Expect ON
	if p.curTokenIs(token.ON) {
		p.nextToken()
	}

	// Parse table name
	stmt.TableName = p.parseQualifiedIdentifier()

	// Parse column list
	if p.peekTokenIs(token.LPAREN) {
		p.nextToken() // move to (
		p.nextToken() // move past (

		for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
			col := &ast.FulltextColumn{}
			col.Name = p.curToken.Literal
			p.nextToken()

			// Check for TYPE COLUMN or LANGUAGE
			for strings.ToUpper(p.curToken.Literal) == "TYPE" || p.curTokenIs(token.LANGUAGE) {
				if strings.ToUpper(p.curToken.Literal) == "TYPE" {
					p.nextToken() // move past TYPE
					if strings.ToUpper(p.curToken.Literal) == "COLUMN" {
						p.nextToken() // move past COLUMN
						col.TypeColumn = p.curToken.Literal
						p.nextToken()
					}
				} else if p.curTokenIs(token.LANGUAGE) {
					p.nextToken() // move past LANGUAGE
					col.Language = p.curToken.Literal
					p.nextToken()
				}
			}

			stmt.Columns = append(stmt.Columns, col)

			if p.curTokenIs(token.COMMA) {
				p.nextToken()
			}
		}
		p.nextToken() // move past )
	}

	// Parse KEY INDEX
	if p.curTokenIs(token.KEY) {
		p.nextToken() // move past KEY
		if p.curTokenIs(token.INDEX) {
			p.nextToken() // move past INDEX
		}
		stmt.KeyIndex = p.curToken.Literal
		p.nextToken()
	}

	// Parse ON catalog
	if p.curTokenIs(token.ON) {
		p.nextToken() // move past ON
		stmt.OnCatalog = p.curToken.Literal
		p.nextToken()
	}

	// Parse WITH options
	if p.curTokenIs(token.WITH) {
		p.nextToken() // move past WITH
		if p.curTokenIs(token.LPAREN) {
			// Skip to matching )
			depth := 1
			for depth > 0 && !p.curTokenIs(token.EOF) {
				p.nextToken()
				if p.curTokenIs(token.LPAREN) {
					depth++
				} else if p.curTokenIs(token.RPAREN) {
					depth--
				}
			}
			p.nextToken() // move past final )
		}
	}

	return stmt
}

// parseAlterFulltextStatement handles ALTER FULLTEXT INDEX
func (p *Parser) parseAlterFulltextStatement(alterToken token.Token) ast.Statement {
	p.nextToken() // move past FULLTEXT

	if p.curTokenIs(token.INDEX) {
		return p.parseAlterFulltextIndexStatement(alterToken)
	}

	return nil
}

// parseAlterFulltextIndexStatement parses ALTER FULLTEXT INDEX ON table ADD/DROP/ENABLE/DISABLE
func (p *Parser) parseAlterFulltextIndexStatement(alterToken token.Token) ast.Statement {
	stmt := &ast.AlterFulltextIndexStatement{Token: alterToken}
	p.nextToken() // move past INDEX

	// Expect ON
	if p.curTokenIs(token.ON) {
		p.nextToken()
	}

	// Parse table name
	stmt.TableName = p.parseQualifiedIdentifier()
	p.nextToken()

	// Parse action: ADD, DROP, ENABLE, DISABLE, START, STOP, etc.
	action := strings.ToUpper(p.curToken.Literal)
	stmt.Action = action
	p.nextToken()

	// For ADD/DROP, parse column list
	if action == "ADD" || action == "DROP" {
		if p.curTokenIs(token.LPAREN) {
			p.nextToken() // move past (

			for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
				col := &ast.FulltextColumn{}
				col.Name = p.curToken.Literal
				p.nextToken()

				// Check for LANGUAGE
				if p.curTokenIs(token.LANGUAGE) {
					p.nextToken() // move past LANGUAGE
					col.Language = p.curToken.Literal
					p.nextToken()
				}

				stmt.Columns = append(stmt.Columns, col)

				if p.curTokenIs(token.COMMA) {
					p.nextToken()
				}
			}
			p.nextToken() // move past )
		}
	}

	return stmt
}

// parseDropFulltextStatement handles DROP FULLTEXT INDEX/CATALOG
func (p *Parser) parseDropFulltextStatement(dropToken token.Token) ast.Statement {
	p.nextToken() // move past FULLTEXT

	if p.curTokenIs(token.INDEX) {
		return p.parseDropFulltextIndexStatement(dropToken)
	} else if p.curTokenIs(token.CATALOG) {
		return p.parseDropFulltextCatalogStatement(dropToken)
	}

	return nil
}

// parseDropFulltextIndexStatement parses DROP FULLTEXT INDEX ON table
func (p *Parser) parseDropFulltextIndexStatement(dropToken token.Token) ast.Statement {
	stmt := &ast.DropFulltextIndexStatement{Token: dropToken}
	p.nextToken() // move past INDEX

	// Expect ON
	if p.curTokenIs(token.ON) {
		p.nextToken()
	}

	// Parse table name
	stmt.TableName = p.parseQualifiedIdentifier()

	return stmt
}

// parseDropFulltextCatalogStatement parses DROP FULLTEXT CATALOG name
func (p *Parser) parseDropFulltextCatalogStatement(dropToken token.Token) ast.Statement {
	stmt := &ast.DropFulltextCatalogStatement{Token: dropToken}
	p.nextToken() // move past CATALOG

	stmt.Name = p.curToken.Literal
	p.nextToken()

	return stmt
}

// -----------------------------------------------------------------------------
// Stage 11: Resource Governor & Availability Groups
// -----------------------------------------------------------------------------

// parseCreateResourcePoolStatement parses CREATE RESOURCE POOL name WITH (options)
func (p *Parser) parseCreateResourcePoolStatement(createToken token.Token) ast.Statement {
	stmt := &ast.CreateResourcePoolStatement{Token: createToken, Options: make(map[string]string)}
	p.nextToken() // move past RESOURCE

	if p.curTokenIs(token.POOL) {
		p.nextToken() // move past POOL
	}

	stmt.Name = p.curToken.Literal
	p.nextToken()

	// Parse WITH options
	if p.curTokenIs(token.WITH) {
		p.nextToken() // move past WITH
		if p.curTokenIs(token.LPAREN) {
			p.nextToken() // move past (
			for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
				optName := strings.ToUpper(p.curToken.Literal)
				p.nextToken()
				if p.curTokenIs(token.EQ) {
					p.nextToken() // move past =
				}
				optValue := p.curToken.Literal
				stmt.Options[optName] = optValue
				p.nextToken()
				if p.curTokenIs(token.COMMA) {
					p.nextToken()
				}
			}
			p.nextToken() // move past )
		}
	}

	return stmt
}

// parseAlterResourceStatement handles ALTER RESOURCE POOL and ALTER RESOURCE GOVERNOR
func (p *Parser) parseAlterResourceStatement(alterToken token.Token) ast.Statement {
	p.nextToken() // move past RESOURCE

	if p.curTokenIs(token.POOL) {
		return p.parseAlterResourcePoolStatement(alterToken)
	} else if p.curTokenIs(token.GOVERNOR) {
		return p.parseAlterResourceGovernorStatement(alterToken)
	}

	return nil
}

// parseAlterResourcePoolStatement parses ALTER RESOURCE POOL name WITH (options)
func (p *Parser) parseAlterResourcePoolStatement(alterToken token.Token) ast.Statement {
	stmt := &ast.AlterResourcePoolStatement{Token: alterToken, Options: make(map[string]string)}
	p.nextToken() // move past POOL

	stmt.Name = p.curToken.Literal
	p.nextToken()

	// Parse WITH options
	if p.curTokenIs(token.WITH) {
		p.nextToken() // move past WITH
		if p.curTokenIs(token.LPAREN) {
			p.nextToken() // move past (
			for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
				optName := strings.ToUpper(p.curToken.Literal)
				p.nextToken()
				if p.curTokenIs(token.EQ) {
					p.nextToken() // move past =
				}
				optValue := p.curToken.Literal
				stmt.Options[optName] = optValue
				p.nextToken()
				if p.curTokenIs(token.COMMA) {
					p.nextToken()
				}
			}
			p.nextToken() // move past )
		}
	}

	return stmt
}

// parseAlterResourceGovernorStatement parses ALTER RESOURCE GOVERNOR RECONFIGURE/DISABLE/WITH
func (p *Parser) parseAlterResourceGovernorStatement(alterToken token.Token) ast.Statement {
	stmt := &ast.AlterResourceGovernorStatement{Token: alterToken}
	p.nextToken() // move past GOVERNOR

	// Check for action or WITH clause
	if p.curTokenIs(token.RECONFIGURE) {
		stmt.Action = "RECONFIGURE"
		p.nextToken()
	} else if p.curTokenIs(token.DISABLE) {
		stmt.Action = "DISABLE"
		p.nextToken()
	} else if strings.ToUpper(p.curToken.Literal) == "RESET" {
		p.nextToken() // move past RESET
		if strings.ToUpper(p.curToken.Literal) == "STATISTICS" {
			stmt.Action = "RESET STATISTICS"
			p.nextToken()
		}
	} else if p.curTokenIs(token.WITH) {
		p.nextToken() // move past WITH
		if p.curTokenIs(token.LPAREN) {
			p.nextToken() // move past (
			// Handle CLASSIFIER_FUNCTION = ...
			if p.curTokenIs(token.CLASSIFIER) || strings.ToUpper(p.curToken.Literal) == "CLASSIFIER_FUNCTION" {
				p.nextToken() // move past CLASSIFIER_FUNCTION
			}
			if p.curTokenIs(token.EQ) {
				p.nextToken() // move past =
			}
			// Classifier function name or NULL
			if p.curTokenIs(token.NULL) {
				stmt.ClassifierFunction = "NULL"
			} else {
				stmt.ClassifierFunction = p.curToken.Literal
				// Handle qualified name
				for p.peekTokenIs(token.DOT) {
					p.nextToken() // move to dot
					p.nextToken() // move past dot
					stmt.ClassifierFunction += "." + p.curToken.Literal
				}
			}
			p.nextToken()
			if p.curTokenIs(token.RPAREN) {
				p.nextToken()
			}
		}
	}

	return stmt
}

// parseDropResourcePoolStatement parses DROP RESOURCE POOL name
func (p *Parser) parseDropResourcePoolStatement(dropToken token.Token) ast.Statement {
	stmt := &ast.DropResourcePoolStatement{Token: dropToken}
	p.nextToken() // move past RESOURCE

	if p.curTokenIs(token.POOL) {
		p.nextToken() // move past POOL
	}

	stmt.Name = p.curToken.Literal
	p.nextToken()

	return stmt
}

// parseCreateWorkloadGroupStatement parses CREATE WORKLOAD GROUP name WITH (options) USING pool
func (p *Parser) parseCreateWorkloadGroupStatement(createToken token.Token) ast.Statement {
	stmt := &ast.CreateWorkloadGroupStatement{Token: createToken, Options: make(map[string]string)}
	p.nextToken() // move past WORKLOAD

	if p.curTokenIs(token.GROUP) {
		p.nextToken() // move past GROUP
	}

	stmt.Name = p.curToken.Literal
	p.nextToken()

	// Parse WITH options (optional)
	if p.curTokenIs(token.WITH) {
		p.nextToken() // move past WITH
		if p.curTokenIs(token.LPAREN) {
			p.nextToken() // move past (
			for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
				optName := strings.ToUpper(p.curToken.Literal)
				p.nextToken()
				if p.curTokenIs(token.EQ) {
					p.nextToken() // move past =
				}
				optValue := p.curToken.Literal
				stmt.Options[optName] = optValue
				p.nextToken()
				if p.curTokenIs(token.COMMA) {
					p.nextToken()
				}
			}
			p.nextToken() // move past )
		}
	}

	// Parse USING pool_name
	if p.curTokenIs(token.USING) {
		p.nextToken() // move past USING
		stmt.PoolName = p.curToken.Literal
		p.nextToken()
	}

	return stmt
}

// parseAlterWorkloadGroupStatement parses ALTER WORKLOAD GROUP name WITH (options) USING pool
func (p *Parser) parseAlterWorkloadGroupStatement(alterToken token.Token) ast.Statement {
	stmt := &ast.AlterWorkloadGroupStatement{Token: alterToken, Options: make(map[string]string)}
	p.nextToken() // move past WORKLOAD

	if p.curTokenIs(token.GROUP) {
		p.nextToken() // move past GROUP
	}

	stmt.Name = p.curToken.Literal
	p.nextToken()

	// Parse WITH options (optional)
	if p.curTokenIs(token.WITH) {
		p.nextToken() // move past WITH
		if p.curTokenIs(token.LPAREN) {
			p.nextToken() // move past (
			for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
				optName := strings.ToUpper(p.curToken.Literal)
				p.nextToken()
				if p.curTokenIs(token.EQ) {
					p.nextToken() // move past =
				}
				optValue := p.curToken.Literal
				stmt.Options[optName] = optValue
				p.nextToken()
				if p.curTokenIs(token.COMMA) {
					p.nextToken()
				}
			}
			p.nextToken() // move past )
		}
	}

	// Parse USING pool_name
	if p.curTokenIs(token.USING) {
		p.nextToken() // move past USING
		stmt.PoolName = p.curToken.Literal
		p.nextToken()
	}

	return stmt
}

// parseDropWorkloadGroupStatement parses DROP WORKLOAD GROUP name
func (p *Parser) parseDropWorkloadGroupStatement(dropToken token.Token) ast.Statement {
	stmt := &ast.DropWorkloadGroupStatement{Token: dropToken}
	p.nextToken() // move past WORKLOAD

	if p.curTokenIs(token.GROUP) {
		p.nextToken() // move past GROUP
	}

	stmt.Name = p.curToken.Literal
	p.nextToken()

	return stmt
}

// parseCreateAvailabilityGroupStatement parses CREATE AVAILABILITY GROUP name FOR DATABASE db REPLICA ON ...
func (p *Parser) parseCreateAvailabilityGroupStatement(createToken token.Token) ast.Statement {
	stmt := &ast.CreateAvailabilityGroupStatement{Token: createToken}
	p.nextToken() // move past AVAILABILITY

	if p.curTokenIs(token.GROUP) {
		p.nextToken() // move past GROUP
	}

	stmt.Name = p.curToken.Literal
	p.nextToken()

	// Parse FOR DATABASE clause (optional)
	if p.curTokenIs(token.FOR) {
		p.nextToken() // move past FOR
		if p.curTokenIs(token.DATABASE) {
			p.nextToken() // move past DATABASE
			// Parse database names
			for {
				stmt.Databases = append(stmt.Databases, p.curToken.Literal)
				p.nextToken()
				if p.curTokenIs(token.COMMA) {
					p.nextToken()
				} else {
					break
				}
			}
		}
	}

	// Parse REPLICA ON clauses
	for p.curTokenIs(token.REPLICA) {
		p.nextToken() // move past REPLICA
		if p.curTokenIs(token.ON) {
			p.nextToken() // move past ON
		}

		replica := &ast.AvailabilityReplica{Options: make(map[string]string)}

		// Server name (may be quoted)
		if p.curTokenIs(token.STRING) || p.curTokenIs(token.NSTRING) {
			replica.ServerName = p.curToken.Literal
		} else {
			replica.ServerName = p.curToken.Literal
		}
		p.nextToken()

		// Parse WITH (options)
		if p.curTokenIs(token.WITH) {
			p.nextToken() // move past WITH
			if p.curTokenIs(token.LPAREN) {
				p.nextToken() // move past (
				for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
					optName := strings.ToUpper(p.curToken.Literal)
					p.nextToken()
					if p.curTokenIs(token.EQ) {
						p.nextToken() // move past =
					}

					// Handle special options
					if optName == "ENDPOINT_URL" {
						if p.curTokenIs(token.STRING) || p.curTokenIs(token.NSTRING) {
							replica.EndpointURL = p.curToken.Literal
						} else {
							replica.EndpointURL = p.curToken.Literal
						}
					} else if optName == "AVAILABILITY_MODE" {
						replica.AvailabilityMode = strings.ToUpper(p.curToken.Literal)
					} else if optName == "FAILOVER_MODE" {
						replica.FailoverMode = strings.ToUpper(p.curToken.Literal)
					} else {
						replica.Options[optName] = p.curToken.Literal
					}
					p.nextToken()
					if p.curTokenIs(token.COMMA) {
						p.nextToken()
					}
				}
				p.nextToken() // move past )
			}
		}

		stmt.Replicas = append(stmt.Replicas, replica)

		// Check for another REPLICA or comma-separated replica
		if p.curTokenIs(token.COMMA) {
			p.nextToken()
		}
	}

	return stmt
}

// parseAlterAvailabilityGroupStatement parses ALTER AVAILABILITY GROUP name action
func (p *Parser) parseAlterAvailabilityGroupStatement(alterToken token.Token) ast.Statement {
	stmt := &ast.AlterAvailabilityGroupStatement{Token: alterToken}
	p.nextToken() // move past AVAILABILITY

	if p.curTokenIs(token.GROUP) {
		p.nextToken() // move past GROUP
	}

	stmt.Name = p.curToken.Literal
	p.nextToken()

	// Parse action
	action := strings.ToUpper(p.curToken.Literal)

	switch action {
	case "ADD":
		p.nextToken() // move past ADD
		if p.curTokenIs(token.DATABASE) {
			stmt.Action = "ADD DATABASE"
			p.nextToken() // move past DATABASE
			// Parse database name(s)
			for {
				stmt.Databases = append(stmt.Databases, p.curToken.Literal)
				p.nextToken()
				if p.curTokenIs(token.COMMA) {
					p.nextToken()
				} else {
					break
				}
			}
		} else if p.curTokenIs(token.REPLICA) {
			stmt.Action = "ADD REPLICA"
			// Could parse replica details here
			p.nextToken()
		}
	case "REMOVE":
		p.nextToken() // move past REMOVE
		if p.curTokenIs(token.DATABASE) {
			stmt.Action = "REMOVE DATABASE"
			p.nextToken() // move past DATABASE
			for {
				stmt.Databases = append(stmt.Databases, p.curToken.Literal)
				p.nextToken()
				if p.curTokenIs(token.COMMA) {
					p.nextToken()
				} else {
					break
				}
			}
		} else if p.curTokenIs(token.REPLICA) {
			stmt.Action = "REMOVE REPLICA"
			p.nextToken()
		}
	case "FAILOVER":
		stmt.Action = "FAILOVER"
		p.nextToken()
	case "FORCE_FAILOVER_ALLOW_DATA_LOSS":
		stmt.Action = "FORCE_FAILOVER_ALLOW_DATA_LOSS"
		p.nextToken()
	case "JOIN":
		stmt.Action = "JOIN"
		p.nextToken()
	case "OFFLINE":
		stmt.Action = "OFFLINE"
		p.nextToken()
	case "ONLINE":
		stmt.Action = "ONLINE"
		p.nextToken()
	default:
		stmt.Action = action
		p.nextToken()
	}

	return stmt
}

// parseDropAvailabilityGroupStatement parses DROP AVAILABILITY GROUP name
func (p *Parser) parseDropAvailabilityGroupStatement(dropToken token.Token) ast.Statement {
	stmt := &ast.DropAvailabilityGroupStatement{Token: dropToken}
	p.nextToken() // move past AVAILABILITY

	if p.curTokenIs(token.GROUP) {
		p.nextToken() // move past GROUP
	}

	stmt.Name = p.curToken.Literal
	p.nextToken()

	return stmt
}

// -----------------------------------------------------------------------------
// Stage 12: Service Broker
// -----------------------------------------------------------------------------

// parseCreateMessageTypeStatement parses CREATE MESSAGE TYPE name VALIDATION = ...
func (p *Parser) parseCreateMessageTypeStatement(createToken token.Token) ast.Statement {
	stmt := &ast.CreateMessageTypeStatement{Token: createToken}
	p.nextToken() // move past MESSAGE

	if strings.ToUpper(p.curToken.Literal) == "TYPE" {
		p.nextToken() // move past TYPE
	}

	stmt.Name = p.curToken.Literal
	p.nextToken()

	// Optional AUTHORIZATION
	if p.curTokenIs(token.AUTHORIZATION) {
		p.nextToken()
		stmt.Authorization = p.curToken.Literal
		p.nextToken()
	}

	// VALIDATION = NONE | EMPTY | WELL_FORMED_XML | VALID_XML WITH SCHEMA COLLECTION
	if p.curTokenIs(token.VALIDATION) {
		p.nextToken() // move past VALIDATION
		if p.curTokenIs(token.EQ) {
			p.nextToken() // move past =
		}
		stmt.Validation = strings.ToUpper(p.curToken.Literal)
		p.nextToken()
	}

	return stmt
}

// parseCreateContractStatement parses CREATE CONTRACT name (message_type SENT BY ...)
func (p *Parser) parseCreateContractStatement(createToken token.Token) ast.Statement {
	stmt := &ast.CreateContractStatement{Token: createToken}
	p.nextToken() // move past CONTRACT

	stmt.Name = p.curToken.Literal
	p.nextToken()

	// Optional AUTHORIZATION
	if p.curTokenIs(token.AUTHORIZATION) {
		p.nextToken()
		stmt.Authorization = p.curToken.Literal
		p.nextToken()
	}

	// Parse message types (message_type SENT BY INITIATOR|TARGET|ANY)
	if p.curTokenIs(token.LPAREN) {
		p.nextToken() // move past (
		for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
			msg := &ast.ContractMessage{}
			msg.MessageType = p.curToken.Literal
			p.nextToken()

			// SENT BY
			if p.curTokenIs(token.SENT) {
				p.nextToken() // move past SENT
				if p.curTokenIs(token.BY) {
					p.nextToken() // move past BY
				}
				msg.SentBy = strings.ToUpper(p.curToken.Literal)
				p.nextToken()
			}

			stmt.Messages = append(stmt.Messages, msg)

			if p.curTokenIs(token.COMMA) {
				p.nextToken()
			}
		}
		p.nextToken() // move past )
	}

	return stmt
}

// parseCreateQueueStatement parses CREATE QUEUE name WITH (options)
func (p *Parser) parseCreateQueueStatement(createToken token.Token) ast.Statement {
	stmt := &ast.CreateQueueStatement{Token: createToken, Options: make(map[string]string)}
	p.nextToken() // move past QUEUE

	stmt.Name = p.parseQualifiedIdentifier()

	// Parse WITH options
	if p.peekTokenIs(token.WITH) {
		p.nextToken() // move to WITH
		p.nextToken() // move past WITH
		if p.curTokenIs(token.LPAREN) {
			p.nextToken() // move past (
			for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
				optName := strings.ToUpper(p.curToken.Literal)
				p.nextToken()
				if p.curTokenIs(token.EQ) {
					p.nextToken() // move past =
				}
				optValue := p.curToken.Literal
				stmt.Options[optName] = optValue
				p.nextToken()
				if p.curTokenIs(token.COMMA) {
					p.nextToken()
				}
			}
			p.nextToken() // move past )
		}
	}

	return stmt
}

// parseAlterQueueStatement parses ALTER QUEUE name WITH (options) or WITH STATUS = ON
func (p *Parser) parseAlterQueueStatement(alterToken token.Token) ast.Statement {
	stmt := &ast.AlterQueueStatement{Token: alterToken, Options: make(map[string]string)}
	p.nextToken() // move past QUEUE

	stmt.Name = p.parseQualifiedIdentifier()

	// Parse WITH options - skip until end of statement
	if p.peekTokenIs(token.WITH) {
		p.nextToken() // move to WITH
		// Skip everything until semicolon, GO, or EOF
		depth := 0
		for !p.peekTokenIs(token.SEMICOLON) && !p.peekTokenIs(token.GO) && !p.peekTokenIs(token.EOF) {
			p.nextToken()
			if p.curTokenIs(token.LPAREN) {
				depth++
			} else if p.curTokenIs(token.RPAREN) {
				depth--
			}
		}
	}

	return stmt
}

// parseCreateServiceStatement parses CREATE SERVICE name ON QUEUE queue (contract, ...)
func (p *Parser) parseCreateServiceStatement(createToken token.Token) ast.Statement {
	stmt := &ast.CreateServiceStatement{Token: createToken}
	p.nextToken() // move past SERVICE

	stmt.Name = p.curToken.Literal
	p.nextToken()

	// Optional AUTHORIZATION
	if p.curTokenIs(token.AUTHORIZATION) {
		p.nextToken()
		stmt.Authorization = p.curToken.Literal
		p.nextToken()
	}

	// ON QUEUE queue_name (possibly qualified)
	if p.curTokenIs(token.ON) {
		p.nextToken() // move past ON
		if p.curTokenIs(token.QUEUE) {
			p.nextToken() // move past QUEUE
		}
		// Parse qualified queue name
		queueName := p.parseQualifiedIdentifier()
		stmt.OnQueue = queueName.String()
	}

	// Contract list (contract1, contract2, ...)
	if p.peekTokenIs(token.LPAREN) {
		p.nextToken() // move to (
		p.nextToken() // move past (
		for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
			stmt.Contracts = append(stmt.Contracts, p.curToken.Literal)
			p.nextToken()
			if p.curTokenIs(token.COMMA) {
				p.nextToken()
			}
		}
		p.nextToken() // move past )
	}

	return stmt
}

// parseBeginDialogStatement parses BEGIN DIALOG @handle FROM SERVICE ... TO SERVICE ... ON CONTRACT ...
func (p *Parser) parseBeginDialogStatement() ast.Statement {
	stmt := &ast.BeginDialogStatement{Token: p.curToken, WithOptions: make(map[string]string)}
	p.nextToken() // move past BEGIN
	p.nextToken() // move past DIALOG

	// Optional CONVERSATION keyword
	if p.curTokenIs(token.CONVERSATION) {
		p.nextToken()
	}

	// Dialog handle variable
	stmt.DialogHandle = p.curToken.Literal
	p.nextToken()

	// FROM SERVICE
	if p.curTokenIs(token.FROM) {
		p.nextToken() // move past FROM
		if p.curTokenIs(token.SERVICE) {
			p.nextToken() // move past SERVICE
		}
		stmt.FromService = p.curToken.Literal
		p.nextToken()
	}

	// TO SERVICE
	if p.curTokenIs(token.TO) {
		p.nextToken() // move past TO
		if p.curTokenIs(token.SERVICE) {
			p.nextToken() // move past SERVICE
		}
		// Service name is often a string
		if p.curTokenIs(token.STRING) || p.curTokenIs(token.NSTRING) {
			stmt.ToService = p.curToken.Literal
		} else {
			stmt.ToService = p.curToken.Literal
		}
		p.nextToken()
	}

	// ON CONTRACT
	if p.curTokenIs(token.ON) {
		p.nextToken() // move past ON
		if p.curTokenIs(token.CONTRACT) {
			p.nextToken() // move past CONTRACT
		}
		stmt.OnContract = p.curToken.Literal
		p.nextToken()
	}

	// WITH options
	if p.curTokenIs(token.WITH) {
		p.nextToken() // move past WITH
		// Parse options
		for !p.curTokenIs(token.EOF) && !p.curTokenIs(token.SEMICOLON) {
			optName := strings.ToUpper(p.curToken.Literal)
			p.nextToken()
			if p.curTokenIs(token.EQ) {
				p.nextToken() // move past =
			}
			optValue := p.curToken.Literal
			stmt.WithOptions[optName] = optValue
			p.nextToken()
			if p.curTokenIs(token.COMMA) {
				p.nextToken()
			} else {
				break
			}
		}
	}

	return stmt
}

// parseSendOnConversationStatement parses SEND ON CONVERSATION @handle MESSAGE TYPE name (body)
func (p *Parser) parseSendOnConversationStatement() ast.Statement {
	stmt := &ast.SendOnConversationStatement{Token: p.curToken}
	p.nextToken() // move past SEND

	// ON CONVERSATION
	if p.curTokenIs(token.ON) {
		p.nextToken() // move past ON
	}
	if p.curTokenIs(token.CONVERSATION) {
		p.nextToken() // move past CONVERSATION
	}

	// Conversation handle
	stmt.ConversationHandle = p.curToken.Literal
	p.nextToken()

	// Optional MESSAGE TYPE
	if p.curTokenIs(token.MESSAGE) {
		p.nextToken() // move past MESSAGE
		if strings.ToUpper(p.curToken.Literal) == "TYPE" {
			p.nextToken() // move past TYPE
		}
		stmt.MessageType = p.curToken.Literal
		p.nextToken()
	}

	// Message body in parentheses
	if p.curTokenIs(token.LPAREN) {
		p.nextToken() // move past (
		stmt.MessageBody = p.parseExpression(LOWEST)
		if p.peekTokenIs(token.RPAREN) {
			p.nextToken()
		}
	}

	return stmt
}

// parseReceiveStatement parses RECEIVE TOP(n) columns FROM queue
func (p *Parser) parseReceiveStatement() ast.Statement {
	stmt := &ast.ReceiveStatement{Token: p.curToken}
	p.nextToken() // move past RECEIVE

	// Optional TOP(n)
	if p.curTokenIs(token.TOP) {
		p.nextToken() // move past TOP
		if p.curTokenIs(token.LPAREN) {
			p.nextToken() // move past (
			stmt.Top = p.parseExpression(LOWEST)
			if p.peekTokenIs(token.RPAREN) {
				p.nextToken() // move to )
			}
			p.nextToken() // move past )
		}
	}

	// Parse columns: @var = column_name, ...
	for !p.curTokenIs(token.FROM) && !p.curTokenIs(token.EOF) {
		col := &ast.ReceiveColumn{}

		// Check for @var = column pattern
		if p.curTokenIs(token.VARIABLE) {
			col.Variable = p.curToken.Literal
			p.nextToken()
			if p.curTokenIs(token.EQ) {
				p.nextToken() // move past =
			}
		}

		col.ColumnName = p.curToken.Literal
		stmt.Columns = append(stmt.Columns, col)
		p.nextToken()

		if p.curTokenIs(token.COMMA) {
			p.nextToken()
		}
	}

	// FROM queue
	if p.curTokenIs(token.FROM) {
		p.nextToken() // move past FROM
		stmt.FromQueue = p.parseQualifiedIdentifier()
	}

	return stmt
}

// parseEndConversationStatement parses END CONVERSATION @handle [WITH CLEANUP | WITH ERROR ... DESCRIPTION ...]
func (p *Parser) parseEndConversationStatement() ast.Statement {
	stmt := &ast.EndConversationStatement{Token: p.curToken}
	p.nextToken() // move past END_CONVERSATION

	// Conversation handle
	stmt.ConversationHandle = p.curToken.Literal

	// WITH CLEANUP or WITH ERROR
	if p.peekTokenIs(token.WITH) {
		p.nextToken() // move to WITH
		p.nextToken() // move past WITH
		if strings.ToUpper(p.curToken.Literal) == "CLEANUP" {
			stmt.WithCleanup = true
			p.nextToken()
		} else if strings.ToUpper(p.curToken.Literal) == "ERROR" {
			p.nextToken() // move past ERROR
			if p.curTokenIs(token.EQ) {
				p.nextToken() // move past =
			}
			stmt.WithError = p.parseExpression(LOWEST)
			// DESCRIPTION = ...
			if p.peekTokenIs(token.IDENT) && strings.ToUpper(p.peekToken.Literal) == "DESCRIPTION" {
				p.nextToken()
				p.nextToken() // move past DESCRIPTION
				if p.curTokenIs(token.EQ) {
					p.nextToken()
				}
				stmt.ErrorDescription = p.parseExpression(LOWEST)
			}
		}
	}

	return stmt
}

// parseGetConversationGroupStatement parses GET CONVERSATION GROUP @group_id FROM queue
func (p *Parser) parseGetConversationGroupStatement() ast.Statement {
	stmt := &ast.GetConversationGroupStatement{Token: p.curToken}
	p.nextToken() // move past GET

	// CONVERSATION GROUP
	if p.curTokenIs(token.CONVERSATION) {
		p.nextToken() // move past CONVERSATION
	}
	if p.curTokenIs(token.GROUP) {
		p.nextToken() // move past GROUP
	}

	// Group ID variable
	stmt.GroupId = p.curToken.Literal
	p.nextToken()

	// FROM queue
	if p.curTokenIs(token.FROM) {
		p.nextToken() // move past FROM
		stmt.FromQueue = p.parseQualifiedIdentifier()
	}

	return stmt
}

// parseMoveConversationStatement parses MOVE CONVERSATION @handle TO @group_id
func (p *Parser) parseMoveConversationStatement() ast.Statement {
	stmt := &ast.MoveConversationStatement{Token: p.curToken}
	p.nextToken() // move past MOVE

	if p.curTokenIs(token.CONVERSATION) {
		p.nextToken() // move past CONVERSATION
	}

	// Conversation handle
	stmt.ConversationHandle = p.curToken.Literal
	p.nextToken()

	// TO group_id
	if p.curTokenIs(token.TO) {
		p.nextToken() // move past TO
		stmt.ToGroupId = p.curToken.Literal
		p.nextToken()
	}

	return stmt
}

// parseDropServiceBrokerObject parses DROP MESSAGE TYPE/CONTRACT/QUEUE/SERVICE name
func (p *Parser) parseDropServiceBrokerObject(dropToken token.Token, objectType string) ast.Statement {
	stmt := &ast.DropObjectStatement{Token: dropToken}
	stmt.ObjectType = objectType
	p.nextToken() // move past first keyword

	// Handle two-word types like MESSAGE TYPE
	if objectType == "MESSAGE TYPE" && strings.ToUpper(p.curToken.Literal) == "TYPE" {
		p.nextToken()
	}

	// Check for IF EXISTS
	if p.curTokenIs(token.IF) {
		p.nextToken() // move past IF
		if p.curTokenIs(token.EXISTS) {
			stmt.IfExists = true
			p.nextToken()
		}
	}

	name := p.parseQualifiedIdentifier()
	stmt.Names = append(stmt.Names, name)

	return stmt
}

// parseDropKeyStatement parses DROP SYMMETRIC KEY, DROP ASYMMETRIC KEY, DROP MASTER KEY
func (p *Parser) parseDropKeyStatement(dropToken token.Token) ast.Statement {
	stmt := &ast.DropObjectStatement{Token: dropToken}

	// Get key type (SYMMETRIC, ASYMMETRIC, MASTER)
	keyType := strings.ToUpper(p.curToken.Literal)
	p.nextToken()

	// Expect KEY
	if p.curTokenIs(token.KEY) {
		stmt.ObjectType = keyType + " KEY"
		p.nextToken()
	}

	// Check for IF EXISTS
	if p.curTokenIs(token.IF) {
		p.nextToken() // EXISTS
		if strings.ToUpper(p.curToken.Literal) == "EXISTS" {
			stmt.IfExists = true
			p.nextToken()
		}
	}

	// Parse key name (not for MASTER KEY)
	if keyType != "MASTER" {
		stmt.Names = append(stmt.Names, p.parseQualifiedIdentifier())
	}

	return stmt
}

func (p *Parser) parseCreateProcedureStatement() ast.Statement {
	stmt := &ast.CreateProcedureStatement{Token: p.curToken}
	p.nextToken()

	stmt.Name = p.parseQualifiedIdentifier()

	// Parse parameters
	if p.peekTokenIs(token.VARIABLE) || p.peekTokenIs(token.LPAREN) {
		if p.peekTokenIs(token.LPAREN) {
			p.nextToken()
		}
		p.nextToken()
		stmt.Parameters = p.parseParameterDefs()
	}

	// Handle WITH clause options (RECOMPILE, ENCRYPTION, EXECUTE AS)
	for p.peekTokenIs(token.WITH) {
		p.nextToken() // consume WITH
		p.nextToken() // move to option
		for {
			optionName := strings.ToUpper(p.curToken.Literal)
			if optionName == "EXECUTE" {
				// EXECUTE AS CALLER|OWNER|SELF|'user_name'
				p.nextToken() // move past EXECUTE
				if p.curTokenIs(token.AS) {
					p.nextToken() // move past AS
					p.nextToken() // move past CALLER/OWNER/SELF/user
				}
			} else if optionName == "RECOMPILE" || optionName == "ENCRYPTION" || optionName == "SCHEMABINDING" {
				// Single keyword options
			}
			if !p.peekTokenIs(token.COMMA) {
				break
			}
			p.nextToken() // consume comma
			p.nextToken() // move to next option
		}
	}

	// Skip to AS (the one that starts the body)
	for !p.curTokenIs(token.AS) && !p.curTokenIs(token.EOF) {
		p.nextToken()
	}
	p.nextToken()

	// Parse body - either BEGIN block or single/multiple statements
	if p.curTokenIs(token.BEGIN) {
		stmt.Body = p.parseBeginEndBlock()
	} else if p.curTokenIs(token.BEGIN_ATOMIC) {
		// BEGIN ATOMIC WITH (...) for natively compiled procedures
		stmt.Body = p.parseBeginAtomicBlock()
	} else {
		// Single or multiple statements without BEGIN/END
		// Wrap in a synthetic BEGIN/END block
		block := &ast.BeginEndBlock{Token: p.curToken}
		for !p.curTokenIs(token.EOF) && !p.curTokenIs(token.GO) {
			s := p.parseStatement()
			if s != nil {
				block.Statements = append(block.Statements, s)
			}
			if p.peekTokenIs(token.EOF) || p.peekTokenIs(token.GO) {
				break
			}
			p.nextToken()
		}
		stmt.Body = block
	}

	return stmt
}

func (p *Parser) parseParameterDefs() []*ast.ParameterDef {
	params := []*ast.ParameterDef{}

	param := p.parseParameterDef()
	params = append(params, param)

	for p.peekTokenIs(token.COMMA) {
		p.nextToken()
		p.nextToken()
		param = p.parseParameterDef()
		params = append(params, param)
	}

	return params
}

func (p *Parser) parseParameterDef() *ast.ParameterDef {
	param := &ast.ParameterDef{Name: p.curToken.Literal}
	p.nextToken()

	// Skip optional AS keyword
	if p.curTokenIs(token.AS) {
		p.nextToken()
	}

	param.DataType = p.parseDataType()

	// Check for READONLY (table-valued parameters)
	if p.peekTokenIs(token.READONLY) {
		p.nextToken()
		param.ReadOnly = true
	}

	// Check for default value
	if p.peekTokenIs(token.EQ) {
		p.nextToken()
		p.nextToken()
		param.Default = p.parseExpression(LOWEST)
	}

	// Check for OUTPUT
	if p.peekTokenIs(token.OUTPUT) {
		p.nextToken()
		param.Output = true
	}

	return param
}

func (p *Parser) parseThrowStatement() ast.Statement {
	stmt := &ast.ThrowStatement{Token: p.curToken}

	// THROW with no arguments (re-throw in CATCH block)
	// Can be followed by SEMICOLON, EOF, END, or statement terminator
	if p.peekTokenIs(token.SEMICOLON) || p.peekTokenIs(token.EOF) ||
		p.peekTokenIs(token.END) || p.peekTokenIs(token.GO) {
		return stmt
	}

	p.nextToken()
	stmt.ErrorNum = p.parseExpression(LOWEST)

	if !p.expectPeek(token.COMMA) {
		return nil
	}
	p.nextToken()
	stmt.Message = p.parseExpression(LOWEST)

	if !p.expectPeek(token.COMMA) {
		return nil
	}
	p.nextToken()
	stmt.State = p.parseExpression(LOWEST)

	return stmt
}

func (p *Parser) parseRaiserrorStatement() ast.Statement {
	stmt := &ast.RaiserrorStatement{Token: p.curToken}

	if !p.expectPeek(token.LPAREN) {
		return nil
	}
	p.nextToken()

	stmt.Message = p.parseExpression(LOWEST)

	if !p.expectPeek(token.COMMA) {
		return nil
	}
	p.nextToken()
	stmt.Severity = p.parseExpression(LOWEST)

	if !p.expectPeek(token.COMMA) {
		return nil
	}
	p.nextToken()
	stmt.State = p.parseExpression(LOWEST)

	// Parse additional format arguments
	for p.peekTokenIs(token.COMMA) {
		p.nextToken()
		p.nextToken()
		stmt.Args = append(stmt.Args, p.parseExpression(LOWEST))
	}

	p.expectPeek(token.RPAREN)

	// Parse WITH options (NOWAIT, LOG, SETERROR)
	if p.peekTokenIs(token.WITH) {
		p.nextToken() // consume WITH
		p.nextToken() // move to first option

		// Parse options
		for {
			stmt.Options = append(stmt.Options, strings.ToUpper(p.curToken.Literal))
			if !p.peekTokenIs(token.COMMA) {
				break
			}
			p.nextToken() // consume comma
			p.nextToken() // move to next option
		}
	}

	return stmt
}

func (p *Parser) parseCommitStatement() ast.Statement {
	stmt := &ast.CommitTransactionStatement{Token: p.curToken}

	if p.peekTokenIs(token.TRANSACTION) || p.peekTokenIs(token.TRAN) {
		p.nextToken()
	}

	if p.peekTokenIs(token.IDENT) {
		p.nextToken()
		stmt.Name = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
	}

	return stmt
}

func (p *Parser) parseRollbackStatement() ast.Statement {
	stmt := &ast.RollbackTransactionStatement{Token: p.curToken}

	if p.peekTokenIs(token.TRANSACTION) || p.peekTokenIs(token.TRAN) {
		p.nextToken()
	}

	if p.peekTokenIs(token.IDENT) {
		p.nextToken()
		stmt.Name = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
	}

	return stmt
}

func (p *Parser) parseWithStatement() ast.Statement {
	stmt := &ast.WithStatement{Token: p.curToken}
	p.nextToken()

	// Parse CTEs
	cte := p.parseCTEDef()
	stmt.CTEs = append(stmt.CTEs, cte)

	for p.peekTokenIs(token.COMMA) {
		p.nextToken()
		p.nextToken()
		cte = p.parseCTEDef()
		stmt.CTEs = append(stmt.CTEs, cte)
	}

	// Parse main query
	p.nextToken()
	stmt.Query = p.parseStatement()

	return stmt
}

// parseWithXmlnamespacesStatement parses WITH XMLNAMESPACES (...) SELECT ...
func (p *Parser) parseWithXmlnamespacesStatement() ast.Statement {
	stmt := &ast.WithXmlnamespacesStatement{Token: p.curToken}

	// Current token is WITH_XMLNAMESPACES, expect (
	if !p.expectPeek(token.LPAREN) {
		return nil
	}
	p.nextToken() // move past (

	// Parse namespace declarations
	for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
		ns := &ast.XmlNamespaceDef{}

		if p.curTokenIs(token.DEFAULT_KW) {
			ns.IsDefault = true
			p.nextToken() // move past DEFAULT
			if p.curTokenIs(token.STRING) || p.curTokenIs(token.NSTRING) {
				ns.URI = p.curToken.Literal
			}
			p.nextToken()
		} else if p.curTokenIs(token.STRING) || p.curTokenIs(token.NSTRING) {
			ns.URI = p.curToken.Literal
			p.nextToken() // move past URI string
			if p.curTokenIs(token.AS) {
				p.nextToken() // move past AS
				ns.Prefix = p.curToken.Literal
				p.nextToken()
			}
		} else {
			p.nextToken() // skip unknown token
		}

		stmt.Namespaces = append(stmt.Namespaces, ns)

		if p.curTokenIs(token.COMMA) {
			p.nextToken() // move past comma
		}
	}

	// Move past )
	if p.curTokenIs(token.RPAREN) {
		p.nextToken()
	}

	// Parse the main query (typically SELECT)
	stmt.Query = p.parseStatement()

	return stmt
}

func (p *Parser) parseCTEDef() *ast.CTEDef {
	cte := &ast.CTEDef{}
	cte.Name = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}

	// Parse column list
	if p.peekTokenIs(token.LPAREN) {
		p.nextToken()
		cte.Columns = p.parseIdentifierList()
	}

	if !p.expectPeek(token.AS) {
		return nil
	}
	if !p.expectPeek(token.LPAREN) {
		return nil
	}
	p.nextToken()

	cte.Query = p.parseSelectStatement()

	p.expectPeek(token.RPAREN)

	return cte
}

func (p *Parser) parseGoStatement() ast.Statement {
	stmt := &ast.GoStatement{Token: p.curToken}

	if p.peekTokenIs(token.INT) {
		p.nextToken()
		count, _ := strconv.Atoi(p.curToken.Literal)
		stmt.Count = &count
	}

	return stmt
}

// parseEnableDisableTriggerStatement parses ENABLE/DISABLE TRIGGER statements
// Syntax: ENABLE/DISABLE TRIGGER { trigger_name | ALL } ON { table | DATABASE | ALL SERVER }
func (p *Parser) parseEnableDisableTriggerStatement(enable bool) ast.Statement {
	stmt := &ast.EnableDisableTriggerStatement{Token: p.curToken, Enable: enable}

	// Expect TRIGGER
	if !p.expectPeek(token.TRIGGER) {
		return nil
	}
	p.nextToken() // move past TRIGGER

	// Parse trigger name or ALL
	if p.curTokenIs(token.ALL) {
		stmt.AllTriggers = true
	} else {
		stmt.TriggerName = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
	}

	// Expect ON
	if !p.expectPeek(token.ON) {
		return nil
	}
	p.nextToken() // move past ON

	// Parse target: table name, DATABASE, or ALL SERVER
	if p.curTokenIs(token.DATABASE) {
		stmt.OnDatabase = true
	} else if p.curTokenIs(token.ALL) {
		// ALL SERVER
		if p.peekTokenIs(token.IDENT) && strings.ToUpper(p.peekToken.Literal) == "SERVER" ||
			p.peekTokenIs(token.SERVER) {
			p.nextToken()
			stmt.OnAllServer = true
		}
	} else {
		// Table name
		stmt.TableName = p.parseQualifiedIdentifier()
	}

	return stmt
}

// -----------------------------------------------------------------------------
// Stage 7a: Quick Wins - Statement Parsers
// -----------------------------------------------------------------------------

func (p *Parser) parseUseStatement() ast.Statement {
	stmt := &ast.UseStatement{Token: p.curToken}
	p.nextToken()

	stmt.Database = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
	return stmt
}

func (p *Parser) parseWaitforStatement() ast.Statement {
	stmt := &ast.WaitforStatement{Token: p.curToken}
	p.nextToken()

	// DELAY or TIME
	stmt.Type = strings.ToUpper(p.curToken.Literal)
	p.nextToken()

	// Duration (string or variable)
	stmt.Duration = p.parseExpression(LOWEST)
	return stmt
}

func (p *Parser) parseSaveTransactionStatement() ast.Statement {
	stmt := &ast.SaveTransactionStatement{Token: p.curToken}
	p.nextToken() // move past SAVE

	// TRANSACTION or TRAN (optional)
	if p.curTokenIs(token.TRANSACTION) || p.curTokenIs(token.TRAN) {
		p.nextToken()
	}

	stmt.SavepointName = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
	return stmt
}

func (p *Parser) parseGotoStatement() ast.Statement {
	stmt := &ast.GotoStatement{Token: p.curToken}
	p.nextToken()

	stmt.Label = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
	return stmt
}

func (p *Parser) parseLabelStatement() ast.Statement {
	stmt := &ast.LabelStatement{Token: p.curToken}
	stmt.Name = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
	p.nextToken() // consume the colon
	return stmt
}

func (p *Parser) parseExpressionStatement() ast.Statement {
	stmt := &ast.ExpressionStatement{Token: p.curToken}
	stmt.Expression = p.parseExpression(LOWEST)
	return stmt
}

// -----------------------------------------------------------------------------
// Stage 2: Cursor Statement Parsers
// -----------------------------------------------------------------------------

func (p *Parser) parseOpenCursorStatement() ast.Statement {
	openToken := p.curToken
	p.nextToken()

	// Check for OPEN SYMMETRIC KEY
	if p.curTokenIs(token.SYMMETRIC) {
		return p.parseOpenSymmetricKeyStatement(openToken)
	}

	// Regular OPEN cursor
	stmt := &ast.OpenCursorStatement{Token: openToken}
	stmt.CursorName = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
	return stmt
}

func (p *Parser) parseCloseCursorStatement() ast.Statement {
	closeToken := p.curToken
	p.nextToken()

	// Check for CLOSE ALL SYMMETRIC KEYS
	if p.curTokenIs(token.ALL) {
		p.nextToken() // move past ALL
		if p.curTokenIs(token.SYMMETRIC) {
			p.nextToken() // move past SYMMETRIC
			if strings.ToUpper(p.curToken.Literal) == "KEYS" {
				p.nextToken() // move past KEYS
			}
		}
		return &ast.CloseSymmetricKeyStatement{Token: closeToken, All: true}
	}

	// Check for CLOSE SYMMETRIC KEY
	if p.curTokenIs(token.SYMMETRIC) {
		stmt := &ast.CloseSymmetricKeyStatement{Token: closeToken}
		p.nextToken() // move past SYMMETRIC

		if p.curTokenIs(token.KEY) {
			p.nextToken() // move past KEY
		}

		stmt.KeyName = p.curToken.Literal
		p.nextToken()

		return stmt
	}

	// Regular CLOSE cursor
	stmt := &ast.CloseCursorStatement{Token: closeToken}
	stmt.CursorName = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
	return stmt
}

func (p *Parser) parseFetchStatement() ast.Statement {
	stmt := &ast.FetchStatement{Token: p.curToken}
	p.nextToken()

	// Check for direction: NEXT, PRIOR, FIRST, LAST, ABSOLUTE n, RELATIVE n
	switch p.curToken.Type {
	case token.NEXT:
		stmt.Direction = "NEXT"
		p.nextToken()
	case token.PRIOR:
		stmt.Direction = "PRIOR"
		p.nextToken()
	case token.FIRST:
		stmt.Direction = "FIRST"
		p.nextToken()
	case token.LAST:
		stmt.Direction = "LAST"
		p.nextToken()
	case token.ABSOLUTE:
		stmt.Direction = "ABSOLUTE"
		p.nextToken()
		stmt.Offset = p.parseExpression(LOWEST)
		p.nextToken()
	case token.RELATIVE:
		stmt.Direction = "RELATIVE"
		p.nextToken()
		stmt.Offset = p.parseExpression(LOWEST)
		p.nextToken()
	}

	// Expect FROM
	if p.curTokenIs(token.FROM) {
		p.nextToken()
	}

	// Parse cursor name
	stmt.CursorName = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}

	// Check for INTO
	if p.peekTokenIs(token.INTO) {
		p.nextToken()
		p.nextToken()

		// Parse variable list
		variable := &ast.Variable{Token: p.curToken, Name: p.curToken.Literal}
		stmt.IntoVars = append(stmt.IntoVars, variable)

		for p.peekTokenIs(token.COMMA) {
			p.nextToken()
			p.nextToken()
			variable = &ast.Variable{Token: p.curToken, Name: p.curToken.Literal}
			stmt.IntoVars = append(stmt.IntoVars, variable)
		}
	}

	return stmt
}

func (p *Parser) parseDeallocateCursorStatement() ast.Statement {
	stmt := &ast.DeallocateCursorStatement{Token: p.curToken}
	p.nextToken()

	stmt.CursorName = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
	return stmt
}

// parseAlterIndexStatement parses ALTER INDEX name ON table action
func (p *Parser) parseAlterIndexStatement(alterToken token.Token) ast.Statement {
	stmt := &ast.AlterIndexStatement{Token: alterToken}
	p.nextToken() // move past INDEX

	// Parse index name (or ALL)
	stmt.Name = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}

	// Expect ON
	if !p.expectPeek(token.ON) {
		return nil
	}
	p.nextToken()

	// Parse table name
	stmt.Table = p.parseQualifiedIdentifier()

	// Parse action: REBUILD, REORGANIZE, DISABLE, SET, etc.
	p.nextToken()
	stmt.Action = strings.ToUpper(p.curToken.Literal)

	// For SET action, options come immediately after in parentheses: SET (opt = val, ...)
	if stmt.Action == "SET" {
		if p.peekTokenIs(token.LPAREN) {
			p.nextToken() // consume (
			p.nextToken() // move to first option
			for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
				stmt.Options = append(stmt.Options, p.curToken.Literal)
				if p.peekTokenIs(token.COMMA) || p.peekTokenIs(token.EQ) {
					p.nextToken()
				}
				p.nextToken()
			}
		}
		return stmt
	}

	// Parse optional WITH options for other actions
	if p.peekTokenIs(token.WITH) {
		p.nextToken()
		if p.expectPeek(token.LPAREN) {
			p.nextToken()
			for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
				stmt.Options = append(stmt.Options, p.curToken.Literal)
				if p.peekTokenIs(token.COMMA) {
					p.nextToken()
				}
				p.nextToken()
			}
		}
	}

	return stmt
}

// parseBulkInsertStatement parses BULK INSERT table FROM 'file' [WITH (...)]
func (p *Parser) parseBulkInsertStatement() ast.Statement {
	stmt := &ast.BulkInsertStatement{Token: p.curToken}
	stmt.Options = make(map[string]string)

	// Expect INSERT
	if !p.expectPeek(token.INSERT) {
		return nil
	}
	p.nextToken()

	// Parse table name
	stmt.Table = p.parseQualifiedIdentifier()

	// Expect FROM
	if !p.expectPeek(token.FROM) {
		return nil
	}
	p.nextToken()

	// Parse data file path (string literal)
	if p.curToken.Type == token.STRING {
		stmt.DataFile = p.curToken.Literal
	}

	// Parse optional WITH options
	if p.peekTokenIs(token.WITH) {
		p.nextToken()
		if p.expectPeek(token.LPAREN) {
			p.nextToken()
			for !p.curTokenIs(token.RPAREN) && !p.curTokenIs(token.EOF) {
				optName := p.curToken.Literal
				if p.peekTokenIs(token.EQ) {
					p.nextToken() // consume =
					p.nextToken() // move to value
					stmt.Options[optName] = p.curToken.Literal
				} else if p.peekTokenIs(token.LPAREN) {
					// Handle ORDER (col ASC), ROWS_PER_BATCH (n), etc.
					p.nextToken() // consume (
					var innerParts []string
					depth := 1
					for depth > 0 && !p.curTokenIs(token.EOF) {
						p.nextToken()
						if p.curTokenIs(token.LPAREN) {
							depth++
							innerParts = append(innerParts, "(")
						} else if p.curTokenIs(token.RPAREN) {
							depth--
							if depth > 0 {
								innerParts = append(innerParts, ")")
							}
						} else {
							innerParts = append(innerParts, p.curToken.Literal)
						}
					}
					stmt.Options[optName] = "(" + strings.Join(innerParts, " ") + ")"
				} else {
					stmt.Options[optName] = "true"
				}
				if p.peekTokenIs(token.COMMA) {
					p.nextToken()
				}
				p.nextToken()
			}
		}
	}

	return stmt
}
