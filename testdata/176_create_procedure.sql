-- Sample 176: Stored Procedure Creation Patterns
-- Category: DDL / Syntax Coverage
-- Complexity: Complex
-- Purpose: Parser testing - CREATE PROCEDURE syntax variations
-- Features: Parameters, options, body patterns

-- Pattern 1: Basic stored procedure
CREATE PROCEDURE dbo.BasicProc
AS
BEGIN
    SELECT * FROM dbo.Customers;
END;
GO
DROP PROCEDURE dbo.BasicProc;
GO

-- Pattern 2: Procedure with PROC abbreviation
CREATE PROC dbo.ProcAbbrev
AS
    SELECT 1;
GO
DROP PROC dbo.ProcAbbrev;
GO

-- Pattern 3: Procedure with input parameters
CREATE PROCEDURE dbo.GetCustomerOrders
    @CustomerID INT,
    @StartDate DATE,
    @EndDate DATE
AS
BEGIN
    SELECT OrderID, OrderDate, TotalAmount
    FROM dbo.Orders
    WHERE CustomerID = @CustomerID
      AND OrderDate BETWEEN @StartDate AND @EndDate;
END;
GO
DROP PROCEDURE dbo.GetCustomerOrders;
GO

-- Pattern 4: Procedure with default parameter values
CREATE PROCEDURE dbo.SearchProducts
    @SearchTerm VARCHAR(100) = NULL,
    @CategoryID INT = NULL,
    @MinPrice DECIMAL(10,2) = 0,
    @MaxPrice DECIMAL(10,2) = 999999.99,
    @PageSize INT = 20,
    @PageNumber INT = 1
AS
BEGIN
    SELECT ProductID, ProductName, Price
    FROM dbo.Products
    WHERE (@SearchTerm IS NULL OR ProductName LIKE '%' + @SearchTerm + '%')
      AND (@CategoryID IS NULL OR CategoryID = @CategoryID)
      AND Price BETWEEN @MinPrice AND @MaxPrice
    ORDER BY ProductName
    OFFSET (@PageNumber - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY;
END;
GO
DROP PROCEDURE dbo.SearchProducts;
GO

-- Pattern 5: Procedure with OUTPUT parameters
CREATE PROCEDURE dbo.InsertCustomer
    @CustomerName VARCHAR(100),
    @Email VARCHAR(200),
    @NewCustomerID INT OUTPUT,
    @Success BIT OUTPUT
AS
BEGIN
    SET @Success = 0;
    
    INSERT INTO dbo.Customers (CustomerName, Email)
    VALUES (@CustomerName, @Email);
    
    SET @NewCustomerID = SCOPE_IDENTITY();
    SET @Success = 1;
END;
GO
DROP PROCEDURE dbo.InsertCustomer;
GO

-- Pattern 6: Procedure with return value
CREATE PROCEDURE dbo.ValidateCustomer
    @CustomerID INT
AS
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.Customers WHERE CustomerID = @CustomerID)
        RETURN -1;  -- Not found
    
    IF EXISTS (SELECT 1 FROM dbo.Customers WHERE CustomerID = @CustomerID AND IsActive = 0)
        RETURN 0;   -- Inactive
    
    RETURN 1;  -- Valid
END;
GO
DROP PROCEDURE dbo.ValidateCustomer;
GO

-- Pattern 7: Procedure with cursor parameter
CREATE PROCEDURE dbo.ProcessWithCursor
    @ResultCursor CURSOR VARYING OUTPUT
AS
BEGIN
    SET @ResultCursor = CURSOR FOR
        SELECT CustomerID, CustomerName FROM dbo.Customers WHERE IsActive = 1;
    
    OPEN @ResultCursor;
END;
GO
DROP PROCEDURE dbo.ProcessWithCursor;
GO

-- Pattern 8: Procedure with table-valued parameter
CREATE TYPE dbo.CustomerTableType AS TABLE (
    CustomerName VARCHAR(100),
    Email VARCHAR(200)
);
GO

CREATE PROCEDURE dbo.BulkInsertCustomers
    @Customers dbo.CustomerTableType READONLY
AS
BEGIN
    INSERT INTO dbo.Customers (CustomerName, Email)
    SELECT CustomerName, Email FROM @Customers;
END;
GO
DROP PROCEDURE dbo.BulkInsertCustomers;
DROP TYPE dbo.CustomerTableType;
GO

-- Pattern 9: Procedure WITH RECOMPILE
CREATE PROCEDURE dbo.DynamicQuery
    @TableName SYSNAME
WITH RECOMPILE
AS
BEGIN
    DECLARE @SQL NVARCHAR(MAX) = N'SELECT * FROM ' + QUOTENAME(@TableName);
    EXEC sp_executesql @SQL;
END;
GO
DROP PROCEDURE dbo.DynamicQuery;
GO

-- Pattern 10: Procedure WITH ENCRYPTION
CREATE PROCEDURE dbo.SecretProcedure
WITH ENCRYPTION
AS
BEGIN
    SELECT 'This is encrypted';
END;
GO
DROP PROCEDURE dbo.SecretProcedure;
GO

-- Pattern 11: Procedure WITH EXECUTE AS
CREATE PROCEDURE dbo.ElevatedProcedure
WITH EXECUTE AS OWNER
AS
BEGIN
    SELECT * FROM dbo.SensitiveData;
END;
GO
DROP PROCEDURE dbo.ElevatedProcedure;
GO

