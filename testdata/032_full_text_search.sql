-- Sample 032: Full-Text Search Procedures
-- Source: Microsoft Learn, MSSQLTips, SQLShack
-- Category: Performance
-- Complexity: Advanced
-- Features: CONTAINS, FREETEXT, CONTAINSTABLE, FREETEXTTABLE, full-text catalogs

-- Setup full-text search on a table
CREATE PROCEDURE dbo.SetupFullTextSearch
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @CatalogName NVARCHAR(128) = NULL,
    @KeyIndexName NVARCHAR(128) = NULL,
    @Columns NVARCHAR(MAX),  -- Comma-separated column names
    @Language NVARCHAR(50) = 'English'
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FullTableName NVARCHAR(256) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    
    SET @CatalogName = ISNULL(@CatalogName, @TableName + '_FTCatalog');
    
    -- Get primary key index if not specified
    IF @KeyIndexName IS NULL
    BEGIN
        SELECT @KeyIndexName = i.name
        FROM sys.indexes i
        WHERE i.object_id = OBJECT_ID(@FullTableName)
          AND i.is_primary_key = 1;
    END
    
    IF @KeyIndexName IS NULL
    BEGIN
        RAISERROR('No primary key found. Full-text search requires a unique index.', 16, 1);
        RETURN;
    END
    
    BEGIN TRY
        -- Create catalog if not exists
        IF NOT EXISTS (SELECT 1 FROM sys.fulltext_catalogs WHERE name = @CatalogName)
        BEGIN
            SET @SQL = 'CREATE FULLTEXT CATALOG ' + QUOTENAME(@CatalogName) + ' AS DEFAULT';
            EXEC sp_executesql @SQL;
            PRINT 'Created full-text catalog: ' + @CatalogName;
        END
        
        -- Drop existing full-text index
        IF EXISTS (
            SELECT 1 FROM sys.fulltext_indexes 
            WHERE object_id = OBJECT_ID(@FullTableName)
        )
        BEGIN
            SET @SQL = 'DROP FULLTEXT INDEX ON ' + @FullTableName;
            EXEC sp_executesql @SQL;
            PRINT 'Dropped existing full-text index';
        END
        
        -- Build column list with language
        DECLARE @ColumnList NVARCHAR(MAX) = '';
        SELECT @ColumnList = @ColumnList + QUOTENAME(LTRIM(RTRIM(value))) + ' LANGUAGE ''' + @Language + ''', '
        FROM STRING_SPLIT(@Columns, ',');
        SET @ColumnList = LEFT(@ColumnList, LEN(@ColumnList) - 1);
        
        -- Create full-text index
        SET @SQL = 'CREATE FULLTEXT INDEX ON ' + @FullTableName + '(' + @ColumnList + ')
            KEY INDEX ' + QUOTENAME(@KeyIndexName) + '
            ON ' + QUOTENAME(@CatalogName) + '
            WITH CHANGE_TRACKING AUTO';
        
        EXEC sp_executesql @SQL;
        PRINT 'Created full-text index on ' + @FullTableName;
        
        -- Return status
        SELECT 
            @CatalogName AS CatalogName,
            @FullTableName AS TableName,
            @KeyIndexName AS KeyIndex,
            @Columns AS IndexedColumns,
            'Full-text search enabled' AS Status;
            
    END TRY
    BEGIN CATCH
        SELECT 
            ERROR_MESSAGE() AS ErrorMessage,
            'Setup failed' AS Status;
        THROW;
    END CATCH
END
GO

-- Search using CONTAINS
CREATE PROCEDURE dbo.SearchWithContains
    @TableName NVARCHAR(128),
    @SchemaName NVARCHAR(128) = 'dbo',
    @SearchColumn NVARCHAR(128),
    @SearchTerm NVARCHAR(500),
    @SearchType NVARCHAR(20) = 'SIMPLE',  -- SIMPLE, PHRASE, PREFIX, PROXIMITY, INFLECTIONAL, THESAURUS
    @TopN INT = 100
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @ContainsClause NVARCHAR(MAX);
    
    -- Build CONTAINS clause based on search type
    SET @ContainsClause = CASE @SearchType
        WHEN 'SIMPLE' THEN '''' + REPLACE(@SearchTerm, '''', '''''') + ''''
        WHEN 'PHRASE' THEN '"' + @SearchTerm + '"'
        WHEN 'PREFIX' THEN '"' + @SearchTerm + '*"'
        WHEN 'INFLECTIONAL' THEN 'FORMSOF(INFLECTIONAL, ' + @SearchTerm + ')'
        WHEN 'THESAURUS' THEN 'FORMSOF(THESAURUS, ' + @SearchTerm + ')'
        WHEN 'PROXIMITY' THEN @SearchTerm  -- Assumes user provides NEAR clause
        ELSE '''' + REPLACE(@SearchTerm, '''', '''''') + ''''
    END;
    
    SET @SQL = N'
        SELECT TOP (@TopN) *
        FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + '
        WHERE CONTAINS(' + QUOTENAME(@SearchColumn) + ', @ContainsClause)';
    
    EXEC sp_executesql @SQL,
        N'@TopN INT, @ContainsClause NVARCHAR(MAX)',
        @TopN = @TopN,
        @ContainsClause = @ContainsClause;
END
GO

