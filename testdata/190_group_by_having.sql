-- Sample 190: GROUP BY and HAVING Patterns
-- Category: Syntax Coverage / Query Patterns
-- Complexity: Complex
-- Purpose: Parser testing - GROUP BY and HAVING syntax
-- Features: GROUP BY, HAVING, GROUPING SETS, CUBE, ROLLUP

-- Pattern 1: Basic GROUP BY
SELECT CategoryID, COUNT(*) AS ProductCount
FROM dbo.Products
GROUP BY CategoryID;
GO

-- Pattern 2: GROUP BY with multiple columns
SELECT CategoryID, SupplierID, COUNT(*) AS ProductCount
FROM dbo.Products
GROUP BY CategoryID, SupplierID;
GO

-- Pattern 3: GROUP BY with aggregates
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

-- Pattern 4: GROUP BY with expression
SELECT 
    YEAR(OrderDate) AS OrderYear,
    MONTH(OrderDate) AS OrderMonth,
    COUNT(*) AS OrderCount,
    SUM(TotalAmount) AS TotalSales
FROM dbo.Orders
GROUP BY YEAR(OrderDate), MONTH(OrderDate);
GO

-- Pattern 5: GROUP BY with CASE
SELECT 
    CASE 
        WHEN Price < 10 THEN 'Budget'
        WHEN Price < 50 THEN 'Standard'
        WHEN Price < 100 THEN 'Premium'
        ELSE 'Luxury'
    END AS PriceCategory,
    COUNT(*) AS ProductCount
FROM dbo.Products
GROUP BY 
    CASE 
        WHEN Price < 10 THEN 'Budget'
        WHEN Price < 50 THEN 'Standard'
        WHEN Price < 100 THEN 'Premium'
        ELSE 'Luxury'
    END;
GO

-- Pattern 6: Basic HAVING
SELECT CategoryID, COUNT(*) AS ProductCount
FROM dbo.Products
GROUP BY CategoryID
HAVING COUNT(*) > 10;
GO

-- Pattern 7: HAVING with multiple conditions
SELECT 
    CustomerID,
    COUNT(*) AS OrderCount,
    SUM(TotalAmount) AS TotalSpent
FROM dbo.Orders
GROUP BY CustomerID
HAVING COUNT(*) >= 5 AND SUM(TotalAmount) > 1000;
GO

-- Pattern 8: HAVING with subquery
SELECT CategoryID, AVG(Price) AS AvgPrice
FROM dbo.Products
GROUP BY CategoryID
HAVING AVG(Price) > (SELECT AVG(Price) FROM dbo.Products);
GO

-- Pattern 9: WHERE and HAVING combined
SELECT 
    CategoryID,
    COUNT(*) AS ActiveProductCount,
    AVG(Price) AS AvgPrice
FROM dbo.Products
WHERE IsActive = 1
GROUP BY CategoryID
HAVING COUNT(*) >= 3 AND AVG(Price) < 100;
GO

-- Pattern 10: GROUP BY ALL (deprecated but parseable)
-- SELECT CategoryID, COUNT(*) FROM dbo.Products GROUP BY ALL CategoryID;
GO

-- Pattern 11: GROUPING SETS
SELECT 
    CategoryID,
    SupplierID,
    COUNT(*) AS ProductCount,
    SUM(Price) AS TotalPrice
FROM dbo.Products
GROUP BY GROUPING SETS (
    (CategoryID, SupplierID),
    (CategoryID),
    (SupplierID),
    ()
);
GO

-- Pattern 12: GROUPING SETS with single sets
SELECT 
    YEAR(OrderDate) AS Year,
    MONTH(OrderDate) AS Month,
    SUM(TotalAmount) AS Sales
FROM dbo.Orders
GROUP BY GROUPING SETS (
    (YEAR(OrderDate)),
    (YEAR(OrderDate), MONTH(OrderDate))
);
GO

-- Pattern 13: CUBE
SELECT 
    CategoryID,
    SupplierID,
    COUNT(*) AS ProductCount
