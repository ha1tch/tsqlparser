-- Sample 121: Collation Specifications and String Comparison
-- Category: Missing Syntax Elements
-- Complexity: Complex
-- Purpose: Parser testing - collation syntax in various contexts
-- Features: COLLATE clause, collation in expressions, comparisons, sorting

-- Pattern 1: COLLATE in column definition
CREATE TABLE dbo.MultiLanguageData (
    ID INT IDENTITY(1,1) PRIMARY KEY,
    EnglishText VARCHAR(100) COLLATE Latin1_General_CI_AS,
    GermanText VARCHAR(100) COLLATE German_PhoneBook_CI_AS,
    FrenchText VARCHAR(100) COLLATE French_CI_AS,
    TurkishText NVARCHAR(100) COLLATE Turkish_CI_AS,
    JapaneseText NVARCHAR(100) COLLATE Japanese_CI_AS,
    ChineseText NVARCHAR(100) COLLATE Chinese_PRC_CI_AS,
    BinaryText VARCHAR(100) COLLATE Latin1_General_BIN,
    BinaryText2 VARCHAR(100) COLLATE Latin1_General_BIN2
);
GO

-- Pattern 2: COLLATE in comparison
SELECT *
FROM Customers
WHERE CustomerName COLLATE Latin1_General_CI_AS = 'SMITH';  -- Case insensitive
GO

SELECT *
FROM Customers
WHERE CustomerName COLLATE Latin1_General_CS_AS = 'Smith';  -- Case sensitive
GO

-- Pattern 3: COLLATE in ORDER BY
SELECT CustomerName
FROM Customers
ORDER BY CustomerName COLLATE Latin1_General_CI_AS;
GO

SELECT CustomerName
FROM Customers
ORDER BY CustomerName COLLATE Latin1_General_BIN;  -- Binary sort (ASCII order)
GO

-- Pattern 4: COLLATE in JOIN condition
SELECT a.Name, b.Name
FROM TableA a
INNER JOIN TableB b ON a.Name COLLATE Latin1_General_CI_AS = b.Name COLLATE Latin1_General_CI_AS;
GO

-- Pattern 5: COLLATE in WHERE with LIKE
SELECT *
FROM Products
WHERE ProductName COLLATE Latin1_General_CI_AS LIKE '%café%';  -- Accent insensitive
GO

SELECT *
FROM Products
WHERE ProductName COLLATE Latin1_General_CS_AI LIKE '%CAFE%';  -- Case sensitive, Accent insensitive
GO

-- Pattern 6: COLLATE in CASE expression
SELECT 
    CustomerName,
    CASE 
        WHEN CustomerName COLLATE Latin1_General_CI_AS = 'smith' THEN 'Found Smith'
        ELSE 'Other'
    END AS Result
FROM Customers;
GO

-- Pattern 7: COLLATE in aggregate
SELECT 
    MAX(ProductName COLLATE Latin1_General_BIN) AS MaxBinary,
    MIN(ProductName COLLATE Latin1_General_BIN) AS MinBinary
FROM Products;
GO

-- Pattern 8: COLLATE in UNION (resolving collation conflicts)
SELECT Name COLLATE Latin1_General_CI_AS AS CombinedName FROM Table1
UNION
SELECT Name COLLATE Latin1_General_CI_AS FROM Table2;
GO

-- Pattern 9: COLLATE in GROUP BY
SELECT 
    CustomerName COLLATE Latin1_General_CI_AS AS NormalizedName,
    COUNT(*) AS Count
FROM Customers
GROUP BY CustomerName COLLATE Latin1_General_CI_AS;
GO

-- Pattern 10: COLLATE in computed column
ALTER TABLE Products
ADD SearchName AS (ProductName COLLATE Latin1_General_CI_AI);
GO

-- Pattern 11: COLLATE in variable declaration
DECLARE @SearchTerm VARCHAR(100) COLLATE Latin1_General_CI_AS = 'test';
SELECT * FROM Products WHERE ProductName = @SearchTerm;
GO

-- Pattern 12: Collation-sensitive comparison variations
DECLARE @Text1 NVARCHAR(50) = N'Café';
DECLARE @Text2 NVARCHAR(50) = N'cafe';
DECLARE @Text3 NVARCHAR(50) = N'CAFÉ';

