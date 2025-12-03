-- Sample 023: String Parsing and Manipulation Procedures
-- Source: Various - Stack Overflow, MSSQLTips, Jeff Moden articles
-- Category: Data Validation
-- Complexity: Complex
-- Features: STRING_SPLIT, STRING_AGG, PARSENAME, CTEs for parsing, regex-like patterns

-- Split delimited string with position tracking
CREATE FUNCTION dbo.SplitStringWithPosition
(
    @String NVARCHAR(MAX),
    @Delimiter NVARCHAR(10)
)
RETURNS @Result TABLE (
    Position INT,
    Value NVARCHAR(MAX)
)
AS
BEGIN
    ;WITH Splitter AS (
        SELECT 
            1 AS Position,
            CASE 
                WHEN CHARINDEX(@Delimiter, @String) > 0 
                THEN LEFT(@String, CHARINDEX(@Delimiter, @String) - 1)
                ELSE @String
            END AS Value,
            CASE 
                WHEN CHARINDEX(@Delimiter, @String) > 0 
                THEN SUBSTRING(@String, CHARINDEX(@Delimiter, @String) + LEN(@Delimiter), LEN(@String))
                ELSE ''
            END AS Remainder
        
        UNION ALL
        
        SELECT 
            Position + 1,
            CASE 
                WHEN CHARINDEX(@Delimiter, Remainder) > 0 
                THEN LEFT(Remainder, CHARINDEX(@Delimiter, Remainder) - 1)
                ELSE Remainder
            END,
            CASE 
                WHEN CHARINDEX(@Delimiter, Remainder) > 0 
                THEN SUBSTRING(Remainder, CHARINDEX(@Delimiter, Remainder) + LEN(@Delimiter), LEN(Remainder))
                ELSE ''
            END
        FROM Splitter
        WHERE Remainder <> ''
    )
    INSERT INTO @Result (Position, Value)
    SELECT Position, Value
    FROM Splitter
    OPTION (MAXRECURSION 1000);
    
    RETURN;
END
GO

-- Parse name into components
CREATE PROCEDURE dbo.ParseFullName
    @FullName NVARCHAR(200),
    @FirstName NVARCHAR(100) OUTPUT,
    @MiddleName NVARCHAR(100) OUTPUT,
    @LastName NVARCHAR(100) OUTPUT,
    @Suffix NVARCHAR(20) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @NameParts TABLE (Position INT, Part NVARCHAR(100));
    DECLARE @PartCount INT;
    DECLARE @CleanName NVARCHAR(200);
    
    -- Common suffixes
    DECLARE @Suffixes TABLE (Suffix NVARCHAR(20));
    INSERT INTO @Suffixes VALUES ('Jr'), ('Jr.'), ('Sr'), ('Sr.'), 
        ('II'), ('III'), ('IV'), ('MD'), ('M.D.'), ('PhD'), ('Ph.D.');
    
    -- Clean and normalize
    SET @CleanName = LTRIM(RTRIM(@FullName));
    SET @CleanName = REPLACE(@CleanName, '  ', ' ');  -- Double spaces
    
    -- Check for suffix
    SET @Suffix = NULL;
    IF EXISTS (
        SELECT 1 FROM @Suffixes 
        WHERE @CleanName LIKE '% ' + Suffix 
           OR @CleanName LIKE '%,' + Suffix
           OR @CleanName LIKE '%, ' + Suffix
    )
    BEGIN
        SELECT TOP 1 @Suffix = Suffix
        FROM @Suffixes
        WHERE @CleanName LIKE '% ' + Suffix 
           OR @CleanName LIKE '%,' + Suffix
           OR @CleanName LIKE '%, ' + Suffix;
        
        SET @CleanName = RTRIM(LEFT(@CleanName, 
            LEN(@CleanName) - LEN(@Suffix) - 
            CASE WHEN @CleanName LIKE '%, %' THEN 2 
                 WHEN @CleanName LIKE '%,%' THEN 1 
                 ELSE 1 END));
    END
    
    -- Split into parts
    INSERT INTO @NameParts (Position, Part)
    SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)), value
    FROM STRING_SPLIT(@CleanName, ' ')
    WHERE LTRIM(RTRIM(value)) <> '';
    
    SELECT @PartCount = COUNT(*) FROM @NameParts;
    
    -- Assign based on part count
    IF @PartCount = 1
    BEGIN
        SELECT @FirstName = Part FROM @NameParts WHERE Position = 1;
        SET @MiddleName = NULL;
        SET @LastName = NULL;
    END
    ELSE IF @PartCount = 2
    BEGIN
        SELECT @FirstName = Part FROM @NameParts WHERE Position = 1;
        SET @MiddleName = NULL;
        SELECT @LastName = Part FROM @NameParts WHERE Position = 2;
    END
    ELSE IF @PartCount >= 3
    BEGIN
        SELECT @FirstName = Part FROM @NameParts WHERE Position = 1;
        
        -- Middle name(s) - everything between first and last
        SELECT @MiddleName = STRING_AGG(Part, ' ') WITHIN GROUP (ORDER BY Position)
        FROM @NameParts 
        WHERE Position > 1 AND Position < @PartCount;
        
        SELECT @LastName = Part FROM @NameParts WHERE Position = @PartCount;
    END
