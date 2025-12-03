-- Sample 089: Database Health Check System
-- Source: Various - Brent Ozar, Glenn Berry, sp_Blitz patterns
-- Category: Performance
-- Complexity: Advanced
-- Features: Comprehensive health checks, alerts, scoring system

-- Run comprehensive health check
CREATE PROCEDURE dbo.RunDatabaseHealthCheck
    @DatabaseName NVARCHAR(128) = NULL,
    @CheckLevel NVARCHAR(20) = 'STANDARD'  -- QUICK, STANDARD, DETAILED
AS
BEGIN
    SET NOCOUNT ON;
    
    SET @DatabaseName = ISNULL(@DatabaseName, DB_NAME());
    
    CREATE TABLE #HealthResults (
        CheckID INT IDENTITY(1,1),
        Category NVARCHAR(50),
        CheckName NVARCHAR(200),
        Status NVARCHAR(20),  -- OK, WARNING, CRITICAL, INFO
        CurrentValue NVARCHAR(MAX),
        RecommendedValue NVARCHAR(MAX),
        Details NVARCHAR(MAX),
        Priority INT  -- 1=Critical, 2=High, 3=Medium, 4=Low
    );
    
    -- =====================
    -- DATABASE CONFIGURATION
    -- =====================
    
    -- Auto-close
    INSERT INTO #HealthResults
    SELECT 'Configuration', 'Auto Close', 
           CASE WHEN is_auto_close_on = 1 THEN 'CRITICAL' ELSE 'OK' END,
           CAST(is_auto_close_on AS VARCHAR(10)), '0 (OFF)',
           'Auto-close can cause performance issues',
           CASE WHEN is_auto_close_on = 1 THEN 1 ELSE 4 END
    FROM sys.databases WHERE name = @DatabaseName;
    
    -- Auto-shrink
    INSERT INTO #HealthResults
    SELECT 'Configuration', 'Auto Shrink',
           CASE WHEN is_auto_shrink_on = 1 THEN 'CRITICAL' ELSE 'OK' END,
           CAST(is_auto_shrink_on AS VARCHAR(10)), '0 (OFF)',
           'Auto-shrink causes fragmentation and performance degradation',
           CASE WHEN is_auto_shrink_on = 1 THEN 1 ELSE 4 END
    FROM sys.databases WHERE name = @DatabaseName;
    
    -- Page verify
    INSERT INTO #HealthResults
    SELECT 'Configuration', 'Page Verify Option',
           CASE WHEN page_verify_option_desc <> 'CHECKSUM' THEN 'WARNING' ELSE 'OK' END,
           page_verify_option_desc, 'CHECKSUM',
           'CHECKSUM provides best data corruption detection',
           CASE WHEN page_verify_option_desc <> 'CHECKSUM' THEN 2 ELSE 4 END
    FROM sys.databases WHERE name = @DatabaseName;
    
    -- Recovery model check
    INSERT INTO #HealthResults
    SELECT 'Configuration', 'Recovery Model',
           'INFO',
           recovery_model_desc, 'Depends on requirements',
           'Verify recovery model matches business requirements',
           4
    FROM sys.databases WHERE name = @DatabaseName;
    
    -- =====================
    -- BACKUP STATUS
    -- =====================
    
    -- Last full backup
    INSERT INTO #HealthResults
    SELECT 'Backup', 'Last Full Backup',
           CASE 
               WHEN MAX(backup_finish_date) IS NULL THEN 'CRITICAL'
               WHEN DATEDIFF(DAY, MAX(backup_finish_date), GETDATE()) > 7 THEN 'CRITICAL'
               WHEN DATEDIFF(DAY, MAX(backup_finish_date), GETDATE()) > 1 THEN 'WARNING'
               ELSE 'OK'
           END,
           ISNULL(CONVERT(VARCHAR(30), MAX(backup_finish_date), 121), 'Never'),
           'Daily or more frequent',
           'Days since last backup: ' + ISNULL(CAST(DATEDIFF(DAY, MAX(backup_finish_date), GETDATE()) AS VARCHAR(10)), 'N/A'),
           CASE 
               WHEN MAX(backup_finish_date) IS NULL THEN 1
               WHEN DATEDIFF(DAY, MAX(backup_finish_date), GETDATE()) > 7 THEN 1
               ELSE 3
           END
    FROM msdb.dbo.backupset
    WHERE database_name = @DatabaseName AND type = 'D';
    
    -- =====================
    -- INDEX HEALTH
    -- =====================
    
    -- Fragmented indexes
    INSERT INTO #HealthResults
    SELECT 'Index Health', 'Highly Fragmented Indexes',
           CASE WHEN COUNT(*) > 10 THEN 'WARNING' WHEN COUNT(*) > 0 THEN 'INFO' ELSE 'OK' END,
           CAST(COUNT(*) AS VARCHAR(10)) + ' indexes > 30% fragmented',
           '0 highly fragmented indexes',
           'Consider rebuilding or reorganizing fragmented indexes',
           CASE WHEN COUNT(*) > 10 THEN 2 ELSE 3 END
    FROM sys.dm_db_index_physical_stats(DB_ID(@DatabaseName), NULL, NULL, NULL, 'LIMITED')
    WHERE avg_fragmentation_in_percent > 30 AND page_count > 1000;
    
    -- Missing indexes
    INSERT INTO #HealthResults
    SELECT 'Index Health', 'Missing Indexes',
           CASE WHEN COUNT(*) > 20 THEN 'WARNING' WHEN COUNT(*) > 0 THEN 'INFO' ELSE 'OK' END,
           CAST(COUNT(*) AS VARCHAR(10)) + ' missing indexes detected',
           'Review and create beneficial indexes',
           'High-impact missing indexes can significantly improve performance',
           CASE WHEN COUNT(*) > 20 THEN 2 ELSE 3 END
    FROM sys.dm_db_missing_index_details
    WHERE database_id = DB_ID(@DatabaseName);
    
    -- =====================
    -- SPACE MANAGEMENT
    -- =====================
    
    -- Data file space
    INSERT INTO #HealthResults
    SELECT 'Space', 'Data File Usage',
           CASE 
               WHEN 100.0 * SUM(FILEPROPERTY(name, 'SpaceUsed')) / SUM(size) > 95 THEN 'CRITICAL'
               WHEN 100.0 * SUM(FILEPROPERTY(name, 'SpaceUsed')) / SUM(size) > 85 THEN 'WARNING'
               ELSE 'OK'
           END,
           CAST(CAST(100.0 * SUM(FILEPROPERTY(name, 'SpaceUsed')) / SUM(size) AS DECIMAL(5,2)) AS VARCHAR(10)) + '% used',
           'Below 85% for growth headroom',
           'Total: ' + CAST(SUM(size) * 8 / 1024 AS VARCHAR(20)) + ' MB, Used: ' + 
           CAST(SUM(FILEPROPERTY(name, 'SpaceUsed')) * 8 / 1024 AS VARCHAR(20)) + ' MB',
           CASE WHEN 100.0 * SUM(FILEPROPERTY(name, 'SpaceUsed')) / SUM(size) > 95 THEN 1 ELSE 3 END
    FROM sys.database_files WHERE type = 0;
    
    -- Log file space
    INSERT INTO #HealthResults
    SELECT 'Space', 'Log File Usage',
           CASE 
               WHEN 100.0 * SUM(FILEPROPERTY(name, 'SpaceUsed')) / SUM(size) > 90 THEN 'WARNING'
               ELSE 'OK'
           END,
           CAST(CAST(100.0 * SUM(FILEPROPERTY(name, 'SpaceUsed')) / SUM(size) AS DECIMAL(5,2)) AS VARCHAR(10)) + '% used',
           'Below 90%',
           'Log size: ' + CAST(SUM(size) * 8 / 1024 AS VARCHAR(20)) + ' MB',
           CASE WHEN 100.0 * SUM(FILEPROPERTY(name, 'SpaceUsed')) / SUM(size) > 90 THEN 2 ELSE 4 END
    FROM sys.database_files WHERE type = 1;
    
    -- =====================
    -- STATISTICS
    -- =====================
    
    -- Outdated statistics
    INSERT INTO #HealthResults
    SELECT 'Statistics', 'Outdated Statistics',
           CASE WHEN COUNT(*) > 50 THEN 'WARNING' WHEN COUNT(*) > 0 THEN 'INFO' ELSE 'OK' END,
           CAST(COUNT(*) AS VARCHAR(10)) + ' statistics older than 7 days',
           'Statistics should be regularly updated',
           'Consider UPDATE STATISTICS or enabling AUTO_UPDATE_STATISTICS',
           CASE WHEN COUNT(*) > 50 THEN 2 ELSE 3 END
    FROM sys.stats s
    CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
    WHERE OBJECTPROPERTY(s.object_id, 'IsUserTable') = 1
      AND sp.last_updated < DATEADD(DAY, -7, GETDATE());
    
    -- =====================
    -- SECURITY
    -- =====================
    
    -- Orphaned users
    INSERT INTO #HealthResults
    SELECT 'Security', 'Orphaned Users',
           CASE WHEN COUNT(*) > 0 THEN 'WARNING' ELSE 'OK' END,
           CAST(COUNT(*) AS VARCHAR(10)) + ' orphaned users',
           '0 orphaned users',
           'Orphaned users have no associated login',
           CASE WHEN COUNT(*) > 0 THEN 3 ELSE 4 END
    FROM sys.database_principals dp
    LEFT JOIN sys.server_principals sp ON dp.sid = sp.sid
    WHERE dp.type IN ('S', 'U') AND sp.sid IS NULL AND dp.sid <> 0x00;
    
    -- Return results
    SELECT 
        CheckID,
        Category,
        CheckName,
        Status,
        CurrentValue,
        RecommendedValue,
        Details,
        Priority
    FROM #HealthResults
    ORDER BY Priority, Category, CheckName;
    
    -- Summary
    SELECT 
        Status,
        COUNT(*) AS CheckCount
    FROM #HealthResults
    GROUP BY Status
    ORDER BY CASE Status 
        WHEN 'CRITICAL' THEN 1 
        WHEN 'WARNING' THEN 2 
        WHEN 'INFO' THEN 3 
        ELSE 4 
    END;
    
    -- Health Score (0-100)
    SELECT 
        100 - (SUM(CASE Status WHEN 'CRITICAL' THEN 25 WHEN 'WARNING' THEN 10 ELSE 0 END)) AS HealthScore,
        CASE 
            WHEN 100 - (SUM(CASE Status WHEN 'CRITICAL' THEN 25 WHEN 'WARNING' THEN 10 ELSE 0 END)) >= 90 THEN 'Excellent'
            WHEN 100 - (SUM(CASE Status WHEN 'CRITICAL' THEN 25 WHEN 'WARNING' THEN 10 ELSE 0 END)) >= 70 THEN 'Good'
            WHEN 100 - (SUM(CASE Status WHEN 'CRITICAL' THEN 25 WHEN 'WARNING' THEN 10 ELSE 0 END)) >= 50 THEN 'Fair'
            ELSE 'Poor'
        END AS HealthGrade
    FROM #HealthResults;
    
    DROP TABLE #HealthResults;