SELECT 
    -- Case Insensitive, Accent Sensitive
    CASE WHEN @Text1 COLLATE Latin1_General_CI_AS = @Text2 THEN 'Match' ELSE 'No Match' END AS CI_AS,
    
    -- Case Sensitive, Accent Insensitive  
    CASE WHEN @Text1 COLLATE Latin1_General_CS_AI = @Text2 THEN 'Match' ELSE 'No Match' END AS CS_AI,
    
    -- Case Insensitive, Accent Insensitive
    CASE WHEN @Text1 COLLATE Latin1_General_CI_AI = @Text2 THEN 'Match' ELSE 'No Match' END AS CI_AI,
    
    -- Case Sensitive, Accent Sensitive
    CASE WHEN @Text1 COLLATE Latin1_General_CS_AS = @Text2 THEN 'Match' ELSE 'No Match' END AS CS_AS,
    
    -- Binary comparison
    CASE WHEN @Text1 COLLATE Latin1_General_BIN = @Text3 THEN 'Match' ELSE 'No Match' END AS BIN;
GO

-- Pattern 13: Collation in temp table
CREATE TABLE #TempCollation (
    ID INT,
    Name VARCHAR(100) COLLATE DATABASE_DEFAULT,
    Code VARCHAR(50) COLLATE SQL_Latin1_General_CP1_CI_AS
);
GO

-- Pattern 14: Collation in table variable
DECLARE @TableVar TABLE (
    ID INT,
    Name VARCHAR(100) COLLATE Latin1_General_CI_AS
);
GO

-- Pattern 15: COLLATE with Unicode data
SELECT 
    N'Ä' COLLATE German_PhoneBook_CI_AS AS German1,
    N'Ae' COLLATE German_PhoneBook_CI_AS AS German2,
    CASE WHEN N'Ä' COLLATE German_PhoneBook_CI_AS = N'Ae' THEN 'Equal' ELSE 'Not Equal' END AS Comparison;
GO

-- Pattern 16: COLLATE in CHARINDEX/PATINDEX
SELECT 
    CHARINDEX('é', 'Café' COLLATE Latin1_General_CI_AI) AS WithAccent,
    CHARINDEX('e', 'Café' COLLATE Latin1_General_CI_AI) AS WithoutAccent;
GO

-- Pattern 17: Collation in constraint
CREATE TABLE dbo.UniqueNames (
    ID INT PRIMARY KEY,
    Name VARCHAR(100),
    CONSTRAINT UQ_Name_CI UNIQUE (Name)  -- Uses table's collation
);
GO

-- Pattern 18: List available collations
SELECT name, description
FROM fn_helpcollations()
WHERE name LIKE 'Latin1_General%'
ORDER BY name;
GO

-- Pattern 19: Database and server collation
SELECT 
    SERVERPROPERTY('Collation') AS ServerCollation,
    DATABASEPROPERTYEX(DB_NAME(), 'Collation') AS DatabaseCollation;
GO

-- Pattern 20: Column collation from metadata
SELECT 
    c.name AS ColumnName,
    c.collation_name AS Collation
FROM sys.columns c
WHERE c.object_id = OBJECT_ID('dbo.Customers')
AND c.collation_name IS NOT NULL;
GO

-- Pattern 21: SQL collations vs Windows collations
-- SQL_Latin1_General_CP1_CI_AS (SQL collation)
-- Latin1_General_CI_AS (Windows collation)
SELECT 
    CASE WHEN 'a' COLLATE SQL_Latin1_General_CP1_CI_AS = 'A' THEN 'Equal' ELSE 'Not Equal' END AS SQLCollation,
    CASE WHEN 'a' COLLATE Latin1_General_CI_AS = 'A' THEN 'Equal' ELSE 'Not Equal' END AS WindowsCollation;
GO

-- Pattern 22: Supplementary character aware collations (_SC)
SELECT 
    N'𠀀' COLLATE Latin1_General_100_CI_AS_SC AS SCCollation;  -- SQL Server 2012+
GO

-- Pattern 23: UTF-8 collations (SQL Server 2019+)
-- CREATE TABLE dbo.UTF8Table (
--     ID INT,
--     Text VARCHAR(100) COLLATE Latin1_General_100_CI_AS_SC_UTF8
-- );
-- GO

-- Pattern 24: Kana-sensitive and Width-sensitive collations
SELECT 
    CASE WHEN N'カ' COLLATE Japanese_CI_AS_KS = N'ｶ' THEN 'Equal' ELSE 'Not Equal' END AS KanaSensitive,
    CASE WHEN N'Ａ' COLLATE Japanese_CI_AS_WS = N'A' THEN 'Equal' ELSE 'Not Equal' END AS WidthSensitive;
GO

-- Pattern 25: COLLATE in expression concatenation
SELECT 
    FirstName COLLATE Latin1_General_CI_AS + ' ' + LastName COLLATE Latin1_General_CI_AS AS FullName
FROM Employees;
GO