END
GO

-- Parse and validate email address
CREATE FUNCTION dbo.ParseEmail
(
    @Email NVARCHAR(254)
)
RETURNS TABLE
AS
RETURN
(
    SELECT 
        @Email AS OriginalEmail,
        CASE 
            WHEN @Email IS NULL THEN 0
            WHEN @Email NOT LIKE '%_@__%.__%' THEN 0
            WHEN @Email LIKE '%@%@%' THEN 0
            WHEN @Email LIKE '%.@%' THEN 0
            WHEN @Email LIKE '%@.%' THEN 0
            WHEN @Email LIKE '%..%' THEN 0
            WHEN @Email LIKE '% %' THEN 0
            ELSE 1
        END AS IsValid,
        LEFT(@Email, CHARINDEX('@', @Email) - 1) AS LocalPart,
        SUBSTRING(@Email, CHARINDEX('@', @Email) + 1, LEN(@Email)) AS Domain,
        REVERSE(PARSENAME(REVERSE(SUBSTRING(@Email, CHARINDEX('@', @Email) + 1, LEN(@Email))), 1)) AS TopLevelDomain
);
GO

-- Extract key-value pairs from delimited string
CREATE FUNCTION dbo.ParseKeyValuePairs
(
    @Input NVARCHAR(MAX),
    @PairDelimiter NVARCHAR(5) = ';',
    @KeyValueDelimiter NVARCHAR(5) = '='
)
RETURNS @Result TABLE (
    KeyName NVARCHAR(255),
    KeyValue NVARCHAR(MAX)
)
AS
BEGIN
    INSERT INTO @Result (KeyName, KeyValue)
    SELECT 
        LTRIM(RTRIM(LEFT(value, CHARINDEX(@KeyValueDelimiter, value) - 1))) AS KeyName,
        LTRIM(RTRIM(SUBSTRING(value, CHARINDEX(@KeyValueDelimiter, value) + 1, LEN(value)))) AS KeyValue
    FROM STRING_SPLIT(@Input, @PairDelimiter)
    WHERE value LIKE '%' + @KeyValueDelimiter + '%';
    
    RETURN;
END
GO

-- Parse CSV line respecting quoted fields
CREATE FUNCTION dbo.ParseCSVLine
(
    @Line NVARCHAR(MAX),
    @Delimiter NVARCHAR(1) = ','
)
RETURNS @Result TABLE (
    FieldNumber INT,
    FieldValue NVARCHAR(MAX)
)
AS
BEGIN
    DECLARE @Position INT = 1;
    DECLARE @Length INT = LEN(@Line);
    DECLARE @FieldNum INT = 1;
    DECLARE @InQuotes BIT = 0;
    DECLARE @FieldStart INT = 1;
    DECLARE @CurrentChar NCHAR(1);
    DECLARE @FieldValue NVARCHAR(MAX);
    
    WHILE @Position <= @Length + 1
    BEGIN
        IF @Position <= @Length
            SET @CurrentChar = SUBSTRING(@Line, @Position, 1);
        ELSE
            SET @CurrentChar = @Delimiter;  -- Treat end as delimiter
        
        IF @CurrentChar = '"' AND @InQuotes = 0
            SET @InQuotes = 1;
        ELSE IF @CurrentChar = '"' AND @InQuotes = 1
        BEGIN
            -- Check for escaped quote
            IF @Position < @Length AND SUBSTRING(@Line, @Position + 1, 1) = '"'
                SET @Position = @Position + 1;  -- Skip escaped quote
            ELSE
                SET @InQuotes = 0;
        END
        ELSE IF @CurrentChar = @Delimiter AND @InQuotes = 0
        BEGIN
            -- Extract field value
            SET @FieldValue = SUBSTRING(@Line, @FieldStart, @Position - @FieldStart);
            
            -- Remove surrounding quotes if present
            IF LEFT(@FieldValue, 1) = '"' AND RIGHT(@FieldValue, 1) = '"'
                SET @FieldValue = SUBSTRING(@FieldValue, 2, LEN(@FieldValue) - 2);
            
            -- Unescape doubled quotes
            SET @FieldValue = REPLACE(@FieldValue, '""', '"');
            
            INSERT INTO @Result (FieldNumber, FieldValue)
            VALUES (@FieldNum, @FieldValue);
            
            SET @FieldNum = @FieldNum + 1;
            SET @FieldStart = @Position + 1;
        END
        
        SET @Position = @Position + 1;
    END
    
    RETURN;
