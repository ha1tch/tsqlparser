-- Sample 039: Advanced JSON Operations
-- Source: Microsoft Learn, MSSQLTips, Jovan Popovic articles
-- Category: XML/JSON Processing
-- Complexity: Advanced
-- Features: JSON_VALUE, JSON_QUERY, JSON_MODIFY, OPENJSON, FOR JSON, JSON Schema validation

-- Parse and shred complex JSON document
CREATE PROCEDURE dbo.ParseComplexJSON
    @JSONDocument NVARCHAR(MAX),
    @ExtractPath NVARCHAR(500) = '$'
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Validate JSON
    IF ISJSON(@JSONDocument) = 0
    BEGIN
        RAISERROR('Invalid JSON document', 16, 1);
        RETURN;
    END
    
    -- Extract metadata
    SELECT 
        'JSON Metadata' AS Section,
        JSON_VALUE(@JSONDocument, '$.metadata.version') AS Version,
        JSON_VALUE(@JSONDocument, '$.metadata.timestamp') AS Timestamp,
        JSON_VALUE(@JSONDocument, '$.metadata.source') AS Source;
    
    -- Shred array data
    SELECT 
        j.[key] AS ArrayIndex,
        JSON_VALUE(j.value, '$.id') AS ID,
        JSON_VALUE(j.value, '$.name') AS Name,
        JSON_VALUE(j.value, '$.type') AS Type,
        JSON_QUERY(j.value, '$.attributes') AS Attributes,
        JSON_QUERY(j.value, '$.children') AS Children
    FROM OPENJSON(@JSONDocument, @ExtractPath) j
    WHERE j.type = 5;  -- type 5 = object
    
    -- Nested array extraction
    SELECT 
        parent.[key] AS ParentIndex,
        JSON_VALUE(parent.value, '$.id') AS ParentID,
        JSON_VALUE(parent.value, '$.name') AS ParentName,
        child.[key] AS ChildIndex,
        JSON_VALUE(child.value, '$.id') AS ChildID,
        JSON_VALUE(child.value, '$.name') AS ChildName
    FROM OPENJSON(@JSONDocument, @ExtractPath) parent
    CROSS APPLY OPENJSON(parent.value, '$.children') child
    WHERE ISJSON(JSON_QUERY(parent.value, '$.children')) = 1;
END
GO

