-- Sample 028: Data Archiving Procedures
-- Source: MSSQLTips, SQLServerCentral, Various
-- Category: ETL/Data Loading
-- Complexity: Advanced
-- Features: Batch processing, partition switching, archival strategies, compression

-- Archive data to history table in batches
CREATE PROCEDURE dbo.ArchiveDataInBatches
    @SourceSchema NVARCHAR(128) = 'dbo',
    @SourceTable NVARCHAR(128),
    @ArchiveSchema NVARCHAR(128) = 'archive',
    @ArchiveTable NVARCHAR(128) = NULL,
    @DateColumn NVARCHAR(128),
    @CutoffDate DATE,
    @BatchSize INT = 10000,
    @MaxBatches INT = NULL,  -- NULL = no limit
    @DeleteAfterArchive BIT = 1,
    @LogProgress BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @RowsAffected INT = 1;
    DECLARE @TotalArchived INT = 0;
    DECLARE @TotalDeleted INT = 0;
    DECLARE @BatchCount INT = 0;
    DECLARE @StartTime DATETIME = GETDATE();
    
    SET @ArchiveTable = ISNULL(@ArchiveTable, @SourceTable + '_Archive');
    
    -- Create archive table if not exists
    IF OBJECT_ID(@ArchiveSchema + '.' + @ArchiveTable) IS NULL
    BEGIN
        SET @SQL = N'
            SELECT * INTO ' + QUOTENAME(@ArchiveSchema) + '.' + QUOTENAME(@ArchiveTable) + '
            FROM ' + QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable) + '
            WHERE 1 = 0';
        EXEC sp_executesql @SQL;
        
        IF @LogProgress = 1
            PRINT 'Created archive table: ' + @ArchiveSchema + '.' + @ArchiveTable;
    END
    
    -- Archive in batches
    WHILE @RowsAffected > 0 AND (@MaxBatches IS NULL OR @BatchCount < @MaxBatches)
    BEGIN
        BEGIN TRY
            BEGIN TRANSACTION;
            
            -- Insert to archive
            SET @SQL = N'
                INSERT INTO ' + QUOTENAME(@ArchiveSchema) + '.' + QUOTENAME(@ArchiveTable) + '
                SELECT TOP (@BatchSize) *
                FROM ' + QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable) + '
                WHERE ' + QUOTENAME(@DateColumn) + ' < @CutoffDate';
            
            EXEC sp_executesql @SQL,
                N'@BatchSize INT, @CutoffDate DATE',
                @BatchSize = @BatchSize,
                @CutoffDate = @CutoffDate;
            
            SET @RowsAffected = @@ROWCOUNT;
            SET @TotalArchived = @TotalArchived + @RowsAffected;
            
            -- Delete from source
            IF @DeleteAfterArchive = 1 AND @RowsAffected > 0
            BEGIN
                SET @SQL = N'
                    DELETE TOP (@BatchSize)
                    FROM ' + QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable) + '
                    WHERE ' + QUOTENAME(@DateColumn) + ' < @CutoffDate';
                
                EXEC sp_executesql @SQL,
                    N'@BatchSize INT, @CutoffDate DATE',
                    @BatchSize = @BatchSize,
                    @CutoffDate = @CutoffDate;
                
                SET @TotalDeleted = @TotalDeleted + @@ROWCOUNT;
            END
            
            COMMIT TRANSACTION;
            
            SET @BatchCount = @BatchCount + 1;
            
            IF @LogProgress = 1 AND @RowsAffected > 0
                PRINT 'Batch ' + CAST(@BatchCount AS VARCHAR(10)) + ': ' + 
                      CAST(@RowsAffected AS VARCHAR(10)) + ' rows archived';
            
            -- Small delay to reduce blocking
            IF @RowsAffected > 0
                WAITFOR DELAY '00:00:00.100';
                
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0
                ROLLBACK TRANSACTION;
            
            THROW;
        END CATCH
    END
    
    -- Return summary
    SELECT 
        @SourceSchema + '.' + @SourceTable AS SourceTable,
        @ArchiveSchema + '.' + @ArchiveTable AS ArchiveTable,
        @TotalArchived AS RowsArchived,
        @TotalDeleted AS RowsDeleted,
        @BatchCount AS BatchesProcessed,
        DATEDIFF(SECOND, @StartTime, GETDATE()) AS DurationSeconds,
        @CutoffDate AS CutoffDate;
END
GO

