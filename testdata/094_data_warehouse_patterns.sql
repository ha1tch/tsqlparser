-- Sample 094: Data Warehouse Loading Patterns
-- Source: Kimball methodology, Microsoft patterns, Data warehouse best practices
-- Category: ETL/Data Loading
-- Complexity: Advanced
-- Features: Fact table loading, surrogate keys, type 1/2 SCD, incremental loads

-- Load fact table with surrogate key lookups
CREATE PROCEDURE dbo.LoadFactTable
    @SourceQuery NVARCHAR(MAX),
    @FactTableName NVARCHAR(128),
    @DateKeyColumn NVARCHAR(128),
    @DimensionLookups NVARCHAR(MAX)  -- JSON: [{"source":"CustomerID","dim":"DimCustomer","dimKey":"CustomerKey","naturalKey":"CustomerID"}]
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @SelectColumns NVARCHAR(MAX) = '';
    DECLARE @JoinClauses NVARCHAR(MAX) = '';
    DECLARE @RowsLoaded INT;
    
    -- Build surrogate key lookups
    SELECT @SelectColumns = @SelectColumns + 
        'd_' + JSON_VALUE(value, '$.source') + '.' + JSON_VALUE(value, '$.dimKey') + ' AS ' + JSON_VALUE(value, '$.dimKey') + ', ',
        @JoinClauses = @JoinClauses +
        'LEFT JOIN dbo.' + JSON_VALUE(value, '$.dim') + ' d_' + JSON_VALUE(value, '$.source') + 
        ' ON src.' + JSON_VALUE(value, '$.source') + ' = d_' + JSON_VALUE(value, '$.source') + '.' + JSON_VALUE(value, '$.naturalKey') +
        ' AND d_' + JSON_VALUE(value, '$.source') + '.IsCurrent = 1 '
    FROM OPENJSON(@DimensionLookups);
    
    -- Date key lookup
    SET @SelectColumns = @SelectColumns + 'dd.DateKey AS ' + @DateKeyColumn + 'Key, ';
    SET @JoinClauses = @JoinClauses + 'LEFT JOIN dbo.DimDate dd ON CAST(src.' + @DateKeyColumn + ' AS DATE) = dd.FullDate ';
    
    -- Get remaining columns from source
    SET @SQL = N'
        INSERT INTO dbo.' + QUOTENAME(@FactTableName) + '
        SELECT ' + @SelectColumns + ' src.*
        FROM (' + @SourceQuery + ') src
        ' + @JoinClauses;
    
    EXEC sp_executesql @SQL;
    SET @RowsLoaded = @@ROWCOUNT;
    
    SELECT @RowsLoaded AS RowsLoaded, SYSDATETIME() AS LoadTime;
END
GO

-- Generate surrogate key
CREATE PROCEDURE dbo.GetOrCreateSurrogateKey
    @DimensionTable NVARCHAR(128),
    @NaturalKeyColumn NVARCHAR(128),
    @NaturalKeyValue NVARCHAR(MAX),
    @SurrogateKeyColumn NVARCHAR(128) = NULL,
    @SurrogateKey INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    SET @SurrogateKeyColumn = ISNULL(@SurrogateKeyColumn, REPLACE(@DimensionTable, 'Dim', '') + 'Key');
    
    DECLARE @SQL NVARCHAR(MAX);
    
    -- Try to get existing key
    SET @SQL = N'SELECT @Key = ' + QUOTENAME(@SurrogateKeyColumn) + 
               ' FROM dbo.' + QUOTENAME(@DimensionTable) + 
               ' WHERE ' + QUOTENAME(@NaturalKeyColumn) + ' = @NatKey AND IsCurrent = 1';
    
    EXEC sp_executesql @SQL, N'@NatKey NVARCHAR(MAX), @Key INT OUTPUT', @NatKey = @NaturalKeyValue, @Key = @SurrogateKey OUTPUT;
    
    -- If not found, create unknown member reference
    IF @SurrogateKey IS NULL
    BEGIN
        SET @SQL = N'SELECT @Key = ' + QUOTENAME(@SurrogateKeyColumn) + 
                   ' FROM dbo.' + QUOTENAME(@DimensionTable) + 
                   ' WHERE ' + QUOTENAME(@NaturalKeyColumn) + ' = ''Unknown''';
        EXEC sp_executesql @SQL, N'@Key INT OUTPUT', @Key = @SurrogateKey OUTPUT;
        
        -- Default to -1 if no unknown member
        SET @SurrogateKey = ISNULL(@SurrogateKey, -1);
    END
