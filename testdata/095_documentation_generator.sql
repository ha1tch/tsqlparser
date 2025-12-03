-- Sample 095: Database Documentation Generator
-- Source: Various - Redgate patterns, Microsoft Learn, Documentation best practices
-- Category: Documentation
-- Complexity: Complex
-- Features: Schema documentation, data dictionary, relationship diagrams, markdown output

-- Generate comprehensive data dictionary
CREATE PROCEDURE dbo.GenerateDataDictionary
    @SchemaName NVARCHAR(128) = NULL,
    @OutputFormat NVARCHAR(20) = 'TABLE'  -- TABLE, MARKDOWN, HTML
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Tables and columns with extended properties
    SELECT 
        s.name AS SchemaName,
        t.name AS TableName,
        ISNULL(CAST(ep_table.value AS NVARCHAR(MAX)), '') AS TableDescription,
        c.name AS ColumnName,
        TYPE_NAME(c.user_type_id) AS DataType,
        CASE 
            WHEN TYPE_NAME(c.user_type_id) IN ('varchar', 'nvarchar', 'char', 'nchar') 
                THEN CASE c.max_length WHEN -1 THEN 'MAX' ELSE CAST(c.max_length AS VARCHAR(10)) END
            WHEN TYPE_NAME(c.user_type_id) IN ('decimal', 'numeric') 
                THEN CAST(c.precision AS VARCHAR(3)) + ',' + CAST(c.scale AS VARCHAR(3))
            ELSE NULL
        END AS Length,
        CASE c.is_nullable WHEN 1 THEN 'Yes' ELSE 'No' END AS Nullable,
        CASE WHEN pk.column_id IS NOT NULL THEN 'Yes' ELSE 'No' END AS IsPrimaryKey,
        CASE WHEN fk.parent_column_id IS NOT NULL THEN 'Yes' ELSE 'No' END AS IsForeignKey,
        ISNULL(CAST(ep_col.value AS NVARCHAR(MAX)), '') AS ColumnDescription,
        dc.definition AS DefaultValue
    FROM sys.tables t
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    INNER JOIN sys.columns c ON t.object_id = c.object_id
    LEFT JOIN sys.extended_properties ep_table 
        ON t.object_id = ep_table.major_id AND ep_table.minor_id = 0 AND ep_table.name = 'MS_Description'
    LEFT JOIN sys.extended_properties ep_col 
        ON c.object_id = ep_col.major_id AND c.column_id = ep_col.minor_id AND ep_col.name = 'MS_Description'
    LEFT JOIN (
        SELECT ic.object_id, ic.column_id
        FROM sys.index_columns ic
        INNER JOIN sys.indexes i ON ic.object_id = i.object_id AND ic.index_id = i.index_id
        WHERE i.is_primary_key = 1
    ) pk ON c.object_id = pk.object_id AND c.column_id = pk.column_id
    LEFT JOIN sys.foreign_key_columns fk ON c.object_id = fk.parent_object_id AND c.column_id = fk.parent_column_id
    LEFT JOIN sys.default_constraints dc ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
    WHERE (@SchemaName IS NULL OR s.name = @SchemaName)
    ORDER BY s.name, t.name, c.column_id;
END
GO

