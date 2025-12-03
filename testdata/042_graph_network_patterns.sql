-- Sample 042: Graph and Network Data Patterns
-- Source: Microsoft Learn, MSSQLTips, Itzik Ben-Gan articles
-- Category: Hierarchy/Recursion
-- Complexity: Advanced
-- Features: Recursive CTEs, graph traversal, shortest path, adjacency list

-- Find all paths between two nodes
CREATE PROCEDURE dbo.FindAllPaths
    @StartNode INT,
    @EndNode INT,
    @MaxDepth INT = 10
AS
BEGIN
    SET NOCOUNT ON;
    
    ;WITH PathCTE AS (
        -- Anchor: Start from source node
        SELECT 
            e.FromNodeID,
            e.ToNodeID,
            CAST(CAST(e.FromNodeID AS VARCHAR(10)) + '->' + CAST(e.ToNodeID AS VARCHAR(10)) AS VARCHAR(MAX)) AS Path,
            1 AS PathLength,
            e.Weight AS TotalWeight
        FROM dbo.Edges e
        WHERE e.FromNodeID = @StartNode
        
        UNION ALL
        
        -- Recursive: Extend paths
        SELECT 
            p.FromNodeID,
            e.ToNodeID,
            CAST(p.Path + '->' + CAST(e.ToNodeID AS VARCHAR(10)) AS VARCHAR(MAX)),
            p.PathLength + 1,
            p.TotalWeight + e.Weight
        FROM PathCTE p
        INNER JOIN dbo.Edges e ON p.ToNodeID = e.FromNodeID
        WHERE p.PathLength < @MaxDepth
          AND CHARINDEX('->' + CAST(e.ToNodeID AS VARCHAR(10)) + '->', '->' + p.Path + '->') = 0  -- Prevent cycles
    )
    SELECT 
        Path,
        PathLength,
        TotalWeight
    FROM PathCTE
    WHERE ToNodeID = @EndNode
    ORDER BY PathLength, TotalWeight;
END
GO

