-- Sample 118: WITH RESULT SETS and Typed Results
-- Category: Missing Syntax Elements
-- Complexity: Complex
-- Purpose: Parser testing - result set definition and reshaping
-- Features: EXECUTE WITH RESULT SETS, result set definitions, column aliasing

-- Pattern 1: Simple WITH RESULT SETS
CREATE PROCEDURE dbo.GetEmployeeData
AS
BEGIN
    SELECT EmployeeID, FirstName, LastName, Salary FROM Employees;
END;
GO

EXEC dbo.GetEmployeeData
WITH RESULT SETS (
    (
        EmpID INT,
        GivenName NVARCHAR(50),
        FamilyName NVARCHAR(50),
        AnnualSalary DECIMAL(18,2)
    )
);
GO

-- Pattern 2: Changing data types in result set
CREATE PROCEDURE dbo.GetProductInfo
AS
BEGIN
    SELECT ProductID, ProductName, Price, StockQuantity FROM Products;
END;
GO

EXEC dbo.GetProductInfo
WITH RESULT SETS (
    (
        ID BIGINT,                    -- Changed from INT
        Name NVARCHAR(200),           -- Changed from NVARCHAR(100)
        UnitPrice MONEY,              -- Changed from DECIMAL
        UnitsInStock SMALLINT         -- Changed from INT
    )
);
GO

-- Pattern 3: Multiple result sets
CREATE PROCEDURE dbo.GetOrderSummary
    @CustomerID INT
AS
BEGIN
    -- Result set 1: Customer info
    SELECT CustomerID, CustomerName, Email FROM Customers WHERE CustomerID = @CustomerID;
    
    -- Result set 2: Orders
    SELECT OrderID, OrderDate, TotalAmount FROM Orders WHERE CustomerID = @CustomerID;
    
    -- Result set 3: Order count
    SELECT COUNT(*) AS OrderCount FROM Orders WHERE CustomerID = @CustomerID;
END;
GO

EXEC dbo.GetOrderSummary @CustomerID = 1
WITH RESULT SETS (
    (
        -- First result set definition
        CustID INT,
        CustName NVARCHAR(100),
        EmailAddress NVARCHAR(200)
    ),
    (
        -- Second result set definition
        OrderNumber INT,
        DateOrdered DATE,
        Total MONEY
    ),
    (
        -- Third result set definition
        TotalOrders INT
    )
);
GO

-- Pattern 4: WITH RESULT SETS UNDEFINED
EXEC dbo.GetEmployeeData
WITH RESULT SETS UNDEFINED;
GO

-- Pattern 5: WITH RESULT SETS NONE
CREATE PROCEDURE dbo.UpdateAndReturn
AS
BEGIN
    UPDATE Products SET LastModified = GETDATE() WHERE CategoryID = 1;
    SELECT @@ROWCOUNT AS RowsAffected;  -- This result set will be suppressed
END;
GO

EXEC dbo.UpdateAndReturn
WITH RESULT SETS NONE;
GO

-- Pattern 6: Result set with NULL column definitions
EXEC dbo.GetEmployeeData
WITH RESULT SETS (
    (
        EmpID INT NOT NULL,
        GivenName NVARCHAR(50) NULL,
        FamilyName NVARCHAR(50) NOT NULL,
        AnnualSalary DECIMAL(18,2) NULL
    )
);
GO

-- Pattern 7: Result set with collation
EXEC dbo.GetEmployeeData
WITH RESULT SETS (
    (
        EmpID INT,
        GivenName NVARCHAR(50) COLLATE Latin1_General_CI_AS,
        FamilyName NVARCHAR(50) COLLATE Latin1_General_CS_AS,
        AnnualSalary DECIMAL(18,2)
    )
);
GO

-- Pattern 8: Complex procedure with conditional result sets
CREATE PROCEDURE dbo.GetDataByType
    @DataType VARCHAR(20)
