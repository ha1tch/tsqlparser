-- Sample 071: Schema Documentation Generation
-- Source: Various - MSSQLTips, Red Gate, Stack Overflow
-- Category: Reporting
-- Complexity: Complex
-- Features: Extended properties, schema analysis, documentation export

-- Generate table documentation
CREATE PROCEDURE dbo.GenerateTableDocumentation
    @SchemaName NVARCHAR(128) = NULL,
    @TableName NVARCHAR(128) = NULL,
    @OutputFormat NVARCHAR(20) = 'HTML'  -- HTML, MARKDOWN, TEXT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @Output NVARCHAR(MAX) = '';
    DECLARE @TableList TABLE (SchemaName NVARCHAR(128), TableName NVARCHAR(128));
    
    -- Get tables to document
    INSERT INTO @TableList
    SELECT s.name, t.name
    FROM sys.tables t
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE (@SchemaName IS NULL OR s.name = @SchemaName)
      AND (@TableName IS NULL OR t.name = @TableName)
    ORDER BY s.name, t.name;
    
    IF @OutputFormat = 'HTML'
    BEGIN
        SET @Output = '<html><head><style>
            body { font-family: Arial, sans-serif; margin: 20px; }
            h1 { color: #333; border-bottom: 2px solid #4472C4; }
            h2 { color: #4472C4; margin-top: 30px; }
            table { border-collapse: collapse; width: 100%; margin: 10px 0; }
            th { background-color: #4472C4; color: white; padding: 10px; text-align: left; }
            td { border: 1px solid #ddd; padding: 8px; }
            tr:nth-child(even) { background-color: #f9f9f9; }
            .description { font-style: italic; color: #666; margin: 10px 0; }
            .pk { color: #c00; font-weight: bold; }
            .fk { color: #00c; }
            .nullable { color: #999; }
        </style></head><body>';
        SET @Output = @Output + '<h1>Database Schema Documentation</h1>';
        SET @Output = @Output + '<p>Generated: ' + CONVERT(VARCHAR(30), SYSDATETIME(), 121) + '</p>';
        SET @Output = @Output + '<p>Database: ' + DB_NAME() + '</p>';
    END
    ELSE IF @OutputFormat = 'MARKDOWN'
    BEGIN
        SET @Output = '# Database Schema Documentation' + CHAR(13) + CHAR(10);
        SET @Output = @Output + 'Generated: ' + CONVERT(VARCHAR(30), SYSDATETIME(), 121) + CHAR(13) + CHAR(10);
        SET @Output = @Output + 'Database: ' + DB_NAME() + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10);
    END
    
    -- Process each table
    DECLARE @Schema NVARCHAR(128), @Table NVARCHAR(128);
    DECLARE @TableDesc NVARCHAR(MAX);
    
    DECLARE TableCursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT SchemaName, TableName FROM @TableList;
    
    OPEN TableCursor;
    FETCH NEXT FROM TableCursor INTO @Schema, @Table;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Get table description
        SELECT @TableDesc = CAST(value AS NVARCHAR(MAX))
        FROM sys.extended_properties
        WHERE major_id = OBJECT_ID(QUOTENAME(@Schema) + '.' + QUOTENAME(@Table))
          AND minor_id = 0
          AND name = 'MS_Description';
        
        IF @OutputFormat = 'HTML'
        BEGIN
            SET @Output = @Output + '<h2>' + @Schema + '.' + @Table + '</h2>';
            SET @Output = @Output + '<p class="description">' + ISNULL(@TableDesc, 'No description available') + '</p>';
            SET @Output = @Output + '<table><tr><th>Column</th><th>Type</th><th>Nullable</th><th>Default</th><th>Description</th></tr>';
            
            SELECT @Output = @Output + 
                '<tr><td>' + 
                CASE WHEN ic.object_id IS NOT NULL THEN '<span class="pk">' + c.name + ' (PK)</span>'
                     WHEN fkc.parent_object_id IS NOT NULL THEN '<span class="fk">' + c.name + ' (FK)</span>'
                     ELSE c.name 
                END + '</td>' +
                '<td>' + TYPE_NAME(c.user_type_id) + 
                    CASE WHEN TYPE_NAME(c.user_type_id) IN ('varchar', 'nvarchar', 'char', 'nchar') 
                         THEN '(' + CASE WHEN c.max_length = -1 THEN 'MAX' ELSE CAST(c.max_length / CASE WHEN TYPE_NAME(c.user_type_id) LIKE 'n%' THEN 2 ELSE 1 END AS VARCHAR(10)) END + ')'
                         WHEN TYPE_NAME(c.user_type_id) IN ('decimal', 'numeric')
                         THEN '(' + CAST(c.precision AS VARCHAR(10)) + ',' + CAST(c.scale AS VARCHAR(10)) + ')'
                         ELSE ''
                    END + '</td>' +
                '<td>' + CASE WHEN c.is_nullable = 1 THEN '<span class="nullable">Yes</span>' ELSE 'No' END + '</td>' +
                '<td>' + ISNULL(dc.definition, '') + '</td>' +
                '<td>' + ISNULL(CAST(ep.value AS NVARCHAR(500)), '') + '</td></tr>'
            FROM sys.columns c
            LEFT JOIN sys.extended_properties ep ON c.object_id = ep.major_id AND c.column_id = ep.minor_id AND ep.name = 'MS_Description'
            LEFT JOIN sys.default_constraints dc ON c.default_object_id = dc.object_id
            LEFT JOIN sys.index_columns ic ON c.object_id = ic.object_id AND c.column_id = ic.column_id AND ic.index_id = 1
            LEFT JOIN sys.foreign_key_columns fkc ON c.object_id = fkc.parent_object_id AND c.column_id = fkc.parent_column_id
            WHERE c.object_id = OBJECT_ID(QUOTENAME(@Schema) + '.' + QUOTENAME(@Table))
            ORDER BY c.column_id;
            
            SET @Output = @Output + '</table>';
        END
        ELSE IF @OutputFormat = 'MARKDOWN'
        BEGIN
            SET @Output = @Output + '## ' + @Schema + '.' + @Table + CHAR(13) + CHAR(10);
            SET @Output = @Output + ISNULL(@TableDesc, '_No description_') + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10);
            SET @Output = @Output + '| Column | Type | Nullable | Description |' + CHAR(13) + CHAR(10);
            SET @Output = @Output + '|--------|------|----------|-------------|' + CHAR(13) + CHAR(10);
            
            SELECT @Output = @Output + 
                '| ' + c.name + ' | ' + TYPE_NAME(c.user_type_id) + ' | ' + 
                CASE WHEN c.is_nullable = 1 THEN 'Yes' ELSE 'No' END + ' | ' +
                ISNULL(CAST(ep.value AS NVARCHAR(200)), '') + ' |' + CHAR(13) + CHAR(10)
            FROM sys.columns c
            LEFT JOIN sys.extended_properties ep ON c.object_id = ep.major_id AND c.column_id = ep.minor_id AND ep.name = 'MS_Description'
            WHERE c.object_id = OBJECT_ID(QUOTENAME(@Schema) + '.' + QUOTENAME(@Table))
            ORDER BY c.column_id;
            
            SET @Output = @Output + CHAR(13) + CHAR(10);
        END
        
        FETCH NEXT FROM TableCursor INTO @Schema, @Table;
    END
    
    CLOSE TableCursor;
    DEALLOCATE TableCursor;
    
    IF @OutputFormat = 'HTML'
        SET @Output = @Output + '</body></html>';
    
    SELECT @Output AS Documentation;
END
GO

-- Add/Update extended property description
CREATE PROCEDURE dbo.SetObjectDescription
    @SchemaName NVARCHAR(128) = 'dbo',
    @ObjectName NVARCHAR(128),
    @ColumnName NVARCHAR(128) = NULL,
    @Description NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    
    IF @ColumnName IS NULL
    BEGIN
        -- Table/View description
        IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE major_id = OBJECT_ID(QUOTENAME(@SchemaName) + '.' + QUOTENAME(@ObjectName)) AND minor_id = 0 AND name = 'MS_Description')
        BEGIN
            EXEC sp_updateextendedproperty 
                @name = 'MS_Description',
                @value = @Description,
                @level0type = 'SCHEMA', @level0name = @SchemaName,
                @level1type = 'TABLE', @level1name = @ObjectName;
        END
        ELSE
        BEGIN
            EXEC sp_addextendedproperty 
                @name = 'MS_Description',
                @value = @Description,
                @level0type = 'SCHEMA', @level0name = @SchemaName,
                @level1type = 'TABLE', @level1name = @ObjectName;
        END
    END
    ELSE
    BEGIN
        -- Column description
        IF EXISTS (SELECT 1 FROM sys.extended_properties ep
                   INNER JOIN sys.columns c ON ep.major_id = c.object_id AND ep.minor_id = c.column_id
                   WHERE c.object_id = OBJECT_ID(QUOTENAME(@SchemaName) + '.' + QUOTENAME(@ObjectName))
                     AND c.name = @ColumnName AND ep.name = 'MS_Description')
        BEGIN
            EXEC sp_updateextendedproperty 
                @name = 'MS_Description',
                @value = @Description,
                @level0type = 'SCHEMA', @level0name = @SchemaName,
                @level1type = 'TABLE', @level1name = @ObjectName,
                @level2type = 'COLUMN', @level2name = @ColumnName;
        END
        ELSE
        BEGIN
            EXEC sp_addextendedproperty 
                @name = 'MS_Description',
                @value = @Description,
                @level0type = 'SCHEMA', @level0name = @SchemaName,
                @level1type = 'TABLE', @level1name = @ObjectName,
                @level2type = 'COLUMN', @level2name = @ColumnName;
        END
    END
    
    SELECT 'Description updated' AS Status;
END
GO

-- Generate data dictionary
CREATE PROCEDURE dbo.GenerateDataDictionary
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Tables summary
    SELECT 
        s.name AS SchemaName,
        t.name AS TableName,
        CAST(ep.value AS NVARCHAR(500)) AS TableDescription,
        (SELECT COUNT(*) FROM sys.columns WHERE object_id = t.object_id) AS ColumnCount,
        (SELECT SUM(row_count) FROM sys.dm_db_partition_stats WHERE object_id = t.object_id AND index_id IN (0,1)) AS RowCount,
        t.create_date AS CreatedDate,
        t.modify_date AS ModifiedDate
    FROM sys.tables t
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    LEFT JOIN sys.extended_properties ep ON t.object_id = ep.major_id AND ep.minor_id = 0 AND ep.name = 'MS_Description'
    ORDER BY s.name, t.name;
    
    -- Columns detail
    SELECT 
        s.name AS SchemaName,
        t.name AS TableName,
        c.name AS ColumnName,
        TYPE_NAME(c.user_type_id) AS DataType,
        c.max_length AS MaxLength,
        c.precision AS Precision,
        c.scale AS Scale,
        c.is_nullable AS IsNullable,
        c.is_identity AS IsIdentity,
        dc.definition AS DefaultValue,
        CAST(ep.value AS NVARCHAR(500)) AS ColumnDescription,
        CASE WHEN pk.column_id IS NOT NULL THEN 1 ELSE 0 END AS IsPrimaryKey,
        CASE WHEN fk.parent_column_id IS NOT NULL THEN 1 ELSE 0 END AS IsForeignKey
    FROM sys.tables t
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    INNER JOIN sys.columns c ON t.object_id = c.object_id
    LEFT JOIN sys.extended_properties ep ON c.object_id = ep.major_id AND c.column_id = ep.minor_id AND ep.name = 'MS_Description'
    LEFT JOIN sys.default_constraints dc ON c.default_object_id = dc.object_id
    LEFT JOIN (SELECT ic.object_id, ic.column_id FROM sys.index_columns ic INNER JOIN sys.indexes i ON ic.object_id = i.object_id AND ic.index_id = i.index_id WHERE i.is_primary_key = 1) pk ON c.object_id = pk.object_id AND c.column_id = pk.column_id
    LEFT JOIN sys.foreign_key_columns fk ON c.object_id = fk.parent_object_id AND c.column_id = fk.parent_column_id
    ORDER BY s.name, t.name, c.column_id;
    
    -- Foreign key relationships
    SELECT 
        OBJECT_SCHEMA_NAME(fk.parent_object_id) AS ParentSchema,
        OBJECT_NAME(fk.parent_object_id) AS ParentTable,
        COL_NAME(fkc.parent_object_id, fkc.parent_column_id) AS ParentColumn,
        OBJECT_SCHEMA_NAME(fk.referenced_object_id) AS ReferencedSchema,
        OBJECT_NAME(fk.referenced_object_id) AS ReferencedTable,
        COL_NAME(fkc.referenced_object_id, fkc.referenced_column_id) AS ReferencedColumn,
        fk.name AS ForeignKeyName,
        fk.delete_referential_action_desc AS OnDelete,
        fk.update_referential_action_desc AS OnUpdate
    FROM sys.foreign_keys fk
    INNER JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
    ORDER BY ParentSchema, ParentTable, ForeignKeyName;
END
GO

-- Find undocumented objects
CREATE PROCEDURE dbo.FindUndocumentedObjects
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Undocumented tables
    SELECT 
        'Table' AS ObjectType,
        SCHEMA_NAME(t.schema_id) AS SchemaName,
        t.name AS ObjectName,
        NULL AS ColumnName
    FROM sys.tables t
    WHERE NOT EXISTS (
        SELECT 1 FROM sys.extended_properties ep 
        WHERE ep.major_id = t.object_id AND ep.minor_id = 0 AND ep.name = 'MS_Description'
    )
    
    UNION ALL
    
    -- Undocumented columns
    SELECT 
        'Column' AS ObjectType,
        SCHEMA_NAME(t.schema_id) AS SchemaName,
        t.name AS ObjectName,
        c.name AS ColumnName
    FROM sys.tables t
    INNER JOIN sys.columns c ON t.object_id = c.object_id
    WHERE NOT EXISTS (
        SELECT 1 FROM sys.extended_properties ep 
        WHERE ep.major_id = c.object_id AND ep.minor_id = c.column_id AND ep.name = 'MS_Description'
    )
    
    ORDER BY SchemaName, ObjectName, ColumnName;
    
    -- Summary
    SELECT 
        (SELECT COUNT(*) FROM sys.tables t WHERE NOT EXISTS (SELECT 1 FROM sys.extended_properties ep WHERE ep.major_id = t.object_id AND ep.minor_id = 0 AND ep.name = 'MS_Description')) AS UndocumentedTables,
        (SELECT COUNT(*) FROM sys.tables) AS TotalTables,
        (SELECT COUNT(*) FROM sys.tables t INNER JOIN sys.columns c ON t.object_id = c.object_id WHERE NOT EXISTS (SELECT 1 FROM sys.extended_properties ep WHERE ep.major_id = c.object_id AND ep.minor_id = c.column_id AND ep.name = 'MS_Description')) AS UndocumentedColumns,
        (SELECT COUNT(*) FROM sys.tables t INNER JOIN sys.columns c ON t.object_id = c.object_id) AS TotalColumns;
END
GO
