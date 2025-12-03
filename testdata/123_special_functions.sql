-- Sample 123: Special Functions - $PARTITION, $IDENTITY, $ROWGUID
-- Category: Missing Syntax Elements
-- Complexity: Complex
-- Purpose: Parser testing - special system functions
-- Features: $PARTITION, $IDENTITY, $ROWGUID, partition functions

-- Pattern 1: $PARTITION function basic usage
-- Returns the partition number for a given value
SELECT $PARTITION.MyPartitionFunction(100) AS PartitionNumber;
GO

SELECT $PARTITION.DatePartitionFunction('2024-06-15') AS PartitionNumber;
GO

-- Pattern 2: $PARTITION in WHERE clause
SELECT *
FROM dbo.PartitionedSales
WHERE $PARTITION.SalesDatePartitionFunction(SaleDate) = 5;
GO

-- Pattern 3: $PARTITION to find data distribution
SELECT 
    $PARTITION.MyPartitionFunction(PartitionKey) AS PartitionNumber,
    COUNT(*) AS RowCount,
    MIN(PartitionKey) AS MinValue,
    MAX(PartitionKey) AS MaxValue
FROM dbo.PartitionedTable
GROUP BY $PARTITION.MyPartitionFunction(PartitionKey)
ORDER BY PartitionNumber;
GO

-- Pattern 4: $PARTITION with partition scheme info
SELECT 
    ps.name AS PartitionScheme,
    pf.name AS PartitionFunction,
    p.partition_number,
    p.rows,
    $PARTITION.MyPartitionFunction(prv.value) AS ComputedPartition
FROM sys.partitions p
INNER JOIN sys.tables t ON p.object_id = t.object_id
INNER JOIN sys.indexes i ON p.object_id = i.object_id AND p.index_id = i.index_id
INNER JOIN sys.partition_schemes ps ON i.data_space_id = ps.data_space_id
INNER JOIN sys.partition_functions pf ON ps.function_id = pf.function_id
LEFT JOIN sys.partition_range_values prv ON pf.function_id = prv.function_id 
    AND p.partition_number = prv.boundary_id + 1
WHERE t.name = 'PartitionedTable'
AND i.index_id <= 1;
GO

-- Pattern 5: $PARTITION to move data between partitions
-- Find rows that would be in a different partition after value change
SELECT 
    PartitionKey,
    $PARTITION.MyPartitionFunction(PartitionKey) AS CurrentPartition,
    $PARTITION.MyPartitionFunction(PartitionKey + 1000) AS NewPartition
FROM dbo.PartitionedTable
WHERE $PARTITION.MyPartitionFunction(PartitionKey) <> $PARTITION.MyPartitionFunction(PartitionKey + 1000);
GO

-- Pattern 6: $IDENTITY in INSERT
-- Returns the last identity value inserted
CREATE TABLE #TestIdentity (
    ID INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(50)
);

INSERT INTO #TestIdentity (Name) VALUES ('First');
SELECT $IDENTITY AS LastIdentity;  -- Alternative to @@IDENTITY

INSERT INTO #TestIdentity (Name) VALUES ('Second');
SELECT $IDENTITY AS LastIdentity;

DROP TABLE #TestIdentity;
GO

-- Pattern 7: $IDENTITY as column reference (deprecated but valid)
CREATE TABLE #IdentityTest (
    ID INT IDENTITY(100, 5),
    Value NVARCHAR(50)
);

INSERT INTO #IdentityTest (Value) VALUES ('A'), ('B'), ('C');

-- $IDENTITY refers to the identity column
SELECT $IDENTITY, Value FROM #IdentityTest;

DROP TABLE #IdentityTest;
GO

-- Pattern 8: $ROWGUID as column reference
CREATE TABLE #RowGuidTest (
    ID INT IDENTITY(1,1),
    RowGuid UNIQUEIDENTIFIER ROWGUIDCOL DEFAULT NEWSEQUENTIALID(),
    Name NVARCHAR(50)
);

INSERT INTO #RowGuidTest (Name) VALUES ('Test1'), ('Test2');

-- $ROWGUID refers to the ROWGUIDCOL column
SELECT $ROWGUID, ID, Name FROM #RowGuidTest;

DROP TABLE #RowGuidTest;
GO

