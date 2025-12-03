-- Sample 165: Synonyms and Object Aliases
-- Category: Missing Syntax Elements / DDL
-- Complexity: Intermediate
-- Purpose: Parser testing - synonym syntax
-- Features: CREATE SYNONYM, DROP SYNONYM, synonym usage patterns

-- Pattern 1: Basic synonym for table
CREATE SYNONYM dbo.Cust FOR dbo.Customers;

SELECT * FROM dbo.Cust WHERE CustomerID = 1;

DROP SYNONYM dbo.Cust;
GO

-- Pattern 2: Synonym for table in different schema
CREATE SCHEMA Sales;
GO

CREATE TABLE Sales.Orders (
    OrderID INT PRIMARY KEY,
    OrderDate DATE
);

CREATE SYNONYM dbo.SalesOrders FOR Sales.Orders;

SELECT * FROM dbo.SalesOrders;

DROP SYNONYM dbo.SalesOrders;
DROP TABLE Sales.Orders;
DROP SCHEMA Sales;
GO

-- Pattern 3: Synonym for linked server table
CREATE SYNONYM dbo.RemoteCustomers 
    FOR LinkedServer.RemoteDB.dbo.Customers;
    
DROP SYNONYM dbo.RemoteCustomers;
GO

-- Pattern 4: Synonym for view
CREATE VIEW dbo.ActiveCustomersView AS
    SELECT CustomerID, CustomerName FROM dbo.Customers WHERE IsActive = 1;
GO

CREATE SYNONYM dbo.ActiveCust FOR dbo.ActiveCustomersView;

SELECT * FROM dbo.ActiveCust;

DROP SYNONYM dbo.ActiveCust;
DROP VIEW dbo.ActiveCustomersView;
GO

-- Pattern 5: Synonym for stored procedure
CREATE PROCEDURE dbo.GetCustomerDetails
    @CustomerID INT
AS
BEGIN
    SELECT * FROM dbo.Customers WHERE CustomerID = @CustomerID;
END;
GO

CREATE SYNONYM dbo.GetCust FOR dbo.GetCustomerDetails;

EXEC dbo.GetCust @CustomerID = 1;

DROP SYNONYM dbo.GetCust;
DROP PROCEDURE dbo.GetCustomerDetails;
GO

-- Pattern 6: Synonym for scalar function
CREATE FUNCTION dbo.GetCustomerName(@CustomerID INT)
RETURNS VARCHAR(100)
AS
BEGIN
    DECLARE @Name VARCHAR(100);
    SELECT @Name = CustomerName FROM dbo.Customers WHERE CustomerID = @CustomerID;
    RETURN @Name;
END;
GO

CREATE SYNONYM dbo.CustName FOR dbo.GetCustomerName;

SELECT dbo.CustName(1) AS CustomerName;

DROP SYNONYM dbo.CustName;
DROP FUNCTION dbo.GetCustomerName;
GO

-- Pattern 7: Synonym for table-valued function
CREATE FUNCTION dbo.GetCustomerOrders(@CustomerID INT)
RETURNS TABLE
AS
RETURN (
    SELECT OrderID, OrderDate, TotalAmount
    FROM dbo.Orders
    WHERE CustomerID = @CustomerID
);
GO

CREATE SYNONYM dbo.CustOrders FOR dbo.GetCustomerOrders;

SELECT * FROM dbo.CustOrders(1);

DROP SYNONYM dbo.CustOrders;
DROP FUNCTION dbo.GetCustomerOrders;
GO

-- Pattern 8: Synonym for aggregate function (user-defined)
-- Note: Requires CLR aggregate to be created first
-- CREATE SYNONYM dbo.MyAgg FOR dbo.MyUserDefinedAggregate;
GO

-- Pattern 9: Using synonyms in INSERT
CREATE SYNONYM dbo.CustInsert FOR dbo.Customers;

INSERT INTO dbo.CustInsert (CustomerName, Email)
VALUES ('Test Customer', 'test@example.com');

DROP SYNONYM dbo.CustInsert;
GO

-- Pattern 10: Using synonyms in UPDATE
CREATE SYNONYM dbo.CustUpdate FOR dbo.Customers;

UPDATE dbo.CustUpdate
SET ModifiedDate = GETDATE()
WHERE CustomerID = 1;

