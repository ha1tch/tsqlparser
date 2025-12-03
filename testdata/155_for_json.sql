-- Sample 155: FOR JSON and JSON Generation Patterns
-- Category: Missing Syntax Elements / Syntax Coverage
-- Complexity: Complex
-- Purpose: Parser testing - JSON generation syntax
-- Features: FOR JSON modes, PATH, AUTO, nested JSON, WITHOUT_ARRAY_WRAPPER

-- Pattern 1: Basic FOR JSON AUTO
SELECT CustomerID, CustomerName, Email
FROM dbo.Customers
FOR JSON AUTO;
GO

-- Pattern 2: FOR JSON PATH basic
SELECT CustomerID, CustomerName, Email
FROM dbo.Customers
FOR JSON PATH;
GO

-- Pattern 3: FOR JSON PATH with ROOT
SELECT CustomerID, CustomerName, Email
FROM dbo.Customers
FOR JSON PATH, ROOT('customers');
GO

-- Pattern 4: FOR JSON with nested property names
SELECT 
    CustomerID AS 'id',
    CustomerName AS 'name',
    Email AS 'contact.email',
    Phone AS 'contact.phone',
    City AS 'address.city',
    Country AS 'address.country'
FROM dbo.Customers
FOR JSON PATH;
GO

-- Pattern 5: FOR JSON without array wrapper (single object)
SELECT CustomerID, CustomerName, Email
FROM dbo.Customers
WHERE CustomerID = 1
FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
GO

-- Pattern 6: FOR JSON with INCLUDE_NULL_VALUES
SELECT CustomerID, CustomerName, Email, Phone, Fax
FROM dbo.Customers
FOR JSON PATH, INCLUDE_NULL_VALUES;
GO

-- Pattern 7: Nested JSON with subquery
SELECT 
    c.CustomerID AS id,
    c.CustomerName AS name,
    (
        SELECT o.OrderID, o.OrderDate, o.TotalAmount
        FROM dbo.Orders o
        WHERE o.CustomerID = c.CustomerID
        FOR JSON PATH
    ) AS orders
FROM dbo.Customers c
FOR JSON PATH;
GO

-- Pattern 8: Multiple nesting levels
SELECT 
    cat.CategoryID AS id,
    cat.CategoryName AS name,
    (
        SELECT 
            p.ProductID AS id,
            p.ProductName AS name,
            p.Price AS price,
            (
                SELECT r.Rating, r.Comment
                FROM dbo.Reviews r
                WHERE r.ProductID = p.ProductID
                FOR JSON PATH
            ) AS reviews
        FROM dbo.Products p
        WHERE p.CategoryID = cat.CategoryID
        FOR JSON PATH
    ) AS products
FROM dbo.Categories cat
FOR JSON PATH, ROOT('catalog');
GO

-- Pattern 9: FOR JSON AUTO with joins (automatic nesting)
SELECT c.CustomerID, c.CustomerName, o.OrderID, o.OrderDate
FROM dbo.Customers c
INNER JOIN dbo.Orders o ON c.CustomerID = o.CustomerID
FOR JSON AUTO;
GO

-- Pattern 10: Combining FOR JSON with aggregates
SELECT 
    c.CustomerID AS id,
    c.CustomerName AS name,
    COUNT(o.OrderID) AS orderCount,
    SUM(o.TotalAmount) AS totalSpent,
    (
        SELECT TOP 3 o2.OrderID, o2.OrderDate, o2.TotalAmount
        FROM dbo.Orders o2
        WHERE o2.CustomerID = c.CustomerID
        ORDER BY o2.OrderDate DESC
        FOR JSON PATH
    ) AS recentOrders
FROM dbo.Customers c
LEFT JOIN dbo.Orders o ON c.CustomerID = o.CustomerID
GROUP BY c.CustomerID, c.CustomerName
FOR JSON PATH;
GO

-- Pattern 11: FOR JSON with CASE expressions
SELECT 
    CustomerID AS id,
    CustomerName AS name,
    CASE IsActive WHEN 1 THEN 'active' ELSE 'inactive' END AS status,
    CASE 
        WHEN TotalOrders > 100 THEN 'platinum'
        WHEN TotalOrders > 50 THEN 'gold'
        WHEN TotalOrders > 10 THEN 'silver'
        ELSE 'bronze'
    END AS tier
FROM dbo.Customers
FOR JSON PATH;
GO

-- Pattern 12: FOR JSON with computed JSON properties
SELECT 
    ProductID AS id,
    ProductName AS name,
    Price AS price,
    Quantity AS inventory,
    Price * Quantity AS totalValue,
    CASE WHEN Quantity > 0 THEN 'true' ELSE 'false' END AS inStock
FROM dbo.Products
FOR JSON PATH;
GO

-- Pattern 13: Building JSON object manually
SELECT 
    '{"id":' + CAST(CustomerID AS VARCHAR(10)) + 
    ',"name":"' + REPLACE(CustomerName, '"', '\"') + 
    '","email":"' + ISNULL(Email, '') + '"}' AS ManualJson
