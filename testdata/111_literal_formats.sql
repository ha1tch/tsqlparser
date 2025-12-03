-- Sample 111: Literal Formats and Edge Cases
-- Category: Syntax Edge Cases
-- Complexity: Complex
-- Purpose: Parser testing - all literal formats and edge cases
-- Features: Numeric, string, date, binary, hex literals, escape sequences

-- Pattern 1: Integer literal formats
SELECT 
    0 AS Zero,
    1 AS One,
    -1 AS NegativeOne,
    2147483647 AS MaxInt,
    -2147483648 AS MinInt,
    9223372036854775807 AS MaxBigInt,
    -9223372036854775808 AS MinBigInt,
    +42 AS ExplicitPositive,
    00042 AS LeadingZeros;
GO

-- Pattern 2: Decimal and float literal formats
SELECT 
    0.0 AS ZeroDecimal,
    .5 AS PointFive,
    0.5 AS ZeroPointFive,
    123.456 AS SimpleDecimal,
    -123.456 AS NegativeDecimal,
    123. AS TrailingDot,
    .123 AS LeadingDot,
    1E10 AS Scientific1,
    1e10 AS ScientificLower,
    1E+10 AS ScientificPlus,
    1E-10 AS ScientificMinus,
    -1.5E+10 AS NegativeScientific,
    1.23456789012345678901234567890 AS LongDecimal,
    0.00000000001 AS VerySmall,
    99999999999999999999.99 AS VeryLarge;
GO

-- Pattern 3: Money literal formats
SELECT 
    $0.00 AS ZeroMoney,
    $1.00 AS OneDollar,
    $1234.56 AS SimpleMoney,
    -$99.99 AS NegativeMoney,
    $1,234,567.89 AS CommaSeparated,
    $0.01 AS OneCent,
    $999999999999.9999 AS LargeMoney;
GO

-- Pattern 4: String literal edge cases
SELECT 
    '' AS EmptyString,
    ' ' AS SingleSpace,
    '   ' AS MultipleSpaces,
    'Hello' AS SimpleString,
    'It''s escaped' AS EscapedQuote,
    'Line1' + CHAR(13) + CHAR(10) + 'Line2' AS NewlineInString,
    'Tab:' + CHAR(9) + 'Value' AS TabInString,
    'He said "Hello"' AS DoubleQuotesInSingle,
    '''Multiple''Quotes''' AS MultipleEscapedQuotes,
    REPLICATE('A', 8000) AS MaxVarchar,
    '	' AS TabCharacter,  -- Actual tab
    '
' AS ActualNewline;  -- Actual newline
GO

-- Pattern 5: Unicode string literals
SELECT 
    N'' AS EmptyNvarchar,
    N'Unicode string' AS SimpleNvarchar,
    N'It''s escaped' AS EscapedNvarchar,
    N'日本語' AS JapaneseText,
    N'Кириллица' AS CyrillicText,
    N'Emoji: 😀🎉🚀' AS EmojiText,
    N'Mixed: Hello 世界' AS MixedText,
    N'Special: ™®©' AS SpecialSymbols,
    N'Math: ∑∏∫√' AS MathSymbols;
GO

-- Pattern 6: Date and time literal formats
SELECT 
    '2024-01-15' AS ISODate,
    '20240115' AS UnseparatedDate,
    '01/15/2024' AS USDate,
    '15/01/2024' AS EuroDate,
    '2024-01-15 14:30:00' AS DateTimeISO,
    '2024-01-15T14:30:00' AS DateTimeT,
    '2024-01-15 14:30:00.123' AS DateTimeMillis,
    '2024-01-15 14:30:00.1234567' AS DateTime2Precision,
    '14:30:00' AS TimeOnly,
    '14:30:00.1234567' AS TimeWithPrecision,
    '2024-01-15 14:30:00.000 +05:30' AS DateTimeOffset,
    '2024-01-15T14:30:00.0000000+00:00' AS DateTimeOffsetISO;
GO

-- Pattern 7: Binary and hexadecimal literals
SELECT 
    0x AS EmptyBinary,
    0x00 AS ZeroBinary,
    0xFF AS MaxByte,
    0x0123456789ABCDEF AS HexUpper,
    0x0123456789abcdef AS HexLower,
    0x0123456789AbCdEf AS HexMixed,
    0x00000000 AS FourByteZero,
    0xDEADBEEF AS DeadBeef,
    0x48454C4C4F AS HelloHex,  -- "HELLO" in ASCII
    CAST(0x48454C4C4F AS VARCHAR(5)) AS HexToString;
GO

