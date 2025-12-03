-- Sample 074: IO Statistics and Analysis
-- Source: Microsoft Learn, Paul Randal, Brent Ozar
-- Category: Performance
-- Complexity: Advanced
-- Features: sys.dm_io_virtual_file_stats, IO latency, throughput analysis

-- Get current IO statistics per file
CREATE PROCEDURE dbo.GetIOStatistics
    @DatabaseName NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        DB_NAME(vfs.database_id) AS DatabaseName,
        mf.name AS LogicalFileName,
        mf.type_desc AS FileType,
        mf.physical_name AS PhysicalPath,
        vfs.num_of_reads AS Reads,
        vfs.num_of_writes AS Writes,
        CAST(vfs.num_of_bytes_read / 1024.0 / 1024.0 AS DECIMAL(18,2)) AS ReadMB,
        CAST(vfs.num_of_bytes_written / 1024.0 / 1024.0 AS DECIMAL(18,2)) AS WrittenMB,
        vfs.io_stall_read_ms AS ReadStallMs,
        vfs.io_stall_write_ms AS WriteStallMs,
        CASE WHEN vfs.num_of_reads > 0 
             THEN CAST(vfs.io_stall_read_ms * 1.0 / vfs.num_of_reads AS DECIMAL(10,2))
             ELSE 0 
        END AS AvgReadLatencyMs,
        CASE WHEN vfs.num_of_writes > 0 
             THEN CAST(vfs.io_stall_write_ms * 1.0 / vfs.num_of_writes AS DECIMAL(10,2))
             ELSE 0 
        END AS AvgWriteLatencyMs,
        CASE WHEN vfs.num_of_reads > 0 
             THEN CAST(vfs.num_of_bytes_read / 1024.0 / vfs.num_of_reads AS DECIMAL(10,2))
             ELSE 0 
        END AS AvgReadSizeKB,
        CASE WHEN vfs.num_of_writes > 0 
             THEN CAST(vfs.num_of_bytes_written / 1024.0 / vfs.num_of_writes AS DECIMAL(10,2))
             ELSE 0 
        END AS AvgWriteSizeKB,
        vfs.size_on_disk_bytes / 1024 / 1024 AS FileSizeMB
    FROM sys.dm_io_virtual_file_stats(NULL, NULL) vfs
    INNER JOIN sys.master_files mf ON vfs.database_id = mf.database_id AND vfs.file_id = mf.file_id
    WHERE @DatabaseName IS NULL OR DB_NAME(vfs.database_id) = @DatabaseName
    ORDER BY vfs.io_stall DESC;
END
GO

