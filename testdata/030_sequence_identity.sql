-- Sample 030: Sequence and Identity Management
-- Source: Microsoft Learn, MSSQLTips, Stack Overflow
-- Category: Performance
-- Complexity: Complex
-- Features: SEQUENCE objects, IDENTITY, DBCC CHECKIDENT, NEXT VALUE FOR

-- Create or reset a sequence
CREATE PROCEDURE dbo.ManageSequence
    @SequenceName NVARCHAR(128),
    @SchemaName NVARCHAR(128) = 'dbo',
    @Action NVARCHAR(20) = 'CREATE',  -- CREATE, RESET, DROP, INFO
    @StartValue BIGINT = 1,
    @IncrementBy BIGINT = 1,
    @MinValue BIGINT = NULL,
    @MaxValue BIGINT = NULL,
    @Cycle BIT = 0,
    @CacheSize INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FullName NVARCHAR(256) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@SequenceName);
    
    IF @Action = 'CREATE'
    BEGIN
        -- Drop if exists
        IF EXISTS (
            SELECT 1 FROM sys.sequences s
            INNER JOIN sys.schemas sch ON s.schema_id = sch.schema_id
            WHERE s.name = @SequenceName AND sch.name = @SchemaName
        )
        BEGIN
            SET @SQL = 'DROP SEQUENCE ' + @FullName;
            EXEC sp_executesql @SQL;
        END
        
        -- Create sequence
        SET @SQL = 'CREATE SEQUENCE ' + @FullName + '
            AS BIGINT
            START WITH ' + CAST(@StartValue AS NVARCHAR(20)) + '
            INCREMENT BY ' + CAST(@IncrementBy AS NVARCHAR(20));
        
        IF @MinValue IS NOT NULL
            SET @SQL = @SQL + ' MINVALUE ' + CAST(@MinValue AS NVARCHAR(20));
        ELSE
            SET @SQL = @SQL + ' NO MINVALUE';
        
        IF @MaxValue IS NOT NULL
            SET @SQL = @SQL + ' MAXVALUE ' + CAST(@MaxValue AS NVARCHAR(20));
        ELSE
            SET @SQL = @SQL + ' NO MAXVALUE';
        
        IF @Cycle = 1
            SET @SQL = @SQL + ' CYCLE';
        ELSE
            SET @SQL = @SQL + ' NO CYCLE';
        
        IF @CacheSize > 0
            SET @SQL = @SQL + ' CACHE ' + CAST(@CacheSize AS NVARCHAR(10));
        ELSE
            SET @SQL = @SQL + ' NO CACHE';
        
        EXEC sp_executesql @SQL;
        PRINT 'Sequence created: ' + @FullName;
    END
    ELSE IF @Action = 'RESET'
    BEGIN
        SET @SQL = 'ALTER SEQUENCE ' + @FullName + ' RESTART WITH ' + CAST(@StartValue AS NVARCHAR(20));
        EXEC sp_executesql @SQL;
        PRINT 'Sequence reset to: ' + CAST(@StartValue AS NVARCHAR(20));
    END
    ELSE IF @Action = 'DROP'
    BEGIN
        IF EXISTS (
            SELECT 1 FROM sys.sequences s
            INNER JOIN sys.schemas sch ON s.schema_id = sch.schema_id
            WHERE s.name = @SequenceName AND sch.name = @SchemaName
        )
        BEGIN
            SET @SQL = 'DROP SEQUENCE ' + @FullName;
            EXEC sp_executesql @SQL;
            PRINT 'Sequence dropped: ' + @FullName;
        END
        ELSE
            PRINT 'Sequence not found: ' + @FullName;
    END
    
    -- Always show info
    IF @Action = 'INFO' OR @Action IN ('CREATE', 'RESET')
    BEGIN
        SELECT 
            sch.name AS SchemaName,
            s.name AS SequenceName,
            TYPE_NAME(s.user_type_id) AS DataType,
            s.start_value AS StartValue,
            s.increment AS IncrementBy,
            s.minimum_value AS MinValue,
            s.maximum_value AS MaxValue,
            s.current_value AS CurrentValue,
            s.is_cycling AS IsCycling,
            s.is_cached AS IsCached,
            s.cache_size AS CacheSize,
            s.is_exhausted AS IsExhausted,
            s.create_date AS CreateDate,
            s.modify_date AS ModifyDate
        FROM sys.sequences s
        INNER JOIN sys.schemas sch ON s.schema_id = sch.schema_id
        WHERE s.name = @SequenceName AND sch.name = @SchemaName;
    END
