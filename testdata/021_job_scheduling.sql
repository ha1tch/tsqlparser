-- Sample 021: SQL Agent Job Management Procedures
-- Source: Microsoft Learn, MSSQLTips, SQLServerCentral
-- Category: Scheduling/Jobs
-- Complexity: Advanced
-- Features: msdb system tables, sp_add_job, sp_add_jobstep, sp_add_schedule

-- Create a complete SQL Agent job with step and schedule
CREATE PROCEDURE dbo.CreateMaintenanceJob
    @JobName NVARCHAR(128),
    @JobDescription NVARCHAR(512) = NULL,
    @StepName NVARCHAR(128),
    @StepCommand NVARCHAR(MAX),
    @DatabaseName NVARCHAR(128) = NULL,
    @ScheduleName NVARCHAR(128) = NULL,
    @FrequencyType INT = 4,  -- 4 = Daily
    @FrequencyInterval INT = 1,
    @StartTime INT = 20000,  -- HHMMSS format (8:00 PM)
    @OwnerLogin NVARCHAR(128) = NULL,
    @NotifyEmail NVARCHAR(128) = NULL,
    @Enabled BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @JobID UNIQUEIDENTIFIER;
    DECLARE @ScheduleID INT;
    DECLARE @ReturnCode INT = 0;
    DECLARE @OperatorName NVARCHAR(128);
    
    SET @OwnerLogin = ISNULL(@OwnerLogin, SUSER_SNAME());
    SET @DatabaseName = ISNULL(@DatabaseName, DB_NAME());
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        -- Delete job if it already exists
        IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @JobName)
        BEGIN
            EXEC msdb.dbo.sp_delete_job @job_name = @JobName, @delete_unused_schedule = 1;
        END
        
        -- Create the job
        EXEC @ReturnCode = msdb.dbo.sp_add_job
            @job_name = @JobName,
            @enabled = @Enabled,
            @description = @JobDescription,
            @owner_login_name = @OwnerLogin,
            @notify_level_eventlog = 2,  -- On failure
            @notify_level_email = CASE WHEN @NotifyEmail IS NOT NULL THEN 2 ELSE 0 END,
            @job_id = @JobID OUTPUT;
        
        IF @ReturnCode <> 0
        BEGIN
            RAISERROR('Failed to create job', 16, 1);
            RETURN;
        END
        
        -- Add job step
        EXEC @ReturnCode = msdb.dbo.sp_add_jobstep
            @job_id = @JobID,
            @step_name = @StepName,
            @step_id = 1,
            @subsystem = N'TSQL',
            @command = @StepCommand,
            @database_name = @DatabaseName,
            @on_success_action = 1,  -- Quit with success
            @on_fail_action = 2,     -- Quit with failure
            @retry_attempts = 3,
            @retry_interval = 5;
        
        IF @ReturnCode <> 0
        BEGIN
            RAISERROR('Failed to add job step', 16, 1);
            RETURN;
        END
        
        -- Add schedule if specified
        IF @ScheduleName IS NOT NULL
        BEGIN
            EXEC @ReturnCode = msdb.dbo.sp_add_schedule
                @schedule_name = @ScheduleName,
                @enabled = 1,
                @freq_type = @FrequencyType,
                @freq_interval = @FrequencyInterval,
                @freq_subday_type = 1,  -- At specified time
                @active_start_time = @StartTime,
                @schedule_id = @ScheduleID OUTPUT;
            
            IF @ReturnCode <> 0
            BEGIN
                RAISERROR('Failed to create schedule', 16, 1);
                RETURN;
            END
            
            -- Attach schedule to job
            EXEC @ReturnCode = msdb.dbo.sp_attach_schedule
                @job_id = @JobID,
                @schedule_id = @ScheduleID;
            
            IF @ReturnCode <> 0
            BEGIN
                RAISERROR('Failed to attach schedule', 16, 1);
                RETURN;
            END
        END
        
        -- Add job server (required to run locally)
        EXEC @ReturnCode = msdb.dbo.sp_add_jobserver
            @job_id = @JobID,
            @server_name = N'(local)';
        
        COMMIT TRANSACTION;
        
        SELECT 
            @JobName AS JobName,
            @JobID AS JobID,
            'Created successfully' AS Status,
            @ScheduleName AS ScheduleName;
            
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        THROW;
    END CATCH
