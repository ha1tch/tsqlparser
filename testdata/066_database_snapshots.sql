-- Sample 066: Database Snapshot Management
-- Source: Microsoft Learn, MSSQLTips, Paul Randal
-- Category: Performance
-- Complexity: Complex
-- Features: Database snapshots, point-in-time recovery, reporting databases

-- Create database snapshot
CREATE PROCEDURE dbo.CreateDatabaseSnapshot
    @SourceDatabase NVARCHAR(128),
    @SnapshotName NVARCHAR(128) = NULL,
    @SnapshotPath NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FileList NVARCHAR(MAX) = '';
    
    -- Generate snapshot name if not provided
    SET @SnapshotName = ISNULL(@SnapshotName, 
        @SourceDatabase + '_Snapshot_' + FORMAT(SYSDATETIME(), 'yyyyMMdd_HHmmss'));
    
    -- Get default path from source database if not provided
    IF @SnapshotPath IS NULL
    BEGIN
        SELECT TOP 1 @SnapshotPath = LEFT(physical_name, LEN(physical_name) - CHARINDEX('\', REVERSE(physical_name)) + 1)
        FROM sys.master_files
        WHERE database_id = DB_ID(@SourceDatabase) AND type = 0;
    END
    
    -- Build file list for snapshot
    SELECT @FileList = @FileList + 
        '(NAME = ' + QUOTENAME(name) + ', FILENAME = N''' + 
        @SnapshotPath + @SnapshotName + '_' + name + '.ss''),'
    FROM sys.master_files
    WHERE database_id = DB_ID(@SourceDatabase)
      AND type = 0;  -- Data files only
    
    SET @FileList = LEFT(@FileList, LEN(@FileList) - 1);
    
    SET @SQL = N'
        CREATE DATABASE ' + QUOTENAME(@SnapshotName) + '
        ON ' + @FileList + '
        AS SNAPSHOT OF ' + QUOTENAME(@SourceDatabase);
    
    EXEC sp_executesql @SQL;
    
    SELECT 
        'Snapshot created successfully' AS Status,
        @SnapshotName AS SnapshotName,
        @SourceDatabase AS SourceDatabase,
        SYSDATETIME() AS CreatedAt;
END
GO

-- List all database snapshots
CREATE PROCEDURE dbo.ListDatabaseSnapshots
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        d.name AS SnapshotName,
        d.source_database_id,
        DB_NAME(d.source_database_id) AS SourceDatabase,
        d.create_date AS SnapshotCreated,
        DATEDIFF(HOUR, d.create_date, SYSDATETIME()) AS AgeHours,
        mf.name AS LogicalFileName,
        mf.physical_name AS SnapshotFile,
        CAST(mf.size * 8.0 / 1024 AS DECIMAL(18,2)) AS SparseSizeMB
    FROM sys.databases d
    INNER JOIN sys.master_files mf ON d.database_id = mf.database_id
    WHERE d.source_database_id IS NOT NULL
    ORDER BY d.create_date DESC;
    
    -- Summary by source database
    SELECT 
        DB_NAME(source_database_id) AS SourceDatabase,
        COUNT(*) AS SnapshotCount,
        MIN(create_date) AS OldestSnapshot,
        MAX(create_date) AS NewestSnapshot
    FROM sys.databases
    WHERE source_database_id IS NOT NULL
    GROUP BY source_database_id;
END
GO

-- Drop database snapshot
CREATE PROCEDURE dbo.DropDatabaseSnapshot
    @SnapshotName NVARCHAR(128) = NULL,
    @SourceDatabase NVARCHAR(128) = NULL,
    @OlderThanHours INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @DroppedCount INT = 0;
    DECLARE @Name NVARCHAR(128);
    
    DECLARE SnapCursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT name
        FROM sys.databases
        WHERE source_database_id IS NOT NULL
          AND (@SnapshotName IS NULL OR name = @SnapshotName)
          AND (@SourceDatabase IS NULL OR source_database_id = DB_ID(@SourceDatabase))
          AND (@OlderThanHours IS NULL OR DATEDIFF(HOUR, create_date, SYSDATETIME()) > @OlderThanHours);
    
    OPEN SnapCursor;
    FETCH NEXT FROM SnapCursor INTO @Name;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @SQL = 'DROP DATABASE ' + QUOTENAME(@Name);
        
        BEGIN TRY
            EXEC sp_executesql @SQL;
            SET @DroppedCount = @DroppedCount + 1;
            PRINT 'Dropped snapshot: ' + @Name;
        END TRY
        BEGIN CATCH
            PRINT 'Failed to drop snapshot: ' + @Name + ' - ' + ERROR_MESSAGE();
        END CATCH
        
        FETCH NEXT FROM SnapCursor INTO @Name;
    END
    
    CLOSE SnapCursor;
    DEALLOCATE SnapCursor;
    
    SELECT @DroppedCount AS SnapshotsDropped;
END
GO

-- Revert database from snapshot
CREATE PROCEDURE dbo.RevertDatabaseFromSnapshot
    @SnapshotName NVARCHAR(128),
    @ConfirmRevert BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @SourceDB NVARCHAR(128);
    
    -- Get source database
    SELECT @SourceDB = DB_NAME(source_database_id)
    FROM sys.databases
    WHERE name = @SnapshotName;
    
    IF @SourceDB IS NULL
    BEGIN
        RAISERROR('Snapshot not found or is not a valid database snapshot: %s', 16, 1, @SnapshotName);
        RETURN;
    END
    
    IF @ConfirmRevert = 0
    BEGIN
        SELECT 
            'WARNING: This will revert the database to the snapshot point-in-time!' AS Warning,
            @SourceDB AS DatabaseToRevert,
            @SnapshotName AS SnapshotToUse,
            d.create_date AS SnapshotPointInTime,
            'Set @ConfirmRevert = 1 to proceed' AS Action
        FROM sys.databases d
        WHERE d.name = @SnapshotName;
        RETURN;
    END
    
    -- Check for other snapshots that would be dropped
    IF EXISTS (
        SELECT 1 FROM sys.databases 
        WHERE source_database_id = DB_ID(@SourceDB) 
          AND name <> @SnapshotName
    )
    BEGIN
        SELECT 
            'These snapshots will be dropped:' AS Warning,
            name AS SnapshotName,
            create_date AS CreatedDate
        FROM sys.databases
        WHERE source_database_id = DB_ID(@SourceDB)
          AND name <> @SnapshotName;
    END
    
    -- Set database to single user
    SET @SQL = 'ALTER DATABASE ' + QUOTENAME(@SourceDB) + ' SET SINGLE_USER WITH ROLLBACK IMMEDIATE';
    EXEC sp_executesql @SQL;
    
    -- Restore from snapshot
    SET @SQL = 'RESTORE DATABASE ' + QUOTENAME(@SourceDB) + ' FROM DATABASE_SNAPSHOT = ' + QUOTENAME(@SnapshotName, '''');
    
    BEGIN TRY
        EXEC sp_executesql @SQL;
        
        -- Set back to multi user
        SET @SQL = 'ALTER DATABASE ' + QUOTENAME(@SourceDB) + ' SET MULTI_USER';
        EXEC sp_executesql @SQL;
        
        SELECT 'Database reverted successfully' AS Status, @SourceDB AS Database, @SnapshotName AS FromSnapshot;
    END TRY
    BEGIN CATCH
        -- Try to set back to multi user on failure
        SET @SQL = 'ALTER DATABASE ' + QUOTENAME(@SourceDB) + ' SET MULTI_USER';
        EXEC sp_executesql @SQL;
        
        THROW;
    END CATCH
END
GO

-- Compare snapshot to current database
CREATE PROCEDURE dbo.CompareSnapshotToSource
    @SnapshotName NVARCHAR(128),
    @TableName NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SourceDB NVARCHAR(128);
    DECLARE @SQL NVARCHAR(MAX);
    
    SELECT @SourceDB = DB_NAME(source_database_id)
    FROM sys.databases
    WHERE name = @SnapshotName;
    
    IF @SourceDB IS NULL
    BEGIN
        RAISERROR('Invalid snapshot name', 16, 1);
        RETURN;
    END
    
    -- Compare row counts
    SET @SQL = N'
        SELECT 
            s.name AS SchemaName,
            t.name AS TableName,
            snap.row_count AS SnapshotRows,
            curr.row_count AS CurrentRows,
            curr.row_count - snap.row_count AS Difference
        FROM ' + QUOTENAME(@SourceDB) + '.sys.tables t
        INNER JOIN ' + QUOTENAME(@SourceDB) + '.sys.schemas s ON t.schema_id = s.schema_id
        INNER JOIN ' + QUOTENAME(@SourceDB) + '.sys.dm_db_partition_stats curr 
            ON t.object_id = curr.object_id AND curr.index_id IN (0, 1)
        INNER JOIN ' + QUOTENAME(@SnapshotName) + '.sys.dm_db_partition_stats snap 
            ON snap.object_id = t.object_id AND snap.index_id IN (0, 1)
        WHERE (@TableFilter IS NULL OR t.name = @TableFilter)
        ORDER BY ABS(curr.row_count - snap.row_count) DESC';
    
    EXEC sp_executesql @SQL, N'@TableFilter NVARCHAR(128)', @TableFilter = @TableName;
END
GO
