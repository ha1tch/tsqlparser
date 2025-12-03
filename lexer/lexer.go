// Package lexer implements a lexical scanner for T-SQL.
package lexer

import (
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/ha1tch/tsqlparser/token"
)

// Lexer represents a lexical scanner for T-SQL.
type Lexer struct {
	input        string
	position     int  // current position in input (points to current char)
	readPosition int  // current reading position in input (after current char)
	ch           rune // current char under examination
	line         int
	column       int
}

// New creates a new Lexer for the given input.
func New(input string) *Lexer {
	l := &Lexer{
		input:  input,
		line:   1,
		column: 0,
	}
	l.readChar()
	return l
}

// readChar reads the next character and advances the position.
func (l *Lexer) readChar() {
	if l.readPosition >= len(l.input) {
		l.ch = 0
		l.position = l.readPosition
	} else {
		r, size := utf8.DecodeRuneInString(l.input[l.readPosition:])
		l.ch = r
		l.position = l.readPosition
		l.readPosition += size
	}
	l.column++
	if l.ch == '\n' {
		l.line++
		l.column = 0
	}
}

// peekChar returns the next character without advancing the position.
func (l *Lexer) peekChar() rune {
	if l.readPosition >= len(l.input) {
		return 0
	}
	r, _ := utf8.DecodeRuneInString(l.input[l.readPosition:])
	return r
}

