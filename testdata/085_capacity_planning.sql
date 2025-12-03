-- Sample 085: Capacity Planning and Forecasting
-- Source: Various - Microsoft Learn, Brent Ozar, Database capacity patterns
-- Category: Performance
-- Complexity: Advanced
-- Features: Growth tracking, trend analysis, capacity forecasting, resource utilization

-- Setup capacity tracking tables
CREATE PROCEDURE dbo.SetupCapacityTracking
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Database size history
    IF OBJECT_ID('dbo.DatabaseSizeHistory', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.DatabaseSizeHistory (
            HistoryID BIGINT IDENTITY(1,1) PRIMARY KEY,
            CaptureDate DATE NOT NULL,
            DatabaseName NVARCHAR(128) NOT NULL,
            DataSizeMB DECIMAL(18,2),
            LogSizeMB DECIMAL(18,2),
            DataUsedMB DECIMAL(18,2),
            LogUsedMB DECIMAL(18,2),
            RowCount BIGINT,
            UNIQUE (CaptureDate, DatabaseName)
        );
    END
    
    -- Table size history
    IF OBJECT_ID('dbo.TableSizeHistory', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.TableSizeHistory (
            HistoryID BIGINT IDENTITY(1,1) PRIMARY KEY,
            CaptureDate DATE NOT NULL,
            DatabaseName NVARCHAR(128),
            SchemaName NVARCHAR(128),
            TableName NVARCHAR(128),
            RowCount BIGINT,
            TotalSizeMB DECIMAL(18,2),
            DataSizeMB DECIMAL(18,2),
            IndexSizeMB DECIMAL(18,2)
        );
    END
    
    -- Resource utilization history
    IF OBJECT_ID('dbo.ResourceUtilizationHistory', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.ResourceUtilizationHistory (
            HistoryID BIGINT IDENTITY(1,1) PRIMARY KEY,
            CaptureTime DATETIME2 NOT NULL,
            CPUPercent DECIMAL(5,2),
            MemoryUsedMB DECIMAL(18,2),
            MemoryAvailableMB DECIMAL(18,2),
            DiskReadsMB DECIMAL(18,2),
            DiskWritesMB DECIMAL(18,2),
            ConnectionCount INT,
            BatchRequestsPerSec INT
        );
    END
    
    SELECT 'Capacity tracking tables created' AS Status;
END
GO

-- Capture database size snapshot
CREATE PROCEDURE dbo.CaptureCapacitySnapshot
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Capture database sizes using MERGE to handle duplicates (T-SQL approach)
    MERGE INTO dbo.DatabaseSizeHistory AS target
    USING (
        SELECT 
            CAST(GETDATE() AS DATE) AS CaptureDate,
            DB_NAME(database_id) AS DatabaseName,
            SUM(CASE WHEN type = 0 THEN size * 8.0 / 1024 ELSE 0 END) AS DataSizeMB,
            SUM(CASE WHEN type = 1 THEN size * 8.0 / 1024 ELSE 0 END) AS LogSizeMB,
            SUM(CASE WHEN type = 0 THEN FILEPROPERTY(name, 'SpaceUsed') * 8.0 / 1024 ELSE 0 END) AS DataUsedMB,
            SUM(CASE WHEN type = 1 THEN FILEPROPERTY(name, 'SpaceUsed') * 8.0 / 1024 ELSE 0 END) AS LogUsedMB,
            NULL AS RowCount
        FROM sys.master_files
        WHERE database_id > 4
        GROUP BY database_id
    ) AS source
    ON target.CaptureDate = source.CaptureDate AND target.DatabaseName = source.DatabaseName
    WHEN NOT MATCHED THEN
        INSERT (CaptureDate, DatabaseName, DataSizeMB, LogSizeMB, DataUsedMB, LogUsedMB, RowCount)
        VALUES (source.CaptureDate, source.DatabaseName, source.DataSizeMB, source.LogSizeMB, 
                source.DataUsedMB, source.LogUsedMB, source.RowCount);
    
    -- Capture current database table sizes
    INSERT INTO dbo.TableSizeHistory (CaptureDate, DatabaseName, SchemaName, TableName, RowCount, TotalSizeMB, DataSizeMB, IndexSizeMB)
    SELECT 
        CAST(GETDATE() AS DATE),
        DB_NAME(),
        SCHEMA_NAME(t.schema_id),
        t.name,
        SUM(p.rows),
        SUM(a.total_pages) * 8.0 / 1024,
        SUM(a.data_pages) * 8.0 / 1024,
        (SUM(a.total_pages) - SUM(a.data_pages)) * 8.0 / 1024
    FROM sys.tables t
    INNER JOIN sys.partitions p ON t.object_id = p.object_id AND p.index_id IN (0, 1)
    INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
    GROUP BY t.schema_id, t.name;
    
    SELECT 'Capacity snapshot captured' AS Status, GETDATE() AS CaptureTime;
END
GO

-- Analyze database growth trends
CREATE PROCEDURE dbo.AnalyzeGrowthTrends
    @DatabaseName NVARCHAR(128) = NULL,
    @DaysBack INT = 90
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Daily growth rates
    SELECT 
        DatabaseName,
        CaptureDate,
        DataUsedMB,
        LAG(DataUsedMB) OVER (PARTITION BY DatabaseName ORDER BY CaptureDate) AS PrevDataUsedMB,
        DataUsedMB - LAG(DataUsedMB) OVER (PARTITION BY DatabaseName ORDER BY CaptureDate) AS DailyGrowthMB,
        CASE 
            WHEN LAG(DataUsedMB) OVER (PARTITION BY DatabaseName ORDER BY CaptureDate) > 0
            THEN (DataUsedMB - LAG(DataUsedMB) OVER (PARTITION BY DatabaseName ORDER BY CaptureDate)) * 100.0 
                 / LAG(DataUsedMB) OVER (PARTITION BY DatabaseName ORDER BY CaptureDate)
            ELSE 0
        END AS DailyGrowthPercent
    FROM dbo.DatabaseSizeHistory
    WHERE CaptureDate >= DATEADD(DAY, -@DaysBack, GETDATE())
      AND (@DatabaseName IS NULL OR DatabaseName = @DatabaseName)
    ORDER BY DatabaseName, CaptureDate;
    
    -- Growth summary
    SELECT 
        DatabaseName,
        MIN(CaptureDate) AS PeriodStart,
        MAX(CaptureDate) AS PeriodEnd,
        MIN(DataUsedMB) AS StartSizeMB,
        MAX(DataUsedMB) AS EndSizeMB,
        MAX(DataUsedMB) - MIN(DataUsedMB) AS TotalGrowthMB,
        (MAX(DataUsedMB) - MIN(DataUsedMB)) / NULLIF(DATEDIFF(DAY, MIN(CaptureDate), MAX(CaptureDate)), 0) AS AvgDailyGrowthMB,
        (MAX(DataUsedMB) - MIN(DataUsedMB)) / NULLIF(DATEDIFF(DAY, MIN(CaptureDate), MAX(CaptureDate)), 0) * 30 AS ProjectedMonthlyGrowthMB
    FROM dbo.DatabaseSizeHistory
    WHERE CaptureDate >= DATEADD(DAY, -@DaysBack, GETDATE())
      AND (@DatabaseName IS NULL OR DatabaseName = @DatabaseName)
    GROUP BY DatabaseName
    HAVING COUNT(*) > 1
    ORDER BY TotalGrowthMB DESC;
END
GO

-- Forecast storage requirements
CREATE PROCEDURE dbo.ForecastStorageNeeds
    @DatabaseName NVARCHAR(128),
    @ForecastDays INT = 365
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @AvgDailyGrowth DECIMAL(18,2);
    DECLARE @CurrentSize DECIMAL(18,2);
    DECLARE @AllocatedSize DECIMAL(18,2);
    
    -- Calculate average daily growth (last 90 days)
    SELECT 
        @AvgDailyGrowth = (MAX(DataUsedMB) - MIN(DataUsedMB)) / NULLIF(DATEDIFF(DAY, MIN(CaptureDate), MAX(CaptureDate)), 0),
        @CurrentSize = MAX(DataUsedMB)
    FROM dbo.DatabaseSizeHistory
    WHERE DatabaseName = @DatabaseName
      AND CaptureDate >= DATEADD(DAY, -90, GETDATE());
    
    -- Get current allocated size
    SELECT @AllocatedSize = SUM(size * 8.0 / 1024)
    FROM sys.master_files
    WHERE database_id = DB_ID(@DatabaseName) AND type = 0;
    
    -- Generate forecast
    ;WITH ForecastDates AS (
        SELECT 0 AS DaysFromNow
        UNION ALL
        SELECT DaysFromNow + 30
        FROM ForecastDates
        WHERE DaysFromNow < @ForecastDays
    )
    SELECT 
        DATEADD(DAY, DaysFromNow, GETDATE()) AS ForecastDate,
        DaysFromNow,
        @CurrentSize + (@AvgDailyGrowth * DaysFromNow) AS ProjectedUsedMB,
        @AllocatedSize AS CurrentAllocatedMB,
        CASE 
            WHEN @CurrentSize + (@AvgDailyGrowth * DaysFromNow) > @AllocatedSize * 0.9
            THEN 'Action Required - Approaching capacity'
            WHEN @CurrentSize + (@AvgDailyGrowth * DaysFromNow) > @AllocatedSize * 0.8
            THEN 'Warning - 80% capacity within forecast'
            ELSE 'OK'
        END AS Status,
        CASE 
            WHEN @AvgDailyGrowth > 0
            THEN CAST((@AllocatedSize * 0.9 - @CurrentSize) / @AvgDailyGrowth AS INT)
            ELSE NULL
        END AS DaysUntil90PercentFull
    FROM ForecastDates
    ORDER BY DaysFromNow;
    
    -- Recommendations
    SELECT 
        @DatabaseName AS DatabaseName,
        @CurrentSize AS CurrentUsedMB,
        @AllocatedSize AS AllocatedMB,
        @AvgDailyGrowth AS AvgDailyGrowthMB,
        @AvgDailyGrowth * 30 AS MonthlyGrowthMB,
        @AvgDailyGrowth * 365 AS YearlyGrowthMB,
        CASE 
            WHEN @AvgDailyGrowth * @ForecastDays + @CurrentSize > @AllocatedSize
            THEN 'Recommend adding ' + CAST(CEILING((@AvgDailyGrowth * @ForecastDays) / 1024.0) AS VARCHAR(20)) + ' GB'
            ELSE 'Current allocation sufficient for forecast period'
        END AS Recommendation;
END
GO

-- Identify fast-growing tables
CREATE PROCEDURE dbo.IdentifyFastGrowingTables
    @DaysBack INT = 30,
    @MinGrowthMB DECIMAL(18,2) = 100
AS
BEGIN
    SET NOCOUNT ON;
    
    ;WITH TableGrowth AS (
        SELECT 
            DatabaseName,
            SchemaName,
            TableName,
            MIN(CaptureDate) AS FirstCapture,
            MAX(CaptureDate) AS LastCapture,
            MIN(TotalSizeMB) AS StartSize,
            MAX(TotalSizeMB) AS EndSize,
            MIN(RowCount) AS StartRows,
            MAX(RowCount) AS EndRows
        FROM dbo.TableSizeHistory
        WHERE CaptureDate >= DATEADD(DAY, -@DaysBack, GETDATE())
        GROUP BY DatabaseName, SchemaName, TableName
        HAVING COUNT(*) > 1
    )
    SELECT 
        DatabaseName,
        SchemaName,
        TableName,
        StartSize AS StartSizeMB,
        EndSize AS CurrentSizeMB,
        EndSize - StartSize AS GrowthMB,
        CASE WHEN StartSize > 0 THEN (EndSize - StartSize) * 100.0 / StartSize ELSE 0 END AS GrowthPercent,
        (EndSize - StartSize) / NULLIF(DATEDIFF(DAY, FirstCapture, LastCapture), 0) AS AvgDailyGrowthMB,
        StartRows,
        EndRows,
        EndRows - StartRows AS RowGrowth
    FROM TableGrowth
    WHERE EndSize - StartSize >= @MinGrowthMB
    ORDER BY GrowthMB DESC;
END
GO

-- Get capacity recommendations
CREATE PROCEDURE dbo.GetCapacityRecommendations
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Disk space alerts
    SELECT 
        'Disk Space' AS Category,
        DB_NAME(database_id) AS DatabaseName,
        name AS FileName,
        CAST(size * 8.0 / 1024 AS DECIMAL(18,2)) AS AllocatedMB,
        CAST(FILEPROPERTY(name, 'SpaceUsed') * 8.0 / 1024 AS DECIMAL(18,2)) AS UsedMB,
        CAST((size - FILEPROPERTY(name, 'SpaceUsed')) * 8.0 / 1024 AS DECIMAL(18,2)) AS FreeMB,
        CAST(FILEPROPERTY(name, 'SpaceUsed') * 100.0 / NULLIF(size, 0) AS DECIMAL(5,2)) AS UsedPercent,
        CASE 
            WHEN FILEPROPERTY(name, 'SpaceUsed') * 100.0 / NULLIF(size, 0) > 90 THEN 'CRITICAL - Over 90% used'
            WHEN FILEPROPERTY(name, 'SpaceUsed') * 100.0 / NULLIF(size, 0) > 80 THEN 'WARNING - Over 80% used'
            ELSE 'OK'
        END AS Status
    FROM sys.master_files
    WHERE database_id > 4 AND type = 0
    ORDER BY UsedPercent DESC;
    
    -- Memory recommendations
    SELECT 
        'Memory' AS Category,
        physical_memory_kb / 1024 AS PhysicalMemoryMB,
        committed_kb / 1024 AS SQLCommittedMB,
        committed_target_kb / 1024 AS SQLTargetMB,
        CASE 
            WHEN committed_kb > committed_target_kb * 0.95 THEN 'Consider increasing max server memory'
            ELSE 'Memory allocation OK'
        END AS Recommendation
    FROM sys.dm_os_sys_info;
END
GO