-- Build JSON document from relational data
CREATE PROCEDURE dbo.BuildJSONFromTables
    @CustomerID INT = NULL,
    @IncludeOrders BIT = 1,
    @IncludeAddresses BIT = 1,
    @PrettyPrint BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @JSON NVARCHAR(MAX);
    
    -- Build hierarchical JSON
    SET @JSON = (
        SELECT 
            c.CustomerID AS 'id',
            c.CustomerName AS 'name',
            c.Email AS 'email',
            c.Phone AS 'phone',
            c.CreatedDate AS 'createdDate',
            -- Nested addresses
            CASE WHEN @IncludeAddresses = 1 THEN (
                SELECT 
                    a.AddressID AS 'id',
                    a.AddressType AS 'type',
                    a.Street AS 'street',
                    a.City AS 'city',
                    a.State AS 'state',
                    a.PostalCode AS 'postalCode',
                    a.Country AS 'country'
                FROM dbo.CustomerAddresses a
                WHERE a.CustomerID = c.CustomerID
                FOR JSON PATH
            ) END AS 'addresses',
            -- Nested orders with items
            CASE WHEN @IncludeOrders = 1 THEN (
                SELECT 
                    o.OrderID AS 'id',
                    o.OrderDate AS 'orderDate',
                    o.Status AS 'status',
                    o.OrderTotal AS 'total',
                    (
                        SELECT 
                            od.ProductID AS 'productId',
                            p.ProductName AS 'productName',
                            od.Quantity AS 'quantity',
                            od.UnitPrice AS 'unitPrice',
                            od.LineTotal AS 'lineTotal'
                        FROM dbo.OrderDetails od
                        INNER JOIN dbo.Products p ON od.ProductID = p.ProductID
                        WHERE od.OrderID = o.OrderID
                        FOR JSON PATH
                    ) AS 'items'
                FROM dbo.Orders o
                WHERE o.CustomerID = c.CustomerID
                FOR JSON PATH
            ) END AS 'orders'
        FROM dbo.Customers c
        WHERE @CustomerID IS NULL OR c.CustomerID = @CustomerID
        FOR JSON PATH, ROOT('customers')
    );
    
    -- Pretty print if requested
    IF @PrettyPrint = 1
    BEGIN
        -- Simple formatting (actual pretty print would need more complex logic)
        SET @JSON = REPLACE(@JSON, '},{', '},
{');
        SET @JSON = REPLACE(@JSON, '","', '",
"');
    END
    
    SELECT @JSON AS JSONDocument;
END
GO

-- Update JSON properties
CREATE PROCEDURE dbo.UpdateJSONProperty
    @TableName NVARCHAR(128),
    @SchemaName NVARCHAR(128) = 'dbo',
    @JSONColumn NVARCHAR(128),
    @KeyColumn NVARCHAR(128),
    @KeyValue SQL_VARIANT,
    @JSONPath NVARCHAR(500),
    @NewValue NVARCHAR(MAX),
    @ValueType NVARCHAR(20) = 'string'  -- string, number, boolean, null, object, array
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @TypedValue NVARCHAR(MAX);
    
    -- Format value based on type
    SET @TypedValue = CASE @ValueType
        WHEN 'string' THEN '"' + REPLACE(@NewValue, '"', '\"') + '"'
        WHEN 'number' THEN @NewValue
        WHEN 'boolean' THEN LOWER(@NewValue)
        WHEN 'null' THEN 'null'
        WHEN 'object' THEN @NewValue
        WHEN 'array' THEN @NewValue
        ELSE '"' + @NewValue + '"'
    END;
    
    SET @SQL = '
        UPDATE ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + '
        SET ' + QUOTENAME(@JSONColumn) + ' = JSON_MODIFY(' + QUOTENAME(@JSONColumn) + ', 
            ''' + @JSONPath + ''', 
            JSON_QUERY(''' + @TypedValue + '''))
        WHERE ' + QUOTENAME(@KeyColumn) + ' = @KeyValue';
    
    -- For non-object/array values, use simpler syntax
    IF @ValueType NOT IN ('object', 'array')
    BEGIN
        SET @SQL = '
            UPDATE ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + '
            SET ' + QUOTENAME(@JSONColumn) + ' = JSON_MODIFY(' + QUOTENAME(@JSONColumn) + ', 
                ''' + @JSONPath + ''', 
                ' + CASE @ValueType 
                    WHEN 'string' THEN '''' + REPLACE(@NewValue, '''', '''''') + ''''
                    WHEN 'null' THEN 'NULL'
                    ELSE @NewValue 
                END + ')
            WHERE ' + QUOTENAME(@KeyColumn) + ' = @KeyValue';
    END
    
    EXEC sp_executesql @SQL, N'@KeyValue SQL_VARIANT', @KeyValue = @KeyValue;
    
    SELECT @@ROWCOUNT AS RowsUpdated;
END
GO

-- Query JSON data with dynamic filters
CREATE PROCEDURE dbo.QueryJSONData
    @TableName NVARCHAR(128),
    @SchemaName NVARCHAR(128) = 'dbo',
    @JSONColumn NVARCHAR(128),
    @Filters NVARCHAR(MAX) = NULL,  -- JSON object with path:value pairs
    @SelectPaths NVARCHAR(MAX) = NULL  -- JSON array of paths to select
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @WhereClause NVARCHAR(MAX) = '';
    DECLARE @SelectClause NVARCHAR(MAX) = '*';
    
    -- Build WHERE clause from filters
    IF @Filters IS NOT NULL AND ISJSON(@Filters) = 1
    BEGIN
        SELECT @WhereClause = STRING_AGG(
            'JSON_VALUE(' + QUOTENAME(@JSONColumn) + ', ''$.' + [key] + ''') = ''' + 
            REPLACE(CAST(value AS NVARCHAR(MAX)), '''', '''''') + '''',
            ' AND '
        )
        FROM OPENJSON(@Filters);
    END
    
    -- Build SELECT clause from paths
    IF @SelectPaths IS NOT NULL AND ISJSON(@SelectPaths) = 1
    BEGIN
        SELECT @SelectClause = STRING_AGG(
            'JSON_VALUE(' + QUOTENAME(@JSONColumn) + ', ''$.' + 
            CAST(value AS NVARCHAR(MAX)) + ''') AS [' + 
            REPLACE(CAST(value AS NVARCHAR(MAX)), '.', '_') + ']',
            ', '
        )
        FROM OPENJSON(@SelectPaths);
    END
    
    SET @SQL = 'SELECT ' + @SelectClause + ' FROM ' + 
               QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    
    IF LEN(@WhereClause) > 0
        SET @SQL = @SQL + ' WHERE ' + @WhereClause;
    
    EXEC sp_executesql @SQL;
END
GO

-- Merge JSON data into relational tables
CREATE PROCEDURE dbo.MergeJSONToTable
    @JSONData NVARCHAR(MAX),
    @TargetSchema NVARCHAR(128) = 'dbo',
    @TargetTable NVARCHAR(128),
    @KeyMapping NVARCHAR(MAX),  -- JSON: {"jsonPath": "columnName"}
    @ArrayPath NVARCHAR(500) = '$'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @Columns NVARCHAR(MAX);
    DECLARE @InsertCols NVARCHAR(MAX);
    DECLARE @UpdateCols NVARCHAR(MAX);
    DECLARE @JoinCond NVARCHAR(MAX);
    DECLARE @TargetPath NVARCHAR(256) = QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable);
    
    -- Build column mappings
    SELECT 
        @Columns = STRING_AGG(
            'JSON_VALUE(j.value, ''$.' + [key] + ''') AS ' + QUOTENAME(value), ', '),
        @InsertCols = STRING_AGG(QUOTENAME(value), ', '),
        @UpdateCols = STRING_AGG(
            't.' + QUOTENAME(value) + ' = s.' + QUOTENAME(value), ', ')
    FROM OPENJSON(@KeyMapping)
    WHERE [key] NOT LIKE '%_key';  -- Exclude key columns from update
    
    -- Get key columns for join
    SELECT @JoinCond = STRING_AGG(
        't.' + QUOTENAME(value) + ' = s.' + QUOTENAME(value), ' AND ')
    FROM OPENJSON(@KeyMapping)
    WHERE [key] LIKE '%_key' OR value IN (
        SELECT c.name FROM sys.columns c
        INNER JOIN sys.indexes i ON c.object_id = i.object_id
        INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id 
            AND i.index_id = ic.index_id AND c.column_id = ic.column_id
        WHERE c.object_id = OBJECT_ID(@TargetPath) AND i.is_primary_key = 1
    );
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        SET @SQL = '
            ;WITH SourceData AS (
                SELECT ' + @Columns + '
                FROM OPENJSON(@JSON, ''' + @ArrayPath + ''') j
            )
            MERGE ' + @TargetPath + ' AS t
            USING SourceData AS s ON ' + @JoinCond + '
            WHEN MATCHED THEN UPDATE SET ' + @UpdateCols + '
            WHEN NOT MATCHED THEN INSERT (' + @InsertCols + ') 
                VALUES (' + REPLACE(@InsertCols, '[', 's.[') + ');';
        
        EXEC sp_executesql @SQL, N'@JSON NVARCHAR(MAX)', @JSON = @JSONData;
        
        COMMIT TRANSACTION;
        
        SELECT @@ROWCOUNT AS RowsAffected, 'Merge completed' AS Status;
        
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
