-- Sample 054: Data Quality Profiling
-- Source: Various - Data quality frameworks, MSSQLTips, Microsoft patterns
-- Category: Data Validation
-- Complexity: Advanced
-- Features: Column profiling, data quality metrics, completeness, uniqueness

-- Profile all columns in a table
CREATE PROCEDURE dbo.ProfileTableColumns
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FullPath NVARCHAR(256) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    DECLARE @ColumnName NVARCHAR(128);
    DECLARE @DataType NVARCHAR(128);
    DECLARE @ColumnID INT;
    
    -- Results table
    CREATE TABLE #Profile (
        ColumnName NVARCHAR(128),
        DataType NVARCHAR(128),
        TotalRows BIGINT,
        NullCount BIGINT,
        NullPercent DECIMAL(5,2),
        DistinctCount BIGINT,
        UniquePercent DECIMAL(5,2),
        MinLength INT,
        MaxLength INT,
        AvgLength DECIMAL(10,2),
        MinValue NVARCHAR(500),
        MaxValue NVARCHAR(500),
        SampleValues NVARCHAR(MAX)
    );
    
    -- Get total row count
    DECLARE @TotalRows BIGINT;
    SET @SQL = N'SELECT @Cnt = COUNT(*) FROM ' + @FullPath;
    EXEC sp_executesql @SQL, N'@Cnt BIGINT OUTPUT', @Cnt = @TotalRows OUTPUT;
    
    -- Profile each column
    DECLARE ColumnCursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT c.name, TYPE_NAME(c.user_type_id), c.column_id
        FROM sys.columns c
        WHERE c.object_id = OBJECT_ID(@FullPath)
        ORDER BY c.column_id;
    
    OPEN ColumnCursor;
    FETCH NEXT FROM ColumnCursor INTO @ColumnName, @DataType, @ColumnID;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @SQL = N'
            INSERT INTO #Profile
            SELECT 
                @ColName AS ColumnName,
                @ColType AS DataType,
                @Total AS TotalRows,
                SUM(CASE WHEN ' + QUOTENAME(@ColumnName) + ' IS NULL THEN 1 ELSE 0 END) AS NullCount,
                CAST(SUM(CASE WHEN ' + QUOTENAME(@ColumnName) + ' IS NULL THEN 1 ELSE 0 END) * 100.0 / @Total AS DECIMAL(5,2)) AS NullPercent,
                COUNT(DISTINCT ' + QUOTENAME(@ColumnName) + ') AS DistinctCount,
                CAST(COUNT(DISTINCT ' + QUOTENAME(@ColumnName) + ') * 100.0 / NULLIF(COUNT(' + QUOTENAME(@ColumnName) + '), 0) AS DECIMAL(5,2)) AS UniquePercent,
                MIN(LEN(CAST(' + QUOTENAME(@ColumnName) + ' AS NVARCHAR(MAX)))) AS MinLength,
                MAX(LEN(CAST(' + QUOTENAME(@ColumnName) + ' AS NVARCHAR(MAX)))) AS MaxLength,
                AVG(CAST(LEN(CAST(' + QUOTENAME(@ColumnName) + ' AS NVARCHAR(MAX))) AS DECIMAL(10,2))) AS AvgLength,
                CAST(MIN(' + QUOTENAME(@ColumnName) + ') AS NVARCHAR(500)) AS MinValue,
                CAST(MAX(' + QUOTENAME(@ColumnName) + ') AS NVARCHAR(500)) AS MaxValue,
                (SELECT STRING_AGG(CAST(val AS NVARCHAR(100)), '', '') 
                 FROM (SELECT DISTINCT TOP 5 ' + QUOTENAME(@ColumnName) + ' AS val 
                       FROM ' + @FullPath + ' 
                       WHERE ' + QUOTENAME(@ColumnName) + ' IS NOT NULL 
                       ORDER BY val) x) AS SampleValues
            FROM ' + @FullPath;
        
        EXEC sp_executesql @SQL,
            N'@ColName NVARCHAR(128), @ColType NVARCHAR(128), @Total BIGINT',
            @ColName = @ColumnName, @ColType = @DataType, @Total = @TotalRows;
        
        FETCH NEXT FROM ColumnCursor INTO @ColumnName, @DataType, @ColumnID;
    END
    
    CLOSE ColumnCursor;
    DEALLOCATE ColumnCursor;
    
    SELECT * FROM #Profile ORDER BY ColumnName;
    DROP TABLE #Profile;
END
GO

