-- Sample 181: SELECT INTO and INSERT Patterns
-- Category: DML / Syntax Coverage
-- Complexity: Complex
-- Purpose: Parser testing - INSERT and SELECT INTO syntax
-- Features: All INSERT variations, SELECT INTO, OUTPUT clause

-- Pattern 1: Basic INSERT with VALUES
INSERT INTO dbo.Customers (CustomerName, Email)
VALUES ('John Smith', 'john@example.com');
GO

-- Pattern 2: INSERT with multiple rows
INSERT INTO dbo.Customers (CustomerName, Email, Phone)
VALUES 
    ('Customer 1', 'c1@example.com', '111-1111'),
    ('Customer 2', 'c2@example.com', '222-2222'),
    ('Customer 3', 'c3@example.com', '333-3333');
GO

-- Pattern 3: INSERT without column list
INSERT INTO dbo.SimpleTable
VALUES (1, 'Value1', GETDATE());
GO

-- Pattern 4: INSERT with DEFAULT VALUES
INSERT INTO dbo.LogTable DEFAULT VALUES;
GO

-- Pattern 5: INSERT with DEFAULT keyword
INSERT INTO dbo.Customers (CustomerName, Email, CreatedDate, IsActive)
VALUES ('Test', 'test@example.com', DEFAULT, DEFAULT);
GO

-- Pattern 6: INSERT with NULL
INSERT INTO dbo.Customers (CustomerName, Email, Phone, Fax)
VALUES ('Test', 'test@example.com', NULL, NULL);
GO

-- Pattern 7: INSERT with SELECT
INSERT INTO dbo.CustomerArchive (CustomerID, CustomerName, Email)
SELECT CustomerID, CustomerName, Email
FROM dbo.Customers
WHERE IsActive = 0;
GO

-- Pattern 8: INSERT with SELECT and TOP
INSERT INTO dbo.TopCustomers (CustomerID, CustomerName)
SELECT TOP 100 CustomerID, CustomerName
FROM dbo.Customers
ORDER BY CreatedDate DESC;
GO

-- Pattern 9: INSERT with SELECT and JOIN
INSERT INTO dbo.OrderSummary (CustomerID, CustomerName, TotalOrders, TotalAmount)
SELECT 
    c.CustomerID,
    c.CustomerName,
    COUNT(o.OrderID),
    SUM(o.TotalAmount)
FROM dbo.Customers c
LEFT JOIN dbo.Orders o ON c.CustomerID = o.CustomerID
GROUP BY c.CustomerID, c.CustomerName;
GO

-- Pattern 10: INSERT with CTE
WITH ActiveOrders AS (
    SELECT CustomerID, OrderID, TotalAmount
    FROM dbo.Orders
    WHERE Status = 'Active'
)
INSERT INTO dbo.ActiveOrdersBackup
SELECT * FROM ActiveOrders;
GO

-- Pattern 11: INSERT with EXEC
INSERT INTO dbo.Results (ResultData)
EXEC dbo.GetCustomerData @CustomerID = 1;
GO

-- Pattern 12: INSERT with EXEC of dynamic SQL
DECLARE @SQL NVARCHAR(MAX) = N'SELECT CustomerID, CustomerName FROM dbo.Customers';
INSERT INTO #TempCustomers
EXEC sp_executesql @SQL;
GO

-- Pattern 13: INSERT with OUTPUT clause
DECLARE @InsertedIDs TABLE (ID INT);

INSERT INTO dbo.Customers (CustomerName, Email)
OUTPUT inserted.CustomerID INTO @InsertedIDs
VALUES ('New Customer', 'new@example.com');

SELECT * FROM @InsertedIDs;
GO

-- Pattern 14: INSERT with OUTPUT to table
INSERT INTO dbo.Customers (CustomerName, Email)
OUTPUT inserted.CustomerID, inserted.CustomerName, 'INSERT', GETDATE()
INTO dbo.AuditLog (RecordID, RecordName, Action, ActionDate)
VALUES ('Audited Customer', 'audit@example.com');
GO

-- Pattern 15: INSERT with identity column
SET IDENTITY_INSERT dbo.Customers ON;

INSERT INTO dbo.Customers (CustomerID, CustomerName, Email)
VALUES (999, 'Manual ID', 'manual@example.com');

SET IDENTITY_INSERT dbo.Customers OFF;
GO

-- Pattern 16: INSERT into table variable
DECLARE @TempData TABLE (ID INT, Name VARCHAR(100));

INSERT INTO @TempData (ID, Name)
VALUES (1, 'First'), (2, 'Second');

