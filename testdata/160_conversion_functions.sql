-- Sample 160: Conversion Functions
-- Category: Syntax Coverage / Pure Logic
-- Complexity: Complex
-- Purpose: Parser testing - data type conversion syntax
-- Features: CAST, CONVERT, TRY_CAST, TRY_CONVERT, PARSE, TRY_PARSE

-- Pattern 1: Basic CAST
SELECT 
    CAST(123 AS VARCHAR(10)) AS IntToStr,
    CAST('456' AS INT) AS StrToInt,
    CAST(123.456 AS INT) AS DecToInt,
    CAST(123 AS DECIMAL(10,2)) AS IntToDec,
    CAST('2024-06-15' AS DATE) AS StrToDate,
    CAST(GETDATE() AS DATE) AS DateTimeToDate;
GO

-- Pattern 2: CAST with all numeric types
SELECT 
    CAST(127 AS TINYINT) AS ToTinyInt,
    CAST(32767 AS SMALLINT) AS ToSmallInt,
    CAST(2147483647 AS INT) AS ToInt,
    CAST(9223372036854775807 AS BIGINT) AS ToBigInt,
    CAST(123.456789 AS DECIMAL(18,6)) AS ToDecimal,
    CAST(123.456789 AS NUMERIC(10,2)) AS ToNumeric,
    CAST(123.45 AS MONEY) AS ToMoney,
    CAST(123.45 AS SMALLMONEY) AS ToSmallMoney,
    CAST(123.456789 AS FLOAT) AS ToFloat,
    CAST(123.456789 AS REAL) AS ToReal;
GO

-- Pattern 3: CAST with string types
SELECT 
    CAST('Hello' AS CHAR(10)) AS ToChar,
    CAST('Hello' AS VARCHAR(100)) AS ToVarChar,
    CAST(N'Hello' AS NCHAR(10)) AS ToNChar,
    CAST(N'Hello' AS NVARCHAR(100)) AS ToNVarChar,
    CAST('Hello' AS VARCHAR(MAX)) AS ToVarCharMax,
    CAST(N'Unicode: 日本語' AS NVARCHAR(MAX)) AS ToNVarCharMax;
GO

-- Pattern 4: CAST with date/time types
SELECT 
    CAST('2024-06-15' AS DATE) AS ToDate,
    CAST('14:30:45' AS TIME) AS ToTime,
    CAST('14:30:45.1234567' AS TIME(7)) AS ToTime7,
    CAST('2024-06-15 14:30:45' AS DATETIME) AS ToDateTime,
    CAST('2024-06-15 14:30:45.1234567' AS DATETIME2) AS ToDateTime2,
    CAST('2024-06-15 14:30' AS SMALLDATETIME) AS ToSmallDateTime,
    CAST('2024-06-15 14:30:45 +05:30' AS DATETIMEOFFSET) AS ToDateTimeOffset;
GO

-- Pattern 5: CAST with binary types
SELECT 
    CAST('Hello' AS BINARY(10)) AS ToBinary,
    CAST('Hello' AS VARBINARY(100)) AS ToVarBinary,
    CAST(0x48656C6C6F AS VARCHAR(10)) AS BinaryToStr,
    CAST(12345 AS VARBINARY(8)) AS IntToBinary;
GO

-- Pattern 6: Basic CONVERT
SELECT 
    CONVERT(VARCHAR(10), 123) AS IntToStr,
    CONVERT(INT, '456') AS StrToInt,
    CONVERT(DATE, '2024-06-15') AS StrToDate,
    CONVERT(DECIMAL(10,2), 123.456) AS ToDecimal;
GO

-- Pattern 7: CONVERT with date styles
DECLARE @dt DATETIME = '2024-06-15 14:30:45';

