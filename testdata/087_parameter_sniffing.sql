-- Sample 087: Parameter Sniffing Management
-- Source: Brent Ozar, Kendra Little, Microsoft Learn
-- Category: Performance
-- Complexity: Advanced
-- Features: Parameter sniffing detection, OPTIMIZE FOR, RECOMPILE, plan guides

-- Detect procedures affected by parameter sniffing
CREATE PROCEDURE dbo.DetectParameterSniffingIssues
    @MinExecutions INT = 100,
    @VarianceThreshold DECIMAL(5,2) = 5.0  -- Max/Avg ratio threshold
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        OBJECT_NAME(qs.object_id, qs.database_id) AS ProcedureName,
        qs.execution_count AS ExecutionCount,
        qs.total_worker_time / qs.execution_count / 1000 AS AvgCPUMs,
        qs.max_worker_time / 1000 AS MaxCPUMs,
        CAST(qs.max_worker_time * 1.0 / NULLIF(qs.total_worker_time / qs.execution_count, 0) AS DECIMAL(10,2)) AS CPUVarianceRatio,
        qs.total_elapsed_time / qs.execution_count / 1000 AS AvgDurationMs,
        qs.max_elapsed_time / 1000 AS MaxDurationMs,
        CAST(qs.max_elapsed_time * 1.0 / NULLIF(qs.total_elapsed_time / qs.execution_count, 0) AS DECIMAL(10,2)) AS DurationVarianceRatio,
        qs.total_logical_reads / qs.execution_count AS AvgLogicalReads,
        qs.max_logical_reads AS MaxLogicalReads,
        CAST(qs.max_logical_reads * 1.0 / NULLIF(qs.total_logical_reads / qs.execution_count, 0) AS DECIMAL(10,2)) AS ReadsVarianceRatio,
        qs.plan_generation_num AS PlanRegenerations,
        'Potential parameter sniffing - high variance in execution metrics' AS Analysis
    FROM sys.dm_exec_procedure_stats qs
    WHERE qs.database_id = DB_ID()
      AND qs.execution_count >= @MinExecutions
      AND (
          qs.max_worker_time * 1.0 / NULLIF(qs.total_worker_time / qs.execution_count, 0) > @VarianceThreshold
          OR qs.max_elapsed_time * 1.0 / NULLIF(qs.total_elapsed_time / qs.execution_count, 0) > @VarianceThreshold
          OR qs.max_logical_reads * 1.0 / NULLIF(qs.total_logical_reads / qs.execution_count, 0) > @VarianceThreshold
      )
    ORDER BY DurationVarianceRatio DESC;
END
GO

