-- Sample 169: Expression Operators and Precedence
-- Category: Syntax Coverage / Pure Logic
-- Complexity: Complex
-- Purpose: Parser testing - operator syntax and precedence
-- Features: All operators, precedence rules, complex expressions

-- Pattern 1: Arithmetic operators
SELECT 
    10 + 5 AS Addition,
    10 - 5 AS Subtraction,
    10 * 5 AS Multiplication,
    10 / 5 AS Division,
    10 % 3 AS Modulo,
    -10 AS UnaryMinus,
    +10 AS UnaryPlus;
GO

-- Pattern 2: Arithmetic precedence (* / before + -)
SELECT 
    10 + 5 * 2 AS WithoutParens,     -- 20 (5*2 first)
    (10 + 5) * 2 AS WithParens,       -- 30
    10 - 5 / 5 AS DivFirst,           -- 9 (5/5 first)
    (10 - 5) / 5 AS SubFirst,         -- 1
    10 + 5 * 2 - 3 / 3 AS Mixed;      -- 19
GO

-- Pattern 3: Comparison operators
DECLARE @a INT = 10, @b INT = 5;

SELECT 
    CASE WHEN @a = @b THEN 1 ELSE 0 END AS Equal,
    CASE WHEN @a <> @b THEN 1 ELSE 0 END AS NotEqual1,
    CASE WHEN @a != @b THEN 1 ELSE 0 END AS NotEqual2,
    CASE WHEN @a > @b THEN 1 ELSE 0 END AS GreaterThan,
    CASE WHEN @a < @b THEN 1 ELSE 0 END AS LessThan,
    CASE WHEN @a >= @b THEN 1 ELSE 0 END AS GreaterOrEqual,
    CASE WHEN @a <= @b THEN 1 ELSE 0 END AS LessOrEqual,
    CASE WHEN @a !< @b THEN 1 ELSE 0 END AS NotLessThan,
    CASE WHEN @a !> @b THEN 1 ELSE 0 END AS NotGreaterThan;
GO

-- Pattern 4: Logical operators
DECLARE @x BIT = 1, @y BIT = 0;

SELECT 
    CASE WHEN @x AND @y THEN 1 ELSE 0 END AS AndResult,
    CASE WHEN @x OR @y THEN 1 ELSE 0 END AS OrResult,
    CASE WHEN NOT @y THEN 1 ELSE 0 END AS NotResult;
GO

-- Pattern 5: Logical operator precedence (NOT before AND before OR)
SELECT 
    -- NOT has highest precedence
    CASE WHEN NOT 0 = 1 AND 1 = 1 THEN 'True' ELSE 'False' END AS Test1,  -- True
    -- AND before OR
    CASE WHEN 1 = 1 OR 1 = 1 AND 0 = 1 THEN 'True' ELSE 'False' END AS Test2,  -- True
    -- Parentheses override
    CASE WHEN (1 = 1 OR 1 = 1) AND 0 = 1 THEN 'True' ELSE 'False' END AS Test3;  -- False
GO

-- Pattern 6: String concatenation operator
SELECT 
    'Hello' + ' ' + 'World' AS Concatenated,
    'Value: ' + CAST(123 AS VARCHAR(10)) AS WithCast,
    N'Unicode' + N' String' AS UnicodeConcat;
GO

-- Pattern 7: Bitwise operators
SELECT 
    5 & 3 AS BitwiseAnd,      -- 0101 & 0011 = 0001 = 1
    5 | 3 AS BitwiseOr,       -- 0101 | 0011 = 0111 = 7
    5 ^ 3 AS BitwiseXor,      -- 0101 ^ 0011 = 0110 = 6
    ~5 AS BitwiseNot;         -- Inverts all bits
GO

-- Pattern 8: Bitwise shift operators (SQL Server 2022+)
SELECT 
    8 << 2 AS LeftShift,      -- 8 * 4 = 32
    32 >> 2 AS RightShift;    -- 32 / 4 = 8
GO

-- Pattern 9: Assignment operators
DECLARE @val INT = 10;

SET @val += 5;   -- Add and assign
SELECT @val;     -- 15

SET @val -= 3;   -- Subtract and assign
SELECT @val;     -- 12

SET @val *= 2;   -- Multiply and assign
SELECT @val;     -- 24

SET @val /= 4;   -- Divide and assign
SELECT @val;     -- 6

SET @val %= 4;   -- Modulo and assign
SELECT @val;     -- 2

-- Bitwise assignment
SET @val = 15;
SET @val &= 7;   -- Bitwise AND assign
SELECT @val;     -- 7

SET @val |= 8;   -- Bitwise OR assign
SELECT @val;     -- 15

SET @val ^= 5;   -- Bitwise XOR assign
SELECT @val;     -- 10
GO

-- Pattern 10: BETWEEN operator
SELECT * FROM dbo.Products WHERE Price BETWEEN 10 AND 100;
SELECT * FROM dbo.Orders WHERE OrderDate BETWEEN '2024-01-01' AND '2024-12-31';
SELECT * FROM dbo.Products WHERE Price NOT BETWEEN 10 AND 100;
GO

-- Pattern 11: IN operator
SELECT * FROM dbo.Products WHERE CategoryID IN (1, 2, 3);
SELECT * FROM dbo.Customers WHERE Country IN ('USA', 'Canada', 'UK');
SELECT * FROM dbo.Products WHERE CategoryID NOT IN (SELECT CategoryID FROM dbo.InactiveCategories);
GO

