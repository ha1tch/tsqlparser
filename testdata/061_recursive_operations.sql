-- Sample 061: Advanced Recursive Operations
-- Source: Itzik Ben-Gan, Microsoft Learn, MSSQLTips
-- Category: Hierarchy/Recursion
-- Complexity: Advanced
-- Features: Recursive CTEs, tree traversal, materialized path, nested sets

-- Get full path for hierarchy node
CREATE PROCEDURE dbo.GetHierarchyPath
    @TableName NVARCHAR(128),
    @SchemaName NVARCHAR(128) = 'dbo',
    @IdColumn NVARCHAR(128) = 'ID',
    @ParentIdColumn NVARCHAR(128) = 'ParentID',
    @NameColumn NVARCHAR(128) = 'Name',
    @Delimiter NVARCHAR(10) = ' > '
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    
    SET @SQL = N'
        ;WITH Hierarchy AS (
            SELECT 
                ' + QUOTENAME(@IdColumn) + ' AS NodeID,
                ' + QUOTENAME(@ParentIdColumn) + ' AS ParentID,
                CAST(' + QUOTENAME(@NameColumn) + ' AS NVARCHAR(MAX)) AS NodePath,
                0 AS Level
            FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + '
            WHERE ' + QUOTENAME(@ParentIdColumn) + ' IS NULL
            
            UNION ALL
            
            SELECT 
                c.' + QUOTENAME(@IdColumn) + ',
                c.' + QUOTENAME(@ParentIdColumn) + ',
                CAST(h.NodePath + @Delim + c.' + QUOTENAME(@NameColumn) + ' AS NVARCHAR(MAX)),
                h.Level + 1
            FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + ' c
            INNER JOIN Hierarchy h ON c.' + QUOTENAME(@ParentIdColumn) + ' = h.NodeID
            WHERE h.Level < 20
        )
        SELECT 
            NodeID,
            ParentID,
            Level,
            NodePath,
            REPLICATE(''  '', Level) + RIGHT(NodePath, CHARINDEX(@Delim, REVERSE(NodePath) + @Delim) - LEN(@Delim) - 1) AS TreeView
        FROM Hierarchy
        ORDER BY NodePath';
    
    EXEC sp_executesql @SQL, N'@Delim NVARCHAR(10)', @Delim = @Delimiter;
END
GO

-- Get all descendants of a node
CREATE PROCEDURE dbo.GetAllDescendants
    @TableName NVARCHAR(128),
    @SchemaName NVARCHAR(128) = 'dbo',
    @IdColumn NVARCHAR(128) = 'ID',
    @ParentIdColumn NVARCHAR(128) = 'ParentID',
    @RootNodeId INT,
    @IncludeRoot BIT = 0,
    @MaxDepth INT = 20
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    
    SET @SQL = N'
        ;WITH Descendants AS (
            SELECT 
                ' + QUOTENAME(@IdColumn) + ' AS NodeID,
                ' + QUOTENAME(@ParentIdColumn) + ' AS ParentID,
                0 AS Depth
            FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + '
            WHERE ' + QUOTENAME(@IdColumn) + ' = @RootID
            
            UNION ALL
            
            SELECT 
                c.' + QUOTENAME(@IdColumn) + ',
                c.' + QUOTENAME(@ParentIdColumn) + ',
                d.Depth + 1
            FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + ' c
            INNER JOIN Descendants d ON c.' + QUOTENAME(@ParentIdColumn) + ' = d.NodeID
            WHERE d.Depth < @MaxD
        )
        SELECT t.*
        FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + ' t
        INNER JOIN Descendants d ON t.' + QUOTENAME(@IdColumn) + ' = d.NodeID
        WHERE @IncRoot = 1 OR d.Depth > 0
        ORDER BY d.Depth, t.' + QUOTENAME(@IdColumn);
    
    EXEC sp_executesql @SQL,
        N'@RootID INT, @MaxD INT, @IncRoot BIT',
        @RootID = @RootNodeId, @MaxD = @MaxDepth, @IncRoot = @IncludeRoot;
END
GO