-- Generate markdown documentation
CREATE PROCEDURE dbo.GenerateMarkdownDocs
    @SchemaName NVARCHAR(128) = NULL,
    @IncludeIndexes BIT = 1,
    @IncludeForeignKeys BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @Output TABLE (LineNum INT IDENTITY(1,1), Line NVARCHAR(MAX));
    DECLARE @CurrentTable NVARCHAR(256);
    DECLARE @PrevTable NVARCHAR(256) = '';
    
    -- Header
    INSERT INTO @Output (Line) VALUES ('# Database Documentation');
    INSERT INTO @Output (Line) VALUES ('');
    INSERT INTO @Output (Line) VALUES ('Generated: ' + CONVERT(VARCHAR(20), GETDATE(), 120));
    INSERT INTO @Output (Line) VALUES ('Database: ' + DB_NAME());
    INSERT INTO @Output (Line) VALUES ('');
    INSERT INTO @Output (Line) VALUES ('## Table of Contents');
    INSERT INTO @Output (Line) VALUES ('');
    
    -- TOC
    INSERT INTO @Output (Line)
    SELECT '- [' + s.name + '.' + t.name + '](#' + LOWER(s.name + t.name) + ')'
    FROM sys.tables t
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE @SchemaName IS NULL OR s.name = @SchemaName
    ORDER BY s.name, t.name;
    
    INSERT INTO @Output (Line) VALUES ('');
    INSERT INTO @Output (Line) VALUES ('---');
    INSERT INTO @Output (Line) VALUES ('');
    
    -- Table details
    DECLARE TableCursor CURSOR FOR
        SELECT DISTINCT s.name + '.' + t.name
        FROM sys.tables t
        INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
        WHERE @SchemaName IS NULL OR s.name = @SchemaName
        ORDER BY s.name + '.' + t.name;
    
    OPEN TableCursor;
    FETCH NEXT FROM TableCursor INTO @CurrentTable;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @SchName NVARCHAR(128) = PARSENAME(@CurrentTable, 2);
        DECLARE @TblName NVARCHAR(128) = PARSENAME(@CurrentTable, 1);
        
        INSERT INTO @Output (Line) VALUES ('## ' + @CurrentTable);
        INSERT INTO @Output (Line) VALUES ('');
        
        -- Table description
        DECLARE @TableDesc NVARCHAR(MAX);
        SELECT @TableDesc = CAST(ep.value AS NVARCHAR(MAX))
        FROM sys.tables t
        INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
        LEFT JOIN sys.extended_properties ep ON t.object_id = ep.major_id AND ep.minor_id = 0 AND ep.name = 'MS_Description'
        WHERE s.name = @SchName AND t.name = @TblName;
        
        IF @TableDesc IS NOT NULL
            INSERT INTO @Output (Line) VALUES (@TableDesc), ('');
        
        -- Columns header
        INSERT INTO @Output (Line) VALUES ('### Columns');
        INSERT INTO @Output (Line) VALUES ('');
        INSERT INTO @Output (Line) VALUES ('| Column | Type | Nullable | Key | Description |');
        INSERT INTO @Output (Line) VALUES ('|--------|------|----------|-----|-------------|');
        
        -- Column rows
        INSERT INTO @Output (Line)
        SELECT '| ' + c.name + ' | ' + 
            TYPE_NAME(c.user_type_id) + 
            CASE WHEN TYPE_NAME(c.user_type_id) IN ('varchar', 'nvarchar') THEN '(' + 
                CASE c.max_length WHEN -1 THEN 'MAX' ELSE CAST(c.max_length AS VARCHAR(10)) END + ')' ELSE '' END +
            ' | ' + CASE c.is_nullable WHEN 1 THEN 'Yes' ELSE 'No' END +
            ' | ' + CASE WHEN pk.column_id IS NOT NULL THEN 'PK' WHEN fk.parent_column_id IS NOT NULL THEN 'FK' ELSE '' END +
            ' | ' + ISNULL(CAST(ep.value AS NVARCHAR(500)), '') + ' |'
        FROM sys.tables t
        INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
        INNER JOIN sys.columns c ON t.object_id = c.object_id
        LEFT JOIN sys.extended_properties ep ON c.object_id = ep.major_id AND c.column_id = ep.minor_id AND ep.name = 'MS_Description'
        LEFT JOIN (
            SELECT ic.object_id, ic.column_id FROM sys.index_columns ic
            INNER JOIN sys.indexes i ON ic.object_id = i.object_id AND ic.index_id = i.index_id
            WHERE i.is_primary_key = 1
        ) pk ON c.object_id = pk.object_id AND c.column_id = pk.column_id
        LEFT JOIN sys.foreign_key_columns fk ON c.object_id = fk.parent_object_id AND c.column_id = fk.parent_column_id
        WHERE s.name = @SchName AND t.name = @TblName
        ORDER BY c.column_id;
        
        INSERT INTO @Output (Line) VALUES ('');
        
        -- Indexes
        IF @IncludeIndexes = 1
        BEGIN
            INSERT INTO @Output (Line) VALUES ('### Indexes');
            INSERT INTO @Output (Line) VALUES ('');
            
            INSERT INTO @Output (Line)
            SELECT '- **' + i.name + '**: ' + 
                CASE WHEN i.is_primary_key = 1 THEN 'Primary Key' 
                     WHEN i.is_unique = 1 THEN 'Unique' 
                     ELSE 'Non-Unique' END +
                ' (' + STRING_AGG(c.name, ', ') WITHIN GROUP (ORDER BY ic.key_ordinal) + ')'
            FROM sys.indexes i
            INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
            INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
            INNER JOIN sys.tables t ON i.object_id = t.object_id
            INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
            WHERE s.name = @SchName AND t.name = @TblName AND i.name IS NOT NULL
            GROUP BY i.name, i.is_primary_key, i.is_unique;
            
            INSERT INTO @Output (Line) VALUES ('');
        END
        
        -- Foreign keys
        IF @IncludeForeignKeys = 1
        BEGIN
            IF EXISTS (SELECT 1 FROM sys.foreign_keys fk
                       INNER JOIN sys.tables t ON fk.parent_object_id = t.object_id
                       INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
                       WHERE s.name = @SchName AND t.name = @TblName)
            BEGIN
                INSERT INTO @Output (Line) VALUES ('### Foreign Keys');
                INSERT INTO @Output (Line) VALUES ('');
                
                INSERT INTO @Output (Line)
                SELECT '- **' + fk.name + '**: ' + 
                    COL_NAME(fkc.parent_object_id, fkc.parent_column_id) + ' -> ' +
                    OBJECT_SCHEMA_NAME(fkc.referenced_object_id) + '.' + 
                    OBJECT_NAME(fkc.referenced_object_id) + '.' +
                    COL_NAME(fkc.referenced_object_id, fkc.referenced_column_id)
                FROM sys.foreign_keys fk
                INNER JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
                INNER JOIN sys.tables t ON fk.parent_object_id = t.object_id
                INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
                WHERE s.name = @SchName AND t.name = @TblName;
                
                INSERT INTO @Output (Line) VALUES ('');
            END
        END
        
        INSERT INTO @Output (Line) VALUES ('---');
        INSERT INTO @Output (Line) VALUES ('');
        
        FETCH NEXT FROM TableCursor INTO @CurrentTable;
    END
    
    CLOSE TableCursor;
    DEALLOCATE TableCursor;
    
    -- Return as single string
    SELECT Line FROM @Output ORDER BY LineNum;
