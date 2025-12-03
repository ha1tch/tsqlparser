-- Sample 036: Graph Queries and Advanced Hierarchies
-- Source: Microsoft Learn, MSSQLTips, Itzik Ben-Gan articles
-- Category: Hierarchy/Recursion
-- Complexity: Advanced
-- Features: Graph tables, MATCH, recursive CTEs, HierarchyID, closure tables

-- Recursive CTE for organization hierarchy with multiple calculations
CREATE PROCEDURE dbo.GetOrganizationHierarchy
    @RootEmployeeID INT = NULL,
    @MaxDepth INT = 10,
    @IncludeInactive BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    ;WITH OrgHierarchy AS (
        -- Anchor: Top-level employees (or specific root)
        SELECT 
            e.EmployeeID,
            e.EmployeeName,
            e.ManagerID,
            e.Title,
            e.Department,
            e.Salary,
            e.HireDate,
            e.IsActive,
            0 AS Level,
            CAST(e.EmployeeName AS NVARCHAR(MAX)) AS HierarchyPath,
            CAST(RIGHT('000000' + CAST(e.EmployeeID AS VARCHAR(6)), 6) AS VARCHAR(MAX)) AS SortPath,
            1 AS DirectReports,
            e.Salary AS SubtreeSalary
        FROM dbo.Employees e
        WHERE (@RootEmployeeID IS NULL AND e.ManagerID IS NULL)
           OR e.EmployeeID = @RootEmployeeID
        
        UNION ALL
        
        -- Recursive: subordinates
        SELECT 
            e.EmployeeID,
            e.EmployeeName,
            e.ManagerID,
            e.Title,
            e.Department,
            e.Salary,
            e.HireDate,
            e.IsActive,
            h.Level + 1,
            h.HierarchyPath + ' > ' + e.EmployeeName,
            h.SortPath + '/' + RIGHT('000000' + CAST(e.EmployeeID AS VARCHAR(6)), 6),
            1,
            e.Salary
        FROM dbo.Employees e
        INNER JOIN OrgHierarchy h ON e.ManagerID = h.EmployeeID
        WHERE h.Level < @MaxDepth
          AND (@IncludeInactive = 1 OR e.IsActive = 1)
    )
    SELECT 
        EmployeeID,
        REPLICATE('    ', Level) + EmployeeName AS DisplayName,
        EmployeeName,
        ManagerID,
        Title,
        Department,
        Salary,
        HireDate,
        IsActive,
        Level AS HierarchyLevel,
        HierarchyPath,
        (SELECT COUNT(*) FROM OrgHierarchy o2 WHERE o2.HierarchyPath LIKE HierarchyPath + ' > %') AS TotalSubordinates,
        (SELECT SUM(Salary) FROM OrgHierarchy o2 WHERE o2.HierarchyPath LIKE HierarchyPath + '%') AS SubtreeTotalSalary
    FROM OrgHierarchy
    ORDER BY SortPath
    OPTION (MAXRECURSION 100);
END
GO

-- Find all paths between two nodes
CREATE PROCEDURE dbo.FindAllPaths
    @StartNodeID INT,
    @EndNodeID INT,
    @MaxPathLength INT = 10
AS
BEGIN
    SET NOCOUNT ON;
    
    ;WITH PathFinder AS (
        -- Start from source
        SELECT 
            @StartNodeID AS CurrentNode,
            CAST(@StartNodeID AS VARCHAR(MAX)) AS Path,
            1 AS PathLength,
            0 AS ReachedEnd
        
        UNION ALL
        
        -- Traverse edges
        SELECT 
            e.ToNodeID,
            p.Path + ' -> ' + CAST(e.ToNodeID AS VARCHAR(10)),
            p.PathLength + 1,
            CASE WHEN e.ToNodeID = @EndNodeID THEN 1 ELSE 0 END
        FROM PathFinder p
        INNER JOIN dbo.Edges e ON p.CurrentNode = e.FromNodeID
        WHERE p.PathLength < @MaxPathLength
          AND p.ReachedEnd = 0
          AND CHARINDEX(CAST(e.ToNodeID AS VARCHAR(10)), p.Path) = 0  -- Prevent cycles
    )
    SELECT 
        Path,
        PathLength,
        'Complete' AS Status
    FROM PathFinder
    WHERE ReachedEnd = 1
    ORDER BY PathLength, Path
    OPTION (MAXRECURSION 1000);
END
GO

