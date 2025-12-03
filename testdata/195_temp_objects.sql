-- Sample 195: Temporary Objects
-- Category: Syntax Coverage / Session Management
-- Complexity: Intermediate
-- Purpose: Parser testing - temporary object syntax
-- Features: Local temp tables, global temp tables, table variables

-- Pattern 1: Local temporary table (single #)
CREATE TABLE #LocalTemp (
    ID INT PRIMARY KEY,
    Name VARCHAR(100),
    Value DECIMAL(10,2)
);

INSERT INTO #LocalTemp VALUES (1, 'Item1', 10.00);
SELECT * FROM #LocalTemp;
DROP TABLE #LocalTemp;
GO

-- Pattern 2: Global temporary table (double ##)
CREATE TABLE ##GlobalTemp (
    ID INT PRIMARY KEY,
    Name VARCHAR(100)
);

INSERT INTO ##GlobalTemp VALUES (1, 'Global Item');
SELECT * FROM ##GlobalTemp;
-- Visible to all sessions until last session disconnects
DROP TABLE ##GlobalTemp;
GO

-- Pattern 3: SELECT INTO temp table
SELECT CustomerID, CustomerName, Email
INTO #CustomerBackup
FROM dbo.Customers
WHERE IsActive = 1;

SELECT * FROM #CustomerBackup;
DROP TABLE #CustomerBackup;
GO

-- Pattern 4: Temp table with constraints
CREATE TABLE #OrderTemp (
    OrderID INT PRIMARY KEY,
    CustomerID INT NOT NULL,
    OrderDate DATE DEFAULT GETDATE(),
    TotalAmount DECIMAL(18,2) CHECK (TotalAmount >= 0),
    Status VARCHAR(20) DEFAULT 'Pending'
);

DROP TABLE #OrderTemp;
GO

-- Pattern 5: Temp table with identity
CREATE TABLE #SequenceTemp (
    ID INT IDENTITY(1,1) PRIMARY KEY,
    Data VARCHAR(100),
    CreatedAt DATETIME2 DEFAULT SYSDATETIME()
);

INSERT INTO #SequenceTemp (Data) VALUES ('First'), ('Second'), ('Third');
SELECT * FROM #SequenceTemp;
DROP TABLE #SequenceTemp;
GO

-- Pattern 6: Temp table with indexes
CREATE TABLE #IndexedTemp (
    ID INT PRIMARY KEY NONCLUSTERED,
    CategoryID INT,
    Value DECIMAL(10,2),
    INDEX IX_Category CLUSTERED (CategoryID)
);

DROP TABLE #IndexedTemp;
GO

-- Pattern 7: Table variable
DECLARE @TableVar TABLE (
    ID INT PRIMARY KEY,
    Name VARCHAR(100),
    Value DECIMAL(10,2)
);

INSERT INTO @TableVar VALUES (1, 'A', 10), (2, 'B', 20);
SELECT * FROM @TableVar;
GO

-- Pattern 8: Table variable with constraints
DECLARE @ConstrainedVar TABLE (
    ID INT IDENTITY(1,1) PRIMARY KEY,
    Email VARCHAR(200) UNIQUE NOT NULL,
    Age INT CHECK (Age >= 0),
    CreatedDate DATETIME DEFAULT GETDATE()
);

INSERT INTO @ConstrainedVar (Email, Age) VALUES ('test@example.com', 25);
SELECT * FROM @ConstrainedVar;
GO

-- Pattern 9: Table variable with computed column
DECLARE @ComputedVar TABLE (
    ID INT PRIMARY KEY,
    Quantity INT,
    UnitPrice DECIMAL(10,2),
    LineTotal AS (Quantity * UnitPrice)
);

INSERT INTO @ComputedVar (ID, Quantity, UnitPrice) VALUES (1, 5, 10.00);
SELECT * FROM @ComputedVar;
GO

-- Pattern 10: Temp table vs table variable usage
-- Temp table: Better for large datasets, has statistics
CREATE TABLE #LargeTemp (ID INT, Data VARCHAR(1000));
INSERT INTO #LargeTemp SELECT TOP 10000 object_id, name FROM sys.all_objects;
SELECT COUNT(*) FROM #LargeTemp;
DROP TABLE #LargeTemp;