-- Pattern 12: LIKE operator with patterns
SELECT * FROM dbo.Customers WHERE CustomerName LIKE 'John%';        -- Starts with
SELECT * FROM dbo.Customers WHERE CustomerName LIKE '%son';         -- Ends with
SELECT * FROM dbo.Customers WHERE CustomerName LIKE '%mit%';        -- Contains
SELECT * FROM dbo.Customers WHERE CustomerName LIKE 'J_hn';         -- Single char wildcard
SELECT * FROM dbo.Customers WHERE Phone LIKE '[0-9][0-9][0-9]%';   -- Character range
SELECT * FROM dbo.Customers WHERE Code LIKE '[A-Z][0-9]%';         -- Letter then digit
SELECT * FROM dbo.Customers WHERE Name LIKE '%[^a-z]%';            -- Contains non-letter
SELECT * FROM dbo.Products WHERE SKU LIKE '%[_]%';                 -- Contains underscore
SELECT * FROM dbo.Products WHERE Name LIKE '%10[%]%' ESCAPE '[';   -- Contains 10%
GO

-- Pattern 13: EXISTS operator
SELECT * FROM dbo.Customers c
WHERE EXISTS (SELECT 1 FROM dbo.Orders o WHERE o.CustomerID = c.CustomerID);

SELECT * FROM dbo.Customers c
WHERE NOT EXISTS (SELECT 1 FROM dbo.Orders o WHERE o.CustomerID = c.CustomerID);
GO

-- Pattern 14: NULL comparison operators
SELECT * FROM dbo.Customers WHERE Email IS NULL;
SELECT * FROM dbo.Customers WHERE Email IS NOT NULL;
GO

-- Pattern 15: Scope resolution operator (::)
SELECT 
    geometry::STGeomFromText('POINT(0 0)', 4326) AS Point,
    geography::Point(47.65100, -122.34900, 4326) AS GeoPoint,
    hierarchyid::GetRoot() AS RootNode;
GO

-- Pattern 16: Complex expression with multiple operators
SELECT 
    ProductID,
    ProductName,
    Price,
    StockQuantity,
    CASE 
        WHEN Price > 100 AND StockQuantity < 10 THEN 'High Value Low Stock'
        WHEN Price > 100 OR StockQuantity > 100 THEN 'Notable'
        WHEN NOT (Price < 10) AND StockQuantity BETWEEN 20 AND 50 THEN 'Mid Range'
        ELSE 'Standard'
    END AS Category
FROM dbo.Products
WHERE (CategoryID IN (1, 2, 3) OR CategoryID IS NULL)
  AND ProductName LIKE '%Widget%'
  AND Price * StockQuantity > 1000;
GO

-- Pattern 17: Full operator precedence order
/*
Precedence (highest to lowest):
1. () - Parentheses
2. * / % - Multiplication, Division, Modulo
3. + - - Addition, Subtraction (also string concat)
4. = > < >= <= <> != !> !< - Comparison
5. ^ & | ~ - Bitwise
6. NOT
7. AND
8. ALL, ANY, BETWEEN, IN, LIKE, OR, SOME
9. = (assignment)
*/

SELECT 
    -- Demonstrates precedence
    1 + 2 * 3 AS ArithPrecedence,           -- 7 (not 9)
    1 + 2 > 2 AS CompareAfterArith,          -- 1 (true)
    1 = 1 AND 0 = 1 OR 1 = 1 AS LogicPrec,   -- 1 (AND before OR)
    NOT 1 = 1 AND 1 = 1 AS NotFirst,         -- 0 (NOT before AND)
    1 | 2 & 3 AS BitwisePrec;                -- 3 (& before |)
GO

-- Pattern 18: Compound expressions in different contexts
-- In SELECT
SELECT Price * 1.1 + 5 AS AdjustedPrice FROM dbo.Products;

-- In WHERE
SELECT * FROM dbo.Products WHERE Price * Quantity > 1000;

-- In ORDER BY
SELECT * FROM dbo.Products ORDER BY Price * -1;

-- In GROUP BY
SELECT Price / 10 * 10 AS PriceRange, COUNT(*) 
FROM dbo.Products 
GROUP BY Price / 10 * 10;

-- In HAVING
SELECT CategoryID, AVG(Price) 
FROM dbo.Products 
GROUP BY CategoryID
HAVING AVG(Price) * COUNT(*) > 500;

-- In UPDATE
UPDATE dbo.Products SET Price = Price * 1.1 + Adjustment;

-- In CASE
SELECT CASE WHEN Price * 1.1 > 100 THEN 'Expensive' ELSE 'Affordable' END FROM dbo.Products;
GO

-- Pattern 19: Operator with different data types
SELECT 
    1 + 1.5 AS IntPlusDecimal,               -- Decimal
    1 + '1' AS IntPlusString,                -- Error or implicit convert
    '1' + '2' AS StringConcat,               -- '12'
    CAST(1 AS FLOAT) + CAST(2 AS DECIMAL) AS MixedNumeric,
    GETDATE() + 1 AS DatePlusInt,            -- Adds days
    GETDATE() - GETDATE() AS DateMinusDate;  -- Returns INT (days)
GO

-- Pattern 20: Expression in function arguments
SELECT 
    ABS(-5 * 3 + 2) AS AbsComplex,
    POWER(2 + 3, 2) AS PowerComplex,
    SUBSTRING('Hello', 1 + 1, 5 - 2) AS SubstringComplex,
    DATEADD(DAY, 7 * 2, GETDATE()) AS DateAddComplex;
GO
