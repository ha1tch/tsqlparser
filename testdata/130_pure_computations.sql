-- Sample 130: Pure Computational Procedures
-- Category: Pure Logic (No System Dependencies)
-- Complexity: Advanced
-- Purpose: Interpreter testing - pure logic without external dependencies
-- Features: Mathematical algorithms, string manipulation, self-contained logic

-- Pattern 1: Fibonacci sequence generator
CREATE FUNCTION dbo.Fibonacci(@n INT)
RETURNS BIGINT
AS
BEGIN
    IF @n <= 0 RETURN 0;
    IF @n = 1 RETURN 1;
    
    DECLARE @a BIGINT = 0, @b BIGINT = 1, @temp BIGINT;
    DECLARE @i INT = 2;
    
    WHILE @i <= @n
    BEGIN
        SET @temp = @a + @b;
        SET @a = @b;
        SET @b = @temp;
        SET @i = @i + 1;
    END
    
    RETURN @b;
END;
GO

-- Pattern 2: Prime number checker
CREATE FUNCTION dbo.IsPrime(@n BIGINT)
RETURNS BIT
AS
BEGIN
    IF @n < 2 RETURN 0;
    IF @n = 2 RETURN 1;
    IF @n % 2 = 0 RETURN 0;
    
    DECLARE @i BIGINT = 3;
    DECLARE @sqrt BIGINT = CAST(SQRT(CAST(@n AS FLOAT)) AS BIGINT) + 1;
    
    WHILE @i <= @sqrt
    BEGIN
        IF @n % @i = 0 RETURN 0;
        SET @i = @i + 2;
    END
    
    RETURN 1;
END;
GO

-- Pattern 3: Greatest Common Divisor (Euclidean algorithm)
CREATE FUNCTION dbo.GCD(@a BIGINT, @b BIGINT)
RETURNS BIGINT
AS
BEGIN
    SET @a = ABS(@a);
    SET @b = ABS(@b);
    
    WHILE @b <> 0
    BEGIN
        DECLARE @temp BIGINT = @b;
        SET @b = @a % @b;
        SET @a = @temp;
    END
    
    RETURN @a;
END;
GO

-- Pattern 4: Least Common Multiple
CREATE FUNCTION dbo.LCM(@a BIGINT, @b BIGINT)
RETURNS BIGINT
AS
BEGIN
    IF @a = 0 OR @b = 0 RETURN 0;
    RETURN ABS(@a * @b) / dbo.GCD(@a, @b);
END;
GO

-- Pattern 5: Factorial (iterative)
CREATE FUNCTION dbo.Factorial(@n INT)
RETURNS BIGINT
AS
BEGIN
    IF @n < 0 RETURN NULL;
    IF @n <= 1 RETURN 1;
    
    DECLARE @result BIGINT = 1;
    DECLARE @i INT = 2;
    
    WHILE @i <= @n
    BEGIN
        SET @result = @result * @i;
        SET @i = @i + 1;
    END
    
    RETURN @result;
END;
GO

-- Pattern 6: Decimal to Binary converter
CREATE FUNCTION dbo.DecimalToBinary(@n BIGINT)
RETURNS VARCHAR(64)
AS
BEGIN
    IF @n = 0 RETURN '0';
    
    DECLARE @result VARCHAR(64) = '';
    DECLARE @isNegative BIT = CASE WHEN @n < 0 THEN 1 ELSE 0 END;
    SET @n = ABS(@n);
    
    WHILE @n > 0
    BEGIN
        SET @result = CAST(@n % 2 AS CHAR(1)) + @result;
        SET @n = @n / 2;
    END
    
    IF @isNegative = 1
        SET @result = '-' + @result;
    
    RETURN @result;
END;
GO

-- Pattern 7: String reversal
CREATE FUNCTION dbo.ReverseString(@input NVARCHAR(MAX))
RETURNS NVARCHAR(MAX)
AS
BEGIN
    DECLARE @result NVARCHAR(MAX) = '';
    DECLARE @i INT = LEN(@input);
    
    WHILE @i > 0
    BEGIN
        SET @result = @result + SUBSTRING(@input, @i, 1);
        SET @i = @i - 1;
    END
    
    RETURN @result;
END;
GO

