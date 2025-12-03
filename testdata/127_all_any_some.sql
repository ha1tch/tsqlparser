-- Sample 127: ALL, ANY, SOME Quantified Predicates
-- Category: Missing Syntax Elements
-- Complexity: Complex
-- Purpose: Parser testing - quantified comparison predicates
-- Features: ALL, ANY, SOME with subqueries, comparison operators

-- Pattern 1: Basic > ALL (greater than all values)
SELECT ProductID, ProductName, Price
FROM Products
WHERE Price > ALL (
    SELECT Price 
    FROM Products 
    WHERE CategoryID = 1
);
GO

-- Pattern 2: Basic > ANY (greater than at least one value)
SELECT ProductID, ProductName, Price
FROM Products
WHERE Price > ANY (
    SELECT Price 
    FROM Products 
    WHERE CategoryID = 1
);
GO

-- Pattern 3: SOME is equivalent to ANY
SELECT ProductID, ProductName, Price
FROM Products
WHERE Price > SOME (
    SELECT Price 
    FROM Products 
    WHERE CategoryID = 1
);
GO

-- Pattern 4: = ALL (equals all values - rare, usually empty or single value)
SELECT ProductID, ProductName, CategoryID
FROM Products
WHERE CategoryID = ALL (
    SELECT CategoryID 
    FROM Products 
    WHERE ProductID IN (1, 2, 3)
);
GO

-- Pattern 5: = ANY (equivalent to IN)
SELECT ProductID, ProductName, CategoryID
FROM Products
WHERE CategoryID = ANY (
    SELECT CategoryID 
    FROM Categories 
    WHERE CategoryName LIKE '%Electronics%'
);
-- Equivalent to: WHERE CategoryID IN (SELECT ...)
GO

-- Pattern 6: <> ALL (not equal to any - equivalent to NOT IN)
SELECT ProductID, ProductName, CategoryID
FROM Products
WHERE CategoryID <> ALL (
    SELECT CategoryID 
    FROM Categories 
    WHERE IsActive = 0
);
-- Equivalent to: WHERE CategoryID NOT IN (SELECT ...)
GO

-- Pattern 7: <> ANY (not equal to at least one)
SELECT ProductID, ProductName, CategoryID
FROM Products
WHERE CategoryID <> ANY (
    SELECT CategoryID 
    FROM Categories
);
-- True if there are at least 2 different CategoryIDs in Categories
GO

-- Pattern 8: < ALL (less than the minimum)
SELECT OrderID, TotalAmount
FROM Orders
WHERE TotalAmount < ALL (
    SELECT TotalAmount 
    FROM Orders 
    WHERE CustomerID = 100
);
-- Finds orders with amount less than customer 100's smallest order
GO

-- Pattern 9: >= ALL (greater than or equal to maximum)
SELECT EmployeeID, EmployeeName, Salary
FROM Employees
WHERE Salary >= ALL (
    SELECT Salary 
    FROM Employees
);
-- Finds employees with the highest salary
GO

-- Pattern 10: <= ANY (less than or equal to at least one)
SELECT ProductID, ProductName, StockQuantity
FROM Products
WHERE StockQuantity <= ANY (
    SELECT ReorderLevel 
    FROM Products 
    WHERE ReorderLevel > 0
);
GO

-- Pattern 11: ALL with correlated subquery
SELECT o1.OrderID, o1.CustomerID, o1.TotalAmount
FROM Orders o1
WHERE o1.TotalAmount > ALL (
    SELECT o2.TotalAmount 
    FROM Orders o2 
    WHERE o2.CustomerID = o1.CustomerID 
    AND o2.OrderID <> o1.OrderID
);
-- Finds each customer's largest order
GO

