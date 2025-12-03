-- Sample 065: Test Data Generation
-- Source: Various - Red Gate, MSSQLTips, Stack Overflow
-- Category: Data Validation
-- Complexity: Complex
-- Features: Random data generation, realistic test data, bulk generation

-- Generate random string
CREATE FUNCTION dbo.GenerateRandomString
(
    @Length INT,
    @CharSet NVARCHAR(100) = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
)
RETURNS NVARCHAR(MAX)
AS
BEGIN
    DECLARE @Result NVARCHAR(MAX) = '';
    DECLARE @CharSetLen INT = LEN(@CharSet);
    DECLARE @i INT = 1;
    
    WHILE @i <= @Length
    BEGIN
        SET @Result = @Result + SUBSTRING(@CharSet, ABS(CHECKSUM(NEWID())) % @CharSetLen + 1, 1);
        SET @i = @i + 1;
    END
    
    RETURN @Result;
END
GO

-- Generate random person data
CREATE PROCEDURE dbo.GeneratePersonData
    @Count INT = 1000
AS
BEGIN
    SET NOCOUNT ON;
    
    -- First names
    DECLARE @FirstNames TABLE (Name NVARCHAR(50));
    INSERT INTO @FirstNames VALUES 
        ('James'),('John'),('Robert'),('Michael'),('William'),('David'),('Richard'),('Joseph'),('Thomas'),('Charles'),
        ('Mary'),('Patricia'),('Jennifer'),('Linda'),('Elizabeth'),('Barbara'),('Susan'),('Jessica'),('Sarah'),('Karen'),
        ('Daniel'),('Matthew'),('Anthony'),('Mark'),('Donald'),('Steven'),('Paul'),('Andrew'),('Joshua'),('Kenneth'),
        ('Nancy'),('Betty'),('Margaret'),('Sandra'),('Ashley'),('Dorothy'),('Kimberly'),('Emily'),('Donna'),('Michelle');
    
    -- Last names
    DECLARE @LastNames TABLE (Name NVARCHAR(50));
    INSERT INTO @LastNames VALUES 
        ('Smith'),('Johnson'),('Williams'),('Brown'),('Jones'),('Garcia'),('Miller'),('Davis'),('Rodriguez'),('Martinez'),
        ('Hernandez'),('Lopez'),('Gonzalez'),('Wilson'),('Anderson'),('Thomas'),('Taylor'),('Moore'),('Jackson'),('Martin'),
        ('Lee'),('Perez'),('Thompson'),('White'),('Harris'),('Sanchez'),('Clark'),('Ramirez'),('Lewis'),('Robinson');
    
    -- Domains
    DECLARE @Domains TABLE (Domain NVARCHAR(50));
    INSERT INTO @Domains VALUES ('gmail.com'),('yahoo.com'),('outlook.com'),('hotmail.com'),('company.com'),('example.org');
    
    ;WITH Numbers AS (
        SELECT TOP (@Count) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS N
        FROM sys.all_columns a CROSS JOIN sys.all_columns b
    )
    SELECT 
        N AS PersonID,
        fn.Name AS FirstName,
        ln.Name AS LastName,
        fn.Name + ' ' + ln.Name AS FullName,
        LOWER(fn.Name + '.' + ln.Name + CAST(ABS(CHECKSUM(NEWID())) % 1000 AS VARCHAR(10)) + '@' + d.Domain) AS Email,
        '(' + RIGHT('000' + CAST(ABS(CHECKSUM(NEWID())) % 1000 AS VARCHAR(3)), 3) + ') ' +
        RIGHT('000' + CAST(ABS(CHECKSUM(NEWID())) % 1000 AS VARCHAR(3)), 3) + '-' +
        RIGHT('0000' + CAST(ABS(CHECKSUM(NEWID())) % 10000 AS VARCHAR(4)), 4) AS Phone,
        DATEADD(DAY, -ABS(CHECKSUM(NEWID())) % 25000, GETDATE()) AS BirthDate,
        CAST(ABS(CHECKSUM(NEWID())) % 200000 + 30000 AS DECIMAL(10,2)) AS Salary,
        CASE ABS(CHECKSUM(NEWID())) % 3 WHEN 0 THEN 'Active' WHEN 1 THEN 'Inactive' ELSE 'Pending' END AS Status
    FROM Numbers n
    CROSS APPLY (SELECT TOP 1 Name FROM @FirstNames ORDER BY NEWID()) fn
    CROSS APPLY (SELECT TOP 1 Name FROM @LastNames ORDER BY NEWID()) ln
    CROSS APPLY (SELECT TOP 1 Domain FROM @Domains ORDER BY NEWID()) d;