-- Archive using partition switching (fastest method)
CREATE PROCEDURE dbo.ArchivePartitionSwitch
    @SourceSchema NVARCHAR(128) = 'dbo',
    @SourceTable NVARCHAR(128),
    @ArchiveSchema NVARCHAR(128) = 'archive',
    @ArchiveTable NVARCHAR(128),
    @PartitionNumber INT,
    @CreateArchiveIfNotExists BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @StartTime DATETIME = GETDATE();
    DECLARE @RowCount BIGINT;
    
    -- Get row count in partition
    SELECT @RowCount = p.rows
    FROM sys.partitions p
    INNER JOIN sys.tables t ON p.object_id = t.object_id
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = @SourceSchema
      AND t.name = @SourceTable
      AND p.partition_number = @PartitionNumber
      AND p.index_id IN (0, 1);
    
    -- Create archive table if needed (must match structure exactly)
    IF @CreateArchiveIfNotExists = 1 AND OBJECT_ID(@ArchiveSchema + '.' + @ArchiveTable) IS NULL
    BEGIN
        -- For partition switching, archive table must be on same filegroup
        -- and have identical structure
        SET @SQL = N'
            SELECT * INTO ' + QUOTENAME(@ArchiveSchema) + '.' + QUOTENAME(@ArchiveTable) + '
            FROM ' + QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable) + '
            WHERE 1 = 0';
        EXEC sp_executesql @SQL;
        
        PRINT 'Created archive table: ' + @ArchiveSchema + '.' + @ArchiveTable;
    END
    
    BEGIN TRY
        -- Perform partition switch
        SET @SQL = N'
            ALTER TABLE ' + QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable) + '
            SWITCH PARTITION ' + CAST(@PartitionNumber AS NVARCHAR(10)) + '
            TO ' + QUOTENAME(@ArchiveSchema) + '.' + QUOTENAME(@ArchiveTable);
        
        EXEC sp_executesql @SQL;
        
        SELECT 
            'Partition switch completed' AS Status,
            @SourceSchema + '.' + @SourceTable AS SourceTable,
            @ArchiveSchema + '.' + @ArchiveTable AS ArchiveTable,
            @PartitionNumber AS PartitionNumber,
            @RowCount AS RowsSwitched,
            DATEDIFF(MILLISECOND, @StartTime, GETDATE()) AS DurationMs;
            
    END TRY
    BEGIN CATCH
        SELECT 
            'Partition switch failed' AS Status,
            ERROR_MESSAGE() AS ErrorMessage;
        
        THROW;
    END CATCH
END
GO

-- Purge old data with logging
CREATE PROCEDURE dbo.PurgeOldData
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @DateColumn NVARCHAR(128),
    @RetentionDays INT,
    @BatchSize INT = 5000,
    @MaxDurationMinutes INT = 30,
    @LogTableName NVARCHAR(128) = 'DataPurgeLog'
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @RowsDeleted INT = 1;
    DECLARE @TotalDeleted INT = 0;
    DECLARE @StartTime DATETIME = GETDATE();
    DECLARE @CutoffDate DATE = DATEADD(DAY, -@RetentionDays, GETDATE());
    DECLARE @PurgeID INT;
    
    -- Create log table if not exists
    IF OBJECT_ID('dbo.' + @LogTableName) IS NULL
    BEGIN
        SET @SQL = N'
            CREATE TABLE dbo.' + QUOTENAME(@LogTableName) + ' (
                PurgeID INT IDENTITY(1,1) PRIMARY KEY,
                TableName NVARCHAR(256),
                CutoffDate DATE,
                RowsDeleted INT,
                StartTime DATETIME,
                EndTime DATETIME,
                DurationSeconds INT,
                Status NVARCHAR(20),
                ErrorMessage NVARCHAR(MAX)
            )';
        EXEC sp_executesql @SQL;
    END
    
    -- Start log entry
    SET @SQL = N'
        INSERT INTO dbo.' + QUOTENAME(@LogTableName) + ' 
        (TableName, CutoffDate, RowsDeleted, StartTime, Status)
        VALUES (@TableName, @CutoffDate, 0, @StartTime, ''Running'');
        SELECT @PurgeID = SCOPE_IDENTITY();';
    
    EXEC sp_executesql @SQL,
        N'@TableName NVARCHAR(256), @CutoffDate DATE, @StartTime DATETIME, @PurgeID INT OUTPUT',
        @TableName = @SchemaName + '.' + @TableName,
        @CutoffDate = @CutoffDate,
        @StartTime = @StartTime,
        @PurgeID = @PurgeID OUTPUT;
    
    BEGIN TRY
        -- Delete in batches
        WHILE @RowsDeleted > 0 
          AND DATEDIFF(MINUTE, @StartTime, GETDATE()) < @MaxDurationMinutes
        BEGIN
            SET @SQL = N'
                DELETE TOP (@BatchSize)
                FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + '
                WHERE ' + QUOTENAME(@DateColumn) + ' < @CutoffDate';
            
            EXEC sp_executesql @SQL,
                N'@BatchSize INT, @CutoffDate DATE',
                @BatchSize = @BatchSize,
                @CutoffDate = @CutoffDate;
            
            SET @RowsDeleted = @@ROWCOUNT;
            SET @TotalDeleted = @TotalDeleted + @RowsDeleted;
            
            -- Brief pause
            IF @RowsDeleted > 0
                WAITFOR DELAY '00:00:00.050';
        END
        
        -- Update log
        SET @SQL = N'
            UPDATE dbo.' + QUOTENAME(@LogTableName) + '
            SET RowsDeleted = @TotalDeleted,
                EndTime = GETDATE(),
                DurationSeconds = DATEDIFF(SECOND, StartTime, GETDATE()),
                Status = ''Completed''
            WHERE PurgeID = @PurgeID';
        
        EXEC sp_executesql @SQL,
            N'@TotalDeleted INT, @PurgeID INT',
            @TotalDeleted = @TotalDeleted,
            @PurgeID = @PurgeID;
            
    END TRY
    BEGIN CATCH
        -- Log error
        SET @SQL = N'
            UPDATE dbo.' + QUOTENAME(@LogTableName) + '
            SET RowsDeleted = @TotalDeleted,
                EndTime = GETDATE(),
                DurationSeconds = DATEDIFF(SECOND, StartTime, GETDATE()),
                Status = ''Failed'',
                ErrorMessage = @ErrorMsg
            WHERE PurgeID = @PurgeID';
        
        EXEC sp_executesql @SQL,
            N'@TotalDeleted INT, @PurgeID INT, @ErrorMsg NVARCHAR(MAX)',
            @TotalDeleted = @TotalDeleted,
            @PurgeID = @PurgeID,
            @ErrorMsg = ERROR_MESSAGE();
        
        THROW;
    END CATCH
    
    -- Return summary
    SELECT 
        @SchemaName + '.' + @TableName AS TableName,
        @CutoffDate AS CutoffDate,
        @TotalDeleted AS RowsDeleted,
        DATEDIFF(SECOND, @StartTime, GETDATE()) AS DurationSeconds;
