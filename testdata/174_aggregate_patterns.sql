-- Sample 174: Aggregate Function Patterns
-- Category: Syntax Coverage / Pure Logic
-- Complexity: Complex
-- Purpose: Parser testing - aggregate function syntax
-- Features: All aggregate functions, DISTINCT, FILTER, grouping

-- Pattern 1: Basic aggregate functions
SELECT 
    COUNT(*) AS TotalRows,
    COUNT(Email) AS EmailCount,
    COUNT(DISTINCT Email) AS UniqueEmails,
    SUM(TotalAmount) AS TotalSum,
    AVG(TotalAmount) AS Average,
    MIN(TotalAmount) AS Minimum,
    MAX(TotalAmount) AS Maximum
FROM dbo.Orders;
GO

-- Pattern 2: COUNT variations
SELECT 
    COUNT(*) AS CountAll,
    COUNT(1) AS CountOne,
    COUNT(CustomerID) AS CountColumn,
    COUNT(DISTINCT CustomerID) AS CountDistinct,
    COUNT(DISTINCT CASE WHEN TotalAmount > 100 THEN CustomerID END) AS CountDistinctFiltered,
    COUNT_BIG(*) AS CountBig
FROM dbo.Orders;
GO

-- Pattern 3: SUM with expressions
SELECT 
    SUM(Quantity) AS TotalQty,
    SUM(Quantity * UnitPrice) AS TotalValue,
    SUM(Quantity * UnitPrice * (1 - Discount)) AS DiscountedValue,
    SUM(DISTINCT CategoryID) AS DistinctCategorySum,
    SUM(CASE WHEN Quantity > 10 THEN Quantity ELSE 0 END) AS LargeOrderQty
FROM dbo.OrderDetails;
GO

-- Pattern 4: AVG with different types
SELECT 
    AVG(Price) AS AvgPrice,
    AVG(CAST(Price AS FLOAT)) AS AvgPriceFloat,
    AVG(Price * 1.0) AS AvgPriceDecimal,
    AVG(DISTINCT Price) AS AvgDistinctPrice,
    AVG(CASE WHEN StockQuantity > 0 THEN Price END) AS AvgInStockPrice
FROM dbo.Products;
GO

-- Pattern 5: MIN and MAX with different types
SELECT 
    MIN(Price) AS MinPrice,
    MAX(Price) AS MaxPrice,
    MIN(ProductName) AS FirstProduct,
    MAX(ProductName) AS LastProduct,
    MIN(CreatedDate) AS OldestRecord,
    MAX(CreatedDate) AS NewestRecord
FROM dbo.Products;
GO

-- Pattern 6: Statistical aggregates
SELECT 
    STDEV(Price) AS StandardDeviation,
    STDEVP(Price) AS PopulationStdDev,
    VAR(Price) AS Variance,
    VARP(Price) AS PopulationVariance
FROM dbo.Products;
GO

-- Pattern 7: STRING_AGG
SELECT 
    CustomerID,
    STRING_AGG(ProductName, ', ') AS Products,
    STRING_AGG(ProductName, ', ') WITHIN GROUP (ORDER BY ProductName) AS ProductsSorted
FROM dbo.Orders o
INNER JOIN dbo.OrderDetails od ON o.OrderID = od.OrderID
INNER JOIN dbo.Products p ON od.ProductID = p.ProductID
GROUP BY CustomerID;
GO

-- Pattern 8: CHECKSUM_AGG
SELECT 
    CategoryID,
    CHECKSUM_AGG(ProductID) AS ProductChecksum,
    CHECKSUM_AGG(BINARY_CHECKSUM(*)) AS RowChecksum
FROM dbo.Products
GROUP BY CategoryID;
GO

-- Pattern 9: Aggregates with GROUP BY
SELECT 
    CategoryID,
    COUNT(*) AS ProductCount,
    SUM(StockQuantity) AS TotalStock,
    AVG(Price) AS AvgPrice,
    MIN(Price) AS MinPrice,
    MAX(Price) AS MaxPrice
FROM dbo.Products
GROUP BY CategoryID;
GO

-- Pattern 10: Aggregates with multiple GROUP BY columns
SELECT 
    YEAR(OrderDate) AS Year,
    MONTH(OrderDate) AS Month,
    CustomerID,
    COUNT(*) AS OrderCount,
    SUM(TotalAmount) AS TotalSales
FROM dbo.Orders
GROUP BY YEAR(OrderDate), MONTH(OrderDate), CustomerID;
GO

-- Pattern 11: GROUP BY with expressions
SELECT 
    CASE WHEN Price < 10 THEN 'Low' WHEN Price < 50 THEN 'Medium' ELSE 'High' END AS PriceRange,
    COUNT(*) AS ProductCount,
    AVG(Price) AS AvgPrice
FROM dbo.Products
GROUP BY CASE WHEN Price < 10 THEN 'Low' WHEN Price < 50 THEN 'Medium' ELSE 'High' END;
GO

