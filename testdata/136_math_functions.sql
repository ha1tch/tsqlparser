-- Sample 136: Mathematical and Numeric Functions
-- Category: Pure Logic / Syntax Coverage
-- Complexity: Complex
-- Purpose: Parser testing - all math and numeric functions
-- Features: All T-SQL mathematical functions, precision, conversions

-- Pattern 1: Basic arithmetic functions
SELECT 
    ABS(-15.5) AS AbsoluteValue,
    SIGN(-15.5) AS SignNeg,
    SIGN(15.5) AS SignPos,
    SIGN(0) AS SignZero,
    CEILING(15.2) AS Ceiling,
    FLOOR(15.8) AS Floor,
    ROUND(15.567, 2) AS Round2,
    ROUND(15.567, 1) AS Round1,
    ROUND(15.567, 0) AS Round0,
    ROUND(155.67, -1) AS RoundTens,
    ROUND(155.67, -2) AS RoundHundreds;
GO

-- Pattern 2: Power and root functions
SELECT 
    POWER(2, 10) AS PowerOf2,
    POWER(10, 3) AS PowerOf10,
    SQRT(144) AS SquareRoot,
    SQRT(2) AS SqrtTwo,
    SQUARE(5) AS Square,
    EXP(1) AS E,
    EXP(2) AS ESquared,
    LOG(10) AS NaturalLog,
    LOG10(100) AS Log10,
    LOG(8, 2) AS LogBase2;  -- LOG(value, base)
GO

-- Pattern 3: Trigonometric functions
SELECT 
    PI() AS Pi,
    SIN(PI()/6) AS Sin30,
    COS(PI()/3) AS Cos60,
    TAN(PI()/4) AS Tan45,
    COT(PI()/4) AS Cot45,
    ASIN(0.5) AS ArcSin,
    ACOS(0.5) AS ArcCos,
    ATAN(1) AS ArcTan,
    ATN2(1, 1) AS ArcTan2,
    DEGREES(PI()) AS DegreesFromRadians,
    RADIANS(180.0) AS RadiansFromDegrees;
GO

-- Pattern 4: Rounding variations
SELECT 
    ROUND(15.567, 2) AS RoundNormal,
    ROUND(15.565, 2) AS RoundMidpoint,
    ROUND(15.567, 2, 1) AS RoundTruncate,  -- 3rd param = truncate
    ROUND(-15.567, 2) AS RoundNegative,
    ROUND(-15.567, 2, 1) AS RoundNegTruncate;
GO

-- Pattern 5: Random numbers
SELECT 
    RAND() AS Random0to1,
    RAND(12345) AS RandomSeeded,
    CAST(RAND() * 100 AS INT) AS Random0to99,
    1 + CAST(RAND() * 6 AS INT) AS DiceRoll,
    NEWID() AS RandomGuid,
    CHECKSUM(NEWID()) AS RandomInt;
GO

-- Pattern 6: Conversion functions
SELECT 
    CAST(15.7 AS INT) AS CastToInt,
    CONVERT(INT, 15.7) AS ConvertToInt,
    CAST('123' AS INT) AS CastStringToInt,
    TRY_CAST('abc' AS INT) AS TryCastInvalid,
    TRY_CONVERT(INT, 'abc') AS TryConvertInvalid,
    PARSE('123' AS INT) AS ParseInt,
    TRY_PARSE('abc' AS INT) AS TryParseInvalid;
GO

-- Pattern 7: Numeric precision and scale
SELECT 
    CAST(1234.5678 AS DECIMAL(10,2)) AS Decimal10_2,
    CAST(1234.5678 AS DECIMAL(10,4)) AS Decimal10_4,
    CAST(1234.5678 AS NUMERIC(8,3)) AS Numeric8_3,
    CAST(1234.5678 AS FLOAT) AS Float,
    CAST(1234.5678 AS REAL) AS Real,
    CAST(1234.5678 AS MONEY) AS Money,
    CAST(1234.5678 AS SMALLMONEY) AS SmallMoney;
GO

-- Pattern 8: Modulo and division
SELECT 
    17 % 5 AS Modulo,
    17 / 5 AS IntegerDivision,
    17.0 / 5 AS DecimalDivision,
    CAST(17 AS FLOAT) / 5 AS FloatDivision,
    17 / NULLIF(0, 0) AS SafeDivision;  -- Returns NULL instead of error
GO

-- Pattern 9: MIN, MAX with expressions
SELECT 
    CASE WHEN 10 > 5 THEN 10 ELSE 5 END AS MaxManual,
    IIF(10 > 5, 10, 5) AS MaxIIF,
    -- No built-in MAX for scalars, but can use VALUES
    (SELECT MAX(v) FROM (VALUES (10), (5), (8)) AS T(v)) AS MaxOfValues,
    (SELECT MIN(v) FROM (VALUES (10), (5), (8)) AS T(v)) AS MinOfValues;
GO

