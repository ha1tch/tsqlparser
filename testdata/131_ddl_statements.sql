-- Sample 131: DDL Statements and Schema Creation
-- Category: Schema and Test Data Scripts
-- Complexity: Complex
-- Purpose: Parser testing - comprehensive DDL syntax
-- Features: CREATE, ALTER, DROP for all object types, constraints, indexes

-- Pattern 1: CREATE SCHEMA
CREATE SCHEMA Sales AUTHORIZATION dbo;
GO

CREATE SCHEMA HR;
GO

-- Pattern 2: CREATE TABLE with all constraint types
CREATE TABLE Sales.Customers (
    CustomerID INT IDENTITY(1,1) NOT NULL,
    CustomerCode AS ('CUST-' + RIGHT('00000' + CAST(CustomerID AS VARCHAR(5)), 5)) PERSISTED,
    FirstName NVARCHAR(50) NOT NULL,
    LastName NVARCHAR(50) NOT NULL,
    Email NVARCHAR(200) NOT NULL,
    Phone VARCHAR(20) NULL,
    DateOfBirth DATE NULL,
    CreditLimit DECIMAL(18,2) DEFAULT 1000.00,
    IsActive BIT NOT NULL DEFAULT 1,
    CreatedAt DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    ModifiedAt DATETIME2 NULL,
    RowVersion ROWVERSION,
    
    CONSTRAINT PK_Customers PRIMARY KEY CLUSTERED (CustomerID),
    CONSTRAINT UQ_Customers_Email UNIQUE (Email),
    CONSTRAINT UQ_Customers_Code UNIQUE (CustomerCode),
    CONSTRAINT CK_Customers_Email CHECK (Email LIKE '%@%.%'),
    CONSTRAINT CK_Customers_CreditLimit CHECK (CreditLimit >= 0 AND CreditLimit <= 1000000),
    CONSTRAINT CK_Customers_DOB CHECK (DateOfBirth < GETDATE())
);
GO

-- Pattern 3: CREATE TABLE with foreign keys
CREATE TABLE Sales.Orders (
    OrderID INT IDENTITY(1,1) NOT NULL,
    CustomerID INT NOT NULL,
    OrderDate DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    RequiredDate DATE NULL,
    ShippedDate DATE NULL,
    Status VARCHAR(20) NOT NULL DEFAULT 'Pending',
    TotalAmount DECIMAL(18,2) NOT NULL DEFAULT 0,
    Notes NVARCHAR(MAX) NULL,
    
    CONSTRAINT PK_Orders PRIMARY KEY CLUSTERED (OrderID),
    CONSTRAINT FK_Orders_Customers FOREIGN KEY (CustomerID) 
        REFERENCES Sales.Customers(CustomerID)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT CK_Orders_Status CHECK (Status IN ('Pending', 'Processing', 'Shipped', 'Delivered', 'Cancelled')),
    CONSTRAINT CK_Orders_Dates CHECK (ShippedDate IS NULL OR ShippedDate >= OrderDate)
);
GO

-- Pattern 4: CREATE TABLE with composite primary key
CREATE TABLE Sales.OrderDetails (
    OrderID INT NOT NULL,
    LineNumber INT NOT NULL,
    ProductID INT NOT NULL,
    Quantity INT NOT NULL DEFAULT 1,
    UnitPrice DECIMAL(18,2) NOT NULL,
    Discount DECIMAL(5,2) NOT NULL DEFAULT 0,
    LineTotal AS (Quantity * UnitPrice * (1 - Discount/100)) PERSISTED,
    
    CONSTRAINT PK_OrderDetails PRIMARY KEY CLUSTERED (OrderID, LineNumber),
    CONSTRAINT FK_OrderDetails_Orders FOREIGN KEY (OrderID) REFERENCES Sales.Orders(OrderID) ON DELETE CASCADE,
    CONSTRAINT CK_OrderDetails_Quantity CHECK (Quantity > 0),
    CONSTRAINT CK_OrderDetails_Discount CHECK (Discount >= 0 AND Discount <= 100)
);
GO

