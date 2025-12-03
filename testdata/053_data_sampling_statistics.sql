-- Sample 053: Data Sampling and Statistical Analysis
-- Source: Various - MSSQLTips, Stack Overflow, Statistical methods
-- Category: Reporting
-- Complexity: Advanced
-- Features: TABLESAMPLE, NEWID sampling, percentiles, statistical functions

-- Random sample from table
CREATE PROCEDURE dbo.GetRandomSample
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @SampleSize INT = 1000,
    @SampleMethod NVARCHAR(20) = 'ROWS'  -- ROWS, PERCENT, TABLESAMPLE
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FullPath NVARCHAR(256) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    
    IF @SampleMethod = 'ROWS'
    BEGIN
        -- Random N rows using ORDER BY NEWID()
        SET @SQL = N'SELECT TOP (@Size) * FROM ' + @FullPath + ' ORDER BY NEWID()';
        EXEC sp_executesql @SQL, N'@Size INT', @Size = @SampleSize;
    END
    ELSE IF @SampleMethod = 'PERCENT'
    BEGIN
        -- Random percentage using NEWID() with threshold
        SET @SQL = N'
            SELECT * FROM ' + @FullPath + '
            WHERE ABS(CHECKSUM(NEWID())) % 100 < @Pct';
        EXEC sp_executesql @SQL, N'@Pct INT', @Pct = @SampleSize;
    END
    ELSE IF @SampleMethod = 'TABLESAMPLE'
    BEGIN
        -- Use TABLESAMPLE for large tables (faster but less precise)
        SET @SQL = N'SELECT * FROM ' + @FullPath + ' TABLESAMPLE (' + CAST(@SampleSize AS VARCHAR(10)) + ' ROWS)';
        EXEC sp_executesql @SQL;
    END
END
GO

-- Calculate descriptive statistics for numeric column
CREATE PROCEDURE dbo.GetColumnStatistics
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @ColumnName NVARCHAR(128),
    @WhereClause NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FullPath NVARCHAR(256) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    DECLARE @Col NVARCHAR(128) = QUOTENAME(@ColumnName);
    
    SET @SQL = N'
        WITH Stats AS (
            SELECT 
                ' + @Col + ' AS Value,
                COUNT(*) OVER () AS N,
                ROW_NUMBER() OVER (ORDER BY ' + @Col + ') AS RowAsc,
                ROW_NUMBER() OVER (ORDER BY ' + @Col + ' DESC) AS RowDesc
            FROM ' + @FullPath + '
            WHERE ' + @Col + ' IS NOT NULL'
            + ISNULL(' AND ' + @WhereClause, '') + '
        ),
        Aggregates AS (
            SELECT
                COUNT(Value) AS N,
                MIN(Value) AS MinValue,
                MAX(Value) AS MaxValue,
                AVG(CAST(Value AS FLOAT)) AS Mean,
                STDEV(CAST(Value AS FLOAT)) AS StdDev,
                VAR(CAST(Value AS FLOAT)) AS Variance,
                SUM(CAST(Value AS FLOAT)) AS Total
            FROM Stats
        ),
        Median AS (
            SELECT AVG(CAST(Value AS FLOAT)) AS MedianValue
            FROM Stats
            WHERE RowAsc IN ((N + 1) / 2, (N + 2) / 2)
        ),
        Quartiles AS (
            SELECT 
                MAX(CASE WHEN RowAsc <= N * 0.25 THEN Value END) AS Q1,
                MAX(CASE WHEN RowAsc <= N * 0.75 THEN Value END) AS Q3
            FROM Stats
        ),
        Mode AS (
            SELECT TOP 1 Value AS ModeValue, COUNT(*) AS ModeCount
            FROM Stats
            GROUP BY Value
            ORDER BY COUNT(*) DESC
        )
        SELECT 
            ''' + @ColumnName + ''' AS ColumnName,
            a.N AS SampleSize,
            a.MinValue,
            a.MaxValue,
            a.Mean,
            m.MedianValue AS Median,
            mo.ModeValue AS Mode,
            a.StdDev AS StandardDeviation,
            a.Variance,
            a.MaxValue - a.MinValue AS Range,
            q.Q1 AS FirstQuartile,
            q.Q3 AS ThirdQuartile,
            q.Q3 - q.Q1 AS InterquartileRange,
            a.StdDev / NULLIF(a.Mean, 0) AS CoefficientOfVariation
        FROM Aggregates a
        CROSS JOIN Median m
        CROSS JOIN Quartiles q
        CROSS JOIN Mode mo';
    
    EXEC sp_executesql @SQL;