// NextToken returns the next token from the input.
func (l *Lexer) NextToken() token.Token {
	var tok token.Token

	l.skipWhitespace()

	tok.Line = l.line
	tok.Column = l.column

	switch l.ch {
	case '+':
		if l.peekChar() == '=' {
			l.readChar()
			tok = l.newToken(token.PLUSEQ, "+=")
		} else {
			tok = l.newToken(token.PLUS, string(l.ch))
		}
	case '-':
		if l.peekChar() == '-' {
			tok.Type = token.COMMENT
			tok.Literal = l.readLineComment()
			return tok
		} else if l.peekChar() == '=' {
			l.readChar()
			tok = l.newToken(token.MINUSEQ, "-=")
		} else {
			tok = l.newToken(token.MINUS, string(l.ch))
		}
	case '*':
		if l.peekChar() == '=' {
			l.readChar()
			tok = l.newToken(token.MULEQ, "*=")
		} else {
			tok = l.newToken(token.ASTERISK, string(l.ch))
		}
	case '/':
		if l.peekChar() == '*' {
			tok.Type = token.COMMENT
			tok.Literal = l.readBlockComment()
			return tok
		} else if l.peekChar() == '=' {
			l.readChar()
			tok = l.newToken(token.DIVEQ, "/=")
		} else {
			tok = l.newToken(token.SLASH, string(l.ch))
		}
	case '%':
		if l.peekChar() == '=' {
			l.readChar()
			tok = l.newToken(token.MODEQ, "%=")
		} else {
			tok = l.newToken(token.PERCENT, string(l.ch))
		}
	case '&':
		if l.peekChar() == '=' {
			l.readChar()
			tok = l.newToken(token.ANDEQ, "&=")
		} else {
			tok = l.newToken(token.AMPERSAND, string(l.ch))
		}
	case '|':
		if l.peekChar() == '=' {
			l.readChar()
			tok = l.newToken(token.OREQ, "|=")
		} else {
			tok = l.newToken(token.PIPE, string(l.ch))
		}
	case '^':
		if l.peekChar() == '=' {
			l.readChar()
			tok = l.newToken(token.XOREQ, "^=")
		} else {
			tok = l.newToken(token.CARET, string(l.ch))
		}
	case '~':
		tok = l.newToken(token.TILDE, string(l.ch))
	case '=':
		tok = l.newToken(token.EQ, string(l.ch))
	case '!':
		if l.peekChar() == '=' {
			l.readChar()
			tok = l.newToken(token.NEQ, "!=")
		} else if l.peekChar() == '<' {
			l.readChar()
			tok = l.newToken(token.NOT_LT, "!<")
		} else if l.peekChar() == '>' {
			l.readChar()
			tok = l.newToken(token.NOT_GT, "!>")
		} else {
			tok = l.newToken(token.ILLEGAL, string(l.ch))
		}
	case '<':
		if l.peekChar() == '>' {
			l.readChar()
			tok = l.newToken(token.NEQ, "<>")
		} else if l.peekChar() == '=' {
			l.readChar()
			tok = l.newToken(token.LTE, "<=")
		} else if l.peekChar() == '<' {
			l.readChar()
			tok = l.newToken(token.LSHIFT, "<<")
		} else {
			tok = l.newToken(token.LT, string(l.ch))
		}
	case '>':
		if l.peekChar() == '=' {
			l.readChar()
			tok = l.newToken(token.GTE, ">=")
		} else if l.peekChar() == '>' {
			l.readChar()
			tok = l.newToken(token.RSHIFT, ">>")
		} else {
			tok = l.newToken(token.GT, string(l.ch))
		}
	case ',':
		tok = l.newToken(token.COMMA, string(l.ch))
	case ';':
		tok = l.newToken(token.SEMICOLON, string(l.ch))
	case '(':
		tok = l.newToken(token.LPAREN, string(l.ch))
	case ')':
		tok = l.newToken(token.RPAREN, string(l.ch))
	case '[':
		// Bracketed identifier
		tok.Type = token.IDENT
		tok.Literal = l.readBracketedIdentifier()
		return tok
	case ']':
		tok = l.newToken(token.RBRACKET, string(l.ch))
	case '.':
		// Check if this is a floating-point number starting with dot (e.g., .5)
		if isDigit(l.peekChar()) {
			tok.Type = token.FLOAT
			tok.Literal = l.readFloatFromDot()
			return tok
		}
		tok = l.newToken(token.DOT, string(l.ch))
	case ':':
		if l.peekChar() == ':' {
			l.readChar()
			tok = l.newToken(token.SCOPE, "::")
		} else {
			tok = l.newToken(token.COLON, string(l.ch))
		}
	case '?':
		tok = l.newToken(token.PLACEHOLDER, string(l.ch))
	case '\'':
		tok.Type = token.STRING
		tok.Literal = l.readString()
		return tok
	case '"':
		// Double-quoted identifier (ANSI SQL, T-SQL with QUOTED_IDENTIFIER ON)
		tok.Type = token.IDENT
		tok.Literal = l.readQuotedIdentifier()
		return tok
	case '@':
		if l.peekChar() == '@' {
			l.readChar()
			l.readChar()
			tok.Type = token.TEMPVAR
			tok.Literal = "@@" + l.readIdentifier()
		} else {
			l.readChar()
			tok.Type = token.VARIABLE
			tok.Literal = "@" + l.readIdentifier()
		}
		return tok
	case '$':
		// Check if this is a money literal ($123.45) or system variable ($IDENTITY)
		if isDigit(l.peekChar()) {
			tok.Type = token.MONEY_LIT
			tok.Literal = l.readMoneyLiteral()
			return tok
		}
		l.readChar()
		tok.Type = token.SYSVAR
		tok.Literal = "$" + l.readIdentifier()
		return tok
	case 'N', 'n':
		if l.peekChar() == '\'' {
			l.readChar()
			tok.Type = token.NSTRING
			tok.Literal = l.readString()
			return tok
		}
		tok.Literal = l.readIdentifier()
		tok.Type = token.LookupIdent(strings.ToUpper(tok.Literal))
		// Check for compound keywords like END CONVERSATION, NEXT VALUE FOR, XML SCHEMA COLLECTION
		if tok.Type == token.END || tok.Type == token.NEXT || tok.Type == token.XML || 
		   tok.Type == token.ASYMMETRIC || tok.Type == token.SYMMETRIC ||
		   tok.Type == token.TRUNCATE || tok.Type == token.WITH ||
		   tok.Type == token.CREATE || tok.Type == token.BEGIN || tok.Type == token.IS {
			tok = l.checkCompoundKeyword(tok)
		}
		return tok
	case '0':
		if l.peekChar() == 'x' || l.peekChar() == 'X' {
			tok.Type = token.BINARY
			tok.Literal = l.readHexLiteral()
			return tok
		}
		tok.Literal, tok.Type = l.readNumber()
		return tok
	case 0:
		tok.Literal = ""
		tok.Type = token.EOF
	case '#':
		// Temp table identifier
		tok.Literal = l.readIdentifier()
		tok.Type = token.IDENT
		return tok
	default:
		if isDigit(l.ch) {
			tok.Literal, tok.Type = l.readNumber()
			return tok
		} else if isLetter(l.ch) {
			tok.Literal = l.readIdentifier()
			tok.Type = token.LookupIdent(strings.ToUpper(tok.Literal))
			// Check for compound keywords like END CONVERSATION, NEXT VALUE FOR, XML SCHEMA COLLECTION
			if tok.Type == token.END || tok.Type == token.NEXT || tok.Type == token.XML ||
			   tok.Type == token.ASYMMETRIC || tok.Type == token.SYMMETRIC ||
			   tok.Type == token.TRUNCATE || tok.Type == token.WITH ||
			   tok.Type == token.CREATE || tok.Type == token.BEGIN || tok.Type == token.IS {
				tok = l.checkCompoundKeyword(tok)
			}
			return tok
		} else {
			tok = l.newToken(token.ILLEGAL, string(l.ch))
		}
	}

	l.readChar()
	return tok
}