SELECT 
    CONVERT(VARCHAR(20), @dt, 0) AS Style0,    -- Jun 15 2024  2:30PM
    CONVERT(VARCHAR(10), @dt, 1) AS Style1,    -- 06/15/24
    CONVERT(VARCHAR(10), @dt, 101) AS Style101, -- 06/15/2024
    CONVERT(VARCHAR(10), @dt, 2) AS Style2,    -- 24.06.15
    CONVERT(VARCHAR(10), @dt, 102) AS Style102, -- 2024.06.15
    CONVERT(VARCHAR(10), @dt, 3) AS Style3,    -- 15/06/24
    CONVERT(VARCHAR(10), @dt, 103) AS Style103, -- 15/06/2024
    CONVERT(VARCHAR(10), @dt, 4) AS Style4,    -- 15.06.24
    CONVERT(VARCHAR(10), @dt, 104) AS Style104, -- 15.06.2024
    CONVERT(VARCHAR(10), @dt, 5) AS Style5,    -- 15-06-24
    CONVERT(VARCHAR(10), @dt, 105) AS Style105, -- 15-06-2024
    CONVERT(VARCHAR(11), @dt, 6) AS Style6,    -- 15 Jun 24
    CONVERT(VARCHAR(11), @dt, 106) AS Style106, -- 15 Jun 2024
    CONVERT(VARCHAR(12), @dt, 7) AS Style7,    -- Jun 15, 24
    CONVERT(VARCHAR(12), @dt, 107) AS Style107; -- Jun 15, 2024
GO

-- Pattern 8: CONVERT with more date styles
DECLARE @dt DATETIME = '2024-06-15 14:30:45.123';

SELECT 
    CONVERT(VARCHAR(8), @dt, 8) AS Style8,     -- 14:30:45
    CONVERT(VARCHAR(8), @dt, 108) AS Style108,  -- 14:30:45
    CONVERT(VARCHAR(26), @dt, 9) AS Style9,    -- Jun 15 2024  2:30:45:123PM
    CONVERT(VARCHAR(26), @dt, 109) AS Style109, -- Jun 15 2024  2:30:45:123PM
    CONVERT(VARCHAR(10), @dt, 10) AS Style10,   -- 06-15-24
    CONVERT(VARCHAR(10), @dt, 110) AS Style110, -- 06-15-2024
    CONVERT(VARCHAR(10), @dt, 11) AS Style11,   -- 24/06/15
    CONVERT(VARCHAR(10), @dt, 111) AS Style111, -- 2024/06/15
    CONVERT(VARCHAR(8), @dt, 12) AS Style12,    -- 240615
    CONVERT(VARCHAR(8), @dt, 112) AS Style112,  -- 20240615
    CONVERT(VARCHAR(24), @dt, 13) AS Style13,   -- 15 Jun 2024 14:30:45:123
    CONVERT(VARCHAR(24), @dt, 113) AS Style113; -- 15 Jun 2024 14:30:45:123
GO

-- Pattern 9: CONVERT ISO and ODBC styles
DECLARE @dt DATETIME2 = '2024-06-15 14:30:45.1234567';

SELECT 
    CONVERT(VARCHAR(19), @dt, 20) AS Style20,   -- 2024-06-15 14:30:45
    CONVERT(VARCHAR(19), @dt, 120) AS Style120, -- 2024-06-15 14:30:45
    CONVERT(VARCHAR(23), @dt, 21) AS Style21,   -- 2024-06-15 14:30:45.123
    CONVERT(VARCHAR(23), @dt, 121) AS Style121, -- 2024-06-15 14:30:45.123
    CONVERT(VARCHAR(30), @dt, 126) AS Style126, -- 2024-06-15T14:30:45.1234567
    CONVERT(VARCHAR(34), @dt, 127) AS Style127; -- 2024-06-15T14:30:45.1234567Z
GO

-- Pattern 10: CONVERT with binary styles
SELECT 
    CONVERT(VARBINARY(20), 'Hello', 0) AS Style0,  -- Direct conversion
    CONVERT(VARCHAR(20), 0x48656C6C6F, 0) AS FromBin0,
    CONVERT(VARCHAR(20), 0x48656C6C6F, 1) AS FromBin1, -- With 0x prefix
    CONVERT(VARCHAR(20), 0x48656C6C6F, 2) AS FromBin2; -- Without prefix
GO