END
GO

-- Calculate percentiles
CREATE PROCEDURE dbo.GetPercentiles
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @ColumnName NVARCHAR(128),
    @Percentiles NVARCHAR(500) = '10,25,50,75,90,95,99'
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FullPath NVARCHAR(256) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    DECLARE @Col NVARCHAR(128) = QUOTENAME(@ColumnName);
    DECLARE @PercentileSelect NVARCHAR(MAX) = '';
    
    -- Build PERCENTILE_CONT for each percentile
    SELECT @PercentileSelect = @PercentileSelect +
        'PERCENTILE_CONT(' + CAST(CAST(value AS FLOAT) / 100 AS VARCHAR(10)) + 
        ') WITHIN GROUP (ORDER BY ' + @Col + ') AS P' + value + ', '
    FROM STRING_SPLIT(@Percentiles, ',');
    
    SET @PercentileSelect = LEFT(@PercentileSelect, LEN(@PercentileSelect) - 1);
    
    SET @SQL = N'
        SELECT ' + @PercentileSelect + '
        FROM ' + @FullPath + '
        WHERE ' + @Col + ' IS NOT NULL';
    
    EXEC sp_executesql @SQL;
END
GO

-- Histogram/frequency distribution
CREATE PROCEDURE dbo.GetHistogram
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @ColumnName NVARCHAR(128),
    @BucketCount INT = 10,
    @MinValue FLOAT = NULL,
    @MaxValue FLOAT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FullPath NVARCHAR(256) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    DECLARE @Col NVARCHAR(128) = QUOTENAME(@ColumnName);
    
    SET @SQL = N'
        DECLARE @Min FLOAT = @MinVal;
        DECLARE @Max FLOAT = @MaxVal;
        DECLARE @BucketSize FLOAT;
        
        IF @Min IS NULL SELECT @Min = MIN(' + @Col + ') FROM ' + @FullPath + ';
        IF @Max IS NULL SELECT @Max = MAX(' + @Col + ') FROM ' + @FullPath + ';
        
        SET @BucketSize = (@Max - @Min) / @Buckets;
        
        ;WITH Buckets AS (
            SELECT 
                FLOOR((' + @Col + ' - @Min) / @BucketSize) AS BucketNum,
                @Min + FLOOR((' + @Col + ' - @Min) / @BucketSize) * @BucketSize AS BucketStart,
                @Min + (FLOOR((' + @Col + ' - @Min) / @BucketSize) + 1) * @BucketSize AS BucketEnd,
                COUNT(*) AS Frequency
            FROM ' + @FullPath + '
            WHERE ' + @Col + ' IS NOT NULL
            GROUP BY FLOOR((' + @Col + ' - @Min) / @BucketSize)
        )
        SELECT 
            BucketNum,
            BucketStart,
            BucketEnd,
            CAST(BucketStart AS VARCHAR(20)) + '' - '' + CAST(BucketEnd AS VARCHAR(20)) AS BucketRange,
            Frequency,
            CAST(Frequency * 100.0 / SUM(Frequency) OVER () AS DECIMAL(5,2)) AS Percentage,
            REPLICATE(''*'', Frequency * 50 / MAX(Frequency) OVER ()) AS Histogram
        FROM Buckets
        ORDER BY BucketNum';
    
    EXEC sp_executesql @SQL,
        N'@MinVal FLOAT, @MaxVal FLOAT, @Buckets INT',
        @MinVal = @MinValue,
        @MaxVal = @MaxValue,
        @Buckets = @BucketCount;
END
GO

