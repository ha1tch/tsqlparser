-- Sample 014: Temporal Tables (System-Versioned)
-- Source: Microsoft Learn, MSSQLTips, SQLShack
-- Category: Temporal Data
-- Complexity: Advanced
-- Features: Temporal tables, FOR SYSTEM_TIME, AS OF, BETWEEN, CONTAINED IN

-- Setup: Create temporal table
CREATE PROCEDURE dbo.CreateTemporalEmployeeTable
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Drop if exists (need to handle temporal properly)
    IF OBJECT_ID('dbo.Employee', 'U') IS NOT NULL
    BEGIN
        -- First, turn off system versioning
        IF EXISTS (
            SELECT 1 FROM sys.tables 
            WHERE object_id = OBJECT_ID('dbo.Employee') 
              AND temporal_type = 2
        )
        BEGIN
            ALTER TABLE dbo.Employee SET (SYSTEM_VERSIONING = OFF);
        END
        
        DROP TABLE IF EXISTS dbo.EmployeeHistory;
        DROP TABLE IF EXISTS dbo.Employee;
    END
    
    -- Create temporal table
    CREATE TABLE dbo.Employee
    (
        EmployeeID INT NOT NULL PRIMARY KEY CLUSTERED,
        FirstName NVARCHAR(50) NOT NULL,
        LastName NVARCHAR(50) NOT NULL,
        DepartmentID INT NOT NULL,
        Salary DECIMAL(18,2) NOT NULL,
        Title NVARCHAR(100) NOT NULL,
        ManagerID INT NULL,
        
        -- Period columns
        ValidFrom DATETIME2 GENERATED ALWAYS AS ROW START NOT NULL,
        ValidTo DATETIME2 GENERATED ALWAYS AS ROW END NOT NULL,
        
        -- Define period
        PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo)
    )
    WITH (
        SYSTEM_VERSIONING = ON (
            HISTORY_TABLE = dbo.EmployeeHistory,
            HISTORY_RETENTION_PERIOD = 1 YEAR
        )
    );
    
    PRINT 'Temporal table dbo.Employee created successfully.';
END
GO

-- Query employee data as of a specific point in time
CREATE PROCEDURE dbo.GetEmployeeAsOf
    @EmployeeID INT,
    @AsOfDate DATETIME2
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        e.EmployeeID,
        e.FirstName,
        e.LastName,
        e.DepartmentID,
        d.DepartmentName,
        e.Salary,
        e.Title,
        e.ManagerID,
        e.ValidFrom,
        e.ValidTo,
        'Historical' AS DataSource
    FROM dbo.Employee FOR SYSTEM_TIME AS OF @AsOfDate e
    LEFT JOIN dbo.Departments d ON e.DepartmentID = d.DepartmentID
    WHERE e.EmployeeID = @EmployeeID;
END
GO

-- Get complete history for an employee
CREATE PROCEDURE dbo.GetEmployeeHistory
    @EmployeeID INT,
    @StartDate DATETIME2 = NULL,
    @EndDate DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Default to all time if not specified
    SET @StartDate = ISNULL(@StartDate, '1900-01-01');
    SET @EndDate = ISNULL(@EndDate, '9999-12-31 23:59:59.9999999');
    
    SELECT 
        e.EmployeeID,
        e.FirstName,
        e.LastName,
        e.DepartmentID,
        e.Salary,
        e.Title,
        e.ManagerID,
        e.ValidFrom,
        e.ValidTo,
        CASE 
            WHEN e.ValidTo = '9999-12-31 23:59:59.9999999' THEN 'Current'
            ELSE 'Historical'
        END AS RecordStatus,
        DATEDIFF(DAY, e.ValidFrom, 
            CASE WHEN e.ValidTo = '9999-12-31 23:59:59.9999999' 
                 THEN GETUTCDATE() 
                 ELSE e.ValidTo 
            END
        ) AS DaysInEffect
    FROM dbo.Employee FOR SYSTEM_TIME BETWEEN @StartDate AND @EndDate e
    WHERE e.EmployeeID = @EmployeeID
    ORDER BY e.ValidFrom DESC;
END
GO

-- Compare employee state between two points in time
CREATE PROCEDURE dbo.CompareEmployeeVersions
    @EmployeeID INT,
    @Date1 DATETIME2,
    @Date2 DATETIME2
