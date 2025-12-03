-- Sample 051: Advanced XML Operations
-- Source: Microsoft Learn, MSSQLTips, SQLShack
-- Category: XML/JSON Processing
-- Complexity: Advanced
-- Features: FOR XML, OPENXML, XQuery, XML indexes, XML schema

-- Query results to XML with various modes
CREATE PROCEDURE dbo.QueryToXML
    @Query NVARCHAR(MAX),
    @Mode NVARCHAR(20) = 'AUTO',  -- RAW, AUTO, EXPLICIT, PATH
    @RootElement NVARCHAR(128) = 'root',
    @RowElement NVARCHAR(128) = 'row',
    @IncludeSchema BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @XMLOptions NVARCHAR(200) = '';
    
    -- Build options
    IF @RootElement IS NOT NULL
        SET @XMLOptions = @XMLOptions + ', ROOT(''' + @RootElement + ''')';
    
    IF @IncludeSchema = 1
        SET @XMLOptions = @XMLOptions + ', XMLSCHEMA';
    
    -- Build query based on mode
    SET @SQL = @Query + ' FOR XML ' + @Mode;
    
    IF @Mode = 'RAW' AND @RowElement IS NOT NULL
        SET @SQL = @SQL + '(''' + @RowElement + ''')';
    
    SET @SQL = @SQL + @XMLOptions;
    
    EXEC sp_executesql @SQL;
END
GO

-- Parse XML document
CREATE PROCEDURE dbo.ParseXMLDocument
    @XMLDoc XML,
    @NodePath NVARCHAR(500) = '/root/row'
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Get node count
    SELECT @XMLDoc.value('count(//*)', 'INT') AS TotalNodes;
    
    -- Extract data using XQuery
    SELECT 
        node.value('local-name(.)', 'NVARCHAR(128)') AS NodeName,
        node.value('.', 'NVARCHAR(MAX)') AS NodeValue,
        node.value('count(./*)', 'INT') AS ChildCount
    FROM @XMLDoc.nodes('//row/*') AS T(node);
END
GO

-- Shred XML to table
CREATE PROCEDURE dbo.ShredXMLToTable
    @XMLDoc XML,
    @RowXPath NVARCHAR(500),  -- e.g., '/Orders/Order'
    @ColumnMappings NVARCHAR(MAX)  -- JSON: [{"column":"OrderID","xpath":"@ID","type":"INT"}]
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @SelectColumns NVARCHAR(MAX) = '';
    
    -- Build SELECT with XQuery expressions
    SELECT @SelectColumns = @SelectColumns + 
        'T.c.value(''' + JSON_VALUE(value, '$.xpath') + ''', ''' + 
        JSON_VALUE(value, '$.type') + ''') AS [' + 
        JSON_VALUE(value, '$.column') + '], '
    FROM OPENJSON(@ColumnMappings);
    
    -- Remove trailing comma
    SET @SelectColumns = LEFT(@SelectColumns, LEN(@SelectColumns) - 1);
    
    SET @SQL = N'
        SELECT ' + @SelectColumns + '
        FROM @xml.nodes(''' + @RowXPath + ''') AS T(c)';
    
    EXEC sp_executesql @SQL, N'@xml XML', @xml = @XMLDoc;
END
GO

-- Store and query XML data
CREATE PROCEDURE dbo.StoreXMLDocument
    @DocumentType NVARCHAR(50),
    @DocumentID INT,
    @XMLData XML,
    @ValidateSchema BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Create storage table if not exists
    IF OBJECT_ID('dbo.XMLDocuments', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.XMLDocuments (
            XMLDocumentID INT IDENTITY(1,1) PRIMARY KEY,
            DocumentType NVARCHAR(50) NOT NULL,
            DocumentID INT NOT NULL,
            XMLData XML NOT NULL,
            CreatedDate DATETIME2 DEFAULT SYSDATETIME(),
            ModifiedDate DATETIME2 DEFAULT SYSDATETIME(),
            INDEX IX_DocType_ID NONCLUSTERED (DocumentType, DocumentID)
        );
        
        -- Create XML index for better query performance
        CREATE PRIMARY XML INDEX PXML_XMLDocuments ON dbo.XMLDocuments(XMLData);
    END
    
    -- Upsert
    IF EXISTS (SELECT 1 FROM dbo.XMLDocuments WHERE DocumentType = @DocumentType AND DocumentID = @DocumentID)
    BEGIN
        UPDATE dbo.XMLDocuments
        SET XMLData = @XMLData,
            ModifiedDate = SYSDATETIME()
        WHERE DocumentType = @DocumentType AND DocumentID = @DocumentID;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.XMLDocuments (DocumentType, DocumentID, XMLData)
        VALUES (@DocumentType, @DocumentID, @XMLData);
    END
    
    SELECT @@ROWCOUNT AS RowsAffected;
END
GO

-- Query XML with XPath filters
CREATE PROCEDURE dbo.QueryXMLByXPath
    @DocumentType NVARCHAR(50) = NULL,
    @XPathQuery NVARCHAR(500),
    @FilterValue NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    IF @FilterValue IS NULL
    BEGIN
        SELECT 
            XMLDocumentID,
            DocumentType,
            DocumentID,
            XMLData.query(@XPathQuery) AS Result
        FROM dbo.XMLDocuments
        WHERE (@DocumentType IS NULL OR DocumentType = @DocumentType)
          AND XMLData.exist(@XPathQuery) = 1;
    END
    ELSE
    BEGIN
        DECLARE @SQL NVARCHAR(MAX);
        SET @SQL = N'
            SELECT 
                XMLDocumentID,
                DocumentType,
                DocumentID,
                XMLData.query(@XPath) AS Result
            FROM dbo.XMLDocuments
            WHERE (@DocType IS NULL OR DocumentType = @DocType)
              AND XMLData.value(''' + @XPathQuery + '[1]'', ''NVARCHAR(500)'') = @Filter';
        
        EXEC sp_executesql @SQL,
            N'@XPath NVARCHAR(500), @DocType NVARCHAR(50), @Filter NVARCHAR(500)',
            @XPath = @XPathQuery,
            @DocType = @DocumentType,
            @Filter = @FilterValue;
    END
