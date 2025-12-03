-- Sample 041: Advanced XML Operations
-- Source: Microsoft Learn, MSSQLTips, various blog posts
-- Category: XML/JSON Processing
-- Complexity: Advanced
-- Features: XQuery, XSLT concepts, XML indexes, namespace handling, XML DML

-- Parse XML with namespaces
CREATE PROCEDURE dbo.ParseXMLWithNamespaces
    @XMLDocument XML,
    @NamespaceURI NVARCHAR(500) = NULL,
    @NamespacePrefix NVARCHAR(50) = 'ns'
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Without namespace
    IF @NamespaceURI IS NULL
    BEGIN
        SELECT 
            t.c.value('@id', 'INT') AS ID,
            t.c.value('(name)[1]', 'NVARCHAR(100)') AS Name,
            t.c.value('(description)[1]', 'NVARCHAR(500)') AS Description,
            t.c.value('(price)[1]', 'DECIMAL(18,2)') AS Price,
            t.c.query('attributes') AS Attributes
        FROM @XMLDocument.nodes('/root/item') AS t(c);
    END
    ELSE
    BEGIN
        -- With namespace (dynamic SQL needed for variable namespace)
        DECLARE @SQL NVARCHAR(MAX);
        SET @SQL = '
            ;WITH XMLNAMESPACES (''' + @NamespaceURI + ''' AS ' + @NamespacePrefix + ')
            SELECT 
                t.c.value(''@id'', ''INT'') AS ID,
                t.c.value(''(' + @NamespacePrefix + ':name)[1]'', ''NVARCHAR(100)'') AS Name,
                t.c.value(''(' + @NamespacePrefix + ':description)[1]'', ''NVARCHAR(500)'') AS Description,
                t.c.value(''(' + @NamespacePrefix + ':price)[1]'', ''DECIMAL(18,2)'') AS Price
            FROM @xml.nodes(''/' + @NamespacePrefix + ':root/' + @NamespacePrefix + ':item'') AS t(c)';
        
        EXEC sp_executesql @SQL, N'@xml XML', @xml = @XMLDocument;
    END
END
GO

-- Build complex XML from relational data
CREATE PROCEDURE dbo.BuildComplexXML
    @CustomerID INT = NULL,
    @IncludeOrders BIT = 1,
    @RootElement NVARCHAR(100) = 'Customers'
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @XML XML;
    
    SET @XML = (
        SELECT 
            c.CustomerID AS '@id',
            c.CustomerName AS 'Name',
            c.Email AS 'Contact/Email',
            c.Phone AS 'Contact/Phone',
            (
                SELECT 
                    a.AddressType AS '@type',
                    a.Street AS 'Street',
                    a.City AS 'City',
                    a.State AS 'State',
                    a.PostalCode AS 'PostalCode'
                FROM dbo.CustomerAddresses a
                WHERE a.CustomerID = c.CustomerID
                FOR XML PATH('Address'), TYPE
            ) AS 'Addresses',
            CASE WHEN @IncludeOrders = 1 THEN (
                SELECT 
                    o.OrderID AS '@id',
                    o.OrderDate AS '@date',
                    o.Status AS 'Status',
                    o.OrderTotal AS 'Total',
                    (
                        SELECT 
                            od.ProductID AS '@productId',
                            p.ProductName AS 'Product',
                            od.Quantity AS 'Quantity',
                            od.UnitPrice AS 'UnitPrice',
                            od.LineTotal AS 'LineTotal'
                        FROM dbo.OrderDetails od
                        INNER JOIN dbo.Products p ON od.ProductID = p.ProductID
                        WHERE od.OrderID = o.OrderID
                        FOR XML PATH('Item'), TYPE
                    ) AS 'Items'
                FROM dbo.Orders o
                WHERE o.CustomerID = c.CustomerID
                FOR XML PATH('Order'), TYPE
            ) END AS 'Orders'
        FROM dbo.Customers c
        WHERE @CustomerID IS NULL OR c.CustomerID = @CustomerID
        FOR XML PATH('Customer'), ROOT('Customers'), TYPE
    );
    
    SELECT @XML AS XMLDocument;
END
GO