-- Pattern 10: GREATEST and LEAST (SQL Server 2022+)
SELECT 
    GREATEST(10, 5, 8, 3, 12) AS GreatestValue,
    LEAST(10, 5, 8, 3, 12) AS LeastValue,
    GREATEST('Apple', 'Banana', 'Cherry') AS GreatestString,
    LEAST('Apple', 'Banana', 'Cherry') AS LeastString;
GO

-- Pattern 11: Binary and bitwise operations
SELECT 
    5 & 3 AS BitwiseAnd,
    5 | 3 AS BitwiseOr,
    5 ^ 3 AS BitwiseXor,
    ~5 AS BitwiseNot,
    1 << 4 AS LeftShift,  -- SQL Server 2022+
    16 >> 2 AS RightShift;  -- SQL Server 2022+
GO

-- Pattern 12: Statistical calculations
SELECT 
    AVG(Price) AS AveragePrice,
    AVG(CAST(Price AS FLOAT)) AS AveragePriceFloat,
    STDEV(Price) AS StandardDev,
    STDEVP(Price) AS StandardDevPop,
    VAR(Price) AS Variance,
    VARP(Price) AS VariancePop
FROM Products;
GO

-- Pattern 13: Aggregate with DISTINCT
SELECT 
    COUNT(*) AS TotalRows,
    COUNT(CategoryID) AS CountNonNull,
    COUNT(DISTINCT CategoryID) AS DistinctCategories,
    SUM(Price) AS TotalPrice,
    SUM(DISTINCT Price) AS SumDistinctPrices,
    AVG(Price) AS AvgPrice,
    AVG(DISTINCT Price) AS AvgDistinctPrice
FROM Products;
GO

-- Pattern 14: Overflow handling
SELECT 
    CAST(2147483647 AS INT) AS MaxInt,
    CAST(2147483647 AS BIGINT) + 1 AS MaxIntPlusOne,
    CAST(9223372036854775807 AS BIGINT) AS MaxBigInt,
    CAST(1.79E+308 AS FLOAT) AS MaxFloat,
    CAST(99999999999999999999999999999.999999999 AS DECIMAL(38,9)) AS LargeDecimal;
GO

-- Pattern 15: Numeric string functions
SELECT 
    STR(123.456, 10, 2) AS NumToString,
    FORMAT(12345678.90, 'N', 'en-US') AS FormatWithCommas,
    FORMAT(12345678.90, 'C', 'en-US') AS FormatCurrency,
    FORMAT(0.1234, 'P', 'en-US') AS FormatPercent,
    FORMAT(12345678, 'D10') AS FormatPadded;
GO

-- Pattern 16: Complex mathematical expressions
-- Quadratic formula: (-b + sqrt(b^2 - 4ac)) / 2a
DECLARE @a FLOAT = 1, @b FLOAT = -5, @c FLOAT = 6;
-- Roots of x^2 - 5x + 6 = 0 are x=2 and x=3
SELECT 
    (-@b + SQRT(POWER(@b, 2) - 4 * @a * @c)) / (2 * @a) AS Root1,
    (-@b - SQRT(POWER(@b, 2) - 4 * @a * @c)) / (2 * @a) AS Root2;
GO

DECLARE @a FLOAT = 1, @b FLOAT = -5, @c FLOAT = 6;
SELECT 
    (-@b + SQRT(POWER(@b, 2) - 4 * @a * @c)) / (2 * @a) AS Root1,
    (-@b - SQRT(POWER(@b, 2) - 4 * @a * @c)) / (2 * @a) AS Root2;
GO

-- Pattern 17: Distance calculation (Euclidean)
DECLARE @x1 FLOAT = 0, @y1 FLOAT = 0;
DECLARE @x2 FLOAT = 3, @y2 FLOAT = 4;
SELECT SQRT(POWER(@x2 - @x1, 2) + POWER(@y2 - @y1, 2)) AS Distance;  -- Should be 5
GO

-- Pattern 18: Compound interest formula
DECLARE @principal DECIMAL(18,2) = 1000;
DECLARE @rate DECIMAL(10,4) = 0.05;  -- 5%
DECLARE @years INT = 10;
DECLARE @compoundsPerYear INT = 12;

SELECT 
    @principal * POWER(1 + @rate / @compoundsPerYear, @compoundsPerYear * @years) AS FutureValue,
    @principal * POWER(1 + @rate / @compoundsPerYear, @compoundsPerYear * @years) - @principal AS InterestEarned;
GO

-- Pattern 19: Percentage calculations
SELECT 
    Price,
    Price * 0.20 AS TwentyPercent,
    Price * 1.20 AS PricePlusTwentyPercent,
    Price / 1.20 AS PriceBeforeTwentyPercent,
    (Price - Cost) / NULLIF(Cost, 0) * 100 AS MarginPercent
FROM Products;
GO

-- Pattern 20: Number formatting edge cases
SELECT 
    CAST(0.1 + 0.2 AS DECIMAL(10,2)) AS FloatPrecisionIssue,
    0.1 + 0.2 AS FloatResult,
    ROUND(0.1 + 0.2, 2) AS RoundedFloat,
    CAST(1.0 / 3.0 AS DECIMAL(38,20)) AS RepeatingDecimal;
GO