-- Pattern 5: CREATE INDEX variations
CREATE NONCLUSTERED INDEX IX_Customers_LastName ON Sales.Customers(LastName);

CREATE NONCLUSTERED INDEX IX_Customers_Name ON Sales.Customers(LastName, FirstName) 
    INCLUDE (Email, Phone);

CREATE UNIQUE NONCLUSTERED INDEX IX_Customers_Email ON Sales.Customers(Email) 
    WHERE IsActive = 1;

CREATE NONCLUSTERED INDEX IX_Orders_CustomerID ON Sales.Orders(CustomerID) 
    INCLUDE (OrderDate, TotalAmount)
    WITH (FILLFACTOR = 80, PAD_INDEX = ON);

CREATE NONCLUSTERED INDEX IX_Orders_Date ON Sales.Orders(OrderDate DESC) 
    INCLUDE (CustomerID, Status, TotalAmount);
GO

-- Pattern 6: CREATE VIEW
CREATE VIEW Sales.vw_CustomerOrders
WITH SCHEMABINDING
AS
SELECT 
    c.CustomerID,
    c.FirstName + ' ' + c.LastName AS CustomerName,
    c.Email,
    o.OrderID,
    o.OrderDate,
    o.Status,
    o.TotalAmount
FROM Sales.Customers c
INNER JOIN Sales.Orders o ON c.CustomerID = o.CustomerID
WHERE c.IsActive = 1;
GO

-- Pattern 7: CREATE VIEW with CHECK OPTION
CREATE VIEW Sales.vw_ActiveCustomers
AS
SELECT CustomerID, FirstName, LastName, Email, Phone
FROM Sales.Customers
WHERE IsActive = 1
WITH CHECK OPTION;
GO

-- Pattern 8: CREATE FUNCTION (scalar)
CREATE FUNCTION Sales.fn_GetCustomerOrderTotal(@CustomerID INT)
RETURNS DECIMAL(18,2)
AS
BEGIN
    DECLARE @Total DECIMAL(18,2);
    SELECT @Total = SUM(TotalAmount) FROM Sales.Orders WHERE CustomerID = @CustomerID;
    RETURN ISNULL(@Total, 0);
END;
GO

-- Pattern 9: CREATE FUNCTION (inline table-valued)
CREATE FUNCTION Sales.fn_GetCustomerOrders(@CustomerID INT)
RETURNS TABLE
AS
RETURN (
    SELECT OrderID, OrderDate, Status, TotalAmount
    FROM Sales.Orders
    WHERE CustomerID = @CustomerID
);
GO

-- Pattern 10: CREATE FUNCTION (multi-statement table-valued)
CREATE FUNCTION Sales.fn_GetTopCustomers(@TopN INT)
RETURNS @Results TABLE (
    CustomerID INT,
    CustomerName NVARCHAR(101),
    TotalOrders INT,
    TotalSpent DECIMAL(18,2)
)
AS
BEGIN
    INSERT INTO @Results
    SELECT TOP (@TopN)
        c.CustomerID,
        c.FirstName + ' ' + c.LastName,
        COUNT(o.OrderID),
        SUM(o.TotalAmount)
    FROM Sales.Customers c
    LEFT JOIN Sales.Orders o ON c.CustomerID = o.CustomerID
    GROUP BY c.CustomerID, c.FirstName, c.LastName
    ORDER BY SUM(o.TotalAmount) DESC;
    
    RETURN;
END;
GO

-- Pattern 11: CREATE TRIGGER (AFTER)
CREATE TRIGGER Sales.trg_Orders_UpdateTotal
ON Sales.OrderDetails
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    
    UPDATE o
    SET TotalAmount = (
        SELECT ISNULL(SUM(LineTotal), 0)
        FROM Sales.OrderDetails od
        WHERE od.OrderID = o.OrderID
    )
    FROM Sales.Orders o
    WHERE o.OrderID IN (
        SELECT OrderID FROM inserted
        UNION
        SELECT OrderID FROM deleted
    );
END;
GO

