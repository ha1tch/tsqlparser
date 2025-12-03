-- Sample 083: Data Export and Reporting Formats
-- Source: Various - MSSQLTips, Stack Overflow, Reporting patterns
-- Category: Reporting
-- Complexity: Complex
-- Features: CSV/XML/JSON export, formatted reports, pivot reports

-- Export query results to CSV format
CREATE PROCEDURE dbo.ExportToCSV
    @Query NVARCHAR(MAX),
    @IncludeHeaders BIT = 1,
    @Delimiter NVARCHAR(5) = ',',
    @TextQualifier NVARCHAR(1) = '"'
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @Columns NVARCHAR(MAX) = '';
    DECLARE @HeaderRow NVARCHAR(MAX) = '';
    
    -- Create temp table to hold results
    CREATE TABLE #TempResults (RowNum INT IDENTITY(1,1), CSVRow NVARCHAR(MAX));
    
    -- Get column names from query metadata
    DECLARE @ParamDef NVARCHAR(500) = N'@Cols NVARCHAR(MAX) OUTPUT';
    SET @SQL = N'
        SELECT @Cols = STRING_AGG(
            ''ISNULL('' + @TQ + '' + REPLACE(CAST(['' + name + ''] AS NVARCHAR(MAX)), '''''' + @TQ + '''''', '''''' + @TQ + @TQ + '''''') + '' + @TQ, '''''''')'',
            '' + '''''' + @Delim + '''''' + ''
        )
        FROM sys.dm_exec_describe_first_result_set(@Qry, NULL, 0)';
    
    -- Build column concatenation
    SELECT @Columns = STRING_AGG(
        'ISNULL(' + @TextQualifier + ' + REPLACE(CAST([' + name + '] AS NVARCHAR(MAX)), ''' + @TextQualifier + ''', ''' + @TextQualifier + @TextQualifier + ''') + ' + @TextQualifier + ', '''')',
        ' + ''' + @Delimiter + ''' + '
    )
    FROM sys.dm_exec_describe_first_result_set(@Query, NULL, 0);
    
    -- Build header row
    IF @IncludeHeaders = 1
    BEGIN
        SELECT @HeaderRow = STRING_AGG(@TextQualifier + name + @TextQualifier, @Delimiter)
        FROM sys.dm_exec_describe_first_result_set(@Query, NULL, 0);
        
        INSERT INTO #TempResults (CSVRow) VALUES (@HeaderRow);
    END
    
    -- Build and execute data extraction
    SET @SQL = N'
        INSERT INTO #TempResults (CSVRow)
        SELECT ' + @Columns + '
        FROM (' + @Query + ') AS SourceData';
    
    EXEC sp_executesql @SQL;
    
    -- Return results
    SELECT CSVRow FROM #TempResults ORDER BY RowNum;
    
    DROP TABLE #TempResults;
END
GO

-- Export to XML with schema
CREATE PROCEDURE dbo.ExportToXML
    @Query NVARCHAR(MAX),
    @RootElement NVARCHAR(128) = 'Data',
    @RowElement NVARCHAR(128) = 'Row',
    @IncludeSchema BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @Result XML;
    
    IF @IncludeSchema = 1
    BEGIN
        SET @SQL = N'
            SELECT @XMLResult = (
                SELECT * FROM (' + @Query + ') AS SourceData
                FOR XML PATH(''' + @RowElement + '''), ROOT(''' + @RootElement + '''), XMLSCHEMA
            )';
    END
    ELSE
    BEGIN
        SET @SQL = N'
            SELECT @XMLResult = (
                SELECT * FROM (' + @Query + ') AS SourceData
                FOR XML PATH(''' + @RowElement + '''), ROOT(''' + @RootElement + ''')
            )';
    END
    
    EXEC sp_executesql @SQL, N'@XMLResult XML OUTPUT', @XMLResult = @Result OUTPUT;
    
    SELECT @Result AS XMLOutput;
END
GO

-- Generate formatted HTML report
CREATE PROCEDURE dbo.GenerateHTMLReport
    @Query NVARCHAR(MAX),
    @ReportTitle NVARCHAR(200) = 'Data Report',
    @IncludeSummary BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @HTML NVARCHAR(MAX);
    DECLARE @TableHTML NVARCHAR(MAX);
    DECLARE @Headers NVARCHAR(MAX) = '';
    DECLARE @RowCount INT;
    
    -- Build header row
    SELECT @Headers = @Headers + '<th>' + name + '</th>'
    FROM sys.dm_exec_describe_first_result_set(@Query, NULL, 0);
    
    -- Start HTML
    SET @HTML = N'
<!DOCTYPE html>
<html>
<head>
    <title>' + @ReportTitle + '</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        th { background-color: #4472C4; color: white; padding: 12px; text-align: left; }
        td { border: 1px solid #ddd; padding: 10px; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        tr:hover { background-color: #ddd; }
        .summary { background-color: #f0f0f0; padding: 15px; margin-top: 20px; border-radius: 5px; }
        .timestamp { color: #666; font-size: 12px; }
    </style>
</head>
<body>
    <h1>' + @ReportTitle + '</h1>
    <p class="timestamp">Generated: ' + CONVERT(VARCHAR(30), SYSDATETIME(), 121) + '</p>';
    
    -- Build data rows using FOR XML PATH
    DECLARE @SQL NVARCHAR(MAX) = N'
        SELECT @TableOut = (
            SELECT 
                (SELECT td = CAST(col AS NVARCHAR(MAX)), ''''
                 FROM (SELECT * FROM (' + @Query + ') AS src) AS RowData
                 FOR XML PATH(''''), TYPE
                ) AS ''*''
            FROM (' + @Query + ') AS OuterData
            FOR XML PATH(''tr'')
        ),
        @RowCnt = (SELECT COUNT(*) FROM (' + @Query + ') AS CountQuery)';
    
    EXEC sp_executesql @SQL, 
        N'@TableOut NVARCHAR(MAX) OUTPUT, @RowCnt INT OUTPUT', 
        @TableOut = @TableHTML OUTPUT, @RowCnt = @RowCount OUTPUT;
    
    SET @HTML = @HTML + N'
    <table>
        <tr>' + @Headers + '</tr>
        ' + ISNULL(@TableHTML, '') + '
    </table>';
    
    -- Add summary
    IF @IncludeSummary = 1
    BEGIN
        SET @HTML = @HTML + N'
    <div class="summary">
        <strong>Summary:</strong> ' + CAST(@RowCount AS NVARCHAR(20)) + ' rows returned
    </div>';
    END
    
    SET @HTML = @HTML + N'
</body>
</html>';
    
    SELECT @HTML AS HTMLReport;
END
GO

-- Generate cross-tab report
CREATE PROCEDURE dbo.GenerateCrossTabReport
    @TableName NVARCHAR(256),
    @RowField NVARCHAR(128),
    @ColumnField NVARCHAR(128),
    @ValueField NVARCHAR(128),
    @AggFunction NVARCHAR(10) = 'SUM'
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @Columns NVARCHAR(MAX);
    DECLARE @ColumnHeaders NVARCHAR(MAX);
    
    -- Get distinct column values
    SET @SQL = N'SELECT @ColList = STRING_AGG(QUOTENAME(CAST(' + QUOTENAME(@ColumnField) + ' AS NVARCHAR(128))), '','')
                FROM (SELECT DISTINCT ' + QUOTENAME(@ColumnField) + ' FROM ' + @TableName + ') AS DistinctCols';
    EXEC sp_executesql @SQL, N'@ColList NVARCHAR(MAX) OUTPUT', @ColList = @Columns OUTPUT;
    
    -- Build pivot query
    SET @SQL = N'
        SELECT ' + QUOTENAME(@RowField) + ', ' + @Columns + '
        FROM (
            SELECT ' + QUOTENAME(@RowField) + ', ' + QUOTENAME(@ColumnField) + ', ' + QUOTENAME(@ValueField) + '
            FROM ' + @TableName + '
        ) AS SourceData
        PIVOT (
            ' + @AggFunction + '(' + QUOTENAME(@ValueField) + ')
            FOR ' + QUOTENAME(@ColumnField) + ' IN (' + @Columns + ')
        ) AS PivotTable
        ORDER BY ' + QUOTENAME(@RowField);
    
    EXEC sp_executesql @SQL;
END
GO

-- Export to JSON with nested structure
CREATE PROCEDURE dbo.ExportToNestedJSON
    @ParentQuery NVARCHAR(MAX),
    @ChildQuery NVARCHAR(MAX),
    @ParentKeyColumn NVARCHAR(128),
    @ChildKeyColumn NVARCHAR(128),
    @ChildPropertyName NVARCHAR(128) = 'Children'
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    
    SET @SQL = N'
        SELECT 
            p.*,
            (SELECT * FROM (' + @ChildQuery + ') c 
             WHERE c.' + QUOTENAME(@ChildKeyColumn) + ' = p.' + QUOTENAME(@ParentKeyColumn) + '
             FOR JSON PATH) AS ' + QUOTENAME(@ChildPropertyName) + '
        FROM (' + @ParentQuery + ') p
        FOR JSON PATH';
    
    EXEC sp_executesql @SQL;
END
GO

-- Generate summary statistics report
CREATE PROCEDURE dbo.GenerateSummaryReport
    @TableName NVARCHAR(256),
    @GroupByColumn NVARCHAR(128) = NULL,
    @NumericColumns NVARCHAR(MAX) = NULL  -- Comma-separated
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @SelectCols NVARCHAR(MAX) = '';
    DECLARE @Col NVARCHAR(128);
    
    -- If no numeric columns specified, find them
    IF @NumericColumns IS NULL
    BEGIN
        SELECT @NumericColumns = STRING_AGG(c.name, ',')
        FROM sys.columns c
        INNER JOIN sys.types t ON c.user_type_id = t.user_type_id
        WHERE c.object_id = OBJECT_ID(@TableName)
          AND t.name IN ('int', 'bigint', 'smallint', 'tinyint', 'decimal', 'numeric', 'float', 'real', 'money');
    END
    
    -- Build aggregation columns
    SELECT @SelectCols = @SelectCols + 
        'COUNT(' + QUOTENAME(value) + ') AS [' + value + '_Count], ' +
        'SUM(CAST(' + QUOTENAME(value) + ' AS DECIMAL(18,2))) AS [' + value + '_Sum], ' +
        'AVG(CAST(' + QUOTENAME(value) + ' AS DECIMAL(18,2))) AS [' + value + '_Avg], ' +
        'MIN(' + QUOTENAME(value) + ') AS [' + value + '_Min], ' +
        'MAX(' + QUOTENAME(value) + ') AS [' + value + '_Max], '
    FROM STRING_SPLIT(@NumericColumns, ',');
    
    SET @SelectCols = LEFT(@SelectCols, LEN(@SelectCols) - 1);
    
    IF @GroupByColumn IS NOT NULL
    BEGIN
        SET @SQL = N'
            SELECT ' + QUOTENAME(@GroupByColumn) + ', ' + @SelectCols + '
            FROM ' + @TableName + '
            GROUP BY ' + QUOTENAME(@GroupByColumn) + '
            ORDER BY ' + QUOTENAME(@GroupByColumn);
    END
    ELSE
    BEGIN
        SET @SQL = N'
            SELECT ''Total'' AS Category, ' + @SelectCols + '
            FROM ' + @TableName;
    END
    
    EXEC sp_executesql @SQL;
END
GO
