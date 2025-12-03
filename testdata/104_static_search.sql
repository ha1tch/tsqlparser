-- Sample 104: Static Search Queries
-- Category: Static SQL Equivalents
-- Complexity: Complex
-- Purpose: Parser testing - search patterns without dynamic SQL
-- Features: Multiple WHERE conditions, LIKE patterns, NULL handling, OR optimization

-- Pattern 1: Multi-field text search
SELECT 
    CustomerID,
    FirstName,
    LastName,
    Email,
    Phone,
    Address,
    City,
    State,
    ZipCode
FROM dbo.Customers
WHERE 
    (FirstName LIKE '%john%' OR LastName LIKE '%john%')
    OR Email LIKE '%john%'
    OR Phone LIKE '%555%'
    OR Address LIKE '%main%'
ORDER BY LastName, FirstName;
GO

-- Pattern 2: Optional parameters using OR/AND with NULL checks
SELECT 
    o.OrderID,
    o.OrderDate,
    o.TotalAmount,
    o.Status,
    c.CustomerName
FROM dbo.Orders o
INNER JOIN dbo.Customers c ON o.CustomerID = c.CustomerID
WHERE 
    (o.OrderDate >= '2024-01-01' OR '2024-01-01' IS NULL)
    AND (o.OrderDate <= '2024-12-31' OR '2024-12-31' IS NULL)
    AND (o.Status = 'Pending' OR 'Pending' IS NULL)
    AND (c.CustomerID = 12345 OR 12345 IS NULL)
    AND (o.TotalAmount >= 100.00 OR 100.00 IS NULL)
ORDER BY o.OrderDate DESC;
GO

-- Pattern 3: COALESCE-based optional filtering
SELECT 
    ProductID,
    ProductName,
    CategoryID,
    Price,
    StockQuantity
FROM dbo.Products
WHERE 
    CategoryID = COALESCE(NULL, CategoryID)
    AND Price >= COALESCE(NULL, Price)
    AND Price <= COALESCE(NULL, Price)
    AND StockQuantity >= COALESCE(NULL, 0)
    AND IsActive = COALESCE(NULL, IsActive)
ORDER BY ProductName;
GO

-- Pattern 4: Full-text style search with multiple conditions
SELECT 
    ArticleID,
    Title,
    Author,
    PublishDate,
    Category,
    LEFT(Content, 200) AS ContentPreview
FROM dbo.Articles
WHERE 
    (
        Title LIKE '%database%'
        OR Title LIKE '%sql%'
        OR Title LIKE '%performance%'
    )
    AND (
        Content LIKE '%optimization%'
        OR Content LIKE '%index%'
        OR Content LIKE '%query%'
    )
    AND PublishDate >= '2023-01-01'
    AND Status = 'Published'
ORDER BY PublishDate DESC;
GO

-- Pattern 5: Range search with BETWEEN
SELECT 
    TransactionID,
    AccountID,
    TransactionDate,
    Amount,
    TransactionType,
    Description
FROM dbo.Transactions
WHERE 
    TransactionDate BETWEEN '2024-01-01' AND '2024-06-30'
    AND Amount BETWEEN 100.00 AND 10000.00
    AND TransactionType IN ('Credit', 'Debit', 'Transfer')
    AND AccountID BETWEEN 1000 AND 9999
ORDER BY TransactionDate, TransactionID;
GO

-- Pattern 6: Complex boolean logic with parentheses
SELECT 
    EmployeeID,
    FirstName,
    LastName,
    Department,
    JobTitle,
    Salary,
    HireDate
FROM dbo.Employees
WHERE 
    (
        (Department = 'Engineering' AND Salary > 80000)
        OR (Department = 'Sales' AND Salary > 60000)
        OR (Department = 'Marketing' AND Salary > 50000)
    )
    AND (
        HireDate < '2020-01-01'
        OR JobTitle LIKE '%Senior%'
        OR JobTitle LIKE '%Lead%'
    )
    AND IsActive = 1
    AND (TerminationDate IS NULL OR TerminationDate > GETDATE())
ORDER BY Department, Salary DESC;
GO

-- Pattern 7: NOT conditions and exclusions
SELECT 
    ProductID,
    ProductName,
    CategoryID,
    SupplierID,
    Price,
    UnitsInStock
FROM dbo.Products
WHERE 
    CategoryID NOT IN (5, 8, 12)
    AND SupplierID NOT IN (SELECT SupplierID FROM dbo.BlockedSuppliers)
    AND ProductName NOT LIKE '%discontinued%'
    AND ProductName NOT LIKE '%test%'
    AND Price NOT BETWEEN 0 AND 0.99
    AND UnitsInStock IS NOT NULL
    AND Discontinued <> 1
ORDER BY CategoryID, ProductName;
GO

-- Pattern 8: EXISTS and NOT EXISTS patterns
SELECT 
    c.CustomerID,
    c.CustomerName,
    c.Email,
    c.CreatedDate
FROM dbo.Customers c
WHERE 
    EXISTS (
        SELECT 1 
        FROM dbo.Orders o 
        WHERE o.CustomerID = c.CustomerID 
        AND o.OrderDate >= '2024-01-01'
    )
    AND NOT EXISTS (
        SELECT 1 
        FROM dbo.CustomerComplaints cc 
        WHERE cc.CustomerID = c.CustomerID 
        AND cc.Status = 'Unresolved'
    )
    AND EXISTS (
        SELECT 1
        FROM dbo.CustomerPayments cp
        WHERE cp.CustomerID = c.CustomerID
        AND cp.PaymentStatus = 'Completed'
        HAVING SUM(cp.Amount) > 1000
    )
ORDER BY c.CustomerName;
GO

-- Pattern 9: LIKE with escape characters
SELECT 
    DocumentID,
    Title,
    FilePath,
    CreatedBy
FROM dbo.Documents
WHERE 
    Title LIKE '%[%]%' ESCAPE '\'
    OR Title LIKE '%[_]%' ESCAPE '\'
    OR FilePath LIKE '%\\server\\share\\%' ESCAPE '\'
    OR FilePath LIKE '%[[]brackets[]]%' ESCAPE '\'
ORDER BY Title;
GO

-- Pattern 10: Compound key search
SELECT 
    OrderID,
    LineNumber,
    ProductID,
    Quantity,
    UnitPrice,
    Discount
FROM dbo.OrderDetails
WHERE 
    (OrderID = 1001 AND LineNumber = 1)
    OR (OrderID = 1001 AND LineNumber = 3)
    OR (OrderID = 1002 AND LineNumber BETWEEN 1 AND 5)
    OR (OrderID IN (1003, 1004, 1005) AND ProductID = 100)
ORDER BY OrderID, LineNumber;
GO
