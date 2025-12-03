-- Sample 134: String Functions Comprehensive Coverage
-- Category: Pure Logic / Syntax Coverage
-- Complexity: Complex
-- Purpose: Parser testing - all string functions
-- Features: All T-SQL string functions, patterns, edge cases

-- Pattern 1: Basic string functions
SELECT 
    'Hello World' AS Original,
    LEN('Hello World') AS Len,
    DATALENGTH('Hello World') AS DataLength,
    LEFT('Hello World', 5) AS LeftFive,
    RIGHT('Hello World', 5) AS RightFive,
    SUBSTRING('Hello World', 7, 5) AS Substring,
    UPPER('Hello World') AS Upper,
    LOWER('Hello World') AS Lower;
GO

-- Pattern 2: Trimming functions
SELECT 
    '   Hello World   ' AS Original,
    LTRIM('   Hello World   ') AS LTrimmed,
    RTRIM('   Hello World   ') AS RTrimmed,
    TRIM('   Hello World   ') AS Trimmed,
    TRIM('x' FROM 'xxxHelloxxWorldxxx') AS TrimChar,
    TRIM(LEADING 'x' FROM 'xxxHello') AS TrimLeading,
    TRIM(TRAILING 'x' FROM 'Helloxxx') AS TrimTrailing,
    TRIM(BOTH 'x' FROM 'xxxHelloxxx') AS TrimBoth;
GO

-- Pattern 3: Search and position functions
SELECT 
    CHARINDEX('World', 'Hello World') AS CharIndexSimple,
    CHARINDEX('o', 'Hello World') AS CharIndexFirst,
    CHARINDEX('o', 'Hello World', 6) AS CharIndexFromPos,
    PATINDEX('%World%', 'Hello World') AS PatIndex,
    PATINDEX('%[0-9]%', 'ABC123DEF') AS PatIndexPattern;
GO

-- Pattern 4: Replace and translate
SELECT 
    REPLACE('Hello World', 'World', 'Universe') AS ReplaceSimple,
    REPLACE('aaa', 'a', 'bb') AS ReplaceExpand,
    REPLACE('Hello', 'l', '') AS ReplaceRemove,
    TRANSLATE('Hello 123', 'el13', 'EL!@') AS TranslateChars,
    STUFF('Hello World', 7, 5, 'Universe') AS StuffReplace,
    STUFF('Hello', 6, 0, ' World') AS StuffInsert;
GO

-- Pattern 5: Concatenation methods
SELECT 
    'Hello' + ' ' + 'World' AS PlusConcat,
    CONCAT('Hello', ' ', 'World') AS ConcatFunc,
    CONCAT_WS(' ', 'Hello', 'Beautiful', 'World') AS ConcatWithSep,
    CONCAT_WS(', ', 'One', NULL, 'Two', NULL, 'Three') AS ConcatWSNulls,
    'Hello' + NULL AS PlusNull,  -- Returns NULL
    CONCAT('Hello', NULL) AS ConcatNull;  -- Treats NULL as empty
GO

-- Pattern 6: Replication and padding
SELECT 
    REPLICATE('AB', 5) AS Replicate,
    REPLICATE('*', 20) AS Stars,
    SPACE(10) AS TenSpaces,
    '|' + SPACE(10) + '|' AS SpaceDemo;
GO

-- Pattern 7: ASCII and character functions
SELECT 
    ASCII('A') AS AsciiA,
    ASCII('a') AS Asciia,
    CHAR(65) AS Char65,
    CHAR(97) AS Char97,
    UNICODE(N'日') AS UnicodeJapanese,
    NCHAR(26085) AS NCharJapanese,
    CHAR(13) + CHAR(10) AS CRLF;
GO

