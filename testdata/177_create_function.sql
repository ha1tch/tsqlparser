-- Sample 177: Function Creation Patterns
-- Category: DDL / Syntax Coverage
-- Complexity: Complex
-- Purpose: Parser testing - CREATE FUNCTION syntax variations
-- Features: Scalar, table-valued, inline, multi-statement

-- Pattern 1: Basic scalar function
CREATE FUNCTION dbo.GetFullName
(
    @FirstName VARCHAR(50),
    @LastName VARCHAR(50)
)
RETURNS VARCHAR(101)
AS
BEGIN
    RETURN @FirstName + ' ' + @LastName;
END;
GO
DROP FUNCTION dbo.GetFullName;
GO

-- Pattern 2: Scalar function with multiple parameters
CREATE FUNCTION dbo.CalculateDiscount
(
    @Price DECIMAL(10,2),
    @DiscountPercent DECIMAL(5,2),
    @MinimumDiscount DECIMAL(10,2) = 0
)
RETURNS DECIMAL(10,2)
AS
BEGIN
    DECLARE @Discount DECIMAL(10,2);
    SET @Discount = @Price * (@DiscountPercent / 100);
    
    IF @Discount < @MinimumDiscount
        SET @Discount = @MinimumDiscount;
    
    RETURN @Discount;
END;
GO
DROP FUNCTION dbo.CalculateDiscount;
GO

-- Pattern 3: Scalar function with table access
CREATE FUNCTION dbo.GetCustomerOrderCount
(
    @CustomerID INT
)
RETURNS INT
AS
BEGIN
    DECLARE @Count INT;
    
    SELECT @Count = COUNT(*)
    FROM dbo.Orders
    WHERE CustomerID = @CustomerID;
    
    RETURN ISNULL(@Count, 0);
END;
GO
DROP FUNCTION dbo.GetCustomerOrderCount;
GO

-- Pattern 4: Inline table-valued function
CREATE FUNCTION dbo.GetCustomerOrders
(
    @CustomerID INT
)
RETURNS TABLE
AS
RETURN
(
    SELECT OrderID, OrderDate, TotalAmount, Status
    FROM dbo.Orders
    WHERE CustomerID = @CustomerID
);
GO
DROP FUNCTION dbo.GetCustomerOrders;
GO

-- Pattern 5: Inline TVF with parameters
CREATE FUNCTION dbo.GetOrdersInRange
(
    @StartDate DATE,
    @EndDate DATE,
    @MinAmount DECIMAL(10,2) = 0
)
RETURNS TABLE
AS
RETURN
(
    SELECT 
        o.OrderID,
        o.CustomerID,
        c.CustomerName,
        o.OrderDate,
        o.TotalAmount
    FROM dbo.Orders o
    INNER JOIN dbo.Customers c ON o.CustomerID = c.CustomerID
    WHERE o.OrderDate BETWEEN @StartDate AND @EndDate
      AND o.TotalAmount >= @MinAmount
);
GO
DROP FUNCTION dbo.GetOrdersInRange;
GO

-- Pattern 6: Multi-statement table-valued function
CREATE FUNCTION dbo.GetCustomerSummary
(
    @CustomerID INT
)
RETURNS @Result TABLE
(
    CustomerID INT,
    TotalOrders INT,
    TotalSpent DECIMAL(18,2),
    FirstOrderDate DATE,
    LastOrderDate DATE,
    AvgOrderAmount DECIMAL(18,2)
)
AS
BEGIN
    INSERT INTO @Result
    SELECT 
        @CustomerID,
        COUNT(*),
        SUM(TotalAmount),
        MIN(OrderDate),
        MAX(OrderDate),
        AVG(TotalAmount)
    FROM dbo.Orders
    WHERE CustomerID = @CustomerID;
    
    RETURN;
END;
GO
DROP FUNCTION dbo.GetCustomerSummary;
GO