-- Pattern 12: HAVING clause
SELECT 
    CustomerID,
    COUNT(*) AS OrderCount,
    SUM(TotalAmount) AS TotalSpent
FROM dbo.Orders
GROUP BY CustomerID
HAVING COUNT(*) >= 5 AND SUM(TotalAmount) > 1000;
GO

-- Pattern 13: HAVING with aggregate comparison
SELECT 
    CategoryID,
    AVG(Price) AS AvgPrice
FROM dbo.Products
GROUP BY CategoryID
HAVING AVG(Price) > (SELECT AVG(Price) FROM dbo.Products);
GO

-- Pattern 14: GROUPING SETS
SELECT 
    CategoryID,
    SupplierID,
    COUNT(*) AS ProductCount,
    SUM(StockQuantity) AS TotalStock
FROM dbo.Products
GROUP BY GROUPING SETS (
    (CategoryID, SupplierID),
    (CategoryID),
    (SupplierID),
    ()
);
GO

-- Pattern 15: CUBE
SELECT 
    CategoryID,
    SupplierID,
    COUNT(*) AS ProductCount,
    SUM(Price) AS TotalPrice
FROM dbo.Products
GROUP BY CUBE (CategoryID, SupplierID);
GO

-- Pattern 16: ROLLUP
SELECT 
    YEAR(OrderDate) AS Year,
    MONTH(OrderDate) AS Month,
    COUNT(*) AS OrderCount,
    SUM(TotalAmount) AS TotalSales
FROM dbo.Orders
GROUP BY ROLLUP (YEAR(OrderDate), MONTH(OrderDate));
GO

-- Pattern 17: GROUPING function
SELECT 
    CategoryID,
    SupplierID,
    COUNT(*) AS ProductCount,
    GROUPING(CategoryID) AS IsCategoryTotal,
    GROUPING(SupplierID) AS IsSupplierTotal
FROM dbo.Products
GROUP BY CUBE (CategoryID, SupplierID);
GO

-- Pattern 18: GROUPING_ID function
SELECT 
    CategoryID,
    SupplierID,
    COUNT(*) AS ProductCount,
    GROUPING_ID(CategoryID, SupplierID) AS GroupingLevel
FROM dbo.Products
GROUP BY CUBE (CategoryID, SupplierID);
GO

-- Pattern 19: Conditional aggregation
SELECT 
    COUNT(CASE WHEN Status = 'Pending' THEN 1 END) AS PendingCount,
    COUNT(CASE WHEN Status = 'Shipped' THEN 1 END) AS ShippedCount,
    COUNT(CASE WHEN Status = 'Delivered' THEN 1 END) AS DeliveredCount,
    SUM(CASE WHEN Status = 'Shipped' THEN TotalAmount ELSE 0 END) AS ShippedAmount,
    AVG(CASE WHEN TotalAmount > 100 THEN TotalAmount END) AS AvgLargeOrder
FROM dbo.Orders;
GO

-- Pattern 20: Aggregates as window functions
SELECT 
    OrderID,
    CustomerID,
    TotalAmount,
    COUNT(*) OVER () AS TotalOrders,
    SUM(TotalAmount) OVER () AS GrandTotal,
    AVG(TotalAmount) OVER (PARTITION BY CustomerID) AS CustomerAvg,
    SUM(TotalAmount) OVER (ORDER BY OrderDate) AS RunningTotal
FROM dbo.Orders;
GO

-- Pattern 21: APPROX_COUNT_DISTINCT (SQL Server 2019+)
SELECT 
    APPROX_COUNT_DISTINCT(CustomerID) AS ApproxDistinctCustomers
FROM dbo.Orders;
GO

-- Pattern 22: Aggregate with OVER and frame
SELECT 
    OrderID,
    OrderDate,
    TotalAmount,
    SUM(TotalAmount) OVER (ORDER BY OrderDate ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS Week7DayTotal,
    AVG(TotalAmount) OVER (ORDER BY OrderDate ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) AS MovingAvg5
FROM dbo.Orders;
GO

-- Pattern 23: Multiple aggregates in subquery
SELECT 
    c.CustomerID,
    c.CustomerName,
    stats.OrderCount,
    stats.TotalSpent,
    stats.AvgOrder,
    stats.FirstOrder,
    stats.LastOrder
FROM dbo.Customers c
INNER JOIN (
    SELECT 
        CustomerID,
        COUNT(*) AS OrderCount,
        SUM(TotalAmount) AS TotalSpent,
        AVG(TotalAmount) AS AvgOrder,
        MIN(OrderDate) AS FirstOrder,
        MAX(OrderDate) AS LastOrder
    FROM dbo.Orders
    GROUP BY CustomerID
) AS stats ON c.CustomerID = stats.CustomerID;
GO

-- Pattern 24: Aggregate with ALL (no grouping)
SELECT 
    COUNT(*) AS TotalProducts,
    SUM(Price * StockQuantity) AS TotalInventoryValue
FROM dbo.Products;  -- Implicit GROUP BY ALL
GO