-- Find shortest path using Dijkstra-like approach
CREATE PROCEDURE dbo.FindShortestPath
    @StartNode INT,
    @EndNode INT
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Working tables
    CREATE TABLE #Distances (
        NodeID INT PRIMARY KEY,
        Distance DECIMAL(18,4),
        PreviousNode INT,
        Visited BIT DEFAULT 0
    );
    
    CREATE TABLE #Path (
        StepOrder INT,
        NodeID INT
    );
    
    -- Initialize distances
    INSERT INTO #Distances (NodeID, Distance, PreviousNode)
    SELECT NodeID, 
           CASE WHEN NodeID = @StartNode THEN 0 ELSE 999999999 END,
           NULL
    FROM dbo.Nodes;
    
    DECLARE @CurrentNode INT;
    DECLARE @CurrentDistance DECIMAL(18,4);
    
    -- Process nodes
    WHILE EXISTS (SELECT 1 FROM #Distances WHERE Visited = 0 AND Distance < 999999999)
    BEGIN
        -- Get unvisited node with smallest distance
        SELECT TOP 1 
            @CurrentNode = NodeID,
            @CurrentDistance = Distance
        FROM #Distances
        WHERE Visited = 0
        ORDER BY Distance;
        
        -- Mark as visited
        UPDATE #Distances SET Visited = 1 WHERE NodeID = @CurrentNode;
        
        -- Stop if we reached destination
        IF @CurrentNode = @EndNode
            BREAK;
        
        -- Update distances to neighbors
        UPDATE d
        SET d.Distance = @CurrentDistance + e.Weight,
            d.PreviousNode = @CurrentNode
        FROM #Distances d
        INNER JOIN dbo.Edges e ON d.NodeID = e.ToNodeID
        WHERE e.FromNodeID = @CurrentNode
          AND d.Visited = 0
          AND @CurrentDistance + e.Weight < d.Distance;
    END
    
    -- Reconstruct path
    DECLARE @Node INT = @EndNode;
    DECLARE @Step INT = 0;
    
    WHILE @Node IS NOT NULL
    BEGIN
        INSERT INTO #Path (StepOrder, NodeID) VALUES (@Step, @Node);
        SELECT @Node = PreviousNode FROM #Distances WHERE NodeID = @Node;
        SET @Step = @Step + 1;
    END
    
    -- Return results
    SELECT 
        n.NodeID,
        n.NodeName,
        d.Distance AS DistanceFromStart
    FROM #Path p
    INNER JOIN dbo.Nodes n ON p.NodeID = n.NodeID
    INNER JOIN #Distances d ON p.NodeID = d.NodeID
    ORDER BY p.StepOrder DESC;
    
    SELECT Distance AS ShortestDistance
    FROM #Distances
    WHERE NodeID = @EndNode;
    
    DROP TABLE #Distances;
    DROP TABLE #Path;
END
GO

-- Find connected components
CREATE PROCEDURE dbo.FindConnectedComponents
AS
BEGIN
    SET NOCOUNT ON;
    
    CREATE TABLE #Components (
        NodeID INT PRIMARY KEY,
        ComponentID INT
    );
    
    DECLARE @ComponentID INT = 0;
    DECLARE @NodeID INT;
    
    -- Initialize all nodes as unassigned
    INSERT INTO #Components (NodeID, ComponentID)
    SELECT NodeID, NULL FROM dbo.Nodes;
    
    -- Process each unassigned node
    WHILE EXISTS (SELECT 1 FROM #Components WHERE ComponentID IS NULL)
    BEGIN
        SET @ComponentID = @ComponentID + 1;
        
        -- Get first unassigned node
        SELECT TOP 1 @NodeID = NodeID 
        FROM #Components 
        WHERE ComponentID IS NULL;
        
        -- BFS to find all connected nodes
        ;WITH ConnectedNodes AS (
            SELECT @NodeID AS NodeID
            UNION ALL
            SELECT e.ToNodeID
            FROM ConnectedNodes cn
            INNER JOIN dbo.Edges e ON cn.NodeID = e.FromNodeID
            WHERE NOT EXISTS (SELECT 1 FROM #Components WHERE NodeID = e.ToNodeID AND ComponentID IS NOT NULL)
            UNION
            SELECT e.FromNodeID
            FROM ConnectedNodes cn
            INNER JOIN dbo.Edges e ON cn.NodeID = e.ToNodeID
            WHERE NOT EXISTS (SELECT 1 FROM #Components WHERE NodeID = e.FromNodeID AND ComponentID IS NOT NULL)
        )
        UPDATE c
        SET ComponentID = @ComponentID
        FROM #Components c
        WHERE c.NodeID IN (SELECT DISTINCT NodeID FROM ConnectedNodes);
    END
    
    -- Return components with node counts
    SELECT 
        ComponentID,
        COUNT(*) AS NodeCount,
        STRING_AGG(CAST(NodeID AS VARCHAR(10)), ', ') AS Nodes
    FROM #Components
    GROUP BY ComponentID
    ORDER BY NodeCount DESC;
    
    DROP TABLE #Components;
END
GO

-- Calculate node centrality metrics
CREATE PROCEDURE dbo.CalculateNodeCentrality
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Degree centrality
    SELECT 
        n.NodeID,
        n.NodeName,
        ISNULL(out_deg.OutDegree, 0) AS OutDegree,
        ISNULL(in_deg.InDegree, 0) AS InDegree,
        ISNULL(out_deg.OutDegree, 0) + ISNULL(in_deg.InDegree, 0) AS TotalDegree,
        CAST(ISNULL(out_deg.OutDegree, 0) + ISNULL(in_deg.InDegree, 0) AS FLOAT) / 
            NULLIF((SELECT COUNT(*) - 1 FROM dbo.Nodes), 0) AS DegreeCentrality
    FROM dbo.Nodes n
    LEFT JOIN (
        SELECT FromNodeID, COUNT(*) AS OutDegree
        FROM dbo.Edges
        GROUP BY FromNodeID
    ) out_deg ON n.NodeID = out_deg.FromNodeID
    LEFT JOIN (
        SELECT ToNodeID, COUNT(*) AS InDegree
        FROM dbo.Edges
        GROUP BY ToNodeID
    ) in_deg ON n.NodeID = in_deg.ToNodeID
    ORDER BY TotalDegree DESC;
END
GO

-- Detect cycles in graph
CREATE PROCEDURE dbo.DetectCycles
    @MaxCycleLength INT = 10
AS
BEGIN
    SET NOCOUNT ON;
    
    ;WITH CycleCTE AS (
        -- Start from each node
        SELECT 
            e.FromNodeID AS StartNode,
            e.FromNodeID,
            e.ToNodeID,
            CAST(CAST(e.FromNodeID AS VARCHAR(10)) AS VARCHAR(MAX)) AS Path,
            1 AS PathLength
        FROM dbo.Edges e
        
        UNION ALL
        
        -- Extend path
        SELECT 
            c.StartNode,
            c.ToNodeID,
            e.ToNodeID,
            CAST(c.Path + '->' + CAST(c.ToNodeID AS VARCHAR(10)) AS VARCHAR(MAX)),
            c.PathLength + 1
        FROM CycleCTE c
        INNER JOIN dbo.Edges e ON c.ToNodeID = e.FromNodeID
        WHERE c.PathLength < @MaxCycleLength
          AND e.ToNodeID <> c.StartNode  -- Don't close cycle yet
          AND CHARINDEX(CAST(e.ToNodeID AS VARCHAR(10)), c.Path) = 0  -- No revisits except to start
    )
    SELECT DISTINCT
        c.Path + '->' + CAST(c.ToNodeID AS VARCHAR(10)) + '->' + CAST(c.StartNode AS VARCHAR(10)) AS Cycle,
        c.PathLength + 1 AS CycleLength
    FROM CycleCTE c
    INNER JOIN dbo.Edges e ON c.ToNodeID = e.FromNodeID AND e.ToNodeID = c.StartNode
    ORDER BY CycleLength, Cycle;
END
GO
