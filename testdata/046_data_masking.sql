-- Sample 046: Data Masking and Anonymization
-- Source: Microsoft Learn, MSSQLTips, GDPR compliance patterns
-- Category: Security
-- Complexity: Advanced
-- Features: Dynamic data masking, custom masking functions, PII protection

-- Apply dynamic data masking to columns
CREATE PROCEDURE dbo.ApplyDynamicDataMasking
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @ColumnName NVARCHAR(128),
    @MaskingFunction NVARCHAR(50)  -- default(), email(), random(1,100), partial(1,'XXX',1)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FullPath NVARCHAR(256) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    
    SET @SQL = 'ALTER TABLE ' + @FullPath + '
        ALTER COLUMN ' + QUOTENAME(@ColumnName) + ' ADD MASKED WITH (FUNCTION = ''' + @MaskingFunction + ''')';
    
    BEGIN TRY
        EXEC sp_executesql @SQL;
        
        SELECT 
            'Dynamic masking applied' AS Status,
            @FullPath AS TableName,
            @ColumnName AS ColumnName,
            @MaskingFunction AS MaskingFunction;
    END TRY
    BEGIN CATCH
        SELECT 
            'Failed to apply masking' AS Status,
            ERROR_MESSAGE() AS ErrorMessage;
    END CATCH
END
GO

-- Remove dynamic data masking
CREATE PROCEDURE dbo.RemoveDynamicDataMasking
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @ColumnName NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FullPath NVARCHAR(256) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    
    SET @SQL = 'ALTER TABLE ' + @FullPath + '
        ALTER COLUMN ' + QUOTENAME(@ColumnName) + ' DROP MASKED';
    
    EXEC sp_executesql @SQL;
    
    SELECT 'Masking removed' AS Status, @ColumnName AS ColumnName;
END
GO

-- Custom masking functions
CREATE FUNCTION dbo.MaskEmail(@Email NVARCHAR(256))
RETURNS NVARCHAR(256)
AS
BEGIN
    IF @Email IS NULL OR CHARINDEX('@', @Email) = 0
        RETURN @Email;
    
    DECLARE @LocalPart NVARCHAR(128) = LEFT(@Email, CHARINDEX('@', @Email) - 1);
    DECLARE @Domain NVARCHAR(128) = SUBSTRING(@Email, CHARINDEX('@', @Email), LEN(@Email));
    
    RETURN LEFT(@LocalPart, 1) + REPLICATE('*', LEN(@LocalPart) - 1) + @Domain;
END
GO

CREATE FUNCTION dbo.MaskPhone(@Phone NVARCHAR(20))
RETURNS NVARCHAR(20)
AS
BEGIN
    IF @Phone IS NULL OR LEN(@Phone) < 4
        RETURN @Phone;
    
    -- Keep last 4 digits, mask rest
    RETURN REPLICATE('*', LEN(@Phone) - 4) + RIGHT(@Phone, 4);
END
GO

CREATE FUNCTION dbo.MaskSSN(@SSN NVARCHAR(11))
RETURNS NVARCHAR(11)
AS
BEGIN
    IF @SSN IS NULL OR LEN(@SSN) < 4
        RETURN @SSN;
    
    -- Show only last 4 digits: ***-**-1234
    RETURN '***-**-' + RIGHT(REPLACE(@SSN, '-', ''), 4);
END
GO

CREATE FUNCTION dbo.MaskCreditCard(@CardNumber NVARCHAR(20))
RETURNS NVARCHAR(20)
AS
BEGIN
    IF @CardNumber IS NULL OR LEN(@CardNumber) < 4
        RETURN @CardNumber;
    
    DECLARE @CleanNumber NVARCHAR(20) = REPLACE(REPLACE(@CardNumber, '-', ''), ' ', '');
    
    -- Show first 4 and last 4: 4111-****-****-1234
    IF LEN(@CleanNumber) >= 16
        RETURN LEFT(@CleanNumber, 4) + '-****-****-' + RIGHT(@CleanNumber, 4);
    
    RETURN REPLICATE('*', LEN(@CleanNumber) - 4) + RIGHT(@CleanNumber, 4);
END
GO

CREATE FUNCTION dbo.MaskName(@Name NVARCHAR(100))
RETURNS NVARCHAR(100)
AS
BEGIN
    IF @Name IS NULL OR LEN(@Name) < 2
        RETURN @Name;
    
    -- Show first letter only: J***
    RETURN LEFT(@Name, 1) + REPLICATE('*', LEN(@Name) - 1);
END
GO