-- Pattern 8: Palindrome checker
CREATE FUNCTION dbo.IsPalindrome(@input NVARCHAR(MAX))
RETURNS BIT
AS
BEGIN
    -- Remove non-alphanumeric and convert to lower
    DECLARE @cleaned NVARCHAR(MAX) = '';
    DECLARE @i INT = 1;
    DECLARE @char NCHAR(1);
    
    WHILE @i <= LEN(@input)
    BEGIN
        SET @char = LOWER(SUBSTRING(@input, @i, 1));
        IF @char LIKE '[a-z0-9]'
            SET @cleaned = @cleaned + @char;
        SET @i = @i + 1;
    END
    
    -- Check palindrome
    DECLARE @len INT = LEN(@cleaned);
    SET @i = 1;
    WHILE @i <= @len / 2
    BEGIN
        IF SUBSTRING(@cleaned, @i, 1) <> SUBSTRING(@cleaned, @len - @i + 1, 1)
            RETURN 0;
        SET @i = @i + 1;
    END
    
    RETURN 1;
END;
GO

-- Pattern 9: Luhn algorithm (credit card validation)
CREATE FUNCTION dbo.LuhnCheck(@number VARCHAR(20))
RETURNS BIT
AS
BEGIN
    -- Remove spaces and dashes
    SET @number = REPLACE(REPLACE(@number, ' ', ''), '-', '');
    
    IF @number LIKE '%[^0-9]%' RETURN 0;  -- Non-digit found
    
    DECLARE @sum INT = 0;
    DECLARE @i INT = LEN(@number);
    DECLARE @doubleIt BIT = 0;
    DECLARE @digit INT;
    
    WHILE @i > 0
    BEGIN
        SET @digit = CAST(SUBSTRING(@number, @i, 1) AS INT);
        
        IF @doubleIt = 1
        BEGIN
            SET @digit = @digit * 2;
            IF @digit > 9
                SET @digit = @digit - 9;
        END
        
        SET @sum = @sum + @digit;
        SET @doubleIt = 1 - @doubleIt;  -- Toggle
        SET @i = @i - 1;
    END
    
    RETURN CASE WHEN @sum % 10 = 0 THEN 1 ELSE 0 END;
END;
GO

-- Pattern 10: Base conversion
CREATE FUNCTION dbo.ConvertBase(@value VARCHAR(100), @fromBase INT, @toBase INT)
RETURNS VARCHAR(100)
AS
BEGIN
    IF @fromBase < 2 OR @fromBase > 36 OR @toBase < 2 OR @toBase > 36
        RETURN NULL;
    
    DECLARE @digits VARCHAR(36) = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    DECLARE @decimal BIGINT = 0;
    DECLARE @i INT = 1;
    DECLARE @char CHAR(1);
    DECLARE @digitValue INT;
    
    -- Convert to decimal
    SET @value = UPPER(@value);
    WHILE @i <= LEN(@value)
    BEGIN
        SET @char = SUBSTRING(@value, @i, 1);
        SET @digitValue = CHARINDEX(@char, @digits) - 1;
        IF @digitValue < 0 OR @digitValue >= @fromBase RETURN NULL;
        SET @decimal = @decimal * @fromBase + @digitValue;
        SET @i = @i + 1;
    END
    
    -- Convert from decimal
    IF @decimal = 0 RETURN '0';
    
    DECLARE @result VARCHAR(100) = '';
    WHILE @decimal > 0
    BEGIN
        SET @result = SUBSTRING(@digits, (@decimal % @toBase) + 1, 1) + @result;
        SET @decimal = @decimal / @toBase;
    END
    
    RETURN @result;
END;
GO

-- Pattern 11: Simple interest calculator
CREATE FUNCTION dbo.SimpleInterest(@principal DECIMAL(18,2), @rate DECIMAL(10,4), @years DECIMAL(10,2))
RETURNS DECIMAL(18,2)
AS
BEGIN
    RETURN @principal * @rate * @years / 100;
END;
GO

-- Pattern 12: Compound interest calculator
CREATE FUNCTION dbo.CompoundInterest(
    @principal DECIMAL(18,2), 
    @rate DECIMAL(10,4), 
    @years DECIMAL(10,2),
    @compoundingPerYear INT
)
RETURNS DECIMAL(18,2)
AS
BEGIN
    RETURN @principal * POWER(1 + @rate / 100.0 / @compoundingPerYear, @compoundingPerYear * @years) - @principal;
END;
GO