-- Get all ancestors of a node
CREATE PROCEDURE dbo.GetAllAncestors
    @TableName NVARCHAR(128),
    @SchemaName NVARCHAR(128) = 'dbo',
    @IdColumn NVARCHAR(128) = 'ID',
    @ParentIdColumn NVARCHAR(128) = 'ParentID',
    @NodeId INT,
    @IncludeSelf BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    
    SET @SQL = N'
        ;WITH Ancestors AS (
            SELECT 
                ' + QUOTENAME(@IdColumn) + ' AS NodeID,
                ' + QUOTENAME(@ParentIdColumn) + ' AS ParentID,
                0 AS Depth
            FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + '
            WHERE ' + QUOTENAME(@IdColumn) + ' = @NodeID
            
            UNION ALL
            
            SELECT 
                p.' + QUOTENAME(@IdColumn) + ',
                p.' + QUOTENAME(@ParentIdColumn) + ',
                a.Depth + 1
            FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + ' p
            INNER JOIN Ancestors a ON p.' + QUOTENAME(@IdColumn) + ' = a.ParentID
            WHERE a.Depth < 50
        )
        SELECT t.*, a.Depth
        FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + ' t
        INNER JOIN Ancestors a ON t.' + QUOTENAME(@IdColumn) + ' = a.NodeID
        WHERE @IncSelf = 1 OR a.Depth > 0
        ORDER BY a.Depth DESC';
    
    EXEC sp_executesql @SQL,
        N'@NodeID INT, @IncSelf BIT',
        @NodeID = @NodeId, @IncSelf = @IncludeSelf;
END
GO

-- Move node to new parent
CREATE PROCEDURE dbo.MoveHierarchyNode
    @TableName NVARCHAR(128),
    @SchemaName NVARCHAR(128) = 'dbo',
    @IdColumn NVARCHAR(128) = 'ID',
    @ParentIdColumn NVARCHAR(128) = 'ParentID',
    @NodeId INT,
    @NewParentId INT,
    @ValidateNoCycle BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @WouldCycle BIT = 0;
    
    -- Check for cycle (moving node under its own descendant)
    IF @ValidateNoCycle = 1
    BEGIN
        SET @SQL = N'
            ;WITH Descendants AS (
                SELECT ' + QUOTENAME(@IdColumn) + ' AS NodeID
                FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + '
                WHERE ' + QUOTENAME(@IdColumn) + ' = @Node
                
                UNION ALL
                
                SELECT c.' + QUOTENAME(@IdColumn) + '
                FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + ' c
                INNER JOIN Descendants d ON c.' + QUOTENAME(@ParentIdColumn) + ' = d.NodeID
            )
            SELECT @Cycle = 1 WHERE EXISTS (SELECT 1 FROM Descendants WHERE NodeID = @NewPar)';
        
        EXEC sp_executesql @SQL,
            N'@Node INT, @NewPar INT, @Cycle BIT OUTPUT',
            @Node = @NodeId, @NewPar = @NewParentId, @Cycle = @WouldCycle OUTPUT;
        
        IF @WouldCycle = 1
        BEGIN
            RAISERROR('Cannot move node: would create a cycle in the hierarchy', 16, 1);
            RETURN;
        END
    END
    
    -- Perform the move
    SET @SQL = N'
        UPDATE ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + '
        SET ' + QUOTENAME(@ParentIdColumn) + ' = @NewPar
        WHERE ' + QUOTENAME(@IdColumn) + ' = @Node';
    
    EXEC sp_executesql @SQL, N'@Node INT, @NewPar INT', @Node = @NodeId, @NewPar = @NewParentId;
    
    SELECT 'Node moved successfully' AS Status, @NodeId AS NodeId, @NewParentId AS NewParentId;
END
GO