func (l *Lexer) newToken(tokenType token.Type, literal string) token.Token {
	return token.Token{
		Type:    tokenType,
		Literal: literal,
		Line:    l.line,
		Column:  l.column,
	}
}

func (l *Lexer) skipWhitespace() {
	for l.ch == ' ' || l.ch == '\t' || l.ch == '\n' || l.ch == '\r' {
		l.readChar()
	}
}

func (l *Lexer) readIdentifier() string {
	position := l.position
	for isLetter(l.ch) || isDigit(l.ch) || l.ch == '_' || l.ch == '#' || l.ch == '$' {
		l.readChar()
	}
	return l.input[position:l.position]
}

func (l *Lexer) readBracketedIdentifier() string {
	l.readChar() // consume opening [
	position := l.position
	for l.ch != ']' && l.ch != 0 {
		// Handle escaped brackets ]]
		if l.ch == ']' && l.peekChar() == ']' {
			l.readChar()
		}
		l.readChar()
	}
	ident := l.input[position:l.position]
	if l.ch == ']' {
		l.readChar() // consume closing ]
	}
	return ident
}

func (l *Lexer) readQuotedIdentifier() string {
	l.readChar() // consume opening "
	position := l.position
	for l.ch != '"' && l.ch != 0 {
		// Handle escaped quotes ""
		if l.ch == '"' && l.peekChar() == '"' {
			l.readChar()
		}
		l.readChar()
	}
	ident := l.input[position:l.position]
	if l.ch == '"' {
		l.readChar() // consume closing "
	}
	return ident
}

func (l *Lexer) readNumber() (string, token.Type) {
	position := l.position
	tokenType := token.INT

	for isDigit(l.ch) {
		l.readChar()
	}

	// Check for decimal point
	if l.ch == '.' && isDigit(l.peekChar()) {
		tokenType = token.FLOAT
		l.readChar() // consume the dot
		for isDigit(l.ch) {
			l.readChar()
		}
	}

	// Check for exponent
	if l.ch == 'e' || l.ch == 'E' {
		tokenType = token.FLOAT
		l.readChar()
		if l.ch == '+' || l.ch == '-' {
			l.readChar()
		}
		for isDigit(l.ch) {
			l.readChar()
		}
	}

	return l.input[position:l.position], tokenType
}

// readFloatFromDot reads a float literal that starts with a dot (e.g., .5, .123)
func (l *Lexer) readFloatFromDot() string {
	position := l.position
	l.readChar() // consume the dot
	for isDigit(l.ch) {
		l.readChar()
	}
	// Check for exponent
	if l.ch == 'e' || l.ch == 'E' {
		l.readChar()
		if l.ch == '+' || l.ch == '-' {
			l.readChar()
		}
		for isDigit(l.ch) {
			l.readChar()
		}
	}
	return l.input[position:l.position]
}

// readMoneyLiteral reads a money literal starting with $ (e.g., $123.45, $1,234.56)
func (l *Lexer) readMoneyLiteral() string {
	position := l.position
	l.readChar() // consume $
	// Read digits and commas (for thousand separators)
	for isDigit(l.ch) || l.ch == ',' {
		l.readChar()
	}
	// Check for decimal point
	if l.ch == '.' {
		l.readChar()
		for isDigit(l.ch) {
			l.readChar()
		}
	}
	return l.input[position:l.position]
}