END
GO

-- Document stored procedures
CREATE PROCEDURE dbo.DocumentStoredProcedures
    @SchemaName NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        s.name AS SchemaName,
        p.name AS ProcedureName,
        ISNULL(CAST(ep.value AS NVARCHAR(MAX)), '') AS Description,
        p.create_date AS CreatedDate,
        p.modify_date AS ModifiedDate,
        (
            SELECT STRING_AGG(
                par.name + ' ' + TYPE_NAME(par.user_type_id) + 
                CASE WHEN par.is_output = 1 THEN ' OUTPUT' ELSE '' END,
                ', '
            )
            FROM sys.parameters par
            WHERE par.object_id = p.object_id AND par.parameter_id > 0
        ) AS Parameters,
        m.definition AS SourceCode
    FROM sys.procedures p
    INNER JOIN sys.schemas s ON p.schema_id = s.schema_id
    INNER JOIN sys.sql_modules m ON p.object_id = m.object_id
    LEFT JOIN sys.extended_properties ep ON p.object_id = ep.major_id AND ep.minor_id = 0 AND ep.name = 'MS_Description'
    WHERE @SchemaName IS NULL OR s.name = @SchemaName
    ORDER BY s.name, p.name;
END
GO

-- Generate relationship diagram data (for visualization tools)
CREATE PROCEDURE dbo.GenerateRelationshipData
    @SchemaName NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Tables (nodes)
    SELECT 
        'Table' AS NodeType,
        s.name AS SchemaName,
        t.name AS TableName,
        s.name + '.' + t.name AS FullName,
        (SELECT COUNT(*) FROM sys.columns c WHERE c.object_id = t.object_id) AS ColumnCount,
        (SELECT SUM(p.rows) FROM sys.partitions p WHERE p.object_id = t.object_id AND p.index_id IN (0,1)) AS RowCount
    FROM sys.tables t
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE @SchemaName IS NULL OR s.name = @SchemaName;
    
    -- Foreign keys (edges)
    SELECT 
        'Relationship' AS EdgeType,
        fk.name AS RelationshipName,
        OBJECT_SCHEMA_NAME(fk.parent_object_id) + '.' + OBJECT_NAME(fk.parent_object_id) AS FromTable,
        COL_NAME(fkc.parent_object_id, fkc.parent_column_id) AS FromColumn,
        OBJECT_SCHEMA_NAME(fk.referenced_object_id) + '.' + OBJECT_NAME(fk.referenced_object_id) AS ToTable,
        COL_NAME(fkc.referenced_object_id, fkc.referenced_column_id) AS ToColumn,
        CASE fk.delete_referential_action 
            WHEN 0 THEN 'No Action' WHEN 1 THEN 'Cascade' 
            WHEN 2 THEN 'Set Null' WHEN 3 THEN 'Set Default' 
        END AS OnDelete,
        CASE fk.update_referential_action 
            WHEN 0 THEN 'No Action' WHEN 1 THEN 'Cascade' 
            WHEN 2 THEN 'Set Null' WHEN 3 THEN 'Set Default' 
        END AS OnUpdate
    FROM sys.foreign_keys fk
    INNER JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
    WHERE @SchemaName IS NULL 
       OR OBJECT_SCHEMA_NAME(fk.parent_object_id) = @SchemaName
       OR OBJECT_SCHEMA_NAME(fk.referenced_object_id) = @SchemaName;
END
GO