-- Pattern 8: String conversion and formatting
SELECT 
    STR(123.456) AS StrDefault,
    STR(123.456, 10, 2) AS StrFormatted,
    FORMAT(12345.6789, 'N2') AS FormatNumber,
    FORMAT(12345.6789, 'C', 'en-US') AS FormatCurrency,
    FORMAT(GETDATE(), 'yyyy-MM-dd') AS FormatDate,
    FORMAT(GETDATE(), 'dddd, MMMM dd, yyyy') AS FormatDateLong,
    QUOTENAME('TableName') AS QuoteBrackets,
    QUOTENAME('TableName', '''') AS QuoteSingle,
    QUOTENAME('TableName', '"') AS QuoteDouble;
GO

-- Pattern 9: Reversal and soundex
SELECT 
    REVERSE('Hello World') AS Reversed,
    SOUNDEX('Smith') AS SoundexSmith,
    SOUNDEX('Smythe') AS SoundexSmythe,
    DIFFERENCE('Smith', 'Smythe') AS DifferenceScore;  -- 0-4, 4 = most similar
GO

-- Pattern 10: Unicode and special handling
SELECT 
    N'日本語テキスト' AS UnicodeText,
    LEN(N'日本語テキスト') AS UnicodeLen,
    DATALENGTH(N'日本語テキスト') AS UnicodeDataLen,
    NCHAR(0x65E5) + NCHAR(0x672C) AS ConstructedUnicode;
GO

-- Pattern 11: STRING_SPLIT function (SQL Server 2016+)
SELECT value AS SplitValue
FROM STRING_SPLIT('apple,banana,cherry,date', ',');
GO

SELECT value, ordinal
FROM STRING_SPLIT('one|two|three|four', '|', 1)  -- Enable ordinal (SQL Server 2022+)
ORDER BY ordinal;
GO

-- Pattern 12: STRING_AGG function
SELECT 
    CategoryID,
    STRING_AGG(ProductName, ', ') AS Products,
    STRING_AGG(ProductName, ' | ') WITHIN GROUP (ORDER BY ProductName) AS ProductsOrdered
FROM Products
GROUP BY CategoryID;
GO

-- Pattern 13: String comparison edge cases
SELECT 
    CASE WHEN '' = ' ' THEN 'Equal' ELSE 'Not Equal' END AS EmptyVsSpace,
    CASE WHEN 'abc' = 'ABC' THEN 'Equal' ELSE 'Not Equal' END AS CaseSensitivity,
    CASE WHEN 'abc ' = 'abc' THEN 'Equal' ELSE 'Not Equal' END AS TrailingSpace,
    LEN('abc ') AS LenWithTrailing,
    DATALENGTH('abc ') AS DataLenWithTrailing;
GO

-- Pattern 14: Complex pattern matching with LIKE
SELECT 
    'abc123' AS TestValue,
    CASE WHEN 'abc123' LIKE 'abc%' THEN 'Match' ELSE 'No' END AS StartsWithAbc,
    CASE WHEN 'abc123' LIKE '%123' THEN 'Match' ELSE 'No' END AS EndsWith123,
    CASE WHEN 'abc123' LIKE '%[0-9]%' THEN 'Match' ELSE 'No' END AS ContainsDigit,
    CASE WHEN 'abc123' LIKE '[a-z][a-z][a-z][0-9][0-9][0-9]' THEN 'Match' ELSE 'No' END AS ExactPattern,
    CASE WHEN 'abc123' LIKE '%[^a-z]%' THEN 'Match' ELSE 'No' END AS ContainsNonLetter,
    CASE WHEN '100%' LIKE '%[%]%' THEN 'Match' ELSE 'No' END AS ContainsPercent,
    CASE WHEN 'a_b' LIKE '%[_]%' THEN 'Match' ELSE 'No' END AS ContainsUnderscore;
GO

-- Pattern 15: LIKE with ESCAPE
SELECT 
    CASE WHEN '50% off' LIKE '%50!% off%' ESCAPE '!' THEN 'Match' ELSE 'No' END AS EscapedPercent,
    CASE WHEN 'file_name' LIKE '%file!_name%' ESCAPE '!' THEN 'Match' ELSE 'No' END AS EscapedUnderscore,
    CASE WHEN '[test]' LIKE '%![test!]%' ESCAPE '!' THEN 'Match' ELSE 'No' END AS EscapedBrackets;
GO

-- Pattern 16: NULL and empty string handling
SELECT 
    ISNULL(NULL, 'Default') AS IsNullResult,
    COALESCE(NULL, NULL, 'Fallback') AS CoalesceResult,
    NULLIF('', '') AS NullIfEmpty,
    NULLIF('value', 'value') AS NullIfSame,
    NULLIF('value1', 'value2') AS NullIfDifferent,
    IIF('' = '', 'Empty equals empty', 'Not equal') AS EmptyComparison,
    IIF(LEN('') = 0, 'Zero length', 'Has length') AS EmptyLength;
GO

-- Pattern 17: Multi-byte character handling
SELECT 
    N'Ä' AS Umlaut,
    LEN(N'Ä') AS UmlautLen,
    LEN(N'日') AS JapaneseLen,
    SUBSTRING(N'日本語', 1, 1) AS FirstJapanese,
    CHARINDEX(N'本', N'日本語') AS FindJapanese;
GO

-- Pattern 18: COMPRESS and DECOMPRESS (SQL Server 2016+)
SELECT 
    COMPRESS('This is a test string for compression') AS Compressed,
    CAST(DECOMPRESS(COMPRESS('This is a test string for compression')) AS VARCHAR(100)) AS Decompressed;
GO

-- Pattern 19: String functions in WHERE clause
SELECT ProductID, ProductName
FROM Products
WHERE 
    LEN(ProductName) > 10
    AND ProductName LIKE '[A-M]%'
    AND CHARINDEX(' ', ProductName) > 0
    AND UPPER(LEFT(ProductName, 1)) = LEFT(ProductName, 1);  -- Starts with uppercase
GO

-- Pattern 20: Complex string manipulation
SELECT 
    EmailAddress,
    LEFT(EmailAddress, CHARINDEX('@', EmailAddress) - 1) AS LocalPart,
    SUBSTRING(EmailAddress, CHARINDEX('@', EmailAddress) + 1, LEN(EmailAddress)) AS Domain,
    REVERSE(LEFT(REVERSE(EmailAddress), CHARINDEX('.', REVERSE(EmailAddress)) - 1)) AS TopLevelDomain
FROM (SELECT 'user.name@subdomain.example.com' AS EmailAddress) AS T;
GO
