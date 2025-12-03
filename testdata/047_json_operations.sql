-- Sample 047: Advanced JSON Operations
-- Source: Microsoft Learn, MSSQLTips, SQLShack
-- Category: XML/JSON Processing
-- Complexity: Advanced
-- Features: JSON_VALUE, JSON_QUERY, JSON_MODIFY, OPENJSON, FOR JSON

-- Parse JSON document and extract values
CREATE PROCEDURE dbo.ParseJSONDocument
    @JSONDocument NVARCHAR(MAX),
    @ExtractPaths NVARCHAR(MAX) = NULL  -- JSON array of paths: ["$.name","$.address.city"]
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Validate JSON
    IF ISJSON(@JSONDocument) = 0
    BEGIN
        SELECT 'Invalid JSON document' AS Error;
        RETURN;
    END
    
    -- Extract specific paths if provided
    IF @ExtractPaths IS NOT NULL
    BEGIN
        SELECT 
            JSON_VALUE(p.value, '$') AS JSONPath,
            JSON_VALUE(@JSONDocument, JSON_VALUE(p.value, '$')) AS ScalarValue,
            JSON_QUERY(@JSONDocument, JSON_VALUE(p.value, '$')) AS ObjectValue
        FROM OPENJSON(@ExtractPaths) p;
    END
    ELSE
    BEGIN
        -- Auto-discover structure
        ;WITH JSONStructure AS (
            SELECT 
                [key],
                value,
                type,
                '$.' + [key] AS JSONPath,
                0 AS [Level]
            FROM OPENJSON(@JSONDocument)
            
            UNION ALL
            
            SELECT 
                j.[key],
                j.value,
                j.type,
                p.JSONPath + '.' + j.[key],
                p.[Level] + 1
            FROM JSONStructure p
            CROSS APPLY OPENJSON(
                CASE WHEN p.type IN (4, 5) THEN p.value END  -- Object or Array
            ) j
            WHERE p.[Level] < 5
        )
        SELECT 
            JSONPath,
            [key] AS PropertyName,
            CASE type
                WHEN 0 THEN 'null'
                WHEN 1 THEN 'string'
                WHEN 2 THEN 'number'
                WHEN 3 THEN 'boolean'
                WHEN 4 THEN 'array'
                WHEN 5 THEN 'object'
            END AS DataType,
            CASE WHEN type IN (0, 1, 2, 3) THEN value ELSE NULL END AS Value,
            [Level]
        FROM JSONStructure
        ORDER BY JSONPath;
    END
END
GO