AS
BEGIN
    SET NOCOUNT ON;
    
    WITH Version1 AS (
        SELECT 
            EmployeeID, FirstName, LastName, DepartmentID,
            Salary, Title, ManagerID, ValidFrom, ValidTo
        FROM dbo.Employee FOR SYSTEM_TIME AS OF @Date1
        WHERE EmployeeID = @EmployeeID
    ),
    Version2 AS (
        SELECT 
            EmployeeID, FirstName, LastName, DepartmentID,
            Salary, Title, ManagerID, ValidFrom, ValidTo
        FROM dbo.Employee FOR SYSTEM_TIME AS OF @Date2
        WHERE EmployeeID = @EmployeeID
    )
    SELECT 
        COALESCE(v1.EmployeeID, v2.EmployeeID) AS EmployeeID,
        
        v1.FirstName AS FirstName_At_Date1,
        v2.FirstName AS FirstName_At_Date2,
        CASE WHEN v1.FirstName <> v2.FirstName THEN 'Changed' ELSE '' END AS FirstName_Status,
        
        v1.LastName AS LastName_At_Date1,
        v2.LastName AS LastName_At_Date2,
        CASE WHEN v1.LastName <> v2.LastName THEN 'Changed' ELSE '' END AS LastName_Status,
        
        v1.DepartmentID AS DepartmentID_At_Date1,
        v2.DepartmentID AS DepartmentID_At_Date2,
        CASE WHEN v1.DepartmentID <> v2.DepartmentID THEN 'Changed' ELSE '' END AS Department_Status,
        
        v1.Salary AS Salary_At_Date1,
        v2.Salary AS Salary_At_Date2,
        v2.Salary - v1.Salary AS SalaryChange,
        
        v1.Title AS Title_At_Date1,
        v2.Title AS Title_At_Date2,
        CASE WHEN v1.Title <> v2.Title THEN 'Changed' ELSE '' END AS Title_Status,
        
        @Date1 AS CompareDate1,
        @Date2 AS CompareDate2
    FROM Version1 v1
    FULL OUTER JOIN Version2 v2 ON v1.EmployeeID = v2.EmployeeID;
END
GO

-- Get all changes within a time period
CREATE PROCEDURE dbo.GetEmployeeChanges
    @StartDate DATETIME2,
    @EndDate DATETIME2,
    @DepartmentID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Find records that changed during the period
    SELECT 
        e.EmployeeID,
        e.FirstName,
        e.LastName,
        e.DepartmentID,
        e.Salary,
        e.Title,
        e.ValidFrom AS ChangeDate,
        CASE 
            WHEN e.ValidFrom = (
                SELECT MIN(h.ValidFrom) 
                FROM dbo.Employee FOR SYSTEM_TIME ALL h 
                WHERE h.EmployeeID = e.EmployeeID
            ) THEN 'INSERT'
            WHEN e.ValidTo < '9999-12-31 23:59:59.9999999' THEN 'UPDATE'
            ELSE 'CURRENT'
        END AS ChangeType
    FROM dbo.Employee FOR SYSTEM_TIME CONTAINED IN (@StartDate, @EndDate) e
    WHERE @DepartmentID IS NULL OR e.DepartmentID = @DepartmentID
    ORDER BY e.ValidFrom;
END
GO

-- Restore employee to previous state
CREATE PROCEDURE dbo.RestoreEmployeeToPointInTime
    @EmployeeID INT,
    @RestoreToDate DATETIME2
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @FirstName NVARCHAR(50);
    DECLARE @LastName NVARCHAR(50);
    DECLARE @DepartmentID INT;
    DECLARE @Salary DECIMAL(18,2);
    DECLARE @Title NVARCHAR(100);
    DECLARE @ManagerID INT;
    
    -- Get the historical values
    SELECT 
        @FirstName = FirstName,
        @LastName = LastName,
        @DepartmentID = DepartmentID,
        @Salary = Salary,
        @Title = Title,
        @ManagerID = ManagerID
    FROM dbo.Employee FOR SYSTEM_TIME AS OF @RestoreToDate
    WHERE EmployeeID = @EmployeeID;
    
    IF @FirstName IS NULL
    BEGIN
        RAISERROR('No record found for EmployeeID %d as of %s', 16, 1, 
            @EmployeeID, @RestoreToDate);
        RETURN;
    END
    
    -- Update current record with historical values
    UPDATE dbo.Employee
    SET 
        FirstName = @FirstName,
        LastName = @LastName,
        DepartmentID = @DepartmentID,
        Salary = @Salary,
        Title = @Title,
        ManagerID = @ManagerID
    WHERE EmployeeID = @EmployeeID;
    
    SELECT 'Employee restored successfully' AS Result,
           @EmployeeID AS EmployeeID,
           @RestoreToDate AS RestoredToDate;
END
GO
