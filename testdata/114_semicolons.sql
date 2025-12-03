-- Sample 114: Semicolon Variations and Statement Terminators
-- Category: Syntax Edge Cases
-- Complexity: Intermediate
-- Purpose: Parser testing - statement termination rules
-- Features: Optional semicolons, required semicolons, GO batches

-- Pattern 1: Statements without semicolons (traditionally allowed)
SELECT 1
SELECT 2
SELECT 3
GO

-- Pattern 2: Statements with semicolons
SELECT 1;
SELECT 2;
SELECT 3;
GO

-- Pattern 3: Mixed semicolon usage
SELECT 1;
SELECT 2
SELECT 3;
SELECT 4
GO

-- Pattern 4: Multiple semicolons (empty statements)
SELECT 1;;;
SELECT 2;;
;SELECT 3;
;;SELECT 4;;
GO

-- Pattern 5: Semicolon required before WITH (CTE)
SELECT 1;
;WITH CTE AS (SELECT 2 AS Value)
SELECT * FROM CTE;
GO

-- Pattern 6: Semicolon required before MERGE
SELECT 1;
;MERGE INTO Target AS t
USING Source AS s ON t.ID = s.ID
WHEN MATCHED THEN UPDATE SET t.Value = s.Value;
GO

-- Pattern 7: Semicolon with THROW
BEGIN TRY
    SELECT 1/0;
END TRY
BEGIN CATCH
    ;THROW;  -- Semicolon before THROW (required in some contexts)
END CATCH;
GO

-- Pattern 8: Semicolon in control flow
IF 1 = 1
    SELECT 'True';
ELSE
    SELECT 'False';
GO

IF 1 = 1
BEGIN
    SELECT 'True';
    SELECT 'Also True';
END;
ELSE
BEGIN
    SELECT 'False';
END;
GO

-- Pattern 9: Semicolon with WHILE
DECLARE @i INT = 0;
WHILE @i < 5
BEGIN
    SELECT @i;
    SET @i = @i + 1;
END;
GO

-- Pattern 10: Semicolon with transactions
BEGIN TRANSACTION;
    SELECT 1;
    SELECT 2;
COMMIT TRANSACTION;
GO

BEGIN TRAN
    SELECT 1
    SELECT 2
COMMIT
GO

-- Pattern 11: Semicolon placement edge cases
SELECT 
    1
;

SELECT 
    2
    ;

SELECT 3
    ;

SELECT 4;

GO

-- Pattern 12: GO with count
SELECT 'This runs once';
GO

SELECT 'This runs 3 times';
GO 3

SELECT 'Back to once';
GO

-- Pattern 13: Semicolons in stored procedure
CREATE PROCEDURE dbo.SemicolonTest
AS
BEGIN
    DECLARE @x INT;
    SET @x = 1;
    
    SELECT @x;
    
    IF @x = 1
    BEGIN
        SELECT 'One';
    END;
    
    ;WITH CTE AS (SELECT @x AS Value)
    SELECT * FROM CTE;
    
    RETURN;
END;
GO

-- Pattern 14: Semicolon with EXECUTE
EXEC sp_executesql N'SELECT 1';
EXECUTE sp_executesql N'SELECT 2';
EXEC('SELECT 3');
EXECUTE('SELECT 4');
GO

-- Pattern 15: Semicolon after DDL
CREATE TABLE #Temp1 (ID INT);
DROP TABLE #Temp1;

CREATE TABLE #Temp2 (ID INT)
DROP TABLE #Temp2
GO

-- Pattern 16: Semicolon with SET statements
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
GO

SET NOCOUNT ON
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO

-- Pattern 17: Semicolons in expressions (not terminators)
SELECT CASE WHEN 1=1 THEN 'a' ELSE 'b' END;  -- END is keyword, not terminator
SELECT * FROM (SELECT 1 AS A) AS Sub;         -- Parenthesis, not terminator
GO

-- Pattern 18: Batch separator edge cases
GO -- Comment after GO
GO-- No space
GO  -- Spaces
	GO  -- Tab before GO
GO

GO

GO
-- Comment then GO
GO

-- Pattern 19: Statement after GO on same line (error in most tools)
-- GO SELECT 1  -- This would typically error

-- Pattern 20: Empty batches
GO
GO
GO

-- Pattern 21: Semicolon in string literals (not terminators)
SELECT 'text; more text';
SELECT 'SELECT 1; SELECT 2';
SELECT ';';
SELECT ';;;';
GO

-- Pattern 22: Semicolons with labels (if GOTO were used)
-- LabelName:
-- SELECT 1;
-- GOTO LabelName;

-- Pattern 23: All statements with explicit semicolons (modern style)
DECLARE @a INT = 1;
DECLARE @b INT = 2;
DECLARE @c INT;

SET @c = @a + @b;

IF @c > 0
BEGIN
    PRINT 'Positive';
END;

SELECT @a AS A, @b AS B, @c AS C;
GO