END
GO

-- Get job execution history
CREATE PROCEDURE dbo.GetJobHistory
    @JobName NVARCHAR(128) = NULL,
    @StartDate DATETIME = NULL,
    @EndDate DATETIME = NULL,
    @OnlyFailed BIT = 0,
    @TopN INT = 100
AS
BEGIN
    SET NOCOUNT ON;
    
    SET @StartDate = ISNULL(@StartDate, DATEADD(DAY, -7, GETDATE()));
    SET @EndDate = ISNULL(@EndDate, GETDATE());
    
    SELECT TOP (@TopN)
        j.name AS JobName,
        h.step_id AS StepID,
        h.step_name AS StepName,
        CASE h.run_status
            WHEN 0 THEN 'Failed'
            WHEN 1 THEN 'Succeeded'
            WHEN 2 THEN 'Retry'
            WHEN 3 THEN 'Canceled'
            WHEN 4 THEN 'In Progress'
        END AS RunStatus,
        msdb.dbo.agent_datetime(h.run_date, h.run_time) AS RunDateTime,
        STUFF(STUFF(RIGHT('000000' + CAST(h.run_duration AS VARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':') AS Duration,
        h.run_duration AS DurationSeconds,
        h.message AS Message,
        h.retries_attempted AS RetriesAttempted,
        h.server AS ServerName
    FROM msdb.dbo.sysjobhistory h
    INNER JOIN msdb.dbo.sysjobs j ON h.job_id = j.job_id
    WHERE (@JobName IS NULL OR j.name = @JobName)
      AND msdb.dbo.agent_datetime(h.run_date, h.run_time) BETWEEN @StartDate AND @EndDate
      AND (@OnlyFailed = 0 OR h.run_status = 0)
      AND h.step_id > 0  -- Exclude job outcome record
    ORDER BY msdb.dbo.agent_datetime(h.run_date, h.run_time) DESC;
END
GO

-- Monitor running jobs
CREATE PROCEDURE dbo.GetRunningJobs
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        j.name AS JobName,
        ja.start_execution_date AS StartTime,
        DATEDIFF(MINUTE, ja.start_execution_date, GETDATE()) AS RunningMinutes,
        ISNULL(js.step_name, 'Unknown') AS CurrentStep,
        js.step_id AS StepID,
        ja.last_executed_step_id,
        j.description AS JobDescription
    FROM msdb.dbo.sysjobactivity ja
    INNER JOIN msdb.dbo.sysjobs j ON ja.job_id = j.job_id
    LEFT JOIN msdb.dbo.sysjobsteps js 
        ON ja.job_id = js.job_id 
        AND ja.last_executed_step_id + 1 = js.step_id
    WHERE ja.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)
      AND ja.start_execution_date IS NOT NULL
      AND ja.stop_execution_date IS NULL
    ORDER BY ja.start_execution_date;
END
GO

-- Start a job and wait for completion
CREATE PROCEDURE dbo.StartJobAndWait
    @JobName NVARCHAR(128),
    @TimeoutSeconds INT = 3600,  -- 1 hour default
    @PollIntervalSeconds INT = 10
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @JobID UNIQUEIDENTIFIER;
    DECLARE @StartTime DATETIME = GETDATE();
    DECLARE @IsRunning BIT = 0;
    DECLARE @LastRunStatus INT;
    DECLARE @Message NVARCHAR(MAX);
    
    -- Get job ID
    SELECT @JobID = job_id 
    FROM msdb.dbo.sysjobs 
    WHERE name = @JobName;
    
    IF @JobID IS NULL
    BEGIN
        RAISERROR('Job not found: %s', 16, 1, @JobName);
        RETURN;
    END
    
    -- Check if already running
    IF EXISTS (
        SELECT 1 FROM msdb.dbo.sysjobactivity ja
        WHERE ja.job_id = @JobID
          AND ja.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)
          AND ja.start_execution_date IS NOT NULL
          AND ja.stop_execution_date IS NULL
    )
    BEGIN
        RAISERROR('Job is already running: %s', 16, 1, @JobName);
        RETURN;
    END
    
    -- Start the job
    EXEC msdb.dbo.sp_start_job @job_name = @JobName;
    
    PRINT 'Job started: ' + @JobName;
    
    -- Wait for job to start
    WAITFOR DELAY '00:00:02';
    
    -- Poll until complete or timeout
    WHILE DATEDIFF(SECOND, @StartTime, GETDATE()) < @TimeoutSeconds
    BEGIN
        -- Check if job is still running
        IF EXISTS (
            SELECT 1 FROM msdb.dbo.sysjobactivity ja
            WHERE ja.job_id = @JobID
              AND ja.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)
              AND ja.start_execution_date IS NOT NULL
              AND ja.stop_execution_date IS NULL
        )
        BEGIN
            SET @IsRunning = 1;
            WAITFOR DELAY '00:00:10';  -- Poll every 10 seconds
        END
        ELSE
        BEGIN
            SET @IsRunning = 0;
            BREAK;
        END
    END
    
    -- Get final status
    SELECT TOP 1
        @LastRunStatus = h.run_status,
        @Message = h.message
    FROM msdb.dbo.sysjobhistory h
    WHERE h.job_id = @JobID
      AND h.step_id = 0  -- Job outcome
    ORDER BY h.run_date DESC, h.run_time DESC;
    
    -- Return result
    SELECT 
        @JobName AS JobName,
        CASE @LastRunStatus
            WHEN 0 THEN 'Failed'
            WHEN 1 THEN 'Succeeded'
            WHEN 2 THEN 'Retry'
            WHEN 3 THEN 'Canceled'
            ELSE 'Unknown'
        END AS FinalStatus,
        DATEDIFF(SECOND, @StartTime, GETDATE()) AS DurationSeconds,
        @Message AS Message,
        CASE WHEN @IsRunning = 1 THEN 'Timed out' ELSE 'Completed' END AS CompletionType;