-- Pattern 12: Procedure with multiple options
CREATE PROCEDURE dbo.MultiOptionProc
WITH RECOMPILE, EXECUTE AS 'dbo'
AS
BEGIN
    SELECT 1;
END;
GO
DROP PROCEDURE dbo.MultiOptionProc;
GO

-- Pattern 13: Procedure with SCHEMABINDING
CREATE PROCEDURE dbo.SchemaBindProc
WITH SCHEMABINDING
AS
BEGIN
    SELECT CustomerID, CustomerName FROM dbo.Customers;
END;
GO
DROP PROCEDURE dbo.SchemaBindProc;
GO

-- Pattern 14: Procedure with NATIVE_COMPILATION (memory-optimized)
CREATE PROCEDURE dbo.NativeProc
WITH NATIVE_COMPILATION, SCHEMABINDING, EXECUTE AS OWNER
AS
BEGIN ATOMIC WITH (TRANSACTION ISOLATION LEVEL = SNAPSHOT, LANGUAGE = N'English')
    SELECT 1;
END;
GO
DROP PROCEDURE dbo.NativeProc;
GO

-- Pattern 15: Procedure FOR REPLICATION
CREATE PROCEDURE dbo.ReplicationProc
FOR REPLICATION
AS
BEGIN
    -- Replication-only logic
    SELECT 1;
END;
GO
DROP PROCEDURE dbo.ReplicationProc;
GO

-- Pattern 16: Procedure with SET statements
CREATE PROCEDURE dbo.SetOptionsProc
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET ANSI_NULLS ON;
    SET QUOTED_IDENTIFIER ON;
    
    SELECT * FROM dbo.Customers;
END;
GO
DROP PROCEDURE dbo.SetOptionsProc;
GO

-- Pattern 17: Procedure with error handling
CREATE PROCEDURE dbo.ErrorHandlingProc
    @CustomerID INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        UPDATE dbo.Customers SET ModifiedDate = GETDATE() WHERE CustomerID = @CustomerID;
        
        IF @@ROWCOUNT = 0
            THROW 50001, 'Customer not found', 1;
        
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        THROW;
    END CATCH
END;
GO
DROP PROCEDURE dbo.ErrorHandlingProc;
GO

-- Pattern 18: Procedure returning multiple result sets
CREATE PROCEDURE dbo.MultiResultProc
    @CustomerID INT
AS
BEGIN
    -- Result set 1: Customer info
    SELECT CustomerID, CustomerName, Email
    FROM dbo.Customers
    WHERE CustomerID = @CustomerID;
    
    -- Result set 2: Orders
    SELECT OrderID, OrderDate, TotalAmount
    FROM dbo.Orders
    WHERE CustomerID = @CustomerID;
    
    -- Result set 3: Summary
    SELECT COUNT(*) AS OrderCount, SUM(TotalAmount) AS TotalSpent
    FROM dbo.Orders
    WHERE CustomerID = @CustomerID;
END;
GO
DROP PROCEDURE dbo.MultiResultProc;
GO

-- Pattern 19: Procedure with dynamic SQL
CREATE PROCEDURE dbo.DynamicSortProc
    @SortColumn SYSNAME,
    @SortDirection VARCHAR(4) = 'ASC'
AS
BEGIN
    DECLARE @SQL NVARCHAR(MAX);
    
    SET @SQL = N'SELECT CustomerID, CustomerName, Email 
                 FROM dbo.Customers 
                 ORDER BY ' + QUOTENAME(@SortColumn) + N' ' + 
                 CASE WHEN @SortDirection = 'DESC' THEN 'DESC' ELSE 'ASC' END;
    
    EXEC sp_executesql @SQL;
END;
GO
DROP PROCEDURE dbo.DynamicSortProc;
GO

-- Pattern 20: Procedure with conditional logic
CREATE PROCEDURE dbo.ConditionalProc
    @Action VARCHAR(10),
    @CustomerID INT = NULL,
    @CustomerName VARCHAR(100) = NULL,
    @Email VARCHAR(200) = NULL
AS
BEGIN
    IF @Action = 'INSERT'
    BEGIN
        INSERT INTO dbo.Customers (CustomerName, Email)
        VALUES (@CustomerName, @Email);
    END
    ELSE IF @Action = 'UPDATE'
    BEGIN
        UPDATE dbo.Customers
        SET CustomerName = ISNULL(@CustomerName, CustomerName),
            Email = ISNULL(@Email, Email)
        WHERE CustomerID = @CustomerID;
    END
    ELSE IF @Action = 'DELETE'
    BEGIN
        DELETE FROM dbo.Customers WHERE CustomerID = @CustomerID;
    END
    ELSE
    BEGIN
        RAISERROR('Invalid action', 16, 1);
    END
END;
GO
DROP PROCEDURE dbo.ConditionalProc;
GO

-- Pattern 21: ALTER PROCEDURE
CREATE PROCEDURE dbo.ToBeAltered AS SELECT 1;
GO

ALTER PROCEDURE dbo.ToBeAltered
AS
BEGIN
    SELECT 2;
END;
GO
DROP PROCEDURE dbo.ToBeAltered;
GO

-- Pattern 22: Procedure with numbered version (deprecated)
CREATE PROCEDURE dbo.NumberedProc;1
AS
    SELECT 'Version 1';
GO

CREATE PROCEDURE dbo.NumberedProc;2
AS
    SELECT 'Version 2';
GO

DROP PROCEDURE dbo.NumberedProc;
GO