-- Pattern 9: Using $ROWGUID in WHERE clause
CREATE TABLE #Documents (
    DocID INT IDENTITY(1,1),
    DocGuid UNIQUEIDENTIFIER ROWGUIDCOL DEFAULT NEWID(),
    DocName NVARCHAR(100)
);

INSERT INTO #Documents (DocName) VALUES ('Doc1'), ('Doc2');

DECLARE @TargetGuid UNIQUEIDENTIFIER;
SELECT TOP 1 @TargetGuid = $ROWGUID FROM #Documents;

SELECT * FROM #Documents WHERE $ROWGUID = @TargetGuid;

DROP TABLE #Documents;
GO

-- Pattern 10: $PARTITION with date ranges
CREATE PARTITION FUNCTION PF_DateRange (DATE)
AS RANGE RIGHT FOR VALUES ('2023-01-01', '2024-01-01', '2025-01-01');
-- Note: Would need partition scheme in real scenario

SELECT 
    $PARTITION.PF_DateRange('2022-06-15') AS Partition2022,
    $PARTITION.PF_DateRange('2023-06-15') AS Partition2023,
    $PARTITION.PF_DateRange('2024-06-15') AS Partition2024,
    $PARTITION.PF_DateRange('2025-06-15') AS Partition2025;
GO

-- Pattern 11: $PARTITION for partition elimination verification
-- Check which partition a query would hit
DECLARE @SearchDate DATE = '2024-06-15';

SELECT 
    @SearchDate AS SearchDate,
    $PARTITION.PF_DateRange(@SearchDate) AS TargetPartition;

-- Query with partition elimination
SELECT *
FROM dbo.PartitionedSales
WHERE SaleDate = @SearchDate
AND $PARTITION.PF_DateRange(SaleDate) = $PARTITION.PF_DateRange(@SearchDate);
GO

-- Pattern 12: Combining partition function with aggregates
SELECT 
    CASE $PARTITION.PF_DateRange(SaleDate)
        WHEN 1 THEN 'Before 2023'
        WHEN 2 THEN '2023'
        WHEN 3 THEN '2024'
        WHEN 4 THEN '2025 and later'
    END AS Period,
    COUNT(*) AS SaleCount,
    SUM(Amount) AS TotalAmount
FROM dbo.PartitionedSales
GROUP BY $PARTITION.PF_DateRange(SaleDate)
ORDER BY $PARTITION.PF_DateRange(SaleDate);
GO

-- Pattern 13: $PARTITION boundary analysis
SELECT 
    boundary_id,
    value AS BoundaryValue,
    $PARTITION.PF_DateRange(CAST(value AS DATE)) AS PartitionBefore,
    $PARTITION.PF_DateRange(DATEADD(DAY, 1, CAST(value AS DATE))) AS PartitionAfter
FROM sys.partition_range_values prv
INNER JOIN sys.partition_functions pf ON prv.function_id = pf.function_id
WHERE pf.name = 'PF_DateRange';
GO

-- Pattern 14: IDENT_CURRENT vs $IDENTITY vs @@IDENTITY vs SCOPE_IDENTITY
CREATE TABLE #IdentityComparison (
    ID INT IDENTITY(1,1),
    Value NVARCHAR(50)
);

INSERT INTO #IdentityComparison (Value) VALUES ('Test');

SELECT 
    @@IDENTITY AS AtAtIdentity,
    SCOPE_IDENTITY() AS ScopeIdentity,
    IDENT_CURRENT('#IdentityComparison') AS IdentCurrent;
    -- $IDENTITY would need to be in separate SELECT

DROP TABLE #IdentityComparison;
GO

-- Pattern 15: $ROWGUID with MERGE statement
CREATE TABLE #Source (ID INT, Name NVARCHAR(50));
CREATE TABLE #Target (
    ID INT,
    RowGuid UNIQUEIDENTIFIER ROWGUIDCOL DEFAULT NEWID(),
    Name NVARCHAR(50)
);

INSERT INTO #Source VALUES (1, 'New'), (2, 'Updated');
INSERT INTO #Target (ID, Name) VALUES (2, 'Original');

MERGE INTO #Target AS t
USING #Source AS s ON t.ID = s.ID
WHEN MATCHED THEN UPDATE SET t.Name = s.Name
WHEN NOT MATCHED THEN INSERT (ID, Name) VALUES (s.ID, s.Name)
OUTPUT $action, inserted.$ROWGUID, inserted.ID, inserted.Name;

DROP TABLE #Source;
DROP TABLE #Target;
GO
