-- Sample 096: Automated Database Maintenance
-- Source: Ola Hallengren patterns, Microsoft Learn, SQL Server maintenance best practices
-- Category: Maintenance
-- Complexity: Advanced
-- Features: Automated maintenance, intelligent scheduling, maintenance windows, health-based decisions

-- Setup maintenance infrastructure
CREATE PROCEDURE dbo.SetupMaintenanceInfrastructure
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Maintenance configuration
    IF OBJECT_ID('dbo.MaintenanceConfig', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.MaintenanceConfig (
            ConfigID INT IDENTITY(1,1) PRIMARY KEY,
            ConfigName NVARCHAR(100) NOT NULL UNIQUE,
            ConfigValue NVARCHAR(MAX),
            Description NVARCHAR(500),
            LastModified DATETIME2 DEFAULT SYSDATETIME()
        );
        
        -- Default settings
        INSERT INTO dbo.MaintenanceConfig (ConfigName, ConfigValue, Description) VALUES
        ('MaintenanceWindowStart', '02:00', 'Start time for maintenance window'),
        ('MaintenanceWindowEnd', '06:00', 'End time for maintenance window'),
        ('IndexFragmentationThreshold', '30', 'Fragmentation % to trigger rebuild'),
        ('IndexReorganizeThreshold', '10', 'Fragmentation % to trigger reorganize'),
        ('StatisticsAgeThreshold', '7', 'Days before statistics update'),
        ('BackupRetentionDays', '30', 'Days to retain backups'),
        ('MaxIndexMaintenanceMinutes', '120', 'Max time for index maintenance'),
        ('EnableAdaptiveMaintenance', '1', 'Adjust maintenance based on workload');
    END
    
    -- Maintenance history log
    IF OBJECT_ID('dbo.MaintenanceLog', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.MaintenanceLog (
            LogID INT IDENTITY(1,1) PRIMARY KEY,
            MaintenanceType NVARCHAR(50),
            ObjectName NVARCHAR(256),
            StartTime DATETIME2,
            EndTime DATETIME2,
            Status NVARCHAR(20),
            RowsAffected BIGINT,
            SpaceSavedMB DECIMAL(10,2),
            ErrorMessage NVARCHAR(MAX),
            ExecutedBy NVARCHAR(128) DEFAULT SUSER_SNAME()
        );
        
        CREATE INDEX IX_MaintenanceLog_Time ON dbo.MaintenanceLog (StartTime);
    END
    
    SELECT 'Maintenance infrastructure created' AS Status;
END
GO

-- Intelligent index maintenance
CREATE PROCEDURE dbo.PerformIntelligentIndexMaintenance
    @DatabaseName NVARCHAR(128) = NULL,
    @MaxDurationMinutes INT = 120,
    @OnlineOnly BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    SET @DatabaseName = ISNULL(@DatabaseName, DB_NAME());
    
    DECLARE @StartTime DATETIME2 = SYSDATETIME();
    DECLARE @EndTime DATETIME2;
    DECLARE @FragThreshold INT, @ReorgThreshold INT;
    
    -- Get thresholds
    SELECT @FragThreshold = CAST(ConfigValue AS INT) FROM dbo.MaintenanceConfig WHERE ConfigName = 'IndexFragmentationThreshold';
    SELECT @ReorgThreshold = CAST(ConfigValue AS INT) FROM dbo.MaintenanceConfig WHERE ConfigName = 'IndexReorganizeThreshold';
    
    SET @FragThreshold = ISNULL(@FragThreshold, 30);
    SET @ReorgThreshold = ISNULL(@ReorgThreshold, 10);
    
    -- Get indexes needing maintenance
    CREATE TABLE #IndexesToMaintain (
        SchemaName NVARCHAR(128),
        TableName NVARCHAR(128),
        IndexName NVARCHAR(128),
        Fragmentation DECIMAL(5,2),
        PageCount BIGINT,
        Action NVARCHAR(20),
        Priority INT
    );
    
    INSERT INTO #IndexesToMaintain
    SELECT 
        s.name AS SchemaName,
        t.name AS TableName,
        i.name AS IndexName,
        ps.avg_fragmentation_in_percent AS Fragmentation,
        ps.page_count AS PageCount,
        CASE 
            WHEN ps.avg_fragmentation_in_percent >= @FragThreshold THEN 'REBUILD'
            WHEN ps.avg_fragmentation_in_percent >= @ReorgThreshold THEN 'REORGANIZE'
        END AS Action,
        -- Priority: larger, more fragmented indexes first
        ROW_NUMBER() OVER (ORDER BY ps.avg_fragmentation_in_percent * ps.page_count DESC) AS Priority
    FROM sys.dm_db_index_physical_stats(DB_ID(@DatabaseName), NULL, NULL, NULL, 'LIMITED') ps
    INNER JOIN sys.indexes i ON ps.object_id = i.object_id AND ps.index_id = i.index_id
    INNER JOIN sys.tables t ON i.object_id = t.object_id
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE ps.avg_fragmentation_in_percent >= @ReorgThreshold
      AND ps.page_count > 1000
      AND i.name IS NOT NULL;
    
    -- Process indexes within time window
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @Schema NVARCHAR(128), @Table NVARCHAR(128), @Index NVARCHAR(128);
    DECLARE @Frag DECIMAL(5,2), @Act NVARCHAR(20);
    
    DECLARE IndexCursor CURSOR FOR
        SELECT SchemaName, TableName, IndexName, Fragmentation, Action
        FROM #IndexesToMaintain
        ORDER BY Priority;
    
    OPEN IndexCursor;
    FETCH NEXT FROM IndexCursor INTO @Schema, @Table, @Index, @Frag, @Act;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Check time limit
        IF DATEDIFF(MINUTE, @StartTime, SYSDATETIME()) >= @MaxDurationMinutes
            BREAK;
        
        DECLARE @ActionStart DATETIME2 = SYSDATETIME();
        DECLARE @Status NVARCHAR(20) = 'Success';
        DECLARE @ErrorMsg NVARCHAR(MAX) = NULL;
        
        BEGIN TRY
            IF @Act = 'REBUILD'
            BEGIN
                SET @SQL = 'ALTER INDEX ' + QUOTENAME(@Index) + ' ON ' + 
                           QUOTENAME(@Schema) + '.' + QUOTENAME(@Table) + 
                           ' REBUILD' + CASE WHEN @OnlineOnly = 1 THEN ' WITH (ONLINE = ON)' ELSE '' END;
            END
            ELSE
            BEGIN
                SET @SQL = 'ALTER INDEX ' + QUOTENAME(@Index) + ' ON ' + 
                           QUOTENAME(@Schema) + '.' + QUOTENAME(@Table) + ' REORGANIZE';
            END
            
            EXEC sp_executesql @SQL;
        END TRY
        BEGIN CATCH
            SET @Status = 'Failed';
            SET @ErrorMsg = ERROR_MESSAGE();
        END CATCH
        
        -- Log action
        INSERT INTO dbo.MaintenanceLog (MaintenanceType, ObjectName, StartTime, EndTime, Status, ErrorMessage)
        VALUES (@Act, @Schema + '.' + @Table + '.' + @Index, @ActionStart, SYSDATETIME(), @Status, @ErrorMsg);
        
        FETCH NEXT FROM IndexCursor INTO @Schema, @Table, @Index, @Frag, @Act;
    END
    
    CLOSE IndexCursor;
    DEALLOCATE IndexCursor;
    
    DROP TABLE #IndexesToMaintain;
    
    -- Return summary
    SELECT 
        MaintenanceType,
        COUNT(*) AS ActionsPerformed,
        SUM(CASE WHEN Status = 'Success' THEN 1 ELSE 0 END) AS Successful,
        SUM(CASE WHEN Status = 'Failed' THEN 1 ELSE 0 END) AS Failed,
        SUM(DATEDIFF(SECOND, StartTime, EndTime)) AS TotalSeconds
    FROM dbo.MaintenanceLog
    WHERE StartTime >= @StartTime
    GROUP BY MaintenanceType;
END
GO

-- Update statistics intelligently
CREATE PROCEDURE dbo.UpdateOutdatedStatistics
    @DatabaseName NVARCHAR(128) = NULL,
    @SamplePercent INT = NULL,  -- NULL = auto
    @MaxDurationMinutes INT = 60
AS
BEGIN
    SET NOCOUNT ON;
    
    SET @DatabaseName = ISNULL(@DatabaseName, DB_NAME());
    
    DECLARE @StartTime DATETIME2 = SYSDATETIME();
    DECLARE @AgeThreshold INT;
    
    SELECT @AgeThreshold = CAST(ConfigValue AS INT) FROM dbo.MaintenanceConfig WHERE ConfigName = 'StatisticsAgeThreshold';
    SET @AgeThreshold = ISNULL(@AgeThreshold, 7);
    
    CREATE TABLE #StatsToUpdate (
        SchemaName NVARCHAR(128),
        TableName NVARCHAR(128),
        StatsName NVARCHAR(128),
        LastUpdated DATETIME2,
        RowsSampled BIGINT,
        TotalRows BIGINT,
        ModificationCounter BIGINT,
        Priority INT
    );
    
    INSERT INTO #StatsToUpdate
    SELECT 
        s.name AS SchemaName,
        t.name AS TableName,
        st.name AS StatsName,
        sp.last_updated AS LastUpdated,
        sp.rows_sampled AS RowsSampled,
        sp.rows AS TotalRows,
        sp.modification_counter AS ModificationCounter,
        ROW_NUMBER() OVER (ORDER BY sp.modification_counter DESC) AS Priority
    FROM sys.stats st
    INNER JOIN sys.tables t ON st.object_id = t.object_id
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    CROSS APPLY sys.dm_db_stats_properties(st.object_id, st.stats_id) sp
    WHERE sp.last_updated < DATEADD(DAY, -@AgeThreshold, GETDATE())
       OR sp.modification_counter > sp.rows * 0.2;  -- 20% changed
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @Schema NVARCHAR(128), @Table NVARCHAR(128), @Stats NVARCHAR(128);
    DECLARE @Rows BIGINT;
    
    DECLARE StatsCursor CURSOR FOR
        SELECT SchemaName, TableName, StatsName, TotalRows FROM #StatsToUpdate ORDER BY Priority;
    
    OPEN StatsCursor;
    FETCH NEXT FROM StatsCursor INTO @Schema, @Table, @Stats, @Rows;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF DATEDIFF(MINUTE, @StartTime, SYSDATETIME()) >= @MaxDurationMinutes
            BREAK;
        
        DECLARE @ActionStart DATETIME2 = SYSDATETIME();
        DECLARE @Sample INT = @SamplePercent;
        
        -- Auto-calculate sample rate for large tables
        IF @Sample IS NULL
        BEGIN
            SET @Sample = CASE 
                WHEN @Rows < 100000 THEN 100
                WHEN @Rows < 1000000 THEN 50
                WHEN @Rows < 10000000 THEN 25
                ELSE 10
            END;
        END
        
        BEGIN TRY
            SET @SQL = 'UPDATE STATISTICS ' + QUOTENAME(@Schema) + '.' + QUOTENAME(@Table) + 
                       ' ' + QUOTENAME(@Stats) + ' WITH SAMPLE ' + CAST(@Sample AS VARCHAR(3)) + ' PERCENT';
            EXEC sp_executesql @SQL;
            
            INSERT INTO dbo.MaintenanceLog (MaintenanceType, ObjectName, StartTime, EndTime, Status, RowsAffected)
            VALUES ('UPDATE_STATS', @Schema + '.' + @Table + '.' + @Stats, @ActionStart, SYSDATETIME(), 'Success', @Rows);
        END TRY
        BEGIN CATCH
            INSERT INTO dbo.MaintenanceLog (MaintenanceType, ObjectName, StartTime, EndTime, Status, ErrorMessage)
            VALUES ('UPDATE_STATS', @Schema + '.' + @Table + '.' + @Stats, @ActionStart, SYSDATETIME(), 'Failed', ERROR_MESSAGE());
        END CATCH
        
        FETCH NEXT FROM StatsCursor INTO @Schema, @Table, @Stats, @Rows;
    END
    
    CLOSE StatsCursor;
    DEALLOCATE StatsCursor;
    
    DROP TABLE #StatsToUpdate;
    
    SELECT COUNT(*) AS StatisticsUpdated FROM dbo.MaintenanceLog 
    WHERE StartTime >= @StartTime AND MaintenanceType = 'UPDATE_STATS' AND Status = 'Success';