END
GO

-- Format phone number
CREATE FUNCTION dbo.FormatPhoneNumber
(
    @PhoneNumber NVARCHAR(50),
    @Format NVARCHAR(20) = 'US'  -- US, INTL, DIGITS
)
RETURNS NVARCHAR(50)
AS
BEGIN
    DECLARE @Digits NVARCHAR(50);
    DECLARE @Result NVARCHAR(50);
    
    -- Extract only digits
    SET @Digits = '';
    
    ;WITH Nums AS (
        SELECT 1 AS n
        UNION ALL
        SELECT n + 1 FROM Nums WHERE n < LEN(@PhoneNumber)
    )
    SELECT @Digits = @Digits + SUBSTRING(@PhoneNumber, n, 1)
    FROM Nums
    WHERE SUBSTRING(@PhoneNumber, n, 1) LIKE '[0-9]'
    OPTION (MAXRECURSION 100);
    
    IF @Format = 'DIGITS'
        RETURN @Digits;
    
    -- Format based on length and format type
    IF LEN(@Digits) = 10 AND @Format = 'US'
        SET @Result = '(' + LEFT(@Digits, 3) + ') ' + 
                      SUBSTRING(@Digits, 4, 3) + '-' + 
                      RIGHT(@Digits, 4);
    ELSE IF LEN(@Digits) = 11 AND LEFT(@Digits, 1) = '1' AND @Format = 'US'
        SET @Result = '+1 (' + SUBSTRING(@Digits, 2, 3) + ') ' + 
                      SUBSTRING(@Digits, 5, 3) + '-' + 
                      RIGHT(@Digits, 4);
    ELSE IF @Format = 'INTL'
        SET @Result = '+' + @Digits;
    ELSE
        SET @Result = @Digits;
    
    RETURN @Result;
END
GO

-- Generate slug from text
CREATE FUNCTION dbo.GenerateSlug
(
    @Text NVARCHAR(500)
)
RETURNS NVARCHAR(500)
AS
BEGIN
    DECLARE @Slug NVARCHAR(500);
    
    -- Convert to lowercase
    SET @Slug = LOWER(@Text);
    
    -- Replace common special characters
    SET @Slug = REPLACE(@Slug, '&', 'and');
    SET @Slug = REPLACE(@Slug, '@', 'at');
    SET @Slug = REPLACE(@Slug, '%', 'percent');
    
    -- Replace accented characters
    SET @Slug = REPLACE(@Slug, 'á', 'a');
    SET @Slug = REPLACE(@Slug, 'é', 'e');
    SET @Slug = REPLACE(@Slug, 'í', 'i');
    SET @Slug = REPLACE(@Slug, 'ó', 'o');
    SET @Slug = REPLACE(@Slug, 'ú', 'u');
    SET @Slug = REPLACE(@Slug, 'ñ', 'n');
    
    -- Replace spaces and underscores with hyphens
    SET @Slug = REPLACE(@Slug, ' ', '-');
    SET @Slug = REPLACE(@Slug, '_', '-');
    
    -- Remove any character that's not alphanumeric or hyphen
    DECLARE @i INT = 1;
    DECLARE @Cleaned NVARCHAR(500) = '';
    DECLARE @Char NCHAR(1);
    
    WHILE @i <= LEN(@Slug)
    BEGIN
        SET @Char = SUBSTRING(@Slug, @i, 1);
        IF @Char LIKE '[a-z0-9-]'
            SET @Cleaned = @Cleaned + @Char;
        SET @i = @i + 1;
    END
    
    SET @Slug = @Cleaned;
    
    -- Remove multiple consecutive hyphens
    WHILE @Slug LIKE '%--%'
        SET @Slug = REPLACE(@Slug, '--', '-');
    
    -- Remove leading/trailing hyphens
    SET @Slug = TRIM('-' FROM @Slug);
    
    RETURN @Slug;
END
GO