DROP SYNONYM dbo.CustUpdate;
GO

-- Pattern 11: Using synonyms in DELETE
CREATE SYNONYM dbo.CustDelete FOR dbo.Customers;

DELETE FROM dbo.CustDelete WHERE CustomerID = 999999;

DROP SYNONYM dbo.CustDelete;
GO

-- Pattern 12: Using synonyms in JOIN
CREATE SYNONYM dbo.C FOR dbo.Customers;
CREATE SYNONYM dbo.O FOR dbo.Orders;

SELECT c.CustomerName, o.OrderDate, o.TotalAmount
FROM dbo.C c
INNER JOIN dbo.O o ON c.CustomerID = o.CustomerID;

DROP SYNONYM dbo.C;
DROP SYNONYM dbo.O;
GO

-- Pattern 13: Synonym pointing to another database
CREATE SYNONYM dbo.OtherDBTable FOR OtherDatabase.dbo.SomeTable;
DROP SYNONYM dbo.OtherDBTable;
GO

-- Pattern 14: Synonym with four-part name (linked server)
CREATE SYNONYM dbo.FullyQualified 
    FOR [LinkedServer].[DatabaseName].[SchemaName].[TableName];
DROP SYNONYM dbo.FullyQualified;
GO

-- Pattern 15: Querying synonym metadata
SELECT 
    name AS SynonymName,
    SCHEMA_NAME(schema_id) AS SchemaName,
    base_object_name AS BaseObject,
    create_date,
    modify_date
FROM sys.synonyms;
GO

-- Pattern 16: Synonym in different schema
CREATE SCHEMA Reporting;
GO

CREATE SYNONYM Reporting.CustomerReport FOR dbo.Customers;

SELECT * FROM Reporting.CustomerReport;

DROP SYNONYM Reporting.CustomerReport;
DROP SCHEMA Reporting;
GO

-- Pattern 17: Changing synonym target (drop and recreate)
CREATE SYNONYM dbo.DataSource FOR dbo.Customers;

-- To change target, must drop and recreate
DROP SYNONYM dbo.DataSource;
CREATE SYNONYM dbo.DataSource FOR dbo.Orders;

SELECT TOP 5 * FROM dbo.DataSource;

DROP SYNONYM dbo.DataSource;
GO

-- Pattern 18: Synonym in stored procedure
CREATE SYNONYM dbo.CustomerSyn FOR dbo.Customers;
GO

CREATE PROCEDURE dbo.GetCustomersBySynonym
AS
BEGIN
    SELECT CustomerID, CustomerName 
    FROM dbo.CustomerSyn 
    WHERE IsActive = 1;
END;
GO

EXEC dbo.GetCustomersBySynonym;

DROP PROCEDURE dbo.GetCustomersBySynonym;
DROP SYNONYM dbo.CustomerSyn;
GO

-- Pattern 19: Synonym in view definition
CREATE SYNONYM dbo.CustSyn FOR dbo.Customers;
GO

CREATE VIEW dbo.CustomerViewUsingSynonym AS
    SELECT CustomerID, CustomerName FROM dbo.CustSyn;
GO

SELECT * FROM dbo.CustomerViewUsingSynonym;

DROP VIEW dbo.CustomerViewUsingSynonym;
DROP SYNONYM dbo.CustSyn;
GO

-- Pattern 20: Checking if synonym exists
IF EXISTS (SELECT 1 FROM sys.synonyms WHERE name = 'TestSynonym' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
    DROP SYNONYM dbo.TestSynonym;
END

CREATE SYNONYM dbo.TestSynonym FOR dbo.Customers;

-- Check again
IF OBJECT_ID('dbo.TestSynonym', 'SN') IS NOT NULL
    PRINT 'Synonym exists';

DROP SYNONYM dbo.TestSynonym;
GO

-- Pattern 21: Table alias vs synonym
-- Alias: temporary, query-scoped
SELECT c.CustomerID, c.CustomerName
FROM dbo.Customers AS c;

-- Synonym: permanent, database object
CREATE SYNONYM dbo.C FOR dbo.Customers;
SELECT CustomerID, CustomerName FROM dbo.C;
DROP SYNONYM dbo.C;
GO