END
GO

-- Generate random orders data
CREATE PROCEDURE dbo.GenerateOrderData
    @CustomerCount INT = 100,
    @OrderCount INT = 1000,
    @StartDate DATE = '2020-01-01',
    @EndDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    SET @EndDate = ISNULL(@EndDate, GETDATE());
    
    DECLARE @DateRange INT = DATEDIFF(DAY, @StartDate, @EndDate);
    
    -- Products
    DECLARE @Products TABLE (ProductID INT, ProductName NVARCHAR(100), UnitPrice DECIMAL(10,2));
    INSERT INTO @Products VALUES 
        (1, 'Widget A', 19.99), (2, 'Widget B', 29.99), (3, 'Gadget X', 49.99),
        (4, 'Gadget Y', 79.99), (5, 'Tool Alpha', 99.99), (6, 'Tool Beta', 149.99),
        (7, 'Component 1', 9.99), (8, 'Component 2', 14.99), (9, 'Assembly Kit', 199.99),
        (10, 'Service Pack', 299.99);
    
    ;WITH Numbers AS (
        SELECT TOP (@OrderCount) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS N
        FROM sys.all_columns a CROSS JOIN sys.all_columns b
    )
    SELECT 
        N AS OrderID,
        ABS(CHECKSUM(NEWID())) % @CustomerCount + 1 AS CustomerID,
        DATEADD(DAY, ABS(CHECKSUM(NEWID())) % @DateRange, @StartDate) AS OrderDate,
        p.ProductID,
        p.ProductName,
        ABS(CHECKSUM(NEWID())) % 10 + 1 AS Quantity,
        p.UnitPrice,
        (ABS(CHECKSUM(NEWID())) % 10 + 1) * p.UnitPrice AS LineTotal,
        CASE ABS(CHECKSUM(NEWID())) % 5 
            WHEN 0 THEN 'Pending' 
            WHEN 1 THEN 'Processing' 
            WHEN 2 THEN 'Shipped' 
            WHEN 3 THEN 'Delivered'
            ELSE 'Completed' 
        END AS OrderStatus,
        CASE ABS(CHECKSUM(NEWID())) % 4
            WHEN 0 THEN 'Credit Card'
            WHEN 1 THEN 'PayPal'
            WHEN 2 THEN 'Bank Transfer'
            ELSE 'Cash'
        END AS PaymentMethod
    FROM Numbers n
    CROSS APPLY (SELECT TOP 1 * FROM @Products ORDER BY NEWID()) p;
END
GO

-- Populate table with generated data
CREATE PROCEDURE dbo.PopulateTableWithTestData
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @RowCount INT = 1000,
    @TruncateFirst BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @Columns NVARCHAR(MAX) = '';
    DECLARE @Values NVARCHAR(MAX) = '';
    DECLARE @FullPath NVARCHAR(256) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    
    -- Build column list and value generators
    SELECT @Columns = @Columns + QUOTENAME(c.name) + ', ',
           @Values = @Values + 
               CASE 
                   WHEN t.name IN ('int', 'bigint', 'smallint', 'tinyint') THEN 
                       'ABS(CHECKSUM(NEWID())) % 1000000'
                   WHEN t.name IN ('decimal', 'numeric', 'money', 'float', 'real') THEN 
                       'CAST(ABS(CHECKSUM(NEWID())) % 100000 / 100.0 AS ' + t.name + ')'
                   WHEN t.name IN ('varchar', 'nvarchar', 'char', 'nchar') THEN 
                       'LEFT(CAST(NEWID() AS VARCHAR(36)), ' + CAST(ISNULL(c.max_length / CASE WHEN t.name LIKE 'n%' THEN 2 ELSE 1 END, 10) AS VARCHAR(10)) + ')'
                   WHEN t.name IN ('datetime', 'datetime2', 'date') THEN 
                       'DATEADD(DAY, -ABS(CHECKSUM(NEWID())) % 3650, GETDATE())'
                   WHEN t.name = 'bit' THEN 
                       'ABS(CHECKSUM(NEWID())) % 2'
                   WHEN t.name = 'uniqueidentifier' THEN 
                       'NEWID()'
                   ELSE 'NULL'
               END + ', '
    FROM sys.columns c
    INNER JOIN sys.types t ON c.user_type_id = t.user_type_id
    WHERE c.object_id = OBJECT_ID(@FullPath)
      AND c.is_identity = 0
      AND c.is_computed = 0;
    
    SET @Columns = LEFT(@Columns, LEN(@Columns) - 1);
    SET @Values = LEFT(@Values, LEN(@Values) - 1);
    
    IF @TruncateFirst = 1
    BEGIN
        SET @SQL = 'TRUNCATE TABLE ' + @FullPath;
        EXEC sp_executesql @SQL;
    END
    
    SET @SQL = N'
        ;WITH Numbers AS (
            SELECT TOP (@Cnt) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS N
            FROM sys.all_columns a CROSS JOIN sys.all_columns b
        )
        INSERT INTO ' + @FullPath + ' (' + @Columns + ')
        SELECT ' + @Values + '
        FROM Numbers';
    
    EXEC sp_executesql @SQL, N'@Cnt INT', @Cnt = @RowCount;
    
    SELECT @RowCount AS RowsInserted, @FullPath AS TableName;