-- Calculate data quality score
CREATE PROCEDURE dbo.CalculateDataQualityScore
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @Rules NVARCHAR(MAX) = NULL  -- JSON rules
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FullPath NVARCHAR(256) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    DECLARE @TotalRows BIGINT;
    DECLARE @TotalChecks INT = 0;
    DECLARE @PassedChecks DECIMAL(18,2) = 0;
    
    -- Get row count
    SET @SQL = N'SELECT @Cnt = COUNT(*) FROM ' + @FullPath;
    EXEC sp_executesql @SQL, N'@Cnt BIGINT OUTPUT', @Cnt = @TotalRows OUTPUT;
    
    -- Quality metrics table
    CREATE TABLE #QualityMetrics (
        MetricName NVARCHAR(100),
        MetricType NVARCHAR(50),
        ColumnName NVARCHAR(128),
        TotalRecords BIGINT,
        PassingRecords BIGINT,
        Score DECIMAL(5,2),
        Details NVARCHAR(MAX)
    );
    
    -- Completeness check (NULL values)
    INSERT INTO #QualityMetrics
    SELECT 
        'Completeness' AS MetricName,
        'NULL Check' AS MetricType,
        c.name AS ColumnName,
        @TotalRows AS TotalRecords,
        0 AS PassingRecords,
        0 AS Score,
        NULL AS Details
    FROM sys.columns c
    WHERE c.object_id = OBJECT_ID(@FullPath);
    
    -- Update completeness scores dynamically
    DECLARE @ColName NVARCHAR(128);
    DECLARE CompCursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT ColumnName FROM #QualityMetrics WHERE MetricType = 'NULL Check';
    
    OPEN CompCursor;
    FETCH NEXT FROM CompCursor INTO @ColName;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @SQL = N'
            UPDATE #QualityMetrics
            SET PassingRecords = (SELECT COUNT(*) FROM ' + @FullPath + ' WHERE ' + QUOTENAME(@ColName) + ' IS NOT NULL),
                Score = CAST((SELECT COUNT(*) FROM ' + @FullPath + ' WHERE ' + QUOTENAME(@ColName) + ' IS NOT NULL) * 100.0 / @Total AS DECIMAL(5,2))
            WHERE ColumnName = @Col AND MetricType = ''NULL Check''';
        
        EXEC sp_executesql @SQL, N'@Total BIGINT, @Col NVARCHAR(128)', @Total = @TotalRows, @Col = @ColName;
        
        FETCH NEXT FROM CompCursor INTO @ColName;
    END
    
    CLOSE CompCursor;
    DEALLOCATE CompCursor;
    
    -- Uniqueness check for potential key columns
    INSERT INTO #QualityMetrics
    SELECT 
        'Uniqueness' AS MetricName,
        'Duplicate Check' AS MetricType,
        c.name AS ColumnName,
        @TotalRows AS TotalRecords,
        0 AS PassingRecords,
        0 AS Score,
        NULL AS Details
    FROM sys.columns c
    INNER JOIN sys.index_columns ic ON c.object_id = ic.object_id AND c.column_id = ic.column_id
    INNER JOIN sys.indexes i ON ic.object_id = i.object_id AND ic.index_id = i.index_id
    WHERE c.object_id = OBJECT_ID(@FullPath)
      AND (i.is_primary_key = 1 OR i.is_unique = 1);
    
    -- Return quality report
    SELECT 
        MetricName,
        MetricType,
        ColumnName,
        TotalRecords,
        PassingRecords,
        Score AS QualityScore,
        CASE 
            WHEN Score >= 95 THEN 'Excellent'
            WHEN Score >= 80 THEN 'Good'
            WHEN Score >= 60 THEN 'Fair'
            ELSE 'Poor'
        END AS Rating
    FROM #QualityMetrics
    ORDER BY MetricName, ColumnName;
    
    -- Overall score
    SELECT 
        AVG(Score) AS OverallQualityScore,
        COUNT(*) AS TotalChecks,
        SUM(CASE WHEN Score >= 95 THEN 1 ELSE 0 END) AS ExcellentCount,
        SUM(CASE WHEN Score < 60 THEN 1 ELSE 0 END) AS PoorCount
    FROM #QualityMetrics;
    
    DROP TABLE #QualityMetrics;
END
GO

-- Find data anomalies
CREATE PROCEDURE dbo.FindDataAnomalies
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @NumericColumn NVARCHAR(128),
    @StdDevThreshold FLOAT = 3.0  -- Outliers beyond N standard deviations
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FullPath NVARCHAR(256) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    
    SET @SQL = N'
        ;WITH Stats AS (
            SELECT 
                AVG(CAST(' + QUOTENAME(@NumericColumn) + ' AS FLOAT)) AS Mean,
                STDEV(CAST(' + QUOTENAME(@NumericColumn) + ' AS FLOAT)) AS StdDev
            FROM ' + @FullPath + '
            WHERE ' + QUOTENAME(@NumericColumn) + ' IS NOT NULL
        )
        SELECT 
            t.*,
            (CAST(t.' + QUOTENAME(@NumericColumn) + ' AS FLOAT) - s.Mean) / NULLIF(s.StdDev, 0) AS ZScore,
            CASE 
                WHEN ABS((CAST(t.' + QUOTENAME(@NumericColumn) + ' AS FLOAT) - s.Mean) / NULLIF(s.StdDev, 0)) > @Threshold
                THEN ''Outlier''
                ELSE ''Normal''
            END AS Classification
        FROM ' + @FullPath + ' t
        CROSS JOIN Stats s
        WHERE ABS((CAST(t.' + QUOTENAME(@NumericColumn) + ' AS FLOAT) - s.Mean) / NULLIF(s.StdDev, 0)) > @Threshold
        ORDER BY ABS((CAST(t.' + QUOTENAME(@NumericColumn) + ' AS FLOAT) - s.Mean) / NULLIF(s.StdDev, 0)) DESC';
    
    EXEC sp_executesql @SQL, N'@Threshold FLOAT', @Threshold = @StdDevThreshold;
END
GO

-- Check referential integrity
CREATE PROCEDURE dbo.CheckReferentialIntegrity
    @SchemaName NVARCHAR(128) = 'dbo'
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @Results TABLE (
        ForeignKeyName NVARCHAR(128),
        ParentTable NVARCHAR(256),
        ReferencedTable NVARCHAR(256),
        OrphanedCount INT,
        SampleOrphanedValues NVARCHAR(MAX)
    );
    
    -- Check each foreign key
    DECLARE @FKName NVARCHAR(128), @ParentTable NVARCHAR(256), @RefTable NVARCHAR(256);
    DECLARE @ParentCol NVARCHAR(128), @RefCol NVARCHAR(128);
    
    DECLARE FKCursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT 
            fk.name,
            QUOTENAME(OBJECT_SCHEMA_NAME(fk.parent_object_id)) + '.' + QUOTENAME(OBJECT_NAME(fk.parent_object_id)),
            QUOTENAME(OBJECT_SCHEMA_NAME(fk.referenced_object_id)) + '.' + QUOTENAME(OBJECT_NAME(fk.referenced_object_id)),
            COL_NAME(fkc.parent_object_id, fkc.parent_column_id),
            COL_NAME(fkc.referenced_object_id, fkc.referenced_column_id)
        FROM sys.foreign_keys fk
        INNER JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
        WHERE OBJECT_SCHEMA_NAME(fk.parent_object_id) = @SchemaName;
    
    OPEN FKCursor;
    FETCH NEXT FROM FKCursor INTO @FKName, @ParentTable, @RefTable, @ParentCol, @RefCol;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @SQL = N'
            SELECT 
                @FK AS ForeignKeyName,
                @PT AS ParentTable,
                @RT AS ReferencedTable,
                COUNT(*) AS OrphanedCount,
                (SELECT STRING_AGG(CAST(' + QUOTENAME(@ParentCol) + ' AS NVARCHAR(100)), '','') 
                 FROM (SELECT DISTINCT TOP 5 ' + QUOTENAME(@ParentCol) + ' 
                       FROM ' + @ParentTable + ' p
                       WHERE NOT EXISTS (SELECT 1 FROM ' + @RefTable + ' r WHERE r.' + QUOTENAME(@RefCol) + ' = p.' + QUOTENAME(@ParentCol) + ')
                         AND p.' + QUOTENAME(@ParentCol) + ' IS NOT NULL) x) AS SampleOrphanedValues
            FROM ' + @ParentTable + ' p
            WHERE NOT EXISTS (SELECT 1 FROM ' + @RefTable + ' r WHERE r.' + QUOTENAME(@RefCol) + ' = p.' + QUOTENAME(@ParentCol) + ')
              AND p.' + QUOTENAME(@ParentCol) + ' IS NOT NULL
            HAVING COUNT(*) > 0';
        
        BEGIN TRY
            INSERT INTO @Results
            EXEC sp_executesql @SQL,
                N'@FK NVARCHAR(128), @PT NVARCHAR(256), @RT NVARCHAR(256)',
                @FK = @FKName, @PT = @ParentTable, @RT = @RefTable;
        END TRY
        BEGIN CATCH
            -- Skip errors
        END CATCH
        
        FETCH NEXT FROM FKCursor INTO @FKName, @ParentTable, @RefTable, @ParentCol, @RefCol;
    END
    
    CLOSE FKCursor;
    DEALLOCATE FKCursor;
    
    SELECT * FROM @Results ORDER BY OrphanedCount DESC;
END
GO
