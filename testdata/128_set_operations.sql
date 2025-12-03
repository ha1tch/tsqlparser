-- Sample 128: Complex Set Operations
-- Category: Set Operations and Advanced Predicates
-- Complexity: Complex
-- Purpose: Parser testing - advanced set operation patterns
-- Features: UNION, UNION ALL, INTERSECT, EXCEPT, chained operations, ORDER BY

-- Pattern 1: Basic UNION (removes duplicates)
SELECT CustomerID, CustomerName, 'Active' AS Status FROM Customers WHERE IsActive = 1
UNION
SELECT CustomerID, CustomerName, 'Inactive' AS Status FROM Customers WHERE IsActive = 0;
GO

-- Pattern 2: UNION ALL (keeps duplicates)
SELECT ProductID, ProductName FROM Products WHERE CategoryID = 1
UNION ALL
SELECT ProductID, ProductName FROM Products WHERE CategoryID = 2
UNION ALL
SELECT ProductID, ProductName FROM Products WHERE CategoryID = 3;
GO

-- Pattern 3: INTERSECT (common rows)
SELECT CustomerID FROM Customers WHERE Region = 'North'
INTERSECT
SELECT CustomerID FROM Orders WHERE YEAR(OrderDate) = 2024;
-- Customers in North who ordered in 2024
GO

-- Pattern 4: EXCEPT (rows in first but not second)
SELECT CustomerID FROM Customers WHERE IsActive = 1
EXCEPT
SELECT CustomerID FROM Orders WHERE YEAR(OrderDate) = 2024;
-- Active customers who didn't order in 2024
GO

-- Pattern 5: Chained set operations (left to right evaluation)
SELECT ProductID FROM Products WHERE CategoryID = 1
UNION
SELECT ProductID FROM Products WHERE CategoryID = 2
INTERSECT
SELECT ProductID FROM OrderDetails WHERE Quantity > 10;
-- Note: INTERSECT has higher precedence than UNION
GO

-- Pattern 6: Using parentheses to control precedence
(
    SELECT ProductID FROM Products WHERE CategoryID = 1
    UNION
    SELECT ProductID FROM Products WHERE CategoryID = 2
)
INTERSECT
SELECT ProductID FROM OrderDetails WHERE Quantity > 10;
GO

-- Pattern 7: ORDER BY with set operations (only at the end)
SELECT ProductID, ProductName, 'Category1' AS Source FROM Products WHERE CategoryID = 1
UNION ALL
SELECT ProductID, ProductName, 'Category2' AS Source FROM Products WHERE CategoryID = 2
UNION ALL
SELECT ProductID, ProductName, 'Category3' AS Source FROM Products WHERE CategoryID = 3
ORDER BY ProductName, Source;
GO

-- Pattern 8: TOP with set operations
SELECT TOP 5 ProductID, ProductName, Price FROM Products WHERE CategoryID = 1 ORDER BY Price DESC;
-- Note: TOP applies to individual SELECT, not the UNION result
-- To get TOP of UNION, use subquery:
GO

SELECT TOP 10 * FROM (
    SELECT ProductID, ProductName, Price FROM Products WHERE CategoryID = 1
    UNION ALL
    SELECT ProductID, ProductName, Price FROM Products WHERE CategoryID = 2
) AS Combined
ORDER BY Price DESC;
GO

