-- Sample 063: Data Compression Management
-- Source: Microsoft Learn, MSSQLTips, Erin Stellato
-- Category: Performance
-- Complexity: Advanced
-- Features: ROW compression, PAGE compression, sp_estimate_data_compression_savings

-- Estimate compression savings for a table
CREATE PROCEDURE dbo.EstimateCompressionSavings
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @IndexId INT = NULL  -- NULL = all indexes including heap
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @ObjectId INT = OBJECT_ID(QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName));
    
    -- Current size
    SELECT 
        i.name AS IndexName,
        i.index_id,
        p.data_compression_desc AS CurrentCompression,
        CAST(SUM(ps.used_page_count) * 8.0 / 1024 AS DECIMAL(18,2)) AS CurrentSizeMB
    INTO #CurrentSize
    FROM sys.indexes i
    INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
    INNER JOIN sys.dm_db_partition_stats ps ON p.partition_id = ps.partition_id
    WHERE i.object_id = @ObjectId
      AND (@IndexId IS NULL OR i.index_id = @IndexId)
    GROUP BY i.name, i.index_id, p.data_compression_desc;
    
    -- Estimate ROW compression
    CREATE TABLE #RowEstimate (
        object_name SYSNAME,
        schema_name SYSNAME,
        index_id INT,
        partition_number INT,
        size_with_current_compression_setting_KB BIGINT,
        size_with_requested_compression_setting_KB BIGINT,
        sample_size_with_current_compression_setting_KB BIGINT,
        sample_size_with_requested_compression_setting_KB BIGINT
    );
    
    INSERT INTO #RowEstimate
    EXEC sp_estimate_data_compression_savings 
        @schema_name = @SchemaName,
        @object_name = @TableName,
        @index_id = @IndexId,
        @partition_number = NULL,
        @data_compression = 'ROW';
    
    -- Estimate PAGE compression
    CREATE TABLE #PageEstimate (
        object_name SYSNAME,
        schema_name SYSNAME,
        index_id INT,
        partition_number INT,
        size_with_current_compression_setting_KB BIGINT,
        size_with_requested_compression_setting_KB BIGINT,
        sample_size_with_current_compression_setting_KB BIGINT,
        sample_size_with_requested_compression_setting_KB BIGINT
    );
    
    INSERT INTO #PageEstimate
    EXEC sp_estimate_data_compression_savings 
        @schema_name = @SchemaName,
        @object_name = @TableName,
        @index_id = @IndexId,
        @partition_number = NULL,
        @data_compression = 'PAGE';
    
    -- Return comparison
    SELECT 
        c.IndexName,
        c.index_id AS IndexId,
        c.CurrentCompression,
        c.CurrentSizeMB,
        CAST(r.size_with_requested_compression_setting_KB / 1024.0 AS DECIMAL(18,2)) AS EstimatedRowCompressionMB,
        CAST(p.size_with_requested_compression_setting_KB / 1024.0 AS DECIMAL(18,2)) AS EstimatedPageCompressionMB,
        CAST((c.CurrentSizeMB - r.size_with_requested_compression_setting_KB / 1024.0) AS DECIMAL(18,2)) AS RowSavingsMB,
        CAST((c.CurrentSizeMB - p.size_with_requested_compression_setting_KB / 1024.0) AS DECIMAL(18,2)) AS PageSavingsMB,
        CAST((1 - r.size_with_requested_compression_setting_KB / 1024.0 / NULLIF(c.CurrentSizeMB, 0)) * 100 AS DECIMAL(5,2)) AS RowSavingsPercent,
        CAST((1 - p.size_with_requested_compression_setting_KB / 1024.0 / NULLIF(c.CurrentSizeMB, 0)) * 100 AS DECIMAL(5,2)) AS PageSavingsPercent
    FROM #CurrentSize c
    LEFT JOIN #RowEstimate r ON c.index_id = r.index_id
    LEFT JOIN #PageEstimate p ON c.index_id = p.index_id
    ORDER BY c.index_id;
    
    DROP TABLE #CurrentSize, #RowEstimate, #PageEstimate;
END
GO

-- Apply compression to table/index
CREATE PROCEDURE dbo.ApplyCompression
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @CompressionType NVARCHAR(10) = 'PAGE',  -- NONE, ROW, PAGE
    @IndexName NVARCHAR(128) = NULL,  -- NULL = all indexes
    @Online BIT = 1,
    @WhatIf BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FullPath NVARCHAR(256) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    DECLARE @Scripts TABLE (Script NVARCHAR(MAX));
    
    -- Generate rebuild scripts
    IF @IndexName IS NULL
    BEGIN
        -- Rebuild all indexes
        INSERT INTO @Scripts
        SELECT 
            'ALTER INDEX ' + QUOTENAME(i.name) + ' ON ' + @FullPath + 
            ' REBUILD WITH (DATA_COMPRESSION = ' + @CompressionType +
            CASE WHEN @Online = 1 THEN ', ONLINE = ON' ELSE '' END + ');'
        FROM sys.indexes i
        WHERE i.object_id = OBJECT_ID(@FullPath)
          AND i.type > 0  -- Not heap
          AND i.is_disabled = 0;
        
        -- Handle heap separately
        IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(@FullPath) AND type = 0)
        BEGIN
            INSERT INTO @Scripts
            SELECT 'ALTER TABLE ' + @FullPath + ' REBUILD WITH (DATA_COMPRESSION = ' + @CompressionType + ');';
        END
    END
    ELSE
    BEGIN
        INSERT INTO @Scripts
        SELECT 
            'ALTER INDEX ' + QUOTENAME(@IndexName) + ' ON ' + @FullPath + 
            ' REBUILD WITH (DATA_COMPRESSION = ' + @CompressionType +
            CASE WHEN @Online = 1 THEN ', ONLINE = ON' ELSE '' END + ');';
    END
    
    IF @WhatIf = 1
    BEGIN
        SELECT 'WhatIf Mode - Scripts to execute:' AS Status;
        SELECT Script FROM @Scripts;
    END
    ELSE
    BEGIN
        DECLARE @Script NVARCHAR(MAX);
        DECLARE ScriptCursor CURSOR LOCAL FAST_FORWARD FOR SELECT Script FROM @Scripts;
        
        OPEN ScriptCursor;
        FETCH NEXT FROM ScriptCursor INTO @Script;
        
        WHILE @@FETCH_STATUS = 0
        BEGIN
            PRINT 'Executing: ' + @Script;
            EXEC sp_executesql @Script;
            FETCH NEXT FROM ScriptCursor INTO @Script;
        END
        
        CLOSE ScriptCursor;
        DEALLOCATE ScriptCursor;
        
        SELECT 'Compression applied successfully' AS Status;
    END