-- Generate parameter sniffing fix script
CREATE PROCEDURE dbo.GenerateParameterSniffingFix
    @SchemaName NVARCHAR(128) = 'dbo',
    @ProcedureName NVARCHAR(128),
    @FixType NVARCHAR(20) = 'LOCAL_VARIABLE'  -- LOCAL_VARIABLE, OPTIMIZE_UNKNOWN, RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @ProcDefinition NVARCHAR(MAX);
    DECLARE @Parameters NVARCHAR(MAX);
    DECLARE @FixedDefinition NVARCHAR(MAX);
    
    -- Get procedure definition
    SELECT @ProcDefinition = m.definition
    FROM sys.sql_modules m
    INNER JOIN sys.objects o ON m.object_id = o.object_id
    WHERE o.name = @ProcedureName AND SCHEMA_NAME(o.schema_id) = @SchemaName;
    
    IF @ProcDefinition IS NULL
    BEGIN
        RAISERROR('Procedure not found: %s.%s', 16, 1, @SchemaName, @ProcedureName);
        RETURN;
    END
    
    -- Get parameters
    SELECT @Parameters = STRING_AGG(
        name + ' ' + TYPE_NAME(user_type_id) + 
        CASE WHEN TYPE_NAME(user_type_id) IN ('varchar', 'nvarchar', 'char', 'nchar') 
             THEN '(' + CASE WHEN max_length = -1 THEN 'MAX' ELSE CAST(max_length AS VARCHAR(10)) END + ')'
             WHEN TYPE_NAME(user_type_id) IN ('decimal', 'numeric')
             THEN '(' + CAST(precision AS VARCHAR(10)) + ',' + CAST(scale AS VARCHAR(10)) + ')'
             ELSE ''
        END,
        ', '
    )
    FROM sys.parameters
    WHERE object_id = OBJECT_ID(QUOTENAME(@SchemaName) + '.' + QUOTENAME(@ProcedureName))
      AND parameter_id > 0;
    
    -- Generate fix based on type
    IF @FixType = 'LOCAL_VARIABLE'
    BEGIN
        SELECT 
            'Option 1: Local Variable Pattern' AS FixType,
            '-- Add at the beginning of the procedure body:' AS Comment,
            STRING_AGG('DECLARE ' + REPLACE(name, '@', '@Local_') + ' ' + TYPE_NAME(user_type_id) + ' = ' + name + ';', CHAR(13) + CHAR(10)) AS LocalVariableDeclarations,
            '-- Then replace all parameter references with local variables' AS Note
        FROM sys.parameters
        WHERE object_id = OBJECT_ID(QUOTENAME(@SchemaName) + '.' + QUOTENAME(@ProcedureName))
          AND parameter_id > 0;
    END
    ELSE IF @FixType = 'OPTIMIZE_UNKNOWN'
    BEGIN
        SELECT 
            'Option 2: OPTIMIZE FOR UNKNOWN' AS FixType,
            '-- Add to problematic queries:' AS Comment,
            'OPTION (OPTIMIZE FOR (' + STRING_AGG(name + ' UNKNOWN', ', ') + '))' AS HintToAdd
        FROM sys.parameters
        WHERE object_id = OBJECT_ID(QUOTENAME(@SchemaName) + '.' + QUOTENAME(@ProcedureName))
          AND parameter_id > 0;
    END
    ELSE IF @FixType = 'RECOMPILE'
    BEGIN
        SELECT 
            'Option 3: WITH RECOMPILE' AS FixType,
            '-- Modify procedure header:' AS Comment,
            'CREATE PROCEDURE ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@ProcedureName) AS ModifiedHeader,
            '    ' + @Parameters AS Parameters,
            'WITH RECOMPILE' AS AddedClause,
            'AS' AS ProcedureBody,
            '-- Note: This causes recompilation on every execution' AS Warning;
    END
    
    -- Also suggest Query Store forced plan
    SELECT 
        'Alternative: Use Query Store to force a good plan' AS AdditionalOption,
        'EXEC sp_query_store_force_plan @query_id = <query_id>, @plan_id = <plan_id>;' AS Example;
END
GO

-- Create plan guide for parameter sniffing
CREATE PROCEDURE dbo.CreateParameterSniffingPlanGuide
    @GuideName NVARCHAR(128),
    @SchemaName NVARCHAR(128) = 'dbo',
    @ProcedureName NVARCHAR(128),
    @StatementText NVARCHAR(MAX),
    @HintType NVARCHAR(20) = 'OPTIMIZE_UNKNOWN',  -- OPTIMIZE_UNKNOWN, RECOMPILE, SPECIFIC_VALUE
    @SpecificValues NVARCHAR(MAX) = NULL  -- For SPECIFIC_VALUE type
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @Hints NVARCHAR(MAX);
    DECLARE @Parameters NVARCHAR(MAX);
    
    -- Build parameter list
    SELECT @Parameters = STRING_AGG(
        name + ' ' + TYPE_NAME(user_type_id) + 
        CASE WHEN TYPE_NAME(user_type_id) IN ('varchar', 'nvarchar', 'char', 'nchar') 
             THEN '(' + CASE WHEN max_length = -1 THEN 'MAX' ELSE CAST(max_length AS VARCHAR(10)) END + ')'
             ELSE ''
        END,
        ', '
    )
    FROM sys.parameters
    WHERE object_id = OBJECT_ID(QUOTENAME(@SchemaName) + '.' + QUOTENAME(@ProcedureName))
      AND parameter_id > 0;
    
    -- Build hint
    IF @HintType = 'OPTIMIZE_UNKNOWN'
    BEGIN
        SELECT @Hints = 'OPTION (OPTIMIZE FOR (' + 
            STRING_AGG(name + ' UNKNOWN', ', ') + '))'
        FROM sys.parameters
        WHERE object_id = OBJECT_ID(QUOTENAME(@SchemaName) + '.' + QUOTENAME(@ProcedureName))
          AND parameter_id > 0;
    END
    ELSE IF @HintType = 'RECOMPILE'
    BEGIN
        SET @Hints = 'OPTION (RECOMPILE)';
    END
    ELSE IF @HintType = 'SPECIFIC_VALUE'
    BEGIN
        SET @Hints = 'OPTION (OPTIMIZE FOR (' + @SpecificValues + '))';
    END
    
    -- Create plan guide
    EXEC sp_create_plan_guide
        @name = @GuideName,
        @stmt = @StatementText,
        @type = N'OBJECT',
        @module_or_batch = @ProcedureName,
        @params = @Parameters,
        @hints = @Hints;
    
    SELECT 'Plan guide created: ' + @GuideName AS Status;