FROM dbo.Products
GROUP BY CUBE (CategoryID, SupplierID);
GO

-- Pattern 14: ROLLUP
SELECT 
    YEAR(OrderDate) AS Year,
    MONTH(OrderDate) AS Month,
    DAY(OrderDate) AS Day,
    COUNT(*) AS OrderCount,
    SUM(TotalAmount) AS TotalSales
FROM dbo.Orders
GROUP BY ROLLUP (YEAR(OrderDate), MONTH(OrderDate), DAY(OrderDate));
GO

-- Pattern 15: GROUPING function
SELECT 
    CategoryID,
    SupplierID,
    COUNT(*) AS ProductCount,
    GROUPING(CategoryID) AS IsCategoryTotal,
    GROUPING(SupplierID) AS IsSupplierTotal
FROM dbo.Products
GROUP BY ROLLUP (CategoryID, SupplierID);
GO

-- Pattern 16: GROUPING_ID function
SELECT 
    CategoryID,
    SupplierID,
    COUNT(*) AS ProductCount,
    GROUPING_ID(CategoryID, SupplierID) AS GroupLevel
FROM dbo.Products
GROUP BY CUBE (CategoryID, SupplierID);
GO

-- Pattern 17: Using GROUPING for labels
SELECT 
    CASE GROUPING(CategoryID) 
        WHEN 1 THEN 'All Categories' 
        ELSE CAST(CategoryID AS VARCHAR(10)) 
    END AS Category,
    CASE GROUPING(SupplierID) 
        WHEN 1 THEN 'All Suppliers' 
        ELSE CAST(SupplierID AS VARCHAR(10)) 
    END AS Supplier,
    COUNT(*) AS ProductCount
FROM dbo.Products
GROUP BY ROLLUP (CategoryID, SupplierID);
GO

-- Pattern 18: Combining CUBE and ROLLUP
SELECT 
    Region,
    Category,
    Product,
    SUM(Sales) AS TotalSales
FROM dbo.SalesData
GROUP BY 
    Region,
    ROLLUP (Category, Product);
GO

-- Pattern 19: GROUP BY with JOIN
SELECT 
    c.CategoryName,
    COUNT(p.ProductID) AS ProductCount,
    AVG(p.Price) AS AvgPrice
FROM dbo.Categories c
LEFT JOIN dbo.Products p ON c.CategoryID = p.CategoryID
GROUP BY c.CategoryID, c.CategoryName;
GO

-- Pattern 20: GROUP BY with subquery in SELECT
SELECT 
    c.CategoryID,
    COUNT(*) AS ProductCount,
    (SELECT SUM(od.Quantity) 
     FROM dbo.OrderDetails od 
     INNER JOIN dbo.Products p ON od.ProductID = p.ProductID 
     WHERE p.CategoryID = c.CategoryID) AS TotalQuantitySold
FROM dbo.Products c
GROUP BY c.CategoryID;
GO

-- Pattern 21: GROUP BY with DISTINCT aggregate
SELECT 
    CategoryID,
    COUNT(DISTINCT SupplierID) AS UniqueSuppliers,
    COUNT(*) AS TotalProducts
FROM dbo.Products
GROUP BY CategoryID;
GO

-- Pattern 22: HAVING with aggregate comparison
SELECT 
    c.CustomerID,
    c.CustomerName,
    COUNT(o.OrderID) AS OrderCount
FROM dbo.Customers c
LEFT JOIN dbo.Orders o ON c.CustomerID = o.CustomerID
GROUP BY c.CustomerID, c.CustomerName
HAVING COUNT(o.OrderID) > AVG(COUNT(o.OrderID)) OVER ();
-- Note: This specific syntax may need adjustment
GO

-- Pattern 23: Empty GROUP BY (entire table as one group)
SELECT 
    COUNT(*) AS TotalProducts,
    AVG(Price) AS AvgPrice,
    SUM(StockQuantity) AS TotalStock
FROM dbo.Products;
-- Implicit GROUP BY of entire result set
GO
