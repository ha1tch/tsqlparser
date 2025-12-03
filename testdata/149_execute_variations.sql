-- Sample 149: EXECUTE Statement Variations
-- Category: Missing Syntax Elements
-- Complexity: Complex
-- Purpose: Parser testing - all EXEC/EXECUTE syntax variations
-- Features: Stored procs, dynamic SQL, AT linked server, WITH options

-- Pattern 1: Basic EXECUTE/EXEC
EXECUTE dbo.GetCustomerOrders @CustomerID = 100;
EXEC dbo.GetCustomerOrders @CustomerID = 100;
EXEC dbo.GetCustomerOrders 100;  -- Positional parameter
GO

-- Pattern 2: EXEC with multiple parameters
EXEC dbo.SearchCustomers 
    @FirstName = 'John',
    @LastName = 'Smith',
    @City = NULL,
    @MinOrders = 5;
GO

-- Pattern 3: EXEC with OUTPUT parameter
DECLARE @NewID INT;
EXEC dbo.CreateCustomer 
    @FirstName = 'John',
    @LastName = 'Smith',
    @NewCustomerID = @NewID OUTPUT;
SELECT @NewID AS NewCustomerID;
GO

-- Pattern 4: EXEC with return value
DECLARE @ReturnCode INT;
EXEC @ReturnCode = dbo.ValidateCustomer @CustomerID = 100;
SELECT @ReturnCode AS ReturnCode;
GO

-- Pattern 5: EXEC with both return value and OUTPUT
DECLARE @ReturnCode INT;
DECLARE @ErrorMessage NVARCHAR(500);
EXEC @ReturnCode = dbo.ProcessOrder 
    @OrderID = 1001,
    @ErrorMessage = @ErrorMessage OUTPUT;
SELECT @ReturnCode AS ReturnCode, @ErrorMessage AS ErrorMessage;
GO

-- Pattern 6: EXEC dynamic SQL string
EXEC('SELECT * FROM dbo.Customers WHERE CustomerID = 100');
EXECUTE('SELECT * FROM dbo.Customers');
GO

-- Pattern 7: EXEC dynamic SQL with variable
DECLARE @SQL NVARCHAR(MAX) = N'SELECT * FROM dbo.Customers WHERE IsActive = 1';
EXEC(@SQL);
EXECUTE(@SQL);
GO

-- Pattern 8: EXEC dynamic SQL concatenation
DECLARE @TableName NVARCHAR(128) = 'Customers';
DECLARE @Schema NVARCHAR(128) = 'dbo';
EXEC('SELECT * FROM ' + @Schema + '.' + @TableName);
GO

-- Pattern 9: EXEC sp_executesql (preferred for dynamic SQL)
DECLARE @SQL NVARCHAR(MAX) = N'SELECT * FROM dbo.Customers WHERE CustomerID = @ID';
EXEC sp_executesql @SQL, N'@ID INT', @ID = 100;
GO

-- Pattern 10: sp_executesql with multiple parameters
DECLARE @SQL NVARCHAR(MAX) = N'
    SELECT * FROM dbo.Customers 
    WHERE (@FirstName IS NULL OR FirstName LIKE @FirstName)
    AND (@City IS NULL OR City = @City)';
    
EXEC sp_executesql @SQL, 
    N'@FirstName NVARCHAR(50), @City NVARCHAR(50)',
    @FirstName = N'J%',
    @City = NULL;
GO

-- Pattern 11: sp_executesql with OUTPUT parameter
DECLARE @SQL NVARCHAR(MAX) = N'SELECT @Count = COUNT(*) FROM dbo.Customers';
DECLARE @CustomerCount INT;
EXEC sp_executesql @SQL, N'@Count INT OUTPUT', @Count = @CustomerCount OUTPUT;
SELECT @CustomerCount AS CustomerCount;
GO

-- Pattern 12: EXEC AT linked server
EXEC('SELECT * FROM Sales.Customers') AT LinkedServerName;
EXEC('SELECT @@SERVERNAME') AT [RemoteServer];
GO

-- Pattern 13: EXEC AT with sp_executesql
DECLARE @SQL NVARCHAR(MAX) = N'SELECT * FROM Sales.Orders WHERE OrderDate > @Date';
EXEC sp_executesql @SQL, N'@Date DATE', @Date = '2024-01-01' AT LinkedServerName;
GO