-- Pattern 12: CREATE TRIGGER (INSTEAD OF)
CREATE TRIGGER Sales.trg_Customers_Delete
ON Sales.Customers
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;
    -- Soft delete instead of hard delete
    UPDATE c
    SET IsActive = 0, ModifiedAt = SYSDATETIME()
    FROM Sales.Customers c
    INNER JOIN deleted d ON c.CustomerID = d.CustomerID;
END;
GO

-- Pattern 13: CREATE SEQUENCE
CREATE SEQUENCE Sales.OrderNumberSequence
    AS INT
    START WITH 10000
    INCREMENT BY 1
    MINVALUE 10000
    MAXVALUE 99999
    CYCLE
    CACHE 100;
GO

-- Pattern 14: CREATE SYNONYM
CREATE SYNONYM dbo.Customers FOR Sales.Customers;
CREATE SYNONYM dbo.Orders FOR Sales.Orders;
GO

-- Pattern 15: CREATE TYPE (table type)
CREATE TYPE Sales.OrderDetailsType AS TABLE (
    ProductID INT NOT NULL,
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(18,2) NOT NULL,
    Discount DECIMAL(5,2) NOT NULL DEFAULT 0
);
GO

-- Pattern 16: CREATE DEFAULT (deprecated but valid)
CREATE DEFAULT dbo.DefaultZero AS 0;
GO

-- Pattern 17: CREATE RULE (deprecated but valid)
CREATE RULE dbo.RulePositive AS @value > 0;
GO

-- Pattern 18: ALTER TABLE examples
ALTER TABLE Sales.Customers ADD MiddleName NVARCHAR(50) NULL;

ALTER TABLE Sales.Customers ALTER COLUMN Phone VARCHAR(30);

ALTER TABLE Sales.Customers DROP COLUMN MiddleName;

ALTER TABLE Sales.Customers ADD CONSTRAINT DF_Customers_CreatedAt DEFAULT SYSDATETIME() FOR CreatedAt;

ALTER TABLE Sales.Customers DROP CONSTRAINT CK_Customers_DOB;

ALTER TABLE Sales.Customers WITH CHECK ADD CONSTRAINT CK_Customers_DOB 
    CHECK (DateOfBirth <= DATEADD(YEAR, -18, GETDATE()));
GO

-- Pattern 19: ALTER INDEX
ALTER INDEX IX_Customers_LastName ON Sales.Customers REBUILD;
ALTER INDEX IX_Customers_LastName ON Sales.Customers REORGANIZE;
ALTER INDEX IX_Customers_LastName ON Sales.Customers DISABLE;
ALTER INDEX IX_Customers_LastName ON Sales.Customers REBUILD WITH (ONLINE = ON);
GO

-- Pattern 20: DROP statements
DROP SYNONYM IF EXISTS dbo.Orders;
DROP SYNONYM IF EXISTS dbo.Customers;
DROP FUNCTION IF EXISTS Sales.fn_GetTopCustomers;
DROP FUNCTION IF EXISTS Sales.fn_GetCustomerOrders;
DROP FUNCTION IF EXISTS Sales.fn_GetCustomerOrderTotal;
DROP VIEW IF EXISTS Sales.vw_ActiveCustomers;
DROP VIEW IF EXISTS Sales.vw_CustomerOrders;
DROP TRIGGER IF EXISTS Sales.trg_Customers_Delete;
DROP TRIGGER IF EXISTS Sales.trg_Orders_UpdateTotal;
DROP TABLE IF EXISTS Sales.OrderDetails;
DROP TABLE IF EXISTS Sales.Orders;
DROP TABLE IF EXISTS Sales.Customers;
DROP SEQUENCE IF EXISTS Sales.OrderNumberSequence;
DROP TYPE IF EXISTS Sales.OrderDetailsType;
DROP SCHEMA IF EXISTS Sales;
DROP SCHEMA IF EXISTS HR;
DROP DEFAULT IF EXISTS dbo.DefaultZero;
DROP RULE IF EXISTS dbo.RulePositive;
GO
