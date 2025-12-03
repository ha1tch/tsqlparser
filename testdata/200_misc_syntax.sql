-- Sample 200: Additional Miscellaneous Syntax
-- Category: Syntax Coverage / Miscellaneous
-- Complexity: Complex
-- Purpose: Parser testing - additional syntax constructs
-- Features: Various miscellaneous T-SQL syntax patterns

-- Pattern 1: USE statement
USE master;
GO
USE tempdb;
GO

-- Pattern 2: EXECUTE/EXEC statement variations
EXEC dbo.MyProcedure;
EXECUTE dbo.MyProcedure;
EXEC dbo.MyProcedure @Param1 = 1, @Param2 = 'Value';
EXEC dbo.MyProcedure 1, 'Value';
EXEC @ReturnValue = dbo.MyProcedure;
GO

-- Pattern 3: RETURN statement
CREATE PROCEDURE dbo.TestReturn
AS
BEGIN
    IF 1 = 0
        RETURN -1;
    RETURN 0;
END;
GO
DROP PROCEDURE dbo.TestReturn;
GO

-- Pattern 4: BREAK and CONTINUE
DECLARE @i INT = 0;
WHILE @i < 10
BEGIN
    SET @i = @i + 1;
    IF @i = 3 CONTINUE;
    IF @i = 7 BREAK;
    PRINT @i;
END
GO

-- Pattern 5: GOTO and labels
DECLARE @x INT = 0;
StartLoop:
    SET @x = @x + 1;
    IF @x < 5 GOTO StartLoop;
PRINT 'Done';
GO

-- Pattern 6: CHECKPOINT
CHECKPOINT;
CHECKPOINT 30;  -- With duration in seconds
GO

-- Pattern 7: SHUTDOWN
-- SHUTDOWN;
-- SHUTDOWN WITH NOWAIT;
GO

-- Pattern 8: KILL
-- KILL 55;
-- KILL 55 WITH STATUSONLY;
-- KILL UOW WITH 'D5499C66-...' -- Distributed transaction
GO

-- Pattern 9: RECONFIGURE
RECONFIGURE;
RECONFIGURE WITH OVERRIDE;
GO

-- Pattern 10: READTEXT, WRITETEXT, UPDATETEXT (deprecated)
-- READTEXT dbo.Documents.Content @TextPtr 0 100;
-- WRITETEXT dbo.Documents.Content @TextPtr 'New content';
-- UPDATETEXT dbo.Documents.Content @TextPtr 0 NULL 'Inserted text';
GO

-- Pattern 11: Filestream operations
-- SELECT FileData.PathName() FROM dbo.Documents WHERE ID = 1;
-- SELECT GET_FILESTREAM_TRANSACTION_CONTEXT();
GO

-- Pattern 12: Undocumented syntax
-- SELECT * FROM ::fn_helpcollations();  -- Deprecated
SELECT * FROM sys.fn_helpcollations();
GO

-- Pattern 13: @@global variables
SELECT 
    @@VERSION AS Version,
    @@SERVERNAME AS ServerName,
    @@SERVICENAME AS ServiceName,
    @@SPID AS SessionID,
    @@LANGUAGE AS Language,
    @@LANGID AS LanguageID,
    @@DATEFIRST AS DateFirst,
    @@DBTS AS DatabaseTimestamp,
    @@MAX_CONNECTIONS AS MaxConnections,
    @@NESTLEVEL AS NestLevel,
    @@OPTIONS AS Options,
    @@REMSERVER AS RemoteServer,
    @@TEXTSIZE AS TextSize,
    @@TRANCOUNT AS TransactionCount;
GO

-- Pattern 14: Aggregate pushdown hints
-- SELECT * FROM dbo.LargeTable OPTION (USE HINT('ENABLE_PARALLEL_PLAN_PREFERENCE'));
GO

-- Pattern 15: Query Store hints
-- EXEC sp_query_store_set_hints @query_id = 1234, @query_hints = N'OPTION(RECOMPILE)';
GO

-- Pattern 16: sp_describe_first_result_set
EXEC sp_describe_first_result_set N'SELECT CustomerID, CustomerName FROM dbo.Customers';
GO

-- Pattern 17: sp_describe_undeclared_parameters
EXEC sp_describe_undeclared_parameters N'SELECT * FROM dbo.Customers WHERE CustomerID = @ID';
GO

-- Pattern 18: Format specification syntax
SELECT FORMAT(123456.789, 'N', 'en-US');
SELECT FORMAT(123456.789, 'C', 'en-GB');
SELECT FORMAT(GETDATE(), 'D', 'de-DE');
SELECT FORMAT(GETDATE(), 'yyyy-MM-dd HH:mm:ss');
GO

-- Pattern 19: AT TIME ZONE
SELECT 
    GETDATE() AS LocalTime,
    GETDATE() AT TIME ZONE 'Pacific Standard Time' AS PacificTime,
    GETUTCDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Eastern Standard Time' AS EasternTime;
GO

-- Pattern 20: JSON_ARRAYAGG / JSON_OBJECTAGG (SQL Server 2022+)
-- SELECT JSON_ARRAYAGG(ProductName) FROM dbo.Products;
-- SELECT JSON_OBJECTAGG(ProductID, ProductName) FROM dbo.Products;
GO

-- Pattern 21: GENERATE_SERIES (SQL Server 2022+)
SELECT value FROM GENERATE_SERIES(1, 10);
SELECT value FROM GENERATE_SERIES(1, 10, 2);
SELECT value FROM GENERATE_SERIES(CAST('2024-01-01' AS DATE), CAST('2024-01-10' AS DATE), 1);
GO

-- Pattern 22: DATE_BUCKET (SQL Server 2022+)
SELECT DATE_BUCKET(WEEK, 1, OrderDate) AS WeekStart, COUNT(*)
FROM dbo.Orders
GROUP BY DATE_BUCKET(WEEK, 1, OrderDate);
GO

-- Pattern 23: WINDOW clause (SQL Server 2022+)
SELECT 
    OrderID,
    CustomerID,
    TotalAmount,
    SUM(TotalAmount) OVER w AS RunningTotal,
    AVG(TotalAmount) OVER w AS RunningAvg
FROM dbo.Orders
WINDOW w AS (PARTITION BY CustomerID ORDER BY OrderDate);
GO

-- Pattern 24: LEAST and GREATEST (SQL Server 2022+)
SELECT 
    LEAST(10, 20, 5, 15) AS SmallestValue,
    GREATEST(10, 20, 5, 15) AS LargestValue,
    LEAST(Price, DiscountPrice, WholesalePrice) AS LowestPrice
FROM dbo.Products;
GO

-- Pattern 25: IS [NOT] DISTINCT FROM (SQL Server 2022+)
SELECT * FROM dbo.Table1 t1
INNER JOIN dbo.Table2 t2 ON t1.Value IS NOT DISTINCT FROM t2.Value;
GO