-- Modify XML using XML DML
CREATE PROCEDURE dbo.ModifyXMLDocument
    @XMLDocument XML,
    @Operation NVARCHAR(20),  -- INSERT, DELETE, REPLACE
    @XPath NVARCHAR(500),
    @NewValue NVARCHAR(MAX) = NULL,
    @Position NVARCHAR(20) = 'into'  -- into, after, before (for INSERT)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @ModifiedXML XML = @XMLDocument;
    
    IF @Operation = 'INSERT'
    BEGIN
        IF @Position = 'into'
            SET @ModifiedXML.modify('insert sql:variable("@NewValue") into (' + @XPath + ')[1]');
        ELSE IF @Position = 'after'
            SET @ModifiedXML.modify('insert sql:variable("@NewValue") after (' + @XPath + ')[1]');
        ELSE IF @Position = 'before'
            SET @ModifiedXML.modify('insert sql:variable("@NewValue") before (' + @XPath + ')[1]');
    END
    ELSE IF @Operation = 'DELETE'
    BEGIN
        SET @ModifiedXML.modify('delete (' + @XPath + ')');
    END
    ELSE IF @Operation = 'REPLACE'
    BEGIN
        SET @ModifiedXML.modify('replace value of (' + @XPath + '/text())[1] with sql:variable("@NewValue")');
    END
    
    SELECT @ModifiedXML AS ModifiedXML;
END
GO

-- Shred XML into relational table
CREATE PROCEDURE dbo.ShredXMLToTable
    @XMLDocument XML,
    @TargetSchema NVARCHAR(128) = 'dbo',
    @TargetTable NVARCHAR(128),
    @RowPath NVARCHAR(500),
    @ColumnMappings NVARCHAR(MAX),  -- XML: <mappings><map xpath="" column="" datatype=""/></mappings>
    @TruncateFirst BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @SelectCols NVARCHAR(MAX) = '';
    DECLARE @MappingsXML XML = CAST(@ColumnMappings AS XML);
    DECLARE @TargetPath NVARCHAR(256) = QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable);
    
    -- Build SELECT columns from mappings
    SELECT @SelectCols = @SelectCols + 
        't.c.value(''' + m.c.value('@xpath', 'NVARCHAR(500)') + ''', ''' + 
        m.c.value('@datatype', 'NVARCHAR(50)') + ''') AS ' + 
        QUOTENAME(m.c.value('@column', 'NVARCHAR(128)')) + ', '
    FROM @MappingsXML.nodes('/mappings/map') AS m(c);
    
    -- Remove trailing comma
    SET @SelectCols = LEFT(@SelectCols, LEN(@SelectCols) - 1);
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        IF @TruncateFirst = 1
        BEGIN
            SET @SQL = 'TRUNCATE TABLE ' + @TargetPath;
            EXEC sp_executesql @SQL;
        END
        
        SET @SQL = '
            INSERT INTO ' + @TargetPath + '
            SELECT ' + @SelectCols + '
            FROM @xml.nodes(''' + @RowPath + ''') AS t(c)';
        
        EXEC sp_executesql @SQL, N'@xml XML', @xml = @XMLDocument;
        
        COMMIT TRANSACTION;
        
        SELECT @@ROWCOUNT AS RowsInserted;
        
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

-- Query XML with full-text predicates
CREATE PROCEDURE dbo.SearchXMLContent
    @TableName NVARCHAR(128),
    @SchemaName NVARCHAR(128) = 'dbo',
    @XMLColumn NVARCHAR(128),
    @SearchTerm NVARCHAR(200),
    @XPathFilter NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FullPath NVARCHAR(256) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    
    SET @SQL = '
        SELECT *
        FROM ' + @FullPath + '
        WHERE ' + QUOTENAME(@XMLColumn) + '.exist(''
            //*[contains(., "' + @SearchTerm + '")]
        '') = 1';
    
    IF @XPathFilter IS NOT NULL
        SET @SQL = @SQL + ' AND ' + QUOTENAME(@XMLColumn) + '.exist(''' + @XPathFilter + ''') = 1';
    
    EXEC sp_executesql @SQL;
END
GO

-- Validate XML against schema collection
CREATE PROCEDURE dbo.ValidateXMLSchema
    @XMLDocument XML,
    @SchemaCollection NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @IsValid BIT = 0;
    DECLARE @ErrorMessage NVARCHAR(MAX) = NULL;
    
    BEGIN TRY
        SET @SQL = '
            DECLARE @TypedXML XML(' + QUOTENAME(@SchemaCollection) + ');
            SET @TypedXML = @xml;
            SELECT @valid = 1;';
        
        EXEC sp_executesql @SQL, 
            N'@xml XML, @valid BIT OUTPUT',
            @xml = @XMLDocument,
            @valid = @IsValid OUTPUT;
        
        SET @IsValid = 1;
        SET @ErrorMessage = 'XML is valid against schema';
        
    END TRY
    BEGIN CATCH
        SET @IsValid = 0;
        SET @ErrorMessage = ERROR_MESSAGE();
    END CATCH
    
    SELECT 
        @IsValid AS IsValid,
        @ErrorMessage AS ValidationMessage,
        @SchemaCollection AS SchemaCollection;
END
GO