END
GO

-- Get compression status for all tables
CREATE PROCEDURE dbo.GetCompressionStatus
    @SchemaName NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        OBJECT_SCHEMA_NAME(i.object_id) AS SchemaName,
        OBJECT_NAME(i.object_id) AS TableName,
        i.name AS IndexName,
        i.type_desc AS IndexType,
        p.data_compression_desc AS CompressionType,
        CAST(SUM(ps.used_page_count) * 8.0 / 1024 AS DECIMAL(18,2)) AS SizeMB,
        SUM(ps.row_count) AS RowCount
    FROM sys.indexes i
    INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
    INNER JOIN sys.dm_db_partition_stats ps ON p.partition_id = ps.partition_id
    WHERE OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1
      AND (@SchemaName IS NULL OR OBJECT_SCHEMA_NAME(i.object_id) = @SchemaName)
    GROUP BY i.object_id, i.name, i.type_desc, p.data_compression_desc
    ORDER BY SizeMB DESC;
    
    -- Summary
    SELECT 
        p.data_compression_desc AS CompressionType,
        COUNT(DISTINCT i.object_id) AS TableCount,
        CAST(SUM(ps.used_page_count) * 8.0 / 1024 AS DECIMAL(18,2)) AS TotalSizeMB
    FROM sys.indexes i
    INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
    INNER JOIN sys.dm_db_partition_stats ps ON p.partition_id = ps.partition_id
    WHERE OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1
      AND i.index_id IN (0, 1)  -- Heap or clustered only
    GROUP BY p.data_compression_desc;
END
GO

-- Find compression candidates
CREATE PROCEDURE dbo.FindCompressionCandidates
    @MinSizeMB DECIMAL(18,2) = 100,
    @MinSavingsPercent INT = 25
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @Results TABLE (
        SchemaName NVARCHAR(128),
        TableName NVARCHAR(128),
        CurrentSizeMB DECIMAL(18,2),
        EstimatedCompressedMB DECIMAL(18,2),
        SavingsPercent DECIMAL(5,2),
        RecommendedCompression NVARCHAR(10)
    );
    
    DECLARE @Schema NVARCHAR(128), @Table NVARCHAR(128);
    DECLARE @CurrentSize DECIMAL(18,2);
    
    DECLARE TableCursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT 
            OBJECT_SCHEMA_NAME(i.object_id),
            OBJECT_NAME(i.object_id),
            CAST(SUM(ps.used_page_count) * 8.0 / 1024 AS DECIMAL(18,2))
        FROM sys.indexes i
        INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
        INNER JOIN sys.dm_db_partition_stats ps ON p.partition_id = ps.partition_id
        WHERE OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1
          AND i.index_id IN (0, 1)
          AND p.data_compression = 0  -- Currently uncompressed
        GROUP BY i.object_id
        HAVING SUM(ps.used_page_count) * 8.0 / 1024 >= @MinSizeMB;
    
    OPEN TableCursor;
    FETCH NEXT FROM TableCursor INTO @Schema, @Table, @CurrentSize;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            -- Quick estimate using PAGE compression
            CREATE TABLE #Est (
                object_name SYSNAME, schema_name SYSNAME, index_id INT, partition_number INT,
                size_current BIGINT, size_requested BIGINT, sample_current BIGINT, sample_requested BIGINT
            );
            
            INSERT INTO #Est
            EXEC sp_estimate_data_compression_savings @Schema, @Table, NULL, NULL, 'PAGE';
            
            INSERT INTO @Results
            SELECT 
                @Schema, @Table, @CurrentSize,
                CAST(SUM(size_requested) / 1024.0 AS DECIMAL(18,2)),
                CAST((1 - SUM(size_requested) / 1024.0 / @CurrentSize) * 100 AS DECIMAL(5,2)),
                'PAGE'
            FROM #Est
            HAVING (1 - SUM(size_requested) / 1024.0 / @CurrentSize) * 100 >= @MinSavingsPercent;
            
            DROP TABLE #Est;
        END TRY
        BEGIN CATCH
            -- Skip tables that error
        END CATCH
        
        FETCH NEXT FROM TableCursor INTO @Schema, @Table, @CurrentSize;
    END
    
    CLOSE TableCursor;
    DEALLOCATE TableCursor;
    
    SELECT * FROM @Results ORDER BY SavingsPercent DESC;
END
GO