-- Pattern 11: TRY_CAST - safe conversion
SELECT 
    TRY_CAST('123' AS INT) AS ValidInt,
    TRY_CAST('abc' AS INT) AS InvalidInt,
    TRY_CAST('2024-06-15' AS DATE) AS ValidDate,
    TRY_CAST('not a date' AS DATE) AS InvalidDate,
    TRY_CAST('123.456' AS DECIMAL(10,2)) AS ValidDecimal,
    TRY_CAST('12.34.56' AS DECIMAL(10,2)) AS InvalidDecimal;
GO

-- Pattern 12: TRY_CONVERT - safe conversion with style
SELECT 
    TRY_CONVERT(INT, '123') AS ValidInt,
    TRY_CONVERT(INT, 'abc') AS InvalidInt,
    TRY_CONVERT(DATE, '06/15/2024', 101) AS ValidUSDate,
    TRY_CONVERT(DATE, '15/06/2024', 103) AS ValidUKDate,
    TRY_CONVERT(DATE, 'invalid', 101) AS InvalidDate;
GO

-- Pattern 13: PARSE with culture
SELECT 
    PARSE('06/15/2024' AS DATE USING 'en-US') AS USDate,
    PARSE('15/06/2024' AS DATE USING 'en-GB') AS UKDate,
    PARSE('15 juin 2024' AS DATE USING 'fr-FR') AS FrenchDate,
    PARSE('15. Juni 2024' AS DATE USING 'de-DE') AS GermanDate,
    PARSE('$1,234.56' AS MONEY USING 'en-US') AS USMoney,
    PARSE('1.234,56 €' AS MONEY USING 'de-DE') AS GermanMoney;
GO

-- Pattern 14: TRY_PARSE - safe culture-aware parsing
SELECT 
    TRY_PARSE('06/15/2024' AS DATE USING 'en-US') AS ValidUSDate,
    TRY_PARSE('not a date' AS DATE USING 'en-US') AS InvalidDate,
    TRY_PARSE('$1,234.56' AS MONEY USING 'en-US') AS ValidMoney,
    TRY_PARSE('invalid' AS MONEY USING 'en-US') AS InvalidMoney;
GO

-- Pattern 15: Nested conversions
SELECT 
    CAST(CAST(CAST(123.456 AS INT) AS VARCHAR(10)) AS INT) AS MultiCast,
    CONVERT(VARCHAR(10), CONVERT(DATE, '2024-06-15'), 101) AS DateConvert;
GO

-- Pattern 16: CONVERT in expressions
SELECT 
    ProductID,
    ProductName,
    'Price: $' + CONVERT(VARCHAR(20), Price, 1) AS FormattedPrice,
    'Stock: ' + CAST(StockQuantity AS VARCHAR(10)) + ' units' AS StockInfo
FROM dbo.Products;
GO

-- Pattern 17: Conversion in WHERE clause
SELECT ProductID, ProductName, Price
FROM dbo.Products
WHERE TRY_CAST(Price AS INT) > 100;
GO

-- Pattern 18: CONVERT with XML
DECLARE @xml XML = '<root><item>value</item></root>';

SELECT 
    CONVERT(VARCHAR(MAX), @xml) AS XmlToString,
    CONVERT(XML, '<data>test</data>') AS StringToXml;
GO

-- Pattern 19: Conversion between date/time types
DECLARE @dt DATETIME2 = '2024-06-15 14:30:45.1234567';

SELECT 
    CAST(@dt AS DATE) AS ToDate,
    CAST(@dt AS TIME) AS ToTime,
    CAST(@dt AS DATETIME) AS ToDateTime,
    CAST(@dt AS SMALLDATETIME) AS ToSmallDateTime,
    CAST(CAST(@dt AS DATE) AS DATETIME2) AS DateToDateTime2;
GO

-- Pattern 20: Unicode conversion
SELECT 
    CAST('ASCII' AS NVARCHAR(20)) AS AsciiToUnicode,
    CAST(N'Unicode' AS VARCHAR(20)) AS UnicodeToAscii,
    NCHAR(26085) + NCHAR(26412) AS UnicodeChars,
    UNICODE(N'日') AS CharToCode;
GO
