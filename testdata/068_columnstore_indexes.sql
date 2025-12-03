-- Sample 068: Columnstore Index Management
-- Source: Microsoft Learn, Niko Neugebauer, MSSQLTips
-- Category: Performance
-- Complexity: Advanced
-- Features: Columnstore indexes, segment analysis, dictionary management

-- Create clustered columnstore index
CREATE PROCEDURE dbo.CreateClusteredColumnstoreIndex
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @IndexName NVARCHAR(128) = NULL,
    @CompressionDelay INT = 0,  -- minutes
    @DropExisting BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FullPath NVARCHAR(256) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    
    SET @IndexName = ISNULL(@IndexName, 'CCI_' + @TableName);
    
    -- Check for existing clustered index
    IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(@FullPath) AND type IN (1, 5))
    BEGIN
        IF @DropExisting = 0
        BEGIN
            RAISERROR('Table already has a clustered index. Set @DropExisting = 1 to replace.', 16, 1);
            RETURN;
        END
    END
    
    SET @SQL = N'
        CREATE CLUSTERED COLUMNSTORE INDEX ' + QUOTENAME(@IndexName) + '
        ON ' + @FullPath + '
        WITH (
            COMPRESSION_DELAY = ' + CAST(@CompressionDelay AS VARCHAR(10)) + ' MINUTES,
            DATA_COMPRESSION = COLUMNSTORE' +
            CASE WHEN @DropExisting = 1 THEN ', DROP_EXISTING = ON' ELSE '' END + '
        )';
    
    EXEC sp_executesql @SQL;
    
    SELECT 'Clustered columnstore index created' AS Status, @IndexName AS IndexName;
END
GO

-- Create nonclustered columnstore index
CREATE PROCEDURE dbo.CreateNonclusteredColumnstoreIndex
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @IndexName NVARCHAR(128) = NULL,
    @Columns NVARCHAR(MAX),  -- Comma-separated column list
    @FilterPredicate NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FullPath NVARCHAR(256) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    
    SET @IndexName = ISNULL(@IndexName, 'NCCI_' + @TableName);
    
    -- Build column list with proper quoting
    DECLARE @QuotedColumns NVARCHAR(MAX) = '';
    SELECT @QuotedColumns = @QuotedColumns + QUOTENAME(LTRIM(RTRIM(value))) + ', '
    FROM STRING_SPLIT(@Columns, ',');
    SET @QuotedColumns = LEFT(@QuotedColumns, LEN(@QuotedColumns) - 1);
    
    SET @SQL = N'
        CREATE NONCLUSTERED COLUMNSTORE INDEX ' + QUOTENAME(@IndexName) + '
        ON ' + @FullPath + ' (' + @QuotedColumns + ')' +
        CASE WHEN @FilterPredicate IS NOT NULL 
             THEN ' WHERE ' + @FilterPredicate 
             ELSE '' 
        END;
    
    EXEC sp_executesql @SQL;
    
    SELECT 'Nonclustered columnstore index created' AS Status, @IndexName AS IndexName;
END
GO

-- Analyze columnstore index segments
CREATE PROCEDURE dbo.AnalyzeColumnstoreSegments
    @SchemaName NVARCHAR(128) = NULL,
    @TableName NVARCHAR(128) = NULL,
    @ShowFragmentedOnly BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        OBJECT_SCHEMA_NAME(i.object_id) AS SchemaName,
        OBJECT_NAME(i.object_id) AS TableName,
        i.name AS IndexName,
        i.type_desc AS IndexType,
        p.partition_number AS PartitionNumber,
        rg.row_group_id AS RowGroupId,
        rg.state_desc AS RowGroupState,
        rg.total_rows AS TotalRows,
        rg.deleted_rows AS DeletedRows,
        CAST(rg.deleted_rows * 100.0 / NULLIF(rg.total_rows, 0) AS DECIMAL(5,2)) AS DeletedPercent,
        rg.size_in_bytes / 1024 AS SizeKB,
        rg.trim_reason_desc AS TrimReason
    FROM sys.indexes i
    INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
    INNER JOIN sys.column_store_row_groups rg ON p.object_id = rg.object_id 
        AND p.partition_number = rg.partition_number
        AND p.index_id = rg.index_id
    WHERE i.type IN (5, 6)  -- Columnstore indexes
      AND (@SchemaName IS NULL OR OBJECT_SCHEMA_NAME(i.object_id) = @SchemaName)
      AND (@TableName IS NULL OR OBJECT_NAME(i.object_id) = @TableName)
      AND (@ShowFragmentedOnly = 0 OR rg.deleted_rows > 0 OR rg.state_desc <> 'COMPRESSED')
    ORDER BY SchemaName, TableName, PartitionNumber, RowGroupId;
    
    -- Summary
    SELECT 
        OBJECT_SCHEMA_NAME(i.object_id) AS SchemaName,
        OBJECT_NAME(i.object_id) AS TableName,
        i.name AS IndexName,
        COUNT(*) AS TotalRowGroups,
        SUM(CASE WHEN rg.state_desc = 'COMPRESSED' THEN 1 ELSE 0 END) AS CompressedGroups,
        SUM(CASE WHEN rg.state_desc = 'OPEN' THEN 1 ELSE 0 END) AS OpenGroups,
        SUM(CASE WHEN rg.state_desc = 'CLOSED' THEN 1 ELSE 0 END) AS ClosedGroups,
        SUM(rg.total_rows) AS TotalRows,
        SUM(rg.deleted_rows) AS TotalDeletedRows,
        CAST(SUM(rg.deleted_rows) * 100.0 / NULLIF(SUM(rg.total_rows), 0) AS DECIMAL(5,2)) AS OverallDeletedPercent,
        CAST(SUM(rg.size_in_bytes) / 1024.0 / 1024.0 AS DECIMAL(18,2)) AS TotalSizeMB
    FROM sys.indexes i
    INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
    INNER JOIN sys.column_store_row_groups rg ON p.object_id = rg.object_id 
        AND p.partition_number = rg.partition_number
        AND p.index_id = rg.index_id
    WHERE i.type IN (5, 6)
      AND (@SchemaName IS NULL OR OBJECT_SCHEMA_NAME(i.object_id) = @SchemaName)
      AND (@TableName IS NULL OR OBJECT_NAME(i.object_id) = @TableName)
    GROUP BY i.object_id, i.name
    ORDER BY TotalSizeMB DESC;
