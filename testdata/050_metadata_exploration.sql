-- Sample 050: Database Metadata Exploration
-- Source: Microsoft Learn, MSSQLTips, Redgate patterns
-- Category: Reporting
-- Complexity: Complex
-- Features: sys catalog views, INFORMATION_SCHEMA, sp_help alternatives

-- Get comprehensive table information
CREATE PROCEDURE dbo.GetTableInfo
    @SchemaName NVARCHAR(128) = NULL,
    @TableName NVARCHAR(128) = NULL,
    @IncludeSystemTables BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Tables with row counts and sizes
    SELECT 
        s.name AS SchemaName,
        t.name AS TableName,
        t.type_desc AS TableType,
        p.rows AS RowCount,
        CAST(SUM(a.total_pages) * 8.0 / 1024 AS DECIMAL(18,2)) AS TotalSizeMB,
        CAST(SUM(a.used_pages) * 8.0 / 1024 AS DECIMAL(18,2)) AS UsedSizeMB,
        CAST(SUM(a.data_pages) * 8.0 / 1024 AS DECIMAL(18,2)) AS DataSizeMB,
        t.create_date AS CreatedDate,
        t.modify_date AS ModifiedDate,
        OBJECTPROPERTY(t.object_id, 'TableHasPrimaryKey') AS HasPrimaryKey,
        OBJECTPROPERTY(t.object_id, 'TableHasForeignKey') AS HasForeignKey,
        OBJECTPROPERTY(t.object_id, 'TableHasIdentity') AS HasIdentity,
        t.is_tracked_by_cdc AS TrackedByCDC,
        t.temporal_type_desc AS TemporalType
    FROM sys.tables t
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    INNER JOIN sys.partitions p ON t.object_id = p.object_id AND p.index_id IN (0, 1)
    INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
    WHERE (@SchemaName IS NULL OR s.name = @SchemaName)
      AND (@TableName IS NULL OR t.name = @TableName)
      AND (@IncludeSystemTables = 1 OR t.is_ms_shipped = 0)
    GROUP BY s.name, t.name, t.type_desc, p.rows, t.create_date, t.modify_date, 
             t.object_id, t.is_tracked_by_cdc, t.temporal_type_desc
    ORDER BY s.name, t.name;
END
GO

-- Get detailed column information
CREATE PROCEDURE dbo.GetColumnInfo
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        c.column_id AS ColumnOrder,
        c.name AS ColumnName,
        TYPE_NAME(c.user_type_id) AS DataType,
        CASE 
            WHEN TYPE_NAME(c.user_type_id) IN ('varchar', 'nvarchar', 'char', 'nchar')
            THEN CASE WHEN c.max_length = -1 THEN 'MAX' ELSE CAST(c.max_length AS VARCHAR(10)) END
            WHEN TYPE_NAME(c.user_type_id) IN ('decimal', 'numeric')
            THEN CAST(c.precision AS VARCHAR(10)) + ',' + CAST(c.scale AS VARCHAR(10))
            ELSE NULL
        END AS TypeDetail,
        c.is_nullable AS IsNullable,
        c.is_identity AS IsIdentity,
        c.is_computed AS IsComputed,
        cc.definition AS ComputedDefinition,
        dc.definition AS DefaultValue,
        c.is_masked AS IsMasked,
        ep.value AS ColumnDescription,
        ic.is_descending_key AS IndexDescending,
        CASE WHEN pk.column_id IS NOT NULL THEN 1 ELSE 0 END AS IsPrimaryKey,
        CASE WHEN fk.parent_column_id IS NOT NULL THEN 1 ELSE 0 END AS IsForeignKey
    FROM sys.columns c
    INNER JOIN sys.tables t ON c.object_id = t.object_id
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    LEFT JOIN sys.computed_columns cc ON c.object_id = cc.object_id AND c.column_id = cc.column_id
    LEFT JOIN sys.default_constraints dc ON c.default_object_id = dc.object_id
    LEFT JOIN sys.extended_properties ep ON c.object_id = ep.major_id AND c.column_id = ep.minor_id AND ep.name = 'MS_Description'
    LEFT JOIN sys.index_columns ic ON c.object_id = ic.object_id AND c.column_id = ic.column_id AND ic.index_id = 1
    LEFT JOIN (
        SELECT ic.object_id, ic.column_id
        FROM sys.index_columns ic
        INNER JOIN sys.indexes i ON ic.object_id = i.object_id AND ic.index_id = i.index_id
        WHERE i.is_primary_key = 1
    ) pk ON c.object_id = pk.object_id AND c.column_id = pk.column_id
    LEFT JOIN sys.foreign_key_columns fk ON c.object_id = fk.parent_object_id AND c.column_id = fk.parent_column_id
    WHERE s.name = @SchemaName AND t.name = @TableName
    ORDER BY c.column_id;
