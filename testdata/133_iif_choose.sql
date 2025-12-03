-- Sample 133: IIF, CHOOSE, and Conditional Expression Functions
-- Category: Syntax Edge Cases
-- Complexity: Intermediate
-- Purpose: Parser testing - conditional expressions beyond CASE
-- Features: IIF, CHOOSE, COALESCE, NULLIF, conditional patterns

-- Pattern 1: Basic IIF expression
SELECT 
    ProductID,
    ProductName,
    StockQuantity,
    IIF(StockQuantity > 0, 'In Stock', 'Out of Stock') AS StockStatus
FROM Products;
GO

-- Pattern 2: IIF with expressions
SELECT 
    OrderID,
    TotalAmount,
    IIF(TotalAmount >= 1000, TotalAmount * 0.10, 0) AS DiscountAmount,
    IIF(TotalAmount >= 1000, TotalAmount * 0.90, TotalAmount) AS FinalAmount
FROM Orders;
GO

-- Pattern 3: Nested IIF (equivalent to CASE with multiple WHEN)
SELECT 
    StudentID,
    Score,
    IIF(Score >= 90, 'A',
        IIF(Score >= 80, 'B',
            IIF(Score >= 70, 'C',
                IIF(Score >= 60, 'D', 'F')
            )
        )
    ) AS Grade
FROM Students;
GO

-- Pattern 4: IIF with NULL handling
SELECT 
    CustomerID,
    Email,
    IIF(Email IS NULL, 'No Email', Email) AS EmailDisplay,
    IIF(Email IS NOT NULL AND Email <> '', 1, 0) AS HasValidEmail
FROM Customers;
GO