-- Pattern 7: Multi-statement TVF with complex logic
CREATE FUNCTION dbo.GetHierarchy
(
    @RootID INT
)
RETURNS @Hierarchy TABLE
(
    ID INT,
    ParentID INT,
    Name VARCHAR(100),
    Level INT,
    Path VARCHAR(500)
)
AS
BEGIN
    -- Insert root
    INSERT INTO @Hierarchy (ID, ParentID, Name, Level, Path)
    SELECT ID, ParentID, Name, 0, CAST(Name AS VARCHAR(500))
    FROM dbo.Categories
    WHERE ID = @RootID;
    
    -- Recursively insert children
    DECLARE @Level INT = 0;
    
    WHILE @@ROWCOUNT > 0
    BEGIN
        SET @Level = @Level + 1;
        
        INSERT INTO @Hierarchy (ID, ParentID, Name, Level, Path)
        SELECT c.ID, c.ParentID, c.Name, @Level, h.Path + ' > ' + c.Name
        FROM dbo.Categories c
        INNER JOIN @Hierarchy h ON c.ParentID = h.ID
        WHERE h.Level = @Level - 1;
    END
    
    RETURN;
END;
GO
DROP FUNCTION dbo.GetHierarchy;
GO

-- Pattern 8: Function WITH SCHEMABINDING
CREATE FUNCTION dbo.GetProductPrice
(
    @ProductID INT
)
RETURNS DECIMAL(10,2)
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @Price DECIMAL(10,2);
    
    SELECT @Price = Price
    FROM dbo.Products
    WHERE ProductID = @ProductID;
    
    RETURN @Price;
END;
GO
DROP FUNCTION dbo.GetProductPrice;
GO

-- Pattern 9: Function WITH ENCRYPTION
CREATE FUNCTION dbo.SecretCalculation
(
    @Input INT
)
RETURNS INT
WITH ENCRYPTION
AS
BEGIN
    RETURN @Input * 42;
END;
GO
DROP FUNCTION dbo.SecretCalculation;
GO

-- Pattern 10: Function WITH EXECUTE AS
CREATE FUNCTION dbo.ElevatedFunction
(
    @TableName SYSNAME
)
RETURNS INT
WITH EXECUTE AS OWNER
AS
BEGIN
    DECLARE @Count INT;
    -- This would need dynamic SQL which isn't allowed in functions
    SET @Count = 0;
    RETURN @Count;
END;
GO
DROP FUNCTION dbo.ElevatedFunction;
GO

-- Pattern 11: Function with multiple options
CREATE FUNCTION dbo.MultiOptionFunction
(
    @Input INT
)
RETURNS INT
WITH SCHEMABINDING, RETURNS NULL ON NULL INPUT
AS
BEGIN
    RETURN @Input * 2;
END;
GO
DROP FUNCTION dbo.MultiOptionFunction;
GO

-- Pattern 12: Function with CALLED ON NULL INPUT (default)
CREATE FUNCTION dbo.HandleNulls
(
    @Input INT
)
RETURNS INT
WITH CALLED ON NULL INPUT
AS
BEGIN
    IF @Input IS NULL
        RETURN 0;
    RETURN @Input;
END;
GO
DROP FUNCTION dbo.HandleNulls;
GO

-- Pattern 13: Function with RETURNS NULL ON NULL INPUT
CREATE FUNCTION dbo.NullIfNullInput
(
    @Input INT
)
RETURNS INT
WITH RETURNS NULL ON NULL INPUT
AS
BEGIN
    RETURN @Input * 2;  -- Never called if @Input is NULL
END;
GO
DROP FUNCTION dbo.NullIfNullInput;
GO

-- Pattern 14: Inline TVF with complex query
CREATE FUNCTION dbo.GetTopProducts
(
    @CategoryID INT,
    @TopN INT
)
RETURNS TABLE
AS
RETURN
(
    SELECT TOP (@TopN)
        p.ProductID,
        p.ProductName,
        p.Price,
        SUM(od.Quantity) AS TotalSold,
        SUM(od.Quantity * od.UnitPrice) AS Revenue
    FROM dbo.Products p
    INNER JOIN dbo.OrderDetails od ON p.ProductID = od.ProductID
    WHERE p.CategoryID = @CategoryID
    GROUP BY p.ProductID, p.ProductName, p.Price
    ORDER BY Revenue DESC
);
GO
DROP FUNCTION dbo.GetTopProducts;
GO

