-- Sample 161: NULL Handling Functions and Patterns
-- Category: Syntax Coverage / Pure Logic
-- Complexity: Intermediate
-- Purpose: Parser testing - NULL handling syntax
-- Features: ISNULL, COALESCE, NULLIF, IS NULL, IS NOT NULL patterns

-- Pattern 1: IS NULL and IS NOT NULL
SELECT CustomerID, CustomerName, Email, Phone
FROM dbo.Customers
WHERE Email IS NULL;

SELECT CustomerID, CustomerName, Email, Phone
FROM dbo.Customers
WHERE Email IS NOT NULL;

SELECT CustomerID, CustomerName, Email, Phone
FROM dbo.Customers
WHERE Email IS NULL AND Phone IS NOT NULL;
GO

-- Pattern 2: Basic ISNULL
SELECT 
    CustomerID,
    CustomerName,
    ISNULL(Email, 'No Email') AS Email,
    ISNULL(Phone, 'No Phone') AS Phone,
    ISNULL(MiddleName, '') AS MiddleName
FROM dbo.Customers;
GO

-- Pattern 3: ISNULL with different replacement values
SELECT 
    ProductID,
    ProductName,
    ISNULL(Description, 'No description available') AS Description,
    ISNULL(DiscountPrice, Price) AS EffectivePrice,
    ISNULL(StockQuantity, 0) AS StockQuantity,
    ISNULL(ReorderLevel, 10) AS ReorderLevel
FROM dbo.Products;
GO

-- Pattern 4: Basic COALESCE (returns first non-NULL)
SELECT 
    CustomerID,
    COALESCE(PreferredName, FirstName, 'Unknown') AS DisplayName,
    COALESCE(MobilePhone, HomePhone, WorkPhone, 'No Phone') AS ContactPhone,
    COALESCE(Email, AlternateEmail, 'no-email@example.com') AS ContactEmail
FROM dbo.Customers;
GO

-- Pattern 5: COALESCE with many values
SELECT 
    OrderID,
    COALESCE(
        SpecialInstructions,
        CustomerNotes,
        DefaultInstructions,
        'No special instructions'
    ) AS Instructions
FROM dbo.Orders;
GO

-- Pattern 6: NULLIF - return NULL if values match
SELECT 
    ProductID,
    ProductName,
    Price,
    DiscountPrice,
    NULLIF(DiscountPrice, 0) AS NonZeroDiscount,  -- Returns NULL if DiscountPrice = 0
    NULLIF(DiscountPrice, Price) AS DiscountIfDifferent,  -- NULL if same as regular price
    Price / NULLIF(DiscountPrice, 0) AS PriceRatio  -- Avoids division by zero
FROM dbo.Products;
GO

-- Pattern 7: NULLIF for safe division
SELECT 
    DepartmentID,
    TotalSales,
    EmployeeCount,
    TotalSales / NULLIF(EmployeeCount, 0) AS SalesPerEmployee
FROM dbo.DepartmentStats;
GO

-- Pattern 8: Combining ISNULL and NULLIF
SELECT 
    ProductID,
    ProductName,
    ISNULL(NULLIF(Description, ''), 'No description') AS Description,  -- Treat empty as NULL
    ISNULL(NULLIF(Category, 'Unknown'), 'Uncategorized') AS Category
FROM dbo.Products;
GO

-- Pattern 9: COALESCE vs ISNULL differences
-- ISNULL: SQL Server specific, evaluates replacement once
-- COALESCE: ANSI standard, can have multiple arguments
SELECT 
    ISNULL(NULL, 'default') AS IsNullResult,
    COALESCE(NULL, NULL, 'default') AS CoalesceResult,
    -- Data type handling difference
    ISNULL(CAST(NULL AS VARCHAR(5)), 'longer string') AS IsNullType,  -- Truncates to 5
    COALESCE(CAST(NULL AS VARCHAR(5)), 'longer string') AS CoalesceType;  -- Returns full string
GO

-- Pattern 10: NULL in calculations
SELECT 
    OrderID,
    Subtotal,
    TaxAmount,
    DiscountAmount,
    -- NULL propagates in arithmetic
    Subtotal + TaxAmount - DiscountAmount AS WrongTotal,  -- NULL if any is NULL
    -- Proper NULL handling
    ISNULL(Subtotal, 0) + ISNULL(TaxAmount, 0) - ISNULL(DiscountAmount, 0) AS CorrectTotal,
    COALESCE(Subtotal, 0) + COALESCE(TaxAmount, 0) - COALESCE(DiscountAmount, 0) AS AlsoCorrect
FROM dbo.Orders;
GO

-- Pattern 11: NULL in string concatenation
SELECT 
    CustomerID,
    FirstName,
    MiddleName,
    LastName,
    -- With CONCAT_NULL_YIELDS_NULL ON (default), + with NULL = NULL
    FirstName + ' ' + MiddleName + ' ' + LastName AS FullNameBad,
    -- Proper handling
    FirstName + ISNULL(' ' + MiddleName, '') + ' ' + LastName AS FullNameGood,
    -- CONCAT ignores NULLs
    CONCAT(FirstName, ' ', MiddleName, ' ', LastName) AS FullNameConcat,
    CONCAT_WS(' ', FirstName, MiddleName, LastName) AS FullNameConcatWS