END
GO

-- Modify XML document
CREATE PROCEDURE dbo.ModifyXMLDocument
    @DocumentType NVARCHAR(50),
    @DocumentID INT,
    @Operation NVARCHAR(20),  -- INSERT, DELETE, REPLACE
    @XPath NVARCHAR(500),
    @NewValue NVARCHAR(MAX) = NULL,
    @NewXML XML = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @ModifyExpression NVARCHAR(MAX);
    
    -- Build modify expression based on operation
    SET @ModifyExpression = CASE @Operation
        WHEN 'INSERT' THEN 
            CASE 
                WHEN @NewXML IS NOT NULL 
                THEN 'insert sql:variable("@NewXML") into (' + @XPath + ')[1]'
                ELSE 'insert <value>' + ISNULL(@NewValue, '') + '</value> into (' + @XPath + ')[1]'
            END
        WHEN 'DELETE' THEN 
            'delete (' + @XPath + ')[1]'
        WHEN 'REPLACE' THEN 
            CASE
                WHEN @NewXML IS NOT NULL
                THEN 'replace value of (' + @XPath + ')[1] with sql:variable("@NewXML")'
                ELSE 'replace value of (' + @XPath + '/text())[1] with "' + ISNULL(@NewValue, '') + '"'
            END
        ELSE NULL
    END;
    
    IF @ModifyExpression IS NULL
    BEGIN
        RAISERROR('Invalid operation: %s', 16, 1, @Operation);
        RETURN;
    END
    
    SET @SQL = N'
        UPDATE dbo.XMLDocuments
        SET XMLData.modify(''' + @ModifyExpression + '''),
            ModifiedDate = SYSDATETIME()
        WHERE DocumentType = @DocType AND DocumentID = @DocID';
    
    EXEC sp_executesql @SQL,
        N'@DocType NVARCHAR(50), @DocID INT, @NewXML XML',
        @DocType = @DocumentType,
        @DocID = @DocumentID,
        @NewXML = @NewXML;
    
    SELECT @@ROWCOUNT AS RowsModified;
END
GO

-- Convert between XML and table
CREATE PROCEDURE dbo.TableToXML
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @WhereClause NVARCHAR(MAX) = NULL,
    @RootName NVARCHAR(128) = 'Data',
    @RowName NVARCHAR(128) = 'Row'
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FullPath NVARCHAR(256) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    
    SET @SQL = N'
        SELECT * 
        FROM ' + @FullPath;
    
    IF @WhereClause IS NOT NULL
        SET @SQL = @SQL + ' WHERE ' + @WhereClause;
    
    SET @SQL = @SQL + '
        FOR XML PATH(''' + @RowName + '''), ROOT(''' + @RootName + '''), ELEMENTS XSINIL';
    
    EXEC sp_executesql @SQL;
END
GO

-- Validate XML against schema
CREATE PROCEDURE dbo.ValidateXMLSchema
    @XMLDoc XML,
    @SchemaCollection NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @ValidXML XML;
    
    BEGIN TRY
        -- Attempt to cast with schema validation
        SET @SQL = N'
            DECLARE @typed XML(' + @SchemaCollection + ');
            SET @typed = @xml;
            SELECT ''Valid'' AS ValidationResult;';
        
        EXEC sp_executesql @SQL, N'@xml XML', @xml = @XMLDoc;
        
    END TRY
    BEGIN CATCH
        SELECT 
            'Invalid' AS ValidationResult,
            ERROR_MESSAGE() AS ValidationError;
    END CATCH
END
GO

-- Get XML document statistics
CREATE PROCEDURE dbo.GetXMLStatistics
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        DocumentType,
        COUNT(*) AS DocumentCount,
        AVG(DATALENGTH(XMLData)) AS AvgSizeBytes,
        MAX(DATALENGTH(XMLData)) AS MaxSizeBytes,
        MIN(CreatedDate) AS OldestDocument,
        MAX(ModifiedDate) AS NewestModification
    FROM dbo.XMLDocuments
    GROUP BY DocumentType
    ORDER BY DocumentCount DESC;
    
    -- XML index usage
    SELECT 
        OBJECT_NAME(i.object_id) AS TableName,
        i.name AS IndexName,
        i.type_desc AS IndexType,
        us.user_seeks + us.user_scans AS TotalReads,
        us.user_updates AS TotalWrites
    FROM sys.xml_indexes i
    LEFT JOIN sys.dm_db_index_usage_stats us 
        ON i.object_id = us.object_id AND i.index_id = us.index_id
    WHERE us.database_id = DB_ID();
END
GO