END
GO

-- SCD Type 2 dimension load
CREATE PROCEDURE dbo.LoadSCDType2Dimension
    @SourceQuery NVARCHAR(MAX),
    @DimensionTable NVARCHAR(128),
    @NaturalKeyColumn NVARCHAR(128),
    @Type2Columns NVARCHAR(MAX),  -- Comma-separated columns to track history
    @Type1Columns NVARCHAR(MAX) = NULL  -- Columns to overwrite (no history)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @SurrogateKeyColumn NVARCHAR(128) = REPLACE(@DimensionTable, 'Dim', '') + 'Key';
    DECLARE @RowsInserted INT = 0;
    DECLARE @RowsUpdated INT = 0;
    DECLARE @RowsExpired INT = 0;
    
    -- Build comparison for Type 2 columns
    DECLARE @Type2Comparison NVARCHAR(MAX) = '';
    SELECT @Type2Comparison = @Type2Comparison + 
        'ISNULL(CAST(target.' + QUOTENAME(LTRIM(RTRIM(value))) + ' AS NVARCHAR(MAX)), '''') <> ISNULL(CAST(source.' + QUOTENAME(LTRIM(RTRIM(value))) + ' AS NVARCHAR(MAX)), '''') OR '
    FROM STRING_SPLIT(@Type2Columns, ',');
    SET @Type2Comparison = LEFT(@Type2Comparison, LEN(@Type2Comparison) - 3);
    
    -- Create temp staging table
    SET @SQL = N'SELECT * INTO #StagingDim FROM (' + @SourceQuery + ') AS src';
    EXEC sp_executesql @SQL;
    
    -- Expire changed records
    SET @SQL = N'
        UPDATE target
        SET IsCurrent = 0, 
            EffectiveEndDate = DATEADD(DAY, -1, CAST(GETDATE() AS DATE))
        FROM dbo.' + QUOTENAME(@DimensionTable) + ' target
        INNER JOIN #StagingDim source ON target.' + QUOTENAME(@NaturalKeyColumn) + ' = source.' + QUOTENAME(@NaturalKeyColumn) + '
        WHERE target.IsCurrent = 1
          AND (' + @Type2Comparison + ')';
    
    EXEC sp_executesql @SQL;
    SET @RowsExpired = @@ROWCOUNT;
    
    -- Insert new versions for changed records and brand new records
    DECLARE @AllColumns NVARCHAR(MAX);
    SELECT @AllColumns = STRING_AGG(QUOTENAME(name), ', ')
    FROM sys.columns 
    WHERE object_id = OBJECT_ID('dbo.' + @DimensionTable)
      AND name NOT IN (@SurrogateKeyColumn, 'IsCurrent', 'EffectiveStartDate', 'EffectiveEndDate');
    
    SET @SQL = N'
        INSERT INTO dbo.' + QUOTENAME(@DimensionTable) + ' (' + @AllColumns + ', IsCurrent, EffectiveStartDate, EffectiveEndDate)
        SELECT ' + @AllColumns + ', 1, CAST(GETDATE() AS DATE), ''9999-12-31''
        FROM #StagingDim source
        WHERE NOT EXISTS (
            SELECT 1 FROM dbo.' + QUOTENAME(@DimensionTable) + ' target
            WHERE target.' + QUOTENAME(@NaturalKeyColumn) + ' = source.' + QUOTENAME(@NaturalKeyColumn) + '
              AND target.IsCurrent = 1
        )';
    
    EXEC sp_executesql @SQL;
    SET @RowsInserted = @@ROWCOUNT;
    
    -- Type 1 updates (if specified)
    IF @Type1Columns IS NOT NULL
    BEGIN
        DECLARE @Type1Update NVARCHAR(MAX) = '';
        SELECT @Type1Update = @Type1Update + QUOTENAME(LTRIM(RTRIM(value))) + ' = source.' + QUOTENAME(LTRIM(RTRIM(value))) + ', '
        FROM STRING_SPLIT(@Type1Columns, ',');
        SET @Type1Update = LEFT(@Type1Update, LEN(@Type1Update) - 1);
        
        SET @SQL = N'
            UPDATE target
            SET ' + @Type1Update + '
            FROM dbo.' + QUOTENAME(@DimensionTable) + ' target
            INNER JOIN #StagingDim source ON target.' + QUOTENAME(@NaturalKeyColumn) + ' = source.' + QUOTENAME(@NaturalKeyColumn);
        
        EXEC sp_executesql @SQL;
        SET @RowsUpdated = @@ROWCOUNT;
    END
    
    DROP TABLE #StagingDim;
    
    SELECT @RowsInserted AS RowsInserted, @RowsExpired AS RowsExpired, @RowsUpdated AS Type1Updates;