FROM dbo.Customers;
GO

-- Pattern 12: NULL in aggregate functions
SELECT 
    COUNT(*) AS TotalRows,
    COUNT(Email) AS RowsWithEmail,  -- Excludes NULLs
    COUNT(DISTINCT Email) AS UniqueEmails,
    SUM(Amount) AS TotalAmount,  -- Ignores NULLs
    AVG(Amount) AS AvgAmount,  -- Ignores NULLs
    AVG(ISNULL(Amount, 0)) AS AvgIncludingNulls  -- Treats NULL as 0
FROM dbo.Orders;
GO

-- Pattern 13: NULL in CASE expressions
SELECT 
    CustomerID,
    Email,
    Phone,
    CASE 
        WHEN Email IS NOT NULL AND Phone IS NOT NULL THEN 'Full Contact'
        WHEN Email IS NOT NULL THEN 'Email Only'
        WHEN Phone IS NOT NULL THEN 'Phone Only'
        ELSE 'No Contact Info'
    END AS ContactStatus
FROM dbo.Customers;
GO

-- Pattern 14: NULL in comparisons
SELECT 
    ProductID,
    Price,
    DiscountPrice,
    -- These comparisons don't work as expected with NULL
    CASE WHEN Price = DiscountPrice THEN 'Equal' ELSE 'Not Equal' END AS DirectCompare,
    -- Proper NULL-safe comparison
    CASE 
        WHEN Price = DiscountPrice THEN 'Equal'
        WHEN Price IS NULL AND DiscountPrice IS NULL THEN 'Both NULL'
        WHEN Price IS NULL OR DiscountPrice IS NULL THEN 'One NULL'
        ELSE 'Not Equal'
    END AS NullSafeCompare
FROM dbo.Products;
GO

-- Pattern 15: NULL in subqueries
SELECT CustomerID, CustomerName
FROM dbo.Customers c
WHERE CustomerID NOT IN (
    -- If subquery returns any NULL, NOT IN returns nothing!
    SELECT CustomerID FROM dbo.Orders WHERE CustomerID IS NOT NULL
);

-- Safer alternative with NOT EXISTS
SELECT CustomerID, CustomerName
FROM dbo.Customers c
WHERE NOT EXISTS (SELECT 1 FROM dbo.Orders o WHERE o.CustomerID = c.CustomerID);
GO

-- Pattern 16: Handling NULL in ORDER BY
SELECT CustomerID, CustomerName, Email
FROM dbo.Customers
ORDER BY 
    CASE WHEN Email IS NULL THEN 1 ELSE 0 END,  -- NULLs last
    Email;

SELECT CustomerID, CustomerName, Email
FROM dbo.Customers
ORDER BY 
    CASE WHEN Email IS NULL THEN 0 ELSE 1 END,  -- NULLs first
    Email;
GO

-- Pattern 17: SET ANSI_NULLS effects
SET ANSI_NULLS ON;  -- Standard behavior (default)
SELECT * FROM dbo.Customers WHERE Email = NULL;  -- Returns no rows
SELECT * FROM dbo.Customers WHERE Email IS NULL;  -- Correct way

-- With ANSI_NULLS OFF (not recommended)
SET ANSI_NULLS OFF;
SELECT * FROM dbo.Customers WHERE Email = NULL;  -- Would return rows where Email IS NULL
SET ANSI_NULLS ON;
GO

-- Pattern 18: NULL in UPDATE
UPDATE dbo.Customers
SET 
    Email = NULLIF(@NewEmail, ''),  -- Set to NULL if empty string
    ModifiedDate = COALESCE(ModifiedDate, GETDATE())  -- Only set if NULL
WHERE CustomerID = @CustomerID;
GO

-- Pattern 19: NULL handling in stored procedure parameters
CREATE PROCEDURE dbo.SearchCustomers
    @FirstName VARCHAR(50) = NULL,
    @LastName VARCHAR(50) = NULL,
    @Email VARCHAR(200) = NULL
AS
BEGIN
    SELECT CustomerID, FirstName, LastName, Email
    FROM dbo.Customers
    WHERE (@FirstName IS NULL OR FirstName LIKE @FirstName + '%')
      AND (@LastName IS NULL OR LastName LIKE @LastName + '%')
      AND (@Email IS NULL OR Email = @Email);
END;
GO

DROP PROCEDURE IF EXISTS dbo.SearchCustomers;
GO

-- Pattern 20: NULL-safe equality check
-- Treating two NULLs as equal
SELECT 
    a.ID, a.Value AS ValueA, b.Value AS ValueB
FROM TableA a
INNER JOIN TableB b ON 
    (a.Value = b.Value) OR (a.Value IS NULL AND b.Value IS NULL);
GO

-- Pattern 21: NULL bitmap pattern
SELECT 
    CustomerID,
    CASE WHEN FirstName IS NULL THEN 1 ELSE 0 END +
    CASE WHEN LastName IS NULL THEN 2 ELSE 0 END +
    CASE WHEN Email IS NULL THEN 4 ELSE 0 END +
    CASE WHEN Phone IS NULL THEN 8 ELSE 0 END AS NullBitmap
FROM dbo.Customers;
GO