func (l *Lexer) readHexLiteral() string {
	position := l.position
	l.readChar() // consume 0
	l.readChar() // consume x
	for isHexDigit(l.ch) {
		l.readChar()
	}
	return l.input[position:l.position]
}

func (l *Lexer) readString() string {
	var result strings.Builder
	l.readChar() // consume opening quote

	for {
		if l.ch == '\'' {
			if l.peekChar() == '\'' {
				// Escaped quote
				result.WriteRune(l.ch)
				l.readChar()
				l.readChar()
			} else {
				// End of string
				l.readChar()
				break
			}
		} else if l.ch == 0 {
			break
		} else {
			result.WriteRune(l.ch)
			l.readChar()
		}
	}

	return result.String()
}

func (l *Lexer) readLineComment() string {
	position := l.position
	for l.ch != '\n' && l.ch != 0 {
		l.readChar()
	}
	return l.input[position:l.position]
}

func (l *Lexer) readBlockComment() string {
	position := l.position
	l.readChar() // consume /
	l.readChar() // consume *
	
	// T-SQL supports nested block comments
	depth := 1
	for depth > 0 {
		if l.ch == '/' && l.peekChar() == '*' {
			l.readChar()
			l.readChar()
			depth++
		} else if l.ch == '*' && l.peekChar() == '/' {
			l.readChar()
			l.readChar()
			depth--
		} else if l.ch == 0 {
			break
		} else {
			l.readChar()
		}
	}

	return l.input[position:l.position]
}