END
GO

-- Incremental fact load with watermark
CREATE PROCEDURE dbo.IncrementalFactLoad
    @FactTable NVARCHAR(128),
    @SourceTable NVARCHAR(256),
    @WatermarkColumn NVARCHAR(128),
    @LastLoadDate DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @NewWatermark DATETIME2;
    DECLARE @RowsLoaded INT;
    
    -- Get last watermark if not provided
    IF @LastLoadDate IS NULL
    BEGIN
        SET @SQL = N'SELECT @LW = MAX(' + QUOTENAME(@WatermarkColumn) + ') FROM dbo.' + QUOTENAME(@FactTable);
        EXEC sp_executesql @SQL, N'@LW DATETIME2 OUTPUT', @LW = @LastLoadDate OUTPUT;
        SET @LastLoadDate = ISNULL(@LastLoadDate, '1900-01-01');
    END
    
    -- Get new watermark
    SET @SQL = N'SELECT @NW = MAX(' + QUOTENAME(@WatermarkColumn) + ') FROM ' + @SourceTable + 
               ' WHERE ' + QUOTENAME(@WatermarkColumn) + ' > @LW';
    EXEC sp_executesql @SQL, N'@LW DATETIME2, @NW DATETIME2 OUTPUT', @LW = @LastLoadDate, @NW = @NewWatermark OUTPUT;
    
    IF @NewWatermark IS NOT NULL
    BEGIN
        -- Load new records
        SET @SQL = N'
            INSERT INTO dbo.' + QUOTENAME(@FactTable) + '
            SELECT * FROM ' + @SourceTable + '
            WHERE ' + QUOTENAME(@WatermarkColumn) + ' > @LastLoad
              AND ' + QUOTENAME(@WatermarkColumn) + ' <= @NewLoad';
        
        EXEC sp_executesql @SQL, N'@LastLoad DATETIME2, @NewLoad DATETIME2', @LastLoad = @LastLoadDate, @NewLoad = @NewWatermark;
        SET @RowsLoaded = @@ROWCOUNT;
    END
    ELSE
        SET @RowsLoaded = 0;
    
    SELECT @RowsLoaded AS RowsLoaded, @LastLoadDate AS PreviousWatermark, @NewWatermark AS NewWatermark;
END
GO

-- Create unknown dimension member
CREATE PROCEDURE dbo.CreateUnknownMember
    @DimensionTable NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @SurrogateKeyColumn NVARCHAR(128) = REPLACE(@DimensionTable, 'Dim', '') + 'Key';
    DECLARE @Columns NVARCHAR(MAX);
    DECLARE @Values NVARCHAR(MAX);
    
    -- Build column/value lists
    SELECT @Columns = STRING_AGG(QUOTENAME(name), ', '),
           @Values = STRING_AGG(
               CASE 
                   WHEN name = @SurrogateKeyColumn THEN '-1'
                   WHEN TYPE_NAME(user_type_id) IN ('varchar', 'nvarchar', 'char', 'nchar') THEN '''Unknown'''
                   WHEN TYPE_NAME(user_type_id) IN ('int', 'bigint', 'smallint', 'decimal', 'numeric') THEN '-1'
                   WHEN TYPE_NAME(user_type_id) IN ('datetime', 'datetime2', 'date') THEN '''1900-01-01'''
                   WHEN TYPE_NAME(user_type_id) = 'bit' THEN '0'
                   ELSE 'NULL'
               END, ', ')
    FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.' + @DimensionTable)
      AND is_identity = 0;
    
    SET @SQL = N'
        IF NOT EXISTS (SELECT 1 FROM dbo.' + QUOTENAME(@DimensionTable) + ' WHERE ' + QUOTENAME(@SurrogateKeyColumn) + ' = -1)
        BEGIN
            SET IDENTITY_INSERT dbo.' + QUOTENAME(@DimensionTable) + ' ON;
            INSERT INTO dbo.' + QUOTENAME(@DimensionTable) + ' (' + @Columns + ')
            VALUES (' + @Values + ');
            SET IDENTITY_INSERT dbo.' + QUOTENAME(@DimensionTable) + ' OFF;
        END';
    
    EXEC sp_executesql @SQL;
    
    SELECT 'Unknown member ensured for ' + @DimensionTable AS Status;
END
GO