END
GO

-- Create compressed archive table
CREATE PROCEDURE dbo.CreateCompressedArchive
    @SourceSchema NVARCHAR(128),
    @SourceTable NVARCHAR(128),
    @ArchiveSchema NVARCHAR(128) = 'archive',
    @CompressionType NVARCHAR(20) = 'PAGE'  -- PAGE, ROW, NONE
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @ArchiveTable NVARCHAR(128) = @SourceTable + '_Archive';
    
    -- Create schema if not exists
    IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = @ArchiveSchema)
    BEGIN
        SET @SQL = 'CREATE SCHEMA ' + QUOTENAME(@ArchiveSchema);
        EXEC sp_executesql @SQL;
    END
    
    -- Create archive table with compression
    SET @SQL = N'
        CREATE TABLE ' + QUOTENAME(@ArchiveSchema) + '.' + QUOTENAME(@ArchiveTable) + ' (';
    
    -- Get column definitions
    SELECT @SQL = @SQL + 
        QUOTENAME(c.name) + ' ' + 
        tp.name + 
        CASE 
            WHEN tp.name IN ('varchar', 'nvarchar', 'char', 'nchar') 
            THEN '(' + CASE WHEN c.max_length = -1 THEN 'MAX' ELSE CAST(c.max_length AS VARCHAR(10)) END + ')'
            WHEN tp.name IN ('decimal', 'numeric')
            THEN '(' + CAST(c.precision AS VARCHAR(10)) + ',' + CAST(c.scale AS VARCHAR(10)) + ')'
            ELSE ''
        END +
        CASE WHEN c.is_nullable = 1 THEN ' NULL' ELSE ' NOT NULL' END + ','
    FROM sys.columns c
    INNER JOIN sys.types tp ON c.user_type_id = tp.user_type_id
    WHERE c.object_id = OBJECT_ID(@SourceSchema + '.' + @SourceTable)
    ORDER BY c.column_id;
    
    -- Remove trailing comma
    SET @SQL = LEFT(@SQL, LEN(@SQL) - 1);
    
    SET @SQL = @SQL + ')';
    
    -- Add compression
    IF @CompressionType <> 'NONE'
        SET @SQL = @SQL + ' WITH (DATA_COMPRESSION = ' + @CompressionType + ')';
    
    EXEC sp_executesql @SQL;
    
    SELECT 
        'Archive table created' AS Status,
        @ArchiveSchema + '.' + @ArchiveTable AS ArchiveTable,
        @CompressionType AS Compression;
END
GO