SELECT * FROM @TempData;
GO

-- Pattern 17: INSERT with OPENROWSET
INSERT INTO dbo.ImportedData
SELECT * FROM OPENROWSET(
    BULK 'C:\Data\import.csv',
    FORMATFILE = 'C:\Data\format.fmt'
) AS data;
GO

-- Pattern 18: Basic SELECT INTO
SELECT CustomerID, CustomerName, Email
INTO dbo.CustomersCopy
FROM dbo.Customers;
GO
DROP TABLE dbo.CustomersCopy;
GO

-- Pattern 19: SELECT INTO with expression
SELECT 
    CustomerID,
    CustomerName,
    Email,
    GETDATE() AS CopyDate,
    1 AS IsBackup
INTO dbo.CustomersBackup
FROM dbo.Customers
WHERE IsActive = 1;
GO
DROP TABLE dbo.CustomersBackup;
GO

-- Pattern 20: SELECT INTO temp table
SELECT CustomerID, CustomerName
INTO #TempCustomers
FROM dbo.Customers
WHERE IsActive = 1;

SELECT * FROM #TempCustomers;
DROP TABLE #TempCustomers;
GO

-- Pattern 21: SELECT INTO with JOIN
SELECT 
    c.CustomerID,
    c.CustomerName,
    COUNT(o.OrderID) AS OrderCount,
    SUM(o.TotalAmount) AS TotalSpent
INTO dbo.CustomerStats
FROM dbo.Customers c
LEFT JOIN dbo.Orders o ON c.CustomerID = o.CustomerID
GROUP BY c.CustomerID, c.CustomerName;
GO
DROP TABLE dbo.CustomerStats;
GO

-- Pattern 22: SELECT INTO with filegroup
SELECT *
INTO dbo.ArchiveData
ON [ArchiveFileGroup]
FROM dbo.CurrentData
WHERE CreatedDate < '2020-01-01';
GO

-- Pattern 23: SELECT INTO with IDENTITY
SELECT 
    IDENTITY(INT, 1, 1) AS NewID,
    CustomerName,
    Email
INTO dbo.CustomersWithNewID
FROM dbo.Customers;
GO
DROP TABLE dbo.CustomersWithNewID;
GO

-- Pattern 24: INSERT with row constructor for UNPIVOT-like
INSERT INTO dbo.AttributeValues (EntityID, AttributeName, AttributeValue)
SELECT 
    p.ProductID,
    attr.Name,
    attr.Value
FROM dbo.Products p
CROSS APPLY (VALUES
    ('Color', p.Color),
    ('Size', p.Size),
    ('Weight', CAST(p.Weight AS VARCHAR(50)))
) AS attr(Name, Value)
WHERE attr.Value IS NOT NULL;
GO

-- Pattern 25: INSERT with TABLOCK hint
INSERT INTO dbo.LargeTable WITH (TABLOCK)
SELECT * FROM dbo.SourceTable;
GO

-- Pattern 26: INSERT with IGNORE_DUP_KEY index
-- When table has unique index with IGNORE_DUP_KEY = ON
INSERT INTO dbo.UniqueTable (UniqueColumn, Data)
VALUES ('Value1', 'Data1'),
       ('Value1', 'Data2'),  -- Duplicate, will be ignored
       ('Value2', 'Data3');
GO

-- Pattern 27: INSERT with computed column (omit from INSERT)
-- Table has computed column: FullName AS FirstName + ' ' + LastName
INSERT INTO dbo.People (FirstName, LastName, Email)
VALUES ('John', 'Smith', 'john@example.com');
GO

-- Pattern 28: Conditional INSERT (INSERT WHERE NOT EXISTS)
INSERT INTO dbo.Customers (CustomerName, Email)
SELECT 'New Customer', 'new@example.com'
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.Customers WHERE Email = 'new@example.com'
);
GO

-- Pattern 29: INSERT with CROSS JOIN for cartesian
INSERT INTO dbo.ProductPriceMatrix (ProductID, RegionID, Price)
SELECT p.ProductID, r.RegionID, p.BasePrice * r.PriceMultiplier
FROM dbo.Products p
CROSS JOIN dbo.Regions r;
GO

-- Pattern 30: INSERT from VALUES as table source
INSERT INTO dbo.StatusCodes (Code, Description)
SELECT Code, Description
FROM (VALUES
    ('A', 'Active'),
    ('I', 'Inactive'),
    ('P', 'Pending'),
    ('X', 'Deleted')
) AS v(Code, Description)
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.StatusCodes WHERE Code = v.Code
);
GO