-- Correlation between two columns
CREATE PROCEDURE dbo.GetCorrelation
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @Column1 NVARCHAR(128),
    @Column2 NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FullPath NVARCHAR(256) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    
    SET @SQL = N'
        SELECT 
            ''' + @Column1 + ''' AS Column1,
            ''' + @Column2 + ''' AS Column2,
            COUNT(*) AS N,
            -- Pearson correlation coefficient
            (COUNT(*) * SUM(CAST(' + QUOTENAME(@Column1) + ' AS FLOAT) * CAST(' + QUOTENAME(@Column2) + ' AS FLOAT)) - 
             SUM(CAST(' + QUOTENAME(@Column1) + ' AS FLOAT)) * SUM(CAST(' + QUOTENAME(@Column2) + ' AS FLOAT))) /
            NULLIF(
                SQRT((COUNT(*) * SUM(POWER(CAST(' + QUOTENAME(@Column1) + ' AS FLOAT), 2)) - POWER(SUM(CAST(' + QUOTENAME(@Column1) + ' AS FLOAT)), 2)) *
                     (COUNT(*) * SUM(POWER(CAST(' + QUOTENAME(@Column2) + ' AS FLOAT), 2)) - POWER(SUM(CAST(' + QUOTENAME(@Column2) + ' AS FLOAT)), 2))), 0
            ) AS PearsonCorrelation,
            -- Interpretation
            CASE 
                WHEN ABS((COUNT(*) * SUM(CAST(' + QUOTENAME(@Column1) + ' AS FLOAT) * CAST(' + QUOTENAME(@Column2) + ' AS FLOAT)) - 
                     SUM(CAST(' + QUOTENAME(@Column1) + ' AS FLOAT)) * SUM(CAST(' + QUOTENAME(@Column2) + ' AS FLOAT))) /
                    NULLIF(SQRT((COUNT(*) * SUM(POWER(CAST(' + QUOTENAME(@Column1) + ' AS FLOAT), 2)) - POWER(SUM(CAST(' + QUOTENAME(@Column1) + ' AS FLOAT)), 2)) *
                         (COUNT(*) * SUM(POWER(CAST(' + QUOTENAME(@Column2) + ' AS FLOAT), 2)) - POWER(SUM(CAST(' + QUOTENAME(@Column2) + ' AS FLOAT)), 2))), 0)) >= 0.8 THEN ''Strong''
                WHEN ABS((COUNT(*) * SUM(CAST(' + QUOTENAME(@Column1) + ' AS FLOAT) * CAST(' + QUOTENAME(@Column2) + ' AS FLOAT)) - 
                     SUM(CAST(' + QUOTENAME(@Column1) + ' AS FLOAT)) * SUM(CAST(' + QUOTENAME(@Column2) + ' AS FLOAT))) /
                    NULLIF(SQRT((COUNT(*) * SUM(POWER(CAST(' + QUOTENAME(@Column1) + ' AS FLOAT), 2)) - POWER(SUM(CAST(' + QUOTENAME(@Column1) + ' AS FLOAT)), 2)) *
                         (COUNT(*) * SUM(POWER(CAST(' + QUOTENAME(@Column2) + ' AS FLOAT), 2)) - POWER(SUM(CAST(' + QUOTENAME(@Column2) + ' AS FLOAT)), 2))), 0)) >= 0.5 THEN ''Moderate''
                WHEN ABS((COUNT(*) * SUM(CAST(' + QUOTENAME(@Column1) + ' AS FLOAT) * CAST(' + QUOTENAME(@Column2) + ' AS FLOAT)) - 
                     SUM(CAST(' + QUOTENAME(@Column1) + ' AS FLOAT)) * SUM(CAST(' + QUOTENAME(@Column2) + ' AS FLOAT))) /
                    NULLIF(SQRT((COUNT(*) * SUM(POWER(CAST(' + QUOTENAME(@Column1) + ' AS FLOAT), 2)) - POWER(SUM(CAST(' + QUOTENAME(@Column1) + ' AS FLOAT)), 2)) *
                         (COUNT(*) * SUM(POWER(CAST(' + QUOTENAME(@Column2) + ' AS FLOAT), 2)) - POWER(SUM(CAST(' + QUOTENAME(@Column2) + ' AS FLOAT)), 2))), 0)) >= 0.3 THEN ''Weak''
                ELSE ''Very Weak/None''
            END AS CorrelationStrength
        FROM ' + @FullPath + '
        WHERE ' + QUOTENAME(@Column1) + ' IS NOT NULL 
          AND ' + QUOTENAME(@Column2) + ' IS NOT NULL';
    
    EXEC sp_executesql @SQL;
END
GO
