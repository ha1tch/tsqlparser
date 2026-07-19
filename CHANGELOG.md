# Changelog

All notable changes to tsqlparser are documented here.

---

## [0.6.1] — 2026-07-17

### Fixed

- **`parseScopeExpression` nil-pointer panic** (`parser/parser.go`): when the
  scope operator `::` was reached with no valid left operand — for example
  after a preceding prefix expression failed to parse in inputs like
  `(  ! ::` — the outer `parseExpression` passed a nil `left` into
  `parseScopeExpression`, which then panicked on `left.String()`. The parser
  now guards for `left == nil`, appends a consistent error to the parser's
  error slice, and returns nil so recovery can continue. Discovered via xolu's
  `FuzzEvalGuard` corpus.

- **`SelectColumn.String` nil-pointer panic** (`ast/ast.go`): when
  `parseSelectColumn` recovered from a syntax error and left `Expression` nil,
  any subsequent stringification of the program (fmt `%v`, diagnostics, error
  messages) would panic. `SelectColumn.String` now reports `<invalid>` (or
  `varname = <invalid>` when the column is a variable assignment) instead of
  panicking. Defensive complement to the parser fix above.

---

## [0.6.0] — 2026-06-13

### Added

- **`FunctionCall.Distinct` field** (`ast/ast.go`): aggregate functions with a
  `DISTINCT` modifier — `COUNT(DISTINCT x)`, `SUM(DISTINCT x)`, `AVG(DISTINCT x)`,
  `MIN(DISTINCT x)`, `MAX(DISTINCT x)` — now set `Distinct: true` on the resulting
  `FunctionCall` AST node. Previously the modifier was silently discarded, making
  `COUNT(DISTINCT x)` indistinguishable from `COUNT(x)`. `FunctionCall.String()`
  round-trips correctly: `COUNT(DISTINCT status)`.

### Fixed

- **`EXEC(sql, @param) AT [server]`** (119_four_part_names): parameterised
  dynamic `EXEC AT` now parses correctly; extra comma-separated arguments before
  the closing `)` are consumed.

- **Four-part names with empty database component** (119_four_part_names):
  `[Server]..schema.table` (double-dot syntax) is now handled by
  `parseQualifiedIdentifier`, which inserts an empty-string part rather than
  crashing on the second dot.

- **`WITH RESULT SETS` column `COLLATE`** (118_result_sets): a `COLLATE
  collation_name` clause after a column data type inside `EXEC ... WITH RESULT
  SETS ((...))` is now consumed without error.

- **`CREATE SCHEMA` with inline object definitions** (193_schema_operations):
  the deprecated `CREATE SCHEMA name CREATE TABLE ... CREATE VIEW ...` syntax
  (where objects are defined inline in the schema statement) is now parsed by
  skipping the inline body rather than failing.

- **`WAITFOR (RECEIVE ...)` Service Broker form** (142_waitfor):
  `WAITFOR (RECEIVE TOP (1) ... FROM queue), TIMEOUT n` is now handled by
  consuming the parenthesised body and the optional `, TIMEOUT n` suffix.

- **`CONTAINS` column argument forms** (120_fulltext_search):
  - `CONTAINS(PROPERTY(col, 'prop'), term)` — function-call column specifier
  - `CONTAINS(t.col, term)` — qualified (dotted) column name
  - `CONTAINS(col, term, LANGUAGE 1033)` — integer `LANGUAGE` option
  - `FREETEXTTABLE`/`CONTAINSTABLE` with a column list `(col1, col2)` and an
    optional `top_n_by_rank` fourth argument now parse correctly through the
    table-valued function path.

- **Bracket-escaped identifiers** (110_unicode_identifiers, 198_identifiers):
  `readBracketedIdentifier` in the lexer had dead escape logic — the `]]`
  handler was inside a loop gated on `ch != ']'` and could never fire. The loop
  has been restructured so `]]` is correctly consumed as an escaped `]` and the
  identifier continues.

### Changed

- `FunctionCall.String()` now emits `FUNC(DISTINCT arg)` when `Distinct` is
  true. Callers that serialise AST nodes to SQL strings will see correct output
  for the first time; callers that were comparing `String()` output for
  `COUNT(DISTINCT x)` against `COUNT(x)` should update their expectations.

- Known-failure list reduced from eight entries to two. The two remaining
  entries (`110_unicode_identifiers.sql`, `198_identifiers.sql`) reflect
  syntactically invalid T-SQL in those corpus files (unescaped `]` inside a
  bracketed identifier: `[Col[umn]Name]`), which no spec-compliant parser can
  recover from without guessing.

---

## [0.5.2] — 2025

Initial public release. 96.5% corpus pass rate (194/201).