-- Search using CONTAINSTABLE with ranking
CREATE PROCEDURE dbo.SearchWithRanking
    @TableName NVARCHAR(128),
    @SchemaName NVARCHAR(128) = 'dbo',
    @SearchColumns NVARCHAR(500),  -- Comma-separated or *
    @SearchTerm NVARCHAR(500),
    @TopN INT = 100,
    @MinRank INT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @KeyColumn NVARCHAR(128);
    
    -- Get primary key column
    SELECT @KeyColumn = c.name
    FROM sys.indexes i
    INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
    INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
    WHERE i.object_id = OBJECT_ID(@SchemaName + '.' + @TableName)
      AND i.is_primary_key = 1;
    
    SET @SQL = N'
        SELECT TOP (@TopN)
            ft.[KEY] AS MatchedKey,
            ft.[RANK] AS SearchRank,
            t.*
        FROM CONTAINSTABLE(' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + ', 
            ' + CASE WHEN @SearchColumns = '*' THEN '*' ELSE '(' + @SearchColumns + ')' END + ',
            @SearchTerm, @TopN) AS ft
        INNER JOIN ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + ' t
            ON ft.[KEY] = t.' + QUOTENAME(@KeyColumn) + '
        WHERE ft.[RANK] >= @MinRank
        ORDER BY ft.[RANK] DESC';
    
    EXEC sp_executesql @SQL,
        N'@SearchTerm NVARCHAR(500), @TopN INT, @MinRank INT',
        @SearchTerm = @SearchTerm,
        @TopN = @TopN,
        @MinRank = @MinRank;
END
GO

-- Natural language search using FREETEXT
CREATE PROCEDURE dbo.NaturalLanguageSearch
    @TableName NVARCHAR(128),
    @SchemaName NVARCHAR(128) = 'dbo',
    @SearchColumns NVARCHAR(500) = '*',
    @SearchPhrase NVARCHAR(500),
    @TopN INT = 100
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @KeyColumn NVARCHAR(128);
    
    -- Get primary key column
    SELECT @KeyColumn = c.name
    FROM sys.indexes i
    INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
    INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
    WHERE i.object_id = OBJECT_ID(@SchemaName + '.' + @TableName)
      AND i.is_primary_key = 1;
    
    -- Using FREETEXTTABLE for ranking
    SET @SQL = N'
        SELECT TOP (@TopN)
            ft.[KEY] AS MatchedKey,
            ft.[RANK] AS RelevanceScore,
            t.*
        FROM FREETEXTTABLE(' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + ',
            ' + CASE WHEN @SearchColumns = '*' THEN '*' ELSE '(' + @SearchColumns + ')' END + ',
            @SearchPhrase, @TopN) AS ft
        INNER JOIN ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + ' t
            ON ft.[KEY] = t.' + QUOTENAME(@KeyColumn) + '
        ORDER BY ft.[RANK] DESC';
    
    EXEC sp_executesql @SQL,
        N'@SearchPhrase NVARCHAR(500), @TopN INT',
        @SearchPhrase = @SearchPhrase,
        @TopN = @TopN;
END
GO

-- Get full-text index status
CREATE PROCEDURE dbo.GetFullTextStatus
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Catalog status
    SELECT 
        c.name AS CatalogName,
        c.fulltext_catalog_id AS CatalogID,
        FULLTEXTCATALOGPROPERTY(c.name, 'IndexSize') AS IndexSizeMB,
        FULLTEXTCATALOGPROPERTY(c.name, 'ItemCount') AS ItemCount,
        CASE FULLTEXTCATALOGPROPERTY(c.name, 'PopulateStatus')
            WHEN 0 THEN 'Idle'
            WHEN 1 THEN 'Full population in progress'
            WHEN 2 THEN 'Paused'
            WHEN 3 THEN 'Throttled'
            WHEN 4 THEN 'Recovering'
            WHEN 5 THEN 'Shutdown'
            WHEN 6 THEN 'Incremental population in progress'
            WHEN 7 THEN 'Building index'
            WHEN 8 THEN 'Disk is full. Paused.'
            WHEN 9 THEN 'Change tracking'
        END AS PopulateStatus,
        c.is_default AS IsDefault
    FROM sys.fulltext_catalogs c;
    
    -- Index details
    SELECT 
        OBJECT_SCHEMA_NAME(fi.object_id) AS SchemaName,
        OBJECT_NAME(fi.object_id) AS TableName,
        c.name AS CatalogName,
        i.name AS UniqueIndexName,
        fi.is_enabled AS IsEnabled,
        CASE fi.change_tracking_state
            WHEN 'M' THEN 'Manual'
            WHEN 'A' THEN 'Auto'
            WHEN 'O' THEN 'Off'
        END AS ChangeTracking,
        OBJECTPROPERTYEX(fi.object_id, 'TableFullTextPendingChanges') AS PendingChanges,
        fi.crawl_start_date AS LastCrawlStart,
        fi.crawl_end_date AS LastCrawlEnd,
        CASE fi.crawl_type
            WHEN 0 THEN 'Full'
            WHEN 1 THEN 'Incremental'
            WHEN 2 THEN 'Update'
        END AS LastCrawlType
    FROM sys.fulltext_indexes fi
    INNER JOIN sys.fulltext_catalogs c ON fi.fulltext_catalog_id = c.fulltext_catalog_id
    INNER JOIN sys.indexes i ON fi.unique_index_id = i.index_id AND fi.object_id = i.object_id;
    
    -- Indexed columns
    SELECT 
        OBJECT_SCHEMA_NAME(fic.object_id) AS SchemaName,
        OBJECT_NAME(fic.object_id) AS TableName,
        c.name AS ColumnName,
        fic.language_id AS LanguageID,
        l.name AS LanguageName
    FROM sys.fulltext_index_columns fic
    INNER JOIN sys.columns c ON fic.object_id = c.object_id AND fic.column_id = c.column_id
    LEFT JOIN sys.fulltext_languages l ON fic.language_id = l.lcid
    ORDER BY OBJECT_NAME(fic.object_id), c.name;
END
GO