END
GO

-- Get next value from sequence with range support
CREATE PROCEDURE dbo.GetSequenceRange
    @SequenceName NVARCHAR(128),
    @SchemaName NVARCHAR(128) = 'dbo',
    @RangeSize INT = 1,
    @FirstValue BIGINT OUTPUT,
    @LastValue BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    
    EXEC sp_sequence_get_range 
        @sequence_name = @SequenceName,
        @range_size = @RangeSize,
        @range_first_value = @FirstValue OUTPUT,
        @range_last_value = @LastValue OUTPUT;
    
    SELECT 
        @SequenceName AS SequenceName,
        @RangeSize AS RangeSize,
        @FirstValue AS FirstValue,
        @LastValue AS LastValue;
END
GO

-- Reseed identity column
CREATE PROCEDURE dbo.ReseedIdentity
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @NewSeedValue BIGINT = NULL,  -- NULL = set to max existing + 1
    @IncludeCheck BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @IdentityColumn NVARCHAR(128);
    DECLARE @CurrentSeed BIGINT;
    DECLARE @MaxValue BIGINT;
    DECLARE @FullName NVARCHAR(256) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    
    -- Get identity column name
    SELECT @IdentityColumn = c.name
    FROM sys.columns c
    INNER JOIN sys.tables t ON c.object_id = t.object_id
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE t.name = @TableName 
      AND s.name = @SchemaName
      AND c.is_identity = 1;
    
    IF @IdentityColumn IS NULL
    BEGIN
        RAISERROR('Table %s does not have an identity column', 16, 1, @FullName);
        RETURN;
    END
    
    -- Get current max value
    SET @SQL = 'SELECT @max = MAX(' + QUOTENAME(@IdentityColumn) + ') FROM ' + @FullName;
    EXEC sp_executesql @SQL, N'@max BIGINT OUTPUT', @max = @MaxValue OUTPUT;
    
    SET @MaxValue = ISNULL(@MaxValue, 0);
    
    -- Determine new seed value
    IF @NewSeedValue IS NULL
        SET @NewSeedValue = @MaxValue;  -- DBCC will use MaxValue, next insert will be MaxValue + 1
    
    -- Check current identity
    SET @SQL = 'DBCC CHECKIDENT(''' + @FullName + ''', NORESEED)';
    IF @IncludeCheck = 1
        EXEC sp_executesql @SQL;
    
    -- Reseed
    SET @SQL = 'DBCC CHECKIDENT(''' + @FullName + ''', RESEED, ' + CAST(@NewSeedValue AS NVARCHAR(20)) + ')';
    EXEC sp_executesql @SQL;
    
    SELECT 
        @FullName AS TableName,
        @IdentityColumn AS IdentityColumn,
        @MaxValue AS MaxExistingValue,
        @NewSeedValue AS NewSeedValue,
        @NewSeedValue + 1 AS NextIdentityValue;
END
GO

-- Get identity usage statistics
CREATE PROCEDURE dbo.GetIdentityUsage
    @WarningThresholdPercent INT = 80
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        QUOTENAME(s.name) + '.' + QUOTENAME(t.name) AS TableName,
        c.name AS IdentityColumn,
        TYPE_NAME(c.user_type_id) AS DataType,
        IDENT_SEED(s.name + '.' + t.name) AS SeedValue,
        IDENT_INCR(s.name + '.' + t.name) AS IncrementValue,
        IDENT_CURRENT(s.name + '.' + t.name) AS CurrentValue,
        CASE TYPE_NAME(c.user_type_id)
            WHEN 'tinyint' THEN 255
            WHEN 'smallint' THEN 32767
            WHEN 'int' THEN 2147483647
            WHEN 'bigint' THEN 9223372036854775807
        END AS MaxPossibleValue,
        CAST(
            CAST(IDENT_CURRENT(s.name + '.' + t.name) AS DECIMAL(38,2)) * 100 /
            CASE TYPE_NAME(c.user_type_id)
                WHEN 'tinyint' THEN 255
                WHEN 'smallint' THEN 32767
                WHEN 'int' THEN 2147483647
                WHEN 'bigint' THEN 9223372036854775807
            END
        AS DECIMAL(5,2)) AS UsedPercent,
        CASE 
            WHEN CAST(IDENT_CURRENT(s.name + '.' + t.name) AS DECIMAL(38,2)) * 100 /
                CASE TYPE_NAME(c.user_type_id)
                    WHEN 'tinyint' THEN 255
                    WHEN 'smallint' THEN 32767
                    WHEN 'int' THEN 2147483647
                    WHEN 'bigint' THEN 9223372036854775807
                END >= @WarningThresholdPercent
            THEN 'WARNING'
            ELSE 'OK'
        END AS Status
    FROM sys.columns c
    INNER JOIN sys.tables t ON c.object_id = t.object_id
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE c.is_identity = 1
      AND t.type = 'U'
    ORDER BY UsedPercent DESC;
END
GO

-- Generate unique identifier batch
CREATE PROCEDURE dbo.GenerateUniqueIDs
    @Count INT,
    @Type NVARCHAR(20) = 'GUID',  -- GUID, SEQUENTIAL_GUID, CUSTOM
    @Prefix NVARCHAR(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @IDs TABLE (
        RowNum INT,
        UniqueID NVARCHAR(100)
    );
    
    ;WITH Numbers AS (
        SELECT 1 AS n
        UNION ALL
        SELECT n + 1 FROM Numbers WHERE n < @Count
    )
    INSERT INTO @IDs (RowNum, UniqueID)
    SELECT 
        n,
        CASE @Type
            WHEN 'GUID' THEN CAST(NEWID() AS NVARCHAR(50))
            WHEN 'SEQUENTIAL_GUID' THEN CAST(NEWSEQUENTIALID() AS NVARCHAR(50))
            WHEN 'CUSTOM' THEN 
                ISNULL(@Prefix, '') + 
                FORMAT(GETDATE(), 'yyyyMMddHHmmss') + 
                RIGHT('000000' + CAST(n AS VARCHAR(6)), 6)
            ELSE CAST(NEWID() AS NVARCHAR(50))
        END
    FROM Numbers
    OPTION (MAXRECURSION 0);
    
    SELECT UniqueID FROM @IDs ORDER BY RowNum;
END
GO

-- Audit sequence usage
CREATE PROCEDURE dbo.AuditAllSequences
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        sch.name AS SchemaName,
        s.name AS SequenceName,
        TYPE_NAME(s.user_type_id) AS DataType,
        CAST(s.current_value AS BIGINT) AS CurrentValue,
        CAST(s.start_value AS BIGINT) AS StartValue,
        CAST(s.minimum_value AS BIGINT) AS MinValue,
        CAST(s.maximum_value AS BIGINT) AS MaxValue,
        CAST(s.increment AS BIGINT) AS IncrementBy,
        s.is_cycling AS IsCycling,
        s.is_exhausted AS IsExhausted,
        CASE 
            WHEN s.is_exhausted = 1 THEN 'EXHAUSTED'
            WHEN CAST(s.current_value AS DECIMAL(38,2)) * 100 / 
                 NULLIF(CAST(s.maximum_value AS DECIMAL(38,2)), 0) > 90 THEN 'WARNING'
            ELSE 'OK'
        END AS Status,
        s.cache_size AS CacheSize,
        s.create_date,
        s.modify_date,
        -- Estimate remaining values
        CASE 
            WHEN s.increment > 0 
            THEN (CAST(s.maximum_value AS BIGINT) - CAST(s.current_value AS BIGINT)) / CAST(s.increment AS BIGINT)
            ELSE (CAST(s.current_value AS BIGINT) - CAST(s.minimum_value AS BIGINT)) / ABS(CAST(s.increment AS BIGINT))
        END AS EstimatedRemainingValues
    FROM sys.sequences s
    INNER JOIN sys.schemas sch ON s.schema_id = sch.schema_id
    ORDER BY 
        CASE WHEN s.is_exhausted = 1 THEN 0 ELSE 1 END,
        CAST(s.current_value AS DECIMAL(38,2)) * 100 / NULLIF(CAST(s.maximum_value AS DECIMAL(38,2)), 0) DESC;
END
GO