-- Pattern 12: ANY with correlated subquery
SELECT p1.ProductID, p1.ProductName, p1.Price
FROM Products p1
WHERE p1.Price > ANY (
    SELECT p2.Price 
    FROM Products p2 
    WHERE p2.CategoryID = p1.CategoryID 
    AND p2.ProductID <> p1.ProductID
);
-- Products that are more expensive than at least one other product in same category
GO

-- Pattern 13: Combining ALL/ANY with other predicates
SELECT ProductID, ProductName, Price, CategoryID
FROM Products
WHERE Price > ALL (SELECT AVG(Price) FROM Products GROUP BY CategoryID)
  AND CategoryID = ANY (SELECT CategoryID FROM Categories WHERE IsActive = 1)
  AND StockQuantity > 0;
GO

-- Pattern 14: ALL with aggregate subquery
SELECT DepartmentID, DepartmentName
FROM Departments
WHERE DepartmentID = ANY (
    SELECT DepartmentID 
    FROM Employees 
    GROUP BY DepartmentID 
    HAVING AVG(Salary) > 50000
);
GO

-- Pattern 15: Nested ALL/ANY
SELECT ProductID, ProductName, Price
FROM Products p
WHERE Price > ALL (
    SELECT Price 
    FROM Products 
    WHERE CategoryID = ANY (
        SELECT CategoryID 
        FROM Categories 
        WHERE ParentCategoryID IS NULL
    )
    AND ProductID <> p.ProductID
);
GO

-- Pattern 16: ALL with empty subquery returns TRUE
SELECT ProductID, ProductName
FROM Products
WHERE Price > ALL (
    SELECT Price 
    FROM Products 
    WHERE 1 = 0  -- Empty result
);
-- Returns all products because > ALL of nothing is TRUE
GO

-- Pattern 17: ANY with empty subquery returns FALSE
SELECT ProductID, ProductName
FROM Products
WHERE Price > ANY (
    SELECT Price 
    FROM Products 
    WHERE 1 = 0  -- Empty result
);
-- Returns no products because > ANY of nothing is FALSE
GO

-- Pattern 18: ALL with NULL handling
SELECT ProductID, ProductName, Price
FROM Products
WHERE Price > ALL (
    SELECT Price 
    FROM Products 
    WHERE CategoryID = 999  -- May contain NULLs
);
-- If subquery returns any NULL, result may be unexpected
GO

-- Pattern 19: Multiple comparisons with ALL/ANY
SELECT OrderID, OrderDate, TotalAmount
FROM Orders
WHERE TotalAmount > ANY (SELECT TotalAmount FROM Orders WHERE YEAR(OrderDate) = 2023)
  AND TotalAmount < ALL (SELECT TotalAmount FROM Orders WHERE YEAR(OrderDate) = 2025)
  AND OrderDate >= ANY (SELECT MIN(OrderDate) FROM Orders GROUP BY CustomerID);
GO

-- Pattern 20: ALL/ANY vs EXISTS performance alternative
-- These are logically equivalent:
-- Using > ALL:
SELECT p.ProductID, p.ProductName
FROM Products p
WHERE p.Price > ALL (SELECT Price FROM Products WHERE CategoryID = 5);

-- Using NOT EXISTS:
SELECT p.ProductID, p.ProductName
FROM Products p
WHERE NOT EXISTS (
    SELECT 1 FROM Products p2 
    WHERE p2.CategoryID = 5 AND p2.Price >= p.Price
);
GO

-- Pattern 21: = ANY vs IN equivalence
-- These are equivalent:
SELECT * FROM Products WHERE CategoryID = ANY (SELECT CategoryID FROM Categories WHERE IsActive = 1);
SELECT * FROM Products WHERE CategoryID IN (SELECT CategoryID FROM Categories WHERE IsActive = 1);
GO

-- Pattern 22: ALL/ANY with expressions
SELECT ProductID, ProductName, Price, Quantity
FROM Products
WHERE Price * Quantity > ALL (
    SELECT AVG(Price * Quantity) 
    FROM Products 
    GROUP BY CategoryID
);
GO
