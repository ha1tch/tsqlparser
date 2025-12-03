-- Sample 078: Database Dependency Analysis
-- Source: Microsoft Learn, MSSQLTips, Red Gate patterns
-- Category: Reporting
-- Complexity: Complex
-- Features: sys.sql_expression_dependencies, object dependencies, impact analysis

-- Get all dependencies for an object
CREATE PROCEDURE dbo.GetObjectDependencies
    @SchemaName NVARCHAR(128) = 'dbo',
    @ObjectName NVARCHAR(128),
    @ShowReferencedBy BIT = 1,
    @ShowReferences BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @ObjectId INT = OBJECT_ID(QUOTENAME(@SchemaName) + '.' + QUOTENAME(@ObjectName));
    
    IF @ObjectId IS NULL
    BEGIN
        RAISERROR('Object not found: %s.%s', 16, 1, @SchemaName, @ObjectName);
        RETURN;
    END
    
    -- Objects this object references (depends on)
    IF @ShowReferences = 1
    BEGIN
        SELECT 
            'References' AS DependencyDirection,
            COALESCE(d.referenced_server_name, '') AS ServerName,
            COALESCE(d.referenced_database_name, DB_NAME()) AS DatabaseName,
            COALESCE(d.referenced_schema_name, 'dbo') AS SchemaName,
            d.referenced_entity_name AS ObjectName,
            d.referenced_minor_name AS ColumnName,
            d.referenced_class_desc AS ObjectClass,
            d.is_ambiguous AS IsAmbiguous,
            d.is_caller_dependent AS IsCallerDependent
        FROM sys.sql_expression_dependencies d
        WHERE d.referencing_id = @ObjectId
        ORDER BY DatabaseName, SchemaName, ObjectName;
    END
    
    -- Objects that reference this object (dependent on this)
    IF @ShowReferencedBy = 1
    BEGIN
        SELECT 
            'Referenced By' AS DependencyDirection,
            OBJECT_SCHEMA_NAME(d.referencing_id) AS SchemaName,
            OBJECT_NAME(d.referencing_id) AS ObjectName,
            o.type_desc AS ObjectType,
            d.referencing_minor_id AS MinorId,
            COL_NAME(d.referencing_id, d.referencing_minor_id) AS ColumnName,
            d.is_ambiguous AS IsAmbiguous
        FROM sys.sql_expression_dependencies d
        INNER JOIN sys.objects o ON d.referencing_id = o.object_id
        WHERE d.referenced_id = @ObjectId
        ORDER BY SchemaName, ObjectName;
    END
END
GO

-- Build complete dependency tree
CREATE PROCEDURE dbo.BuildDependencyTree
    @SchemaName NVARCHAR(128) = 'dbo',
    @ObjectName NVARCHAR(128),
    @Direction NVARCHAR(10) = 'BOTH',  -- UP (what depends on this), DOWN (what this depends on), BOTH
    @MaxDepth INT = 5
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @ObjectId INT = OBJECT_ID(QUOTENAME(@SchemaName) + '.' + QUOTENAME(@ObjectName));
    
    -- Downstream dependencies (what this object depends on)
    IF @Direction IN ('DOWN', 'BOTH')
    BEGIN
        ;WITH DownstreamDeps AS (
            SELECT 
                d.referencing_id AS ObjectId,
                d.referenced_id AS DependsOnId,
                OBJECT_SCHEMA_NAME(d.referencing_id) AS SchemaName,
                OBJECT_NAME(d.referencing_id) AS ObjectName,
                COALESCE(d.referenced_schema_name, 'dbo') AS DependsOnSchema,
                d.referenced_entity_name AS DependsOnObject,
                1 AS Level,
                CAST(QUOTENAME(@SchemaName) + '.' + QUOTENAME(@ObjectName) + ' -> ' + 
                     QUOTENAME(COALESCE(d.referenced_schema_name, 'dbo')) + '.' + 
                     QUOTENAME(d.referenced_entity_name) AS NVARCHAR(MAX)) AS DependencyPath
            FROM sys.sql_expression_dependencies d
            WHERE d.referencing_id = @ObjectId
              AND d.referenced_id IS NOT NULL
            
            UNION ALL
            
            SELECT 
                d.referencing_id,
                d.referenced_id,
                OBJECT_SCHEMA_NAME(d.referencing_id),
                OBJECT_NAME(d.referencing_id),
                COALESCE(d.referenced_schema_name, 'dbo'),
                d.referenced_entity_name,
                dd.Level + 1,
                CAST(dd.DependencyPath + ' -> ' + 
                     QUOTENAME(COALESCE(d.referenced_schema_name, 'dbo')) + '.' + 
                     QUOTENAME(d.referenced_entity_name) AS NVARCHAR(MAX))
            FROM sys.sql_expression_dependencies d
            INNER JOIN DownstreamDeps dd ON d.referencing_id = dd.DependsOnId
            WHERE dd.Level < @MaxDepth
              AND d.referenced_id IS NOT NULL
        )
        SELECT DISTINCT
            'Downstream' AS Direction,
            Level,
            DependsOnSchema AS SchemaName,
            DependsOnObject AS ObjectName,
            DependencyPath
        FROM DownstreamDeps
        ORDER BY Level, DependsOnSchema, DependsOnObject;
    END
    
    -- Upstream dependencies (what depends on this object)
    IF @Direction IN ('UP', 'BOTH')
    BEGIN
        ;WITH UpstreamDeps AS (
            SELECT 
                d.referencing_id AS DependentId,
                d.referenced_id AS ObjectId,
                OBJECT_SCHEMA_NAME(d.referencing_id) AS DependentSchema,
                OBJECT_NAME(d.referencing_id) AS DependentObject,
                1 AS Level,
                CAST(QUOTENAME(OBJECT_SCHEMA_NAME(d.referencing_id)) + '.' + 
                     QUOTENAME(OBJECT_NAME(d.referencing_id)) + ' -> ' + 
                     QUOTENAME(@SchemaName) + '.' + QUOTENAME(@ObjectName) AS NVARCHAR(MAX)) AS DependencyPath
            FROM sys.sql_expression_dependencies d
            WHERE d.referenced_id = @ObjectId
            
            UNION ALL
            
            SELECT 
                d.referencing_id,
                d.referenced_id,
                OBJECT_SCHEMA_NAME(d.referencing_id),
                OBJECT_NAME(d.referencing_id),
                ud.Level + 1,
                CAST(QUOTENAME(OBJECT_SCHEMA_NAME(d.referencing_id)) + '.' + 
                     QUOTENAME(OBJECT_NAME(d.referencing_id)) + ' -> ' + ud.DependencyPath AS NVARCHAR(MAX))
            FROM sys.sql_expression_dependencies d
            INNER JOIN UpstreamDeps ud ON d.referenced_id = ud.DependentId
            WHERE ud.Level < @MaxDepth
        )
        SELECT DISTINCT
            'Upstream' AS Direction,
            Level,
            DependentSchema AS SchemaName,
            DependentObject AS ObjectName,
            DependencyPath
        FROM UpstreamDeps
        ORDER BY Level, DependentSchema, DependentObject;
    END