-- Pattern 14: EXEC stored procedure on linked server
EXEC LinkedServerName.MyDatabase.dbo.GetCustomerOrders @CustomerID = 100;
EXEC [RemoteServer].RemoteDB.dbo.ProcessData;
GO

-- Pattern 15: EXEC with AS LOGIN / AS USER
EXEC AS LOGIN = 'AppLogin';
EXEC dbo.GetSensitiveData;
REVERT;

EXEC AS USER = 'AppUser';
EXEC dbo.GetUserData;
REVERT;
GO

-- Pattern 16: EXEC with RECOMPILE
EXEC dbo.GetCustomerOrders @CustomerID = 100 WITH RECOMPILE;
GO

-- Pattern 17: EXEC with RESULT SETS
EXEC dbo.GetCustomerSummary @CustomerID = 100
WITH RESULT SETS (
    (
        CustomerID INT,
        CustomerName NVARCHAR(100),
        TotalOrders INT,
        TotalSpent DECIMAL(18,2)
    )
);
GO

-- Pattern 18: EXEC with multiple RESULT SETS
EXEC dbo.GetCustomerDetails @CustomerID = 100
WITH RESULT SETS (
    (
        CustomerID INT,
        FirstName NVARCHAR(50),
        LastName NVARCHAR(50)
    ),
    (
        OrderID INT,
        OrderDate DATE,
        TotalAmount DECIMAL(18,2)
    )
);
GO

-- Pattern 19: EXEC with RESULT SETS UNDEFINED
EXEC dbo.DynamicReportQuery @ReportType = 'Sales'
WITH RESULT SETS UNDEFINED;
GO

-- Pattern 20: EXEC with RESULT SETS NONE
EXEC dbo.UpdateStatistics WITH RESULT SETS NONE;
GO

-- Pattern 21: EXEC system stored procedure
EXEC sp_who;
EXEC sp_who2;
EXEC sp_helpdb 'MyDatabase';
EXEC sp_help 'dbo.Customers';
EXEC sp_helptext 'dbo.GetCustomerOrders';
EXEC sp_columns 'Customers', 'dbo';
EXEC sp_tables @table_type = "'TABLE'";
GO

-- Pattern 22: EXEC extended stored procedure
EXEC xp_cmdshell 'dir C:\';
EXEC xp_fileexist 'C:\Temp\file.txt';
EXEC xp_logevent 50001, 'Custom log message', 'informational';
GO

-- Pattern 23: EXEC with DEFAULT keyword
EXEC dbo.GetOrders 
    @CustomerID = 100,
    @StartDate = DEFAULT,  -- Use default value
    @EndDate = '2024-12-31';
GO

-- Pattern 24: Nested EXEC
CREATE PROCEDURE dbo.OuterProc
AS
BEGIN
    PRINT 'Outer procedure';
    EXEC dbo.InnerProc;
    PRINT 'Back in outer';
END;
GO

-- Pattern 25: EXEC in dynamic context
DECLARE @ProcName NVARCHAR(128) = 'dbo.GetCustomerOrders';
DECLARE @SQL NVARCHAR(MAX) = 'EXEC ' + @ProcName + ' @CustomerID = 100';
EXEC sp_executesql @SQL;
GO

-- Pattern 26: INSERT EXEC
INSERT INTO #TempResults (CustomerID, CustomerName, OrderCount)
EXEC dbo.GetCustomerSummary @CustomerID = 100;
GO

-- Pattern 27: EXEC with variable procedure name
DECLARE @ProcName SYSNAME = N'GetCustomerOrders';
EXEC dbo.@ProcName;  -- This doesn't work directly

-- Use dynamic SQL instead:
DECLARE @SQL NVARCHAR(MAX) = N'EXEC dbo.' + QUOTENAME(@ProcName);
EXEC sp_executesql @SQL;
GO

-- Pattern 28: EXEC in cursor context
DECLARE @CustomerID INT;
DECLARE customer_cursor CURSOR FOR SELECT CustomerID FROM dbo.Customers;
OPEN customer_cursor;
FETCH NEXT FROM customer_cursor INTO @CustomerID;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC dbo.ProcessCustomer @CustomerID = @CustomerID;
    FETCH NEXT FROM customer_cursor INTO @CustomerID;
END
CLOSE customer_cursor;
DEALLOCATE customer_cursor;
GO

-- Cleanup
DROP PROCEDURE IF EXISTS dbo.OuterProc;
GO
