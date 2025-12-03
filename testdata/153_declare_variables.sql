-- Sample 153: DECLARE and Variable Patterns
-- Category: Syntax Edge Cases / Bare Statements
-- Complexity: Intermediate
-- Purpose: Parser testing - variable declaration syntax variations
-- Features: DECLARE variations, table variables, initialization, scope

-- Pattern 1: Basic DECLARE
DECLARE @x INT;
DECLARE @Name VARCHAR(100);
DECLARE @Amount DECIMAL(18,2);
GO

-- Pattern 2: DECLARE with initialization
DECLARE @x INT = 10;
DECLARE @Name VARCHAR(100) = 'John';
DECLARE @Today DATE = GETDATE();
DECLARE @Guid UNIQUEIDENTIFIER = NEWID();
GO

-- Pattern 3: Multiple variables in single DECLARE
DECLARE 
    @FirstName VARCHAR(50),
    @LastName VARCHAR(50),
    @Age INT,
    @IsActive BIT;
GO

-- Pattern 4: Multiple variables with initialization
DECLARE 
    @StartDate DATE = '2024-01-01',
    @EndDate DATE = '2024-12-31',
    @PageSize INT = 25,
    @PageNumber INT = 1;
GO

-- Pattern 5: All data types
DECLARE @TinyInt TINYINT = 255;
DECLARE @SmallInt SMALLINT = 32767;
DECLARE @Int INT = 2147483647;
DECLARE @BigInt BIGINT = 9223372036854775807;
DECLARE @Decimal DECIMAL(38,10) = 12345678901234567890.1234567890;
DECLARE @Numeric NUMERIC(18,4) = 1234567890.1234;
DECLARE @Money MONEY = 922337203685477.5807;
DECLARE @SmallMoney SMALLMONEY = 214748.3647;
DECLARE @Float FLOAT = 1.79E+308;
DECLARE @Real REAL = 3.40E+38;
DECLARE @Date DATE = '2024-06-15';
DECLARE @Time TIME = '14:30:45.1234567';
DECLARE @DateTime DATETIME = '2024-06-15 14:30:45.123';
DECLARE @DateTime2 DATETIME2(7) = '2024-06-15 14:30:45.1234567';
DECLARE @SmallDateTime SMALLDATETIME = '2024-06-15 14:30';
DECLARE @DateTimeOffset DATETIMEOFFSET = '2024-06-15 14:30:45 +05:30';
DECLARE @Char CHAR(10) = 'Fixed     ';
DECLARE @VarChar VARCHAR(MAX) = 'Variable length';
DECLARE @NChar NCHAR(10) = N'Unicode   ';
DECLARE @NVarChar NVARCHAR(MAX) = N'Unicode variable';
DECLARE @Binary BINARY(10) = 0x0102030405;
DECLARE @VarBinary VARBINARY(MAX) = 0x0102030405060708090A;
DECLARE @Bit BIT = 1;
DECLARE @UniqueId UNIQUEIDENTIFIER = 'A0EEBC99-9C0B-4EF8-BB6D-6BB9BD380A11';
DECLARE @Xml XML = '<root><item>value</item></root>';
DECLARE @SqlVariant SQL_VARIANT = 'Can hold any type';
GO

-- Pattern 6: Variable with expression initialization
DECLARE @Tomorrow DATE = DATEADD(DAY, 1, GETDATE());
DECLARE @RandomNum INT = ABS(CHECKSUM(NEWID())) % 100;
DECLARE @FullName VARCHAR(100) = 'John' + ' ' + 'Smith';
DECLARE @Calculated DECIMAL(10,2) = 100.00 * 1.1;
GO

-- Pattern 7: Variable from subquery (not in DECLARE, use SET/SELECT)
DECLARE @MaxID INT;
DECLARE @CustomerCount INT;
DECLARE @TotalSales DECIMAL(18,2);

SET @MaxID = (SELECT MAX(CustomerID) FROM dbo.Customers);
SELECT @CustomerCount = COUNT(*) FROM dbo.Customers;
SELECT @TotalSales = SUM(TotalAmount) FROM dbo.Orders;
GO

-- Pattern 8: Table variable basic
DECLARE @Results TABLE (
    ID INT,
    Name VARCHAR(100),
    Value DECIMAL(10,2)
);

INSERT INTO @Results VALUES (1, 'Item1', 10.00);
INSERT INTO @Results VALUES (2, 'Item2', 20.00);

SELECT * FROM @Results;
GO

-- Pattern 9: Table variable with constraints
DECLARE @Customers TABLE (
    CustomerID INT PRIMARY KEY,
    Email VARCHAR(200) UNIQUE NOT NULL,
    FirstName VARCHAR(50) NOT NULL,
    LastName VARCHAR(50) NOT NULL,
    CreatedDate DATETIME DEFAULT GETDATE()
);
GO