// checkCompoundKeyword checks if the current token starts a compound keyword
// like "END CONVERSATION", "NEXT VALUE FOR", "XML SCHEMA COLLECTION"
func (l *Lexer) checkCompoundKeyword(tok token.Token) token.Token {
	// Save current position to restore if not a compound keyword
	savedPosition := l.position
	savedReadPosition := l.readPosition
	savedCh := l.ch
	savedLine := l.line
	savedColumn := l.column

	// Skip whitespace
	l.skipWhitespace()

	// Check if next identifier matches expected second word
	if isLetter(l.ch) {
		nextWord := l.readIdentifier()
		upperNext := strings.ToUpper(nextWord)

		// Two-word compound: END CONVERSATION
		if tok.Type == token.END && upperNext == "CONVERSATION" {
			tok.Type = token.END_CONVERSATION
			tok.Literal = "END CONVERSATION"
			return tok
		}

		// Three-word compound: NEXT VALUE FOR
		if tok.Type == token.NEXT && upperNext == "VALUE" {
			// Save position after VALUE
			savedPos2 := l.position
			savedReadPos2 := l.readPosition
			savedCh2 := l.ch
			savedLine2 := l.line
			savedColumn2 := l.column

			l.skipWhitespace()
			if isLetter(l.ch) {
				thirdWord := l.readIdentifier()
				if strings.ToUpper(thirdWord) == "FOR" {
					tok.Type = token.NEXT_VALUE_FOR
					tok.Literal = "NEXT VALUE FOR"
					return tok
				}
			}
			// Restore to after VALUE if third word didn't match
			l.position = savedPos2
			l.readPosition = savedReadPos2
			l.ch = savedCh2
			l.line = savedLine2
			l.column = savedColumn2
		}

		// Three-word compound: XML SCHEMA COLLECTION
		if tok.Type == token.XML && upperNext == "SCHEMA" {
			// Save position after SCHEMA
			savedPos2 := l.position
			savedReadPos2 := l.readPosition
			savedCh2 := l.ch
			savedLine2 := l.line
			savedColumn2 := l.column

			l.skipWhitespace()
			if isLetter(l.ch) {
				thirdWord := l.readIdentifier()
				if strings.ToUpper(thirdWord) == "COLLECTION" {
					tok.Type = token.XML_SCHEMA_COLLECTION
					tok.Literal = "XML SCHEMA COLLECTION"
					return tok
				}
			}
			// Restore to after SCHEMA if third word didn't match
			l.position = savedPos2
			l.readPosition = savedReadPos2
			l.ch = savedCh2
			l.line = savedLine2
			l.column = savedColumn2
		}

		// Two-word compound: ASYMMETRIC KEY (only when followed by :: for GRANT context)
		if tok.Type == token.ASYMMETRIC && upperNext == "KEY" {
			// Save position after KEY
			savedPos2 := l.position
			savedReadPos2 := l.readPosition
			savedCh2 := l.ch
			savedLine2 := l.line
			savedColumn2 := l.column

			l.skipWhitespace()
			// Only combine if followed by :: (GRANT context)
			if l.ch == ':' && l.peekChar() == ':' {
				tok.Type = token.ASYMMETRIC_KEY
				tok.Literal = "ASYMMETRIC KEY"
				return tok
			}
			// Restore position if not followed by ::
			l.position = savedPos2
			l.readPosition = savedReadPos2
			l.ch = savedCh2
			l.line = savedLine2
			l.column = savedColumn2
		}

		// Two-word compound: SYMMETRIC KEY (only when followed by :: for GRANT context)
		if tok.Type == token.SYMMETRIC && upperNext == "KEY" {
			// Save position after KEY
			savedPos2 := l.position
			savedReadPos2 := l.readPosition
			savedCh2 := l.ch
			savedLine2 := l.line
			savedColumn2 := l.column

			l.skipWhitespace()
			// Only combine if followed by :: (GRANT context)
			if l.ch == ':' && l.peekChar() == ':' {
				tok.Type = token.SYMMETRIC_KEY
				tok.Literal = "SYMMETRIC KEY"
				return tok
			}
			// Restore position if not followed by ::
			l.position = savedPos2
			l.readPosition = savedReadPos2
			l.ch = savedCh2
			l.line = savedLine2
			l.column = savedColumn2
		}

		// Two-word compound: TRUNCATE TABLE
		if tok.Type == token.TRUNCATE && upperNext == "TABLE" {
			tok.Type = token.TRUNCATE_TABLE
			tok.Literal = "TRUNCATE TABLE"
			return tok
		}

		// Two-word compound: CREATE RULE
		if tok.Type == token.CREATE && upperNext == "RULE" {
			tok.Type = token.CREATE_RULE
			tok.Literal = "CREATE RULE"
			return tok
		}

		// Two-word compound: BEGIN ATOMIC
		if tok.Type == token.BEGIN && upperNext == "ATOMIC" {
			tok.Type = token.BEGIN_ATOMIC
			tok.Literal = "BEGIN ATOMIC"
			return tok
		}

		// Two-word compound: WITH XMLNAMESPACES
		if tok.Type == token.WITH && upperNext == "XMLNAMESPACES" {
			tok.Type = token.WITH_XMLNAMESPACES
			tok.Literal = "WITH XMLNAMESPACES"
			return tok
		}

		// Two-word compound: WITH CHECK (but not WITH CHECK OPTION)
		if tok.Type == token.WITH && upperNext == "CHECK" {
			// Peek ahead to see if OPTION follows - if so, don't form compound
			savedPos2 := l.position
			savedReadPos2 := l.readPosition
			savedCh2 := l.ch
			savedLine2 := l.line
			savedColumn2 := l.column

			l.skipWhitespace()
			if isLetter(l.ch) {
				thirdWord := l.readIdentifier()
				if strings.ToUpper(thirdWord) == "OPTION" {
					// This is WITH CHECK OPTION - restore and don't compound
					l.position = savedPos2
					l.readPosition = savedReadPos2
					l.ch = savedCh2
					l.line = savedLine2
					l.column = savedColumn2
					// Don't return compound - fall through
				} else {
					// Not OPTION - restore and return compound
					l.position = savedPos2
					l.readPosition = savedReadPos2
					l.ch = savedCh2
					l.line = savedLine2
					l.column = savedColumn2
					tok.Type = token.WITH_CHECK
					tok.Literal = "WITH CHECK"
					return tok
				}
			} else {
				// No third word - restore and return compound
				l.position = savedPos2
				l.readPosition = savedReadPos2
				l.ch = savedCh2
				l.line = savedLine2
				l.column = savedColumn2
				tok.Type = token.WITH_CHECK
				tok.Literal = "WITH CHECK"
				return tok
			}
		}

		// Two-word compound: WITH NOCHECK
		if tok.Type == token.WITH && upperNext == "NOCHECK" {
			tok.Type = token.WITH_NOCHECK
			tok.Literal = "WITH NOCHECK"
			return tok
		}

		// IS [NOT] DISTINCT FROM - check for DISTINCT or NOT
		if tok.Type == token.IS && upperNext == "DISTINCT" {
			// IS DISTINCT - check for FROM
			savedPos2 := l.position
			savedReadPos2 := l.readPosition
			savedCh2 := l.ch
			savedLine2 := l.line
			savedColumn2 := l.column

			l.skipWhitespace()
			if isLetter(l.ch) {
				thirdWord := l.readIdentifier()
				if strings.ToUpper(thirdWord) == "FROM" {
					tok.Type = token.IS_DISTINCT_FROM
					tok.Literal = "IS DISTINCT FROM"
					return tok
				}
			}
			l.position = savedPos2
			l.readPosition = savedReadPos2
			l.ch = savedCh2
			l.line = savedLine2
			l.column = savedColumn2
		}

		if tok.Type == token.IS && upperNext == "NOT" {
			// IS NOT - check for DISTINCT FROM
			savedPos2 := l.position
			savedReadPos2 := l.readPosition
			savedCh2 := l.ch
			savedLine2 := l.line
			savedColumn2 := l.column

			l.skipWhitespace()
			if isLetter(l.ch) {
				thirdWord := l.readIdentifier()
				if strings.ToUpper(thirdWord) == "DISTINCT" {
					// Check for FROM
					savedPos3 := l.position
					savedReadPos3 := l.readPosition
					savedCh3 := l.ch
					savedLine3 := l.line
					savedColumn3 := l.column

					l.skipWhitespace()
					if isLetter(l.ch) {
						fourthWord := l.readIdentifier()
						if strings.ToUpper(fourthWord) == "FROM" {
							tok.Type = token.IS_NOT_DISTINCT_FROM
							tok.Literal = "IS NOT DISTINCT FROM"
							return tok
						}
					}
					l.position = savedPos3
					l.readPosition = savedReadPos3
					l.ch = savedCh3
					l.line = savedLine3
					l.column = savedColumn3
				}
			}
			l.position = savedPos2
			l.readPosition = savedReadPos2
			l.ch = savedCh2
			l.line = savedLine2
			l.column = savedColumn2
		}
	}

	// Check for WITH ( PARTITIONS pattern - need special handling since ( is not an identifier
	if tok.Type == token.WITH {
		// Save position after WITH
		savedPos2 := l.position
		savedReadPos2 := l.readPosition
		savedCh2 := l.ch
		savedLine2 := l.line
		savedColumn2 := l.column

		l.skipWhitespace()
		
		if l.ch == '(' {
			l.readChar() // consume (
			l.skipWhitespace()
			if isLetter(l.ch) {
				nextWord := l.readIdentifier()
				if strings.ToUpper(nextWord) == "PARTITIONS" {
					tok.Type = token.WITH_PARTITIONS
					tok.Literal = "WITH (PARTITIONS"
					return tok
				}
			}
		}
		// Restore position
		l.position = savedPos2
		l.readPosition = savedReadPos2
		l.ch = savedCh2
		l.line = savedLine2
		l.column = savedColumn2
	}

	// Not a compound keyword, restore position
	l.position = savedPosition
	l.readPosition = savedReadPosition
	l.ch = savedCh
	l.line = savedLine
	l.column = savedColumn

	return tok
}

func isLetter(ch rune) bool {
	return unicode.IsLetter(ch) || ch == '_'
}

func isDigit(ch rune) bool {
	return ch >= '0' && ch <= '9'
}

func isHexDigit(ch rune) bool {
	return isDigit(ch) || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F')
}

// Tokenize returns all tokens from the input as a slice.
func Tokenize(input string) []token.Token {
	l := New(input)
	var tokens []token.Token

	for {
		tok := l.NextToken()
		tokens = append(tokens, tok)
		if tok.Type == token.EOF {
			break
		}
	}

	return tokens
}