FROM dbo.Customers;
GO

-- Pattern 14: JSON with array of primitives
SELECT 
    CustomerID AS id,
    CustomerName AS name,
    (
        SELECT Tag AS [value]
        FROM dbo.CustomerTags ct
        WHERE ct.CustomerID = c.CustomerID
        FOR JSON PATH
    ) AS tags
FROM dbo.Customers c
FOR JSON PATH;
GO

-- Pattern 15: Conditional JSON structure
SELECT 
    p.ProductID AS id,
    p.ProductName AS name,
    p.Price AS price,
    CASE 
        WHEN p.DiscountPrice IS NOT NULL THEN
            JSON_QUERY('{"original":' + CAST(p.Price AS VARCHAR(20)) + 
                       ',"discounted":' + CAST(p.DiscountPrice AS VARCHAR(20)) + '}')
        ELSE NULL
    END AS pricing
FROM dbo.Products p
FOR JSON PATH, INCLUDE_NULL_VALUES;
GO

-- Pattern 16: FOR JSON with date formatting
SELECT 
    OrderID AS id,
    CONVERT(VARCHAR(10), OrderDate, 120) AS orderDate,
    CONVERT(VARCHAR(19), CreatedAt, 126) AS createdAt,
    FORMAT(OrderDate, 'yyyy-MM-ddTHH:mm:ss') AS isoDate
FROM dbo.Orders
FOR JSON PATH;
GO

-- Pattern 17: Merging JSON from multiple sources
SELECT 
    c.CustomerID AS 'customer.id',
    c.CustomerName AS 'customer.name',
    (SELECT COUNT(*) FROM dbo.Orders WHERE CustomerID = c.CustomerID) AS 'stats.orderCount',
    (SELECT SUM(TotalAmount) FROM dbo.Orders WHERE CustomerID = c.CustomerID) AS 'stats.totalSpent',
    (SELECT MAX(OrderDate) FROM dbo.Orders WHERE CustomerID = c.CustomerID) AS 'stats.lastOrderDate'
FROM dbo.Customers c
FOR JSON PATH;
GO

-- Pattern 18: FOR JSON with empty arrays handled
SELECT 
    c.CustomerID AS id,
    c.CustomerName AS name,
    ISNULL(
        (SELECT o.OrderID, o.OrderDate
         FROM dbo.Orders o
         WHERE o.CustomerID = c.CustomerID
         FOR JSON PATH),
        '[]'
    ) AS orders
FROM dbo.Customers c
FOR JSON PATH;
GO

-- Pattern 19: Complex API response format
SELECT 
    'success' AS status,
    200 AS statusCode,
    (
        SELECT 
            c.CustomerID AS id,
            c.CustomerName AS name,
            c.Email AS email,
            (
                SELECT o.OrderID AS id, o.TotalAmount AS total
                FROM dbo.Orders o
                WHERE o.CustomerID = c.CustomerID
                FOR JSON PATH
            ) AS orders
        FROM dbo.Customers c
        WHERE c.IsActive = 1
        FOR JSON PATH
    ) AS data,
    (SELECT COUNT(*) FROM dbo.Customers WHERE IsActive = 1) AS 'meta.totalCount',
    1 AS 'meta.page',
    25 AS 'meta.pageSize'
FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
GO

-- Pattern 20: Storing FOR JSON result in variable
DECLARE @JsonResult NVARCHAR(MAX);

SET @JsonResult = (
    SELECT CustomerID, CustomerName, Email
    FROM dbo.Customers
    WHERE IsActive = 1
    FOR JSON PATH, ROOT('customers')
);

SELECT @JsonResult AS JsonOutput;
GO

-- Pattern 21: FOR JSON with binary data (base64 encoded)
SELECT 
    DocumentID AS id,
    DocumentName AS name,
    CAST('' AS XML).value('xs:base64Binary(sql:column("FileContent"))', 'VARCHAR(MAX)') AS contentBase64
FROM dbo.Documents
FOR JSON PATH;
GO

-- Pattern 22: Hierarchical data flattening for JSON
;WITH Hierarchy AS (
    SELECT 
        CategoryID, CategoryName, ParentCategoryID,
        CAST(CategoryName AS NVARCHAR(500)) AS Path,
        0 AS Level
    FROM dbo.Categories WHERE ParentCategoryID IS NULL
    UNION ALL
    SELECT 
        c.CategoryID, c.CategoryName, c.ParentCategoryID,
        CAST(h.Path + ' > ' + c.CategoryName AS NVARCHAR(500)),
        h.Level + 1
    FROM dbo.Categories c
    INNER JOIN Hierarchy h ON c.ParentCategoryID = h.CategoryID
)
SELECT CategoryID AS id, CategoryName AS name, Path AS fullPath, Level AS depth
FROM Hierarchy
FOR JSON PATH, ROOT('categories');
GO
