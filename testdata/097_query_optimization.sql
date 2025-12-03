-- Sample 097: Query Optimization Helpers
-- Source: Brent Ozar, Grant Fritchey, Microsoft Learn
-- Category: Performance
-- Complexity: Advanced
-- Features: Query hints, plan forcing, optimization diagnostics, anti-pattern detection

-- Analyze query for optimization opportunities
CREATE PROCEDURE dbo.AnalyzeQueryOptimization
    @QueryText NVARCHAR(MAX),
    @DatabaseName NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    SET @DatabaseName = ISNULL(@DatabaseName, DB_NAME());
    
    -- Optimization suggestions
    CREATE TABLE #Suggestions (
        SuggestionID INT IDENTITY(1,1),
        Category NVARCHAR(50),
        Issue NVARCHAR(200),
        Recommendation NVARCHAR(500),
        Severity NVARCHAR(20)
    );
    
    -- Check for common anti-patterns
    
    -- SELECT *
    IF @QueryText LIKE '%SELECT *%' OR @QueryText LIKE '%SELECT%*%FROM%'
        INSERT INTO #Suggestions VALUES ('Column Selection', 'Using SELECT *', 'Specify only needed columns to reduce IO and memory', 'Medium');
    
    -- Functions on columns in WHERE
    IF @QueryText LIKE '%WHERE%YEAR(%' OR @QueryText LIKE '%WHERE%MONTH(%' 
       OR @QueryText LIKE '%WHERE%CONVERT(%' OR @QueryText LIKE '%WHERE%CAST(%'
        INSERT INTO #Suggestions VALUES ('SARGability', 'Function on column in WHERE clause', 'Rewrite to avoid functions on columns for index usage', 'High');
    
    -- LIKE with leading wildcard
    IF @QueryText LIKE '%LIKE ''[%]%'
        INSERT INTO #Suggestions VALUES ('SARGability', 'Leading wildcard in LIKE', 'Leading wildcards prevent index seeks', 'High');
    
    -- OR conditions
    IF @QueryText LIKE '%WHERE%OR%'
        INSERT INTO #Suggestions VALUES ('Query Structure', 'OR conditions in WHERE', 'Consider UNION ALL for better plan optimization', 'Medium');
    
    -- NOT IN with subquery
    IF @QueryText LIKE '%NOT IN%(%SELECT%'
        INSERT INTO #Suggestions VALUES ('Query Structure', 'NOT IN with subquery', 'Use NOT EXISTS for better NULL handling and performance', 'Medium');
    
    -- Cursors
    IF @QueryText LIKE '%DECLARE%CURSOR%' OR @QueryText LIKE '%OPEN%CURSOR%'
        INSERT INTO #Suggestions VALUES ('Set-Based', 'Cursor usage detected', 'Consider set-based alternatives for better performance', 'High');
    
    -- Scalar UDF in SELECT
    IF @QueryText LIKE '%SELECT%dbo.%(%' AND @QueryText NOT LIKE '%CROSS APPLY%'
        INSERT INTO #Suggestions VALUES ('Functions', 'Possible scalar UDF in SELECT', 'Scalar UDFs execute row-by-row; consider inline TVF or computed column', 'High');
    
    -- Missing TOP/OFFSET without ORDER BY
    IF (@QueryText LIKE '%TOP%' OR @QueryText LIKE '%OFFSET%') 
       AND @QueryText NOT LIKE '%ORDER BY%'
        INSERT INTO #Suggestions VALUES ('Query Structure', 'TOP/OFFSET without ORDER BY', 'Results are non-deterministic without ORDER BY', 'Medium');
    
    -- NOLOCK hint
    IF @QueryText LIKE '%NOLOCK%' OR @QueryText LIKE '%READ UNCOMMITTED%'
        INSERT INTO #Suggestions VALUES ('Isolation', 'NOLOCK/READ UNCOMMITTED used', 'May return dirty reads; verify this is acceptable', 'Low');
    
    -- Implicit conversion potential (common patterns)
    IF @QueryText LIKE '%WHERE%=%N''%' 
        INSERT INTO #Suggestions VALUES ('Data Types', 'Potential implicit conversion', 'N prefix on varchar columns causes implicit conversion', 'Medium');
    
    -- DISTINCT with GROUP BY
    IF @QueryText LIKE '%DISTINCT%' AND @QueryText LIKE '%GROUP BY%'
        INSERT INTO #Suggestions VALUES ('Query Structure', 'DISTINCT with GROUP BY', 'GROUP BY usually eliminates need for DISTINCT', 'Low');
    
    -- Return suggestions
    SELECT * FROM #Suggestions ORDER BY 
        CASE Severity WHEN 'High' THEN 1 WHEN 'Medium' THEN 2 ELSE 3 END,
        Category;
    
    DROP TABLE #Suggestions;
    
    -- Get estimated plan
    DECLARE @SQL NVARCHAR(MAX) = 'SET SHOWPLAN_XML ON; ' + @QueryText + '; SET SHOWPLAN_XML OFF;';
    -- Note: Would need to execute and capture plan in practice
