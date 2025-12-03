-- Sample 198: Identifier Quoting Patterns
-- Category: Syntax Coverage / Identifiers
-- Complexity: Intermediate
-- Purpose: Parser testing - identifier quoting syntax
-- Features: Brackets, double quotes, delimited identifiers

-- Pattern 1: Square brackets
SELECT [CustomerID], [CustomerName], [Email]
FROM [dbo].[Customers];
GO

-- Pattern 2: Double quotes (when QUOTED_IDENTIFIER is ON)
SET QUOTED_IDENTIFIER ON;
SELECT "CustomerID", "CustomerName", "Email"
FROM "dbo"."Customers";
GO

-- Pattern 3: Mixed quoting
SELECT [CustomerID], "CustomerName", Email
FROM [dbo]."Customers";
GO

-- Pattern 4: Reserved words as identifiers
CREATE TABLE [dbo].[Select] (
    [From] INT PRIMARY KEY,
    [Where] VARCHAR(100),
    [Order] INT,
    [Group] VARCHAR(50)
);

SELECT [From], [Where], [Order], [Group]
FROM [dbo].[Select];

DROP TABLE [dbo].[Select];
GO

-- Pattern 5: Identifiers with spaces
CREATE TABLE [dbo].[Customer Orders] (
    [Order ID] INT PRIMARY KEY,
    [Customer Name] VARCHAR(100),
    [Order Date] DATE
);

SELECT [Order ID], [Customer Name], [Order Date]
FROM [dbo].[Customer Orders];

DROP TABLE [dbo].[Customer Orders];
GO

-- Pattern 6: Identifiers with special characters
CREATE TABLE [dbo].[Order#Details] (
    [ID] INT PRIMARY KEY,
    [Price$] DECIMAL(10,2),
    [Qty%] INT,
    [Name@Work] VARCHAR(100)
);

SELECT [ID], [Price$], [Qty%], [Name@Work]
FROM [dbo].[Order#Details];

DROP TABLE [dbo].[Order#Details];
GO

-- Pattern 7: Identifiers with brackets inside
CREATE TABLE [dbo].[Table[1]] (
    [Column[A]] INT
);
-- To include ] in identifier, double it: ]]
SELECT [Column[A]]] 
FROM [dbo].[Table[1]]];

DROP TABLE [dbo].[Table[1]]];
GO

-- Pattern 8: Unicode identifiers
CREATE TABLE [dbo].[客户表] (
    [客户ID] INT PRIMARY KEY,
    [客户名称] NVARCHAR(100),
    [電子メール] NVARCHAR(200)
);

SELECT [客户ID], [客户名称], [電子メール]
FROM [dbo].[客户表];

DROP TABLE [dbo].[客户表];
GO

-- Pattern 9: Identifiers starting with numbers
CREATE TABLE [dbo].[123Table] (
    [456Column] INT
);

SELECT [456Column] FROM [dbo].[123Table];

DROP TABLE [dbo].[123Table];
GO

-- Pattern 10: Case sensitivity with quoting
-- SQL Server default: case-insensitive
SELECT CustomerID FROM dbo.Customers;
SELECT CUSTOMERID FROM DBO.CUSTOMERS;
SELECT customerid FROM Dbo.customers;
GO

-- Pattern 11: Four-part names with quoting
SELECT [CustomerID]
FROM [LinkedServer].[DatabaseName].[dbo].[Customers];
GO

-- Pattern 12: Temp table quoting
CREATE TABLE [#My Temp Table] (
    [Column With Spaces] INT
);

SELECT [Column With Spaces] FROM [#My Temp Table];
DROP TABLE [#My Temp Table];
GO

-- Pattern 13: Variable names (@ prefix)
DECLARE @MyVariable INT = 10;
DECLARE @[Variable With Spaces] INT = 20;
DECLARE @日本語変数 NVARCHAR(100) = N'Japanese';

SELECT @MyVariable, @[Variable With Spaces], @日本語変数;
GO

-- Pattern 14: Parameter names in procedures
CREATE PROCEDURE [dbo].[Procedure With Spaces]
    @[First Parameter] INT,
    @[Second Parameter] VARCHAR(100)
AS
BEGIN
    SELECT @[First Parameter], @[Second Parameter];
END;
GO

DROP PROCEDURE [dbo].[Procedure With Spaces];
GO

-- Pattern 15: Alias with quoting
SELECT 
    CustomerID AS [Customer ID],
    CustomerName AS [Full Name],
    Email AS [Email Address]
FROM dbo.Customers;
GO

-- Pattern 16: Column names in ORDER BY
SELECT CustomerID, CustomerName
FROM dbo.Customers
ORDER BY [CustomerName];
GO

-- Pattern 17: Column names in GROUP BY
SELECT [CategoryID], COUNT(*) AS [Product Count]
FROM dbo.Products
GROUP BY [CategoryID];
GO

-- Pattern 18: Identifiers in constraints
CREATE TABLE [dbo].[Constrained Table] (
    [ID] INT CONSTRAINT [PK_Constrained Table] PRIMARY KEY,
    [Email] VARCHAR(200) CONSTRAINT [UQ_Email Address] UNIQUE,
    [Age] INT CONSTRAINT [CK_Valid Age] CHECK ([Age] >= 0)
);

DROP TABLE [dbo].[Constrained Table];
GO

-- Pattern 19: Index names with quoting
CREATE INDEX [IX_Customer Name] ON dbo.Customers ([CustomerName]);
DROP INDEX [IX_Customer Name] ON dbo.Customers;
GO

-- Pattern 20: QUOTENAME function
SELECT 
    QUOTENAME('Column') AS BracketQuoted,
    QUOTENAME('Column', '"') AS DoubleQuoted,
    QUOTENAME('Column', '''') AS SingleQuoted,
    QUOTENAME('Table[1]') AS WithBracket;
GO

-- Pattern 21: Dynamic SQL with quoted identifiers
DECLARE @TableName SYSNAME = 'Customers';
DECLARE @ColumnName SYSNAME = 'Customer Name';
DECLARE @SQL NVARCHAR(MAX);

SET @SQL = N'SELECT ' + QUOTENAME(@ColumnName) + N' FROM dbo.' + QUOTENAME(@TableName);
PRINT @SQL;
-- EXEC sp_executesql @SQL;
GO

-- Pattern 22: Object names with periods
CREATE TABLE [dbo].[table.with.dots] (
    [column.with.dots] INT
);

SELECT [column.with.dots] FROM [dbo].[table.with.dots];
DROP TABLE [dbo].[table.with.dots];
GO