-- Anonymize table data (for non-production copies)
CREATE PROCEDURE dbo.AnonymizeTableData
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @AnonymizationRules NVARCHAR(MAX)  -- JSON: [{"column":"Email","type":"email"},{"column":"Phone","type":"phone"}]
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX) = '';
    DECLARE @UpdateSet NVARCHAR(MAX) = '';
    DECLARE @FullPath NVARCHAR(256) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    
    -- Parse JSON rules and build update statement
    SELECT @UpdateSet = @UpdateSet + 
        QUOTENAME(JSON_VALUE(value, '$.column')) + ' = ' +
        CASE JSON_VALUE(value, '$.type')
            WHEN 'email' THEN 'dbo.MaskEmail(' + QUOTENAME(JSON_VALUE(value, '$.column')) + ')'
            WHEN 'phone' THEN 'dbo.MaskPhone(' + QUOTENAME(JSON_VALUE(value, '$.column')) + ')'
            WHEN 'ssn' THEN 'dbo.MaskSSN(' + QUOTENAME(JSON_VALUE(value, '$.column')) + ')'
            WHEN 'creditcard' THEN 'dbo.MaskCreditCard(' + QUOTENAME(JSON_VALUE(value, '$.column')) + ')'
            WHEN 'name' THEN 'dbo.MaskName(' + QUOTENAME(JSON_VALUE(value, '$.column')) + ')'
            WHEN 'null' THEN 'NULL'
            WHEN 'random_int' THEN 'ABS(CHECKSUM(NEWID())) % 1000000'
            WHEN 'random_date' THEN 'DATEADD(DAY, ABS(CHECKSUM(NEWID())) % 3650, ''2010-01-01'')'
            ELSE QUOTENAME(JSON_VALUE(value, '$.column'))
        END + ', '
    FROM OPENJSON(@AnonymizationRules);
    
    -- Remove trailing comma
    SET @UpdateSet = LEFT(@UpdateSet, LEN(@UpdateSet) - 1);
    
    IF LEN(@UpdateSet) > 0
    BEGIN
        SET @SQL = 'UPDATE ' + @FullPath + ' SET ' + @UpdateSet;
        
        BEGIN TRY
            EXEC sp_executesql @SQL;
            
            SELECT 
                'Anonymization completed' AS Status,
                @@ROWCOUNT AS RowsAffected,
                @FullPath AS TableName;
        END TRY
        BEGIN CATCH
            SELECT 
                'Anonymization failed' AS Status,
                ERROR_MESSAGE() AS ErrorMessage;
        END CATCH
    END
END
GO

-- Get masked column info
CREATE PROCEDURE dbo.GetMaskedColumns
    @SchemaName NVARCHAR(128) = NULL,
    @TableName NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        SCHEMA_NAME(t.schema_id) AS SchemaName,
        t.name AS TableName,
        c.name AS ColumnName,
        TYPE_NAME(c.user_type_id) AS DataType,
        c.is_masked AS IsMasked,
        mc.masking_function AS MaskingFunction
    FROM sys.columns c
    INNER JOIN sys.tables t ON c.object_id = t.object_id
    LEFT JOIN sys.masked_columns mc ON c.object_id = mc.object_id AND c.column_id = mc.column_id
    WHERE c.is_masked = 1
      AND (@SchemaName IS NULL OR SCHEMA_NAME(t.schema_id) = @SchemaName)
      AND (@TableName IS NULL OR t.name = @TableName)
    ORDER BY t.name, c.column_id;
    
    -- Summary
    SELECT 
        COUNT(DISTINCT t.object_id) AS TablesWithMasking,
        COUNT(*) AS MaskedColumnCount
    FROM sys.columns c
    INNER JOIN sys.tables t ON c.object_id = t.object_id
    WHERE c.is_masked = 1;
END
GO

-- Generate anonymization report
CREATE PROCEDURE dbo.GeneratePIIReport
    @SchemaName NVARCHAR(128) = 'dbo'
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Identify potential PII columns by name patterns
    SELECT 
        SCHEMA_NAME(t.schema_id) AS SchemaName,
        t.name AS TableName,
        c.name AS ColumnName,
        TYPE_NAME(c.user_type_id) AS DataType,
        c.is_masked AS CurrentlyMasked,
        CASE 
            WHEN c.name LIKE '%email%' THEN 'Email'
            WHEN c.name LIKE '%phone%' OR c.name LIKE '%mobile%' OR c.name LIKE '%fax%' THEN 'Phone'
            WHEN c.name LIKE '%ssn%' OR c.name LIKE '%social%security%' THEN 'SSN'
            WHEN c.name LIKE '%credit%card%' OR c.name LIKE '%card%number%' THEN 'Credit Card'
            WHEN c.name LIKE '%first%name%' OR c.name LIKE '%last%name%' OR c.name LIKE '%surname%' THEN 'Name'
            WHEN c.name LIKE '%address%' OR c.name LIKE '%street%' THEN 'Address'
            WHEN c.name LIKE '%birth%' OR c.name LIKE '%dob%' THEN 'Date of Birth'
            WHEN c.name LIKE '%password%' OR c.name LIKE '%pwd%' THEN 'Password'
            WHEN c.name LIKE '%salary%' OR c.name LIKE '%income%' THEN 'Financial'
            ELSE 'Review Manually'
        END AS PIIType,
        CASE 
            WHEN c.name LIKE '%email%' THEN 'email()'
            WHEN c.name LIKE '%phone%' THEN 'default()'
            WHEN c.name LIKE '%ssn%' THEN 'partial(0,''XXX-XX-'',4)'
            WHEN c.name LIKE '%credit%card%' THEN 'partial(4,''XXXX-XXXX-XXXX-'',4)'
            WHEN c.name LIKE '%name%' THEN 'partial(1,''XXX'',0)'
            ELSE 'default()'
        END AS SuggestedMask
    FROM sys.columns c
    INNER JOIN sys.tables t ON c.object_id = t.object_id
    WHERE SCHEMA_NAME(t.schema_id) = @SchemaName
      AND t.type = 'U'
      AND (
          c.name LIKE '%email%' OR
          c.name LIKE '%phone%' OR c.name LIKE '%mobile%' OR
          c.name LIKE '%ssn%' OR c.name LIKE '%social%' OR
          c.name LIKE '%credit%' OR c.name LIKE '%card%' OR
          c.name LIKE '%name%' OR c.name LIKE '%surname%' OR
          c.name LIKE '%address%' OR c.name LIKE '%street%' OR
          c.name LIKE '%birth%' OR c.name LIKE '%dob%' OR
          c.name LIKE '%password%' OR c.name LIKE '%pwd%' OR
          c.name LIKE '%salary%' OR c.name LIKE '%income%'
      )
    ORDER BY t.name, c.column_id;
END
GO