END
GO

-- Get index information
CREATE PROCEDURE dbo.GetIndexInfo
    @SchemaName NVARCHAR(128) = NULL,
    @TableName NVARCHAR(128) = NULL,
    @IncludeUnused BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        s.name AS SchemaName,
        t.name AS TableName,
        i.name AS IndexName,
        i.type_desc AS IndexType,
        i.is_unique AS IsUnique,
        i.is_primary_key AS IsPrimaryKey,
        i.is_unique_constraint AS IsUniqueConstraint,
        STRING_AGG(c.name, ', ') WITHIN GROUP (ORDER BY ic.key_ordinal) AS KeyColumns,
        STRING_AGG(CASE WHEN ic.is_included_column = 1 THEN c.name END, ', ') AS IncludedColumns,
        ISNULL(ps.used_page_count * 8.0 / 1024, 0) AS IndexSizeMB,
        us.user_seeks + us.user_scans + us.user_lookups AS TotalReads,
        us.user_updates AS TotalWrites,
        us.last_user_seek AS LastSeek,
        us.last_user_scan AS LastScan,
        i.fill_factor AS FillFactor,
        i.is_disabled AS IsDisabled,
        i.filter_definition AS FilterDefinition
    FROM sys.indexes i
    INNER JOIN sys.tables t ON i.object_id = t.object_id
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    LEFT JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
    LEFT JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
    LEFT JOIN sys.dm_db_index_usage_stats us ON i.object_id = us.object_id AND i.index_id = us.index_id AND us.database_id = DB_ID()
    LEFT JOIN sys.dm_db_partition_stats ps ON i.object_id = ps.object_id AND i.index_id = ps.index_id
    WHERE i.type > 0  -- Exclude heaps
      AND (@SchemaName IS NULL OR s.name = @SchemaName)
      AND (@TableName IS NULL OR t.name = @TableName)
      AND (@IncludeUnused = 1 OR ISNULL(us.user_seeks + us.user_scans + us.user_lookups, 0) > 0)
    GROUP BY s.name, t.name, i.name, i.type_desc, i.is_unique, i.is_primary_key, 
             i.is_unique_constraint, ps.used_page_count, us.user_seeks, us.user_scans, 
             us.user_lookups, us.user_updates, us.last_user_seek, us.last_user_scan,
             i.fill_factor, i.is_disabled, i.filter_definition
    ORDER BY s.name, t.name, i.index_id;
END
GO

-- Get foreign key relationships
CREATE PROCEDURE dbo.GetForeignKeyInfo
    @SchemaName NVARCHAR(128) = NULL,
    @TableName NVARCHAR(128) = NULL,
    @IncludeIncoming BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Outgoing FKs (this table references others)
    SELECT 
        'Outgoing' AS Direction,
        fk.name AS ForeignKeyName,
        OBJECT_SCHEMA_NAME(fk.parent_object_id) AS FromSchema,
        OBJECT_NAME(fk.parent_object_id) AS FromTable,
        STRING_AGG(pc.name, ', ') AS FromColumns,
        OBJECT_SCHEMA_NAME(fk.referenced_object_id) AS ToSchema,
        OBJECT_NAME(fk.referenced_object_id) AS ToTable,
        STRING_AGG(rc.name, ', ') AS ToColumns,
        fk.delete_referential_action_desc AS OnDelete,
        fk.update_referential_action_desc AS OnUpdate,
        fk.is_disabled AS IsDisabled,
        fk.is_not_trusted AS IsNotTrusted
    FROM sys.foreign_keys fk
    INNER JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
    INNER JOIN sys.columns pc ON fkc.parent_object_id = pc.object_id AND fkc.parent_column_id = pc.column_id
    INNER JOIN sys.columns rc ON fkc.referenced_object_id = rc.object_id AND fkc.referenced_column_id = rc.column_id
    WHERE (@SchemaName IS NULL OR OBJECT_SCHEMA_NAME(fk.parent_object_id) = @SchemaName)
      AND (@TableName IS NULL OR OBJECT_NAME(fk.parent_object_id) = @TableName)
    GROUP BY fk.name, fk.parent_object_id, fk.referenced_object_id, 
             fk.delete_referential_action_desc, fk.update_referential_action_desc,
             fk.is_disabled, fk.is_not_trusted
    
    UNION ALL
    
    -- Incoming FKs (other tables reference this one)
    SELECT 
        'Incoming' AS Direction,
        fk.name AS ForeignKeyName,
        OBJECT_SCHEMA_NAME(fk.parent_object_id) AS FromSchema,
        OBJECT_NAME(fk.parent_object_id) AS FromTable,
        STRING_AGG(pc.name, ', ') AS FromColumns,
        OBJECT_SCHEMA_NAME(fk.referenced_object_id) AS ToSchema,
        OBJECT_NAME(fk.referenced_object_id) AS ToTable,
        STRING_AGG(rc.name, ', ') AS ToColumns,
        fk.delete_referential_action_desc AS OnDelete,
        fk.update_referential_action_desc AS OnUpdate,
        fk.is_disabled AS IsDisabled,
        fk.is_not_trusted AS IsNotTrusted
    FROM sys.foreign_keys fk
    INNER JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
    INNER JOIN sys.columns pc ON fkc.parent_object_id = pc.object_id AND fkc.parent_column_id = pc.column_id
    INNER JOIN sys.columns rc ON fkc.referenced_object_id = rc.object_id AND fkc.referenced_column_id = rc.column_id
    WHERE @IncludeIncoming = 1
      AND (@SchemaName IS NULL OR OBJECT_SCHEMA_NAME(fk.referenced_object_id) = @SchemaName)
      AND (@TableName IS NULL OR OBJECT_NAME(fk.referenced_object_id) = @TableName)
    GROUP BY fk.name, fk.parent_object_id, fk.referenced_object_id,
             fk.delete_referential_action_desc, fk.update_referential_action_desc,
             fk.is_disabled, fk.is_not_trusted
    ORDER BY Direction, FromTable;