-- Pattern 15: Function returning XML
CREATE FUNCTION dbo.GetCustomerXML
(
    @CustomerID INT
)
RETURNS XML
AS
BEGIN
    DECLARE @Result XML;
    
    SELECT @Result = (
        SELECT 
            CustomerID AS '@ID',
            CustomerName AS 'Name',
            Email AS 'Contact/Email',
            Phone AS 'Contact/Phone'
        FROM dbo.Customers
        WHERE CustomerID = @CustomerID
        FOR XML PATH('Customer')
    );
    
    RETURN @Result;
END;
GO
DROP FUNCTION dbo.GetCustomerXML;
GO

-- Pattern 16: Function with date calculations
CREATE FUNCTION dbo.GetAge
(
    @BirthDate DATE,
    @AsOfDate DATE = NULL
)
RETURNS INT
AS
BEGIN
    IF @AsOfDate IS NULL
        SET @AsOfDate = GETDATE();
    
    RETURN DATEDIFF(YEAR, @BirthDate, @AsOfDate) -
           CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, @BirthDate, @AsOfDate), @BirthDate) > @AsOfDate
                THEN 1 ELSE 0 END;
END;
GO
DROP FUNCTION dbo.GetAge;
GO

-- Pattern 17: Function for string manipulation
CREATE FUNCTION dbo.ProperCase
(
    @Input VARCHAR(MAX)
)
RETURNS VARCHAR(MAX)
AS
BEGIN
    DECLARE @Output VARCHAR(MAX) = LOWER(@Input);
    DECLARE @i INT = 1;
    
    -- Capitalize first character
    SET @Output = UPPER(LEFT(@Output, 1)) + SUBSTRING(@Output, 2, LEN(@Output));
    
    -- Capitalize after spaces
    WHILE CHARINDEX(' ', @Output, @i) > 0
    BEGIN
        SET @i = CHARINDEX(' ', @Output, @i) + 1;
        IF @i <= LEN(@Output)
            SET @Output = LEFT(@Output, @i - 1) + UPPER(SUBSTRING(@Output, @i, 1)) + SUBSTRING(@Output, @i + 1, LEN(@Output));
    END
    
    RETURN @Output;
END;
GO
DROP FUNCTION dbo.ProperCase;
GO

-- Pattern 18: ALTER FUNCTION
CREATE FUNCTION dbo.ToBeAltered(@x INT) RETURNS INT AS BEGIN RETURN @x; END;
GO

ALTER FUNCTION dbo.ToBeAltered
(
    @x INT
)
RETURNS INT
AS
BEGIN
    RETURN @x * 2;
END;
GO
DROP FUNCTION dbo.ToBeAltered;
GO

-- Pattern 19: Natively compiled function (memory-optimized)
CREATE FUNCTION dbo.NativeFunction
(
    @x INT
)
RETURNS INT
WITH NATIVE_COMPILATION, SCHEMABINDING
AS
BEGIN ATOMIC WITH (TRANSACTION ISOLATION LEVEL = SNAPSHOT, LANGUAGE = N'English')
    RETURN @x + 1;
END;
GO
DROP FUNCTION dbo.NativeFunction;
GO

-- Pattern 20: Function using CROSS APPLY in TVF
CREATE FUNCTION dbo.SplitString
(
    @String NVARCHAR(MAX),
    @Delimiter NCHAR(1)
)
RETURNS TABLE
AS
RETURN
(
    SELECT value AS Item
    FROM STRING_SPLIT(@String, @Delimiter)
);
GO
DROP FUNCTION dbo.SplitString;
GO
