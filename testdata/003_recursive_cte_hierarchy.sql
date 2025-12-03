-- Sample 003: Recursive CTE for Employee Hierarchy
-- Source: MSSQLTips - Recursive Queries using CTE
-- Category: Hierarchy/Recursion
-- Complexity: Complex
-- Features: Recursive CTE, UNION ALL, Hierarchy traversal

-- Non-stored procedure version showing the CTE pattern
WITH Managers AS
(
    -- Anchor member: Get top-level employees (no manager)
    SELECT EmployeeID, 
           LastName, 
           ReportsTo,
           0 AS Level,
           CAST(LastName AS VARCHAR(1000)) AS HierarchyPath
    FROM Employees
    WHERE ReportsTo IS NULL
    
    UNION ALL
    
    -- Recursive member: Get employees who report to current level
    SELECT e.EmployeeID,
           e.LastName, 
           e.ReportsTo,
           m.Level + 1,
           CAST(m.HierarchyPath + ' -> ' + e.LastName AS VARCHAR(1000))
    FROM Employees e 
    INNER JOIN Managers m ON e.ReportsTo = m.EmployeeID
)
SELECT * FROM Managers 
ORDER BY Level, LastName
OPTION (MAXRECURSION 100);
GO

-- Stored procedure version with parameter
CREATE PROCEDURE sp_GetEmployeeHierarchy
    @StartEmployeeID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    WITH EmployeeHierarchy AS
    (
        -- Anchor: Start from specified employee or top
        SELECT 
            EmployeeID, 
            LastName,
            FirstName,
            ReportsTo,
            0 AS Level,
            CAST(LastName AS VARCHAR(1000)) AS Path
        FROM Employees
        WHERE (@StartEmployeeID IS NULL AND ReportsTo IS NULL)
           OR EmployeeID = @StartEmployeeID
        
        UNION ALL
        
        -- Recursive: Get all subordinates
        SELECT 
            e.EmployeeID, 
            e.LastName,
            e.FirstName,
            e.ReportsTo,
            eh.Level + 1,
            CAST(eh.Path + ' > ' + e.LastName AS VARCHAR(1000))
        FROM Employees e
        INNER JOIN EmployeeHierarchy eh 
            ON e.ReportsTo = eh.EmployeeID
    )
    SELECT 
        EmployeeID,
        REPLICATE('  ', Level) + LastName AS Employee,
        FirstName,
        Level,
        Path
    FROM EmployeeHierarchy
    ORDER BY Path;
END
GO