-- Pattern 8: GUID/Uniqueidentifier literals
SELECT 
    '00000000-0000-0000-0000-000000000000' AS EmptyGuid,
    'FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF' AS MaxGuid,
    '12345678-1234-1234-1234-123456789012' AS SampleGuid,
    NEWID() AS RandomGuid,
    '{12345678-1234-1234-1234-123456789012}' AS GuidWithBraces,
    '12345678123412341234123456789012' AS GuidNoDashes;
GO

-- Pattern 9: Bit literals
SELECT 
    CAST(1 AS BIT) AS TrueBit,
    CAST(0 AS BIT) AS FalseBit,
    CAST('TRUE' AS BIT) AS TrueString,
    CAST('FALSE' AS BIT) AS FalseString;
GO

-- Pattern 10: NULL literal variations
SELECT 
    NULL AS SimpleNull,
    CAST(NULL AS INT) AS NullInt,
    CAST(NULL AS VARCHAR(100)) AS NullVarchar,
    CAST(NULL AS DATETIME) AS NullDatetime,
    CAST(NULL AS DECIMAL(18,2)) AS NullDecimal,
    COALESCE(NULL, NULL, NULL, 'default') AS CoalesceNulls,
    NULLIF(1, 1) AS NullIfEqual,
    ISNULL(NULL, 0) AS IsNullDefault;
GO

-- Pattern 11: Escape sequences in strings
SELECT 
    'Backslash: \\' AS Backslash,
    'Percent: 100%' AS Percent,
    'Underscore: _test_' AS Underscore,
    'Brackets: [test]' AS Brackets,
    'Quote: ''' AS SingleQuote,
    'Tab' + CHAR(9) + 'After' AS TabEscape,
    'CR' + CHAR(13) + 'After' AS CRAfter,
    'LF' + CHAR(10) + 'After' AS LFAfter,
    'CRLF' + CHAR(13) + CHAR(10) + 'After' AS CRLFAfter;
GO

-- Pattern 12: Special numeric values
SELECT 
    CAST('INF' AS FLOAT) AS PositiveInfinity,
    CAST('-INF' AS FLOAT) AS NegativeInfinity,
    CAST('NaN' AS FLOAT) AS NotANumber,
    CAST(1.0 / 0.0 AS FLOAT) AS DivByZeroFloat,  -- Returns INF
    1.0 / 3.0 AS RepeatingDecimal,
    PI() AS PiValue,
    EXP(1) AS EulerNumber,
    SQRT(2) AS SquareRootTwo;
GO

-- Pattern 13: Collation specifications
SELECT 
    'abc' COLLATE Latin1_General_CI_AS AS CaseInsensitive,
    'abc' COLLATE Latin1_General_CS_AS AS CaseSensitive,
    'abc' COLLATE Latin1_General_BIN AS BinaryCollation,
    N'日本語' COLLATE Japanese_CI_AS AS JapaneseCollation,
    N'中文' COLLATE Chinese_PRC_CI_AS AS ChineseCollation;
GO

-- Pattern 14: XML literals
SELECT 
    CAST('<root/>' AS XML) AS EmptyElement,
    CAST('<root>text</root>' AS XML) AS SimpleElement,
    CAST('<root attr="value"/>' AS XML) AS WithAttribute,
    CAST('<root><child>data</child></root>' AS XML) AS Nested,
    CAST('<root xmlns="http://example.com">data</root>' AS XML) AS WithNamespace,
    CAST('<![CDATA[<not>parsed</not>]]>' AS VARCHAR(100)) AS CDATASection;
GO

-- Pattern 15: JSON literals (as strings)
SELECT 
    '{}' AS EmptyObject,
    '[]' AS EmptyArray,
    '{"key": "value"}' AS SimpleObject,
    '{"nested": {"key": "value"}}' AS NestedObject,
    '[1, 2, 3, 4, 5]' AS NumberArray,
    '{"array": [1, 2, 3]}' AS ObjectWithArray,
    '{"null": null, "bool": true, "number": 123.45}' AS MixedTypes;
GO

-- Pattern 16: Boundary values
SELECT 
    CAST(0.00001 AS DECIMAL(38,5)) AS SmallDecimal,
    CAST(99999999999999999999999999999999999999 AS DECIMAL(38,0)) AS MaxDecimal38,
    CAST(0.99999999999999999999999999999999999999 AS DECIMAL(38,38)) AS MaxPrecisionDecimal,
    DATEADD(YEAR, -1000, GETDATE()) AS VeryOldDate,
    DATEADD(YEAR, 1000, GETDATE()) AS VeryFutureDate,
    CAST('1753-01-01' AS DATETIME) AS MinDateTime,
    CAST('9999-12-31 23:59:59.997' AS DATETIME) AS MaxDateTime,
    CAST('0001-01-01' AS DATE) AS MinDate,
    CAST('9999-12-31' AS DATE) AS MaxDate;
GO
