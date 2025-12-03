-- Sample 178: View Creation Patterns
-- Category: DDL / Syntax Coverage
-- Complexity: Complex
-- Purpose: Parser testing - CREATE VIEW syntax variations
-- Features: Options, indexed views, partitioned views

-- Pattern 1: Basic view
CREATE VIEW dbo.ActiveCustomers
AS
    SELECT CustomerID, CustomerName, Email
    FROM dbo.Customers
    WHERE IsActive = 1;
GO
DROP VIEW dbo.ActiveCustomers;
GO

-- Pattern 2: View with column list
CREATE VIEW dbo.CustomerInfo (ID, FullName, ContactEmail)
AS
    SELECT CustomerID, CustomerName, Email
    FROM dbo.Customers;
GO
DROP VIEW dbo.CustomerInfo;
GO

-- Pattern 3: View with computed columns
CREATE VIEW dbo.ProductStats
AS
    SELECT 
        ProductID,
        ProductName,
        Price,
        StockQuantity,
        Price * StockQuantity AS InventoryValue,
        CASE WHEN StockQuantity > 100 THEN 'High' 
             WHEN StockQuantity > 20 THEN 'Medium' 
             ELSE 'Low' END AS StockLevel
    FROM dbo.Products;
GO
DROP VIEW dbo.ProductStats;
GO

-- Pattern 4: View with JOINs
CREATE VIEW dbo.OrderDetails
AS
    SELECT 
        o.OrderID,
        o.OrderDate,
        c.CustomerName,
        c.Email,
        o.TotalAmount,
        o.Status
    FROM dbo.Orders o
    INNER JOIN dbo.Customers c ON o.CustomerID = c.CustomerID;
GO
DROP VIEW dbo.OrderDetails;
GO

-- Pattern 5: View with multiple JOINs
CREATE VIEW dbo.FullOrderDetails
AS
    SELECT 
        o.OrderID,
        o.OrderDate,
        c.CustomerName,
        p.ProductName,
        od.Quantity,
        od.UnitPrice,
        od.Quantity * od.UnitPrice AS LineTotal
    FROM dbo.Orders o
    INNER JOIN dbo.Customers c ON o.CustomerID = c.CustomerID
    INNER JOIN dbo.OrderDetails od ON o.OrderID = od.OrderID
    INNER JOIN dbo.Products p ON od.ProductID = p.ProductID;
GO
DROP VIEW dbo.FullOrderDetails;
GO

-- Pattern 6: View with aggregation
CREATE VIEW dbo.CustomerOrderSummary
AS
    SELECT 
        c.CustomerID,
        c.CustomerName,
        COUNT(o.OrderID) AS TotalOrders,
        ISNULL(SUM(o.TotalAmount), 0) AS TotalSpent,
        MAX(o.OrderDate) AS LastOrderDate
    FROM dbo.Customers c
    LEFT JOIN dbo.Orders o ON c.CustomerID = o.CustomerID
    GROUP BY c.CustomerID, c.CustomerName;
GO
DROP VIEW dbo.CustomerOrderSummary;
GO

-- Pattern 7: View WITH SCHEMABINDING
CREATE VIEW dbo.SchemaBoundView
WITH SCHEMABINDING
AS
    SELECT CustomerID, CustomerName, Email
    FROM dbo.Customers
    WHERE IsActive = 1;
GO
DROP VIEW dbo.SchemaBoundView;
GO

-- Pattern 8: View WITH ENCRYPTION
CREATE VIEW dbo.EncryptedView
WITH ENCRYPTION
AS
    SELECT CustomerID, CustomerName
    FROM dbo.Customers;
GO
DROP VIEW dbo.EncryptedView;
GO

-- Pattern 9: View WITH VIEW_METADATA
CREATE VIEW dbo.MetadataView
WITH VIEW_METADATA
AS
    SELECT CustomerID, CustomerName, Email
    FROM dbo.Customers;
GO
DROP VIEW dbo.MetadataView;
GO

-- Pattern 10: View with multiple options
CREATE VIEW dbo.MultiOptionView
WITH SCHEMABINDING, VIEW_METADATA
AS
    SELECT CustomerID, CustomerName
    FROM dbo.Customers;
GO
DROP VIEW dbo.MultiOptionView;
GO

-- Pattern 11: View WITH CHECK OPTION
CREATE VIEW dbo.ActiveCustomersOnly
AS
    SELECT CustomerID, CustomerName, Email, IsActive
    FROM dbo.Customers
    WHERE IsActive = 1
WITH CHECK OPTION;
GO
DROP VIEW dbo.ActiveCustomersOnly;
GO

-- Pattern 12: Indexed view (materialized)
CREATE VIEW dbo.IndexedOrderSummary
WITH SCHEMABINDING
AS
    SELECT 
        o.CustomerID,
        COUNT_BIG(*) AS OrderCount,
        SUM(o.TotalAmount) AS TotalSpent
    FROM dbo.Orders o
    GROUP BY o.CustomerID;
GO

