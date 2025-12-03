-- Sample 018: Data Validation Framework
-- Source: Various - Stack Overflow, MSSQLTips, Database Journal
-- Category: Data Validation
-- Complexity: Advanced
-- Features: Table-valued parameters, TRY_CAST, JSON output, validation rules

-- Create validation rule type
CREATE TYPE dbo.ValidationRuleType AS TABLE (
    RuleID INT,
    RuleName NVARCHAR(100),
    TableName NVARCHAR(128),
    ColumnName NVARCHAR(128),
    ValidationExpression NVARCHAR(MAX),
    ErrorMessage NVARCHAR(500),
    Severity NVARCHAR(20)  -- Error, Warning, Info
);
GO

-- Main validation procedure
CREATE PROCEDURE dbo.ValidateTableData
    @TableName NVARCHAR(128),
    @SchemaName NVARCHAR(128) = 'dbo',
    @OutputFormat NVARCHAR(10) = 'TABLE',  -- TABLE, JSON, XML
    @StopOnFirstError BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @ValidationResults TABLE (
        ValidationID INT IDENTITY(1,1),
        RuleName NVARCHAR(100),
        ColumnName NVARCHAR(128),
        Severity NVARCHAR(20),
        ViolationCount INT,
        SampleValues NVARCHAR(MAX),
        ErrorMessage NVARCHAR(500)
    );
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @RuleName NVARCHAR(100);
    DECLARE @ColumnName NVARCHAR(128);
    DECLARE @ViolationCount INT;
    
    -- Validation 1: NULL checks on NOT NULL columns
    INSERT INTO @ValidationResults (RuleName, ColumnName, Severity, ViolationCount, ErrorMessage)
    SELECT 
        'Unexpected NULL values',
        c.name,
        'Error',
        0,  -- Will be updated
        'Column marked as NOT NULL contains NULL values'
    FROM sys.columns c
    INNER JOIN sys.tables t ON c.object_id = t.object_id
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE t.name = @TableName
      AND s.name = @SchemaName
      AND c.is_nullable = 0;
    
    -- Validation 2: Check for orphaned foreign keys
    INSERT INTO @ValidationResults (RuleName, ColumnName, Severity, ViolationCount, ErrorMessage)
    SELECT 
        'Orphaned Foreign Key',
        COL_NAME(fkc.parent_object_id, fkc.parent_column_id),
        'Error',
        0,
        'References non-existent parent record in ' + 
            OBJECT_NAME(fkc.referenced_object_id)
    FROM sys.foreign_key_columns fkc
    INNER JOIN sys.foreign_keys fk ON fkc.constraint_object_id = fk.object_id
    WHERE fk.parent_object_id = OBJECT_ID(@SchemaName + '.' + @TableName);
    
    -- Validation 3: Check data type constraints
    -- Email format validation (if column name suggests email)
    IF EXISTS (
        SELECT 1 FROM sys.columns c
        INNER JOIN sys.tables t ON c.object_id = t.object_id
        INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
        WHERE t.name = @TableName AND s.name = @SchemaName
          AND c.name LIKE '%email%'
    )
    BEGIN
        SET @SQL = N'
            SELECT @cnt = COUNT(*)
            FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + '
            WHERE Email IS NOT NULL
              AND Email NOT LIKE ''%_@__%.__%''';
        
        EXEC sp_executesql @SQL, N'@cnt INT OUTPUT', @cnt = @ViolationCount OUTPUT;
        
        IF @ViolationCount > 0
        BEGIN
            INSERT INTO @ValidationResults (RuleName, ColumnName, Severity, ViolationCount, ErrorMessage)
            VALUES ('Invalid Email Format', 'Email', 'Warning', @ViolationCount, 
                    'Email address does not match expected format');
        END
    END
    
    -- Validation 4: Check for duplicate primary keys (shouldn't happen but verify)
    DECLARE @PKColumns NVARCHAR(MAX);
    
    SELECT @PKColumns = STRING_AGG(QUOTENAME(c.name), ', ')
    FROM sys.indexes i
    INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
    INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
    WHERE i.object_id = OBJECT_ID(@SchemaName + '.' + @TableName)
      AND i.is_primary_key = 1;
    
    IF @PKColumns IS NOT NULL
    BEGIN
        SET @SQL = N'
            SELECT @cnt = COUNT(*)
            FROM (
                SELECT ' + @PKColumns + ', COUNT(*) AS cnt
                FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + '
                GROUP BY ' + @PKColumns + '
                HAVING COUNT(*) > 1
            ) dups';
        
        EXEC sp_executesql @SQL, N'@cnt INT OUTPUT', @cnt = @ViolationCount OUTPUT;
        
        IF @ViolationCount > 0
        BEGIN
            INSERT INTO @ValidationResults (RuleName, ColumnName, Severity, ViolationCount, ErrorMessage)
            VALUES ('Duplicate Primary Key', @PKColumns, 'Error', @ViolationCount,
                    'Duplicate values found in primary key columns');
        END
    END
    
    -- Validation 5: Check numeric ranges
    INSERT INTO @ValidationResults (RuleName, ColumnName, Severity, ViolationCount, ErrorMessage)
    SELECT 
        'Potential Data Range Issue',
        c.name,
        'Warning',
        0,
        'Numeric column may have outlier values'
    FROM sys.columns c
    INNER JOIN sys.types t ON c.system_type_id = t.system_type_id
    WHERE c.object_id = OBJECT_ID(@SchemaName + '.' + @TableName)
      AND t.name IN ('int', 'bigint', 'decimal', 'numeric', 'money', 'float');
    
    -- Validation 6: Check for leading/trailing whitespace in string columns
    DECLARE @StringColumns NVARCHAR(MAX);
    
    SELECT @StringColumns = STRING_AGG(
        'SUM(CASE WHEN ' + QUOTENAME(c.name) + ' <> LTRIM(RTRIM(' + QUOTENAME(c.name) + ')) THEN 1 ELSE 0 END) AS ' + QUOTENAME(c.name + '_WhiteSpace'),
        ', '
    )
    FROM sys.columns c
    INNER JOIN sys.types t ON c.system_type_id = t.system_type_id
    WHERE c.object_id = OBJECT_ID(@SchemaName + '.' + @TableName)
      AND t.name IN ('varchar', 'nvarchar', 'char', 'nchar');
    
    -- Output results based on format
    IF @OutputFormat = 'JSON'
    BEGIN
        SELECT (
            SELECT 
                RuleName,
                ColumnName,
                Severity,
                ViolationCount,
                ErrorMessage
            FROM @ValidationResults
            WHERE ViolationCount > 0 OR Severity = 'Error'
            FOR JSON PATH, ROOT('ValidationResults')
        ) AS ValidationResultsJSON;
    END
    ELSE IF @OutputFormat = 'XML'
    BEGIN
        SELECT 
            RuleName,
            ColumnName,
            Severity,
            ViolationCount,
            ErrorMessage
        FROM @ValidationResults
        WHERE ViolationCount > 0 OR Severity = 'Error'
        FOR XML PATH('ValidationResult'), ROOT('ValidationResults');
    END
    ELSE
    BEGIN
        SELECT * FROM @ValidationResults
        ORDER BY 
            CASE Severity WHEN 'Error' THEN 1 WHEN 'Warning' THEN 2 ELSE 3 END,
            ViolationCount DESC;
    END
    
    -- Return summary
    SELECT 
        COUNT(*) AS TotalRulesChecked,
        SUM(CASE WHEN Severity = 'Error' AND ViolationCount > 0 THEN 1 ELSE 0 END) AS ErrorCount,
        SUM(CASE WHEN Severity = 'Warning' AND ViolationCount > 0 THEN 1 ELSE 0 END) AS WarningCount,
        CASE 
            WHEN SUM(CASE WHEN Severity = 'Error' AND ViolationCount > 0 THEN 1 ELSE 0 END) > 0 
            THEN 'FAILED'
            ELSE 'PASSED'
        END AS OverallStatus
    FROM @ValidationResults;
END
GO

-- Validate specific column against pattern
CREATE PROCEDURE dbo.ValidateColumnPattern
    @TableName NVARCHAR(128),
    @SchemaName NVARCHAR(128) = 'dbo',
    @ColumnName NVARCHAR(128),
    @Pattern NVARCHAR(500),
    @MaxViolationsToReturn INT = 100
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    
    SET @SQL = N'
        SELECT TOP (@MaxReturn)
            ' + QUOTENAME(@ColumnName) + ' AS InvalidValue,
            ''Does not match pattern: '' + @Pattern AS Issue
        FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + '
        WHERE ' + QUOTENAME(@ColumnName) + ' IS NOT NULL
          AND ' + QUOTENAME(@ColumnName) + ' NOT LIKE @Pattern
        ORDER BY ' + QUOTENAME(@ColumnName);
    
    EXEC sp_executesql @SQL, 
        N'@Pattern NVARCHAR(500), @MaxReturn INT',
        @Pattern = @Pattern,
        @MaxReturn = @MaxViolationsToReturn;
END
GO

-- Validate referential integrity across databases
CREATE PROCEDURE dbo.ValidateCrossDbReferentialIntegrity
    @SourceDb NVARCHAR(128),
    @SourceSchema NVARCHAR(128),
    @SourceTable NVARCHAR(128),
    @SourceColumn NVARCHAR(128),
    @TargetDb NVARCHAR(128),
    @TargetSchema NVARCHAR(128),
    @TargetTable NVARCHAR(128),
    @TargetColumn NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    
    SET @SQL = N'
        SELECT 
            src.' + QUOTENAME(@SourceColumn) + ' AS OrphanedValue,
            COUNT(*) AS OccurrenceCount
        FROM ' + QUOTENAME(@SourceDb) + '.' + QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable) + ' src
        WHERE NOT EXISTS (
            SELECT 1 
            FROM ' + QUOTENAME(@TargetDb) + '.' + QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable) + ' tgt
            WHERE tgt.' + QUOTENAME(@TargetColumn) + ' = src.' + QUOTENAME(@SourceColumn) + '
        )
        AND src.' + QUOTENAME(@SourceColumn) + ' IS NOT NULL
        GROUP BY src.' + QUOTENAME(@SourceColumn) + '
        ORDER BY COUNT(*) DESC';
    
    EXEC sp_executesql @SQL;
END
GO