END
GO

-- Analyze columnstore dictionary
CREATE PROCEDURE dbo.AnalyzeColumnstoreDictionary
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        c.name AS ColumnName,
        d.dictionary_id AS DictionaryId,
        d.type_desc AS DictionaryType,
        d.entry_count AS EntryCount,
        d.on_disk_size / 1024 AS SizeKB,
        CASE 
            WHEN d.entry_count > 0 
            THEN CAST(d.on_disk_size / d.entry_count AS INT) 
            ELSE 0 
        END AS BytesPerEntry
    FROM sys.column_store_dictionaries d
    INNER JOIN sys.partitions p ON d.hobt_id = p.hobt_id
    INNER JOIN sys.columns c ON p.object_id = c.object_id AND d.column_id = c.column_id
    WHERE p.object_id = OBJECT_ID(QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName))
    ORDER BY d.on_disk_size DESC;
END
GO

-- Reorganize columnstore index
CREATE PROCEDURE dbo.ReorganizeColumnstoreIndex
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @IndexName NVARCHAR(128) = NULL,
    @CompressAllRowGroups BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FullPath NVARCHAR(256) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    
    -- Get index name if not provided
    IF @IndexName IS NULL
    BEGIN
        SELECT @IndexName = name
        FROM sys.indexes
        WHERE object_id = OBJECT_ID(@FullPath) AND type IN (5, 6);
    END
    
    SET @SQL = N'
        ALTER INDEX ' + QUOTENAME(@IndexName) + ' ON ' + @FullPath + '
        REORGANIZE' +
        CASE WHEN @CompressAllRowGroups = 1 
             THEN ' WITH (COMPRESS_ALL_ROW_GROUPS = ON)' 
             ELSE '' 
        END;
    
    EXEC sp_executesql @SQL;
    
    SELECT 'Columnstore index reorganized' AS Status, @IndexName AS IndexName;
END
GO

-- Find columnstore candidates
CREATE PROCEDURE dbo.FindColumnstoreCandidates
    @MinRowCount BIGINT = 1000000,
    @MinSizeMB DECIMAL(18,2) = 100
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        OBJECT_SCHEMA_NAME(t.object_id) AS SchemaName,
        t.name AS TableName,
        SUM(ps.row_count) AS RowCount,
        CAST(SUM(ps.used_page_count) * 8.0 / 1024 AS DECIMAL(18,2)) AS CurrentSizeMB,
        COUNT(DISTINCT c.column_id) AS ColumnCount,
        SUM(CASE WHEN ty.name IN ('varchar', 'nvarchar', 'char', 'nchar') THEN 1 ELSE 0 END) AS StringColumns,
        SUM(CASE WHEN ty.name IN ('int', 'bigint', 'smallint', 'tinyint', 'decimal', 'numeric') THEN 1 ELSE 0 END) AS NumericColumns,
        CASE WHEN EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = t.object_id AND type IN (5,6)) 
             THEN 'Already has columnstore' 
             ELSE 'Good candidate' 
        END AS Recommendation
    FROM sys.tables t
    INNER JOIN sys.partitions p ON t.object_id = p.object_id
    INNER JOIN sys.dm_db_partition_stats ps ON p.partition_id = ps.partition_id
    INNER JOIN sys.columns c ON t.object_id = c.object_id
    INNER JOIN sys.types ty ON c.user_type_id = ty.user_type_id
    WHERE p.index_id IN (0, 1)
    GROUP BY t.object_id, t.name
    HAVING SUM(ps.row_count) >= @MinRowCount
       AND SUM(ps.used_page_count) * 8.0 / 1024 >= @MinSizeMB
    ORDER BY RowCount DESC;
END
GO