-- Table variable: Better for small datasets, no statistics
DECLARE @SmallVar TABLE (ID INT, Data VARCHAR(1000));
INSERT INTO @SmallVar SELECT TOP 100 object_id, name FROM sys.all_objects;
SELECT COUNT(*) FROM @SmallVar;
GO

-- Pattern 11: Temp table in stored procedure
CREATE PROCEDURE dbo.TempTableProc
AS
BEGIN
    CREATE TABLE #ProcTemp (ID INT, Value VARCHAR(100));
    
    INSERT INTO #ProcTemp
    SELECT CustomerID, CustomerName FROM dbo.Customers;
    
    SELECT * FROM #ProcTemp;
    
    -- Automatically dropped when procedure ends
END;
GO
DROP PROCEDURE dbo.TempTableProc;
GO

-- Pattern 12: Table variable as output
CREATE PROCEDURE dbo.GetIDList
    @Result dbo.IDListType READONLY  -- Table type must be READONLY
AS
BEGIN
    SELECT * FROM @Result;
END;
GO
DROP PROCEDURE dbo.GetIDList;
GO

-- Pattern 13: Using temp table for complex logic
CREATE TABLE #Step1 (ID INT, Value INT);
CREATE TABLE #Step2 (ID INT, ProcessedValue INT);

-- Step 1: Initial data
INSERT INTO #Step1 SELECT CustomerID, COUNT(*) FROM dbo.Orders GROUP BY CustomerID;

-- Step 2: Process
INSERT INTO #Step2 SELECT ID, Value * 10 FROM #Step1;

-- Final result
SELECT * FROM #Step2;

DROP TABLE #Step1;
DROP TABLE #Step2;
GO

-- Pattern 14: Check if temp table exists
IF OBJECT_ID('tempdb..#MyTemp') IS NOT NULL
    DROP TABLE #MyTemp;

CREATE TABLE #MyTemp (ID INT);
SELECT * FROM #MyTemp;
DROP TABLE #MyTemp;
GO

-- Pattern 15: Temp table with same name in nested scope
CREATE TABLE #ScopedTemp (ID INT, Scope VARCHAR(10));
INSERT INTO #ScopedTemp VALUES (1, 'Outer');

EXEC('
    SELECT * FROM #ScopedTemp;  -- Sees outer temp table
');

DROP TABLE #ScopedTemp;
GO

-- Pattern 16: Memory-optimized table variable (SQL Server 2014+)
DECLARE @MemOptVar TABLE (
    ID INT NOT NULL PRIMARY KEY NONCLUSTERED HASH WITH (BUCKET_COUNT = 100),
    Value VARCHAR(100) NOT NULL
) -- WITH (MEMORY_OPTIMIZED = ON);  -- Requires memory-optimized filegroup
GO

-- Pattern 17: Temp table for ETL staging
CREATE TABLE #StagingData (
    RowID INT IDENTITY(1,1),
    RawData NVARCHAR(MAX),
    ParsedColumn1 VARCHAR(100),
    ParsedColumn2 INT,
    IsValid BIT DEFAULT 1,
    ErrorMessage VARCHAR(500)
);

-- Would load and process data here

DROP TABLE #StagingData;
GO

-- Pattern 18: Table variable scope demonstration
DECLARE @OuterVar TABLE (ID INT);
INSERT INTO @OuterVar VALUES (1);

BEGIN
    -- Same variable visible in inner block (T-SQL doesn't have block scope)
    INSERT INTO @OuterVar VALUES (2);
END

SELECT * FROM @OuterVar;  -- Returns 1 and 2
GO

-- Pattern 19: Temporary stored procedure
CREATE PROCEDURE #TempProc
AS
    SELECT 'This is a temporary procedure';
GO

EXEC #TempProc;
DROP PROCEDURE #TempProc;
GO

-- Pattern 20: Global temp table with cleanup
CREATE TABLE ##SharedData (ID INT, SessionID INT DEFAULT @@SPID);

INSERT INTO ##SharedData (ID) VALUES (1);

-- Other sessions can access this
SELECT * FROM ##SharedData;

-- Cleanup: drop when done
DROP TABLE ##SharedData;
GO