CREATE UNIQUE CLUSTERED INDEX IX_IndexedOrderSummary
ON dbo.IndexedOrderSummary (CustomerID);
GO

DROP VIEW dbo.IndexedOrderSummary;
GO

-- Pattern 13: View with CTE
CREATE VIEW dbo.RankedProducts
AS
    WITH ProductRanking AS (
        SELECT 
            ProductID,
            ProductName,
            CategoryID,
            Price,
            ROW_NUMBER() OVER (PARTITION BY CategoryID ORDER BY Price DESC) AS PriceRank
        FROM dbo.Products
    )
    SELECT *
    FROM ProductRanking
    WHERE PriceRank <= 5;
GO
DROP VIEW dbo.RankedProducts;
GO

-- Pattern 14: View with UNION
CREATE VIEW dbo.AllContacts
AS
    SELECT CustomerID AS ID, CustomerName AS Name, 'Customer' AS ContactType
    FROM dbo.Customers
    UNION ALL
    SELECT SupplierID, SupplierName, 'Supplier'
    FROM dbo.Suppliers
    UNION ALL
    SELECT EmployeeID, EmployeeName, 'Employee'
    FROM dbo.Employees;
GO
DROP VIEW dbo.AllContacts;
GO

-- Pattern 15: View with subquery
CREATE VIEW dbo.CustomersWithOrders
AS
    SELECT 
        c.CustomerID,
        c.CustomerName,
        (SELECT COUNT(*) FROM dbo.Orders o WHERE o.CustomerID = c.CustomerID) AS OrderCount,
        (SELECT MAX(OrderDate) FROM dbo.Orders o WHERE o.CustomerID = c.CustomerID) AS LastOrder
    FROM dbo.Customers c;
GO
DROP VIEW dbo.CustomersWithOrders;
GO

-- Pattern 16: View with APPLY
CREATE VIEW dbo.CustomersWithRecentOrders
AS
    SELECT 
        c.CustomerID,
        c.CustomerName,
        recent.OrderID,
        recent.OrderDate
    FROM dbo.Customers c
    CROSS APPLY (
        SELECT TOP 3 OrderID, OrderDate
        FROM dbo.Orders o
        WHERE o.CustomerID = c.CustomerID
        ORDER BY OrderDate DESC
    ) AS recent;
GO
DROP VIEW dbo.CustomersWithRecentOrders;
GO

-- Pattern 17: View with window functions
CREATE VIEW dbo.OrdersWithRunningTotal
AS
    SELECT 
        OrderID,
        CustomerID,
        OrderDate,
        TotalAmount,
        SUM(TotalAmount) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS RunningTotal,
        ROW_NUMBER() OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS OrderSequence
    FROM dbo.Orders;
GO
DROP VIEW dbo.OrdersWithRunningTotal;
GO

-- Pattern 18: Partitioned view (local)
CREATE VIEW dbo.AllOrders
AS
    SELECT * FROM dbo.Orders_2022
    UNION ALL
    SELECT * FROM dbo.Orders_2023
    UNION ALL
    SELECT * FROM dbo.Orders_2024;
GO
DROP VIEW dbo.AllOrders;
GO

-- Pattern 19: View referencing another view
CREATE VIEW dbo.BaseView
AS
    SELECT CustomerID, CustomerName FROM dbo.Customers;
GO

CREATE VIEW dbo.DerivedView
AS
    SELECT bv.CustomerID, bv.CustomerName, COUNT(o.OrderID) AS Orders
    FROM dbo.BaseView bv
    LEFT JOIN dbo.Orders o ON bv.CustomerID = o.CustomerID
    GROUP BY bv.CustomerID, bv.CustomerName;
GO

DROP VIEW dbo.DerivedView;
DROP VIEW dbo.BaseView;
GO

-- Pattern 20: ALTER VIEW
CREATE VIEW dbo.ToBeAltered AS SELECT 1 AS Col;
GO

ALTER VIEW dbo.ToBeAltered
AS
    SELECT CustomerID, CustomerName
    FROM dbo.Customers;
GO

DROP VIEW dbo.ToBeAltered;
GO

-- Pattern 21: View with PIVOT
CREATE VIEW dbo.MonthlySalesPivot
AS
    SELECT *
    FROM (
        SELECT 
            CustomerID,
            MONTH(OrderDate) AS OrderMonth,
            TotalAmount
        FROM dbo.Orders
        WHERE YEAR(OrderDate) = 2024
    ) AS src
    PIVOT (
        SUM(TotalAmount)
        FOR OrderMonth IN ([1],[2],[3],[4],[5],[6],[7],[8],[9],[10],[11],[12])
    ) AS pvt;
GO
DROP VIEW dbo.MonthlySalesPivot;
GO

-- Pattern 22: View with JSON
CREATE VIEW dbo.CustomerJSON
AS
    SELECT 
        CustomerID,
        (SELECT CustomerName, Email, Phone FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS CustomerData
    FROM dbo.Customers;
GO
DROP VIEW dbo.CustomerJSON;
GO
