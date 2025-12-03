-- Sample 105: Static Recursive CTE Hierarchy Queries
-- Category: Static SQL Equivalents
-- Complexity: Advanced
-- Purpose: Parser testing - recursive CTEs without dynamic SQL
-- Features: Recursive CTE, hierarchy traversal, path construction, level tracking

-- Pattern 1: Simple employee hierarchy (manager/subordinate)
;WITH EmployeeHierarchy AS (
    -- Anchor: Top-level employees (no manager)
    SELECT 
        EmployeeID,
        EmployeeName,
        ManagerID,
        JobTitle,
        0 AS Level,
        CAST(EmployeeName AS NVARCHAR(MAX)) AS HierarchyPath
    FROM dbo.Employees
    WHERE ManagerID IS NULL
    
    UNION ALL
    
    -- Recursive: Employees with managers
    SELECT 
        e.EmployeeID,
        e.EmployeeName,
        e.ManagerID,
        e.JobTitle,
        eh.Level + 1,
        CAST(eh.HierarchyPath + ' > ' + e.EmployeeName AS NVARCHAR(MAX))
    FROM dbo.Employees e
    INNER JOIN EmployeeHierarchy eh ON e.ManagerID = eh.EmployeeID
    WHERE eh.Level < 10  -- Prevent infinite recursion
)
SELECT 
    EmployeeID,
    EmployeeName,
    ManagerID,
    JobTitle,
    Level,
    HierarchyPath,
    REPLICATE('  ', Level) + EmployeeName AS IndentedName
FROM EmployeeHierarchy
ORDER BY HierarchyPath;
GO

-- Pattern 2: Bill of Materials (BOM) explosion
;WITH BOMExplosion AS (
    -- Anchor: Top-level assemblies
    SELECT 
        p.ProductID,
        p.ProductName,
        CAST(NULL AS INT) AS ParentProductID,
        1 AS Quantity,
        0 AS BOMLevel,
        CAST(p.ProductID AS VARCHAR(MAX)) AS ComponentPath,
        p.UnitCost,
        p.UnitCost AS ExtendedCost
    FROM dbo.Products p
    WHERE p.ProductID = 1000  -- Starting product
    
    UNION ALL
    
    -- Recursive: Component parts
    SELECT 
        c.ComponentProductID,
        p.ProductName,
        c.ParentProductID,
        c.Quantity,
        b.BOMLevel + 1,
        CAST(b.ComponentPath + '/' + CAST(c.ComponentProductID AS VARCHAR(10)) AS VARCHAR(MAX)),
        p.UnitCost,
        p.UnitCost * c.Quantity * b.Quantity
    FROM dbo.BOMComponents c
    INNER JOIN BOMExplosion b ON c.ParentProductID = b.ProductID
    INNER JOIN dbo.Products p ON c.ComponentProductID = p.ProductID
    WHERE b.BOMLevel < 15
)
SELECT 
    ProductID,
    ProductName,
    ParentProductID,
    Quantity,
    BOMLevel,
    ComponentPath,
    UnitCost,
    ExtendedCost,
    REPLICATE('  ', BOMLevel) + ProductName AS IndentedProduct
FROM BOMExplosion
ORDER BY ComponentPath;
GO

-- Pattern 3: Category tree with counts
;WITH CategoryTree AS (
    -- Anchor: Root categories
    SELECT 
        CategoryID,
        CategoryName,
        ParentCategoryID,
        0 AS Level,
        CAST(CategoryName AS NVARCHAR(MAX)) AS FullPath,
        CAST(RIGHT('000' + CAST(CategoryID AS VARCHAR(10)), 5) AS VARCHAR(MAX)) AS SortPath
    FROM dbo.Categories
    WHERE ParentCategoryID IS NULL
    
    UNION ALL
    
    -- Recursive: Child categories
    SELECT 
        c.CategoryID,
        c.CategoryName,
        c.ParentCategoryID,
        ct.Level + 1,
        CAST(ct.FullPath + ' / ' + c.CategoryName AS NVARCHAR(MAX)),
        CAST(ct.SortPath + '/' + RIGHT('000' + CAST(c.CategoryID AS VARCHAR(10)), 5) AS VARCHAR(MAX))
    FROM dbo.Categories c
    INNER JOIN CategoryTree ct ON c.ParentCategoryID = ct.CategoryID
    WHERE ct.Level < 10
)
SELECT 
    ct.CategoryID,
    ct.CategoryName,
    ct.ParentCategoryID,
    ct.Level,
    ct.FullPath,
    (SELECT COUNT(*) FROM dbo.Products p WHERE p.CategoryID = ct.CategoryID) AS DirectProducts,
    (
        SELECT COUNT(*) 
        FROM dbo.Products p 
        INNER JOIN CategoryTree ct2 ON p.CategoryID = ct2.CategoryID
        WHERE ct2.FullPath LIKE ct.FullPath + '%'
    ) AS TotalProducts
FROM CategoryTree ct
ORDER BY ct.SortPath;
GO