-- Convert query results to JSON
CREATE PROCEDURE dbo.QueryToJSON
    @Query NVARCHAR(MAX),
    @RootElement NVARCHAR(128) = NULL,
    @IncludeNulls BIT = 0,
    @OutputFormat NVARCHAR(20) = 'AUTO'  -- AUTO, PATH, RAW
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @JSONOptions NVARCHAR(100) = '';
    
    -- Build JSON options
    IF @RootElement IS NOT NULL
        SET @JSONOptions = @JSONOptions + ', ROOT(''' + @RootElement + ''')';
    
    IF @IncludeNulls = 1
        SET @JSONOptions = @JSONOptions + ', INCLUDE_NULL_VALUES';
    
    -- Build query with FOR JSON
    SET @SQL = @Query + ' FOR JSON ' + @OutputFormat + @JSONOptions;
    
    EXEC sp_executesql @SQL;
END
GO

-- Merge JSON documents
CREATE PROCEDURE dbo.MergeJSONDocuments
    @BaseJSON NVARCHAR(MAX),
    @OverlayJSON NVARCHAR(MAX),
    @MergedJSON NVARCHAR(MAX) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    SET @MergedJSON = @BaseJSON;
    
    -- Apply each property from overlay
    SELECT @MergedJSON = JSON_MODIFY(
        @MergedJSON,
        '$.' + [key],
        JSON_QUERY(CASE 
            WHEN type IN (4, 5) THEN value  -- Keep object/array as-is
            ELSE NULL
        END)
    )
    FROM OPENJSON(@OverlayJSON)
    WHERE type IN (4, 5);  -- Objects and arrays
    
    -- Apply scalar values
    SELECT @MergedJSON = JSON_MODIFY(
        @MergedJSON,
        '$.' + [key],
        CASE type
            WHEN 2 THEN CAST(value AS INT)  -- Number
            WHEN 3 THEN CAST(value AS BIT)  -- Boolean
            ELSE value
        END
    )
    FROM OPENJSON(@OverlayJSON)
    WHERE type IN (1, 2, 3);  -- String, number, boolean
    
    SELECT @MergedJSON AS MergedDocument;
END
GO

-- Store and query JSON in table
CREATE PROCEDURE dbo.StoreJSONData
    @EntityType NVARCHAR(50),
    @EntityID INT,
    @JSONData NVARCHAR(MAX),
    @ValidateSchema BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Create storage table if not exists
    IF OBJECT_ID('dbo.JSONDocuments', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.JSONDocuments (
            DocumentID INT IDENTITY(1,1) PRIMARY KEY,
            EntityType NVARCHAR(50) NOT NULL,
            EntityID INT NOT NULL,
            JSONData NVARCHAR(MAX) NOT NULL,
            CreatedDate DATETIME2 DEFAULT SYSDATETIME(),
            ModifiedDate DATETIME2 DEFAULT SYSDATETIME(),
            CONSTRAINT CK_ValidJSON CHECK (ISJSON(JSONData) = 1),
            INDEX IX_Entity NONCLUSTERED (EntityType, EntityID)
        );
    END
    
    -- Validate JSON
    IF ISJSON(@JSONData) = 0
    BEGIN
        RAISERROR('Invalid JSON document', 16, 1);
        RETURN;
    END
    
    -- Upsert
    IF EXISTS (SELECT 1 FROM dbo.JSONDocuments WHERE EntityType = @EntityType AND EntityID = @EntityID)
    BEGIN
        UPDATE dbo.JSONDocuments
        SET JSONData = @JSONData,
            ModifiedDate = SYSDATETIME()
        WHERE EntityType = @EntityType AND EntityID = @EntityID;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.JSONDocuments (EntityType, EntityID, JSONData)
        VALUES (@EntityType, @EntityID, @JSONData);
    END
    
    SELECT @@ROWCOUNT AS RowsAffected;
END
GO

-- Query JSON data with filters
CREATE PROCEDURE dbo.QueryJSONData
    @EntityType NVARCHAR(50) = NULL,
    @JSONPath NVARCHAR(500),
    @FilterValue NVARCHAR(500) = NULL,
    @FilterOperator NVARCHAR(10) = '='  -- =, <>, >, <, LIKE, IS NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    
    SET @SQL = N'
        SELECT 
            DocumentID,
            EntityType,
            EntityID,
            JSON_VALUE(JSONData, @Path) AS ExtractedValue,
            JSONData
        FROM dbo.JSONDocuments
        WHERE (@EntityType IS NULL OR EntityType = @EntityType)';
    
    IF @FilterValue IS NOT NULL
    BEGIN
        SET @SQL = @SQL + N'
          AND JSON_VALUE(JSONData, @Path) ' + @FilterOperator + ' @FilterValue';
    END
    ELSE IF @FilterOperator = 'IS NULL'
    BEGIN
        SET @SQL = @SQL + N'
          AND JSON_VALUE(JSONData, @Path) IS NULL';
    END
    
    EXEC sp_executesql @SQL,
        N'@EntityType NVARCHAR(50), @Path NVARCHAR(500), @FilterValue NVARCHAR(500)',
        @EntityType = @EntityType,
        @Path = @JSONPath,
        @FilterValue = @FilterValue;
END
GO

-- Flatten JSON array to rows
CREATE PROCEDURE dbo.FlattenJSONArray
    @JSONArray NVARCHAR(MAX),
    @ArrayPath NVARCHAR(500) = '$'
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    
    -- Get the array
    DECLARE @Array NVARCHAR(MAX) = JSON_QUERY(@JSONArray, @ArrayPath);
    
    IF @Array IS NULL
        SET @Array = @JSONArray;
    
    -- Flatten with all properties
    SELECT 
        CAST([key] AS INT) AS ArrayIndex,
        j.[key] AS PropertyName,
        j.value AS PropertyValue,
        j.type AS JSONType
    FROM OPENJSON(@Array)
    CROSS APPLY OPENJSON(value) j
    ORDER BY CAST([key] AS INT), j.[key];
END
GO

-- Update JSON property
CREATE PROCEDURE dbo.UpdateJSONProperty
    @EntityType NVARCHAR(50),
    @EntityID INT,
    @JSONPath NVARCHAR(500),
    @NewValue NVARCHAR(MAX),
    @ValueType NVARCHAR(20) = 'string'  -- string, number, boolean, object, array, null
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @TypedValue SQL_VARIANT;
    DECLARE @SQL NVARCHAR(MAX);
    
    UPDATE dbo.JSONDocuments
    SET JSONData = JSON_MODIFY(
        JSONData,
        @JSONPath,
        CASE @ValueType
            WHEN 'number' THEN CAST(@NewValue AS DECIMAL(18,4))
            WHEN 'boolean' THEN CAST(CASE WHEN @NewValue IN ('true', '1') THEN 1 ELSE 0 END AS BIT)
            WHEN 'null' THEN NULL
            WHEN 'object' THEN JSON_QUERY(@NewValue)
            WHEN 'array' THEN JSON_QUERY(@NewValue)
            ELSE @NewValue
        END
    ),
    ModifiedDate = SYSDATETIME()
    WHERE EntityType = @EntityType 
      AND EntityID = @EntityID;
    
    SELECT @@ROWCOUNT AS RowsUpdated;
END
GO