-- Pattern 13: Levenshtein distance (edit distance)
CREATE FUNCTION dbo.LevenshteinDistance(@s1 NVARCHAR(100), @s2 NVARCHAR(100))
RETURNS INT
AS
BEGIN
    DECLARE @len1 INT = LEN(@s1);
    DECLARE @len2 INT = LEN(@s2);
    
    IF @len1 = 0 RETURN @len2;
    IF @len2 = 0 RETURN @len1;
    
    -- Use simple O(n*m) algorithm with variables (limited size)
    DECLARE @i INT, @j INT;
    DECLARE @cost INT;
    DECLARE @prev INT, @curr INT;
    DECLARE @row TABLE (j INT, val INT);
    
    -- Initialize first row
    SET @j = 0;
    WHILE @j <= @len2
    BEGIN
        INSERT INTO @row VALUES (@j, @j);
        SET @j = @j + 1;
    END
    
    SET @i = 1;
    WHILE @i <= @len1
    BEGIN
        SET @prev = @i;
        UPDATE @row SET val = @i WHERE j = 0;
        
        SET @j = 1;
        WHILE @j <= @len2
        BEGIN
            SET @cost = CASE WHEN SUBSTRING(@s1, @i, 1) = SUBSTRING(@s2, @j, 1) THEN 0 ELSE 1 END;
            
            SELECT @curr = val FROM @row WHERE j = @j - 1;
            DECLARE @above INT;
            SELECT @above = val FROM @row WHERE j = @j;
            
            SET @curr = (
                SELECT MIN(v) FROM (VALUES (@curr + 1), (@above + 1), (@prev + @cost)) AS T(v)
            );
            
            SET @prev = @above;
            UPDATE @row SET val = @curr WHERE j = @j;
            SET @j = @j + 1;
        END
        SET @i = @i + 1;
    END
    
    SELECT @curr = val FROM @row WHERE j = @len2;
    RETURN @curr;
END;
GO

-- Pattern 14: Temperature conversion
CREATE FUNCTION dbo.ConvertTemperature(@value DECIMAL(10,2), @fromUnit CHAR(1), @toUnit CHAR(1))
RETURNS DECIMAL(10,2)
AS
BEGIN
    DECLARE @celsius DECIMAL(10,2);
    
    -- Convert to Celsius first
    SET @celsius = CASE @fromUnit
        WHEN 'C' THEN @value
        WHEN 'F' THEN (@value - 32) * 5.0 / 9.0
        WHEN 'K' THEN @value - 273.15
        ELSE NULL
    END;
    
    IF @celsius IS NULL RETURN NULL;
    
    -- Convert from Celsius to target
    RETURN CASE @toUnit
        WHEN 'C' THEN @celsius
        WHEN 'F' THEN @celsius * 9.0 / 5.0 + 32
        WHEN 'K' THEN @celsius + 273.15
        ELSE NULL
    END;
END;
GO

-- Pattern 15: ROT13 cipher
CREATE FUNCTION dbo.ROT13(@input NVARCHAR(MAX))
RETURNS NVARCHAR(MAX)
AS
BEGIN
    DECLARE @result NVARCHAR(MAX) = '';
    DECLARE @i INT = 1;
    DECLARE @char NCHAR(1);
    DECLARE @code INT;
    
    WHILE @i <= LEN(@input)
    BEGIN
        SET @char = SUBSTRING(@input, @i, 1);
        SET @code = ASCII(@char);
        
        IF @code BETWEEN 65 AND 90  -- A-Z
            SET @char = CHAR((((@code - 65) + 13) % 26) + 65);
        ELSE IF @code BETWEEN 97 AND 122  -- a-z
            SET @char = CHAR((((@code - 97) + 13) % 26) + 97);
        
        SET @result = @result + @char;
        SET @i = @i + 1;
    END
    
    RETURN @result;
END;
GO

-- Test the functions
SELECT dbo.Fibonacci(10) AS Fib10;  -- 55
SELECT dbo.IsPrime(17) AS IsPrime17;  -- 1
SELECT dbo.GCD(48, 18) AS GCD;  -- 6
SELECT dbo.Factorial(5) AS Factorial5;  -- 120
SELECT dbo.DecimalToBinary(42) AS Binary42;  -- 101010
SELECT dbo.IsPalindrome('A man, a plan, a canal: Panama') AS IsPalindrome;  -- 1
SELECT dbo.LuhnCheck('4532015112830366') AS ValidCard;  -- 1
SELECT dbo.ConvertBase('FF', 16, 10) AS HexToDecimal;  -- 255
SELECT dbo.ROT13('Hello World') AS ROT13;  -- Uryyb Jbeyq
GO