END
GO

-- Analyze impact of dropping an object
CREATE PROCEDURE dbo.AnalyzeDropImpact
    @SchemaName NVARCHAR(128) = 'dbo',
    @ObjectName NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @ObjectId INT = OBJECT_ID(QUOTENAME(@SchemaName) + '.' + QUOTENAME(@ObjectName));
    
    -- Objects that would be affected
    SELECT 
        OBJECT_SCHEMA_NAME(d.referencing_id) AS AffectedSchema,
        OBJECT_NAME(d.referencing_id) AS AffectedObject,
        o.type_desc AS ObjectType,
        'Would fail after drop' AS Impact,
        m.definition AS ObjectDefinition
    FROM sys.sql_expression_dependencies d
    INNER JOIN sys.objects o ON d.referencing_id = o.object_id
    LEFT JOIN sys.sql_modules m ON o.object_id = m.object_id
    WHERE d.referenced_id = @ObjectId
    ORDER BY o.type_desc, AffectedSchema, AffectedObject;
    
    -- Summary
    SELECT 
        o.type_desc AS ObjectType,
        COUNT(*) AS AffectedCount
    FROM sys.sql_expression_dependencies d
    INNER JOIN sys.objects o ON d.referencing_id = o.object_id
    WHERE d.referenced_id = @ObjectId
    GROUP BY o.type_desc
    ORDER BY AffectedCount DESC;
END
GO

-- Find broken dependencies
CREATE PROCEDURE dbo.FindBrokenDependencies
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        OBJECT_SCHEMA_NAME(d.referencing_id) AS ReferencingSchema,
        OBJECT_NAME(d.referencing_id) AS ReferencingObject,
        o.type_desc AS ReferencingType,
        d.referenced_database_name AS ReferencedDatabase,
        d.referenced_schema_name AS ReferencedSchema,
        d.referenced_entity_name AS ReferencedObject,
        d.referenced_minor_name AS ReferencedColumn,
        'Object not found' AS Issue
    FROM sys.sql_expression_dependencies d
    INNER JOIN sys.objects o ON d.referencing_id = o.object_id
    WHERE d.referenced_id IS NULL
      AND d.referenced_database_name IS NULL  -- Same database
      AND NOT EXISTS (
          SELECT 1 FROM sys.objects 
          WHERE name = d.referenced_entity_name 
            AND SCHEMA_NAME(schema_id) = ISNULL(d.referenced_schema_name, 'dbo')
      )
    ORDER BY ReferencingSchema, ReferencingObject;
END
GO

-- Generate dependency diagram data
CREATE PROCEDURE dbo.GenerateDependencyDiagram
    @SchemaName NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Nodes (objects)
    SELECT DISTINCT
        OBJECT_SCHEMA_NAME(object_id) AS SchemaName,
        name AS ObjectName,
        type_desc AS ObjectType,
        QUOTENAME(OBJECT_SCHEMA_NAME(object_id)) + '.' + QUOTENAME(name) AS NodeId
    FROM sys.objects
    WHERE is_ms_shipped = 0
      AND (@SchemaName IS NULL OR OBJECT_SCHEMA_NAME(object_id) = @SchemaName)
      AND type IN ('U', 'V', 'P', 'FN', 'TF', 'IF', 'TR');
    
    -- Edges (dependencies)
    SELECT 
        QUOTENAME(OBJECT_SCHEMA_NAME(d.referencing_id)) + '.' + QUOTENAME(OBJECT_NAME(d.referencing_id)) AS SourceNode,
        QUOTENAME(COALESCE(d.referenced_schema_name, 'dbo')) + '.' + QUOTENAME(d.referenced_entity_name) AS TargetNode,
        d.referenced_class_desc AS DependencyType
    FROM sys.sql_expression_dependencies d
    INNER JOIN sys.objects o ON d.referencing_id = o.object_id
    WHERE d.referenced_id IS NOT NULL
      AND o.is_ms_shipped = 0
      AND (@SchemaName IS NULL OR OBJECT_SCHEMA_NAME(d.referencing_id) = @SchemaName)
    ORDER BY SourceNode, TargetNode;
END
GO