END
GO

-- Find queries that would benefit from specific indexes
CREATE PROCEDURE dbo.FindMissingIndexOpportunities
    @TopN INT = 25,
    @MinImpact DECIMAL(10,2) = 1000
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT TOP (@TopN)
        d.statement AS TableName,
        d.equality_columns AS EqualityColumns,
        d.inequality_columns AS InequalityColumns,
        d.included_columns AS IncludedColumns,
        CAST(s.avg_user_impact AS DECIMAL(5,2)) AS AvgImpactPercent,
        s.user_seeks AS UserSeeks,
        s.user_scans AS UserScans,
        CAST(s.avg_user_impact * (s.user_seeks + s.user_scans) AS DECIMAL(18,2)) AS TotalImpact,
        'CREATE NONCLUSTERED INDEX IX_' + 
            REPLACE(REPLACE(REPLACE(d.statement, '[', ''), ']', ''), '.', '_') + '_' +
            CAST(d.index_handle AS VARCHAR(10)) +
            ' ON ' + d.statement + ' (' +
            ISNULL(d.equality_columns, '') +
            CASE WHEN d.equality_columns IS NOT NULL AND d.inequality_columns IS NOT NULL THEN ', ' ELSE '' END +
            ISNULL(d.inequality_columns, '') + ')' +
            CASE WHEN d.included_columns IS NOT NULL THEN ' INCLUDE (' + d.included_columns + ')' ELSE '' END
            AS CreateStatement
    FROM sys.dm_db_missing_index_details d
    INNER JOIN sys.dm_db_missing_index_groups g ON d.index_handle = g.index_handle
    INNER JOIN sys.dm_db_missing_index_group_stats s ON g.index_group_handle = s.group_handle
    WHERE d.database_id = DB_ID()
      AND s.avg_user_impact * (s.user_seeks + s.user_scans) >= @MinImpact
    ORDER BY TotalImpact DESC;
END
GO

-- Generate query hints for problematic queries
CREATE PROCEDURE dbo.GenerateQueryHints
    @QueryHash BINARY(8) = NULL,
    @ObjectName NVARCHAR(256) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    CREATE TABLE #HintSuggestions (
        Category NVARCHAR(50),
        HintType NVARCHAR(50),
        HintSyntax NVARCHAR(200),
        WhenToUse NVARCHAR(500)
    );
    
    INSERT INTO #HintSuggestions VALUES
    -- Join hints
    ('Join', 'LOOP JOIN', 'OPTION (LOOP JOIN)', 'Force nested loops; good for small outer tables'),
    ('Join', 'HASH JOIN', 'OPTION (HASH JOIN)', 'Force hash match; good for large unsorted tables'),
    ('Join', 'MERGE JOIN', 'OPTION (MERGE JOIN)', 'Force merge join; good for sorted inputs'),
    
    -- Parallelism
    ('Parallelism', 'MAXDOP', 'OPTION (MAXDOP 1)', 'Disable parallelism for OLTP queries'),
    ('Parallelism', 'MAXDOP N', 'OPTION (MAXDOP 4)', 'Limit parallel threads'),
    
    -- Optimization
    ('Optimization', 'RECOMPILE', 'OPTION (RECOMPILE)', 'Fresh plan each execution; for parameter sniffing'),
    ('Optimization', 'OPTIMIZE FOR', 'OPTION (OPTIMIZE FOR (@param = value))', 'Optimize for specific parameter value'),
    ('Optimization', 'OPTIMIZE FOR UNKNOWN', 'OPTION (OPTIMIZE FOR UNKNOWN)', 'Use average statistics distribution'),
    
    -- Memory
    ('Memory', 'MIN_GRANT_PERCENT', 'OPTION (MIN_GRANT_PERCENT = 10)', 'Guarantee minimum memory grant'),
    ('Memory', 'MAX_GRANT_PERCENT', 'OPTION (MAX_GRANT_PERCENT = 25)', 'Limit maximum memory grant'),
    
    -- Cardinality
    ('Cardinality', 'USE HINT CE70', 'OPTION (USE HINT (''FORCE_LEGACY_CARDINALITY_ESTIMATION''))', 'Use SQL 2012 CE model'),
    ('Cardinality', 'ASSUME_MIN_SELECTIVITY', 'OPTION (USE HINT (''ASSUME_MIN_SELECTIVITY_FOR_FILTER_ESTIMATES''))', 'Conservative selectivity estimates'),
    
    -- Table hints
    ('Table', 'INDEX', 'WITH (INDEX(IndexName))', 'Force specific index usage'),
    ('Table', 'FORCESEEK', 'WITH (FORCESEEK)', 'Force index seek operation'),
    ('Table', 'FORCESCAN', 'WITH (FORCESCAN)', 'Force index/table scan');
    
    SELECT * FROM #HintSuggestions ORDER BY Category, HintType;
    
    DROP TABLE #HintSuggestions;