-- Pattern 5: Basic CHOOSE function
SELECT 
    OrderID,
    DayOfWeek,
    CHOOSE(DayOfWeek, 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday') AS DayName
FROM Orders;
GO

-- Pattern 6: CHOOSE with calculated index
SELECT 
    ProductID,
    Rating,
    CHOOSE(
        CASE 
            WHEN Rating >= 4.5 THEN 1
            WHEN Rating >= 3.5 THEN 2
            WHEN Rating >= 2.5 THEN 3
            ELSE 4
        END,
        'Excellent', 'Good', 'Average', 'Poor'
    ) AS RatingCategory
FROM Products;
GO

-- Pattern 7: CHOOSE with months
SELECT 
    OrderID,
    OrderDate,
    CHOOSE(MONTH(OrderDate), 
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
    ) AS MonthName
FROM Orders;
GO

-- Pattern 8: CHOOSE returning different types (implicit conversion)
SELECT 
    CategoryID,
    CHOOSE(CategoryID, 10.5, 20, 'Thirty', NULL, 50) AS MixedResult
FROM Categories
WHERE CategoryID <= 5;
GO

-- Pattern 9: COALESCE variations
SELECT 
    CustomerID,
    COALESCE(PreferredName, FirstName, 'Unknown') AS DisplayName,
    COALESCE(MobilePhone, HomePhone, WorkPhone, 'No Phone') AS ContactPhone,
    COALESCE(Email, AlternateEmail, 'noemail@example.com') AS ContactEmail
FROM Customers;
GO

-- Pattern 10: COALESCE with expressions
SELECT 
    OrderID,
    COALESCE(DiscountAmount, TotalAmount * 0.05, 0) AS AppliedDiscount,
    COALESCE(ShippingCost, 
        IIF(TotalAmount >= 100, 0, 9.99), 
        9.99
    ) AS FinalShipping
FROM Orders;
GO

-- Pattern 11: NULLIF variations
SELECT 
    ProductID,
    ProductName,
    NULLIF(StockQuantity, 0) AS NullableStock,  -- Returns NULL if 0
    NULLIF(Description, '') AS NullableDescription,  -- Returns NULL if empty string
    Price / NULLIF(StockQuantity, 0) AS PricePerAvailableUnit  -- Avoids division by zero
FROM Products;
GO

-- Pattern 12: Combining COALESCE and NULLIF
SELECT 
    CustomerID,
    COALESCE(NULLIF(MiddleName, ''), 'N/A') AS MiddleNameDisplay,
    COALESCE(NULLIF(Phone, 'N/A'), NULLIF(Mobile, 'N/A'), 'No Contact') AS PhoneDisplay
FROM Customers;
GO

-- Pattern 13: IIF in aggregate context
SELECT 
    CategoryID,
    COUNT(*) AS TotalProducts,
    SUM(IIF(StockQuantity > 0, 1, 0)) AS InStockCount,
    SUM(IIF(StockQuantity = 0, 1, 0)) AS OutOfStockCount,
    AVG(IIF(StockQuantity > 0, Price, NULL)) AS AvgPriceInStock
FROM Products
GROUP BY CategoryID;
GO

-- Pattern 14: IIF vs CASE comparison
SELECT 
    OrderID,
    Status,
    -- Using IIF
    IIF(Status = 'Shipped', 'Yes', 'No') AS IsShippedIIF,
    -- Equivalent CASE
    CASE WHEN Status = 'Shipped' THEN 'Yes' ELSE 'No' END AS IsShippedCASE,
    -- Multiple conditions with IIF
    IIF(Status IN ('Shipped', 'Delivered'), 'Fulfilled', 
        IIF(Status = 'Cancelled', 'Cancelled', 'Pending')) AS StatusGroupIIF,
    -- Equivalent CASE
    CASE 
        WHEN Status IN ('Shipped', 'Delivered') THEN 'Fulfilled'
        WHEN Status = 'Cancelled' THEN 'Cancelled'
        ELSE 'Pending'
    END AS StatusGroupCASE
FROM Orders;
GO

-- Pattern 15: CHOOSE vs CASE comparison
SELECT 
    Quarter,
    -- Using CHOOSE
    CHOOSE(Quarter, 'Q1', 'Q2', 'Q3', 'Q4') AS QuarterNameCHOOSE,
    -- Equivalent CASE
    CASE Quarter
        WHEN 1 THEN 'Q1'
        WHEN 2 THEN 'Q2'
        WHEN 3 THEN 'Q3'
        WHEN 4 THEN 'Q4'
    END AS QuarterNameCASE
FROM (SELECT 1 AS Quarter UNION SELECT 2 UNION SELECT 3 UNION SELECT 4) AS Q;
GO

-- Pattern 16: IIF with type precedence
SELECT 
    IIF(1 = 1, 1, 'text') AS WillFail,  -- Type conflict error
    IIF(1 = 1, CAST(1 AS SQL_VARIANT), 'text') AS WillWork  -- SQL_VARIANT accepts both
FROM (SELECT 1 AS Dummy) AS T;
GO

-- Pattern 17: Complex nested conditionals
SELECT 
    EmployeeID,
    Salary,
    YearsOfService,
    IIF(
        YearsOfService >= 10,
        IIF(Salary >= 80000, 'Senior High', 'Senior Standard'),
        IIF(
            YearsOfService >= 5,
            IIF(Salary >= 60000, 'Mid High', 'Mid Standard'),
            IIF(Salary >= 40000, 'Junior High', 'Junior Standard')
        )
    ) AS EmployeeCategory
FROM Employees;
GO

-- Pattern 18: CHOOSE with NULL index behavior
SELECT 
    CHOOSE(NULL, 'A', 'B', 'C') AS NullIndex,  -- Returns NULL
    CHOOSE(0, 'A', 'B', 'C') AS ZeroIndex,     -- Returns NULL (out of range)
    CHOOSE(4, 'A', 'B', 'C') AS OutOfRange;    -- Returns NULL (out of range)
GO

-- Pattern 19: Conditional aggregation alternatives
SELECT 
    CategoryID,
    -- Traditional CASE
    SUM(CASE WHEN Status = 'Active' THEN 1 ELSE 0 END) AS ActiveCASE,
    -- Using IIF
    SUM(IIF(Status = 'Active', 1, 0)) AS ActiveIIF,
    -- Count variation
    COUNT(IIF(Status = 'Active', 1, NULL)) AS ActiveCOUNT
FROM Products
GROUP BY CategoryID;
GO

-- Pattern 20: IIF in ORDER BY
SELECT ProductID, ProductName, StockQuantity, Price
FROM Products
ORDER BY 
    IIF(StockQuantity = 0, 1, 0),  -- Out of stock last
    Price DESC;
GO