END
GO

-- Cleanup old maintenance logs
CREATE PROCEDURE dbo.CleanupMaintenanceLogs
    @RetentionDays INT = 90
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @CutoffDate DATETIME2 = DATEADD(DAY, -@RetentionDays, SYSDATETIME());
    DECLARE @Deleted INT;
    
    DELETE FROM dbo.MaintenanceLog WHERE StartTime < @CutoffDate;
    SET @Deleted = @@ROWCOUNT;
    
    SELECT @Deleted AS LogsDeleted, @CutoffDate AS CutoffDate;
END
GO

-- Get maintenance recommendations
CREATE PROCEDURE dbo.GetMaintenanceRecommendations
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        'Recommendation' AS Category,
        Priority,
        Recommendation,
        Details
    FROM (
        -- High fragmentation
        SELECT 1 AS Priority, 
               'High Index Fragmentation' AS Recommendation,
               'Found ' + CAST(COUNT(*) AS VARCHAR(10)) + ' indexes with >50% fragmentation' AS Details
        FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED')
        WHERE avg_fragmentation_in_percent > 50 AND page_count > 1000
        HAVING COUNT(*) > 0
        
        UNION ALL
        
        -- Outdated statistics
        SELECT 2, 'Outdated Statistics',
               'Found ' + CAST(COUNT(*) AS VARCHAR(10)) + ' statistics not updated in 30+ days'
        FROM sys.stats s
        CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
        WHERE sp.last_updated < DATEADD(DAY, -30, GETDATE())
        HAVING COUNT(*) > 0
        
        UNION ALL
        
        -- Missing backups
        SELECT 3, 'Missing Recent Backup',
               'Last full backup was ' + CAST(DATEDIFF(DAY, MAX(backup_finish_date), GETDATE()) AS VARCHAR(10)) + ' days ago'
        FROM msdb.dbo.backupset
        WHERE database_name = DB_NAME() AND type = 'D'
        HAVING DATEDIFF(DAY, MAX(backup_finish_date), GETDATE()) > 1
    ) AS Recommendations
    ORDER BY Priority;
END
GO