END
GO

-- Identify implicit conversions in cached plans
CREATE PROCEDURE dbo.FindImplicitConversions
    @DatabaseName NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    SET @DatabaseName = ISNULL(@DatabaseName, DB_NAME());
    
    SELECT TOP 50
        st.text AS QueryText,
        qp.query_plan,
        qs.execution_count AS ExecutionCount,
        qs.total_worker_time / 1000 AS TotalCPUMs,
        qs.total_logical_reads AS TotalReads,
        -- Extract CONVERT_IMPLICIT from plan
        qp.query_plan.value('declare namespace p="http://schemas.microsoft.com/sqlserver/2004/07/showplan";
            (//p:ScalarOperator/p:Identifier/p:ColumnReference/@Column)[1]', 'nvarchar(128)') AS AffectedColumn
    FROM sys.dm_exec_query_stats qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
    CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
    WHERE qp.query_plan.exist('declare namespace p="http://schemas.microsoft.com/sqlserver/2004/07/showplan";
            //p:Warnings/p:PlanAffectingConvert') = 1
      AND st.dbid = DB_ID(@DatabaseName)
    ORDER BY qs.total_worker_time DESC;
END
GO

-- Compare query performance metrics
CREATE PROCEDURE dbo.CompareQueryVersions
    @Query1Hash BINARY(8),
    @Query2Hash BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        'Query 1' AS QueryVersion,
        qs.query_hash,
        qs.execution_count,
        qs.total_worker_time / 1000 AS TotalCPUMs,
        qs.total_worker_time / NULLIF(qs.execution_count, 0) / 1000 AS AvgCPUMs,
        qs.total_elapsed_time / 1000 AS TotalDurationMs,
        qs.total_elapsed_time / NULLIF(qs.execution_count, 0) / 1000 AS AvgDurationMs,
        qs.total_logical_reads AS TotalReads,
        qs.total_logical_reads / NULLIF(qs.execution_count, 0) AS AvgReads,
        qs.total_logical_writes AS TotalWrites,
        st.text AS QueryText
    FROM sys.dm_exec_query_stats qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
    WHERE qs.query_hash = @Query1Hash
    
    UNION ALL
    
    SELECT 
        'Query 2',
        qs.query_hash,
        qs.execution_count,
        qs.total_worker_time / 1000,
        qs.total_worker_time / NULLIF(qs.execution_count, 0) / 1000,
        qs.total_elapsed_time / 1000,
        qs.total_elapsed_time / NULLIF(qs.execution_count, 0) / 1000,
        qs.total_logical_reads,
        qs.total_logical_reads / NULLIF(qs.execution_count, 0),
        qs.total_logical_writes,
        st.text
    FROM sys.dm_exec_query_stats qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
    WHERE qs.query_hash = @Query2Hash;
END
GO