-- Calculate subtree aggregates
CREATE PROCEDURE dbo.CalculateSubtreeAggregates
    @TableName NVARCHAR(128),
    @SchemaName NVARCHAR(128) = 'dbo',
    @IdColumn NVARCHAR(128) = 'ID',
    @ParentIdColumn NVARCHAR(128) = 'ParentID',
    @ValueColumn NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    
    SET @SQL = N'
        ;WITH NodeValues AS (
            SELECT 
                ' + QUOTENAME(@IdColumn) + ' AS NodeID,
                ' + QUOTENAME(@ParentIdColumn) + ' AS ParentID,
                ' + QUOTENAME(@ValueColumn) + ' AS NodeValue
            FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + '
        ),
        SubtreeSums AS (
            SELECT 
                n.NodeID,
                n.ParentID,
                n.NodeValue,
                n.NodeValue AS SubtreeSum
            FROM NodeValues n
            WHERE NOT EXISTS (
                SELECT 1 FROM NodeValues c WHERE c.ParentID = n.NodeID
            )
            
            UNION ALL
            
            SELECT 
                p.NodeID,
                p.ParentID,
                p.NodeValue,
                p.NodeValue + s.SubtreeSum
            FROM NodeValues p
            INNER JOIN SubtreeSums s ON s.ParentID = p.NodeID
        )
        SELECT 
            NodeID,
            ParentID,
            NodeValue,
            SUM(SubtreeSum) AS SubtreeTotal,
            COUNT(*) AS DescendantCount
        FROM SubtreeSums
        GROUP BY NodeID, ParentID, NodeValue
        ORDER BY NodeID';
    
    EXEC sp_executesql @SQL;
END
GO

-- Convert adjacency list to nested sets
CREATE PROCEDURE dbo.ConvertToNestedSets
    @TableName NVARCHAR(128),
    @SchemaName NVARCHAR(128) = 'dbo',
    @IdColumn NVARCHAR(128) = 'ID',
    @ParentIdColumn NVARCHAR(128) = 'ParentID',
    @LeftColumn NVARCHAR(128) = 'Lft',
    @RightColumn NVARCHAR(128) = 'Rgt'
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @Counter INT = 0;
    
    -- Add columns if they don't exist
    SET @SQL = 'IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(''' + 
               @SchemaName + '.' + @TableName + ''') AND name = ''' + @LeftColumn + ''')
                ALTER TABLE ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + 
               ' ADD ' + QUOTENAME(@LeftColumn) + ' INT, ' + QUOTENAME(@RightColumn) + ' INT';
    EXEC sp_executesql @SQL;
    
    -- Use recursive CTE to assign left/right values
    SET @SQL = N'
        ;WITH OrderedTree AS (
            SELECT 
                ' + QUOTENAME(@IdColumn) + ' AS NodeID,
                ' + QUOTENAME(@ParentIdColumn) + ' AS ParentID,
                ROW_NUMBER() OVER (PARTITION BY ' + QUOTENAME(@ParentIdColumn) + ' ORDER BY ' + QUOTENAME(@IdColumn) + ') AS SiblingOrder,
                0 AS Level
            FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + '
            WHERE ' + QUOTENAME(@ParentIdColumn) + ' IS NULL
            
            UNION ALL
            
            SELECT 
                c.' + QUOTENAME(@IdColumn) + ',
                c.' + QUOTENAME(@ParentIdColumn) + ',
                ROW_NUMBER() OVER (PARTITION BY c.' + QUOTENAME(@ParentIdColumn) + ' ORDER BY c.' + QUOTENAME(@IdColumn) + '),
                p.Level + 1
            FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + ' c
            INNER JOIN OrderedTree p ON c.' + QUOTENAME(@ParentIdColumn) + ' = p.NodeID
        ),
        NumberedTree AS (
            SELECT 
                NodeID,
                ParentID,
                Level,
                ROW_NUMBER() OVER (ORDER BY Level, ParentID, SiblingOrder) * 2 - 1 AS Lft
            FROM OrderedTree
        )
        UPDATE t
        SET t.' + QUOTENAME(@LeftColumn) + ' = nt.Lft,
            t.' + QUOTENAME(@RightColumn) + ' = nt.Lft + 1
        FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + ' t
        INNER JOIN NumberedTree nt ON t.' + QUOTENAME(@IdColumn) + ' = nt.NodeID';
    
    EXEC sp_executesql @SQL;
    
    SELECT 'Nested sets values assigned' AS Status;
END
GO