END
GO

-- Quick health check
CREATE PROCEDURE dbo.RunQuickHealthCheck
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Critical issues only
    SELECT 'CRITICAL ISSUES' AS Section;
    
    -- Databases not backed up
    SELECT 
        'No Recent Backup' AS Issue,
        d.name AS DatabaseName,
        ISNULL(CONVERT(VARCHAR(30), MAX(b.backup_finish_date), 121), 'Never') AS LastBackup
    FROM sys.databases d
    LEFT JOIN msdb.dbo.backupset b ON d.name = b.database_name AND b.type = 'D'
    WHERE d.database_id > 4 AND d.state = 0
    GROUP BY d.name
    HAVING MAX(b.backup_finish_date) IS NULL OR MAX(b.backup_finish_date) < DATEADD(DAY, -1, GETDATE());
    
    -- Files running out of space
    SELECT 
        'Low Disk Space' AS Issue,
        DB_NAME(database_id) AS DatabaseName,
        name AS FileName,
        CAST((size - FILEPROPERTY(name, 'SpaceUsed')) * 8.0 / 1024 AS DECIMAL(10,2)) AS FreeSpaceMB
    FROM sys.master_files
    WHERE type = 0 
      AND CAST(FILEPROPERTY(name, 'SpaceUsed') AS FLOAT) / NULLIF(size, 0) > 0.95;
    
    -- Long running queries
    SELECT 
        'Long Running Query' AS Issue,
        r.session_id,
        r.start_time,
        DATEDIFF(MINUTE, r.start_time, GETDATE()) AS RunningMinutes,
        LEFT(t.text, 100) AS QueryStart
    FROM sys.dm_exec_requests r
    CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
    WHERE r.session_id <> @@SPID
      AND DATEDIFF(MINUTE, r.start_time, GETDATE()) > 30;
END
GO
