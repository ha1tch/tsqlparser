-- Sample 004: Sliding Window Partition Management
-- Source: MSSQLTips - Implementation of Sliding Window Partitioning
-- Category: Partitioning
-- Complexity: Advanced
-- Features: Partition switching, SPLIT RANGE, MERGE RANGE, Dynamic SQL

CREATE PROCEDURE dbo.CreateNextPartition 
    @DtNextBoundary AS DATETIME
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @DtOldestBoundary AS DATETIME;
    DECLARE @strFileGroupToBeUsed AS VARCHAR(100);
    DECLARE @PartitionNumber AS INT;
    DECLARE @SQL NVARCHAR(MAX);
    
    -- Find the oldest partition boundary and its filegroup
    SELECT 
        @strFileGroupToBeUsed = fg.name, 
        @PartitionNumber = p.partition_number, 
        @DtOldestBoundary = CAST(prv.value AS DATETIME) 
    FROM sys.partitions p
    INNER JOIN sys.sysobjects tab ON tab.id = p.object_id
    INNER JOIN sys.allocation_units au ON au.container_id = p.hobt_id
    INNER JOIN sys.filegroups fg ON fg.data_space_id = au.data_space_id
    INNER JOIN sys.partition_range_values prv ON prv.boundary_id = p.partition_number
    INNER JOIN sys.partition_functions pf ON pf.function_id = prv.function_id
    WHERE pf.name = 'OrderPartitionFunction'
      AND tab.name = 'Orders'
      AND CAST(value AS DATETIME) = (
          SELECT MIN(CAST(value AS DATETIME)) 
          FROM sys.partitions p2
          INNER JOIN sys.sysobjects tab2 ON tab2.id = p2.object_id
          INNER JOIN sys.partition_range_values prv2 ON prv2.boundary_id = p2.partition_number
          INNER JOIN sys.partition_functions pf2 ON pf2.function_id = prv2.function_id
          WHERE pf2.name = 'OrderPartitionFunction'
            AND tab2.name = 'Orders'
      );
    
    -- Display information about partition being processed
    SELECT 
        @DtOldestBoundary AS Oldest_Boundary, 
        @strFileGroupToBeUsed AS FileGroupToBeUsed,
        @PartitionNumber AS PartitionNumber;
    
    -- Step 1: Switch out the oldest partition to staging table
    SET @SQL = N'ALTER TABLE Orders SWITCH PARTITION ' + 
               CAST(@PartitionNumber AS NVARCHAR(10)) + 
               N' TO Orders_Work PARTITION ' + 
               CAST(@PartitionNumber AS NVARCHAR(10));
    EXEC sp_executesql @SQL;
    
    -- Step 2: Truncate the staging table
    TRUNCATE TABLE Orders_Work;
    
    -- Step 3: Prepare the filegroup for the new partition
    SET @SQL = N'ALTER PARTITION SCHEME OrderPartitionScheme NEXT USED ' + 
               QUOTENAME(@strFileGroupToBeUsed);
    EXEC sp_executesql @SQL;
    
    -- Step 4: Split to create the new partition boundary
    ALTER PARTITION FUNCTION OrderPartitionFunction() 
        SPLIT RANGE (@DtNextBoundary);
    
    -- Step 5: Merge the old partition boundary
    ALTER PARTITION FUNCTION OrderPartitionFunction() 
        MERGE RANGE (@DtOldestBoundary);
END
GO