-- Capture IO baseline
CREATE PROCEDURE dbo.CaptureIOBaseline
    @BaselineName NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    IF OBJECT_ID('dbo.IOBaseline', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.IOBaseline (
            BaselineID INT IDENTITY(1,1),
            BaselineName NVARCHAR(100),
            CaptureTime DATETIME2 DEFAULT SYSDATETIME(),
            database_id INT,
            file_id INT,
            num_of_reads BIGINT,
            num_of_writes BIGINT,
            num_of_bytes_read BIGINT,
            num_of_bytes_written BIGINT,
            io_stall_read_ms BIGINT,
            io_stall_write_ms BIGINT,
            PRIMARY KEY (BaselineID, database_id, file_id)
        );
    END
    
    SET @BaselineName = ISNULL(@BaselineName, 'Baseline_' + FORMAT(SYSDATETIME(), 'yyyyMMdd_HHmmss'));
    
    INSERT INTO dbo.IOBaseline (BaselineName, database_id, file_id, num_of_reads, num_of_writes,
                                 num_of_bytes_read, num_of_bytes_written, io_stall_read_ms, io_stall_write_ms)
    SELECT @BaselineName, database_id, file_id, num_of_reads, num_of_writes,
           num_of_bytes_read, num_of_bytes_written, io_stall_read_ms, io_stall_write_ms
    FROM sys.dm_io_virtual_file_stats(NULL, NULL);
    
    SELECT 'IO baseline captured' AS Status, @BaselineName AS BaselineName;
END
GO

-- Compare IO to baseline
CREATE PROCEDURE dbo.CompareIOToBaseline
    @BaselineName NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        DB_NAME(c.database_id) AS DatabaseName,
        mf.name AS FileName,
        mf.type_desc AS FileType,
        c.num_of_reads - b.num_of_reads AS ReadsDelta,
        c.num_of_writes - b.num_of_writes AS WritesDelta,
        CAST((c.num_of_bytes_read - b.num_of_bytes_read) / 1024.0 / 1024.0 AS DECIMAL(18,2)) AS ReadMBDelta,
        CAST((c.num_of_bytes_written - b.num_of_bytes_written) / 1024.0 / 1024.0 AS DECIMAL(18,2)) AS WrittenMBDelta,
        c.io_stall_read_ms - b.io_stall_read_ms AS ReadStallMsDelta,
        c.io_stall_write_ms - b.io_stall_write_ms AS WriteStallMsDelta,
        CASE WHEN (c.num_of_reads - b.num_of_reads) > 0 
             THEN CAST((c.io_stall_read_ms - b.io_stall_read_ms) * 1.0 / (c.num_of_reads - b.num_of_reads) AS DECIMAL(10,2))
             ELSE 0 
        END AS AvgReadLatencyMs,
        CASE WHEN (c.num_of_writes - b.num_of_writes) > 0 
             THEN CAST((c.io_stall_write_ms - b.io_stall_write_ms) * 1.0 / (c.num_of_writes - b.num_of_writes) AS DECIMAL(10,2))
             ELSE 0 
        END AS AvgWriteLatencyMs
    FROM sys.dm_io_virtual_file_stats(NULL, NULL) c
    INNER JOIN dbo.IOBaseline b ON c.database_id = b.database_id AND c.file_id = b.file_id
    INNER JOIN sys.master_files mf ON c.database_id = mf.database_id AND c.file_id = mf.file_id
    WHERE b.BaselineName = @BaselineName
    ORDER BY (c.io_stall_read_ms - b.io_stall_read_ms) + (c.io_stall_write_ms - b.io_stall_write_ms) DESC;
END
GO

-- Get IO latency recommendations
CREATE PROCEDURE dbo.GetIOLatencyRecommendations
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        DB_NAME(vfs.database_id) AS DatabaseName,
        mf.name AS FileName,
        mf.type_desc AS FileType,
        CASE WHEN vfs.num_of_reads > 0 
             THEN CAST(vfs.io_stall_read_ms * 1.0 / vfs.num_of_reads AS DECIMAL(10,2))
             ELSE 0 
        END AS AvgReadLatencyMs,
        CASE WHEN vfs.num_of_writes > 0 
             THEN CAST(vfs.io_stall_write_ms * 1.0 / vfs.num_of_writes AS DECIMAL(10,2))
             ELSE 0 
        END AS AvgWriteLatencyMs,
        CASE 
            WHEN vfs.num_of_reads > 0 AND vfs.io_stall_read_ms * 1.0 / vfs.num_of_reads > 20 THEN 
                'HIGH READ LATENCY - Consider faster storage or query optimization'
            WHEN vfs.num_of_reads > 0 AND vfs.io_stall_read_ms * 1.0 / vfs.num_of_reads > 10 THEN 
                'Elevated read latency - Monitor closely'
            ELSE 'Read latency acceptable'
        END AS ReadRecommendation,
        CASE 
            WHEN mf.type_desc = 'LOG' AND vfs.num_of_writes > 0 AND vfs.io_stall_write_ms * 1.0 / vfs.num_of_writes > 5 THEN 
                'HIGH LOG WRITE LATENCY - Transaction log writes are slow'
            WHEN vfs.num_of_writes > 0 AND vfs.io_stall_write_ms * 1.0 / vfs.num_of_writes > 20 THEN 
                'HIGH WRITE LATENCY - Consider faster storage'
            WHEN vfs.num_of_writes > 0 AND vfs.io_stall_write_ms * 1.0 / vfs.num_of_writes > 10 THEN 
                'Elevated write latency - Monitor closely'
            ELSE 'Write latency acceptable'
        END AS WriteRecommendation
    FROM sys.dm_io_virtual_file_stats(NULL, NULL) vfs
    INNER JOIN sys.master_files mf ON vfs.database_id = mf.database_id AND vfs.file_id = mf.file_id
    WHERE vfs.num_of_reads + vfs.num_of_writes > 0
    ORDER BY 
        CASE WHEN vfs.num_of_reads > 0 THEN vfs.io_stall_read_ms * 1.0 / vfs.num_of_reads ELSE 0 END +
        CASE WHEN vfs.num_of_writes > 0 THEN vfs.io_stall_write_ms * 1.0 / vfs.num_of_writes ELSE 0 END DESC;
END
GO

-- Get pending IO requests
CREATE PROCEDURE dbo.GetPendingIORequests
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        DB_NAME(pio.database_id) AS DatabaseName,
        mf.name AS FileName,
        mf.type_desc AS FileType,
        pio.io_type AS IOType,
        pio.io_pending_ms_ticks AS PendingMs,
        pio.io_handle AS IOHandle,
        pio.scheduler_address AS SchedulerAddress
    FROM sys.dm_io_pending_io_requests pio
    INNER JOIN sys.dm_io_virtual_file_stats(NULL, NULL) vfs ON pio.io_handle = vfs.file_handle
    INNER JOIN sys.master_files mf ON vfs.database_id = mf.database_id AND vfs.file_id = mf.file_id
    ORDER BY pio.io_pending_ms_ticks DESC;
    
    -- Summary
    SELECT 
        COUNT(*) AS PendingIOCount,
        MAX(io_pending_ms_ticks) AS MaxPendingMs,
        AVG(io_pending_ms_ticks) AS AvgPendingMs
    FROM sys.dm_io_pending_io_requests;
END
GO

-- Analyze IO by query
CREATE PROCEDURE dbo.AnalyzeIOByQuery
    @TopN INT = 25,
    @SortBy NVARCHAR(20) = 'TotalReads'  -- TotalReads, TotalWrites, AvgReads, AvgWrites
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT TOP (@TopN)
        qs.total_logical_reads AS TotalLogicalReads,
        qs.total_physical_reads AS TotalPhysicalReads,
        qs.total_logical_writes AS TotalLogicalWrites,
        qs.execution_count AS ExecutionCount,
        qs.total_logical_reads / qs.execution_count AS AvgLogicalReads,
        qs.total_physical_reads / qs.execution_count AS AvgPhysicalReads,
        qs.total_logical_writes / qs.execution_count AS AvgLogicalWrites,
        SUBSTRING(st.text, (qs.statement_start_offset/2) + 1,
            ((CASE qs.statement_end_offset
                WHEN -1 THEN DATALENGTH(st.text)
                ELSE qs.statement_end_offset
            END - qs.statement_start_offset)/2) + 1) AS QueryText
    FROM sys.dm_exec_query_stats qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
    ORDER BY 
        CASE @SortBy
            WHEN 'TotalReads' THEN qs.total_logical_reads
            WHEN 'TotalWrites' THEN qs.total_logical_writes
            WHEN 'AvgReads' THEN qs.total_logical_reads / qs.execution_count
            WHEN 'AvgWrites' THEN qs.total_logical_writes / qs.execution_count
            ELSE qs.total_logical_reads
        END DESC;
END
GO
