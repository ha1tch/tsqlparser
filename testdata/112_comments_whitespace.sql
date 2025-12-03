-- Sample 112: Comment Variations and Whitespace Edge Cases
-- Category: Syntax Edge Cases
-- Complexity: Intermediate
-- Purpose: Parser testing - comment handling and whitespace sensitivity
-- Features: Single-line comments, block comments, nested comments, whitespace

-- Pattern 1: Single-line comment variations
SELECT 1; -- Comment at end of line
SELECT 2;-- No space before comment
SELECT 3;--No space at all
--SELECT 4; Entire line commented
SELECT 5; -- Comment with -- dashes -- inside
SELECT 6; -- Comment with 'quotes' and "double quotes"

-- Pattern 2: Block comment variations
SELECT /* inline comment */ 7;
SELECT /*comment without spaces*/ 8;
SELECT /* multi
line
comment */ 9;
SELECT /* comment with -- single line marker */ 10;
SELECT /* comment with 'quotes' */ 11;
SELECT /*
** Formatted
** Block
** Comment
*/ 12;

/* Entire statement in block comment
SELECT 999;
*/

-- Pattern 3: Nested block comments (SQL Server supports this)
SELECT /* outer /* inner */ still outer */ 13;
SELECT /* level1 /* level2 /* level3 */ level2 */ level1 */ 14;

-- Pattern 4: Comments within statements
SELECT 
    Column1, -- first column
    Column2, /* second column */
    Column3  -- third column
FROM /* table name */ TableName
WHERE /* condition */ Column1 = 1
  AND -- another condition
      Column2 = 2;

-- Pattern 5: Comments breaking keywords (parser stress test)
SELECT
    COL/* comment */UMN1,  -- This is invalid but tests parser
    COLUMN1
FROM MyTable;
GO

-- Pattern 6: Whitespace variations
SELECT     1;  -- Multiple spaces
SELECT	1;     -- Tab character
SELECT
1;             -- Newline in statement
SELECT
    
    
    1;         -- Multiple newlines
SELECT 1      ;  -- Space before semicolon
SELECT 1 
;              -- Newline before semicolon

-- Pattern 7: No whitespace (minimal)
SELECT 1+1;
SELECT 1+2*3;
SELECT(1);
SELECT(1+2);

-- Pattern 8: Mixed indentation styles
SELECT
	Column1,		-- Tabs
    Column2,        -- Spaces
	    Column3     -- Mixed
FROM Table1;

-- Pattern 9: Trailing whitespace
SELECT 1;   
SELECT 2;	
SELECT 3;

-- Pattern 10: Empty statements and semicolons
;
;;
; ;
SELECT 1;;
SELECT 2; ;
GO

-- Pattern 11: Comments in string literals (not comments)
SELECT '-- this is not a comment';
SELECT '/* also not a comment */';
SELECT 'text -- more text';
SELECT 'text /* more */ text';

-- Pattern 12: Unicode whitespace (if supported)
SELECT 1; -- Regular space after semicolon

-- Pattern 13: Block comment edge cases
SELECT /**/ 15;              -- Empty block comment
SELECT /*/ 16; */            -- Slash in comment
SELECT /* * / */ 17;         -- Space between * and /
SELECT /***/ 18;             -- Multiple asterisks
-- SELECT /* /* */ 19;       -- Unclosed nested (commented out - our parser supports nested comments)
SELECT /* outer /* inner */ outer */ 19;  -- Properly nested comments
GO

-- Pattern 14: Comments around operators
SELECT 1 +/* plus */2;
SELECT 1/* space */-/* minus */2;
SELECT 1--comment
+2;

-- Pattern 15: Comments in complex statements
CREATE PROCEDURE /* procedure name */ dbo.TestProc
    @Param1 /* first parameter */ INT,
    @Param2 /* second parameter */ VARCHAR(100) = /* default */ 'default'
AS
BEGIN
    -- Procedure body
    SELECT /* selecting */ @Param1 /* param1 */ + /* plus */ 1 /* one */;
END;
GO

-- Pattern 16: Commented out blocks with GO
/*
CREATE TABLE Test1 (ID INT);
GO
CREATE TABLE Test2 (ID INT);
GO
*/

-- Pattern 17: Line continuation (no explicit continuation in T-SQL, but long lines)
SELECT 'This is a very long string that spans what would typically be considered multiple lines in most editors but is actually a single string literal in T-SQL';

-- Pattern 18: Whitespace in identifiers (bracketed)
SELECT [Column With   Multiple   Spaces];
SELECT [Column	With	Tabs];
SELECT [Column
With
Newlines];

-- Pattern 19: Comment-like patterns in LIKE
SELECT * FROM Data WHERE Text LIKE '%--%';
SELECT * FROM Data WHERE Text LIKE '%/*%';
SELECT * FROM Data WHERE Text LIKE '%*/%';

-- Pattern 20: Batch separator variations
GO
go
Go
gO
-- GO 5  -- Execute 5 times (SSMS-specific, not standard T-SQL)
GO
