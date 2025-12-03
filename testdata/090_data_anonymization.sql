-- Sample 090: Data Anonymization and Pseudonymization
-- Source: Various - GDPR patterns, Privacy engineering, MSSQLTips
-- Category: Security
-- Complexity: Advanced
-- Features: Data anonymization, pseudonymization, k-anonymity, data masking

-- Setup anonymization rules table
CREATE PROCEDURE dbo.SetupAnonymizationRules
AS
BEGIN
    SET NOCOUNT ON;
    
    IF OBJECT_ID('dbo.AnonymizationRules', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.AnonymizationRules (
            RuleID INT IDENTITY(1,1) PRIMARY KEY,
            RuleName NVARCHAR(100) NOT NULL,
            SchemaName NVARCHAR(128),
            TableName NVARCHAR(128),
            ColumnName NVARCHAR(128),
            AnonymizationType NVARCHAR(50),  -- MASK, HASH, GENERALIZE, SUPPRESS, PSEUDONYMIZE
            MaskPattern NVARCHAR(100),
            PreserveLength BIT DEFAULT 1,
            PreserveFormat BIT DEFAULT 0,
            IsActive BIT DEFAULT 1,
            CreatedDate DATETIME2 DEFAULT SYSDATETIME()
        );
    END
    
    -- Pseudonymization mapping table
    IF OBJECT_ID('dbo.PseudonymMapping', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.PseudonymMapping (
            MappingID BIGINT IDENTITY(1,1) PRIMARY KEY,
            OriginalValueHash VARBINARY(64) NOT NULL,
            Pseudonym NVARCHAR(200) NOT NULL,
            DataCategory NVARCHAR(50),
            CreatedDate DATETIME2 DEFAULT SYSDATETIME(),
            UNIQUE (OriginalValueHash, DataCategory)
        );
    END
    
    SELECT 'Anonymization infrastructure created' AS Status;
END
GO

-- Anonymize text with masking
CREATE FUNCTION dbo.AnonymizeText
(
    @Value NVARCHAR(MAX),
    @MaskType NVARCHAR(20),  -- EMAIL, PHONE, NAME, PARTIAL, FULL
    @PreserveLength BIT = 1
)
RETURNS NVARCHAR(MAX)
AS
BEGIN
    DECLARE @Result NVARCHAR(MAX);
    DECLARE @Len INT = LEN(@Value);
    
    IF @Value IS NULL RETURN NULL;
    
    IF @MaskType = 'EMAIL'
    BEGIN
        -- Mask email: j***@***.com
        DECLARE @AtPos INT = CHARINDEX('@', @Value);
        DECLARE @DotPos INT = LEN(@Value) - CHARINDEX('.', REVERSE(@Value)) + 1;
        IF @AtPos > 1 AND @DotPos > @AtPos
            SET @Result = LEFT(@Value, 1) + REPLICATE('*', @AtPos - 2) + '@' + 
                          REPLICATE('*', @DotPos - @AtPos - 1) + SUBSTRING(@Value, @DotPos, 100);
        ELSE
            SET @Result = REPLICATE('*', @Len);
    END
    ELSE IF @MaskType = 'PHONE'
    BEGIN
        -- Show last 4 digits only
        SET @Result = REPLICATE('*', @Len - 4) + RIGHT(@Value, 4);
    END
    ELSE IF @MaskType = 'NAME'
    BEGIN
        -- Show first initial only
        SET @Result = LEFT(@Value, 1) + REPLICATE('*', @Len - 1);
    END
    ELSE IF @MaskType = 'PARTIAL'
    BEGIN
        -- Show first and last characters
        IF @Len > 2
            SET @Result = LEFT(@Value, 1) + REPLICATE('*', @Len - 2) + RIGHT(@Value, 1);
        ELSE
            SET @Result = REPLICATE('*', @Len);
    END
    ELSE  -- FULL
    BEGIN
        SET @Result = CASE WHEN @PreserveLength = 1 THEN REPLICATE('*', @Len) ELSE '***' END;
    END
    
    RETURN @Result;
END
GO

-- Generate pseudonym
CREATE FUNCTION dbo.GeneratePseudonym
(
    @OriginalValue NVARCHAR(MAX),
    @Category NVARCHAR(50) = 'DEFAULT'
)
RETURNS NVARCHAR(200)
AS
BEGIN
    DECLARE @Hash VARBINARY(64) = HASHBYTES('SHA2_256', @OriginalValue);
    DECLARE @Pseudonym NVARCHAR(200);
    
    -- Check if pseudonym already exists
    SELECT @Pseudonym = Pseudonym
    FROM dbo.PseudonymMapping
    WHERE OriginalValueHash = @Hash AND DataCategory = @Category;
    
    -- If not found, this function returns NULL - caller should create mapping
    RETURN @Pseudonym;
END
GO

-- Create or get pseudonym
CREATE PROCEDURE dbo.GetOrCreatePseudonym
    @OriginalValue NVARCHAR(MAX),
    @Category NVARCHAR(50) = 'DEFAULT',
    @Pseudonym NVARCHAR(200) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @Hash VARBINARY(64) = HASHBYTES('SHA2_256', @OriginalValue);
    
    -- Try to get existing
    SELECT @Pseudonym = Pseudonym
    FROM dbo.PseudonymMapping
    WHERE OriginalValueHash = @Hash AND DataCategory = @Category;
    
    -- Create new if not found
    IF @Pseudonym IS NULL
    BEGIN
        SET @Pseudonym = @Category + '_' + CAST(NEXT VALUE FOR dbo.PseudonymSequence AS NVARCHAR(20));
        
        INSERT INTO dbo.PseudonymMapping (OriginalValueHash, Pseudonym, DataCategory)
        VALUES (@Hash, @Pseudonym, @Category);
    END
END
GO

-- Anonymize table data
CREATE PROCEDURE dbo.AnonymizeTableData
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @TargetSchema NVARCHAR(128) = NULL,
    @TargetTable NVARCHAR(128) = NULL,
    @WhatIf BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    SET @TargetSchema = ISNULL(@TargetSchema, @SchemaName);
    SET @TargetTable = ISNULL(@TargetTable, @TableName + '_Anonymized');
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @SelectColumns NVARCHAR(MAX) = '';
    DECLARE @FullSource NVARCHAR(256) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    DECLARE @FullTarget NVARCHAR(256) = QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable);
    
    -- Build column list with anonymization
    SELECT @SelectColumns = @SelectColumns +
        CASE 
            WHEN ar.AnonymizationType = 'MASK' THEN
                'dbo.AnonymizeText(' + QUOTENAME(c.name) + ', ''' + ISNULL(ar.MaskPattern, 'FULL') + ''', 1) AS ' + QUOTENAME(c.name)
            WHEN ar.AnonymizationType = 'HASH' THEN
                'CONVERT(NVARCHAR(64), HASHBYTES(''SHA2_256'', ' + QUOTENAME(c.name) + '), 2) AS ' + QUOTENAME(c.name)
            WHEN ar.AnonymizationType = 'SUPPRESS' THEN
                'NULL AS ' + QUOTENAME(c.name)
            WHEN ar.AnonymizationType = 'GENERALIZE' THEN
                CASE 
                    WHEN TYPE_NAME(c.user_type_id) IN ('date', 'datetime', 'datetime2') 
                    THEN 'DATEFROMPARTS(YEAR(' + QUOTENAME(c.name) + '), 1, 1) AS ' + QUOTENAME(c.name)
                    WHEN TYPE_NAME(c.user_type_id) IN ('int', 'bigint', 'decimal', 'numeric')
                    THEN 'FLOOR(' + QUOTENAME(c.name) + ' / 10) * 10 AS ' + QUOTENAME(c.name)
                    ELSE QUOTENAME(c.name)
                END
            ELSE QUOTENAME(c.name)
        END + ', '
    FROM sys.columns c
    LEFT JOIN dbo.AnonymizationRules ar ON ar.SchemaName = @SchemaName 
                                        AND ar.TableName = @TableName 
                                        AND ar.ColumnName = c.name
                                        AND ar.IsActive = 1
    WHERE c.object_id = OBJECT_ID(@FullSource)
    ORDER BY c.column_id;
    
    SET @SelectColumns = LEFT(@SelectColumns, LEN(@SelectColumns) - 1);
    
    IF @WhatIf = 1
    BEGIN
        SET @SQL = 'SELECT TOP 10 ' + @SelectColumns + ' FROM ' + @FullSource;
        SELECT 'Preview of anonymized data (first 10 rows):' AS Info;
        EXEC sp_executesql @SQL;
        
        SELECT 'WhatIf mode - no table created. Set @WhatIf = 0 to create anonymized table.' AS Status;
    END
    ELSE
    BEGIN
        SET @SQL = 'SELECT ' + @SelectColumns + ' INTO ' + @FullTarget + ' FROM ' + @FullSource;
        EXEC sp_executesql @SQL;
        
        SELECT 'Anonymized table created: ' + @FullTarget AS Status, @@ROWCOUNT AS RowsCreated;
    END
END
GO

-- Check k-anonymity
CREATE PROCEDURE dbo.CheckKAnonymity
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @QuasiIdentifiers NVARCHAR(MAX),  -- Comma-separated columns
    @K INT = 5
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FullPath NVARCHAR(256) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    
    -- Find groups smaller than K
    SET @SQL = N'
        SELECT 
            ' + @QuasiIdentifiers + ',
            COUNT(*) AS GroupSize,
            CASE WHEN COUNT(*) < @KValue THEN ''FAILS K-Anonymity'' ELSE ''OK'' END AS Status
        FROM ' + @FullPath + '
        GROUP BY ' + @QuasiIdentifiers + '
        HAVING COUNT(*) < @KValue
        ORDER BY GroupSize';
    
    SELECT 'Groups failing ' + CAST(@K AS VARCHAR(10)) + '-anonymity:' AS Analysis;
    EXEC sp_executesql @SQL, N'@KValue INT', @KValue = @K;
    
    -- Overall statistics
    SET @SQL = N'
        SELECT 
            COUNT(*) AS TotalGroups,
            SUM(CASE WHEN GroupSize < @KValue THEN 1 ELSE 0 END) AS FailingGroups,
            MIN(GroupSize) AS MinGroupSize,
            AVG(GroupSize) AS AvgGroupSize,
            MAX(GroupSize) AS MaxGroupSize
        FROM (
            SELECT COUNT(*) AS GroupSize
            FROM ' + @FullPath + '
            GROUP BY ' + @QuasiIdentifiers + '
        ) AS Groups';
    
    EXEC sp_executesql @SQL, N'@KValue INT', @KValue = @K;
END
GO

-- Generate data anonymization report
CREATE PROCEDURE dbo.GenerateAnonymizationReport
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Rules summary
    SELECT 
        SchemaName,
        TableName,
        COUNT(*) AS ColumnsWithRules,
        SUM(CASE WHEN AnonymizationType = 'MASK' THEN 1 ELSE 0 END) AS MaskedColumns,
        SUM(CASE WHEN AnonymizationType = 'HASH' THEN 1 ELSE 0 END) AS HashedColumns,
        SUM(CASE WHEN AnonymizationType = 'SUPPRESS' THEN 1 ELSE 0 END) AS SuppressedColumns,
        SUM(CASE WHEN AnonymizationType = 'GENERALIZE' THEN 1 ELSE 0 END) AS GeneralizedColumns,
        SUM(CASE WHEN AnonymizationType = 'PSEUDONYMIZE' THEN 1 ELSE 0 END) AS PseudonymizedColumns
    FROM dbo.AnonymizationRules
    WHERE IsActive = 1
    GROUP BY SchemaName, TableName;
    
    -- Pseudonym statistics
    SELECT 
        DataCategory,
        COUNT(*) AS MappingCount,
        MIN(CreatedDate) AS FirstCreated,
        MAX(CreatedDate) AS LastCreated
    FROM dbo.PseudonymMapping
    GROUP BY DataCategory;
END
GO