-- Pattern 4: Ancestor lookup (bottom-up traversal)
;WITH Ancestors AS (
    -- Anchor: Starting node
    SELECT 
        NodeID,
        NodeName,
        ParentNodeID,
        0 AS Level
    FROM dbo.TreeNodes
    WHERE NodeID = 500  -- Starting from this node
    
    UNION ALL
    
    -- Recursive: Parent nodes
    SELECT 
        t.NodeID,
        t.NodeName,
        t.ParentNodeID,
        a.Level - 1
    FROM dbo.TreeNodes t
    INNER JOIN Ancestors a ON t.NodeID = a.ParentNodeID
)
SELECT 
    NodeID,
    NodeName,
    ParentNodeID,
    Level,
    ABS(Level) AS DistanceFromStart
FROM Ancestors
ORDER BY Level;
GO

-- Pattern 5: Find all paths between nodes (graph traversal)
;WITH Paths AS (
    -- Anchor: Starting node
    SELECT 
        FromNode,
        ToNode,
        Weight,
        CAST(CAST(FromNode AS VARCHAR(10)) + '->' + CAST(ToNode AS VARCHAR(10)) AS VARCHAR(MAX)) AS Path,
        Weight AS TotalWeight,
        1 AS Hops
    FROM dbo.GraphEdges
    WHERE FromNode = 1  -- Starting node
    
    UNION ALL
    
    -- Recursive: Traverse edges
    SELECT 
        e.FromNode,
        e.ToNode,
        e.Weight,
        CAST(p.Path + '->' + CAST(e.ToNode AS VARCHAR(10)) AS VARCHAR(MAX)),
        p.TotalWeight + e.Weight,
        p.Hops + 1
    FROM dbo.GraphEdges e
    INNER JOIN Paths p ON e.FromNode = p.ToNode
    WHERE p.Path NOT LIKE '%' + CAST(e.ToNode AS VARCHAR(10)) + '->%'  -- Prevent cycles
    AND p.Hops < 10
)
SELECT 
    Path,
    TotalWeight,
    Hops
FROM Paths
WHERE ToNode = 10  -- Destination node
ORDER BY TotalWeight, Hops;
GO

-- Pattern 6: Running totals in hierarchy
;WITH HierarchyWithTotals AS (
    SELECT 
        DepartmentID,
        DepartmentName,
        ParentDepartmentID,
        Budget,
        0 AS Level,
        CAST(DepartmentID AS VARCHAR(MAX)) AS Path
    FROM dbo.Departments
    WHERE ParentDepartmentID IS NULL
    
    UNION ALL
    
    SELECT 
        d.DepartmentID,
        d.DepartmentName,
        d.ParentDepartmentID,
        d.Budget,
        h.Level + 1,
        CAST(h.Path + '.' + CAST(d.DepartmentID AS VARCHAR(10)) AS VARCHAR(MAX))
    FROM dbo.Departments d
    INNER JOIN HierarchyWithTotals h ON d.ParentDepartmentID = h.DepartmentID
    WHERE h.Level < 10
),
SubtreeTotals AS (
    SELECT 
        h1.DepartmentID,
        h1.DepartmentName,
        h1.Level,
        h1.Budget AS DirectBudget,
        (
            SELECT SUM(h2.Budget)
            FROM HierarchyWithTotals h2
            WHERE h2.Path LIKE h1.Path + '%'
        ) AS SubtreeBudget
    FROM HierarchyWithTotals h1
)
SELECT * FROM SubtreeTotals
ORDER BY DepartmentID;
GO

-- Pattern 7: Date range generation using recursive CTE
;WITH DateRange AS (
    SELECT CAST('2024-01-01' AS DATE) AS DateValue
    
    UNION ALL
    
    SELECT DATEADD(DAY, 1, DateValue)
    FROM DateRange
    WHERE DateValue < '2024-12-31'
)
SELECT 
    DateValue,
    DATENAME(WEEKDAY, DateValue) AS DayName,
    DATEPART(WEEK, DateValue) AS WeekNumber,
    DATENAME(MONTH, DateValue) AS MonthName,
    CASE WHEN DATENAME(WEEKDAY, DateValue) IN ('Saturday', 'Sunday') THEN 1 ELSE 0 END AS IsWeekend
FROM DateRange
OPTION (MAXRECURSION 400);
GO

-- Pattern 8: Number sequence generation
;WITH Numbers AS (
    SELECT 1 AS N
    
    UNION ALL
    
    SELECT N + 1
    FROM Numbers
    WHERE N < 1000
)
SELECT 
    N,
    N * N AS Square,
    N * N * N AS Cube,
    CASE WHEN N % 2 = 0 THEN 'Even' ELSE 'Odd' END AS Parity,
    CASE 
        WHEN N = 1 THEN 0
        WHEN N = 2 THEN 1
        WHEN N > 2 AND NOT EXISTS (
            SELECT 1 FROM Numbers n2 
            WHERE n2.N > 1 AND n2.N < N AND N % n2.N = 0
        ) THEN 1
        ELSE 0
    END AS IsPrime
FROM Numbers
OPTION (MAXRECURSION 1000);
GO