END
GO

-- Disable jobs by pattern
CREATE PROCEDURE dbo.ManageJobsByPattern
    @NamePattern NVARCHAR(128),
    @Action NVARCHAR(20) = 'DISABLE',  -- ENABLE, DISABLE, DELETE
    @WhatIf BIT = 1  -- Preview mode by default
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @JobName NVARCHAR(128);
    DECLARE @SQL NVARCHAR(MAX);
    
    -- Show affected jobs
    SELECT 
        j.name AS JobName,
        j.enabled AS CurrentStatus,
        @Action AS PlannedAction
    FROM msdb.dbo.sysjobs j
    WHERE j.name LIKE @NamePattern;
    
    IF @WhatIf = 0
    BEGIN
        DECLARE JobCursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT name FROM msdb.dbo.sysjobs WHERE name LIKE @NamePattern;
        
        OPEN JobCursor;
        FETCH NEXT FROM JobCursor INTO @JobName;
        
        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF @Action = 'ENABLE'
                EXEC msdb.dbo.sp_update_job @job_name = @JobName, @enabled = 1;
            ELSE IF @Action = 'DISABLE'
                EXEC msdb.dbo.sp_update_job @job_name = @JobName, @enabled = 0;
            ELSE IF @Action = 'DELETE'
                EXEC msdb.dbo.sp_delete_job @job_name = @JobName, @delete_unused_schedule = 1;
            
            PRINT @Action + ': ' + @JobName;
            
            FETCH NEXT FROM JobCursor INTO @JobName;
        END
        
        CLOSE JobCursor;
        DEALLOCATE JobCursor;
    END
    ELSE
    BEGIN
        PRINT 'WhatIf mode - no changes made. Set @WhatIf = 0 to execute.';
    END
END
GO