-- Pattern 10: Table variable with identity
DECLARE @AutoID TABLE (
    ID INT IDENTITY(1,1) PRIMARY KEY,
    Name VARCHAR(100),
    CreatedAt DATETIME2 DEFAULT SYSDATETIME()
);

INSERT INTO @AutoID (Name) VALUES ('First'), ('Second'), ('Third');
SELECT * FROM @AutoID;
GO

-- Pattern 11: Table variable with computed column
DECLARE @Products TABLE (
    ProductID INT,
    ProductName VARCHAR(100),
    Quantity INT,
    UnitPrice DECIMAL(10,2),
    LineTotal AS (Quantity * UnitPrice)
);

INSERT INTO @Products VALUES (1, 'Widget', 5, 10.00);
SELECT * FROM @Products;
GO

-- Pattern 12: Table variable with index (SQL Server 2014+)
DECLARE @IndexedTable TABLE (
    ID INT PRIMARY KEY NONCLUSTERED,
    Category VARCHAR(50),
    Value INT,
    INDEX IX_Category CLUSTERED (Category)
);
GO

-- Pattern 13: Table variable with multiple indexes
DECLARE @MultiIndex TABLE (
    ID INT,
    Col1 VARCHAR(50),
    Col2 INT,
    Col3 DATE,
    PRIMARY KEY CLUSTERED (ID),
    INDEX IX_Col1 NONCLUSTERED (Col1),
    INDEX IX_Col2_Col3 NONCLUSTERED (Col2, Col3)
);
GO

-- Pattern 14: Cursor variable
DECLARE @MyCursor CURSOR;

SET @MyCursor = CURSOR FOR
    SELECT CustomerID, CustomerName FROM dbo.Customers;

OPEN @MyCursor;
-- Use cursor...
CLOSE @MyCursor;
DEALLOCATE @MyCursor;
GO

-- Pattern 15: XML variable with typed XML
DECLARE @TypedXml XML(dbo.MyXmlSchema);
DECLARE @UntypedXml XML = '<data><item id="1">Value</item></data>';
GO

-- Pattern 16: Variables in different scopes
DECLARE @OuterVar INT = 100;

BEGIN
    DECLARE @InnerVar INT = 200;
    SELECT @OuterVar AS OuterVar, @InnerVar AS InnerVar;
END

-- @InnerVar still accessible (T-SQL doesn't have block scope for variables)
SELECT @OuterVar AS OuterVar;
GO

-- Pattern 17: Variable assignment methods
DECLARE @Value INT;

-- SET assignment
SET @Value = 10;

-- SELECT assignment (can assign multiple)
SELECT @Value = 20;

-- SELECT from table (gets last row if multiple)
SELECT @Value = CustomerID FROM dbo.Customers WHERE CustomerID <= 5;

-- SET from subquery
SET @Value = (SELECT MAX(CustomerID) FROM dbo.Customers);
GO

-- Pattern 18: Multiple variable assignment with SELECT
DECLARE @ID INT, @Name VARCHAR(100), @Date DATE;

SELECT 
    @ID = CustomerID,
    @Name = CustomerName,
    @Date = CreatedDate
FROM dbo.Customers
WHERE CustomerID = 1;

SELECT @ID AS ID, @Name AS Name, @Date AS Date;
GO

-- Pattern 19: Variable in OUTPUT clause
DECLARE @InsertedID INT;
DECLARE @InsertedIDs TABLE (ID INT);

INSERT INTO dbo.Customers (CustomerName)
OUTPUT inserted.CustomerID INTO @InsertedIDs
VALUES ('New Customer');

SELECT @InsertedID = ID FROM @InsertedIDs;
GO

-- Pattern 20: Variable scope in stored procedure
CREATE PROCEDURE dbo.VariableScopes
AS
BEGIN
    DECLARE @ProcVar INT = 1;
    
    -- Variable visible throughout procedure
    IF @ProcVar = 1
    BEGIN
        DECLARE @BlockVar INT = 2;
        SET @ProcVar = @BlockVar;
    END
    
    -- @BlockVar still accessible
    SELECT @ProcVar, @BlockVar;
END;
GO

DROP PROCEDURE IF EXISTS dbo.VariableScopes;
GO

-- Pattern 21: Table variable vs temp table comparison
-- Table variable (no statistics, in memory for small sets)
DECLARE @TableVar TABLE (ID INT PRIMARY KEY, Name VARCHAR(100));
INSERT INTO @TableVar VALUES (1, 'A'), (2, 'B');

-- Temp table (has statistics, can have indexes)
CREATE TABLE #TempTable (ID INT PRIMARY KEY, Name VARCHAR(100));
INSERT INTO #TempTable VALUES (1, 'A'), (2, 'B');

SELECT * FROM @TableVar;
SELECT * FROM #TempTable;

DROP TABLE #TempTable;
GO