END
GO

-- List existing plan guides
CREATE PROCEDURE dbo.ListPlanGuides
    @IncludeDisabled BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        pg.name AS GuideName,
        pg.scope_type_desc AS ScopeType,
        pg.scope_object_id,
        OBJECT_NAME(pg.scope_object_id) AS ObjectName,
        pg.is_disabled AS IsDisabled,
        pg.query_text AS QueryText,
        pg.hints AS Hints,
        pg.create_date AS CreatedDate,
        pg.modify_date AS ModifiedDate
    FROM sys.plan_guides pg
    WHERE @IncludeDisabled = 1 OR pg.is_disabled = 0
    ORDER BY pg.name;
END
GO

-- Test procedure with different parameter values
CREATE PROCEDURE dbo.TestParameterSniffing
    @SchemaName NVARCHAR(128) = 'dbo',
    @ProcedureName NVARCHAR(128),
    @TestValues NVARCHAR(MAX)  -- JSON array: [{"param":"@ID","values":[1,100,10000]}]
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @Param NVARCHAR(128);
    DECLARE @Value NVARCHAR(MAX);
    
    -- Clear procedure cache for this proc
    DECLARE @PlanHandle VARBINARY(64);
    SELECT @PlanHandle = plan_handle
    FROM sys.dm_exec_procedure_stats
    WHERE object_id = OBJECT_ID(QUOTENAME(@SchemaName) + '.' + QUOTENAME(@ProcedureName));
    
    IF @PlanHandle IS NOT NULL
        DBCC FREEPROCCACHE(@PlanHandle);
    
    -- Test with each value
    CREATE TABLE #Results (
        TestOrder INT IDENTITY(1,1),
        ParameterValue NVARCHAR(MAX),
        ExecutionTimeMs INT,
        LogicalReads BIGINT,
        CPUTimeMs INT
    );
    
    SELECT 
        'Testing with different parameter values' AS Status,
        'First execution compiles plan, subsequent use cached plan' AS Note;
    
    -- Parse JSON and execute tests
    DECLARE @TestCursor CURSOR;
    SET @TestCursor = CURSOR FOR
        SELECT value FROM OPENJSON(@TestValues);
    
    OPEN @TestCursor;
    FETCH NEXT FROM @TestCursor INTO @Value;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @SQL = 'SET STATISTICS IO ON; SET STATISTICS TIME ON; EXEC ' + 
                   QUOTENAME(@SchemaName) + '.' + QUOTENAME(@ProcedureName) + ' ' + @Value;
        
        -- Execute and capture metrics
        DECLARE @StartTime DATETIME2 = SYSDATETIME();
        EXEC sp_executesql @SQL;
        
        INSERT INTO #Results (ParameterValue, ExecutionTimeMs)
        VALUES (@Value, DATEDIFF(MILLISECOND, @StartTime, SYSDATETIME()));
        
        FETCH NEXT FROM @TestCursor INTO @Value;
    END
    
    CLOSE @TestCursor;
    DEALLOCATE @TestCursor;
    
    SELECT * FROM #Results ORDER BY TestOrder;
    DROP TABLE #Results;
END
GO

-- Monitor parameter sniffing in Query Store
CREATE PROCEDURE dbo.MonitorParameterSniffingQueryStore
    @MinExecutions INT = 100
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        q.query_id,
        qt.query_sql_text,
        COUNT(DISTINCT p.plan_id) AS PlanCount,
        MIN(rs.avg_duration) / 1000 AS MinAvgDurationMs,
        MAX(rs.avg_duration) / 1000 AS MaxAvgDurationMs,
        MAX(rs.avg_duration) / NULLIF(MIN(rs.avg_duration), 0) AS DurationVariance,
        MIN(rs.avg_logical_io_reads) AS MinAvgReads,
        MAX(rs.avg_logical_io_reads) AS MaxAvgReads,
        SUM(rs.count_executions) AS TotalExecutions
    FROM sys.query_store_query q
    INNER JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id
    INNER JOIN sys.query_store_plan p ON q.query_id = p.query_id
    INNER JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
    GROUP BY q.query_id, qt.query_sql_text
    HAVING COUNT(DISTINCT p.plan_id) > 1
       AND SUM(rs.count_executions) >= @MinExecutions
       AND MAX(rs.avg_duration) / NULLIF(MIN(rs.avg_duration), 0) > 3
    ORDER BY DurationVariance DESC;
END
GO
