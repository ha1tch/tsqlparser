-- Sample 119: Four-Part Names and Distributed Queries
-- Category: Missing Syntax Elements
-- Complexity: Advanced
-- Purpose: Parser testing - linked server and distributed query syntax
-- Features: Four-part names, OPENQUERY, OPENROWSET, distributed transactions

-- Pattern 1: Four-part naming convention
-- [Server].[Database].[Schema].[Object]
SELECT *
FROM [LinkedServer1].[RemoteDB].[dbo].[Customers]
WHERE CustomerID = 100;
GO

SELECT 
    c.CustomerID,
    c.CustomerName,
    o.OrderID,
    o.OrderDate
FROM [LinkedServer1].[RemoteDB].[dbo].[Customers] c
INNER JOIN [LinkedServer1].[RemoteDB].[dbo].[Orders] o ON c.CustomerID = o.CustomerID
WHERE o.OrderDate >= '2024-01-01';
GO

-- Pattern 2: Mixed local and remote tables
SELECT 
    l.LocalColumn,
    r.RemoteColumn
FROM dbo.LocalTable l
INNER JOIN [LinkedServer1].[RemoteDB].[dbo].[RemoteTable] r ON l.ID = r.ID;
GO

-- Pattern 3: INSERT from remote to local
INSERT INTO dbo.LocalCustomers (CustomerID, CustomerName, Email)
SELECT CustomerID, CustomerName, Email
FROM [LinkedServer1].[RemoteDB].[dbo].[Customers]
WHERE Region = 'West';
GO

-- Pattern 4: UPDATE using remote data
UPDATE l
SET l.LastSyncDate = GETDATE(),
    l.RemoteValue = r.Value
FROM dbo.LocalTable l
INNER JOIN [LinkedServer1].[RemoteDB].[dbo].[RemoteTable] r ON l.ID = r.ID
WHERE r.ModifiedDate > l.LastSyncDate;
GO

-- Pattern 5: DELETE with remote lookup
DELETE FROM dbo.LocalOrders
WHERE CustomerID IN (
    SELECT CustomerID 
    FROM [LinkedServer1].[RemoteDB].[dbo].[DeletedCustomers]
);
GO

-- Pattern 6: OPENQUERY for passthrough queries
SELECT *
FROM OPENQUERY([LinkedServer1], 'SELECT CustomerID, CustomerName FROM Customers WHERE Active = 1');
GO

SELECT *
FROM OPENQUERY([LinkedServer1], 
    'SELECT TOP 100 OrderID, OrderDate, TotalAmount 
     FROM Orders 
     WHERE OrderDate >= ''2024-01-01'' 
     ORDER BY OrderDate DESC');
GO

-- Pattern 7: OPENQUERY with joins
SELECT 
    oq.CustomerID,
    oq.CustomerName,
    l.LocalData
FROM OPENQUERY([LinkedServer1], 'SELECT CustomerID, CustomerName FROM Customers') oq
INNER JOIN dbo.LocalTable l ON oq.CustomerID = l.CustomerID;
GO

-- Pattern 8: INSERT using OPENQUERY
INSERT INTO OPENQUERY([LinkedServer1], 'SELECT CustomerID, CustomerName, Email FROM Customers')
VALUES (999, 'New Customer', 'new@example.com');
GO

-- Pattern 9: UPDATE using OPENQUERY
UPDATE OPENQUERY([LinkedServer1], 'SELECT CustomerID, Status FROM Customers WHERE CustomerID = 100')
SET Status = 'Inactive';
GO

-- Pattern 10: DELETE using OPENQUERY
DELETE FROM OPENQUERY([LinkedServer1], 'SELECT * FROM Customers WHERE Status = ''Deleted''');
GO

-- Pattern 11: OPENROWSET with provider
SELECT *
FROM OPENROWSET(
    'SQLNCLI',
    'Server=RemoteServer;Trusted_Connection=yes;',
    'SELECT * FROM RemoteDB.dbo.Customers'
);
GO

-- Pattern 12: OPENROWSET with explicit credentials
SELECT *
FROM OPENROWSET(
    'SQLNCLI',
    'Server=RemoteServer;UID=sa;PWD=password123;',
    'SELECT * FROM RemoteDB.dbo.Customers'
);
GO

-- Pattern 13: OPENROWSET for bulk operations
SELECT *
FROM OPENROWSET(
    BULK 'C:\Data\customers.csv',
    FORMATFILE = 'C:\Data\customers.fmt',
    FIRSTROW = 2
) AS DataFile;
GO

-- Pattern 14: OPENROWSET with SINGLE_BLOB
SELECT *
FROM OPENROWSET(
    BULK 'C:\Data\document.pdf',
    SINGLE_BLOB
) AS Document;
GO

-- Pattern 15: EXEC AT linked server
EXEC ('SELECT COUNT(*) FROM Customers') AT [LinkedServer1];
GO

EXEC ('UPDATE Statistics dbo.Customers') AT [LinkedServer1];
GO

-- Pattern 16: Parameterized EXEC AT
DECLARE @CustomerID INT = 100;
EXEC ('SELECT * FROM Customers WHERE CustomerID = ?', @CustomerID) AT [LinkedServer1];
GO

-- Pattern 17: Distributed transaction
SET XACT_ABORT ON;

BEGIN DISTRIBUTED TRANSACTION;

    -- Update local
    UPDATE dbo.LocalOrders SET Status = 'Synced' WHERE OrderID = 1000;
    
    -- Update remote
    UPDATE [LinkedServer1].[RemoteDB].[dbo].[Orders] SET Status = 'Synced' WHERE OrderID = 1000;

COMMIT TRANSACTION;
GO

-- Pattern 18: Multiple linked servers in one query
SELECT 
    c.CustomerName,
    o.OrderID,
    p.PaymentAmount
FROM [Server1].[DB1].[dbo].[Customers] c
INNER JOIN [Server2].[DB2].[dbo].[Orders] o ON c.CustomerID = o.CustomerID
INNER JOIN [Server3].[DB3].[dbo].[Payments] p ON o.OrderID = p.OrderID
WHERE c.Region = 'East';
GO

-- Pattern 19: Stored procedure on linked server
EXEC [LinkedServer1].[RemoteDB].[dbo].[usp_GetCustomerOrders] @CustomerID = 100;
GO

-- Pattern 20: sp_addlinkedserver reference (setup)
-- EXEC sp_addlinkedserver 
--     @server = 'LinkedServer1',
--     @srvproduct = '',
--     @provider = 'SQLNCLI',
--     @datasrc = 'RemoteServer\Instance';
-- GO

-- Pattern 21: Catalog views across linked servers
SELECT *
FROM [LinkedServer1].[RemoteDB].sys.tables
WHERE type = 'U';
GO

SELECT *
FROM [LinkedServer1].[RemoteDB].INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'Customers';
GO

-- Pattern 22: Default database in four-part name
SELECT *
FROM [LinkedServer1]..dbo.Customers;  -- Uses default database on linked server
GO

-- Pattern 23: Three-part name (different database, same server)
SELECT *
FROM [OtherDatabase].[dbo].[Customers];
GO

SELECT *
FROM OtherDatabase.dbo.Customers;  -- Without brackets
GO

-- Pattern 24: Cross-database join
SELECT 
    c.CustomerID,
    c.CustomerName,
    o.OrderID
FROM CurrentDB.dbo.Customers c
INNER JOIN ArchiveDB.dbo.Orders o ON c.CustomerID = o.CustomerID;
GO