-- Bill of Materials explosion (multi-level BOM)
CREATE PROCEDURE dbo.ExplodeBOM
    @ParentProductID INT,
    @Quantity DECIMAL(18,4) = 1,
    @EffectiveDate DATE = NULL,
    @IncludeCosts BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    SET @EffectiveDate = ISNULL(@EffectiveDate, GETDATE());
    
    ;WITH BOMExplosion AS (
        -- Top level
        SELECT 
            b.ParentProductID,
            b.ComponentProductID,
            p.ProductName AS ComponentName,
            b.QuantityRequired,
            b.QuantityRequired * @Quantity AS ExtendedQuantity,
            b.UnitOfMeasure,
            0 AS Level,
            CAST(p.ProductName AS NVARCHAR(MAX)) AS ComponentPath,
            p.UnitCost,
            b.QuantityRequired * @Quantity * ISNULL(p.UnitCost, 0) AS ExtendedCost,
            b.ScrapPercent
        FROM dbo.BillOfMaterials b
        INNER JOIN dbo.Products p ON b.ComponentProductID = p.ProductID
        WHERE b.ParentProductID = @ParentProductID
          AND b.EffectiveDate <= @EffectiveDate
          AND (b.ExpirationDate IS NULL OR b.ExpirationDate > @EffectiveDate)
        
        UNION ALL
        
        -- Subcomponents
        SELECT 
            b.ParentProductID,
            b.ComponentProductID,
            p.ProductName,
            b.QuantityRequired,
            b.QuantityRequired * bom.ExtendedQuantity,
            b.UnitOfMeasure,
            bom.Level + 1,
            bom.ComponentPath + ' > ' + p.ProductName,
            p.UnitCost,
            b.QuantityRequired * bom.ExtendedQuantity * ISNULL(p.UnitCost, 0),
            b.ScrapPercent
        FROM BOMExplosion bom
        INNER JOIN dbo.BillOfMaterials b ON bom.ComponentProductID = b.ParentProductID
        INNER JOIN dbo.Products p ON b.ComponentProductID = p.ProductID
        WHERE b.EffectiveDate <= @EffectiveDate
          AND (b.ExpirationDate IS NULL OR b.ExpirationDate > @EffectiveDate)
          AND bom.Level < 20
    )
    SELECT 
        Level,
        REPLICATE('  ', Level) + ComponentName AS DisplayName,
        ComponentProductID,
        ComponentName,
        QuantityRequired AS QtyPerUnit,
        ExtendedQuantity AS TotalQtyRequired,
        UnitOfMeasure,
        CASE WHEN @IncludeCosts = 1 THEN UnitCost ELSE NULL END AS UnitCost,
        CASE WHEN @IncludeCosts = 1 THEN ExtendedCost ELSE NULL END AS ExtendedCost,
        ScrapPercent,
        ComponentPath
    FROM BOMExplosion
    ORDER BY ComponentPath
    OPTION (MAXRECURSION 100);
    
    -- Summary
    IF @IncludeCosts = 1
    BEGIN
        SELECT 
            SUM(ExtendedCost) AS TotalMaterialCost,
            COUNT(DISTINCT ComponentProductID) AS UniqueComponents,
            MAX(Level) + 1 AS BOMDepth
        FROM BOMExplosion;
    END
END
GO

-- Closure table management for hierarchies
CREATE PROCEDURE dbo.BuildClosureTable
    @SourceTable NVARCHAR(128),
    @IDColumn NVARCHAR(128),
    @ParentColumn NVARCHAR(128),
    @ClosureTable NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    SET @ClosureTable = ISNULL(@ClosureTable, @SourceTable + '_Closure');
    
    -- Create closure table
    SET @SQL = '
        IF OBJECT_ID(''' + @ClosureTable + ''', ''U'') IS NOT NULL
            DROP TABLE ' + QUOTENAME(@ClosureTable) + ';
        
        CREATE TABLE ' + QUOTENAME(@ClosureTable) + ' (
            AncestorID INT NOT NULL,
            DescendantID INT NOT NULL,
            Depth INT NOT NULL,
            PRIMARY KEY (AncestorID, DescendantID)
        );
        CREATE INDEX IX_Descendant ON ' + QUOTENAME(@ClosureTable) + '(DescendantID);';
    
    EXEC sp_executesql @SQL;
    
    -- Populate with recursive CTE
    SET @SQL = '
        ;WITH Hierarchy AS (
            -- Self-reference (depth 0)
            SELECT ' + QUOTENAME(@IDColumn) + ' AS AncestorID,
                   ' + QUOTENAME(@IDColumn) + ' AS DescendantID,
                   0 AS Depth
            FROM ' + QUOTENAME(@SourceTable) + '
            
            UNION ALL
            
            -- Ancestors
            SELECT h.AncestorID,
                   s.' + QUOTENAME(@IDColumn) + ',
                   h.Depth + 1
            FROM Hierarchy h
            INNER JOIN ' + QUOTENAME(@SourceTable) + ' s ON h.DescendantID = s.' + QUOTENAME(@ParentColumn) + '
            WHERE h.Depth < 50
        )
        INSERT INTO ' + QUOTENAME(@ClosureTable) + ' (AncestorID, DescendantID, Depth)
        SELECT AncestorID, DescendantID, Depth
        FROM Hierarchy
        OPTION (MAXRECURSION 100);';
    
    EXEC sp_executesql @SQL;
    
    SELECT 
        @ClosureTable AS ClosureTable,
        (SELECT COUNT(*) FROM sys.tables WHERE name = @ClosureTable) AS Created,
        'Closure table built' AS Status;
END
GO

-- Query using closure table (much faster than recursive CTE for repeated queries)
CREATE PROCEDURE dbo.GetDescendantsFromClosure
    @AncestorID INT,
    @ClosureTable NVARCHAR(128),
    @MaxDepth INT = NULL,
    @IncludeSelf BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    
    SET @SQL = '
        SELECT 
            c.DescendantID,
            c.Depth
        FROM ' + QUOTENAME(@ClosureTable) + ' c
        WHERE c.AncestorID = @AncestorID';
    
    IF @IncludeSelf = 0
        SET @SQL = @SQL + ' AND c.Depth > 0';
    
    IF @MaxDepth IS NOT NULL
        SET @SQL = @SQL + ' AND c.Depth <= @MaxDepth';
    
    SET @SQL = @SQL + ' ORDER BY c.Depth, c.DescendantID';
    
    EXEC sp_executesql @SQL,
        N'@AncestorID INT, @MaxDepth INT',
        @AncestorID = @AncestorID,
        @MaxDepth = @MaxDepth;
END
GO
