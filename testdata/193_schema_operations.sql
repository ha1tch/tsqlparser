-- Sample 193: Schema Operations
-- Category: DDL / Administration
-- Complexity: Intermediate
-- Purpose: Parser testing - schema management syntax
-- Features: CREATE SCHEMA, ALTER SCHEMA, DROP SCHEMA, transfers

-- Pattern 1: Basic CREATE SCHEMA
CREATE SCHEMA Sales;
GO
DROP SCHEMA Sales;
GO

-- Pattern 2: CREATE SCHEMA with authorization
CREATE SCHEMA HR AUTHORIZATION dbo;
GO
DROP SCHEMA HR;
GO

-- Pattern 3: CREATE SCHEMA with objects (deprecated syntax)
CREATE SCHEMA Inventory
    CREATE TABLE Products (
        ProductID INT PRIMARY KEY,
        ProductName VARCHAR(100)
    )
    CREATE VIEW ActiveProducts AS
        SELECT * FROM Inventory.Products WHERE IsActive = 1;
GO
DROP VIEW Inventory.ActiveProducts;
DROP TABLE Inventory.Products;
DROP SCHEMA Inventory;
GO

-- Pattern 4: CREATE SCHEMA with GRANT
CREATE SCHEMA Reporting AUTHORIZATION dbo;
GO
DROP SCHEMA Reporting;
GO

-- Pattern 5: ALTER SCHEMA - transfer object
CREATE SCHEMA NewSchema;
GO

-- Transfer table to new schema
ALTER SCHEMA NewSchema TRANSFER dbo.SomeTable;

-- Transfer back
ALTER SCHEMA dbo TRANSFER NewSchema.SomeTable;

DROP SCHEMA NewSchema;
GO

-- Pattern 6: Transfer multiple object types
CREATE SCHEMA Archive;
GO

-- Tables
ALTER SCHEMA Archive TRANSFER dbo.OldOrders;

-- Views
ALTER SCHEMA Archive TRANSFER dbo.OldOrdersView;

-- Stored procedures
ALTER SCHEMA Archive TRANSFER dbo.GetOldOrders;

-- Functions
ALTER SCHEMA Archive TRANSFER dbo.CalculateOldTotal;

-- Types
ALTER SCHEMA Archive TRANSFER dbo.OldOrderType;

DROP SCHEMA Archive;
GO

-- Pattern 7: DROP SCHEMA
DROP SCHEMA IF EXISTS TempSchema;
GO

-- Pattern 8: List all schemas
SELECT 
    s.name AS SchemaName,
    p.name AS OwnerName,
    s.schema_id
FROM sys.schemas s
INNER JOIN sys.database_principals p ON s.principal_id = p.principal_id
ORDER BY s.name;
GO

-- Pattern 9: List objects in schema
SELECT 
    o.name AS ObjectName,
    o.type_desc AS ObjectType,
    s.name AS SchemaName
FROM sys.objects o
INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE s.name = 'dbo'
ORDER BY o.type_desc, o.name;
GO

-- Pattern 10: Check schema existence
IF SCHEMA_ID('MySchema') IS NOT NULL
    PRINT 'Schema exists';
ELSE
    PRINT 'Schema does not exist';
GO

-- Pattern 11: Create schema if not exists
IF SCHEMA_ID('NewSchema') IS NULL
    EXEC('CREATE SCHEMA NewSchema');
GO
DROP SCHEMA IF EXISTS NewSchema;
GO

-- Pattern 12: Schema for security isolation
CREATE SCHEMA SecureData AUTHORIZATION dbo;
GO

CREATE TABLE SecureData.SensitiveInfo (
    ID INT PRIMARY KEY,
    Data NVARCHAR(MAX)
);

-- Grant access only to specific role
GRANT SELECT ON SCHEMA::SecureData TO SensitiveDataReaders;

DROP TABLE SecureData.SensitiveInfo;
DROP SCHEMA SecureData;
GO

-- Pattern 13: Schema for module organization
CREATE SCHEMA Logging;
CREATE SCHEMA Audit;
CREATE SCHEMA Import;
CREATE SCHEMA Export;
GO

DROP SCHEMA Logging;
DROP SCHEMA Audit;
DROP SCHEMA Import;
DROP SCHEMA Export;
GO

-- Pattern 14: Default schema for user
ALTER USER TestUser WITH DEFAULT_SCHEMA = Sales;
GO

-- Pattern 15: Referencing objects across schemas
SELECT 
    c.CustomerName,
    o.OrderID
FROM dbo.Customers c
INNER JOIN Sales.Orders o ON c.CustomerID = o.CustomerID;
GO

-- Pattern 16: Schema-qualified object creation
CREATE TABLE Sales.Orders (
    OrderID INT PRIMARY KEY,
    CustomerID INT,
    OrderDate DATE
);
GO
DROP TABLE Sales.Orders;
GO

-- Pattern 17: Using SCHEMA_NAME function
SELECT 
    OBJECT_NAME(object_id) AS ObjectName,
    SCHEMA_NAME(schema_id) AS SchemaName
FROM sys.objects
WHERE type = 'U';
GO

-- Pattern 18: Schema binding
CREATE VIEW dbo.BoundView
WITH SCHEMABINDING
AS
    SELECT CustomerID, CustomerName
    FROM dbo.Customers;
GO
DROP VIEW dbo.BoundView;
GO

-- Pattern 19: Cross-schema foreign key
CREATE SCHEMA Orders;
GO

CREATE TABLE Orders.OrderHeaders (
    OrderID INT PRIMARY KEY,
    CustomerID INT REFERENCES dbo.Customers(CustomerID)
);
GO

DROP TABLE Orders.OrderHeaders;
DROP SCHEMA Orders;
GO

-- Pattern 20: Schema permissions
GRANT SELECT ON SCHEMA::dbo TO AppUser;
GRANT INSERT, UPDATE, DELETE ON SCHEMA::dbo TO AppWriter;
GRANT EXECUTE ON SCHEMA::dbo TO AppExecutor;
REVOKE SELECT ON SCHEMA::dbo FROM AppUser;
DENY DELETE ON SCHEMA::dbo TO RestrictedUser;
GO
