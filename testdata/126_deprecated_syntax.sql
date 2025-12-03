-- Sample 126: Deprecated Syntax That Still Parses
-- Category: Syntax Edge Cases / Missing Syntax
-- Complexity: Intermediate
-- Purpose: Parser testing - deprecated but valid syntax
-- Features: COMPUTE BY, old-style joins, deprecated hints, legacy functions

-- Pattern 1: COMPUTE BY (deprecated in SQL Server 2012+)
-- Note: This may error on execution but should parse
/*
SELECT 
    Category,
    ProductName,
    Price
FROM Products
ORDER BY Category, ProductName
COMPUTE SUM(Price) BY Category
COMPUTE SUM(Price);
GO
*/

-- Pattern 2: Old-style (non-ANSI) joins
SELECT p.ProductName, c.CategoryName
FROM Products p, Categories c
WHERE p.CategoryID = c.CategoryID;
GO

SELECT o.OrderID, c.CustomerName, p.ProductName
FROM Orders o, Customers c, OrderDetails od, Products p
WHERE o.CustomerID = c.CustomerID
  AND o.OrderID = od.OrderID
  AND od.ProductID = p.ProductID;
GO

-- Pattern 3: *= and =* operators (old outer join syntax)
-- Note: These may error but some parsers need to recognize them
/*
SELECT c.CustomerName, o.OrderID
FROM Customers c, Orders o
WHERE c.CustomerID *= o.CustomerID;  -- Left outer join

SELECT c.CustomerName, o.OrderID
FROM Customers c, Orders o
WHERE c.CustomerID =* o.CustomerID;  -- Right outer join
*/
GO

-- Pattern 4: Deprecated SET options
SET ANSI_NULLS OFF;  -- Deprecated but valid
SET ANSI_PADDING OFF;  -- Deprecated but valid
SET CONCAT_NULL_YIELDS_NULL OFF;  -- Deprecated but valid
SET ANSI_WARNINGS OFF;
GO

-- Reset to standard
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_WARNINGS ON;
GO

-- Pattern 5: READTEXT/WRITETEXT/UPDATETEXT (deprecated, for TEXT columns)
/*
DECLARE @ptrval VARBINARY(16);
SELECT @ptrval = TEXTPTR(Notes) FROM Documents WHERE DocID = 1;
READTEXT Documents.Notes @ptrval 0 100;

WRITETEXT Documents.Notes @ptrval 'New text content';

UPDATETEXT Documents.Notes @ptrval 0 50 'Replacement text';
*/
GO

-- Pattern 6: GROUP BY ALL (deprecated)
/*
SELECT Category, SUM(Price) AS TotalPrice
FROM Products
WHERE Price > 10
GROUP BY ALL Category;  -- Includes categories with no matching rows
*/
GO

-- Pattern 7: Old CONTAINS syntax variations
-- SELECT * FROM Products WHERE CONTAINS(*, 'search term');  -- Using *
GO

-- Pattern 8: Deprecated table hints
SELECT * FROM Products WITH (HOLDLOCK);  -- Still valid
SELECT * FROM Products WITH (READUNCOMMITTED);  -- Equivalent to NOLOCK
SELECT * FROM Products WITH (REPEATABLEREAD);
SELECT * FROM Products WITH (SERIALIZABLE);
SELECT * FROM Products (NOLOCK);  -- Old syntax without WITH
SELECT * FROM Products (INDEX = 1);  -- Old index hint syntax
GO

-- Pattern 9: Deprecated string functions (ODBC escape sequences)
-- Note: ODBC escape syntax {fn ...}, {d ...}, {t ...}, {ts ...} is legacy ODBC passthrough
-- and is out of scope for a pure T-SQL parser. Use native T-SQL equivalents instead:
SELECT 
    CONCAT('Hello', ' ', 'World') AS ModernConcat,
    UPPER('lower') AS ModernUpper,
    LOWER('UPPER') AS ModernLower,
    LEFT('Hello', 3) AS ModernLeft,
    LEN('Hello') AS ModernLength;
GO

-- Pattern 10: Date/time literals (using native T-SQL syntax instead of ODBC escapes)
SELECT 
    CAST('2024-01-15' AS DATE) AS NativeDate,
    CAST('14:30:00' AS TIME) AS NativeTime,
    CAST('2024-01-15 14:30:00' AS DATETIME2) AS NativeTimestamp;
GO

-- Example using native T-SQL date literal (instead of ODBC {d ...} escape)
SELECT * FROM Orders
WHERE OrderDate = CAST('2024-01-15' AS DATE);
GO

-- Pattern 11: Deprecated DUMP and LOAD (old backup/restore)
-- DUMP DATABASE MyDB TO disk = 'backup.bak';  -- Use BACKUP instead
-- LOAD DATABASE MyDB FROM disk = 'backup.bak';  -- Use RESTORE instead
GO

-- Pattern 12: sp_dboption (deprecated, use ALTER DATABASE)
-- EXEC sp_dboption 'MyDB', 'read only', 'true';
-- Modern: ALTER DATABASE MyDB SET READ_ONLY;
GO

-- Pattern 13: SETUSER (deprecated, use EXECUTE AS)
-- SETUSER 'guest';
-- Modern: EXECUTE AS USER = 'guest';
GO

-- Pattern 14: Old-style TOP without parentheses (pre-SQL 2005)
SELECT TOP 10 * FROM Products;
SELECT TOP 10 PERCENT * FROM Products;
-- Modern prefers: SELECT TOP (10) * FROM Products;
GO

-- Pattern 15: = for string assignment in SET (always worked)
DECLARE @str VARCHAR(100);
SET @str = 'test';  -- Standard
SELECT @str = 'test2';  -- Also valid (SELECT for assignment)
GO

-- Pattern 16: Deprecated raiserror syntax (without parentheses)
-- Note: Old syntax without parentheses is deprecated; use modern form
-- Old: RAISERROR 50001 'This is an error message'
RAISERROR('This is an error message', 16, 1);  -- Modern style
GO

-- Pattern 17: String delimiters variations
SET QUOTED_IDENTIFIER OFF;
GO
SELECT "This is a string literal when QUOTED_IDENTIFIER is OFF";
GO
SET QUOTED_IDENTIFIER ON;
GO
SELECT "TableName" AS "This is now an identifier";
GO

-- Pattern 18: PROC instead of PROCEDURE
CREATE PROC dbo.ShortProc
AS
SELECT 1;
GO

-- Pattern 19: TRAN instead of TRANSACTION
BEGIN TRAN;
SELECT 1;
COMMIT TRAN;
GO

-- Pattern 20: Mixed deprecated and modern syntax
SELECT TOP 10
    p.ProductName,
    c.CategoryName,
    p.Price
FROM Products p, Categories c  -- Old-style join
WHERE p.CategoryID = c.CategoryID
ORDER BY p.Price DESC;
GO

-- Pattern 21: FASTFIRSTROW hint (deprecated)
SELECT * FROM Products WITH (FASTFIRSTROW);
-- Modern equivalent: OPTION (FAST 1)
GO

-- Pattern 22: Deprecated isolation level hints
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT * FROM Products;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
GO

-- Pattern 23: TEXTIMAGE_ON filegroup (deprecated)
-- CREATE TABLE OldStyle (
--     ID INT PRIMARY KEY,
--     Data TEXT
-- ) TEXTIMAGE_ON [PRIMARY];
GO

-- Cleanup
DROP PROCEDURE IF EXISTS dbo.ShortProc;
GO