AS
BEGIN
    IF @DataType = 'Customers'
        SELECT CustomerID, CustomerName, Email FROM Customers;
    ELSE IF @DataType = 'Products'
        SELECT ProductID, ProductName, Price FROM Products;
    ELSE IF @DataType = 'Orders'
        SELECT OrderID, CustomerID, OrderDate, TotalAmount FROM Orders;
END;
GO

-- Must match the actual output
EXEC dbo.GetDataByType @DataType = 'Customers'
WITH RESULT SETS (
    (
        ID INT,
        Name NVARCHAR(100),
        Contact NVARCHAR(200)
    )
);
GO

-- Pattern 9: Nested procedure calls with result sets
CREATE PROCEDURE dbo.OuterProc
AS
BEGIN
    EXEC dbo.GetEmployeeData;
    EXEC dbo.GetProductInfo;
END;
GO

EXEC dbo.OuterProc
WITH RESULT SETS (
    (
        -- First proc's result
        EmpID INT,
        FirstName NVARCHAR(50),
        LastName NVARCHAR(50),
        Salary DECIMAL(18,2)
    ),
    (
        -- Second proc's result
        ProdID INT,
        ProdName NVARCHAR(100),
        UnitPrice DECIMAL(10,2),
        Stock INT
    )
);
GO

-- Pattern 10: Dynamic SQL with result sets
DECLARE @SQL NVARCHAR(MAX) = N'SELECT 1 AS Col1, ''Test'' AS Col2, GETDATE() AS Col3';

EXEC sp_executesql @SQL
WITH RESULT SETS (
    (
        Number INT,
        Text NVARCHAR(50),
        DateValue DATETIME
    )
);
GO

-- Pattern 11: Result set for system procedure
EXEC sp_who2
WITH RESULT SETS (
    (
        SPID SMALLINT,
        Status NVARCHAR(50),
        Login NVARCHAR(128),
        HostName NVARCHAR(128),
        BlkBy NVARCHAR(10),
        DBName NVARCHAR(128),
        Command NVARCHAR(50),
        CPUTime BIGINT,
        DiskIO BIGINT,
        LastBatch NVARCHAR(50),
        ProgramName NVARCHAR(128),
        SPID2 SMALLINT,
        RequestID INT
    )
);
GO

-- Pattern 12: Header row definition (for metadata)
EXEC dbo.GetEmployeeData
WITH RESULT SETS (
    (
        [Employee ID] INT,
        [First Name] NVARCHAR(50),
        [Last Name] NVARCHAR(50),
        [Annual Salary ($)] DECIMAL(18,2)
    )
);
GO

-- Pattern 13: Using FOR XML with result sets
CREATE PROCEDURE dbo.GetEmployeesXML
AS
BEGIN
    SELECT EmployeeID, FirstName, LastName
    FROM Employees
    FOR XML PATH('Employee'), ROOT('Employees');
END;
GO

EXEC dbo.GetEmployeesXML
WITH RESULT SETS (
    (
        XMLData XML
    )
);
GO

-- Pattern 14: Using FOR JSON with result sets
CREATE PROCEDURE dbo.GetEmployeesJSON
AS
BEGIN
    SELECT EmployeeID, FirstName, LastName
    FROM Employees
    FOR JSON PATH;
END;
GO

EXEC dbo.GetEmployeesJSON
WITH RESULT SETS (
    (
        JSONData NVARCHAR(MAX)
    )
);
GO

-- Pattern 15: Result set redefining computed columns
CREATE PROCEDURE dbo.GetComputedData
AS
BEGIN
    SELECT 
        ProductID,
        ProductName,
        Price * Quantity AS TotalValue,
        CASE WHEN Quantity > 0 THEN 'In Stock' ELSE 'Out of Stock' END AS StockStatus
    FROM Products;
END;
GO

EXEC dbo.GetComputedData
WITH RESULT SETS (
    (
        ID INT,
        Name NVARCHAR(100),
        Value MONEY,
        Status VARCHAR(20)
    )
);
GO