-- Pattern 9: Set operations with different column names (uses first SELECT's names)
SELECT CustomerID AS ID, CustomerName AS Name FROM Customers
UNION
SELECT SupplierID, SupplierName FROM Suppliers;
-- Result columns are ID, Name (from first SELECT)
GO

-- Pattern 10: Set operations with expressions
SELECT CustomerID, FirstName + ' ' + LastName AS FullName, 'Customer' AS EntityType
FROM Customers
UNION
SELECT EmployeeID, FirstName + ' ' + LastName, 'Employee'
FROM Employees
UNION
SELECT SupplierID, ContactName, 'Supplier'
FROM Suppliers
ORDER BY EntityType, FullName;
GO

-- Pattern 11: EXCEPT ALL and INTERSECT ALL (SQL Server 2022+)
-- SELECT ProductID FROM Products WHERE CategoryID = 1
-- EXCEPT ALL
-- SELECT ProductID FROM OrderDetails;
-- Note: EXCEPT ALL keeps duplicates based on count
GO

-- Pattern 12: Complex chaining with all operators
SELECT CustomerID FROM Customers WHERE Country = 'USA'
UNION
SELECT CustomerID FROM Customers WHERE Country = 'Canada'
EXCEPT
SELECT CustomerID FROM BlacklistedCustomers
INTERSECT
SELECT CustomerID FROM Orders WHERE TotalAmount > 1000;
GO

-- Pattern 13: Set operations in CTE
;WITH 
CustomerSet1 AS (
    SELECT CustomerID, CustomerName FROM Customers WHERE Region = 'North'
),
CustomerSet2 AS (
    SELECT CustomerID, CustomerName FROM Customers WHERE Region = 'South'
),
CombinedCustomers AS (
    SELECT CustomerID, CustomerName FROM CustomerSet1
    UNION
    SELECT CustomerID, CustomerName FROM CustomerSet2
)
SELECT * FROM CombinedCustomers
INTERSECT
SELECT CustomerID, CustomerName FROM Customers WHERE IsActive = 1;
GO

-- Pattern 14: Set operations in subquery
SELECT *
FROM Products
WHERE CategoryID IN (
    SELECT CategoryID FROM Categories WHERE ParentID IS NULL
    UNION
    SELECT CategoryID FROM Categories WHERE IsPromoted = 1
);
GO

-- Pattern 15: Set operations with GROUP BY in each part
SELECT CategoryID, COUNT(*) AS ProductCount, 'All Products' AS CountType
FROM Products
GROUP BY CategoryID
UNION ALL
SELECT CategoryID, COUNT(*) AS ProductCount, 'In Stock' AS CountType
FROM Products
WHERE StockQuantity > 0
GROUP BY CategoryID
ORDER BY CategoryID, CountType;
GO

-- Pattern 16: Set operations with HAVING
SELECT CategoryID, AVG(Price) AS AvgPrice
FROM Products
GROUP BY CategoryID
HAVING AVG(Price) > 50
UNION
SELECT CategoryID, AVG(Price)
FROM Products
GROUP BY CategoryID
HAVING COUNT(*) > 10;
GO

-- Pattern 17: EXCEPT for finding missing records
-- Products without orders
SELECT ProductID FROM Products
EXCEPT
SELECT DISTINCT ProductID FROM OrderDetails;
GO

-- Pattern 18: INTERSECT for finding common records
-- Customers who are also employees (by name)
SELECT FirstName, LastName FROM Customers
INTERSECT
SELECT FirstName, LastName FROM Employees;
GO

-- Pattern 19: Multiple EXCEPT
SELECT ProductID FROM Products
EXCEPT
SELECT ProductID FROM OrderDetails WHERE YEAR(OrderDate) = 2024
EXCEPT
SELECT ProductID FROM DiscontinuedProducts;
GO

-- Pattern 20: Set operations with NULL handling
-- UNION treats NULLs as equal for duplicate elimination
SELECT NULL AS Value
UNION
SELECT NULL AS Value;
-- Returns single NULL row
GO

-- Pattern 21: Set operations preserving order via row numbers
SELECT ProductID, ProductName, ROW_NUMBER() OVER (ORDER BY Price) AS RowNum
FROM (
    SELECT ProductID, ProductName, Price FROM Products WHERE CategoryID = 1
    UNION ALL
    SELECT ProductID, ProductName, Price FROM Products WHERE CategoryID = 2
) AS Combined;
GO

-- Pattern 22: Recursive CTE with UNION ALL (required for recursion)
;WITH Hierarchy AS (
    SELECT EmployeeID, ManagerID, EmployeeName, 0 AS Level
    FROM Employees
    WHERE ManagerID IS NULL
    
    UNION ALL  -- Must be UNION ALL, not UNION
    
    SELECT e.EmployeeID, e.ManagerID, e.EmployeeName, h.Level + 1
    FROM Employees e
    INNER JOIN Hierarchy h ON e.ManagerID = h.EmployeeID
)
SELECT * FROM Hierarchy;
GO

-- Pattern 23: Set operations with different data types (implicit conversion)
SELECT CAST(1 AS INT) AS Value
UNION
SELECT CAST(1.5 AS DECIMAL(10,2));
-- Result type is DECIMAL
GO

-- Pattern 24: Finding symmetric difference (XOR)
-- Items in A or B but not both
(
    SELECT ProductID FROM Products WHERE CategoryID = 1
    EXCEPT
    SELECT ProductID FROM Products WHERE CategoryID = 2
)
UNION
(
    SELECT ProductID FROM Products WHERE CategoryID = 2
    EXCEPT
    SELECT ProductID FROM Products WHERE CategoryID = 1
);
GO