END
GO

-- Get stored procedure information
CREATE PROCEDURE dbo.GetProcedureInfo
    @SchemaName NVARCHAR(128) = NULL,
    @ProcedureName NVARCHAR(128) = NULL,
    @SearchText NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        s.name AS SchemaName,
        p.name AS ProcedureName,
        p.type_desc AS ObjectType,
        p.create_date AS CreatedDate,
        p.modify_date AS ModifiedDate,
        ISNULL(ps.execution_count, 0) AS ExecutionCount,
        ISNULL(ps.total_elapsed_time / 1000000.0, 0) AS TotalElapsedSec,
        ISNULL(ps.total_worker_time / 1000000.0, 0) AS TotalCPUSec,
        ISNULL(ps.total_logical_reads, 0) AS TotalLogicalReads,
        LEN(m.definition) AS DefinitionLength,
        ep.value AS Description
    FROM sys.procedures p
    INNER JOIN sys.schemas s ON p.schema_id = s.schema_id
    LEFT JOIN sys.sql_modules m ON p.object_id = m.object_id
    LEFT JOIN sys.dm_exec_procedure_stats ps ON p.object_id = ps.object_id
    LEFT JOIN sys.extended_properties ep ON p.object_id = ep.major_id AND ep.minor_id = 0 AND ep.name = 'MS_Description'
    WHERE (@SchemaName IS NULL OR s.name = @SchemaName)
      AND (@ProcedureName IS NULL OR p.name LIKE '%' + @ProcedureName + '%')
      AND (@SearchText IS NULL OR m.definition LIKE '%' + @SearchText + '%')
    ORDER BY s.name, p.name;
END
GO

-- Generate CREATE script for table
CREATE PROCEDURE dbo.GenerateTableScript
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX) = '';
    DECLARE @FullPath NVARCHAR(256) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    
    -- Table definition
    SET @SQL = 'CREATE TABLE ' + @FullPath + ' (' + CHAR(13) + CHAR(10);
    
    SELECT @SQL = @SQL + '    ' + QUOTENAME(c.name) + ' ' +
        TYPE_NAME(c.user_type_id) +
        CASE 
            WHEN TYPE_NAME(c.user_type_id) IN ('varchar', 'nvarchar', 'char', 'nchar')
            THEN '(' + CASE WHEN c.max_length = -1 THEN 'MAX' ELSE CAST(c.max_length AS VARCHAR(10)) END + ')'
            WHEN TYPE_NAME(c.user_type_id) IN ('decimal', 'numeric')
            THEN '(' + CAST(c.precision AS VARCHAR(10)) + ',' + CAST(c.scale AS VARCHAR(10)) + ')'
            ELSE ''
        END +
        CASE WHEN c.is_identity = 1 THEN ' IDENTITY(' + CAST(IDENT_SEED(@FullPath) AS VARCHAR(20)) + ',' + CAST(IDENT_INCR(@FullPath) AS VARCHAR(20)) + ')' ELSE '' END +
        CASE WHEN c.is_nullable = 0 THEN ' NOT NULL' ELSE ' NULL' END +
        ISNULL(' DEFAULT ' + dc.definition, '') +
        ',' + CHAR(13) + CHAR(10)
    FROM sys.columns c
    LEFT JOIN sys.default_constraints dc ON c.default_object_id = dc.object_id
    WHERE c.object_id = OBJECT_ID(@FullPath)
    ORDER BY c.column_id;
    
    -- Remove trailing comma
    SET @SQL = LEFT(@SQL, LEN(@SQL) - 3) + CHAR(13) + CHAR(10) + ');';
    
    SELECT @SQL AS CreateTableScript;
END
GO