END
GO

-- Generate date dimension table
CREATE PROCEDURE dbo.GenerateDateDimension
    @StartDate DATE = '2010-01-01',
    @EndDate DATE = '2030-12-31',
    @TableName NVARCHAR(128) = 'DimDate'
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    
    -- Create table
    SET @SQL = N'
        IF OBJECT_ID(''dbo.' + @TableName + ''', ''U'') IS NOT NULL
            DROP TABLE dbo.' + QUOTENAME(@TableName) + ';
        
        CREATE TABLE dbo.' + QUOTENAME(@TableName) + ' (
            DateKey INT PRIMARY KEY,
            FullDate DATE NOT NULL,
            DayOfMonth TINYINT,
            DayName NVARCHAR(10),
            DayOfWeek TINYINT,
            DayOfYear SMALLINT,
            WeekOfYear TINYINT,
            MonthNumber TINYINT,
            MonthName NVARCHAR(10),
            Quarter TINYINT,
            Year SMALLINT,
            IsWeekend BIT,
            IsLeapYear BIT,
            FiscalYear SMALLINT,
            FiscalQuarter TINYINT
        )';
    EXEC sp_executesql @SQL;
    
    ;WITH DateSeries AS (
        SELECT @StartDate AS DateValue
        UNION ALL
        SELECT DATEADD(DAY, 1, DateValue)
        FROM DateSeries
        WHERE DateValue < @EndDate
    )
    INSERT INTO dbo.DimDate
    SELECT 
        CAST(FORMAT(DateValue, 'yyyyMMdd') AS INT) AS DateKey,
        DateValue AS FullDate,
        DAY(DateValue) AS DayOfMonth,
        DATENAME(WEEKDAY, DateValue) AS DayName,
        DATEPART(WEEKDAY, DateValue) AS DayOfWeek,
        DATEPART(DAYOFYEAR, DateValue) AS DayOfYear,
        DATEPART(WEEK, DateValue) AS WeekOfYear,
        MONTH(DateValue) AS MonthNumber,
        DATENAME(MONTH, DateValue) AS MonthName,
        DATEPART(QUARTER, DateValue) AS Quarter,
        YEAR(DateValue) AS Year,
        CASE WHEN DATEPART(WEEKDAY, DateValue) IN (1, 7) THEN 1 ELSE 0 END AS IsWeekend,
        CASE WHEN (YEAR(DateValue) % 4 = 0 AND YEAR(DateValue) % 100 <> 0) OR YEAR(DateValue) % 400 = 0 THEN 1 ELSE 0 END AS IsLeapYear,
        CASE WHEN MONTH(DateValue) >= 7 THEN YEAR(DateValue) + 1 ELSE YEAR(DateValue) END AS FiscalYear,
        CASE WHEN MONTH(DateValue) >= 7 THEN ((MONTH(DateValue) - 7) / 3) + 1 ELSE ((MONTH(DateValue) + 5) / 3) + 1 END AS FiscalQuarter
    FROM DateSeries
    OPTION (MAXRECURSION 0);
    
    SELECT COUNT(*) AS DatesGenerated FROM dbo.DimDate;
END
GO
