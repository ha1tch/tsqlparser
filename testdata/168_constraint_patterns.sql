-- Sample 168: Constraint Patterns
-- Category: DDL / Syntax Coverage
-- Complexity: Complex
-- Purpose: Parser testing - constraint syntax variations
-- Features: PRIMARY KEY, FOREIGN KEY, UNIQUE, CHECK, DEFAULT

-- Pattern 1: Inline PRIMARY KEY
CREATE TABLE #InlinePK (
    ID INT PRIMARY KEY,
    Name VARCHAR(100)
);
DROP TABLE #InlinePK;
GO

-- Pattern 2: Named inline PRIMARY KEY
CREATE TABLE #NamedInlinePK (
    ID INT CONSTRAINT PK_NamedInline PRIMARY KEY,
    Name VARCHAR(100)
);
DROP TABLE #NamedInlinePK;
GO

-- Pattern 3: Table-level PRIMARY KEY
CREATE TABLE #TablePK (
    ID INT NOT NULL,
    Name VARCHAR(100),
    CONSTRAINT PK_TablePK PRIMARY KEY (ID)
);
DROP TABLE #TablePK;
GO

-- Pattern 4: Composite PRIMARY KEY
CREATE TABLE #CompositePK (
    OrderID INT NOT NULL,
    LineNumber INT NOT NULL,
    ProductID INT,
    CONSTRAINT PK_OrderLine PRIMARY KEY (OrderID, LineNumber)
);
DROP TABLE #CompositePK;
GO

-- Pattern 5: PRIMARY KEY with options
CREATE TABLE #PKOptions (
    ID INT NOT NULL,
    CONSTRAINT PK_Options PRIMARY KEY CLUSTERED (ID)
        WITH (FILLFACTOR = 90, PAD_INDEX = ON)
);
DROP TABLE #PKOptions;
GO

-- Pattern 6: PRIMARY KEY NONCLUSTERED
CREATE TABLE #PKNonclustered (
    ID INT NOT NULL,
    OrderDate DATE NOT NULL,
    CONSTRAINT PK_Nonclustered PRIMARY KEY NONCLUSTERED (ID),
    INDEX IX_Clustered CLUSTERED (OrderDate)
);
DROP TABLE #PKNonclustered;
GO

-- Pattern 7: Inline FOREIGN KEY
CREATE TABLE #InlineFK (
    ID INT PRIMARY KEY,
    CustomerID INT REFERENCES dbo.Customers(CustomerID),
    Name VARCHAR(100)
);
DROP TABLE #InlineFK;
GO

-- Pattern 8: Named inline FOREIGN KEY
CREATE TABLE #NamedInlineFK (
    ID INT PRIMARY KEY,
    CustomerID INT CONSTRAINT FK_Customer REFERENCES dbo.Customers(CustomerID),
    Name VARCHAR(100)
);
DROP TABLE #NamedInlineFK;
GO

-- Pattern 9: Table-level FOREIGN KEY
CREATE TABLE #TableFK (
    ID INT PRIMARY KEY,
    CustomerID INT NOT NULL,
    CONSTRAINT FK_TableFK_Customer 
        FOREIGN KEY (CustomerID) REFERENCES dbo.Customers(CustomerID)
);
DROP TABLE #TableFK;
GO

-- Pattern 10: FOREIGN KEY with ON DELETE/UPDATE
CREATE TABLE #FKCascade (
    ID INT PRIMARY KEY,
    CustomerID INT,
    CONSTRAINT FK_Cascade FOREIGN KEY (CustomerID) 
        REFERENCES dbo.Customers(CustomerID)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);
DROP TABLE #FKCascade;
GO

-- Pattern 11: FOREIGN KEY with SET NULL
CREATE TABLE #FKSetNull (
    ID INT PRIMARY KEY,
    CustomerID INT NULL,
    CONSTRAINT FK_SetNull FOREIGN KEY (CustomerID) 
        REFERENCES dbo.Customers(CustomerID)
        ON DELETE SET NULL
        ON UPDATE SET NULL
);
DROP TABLE #FKSetNull;
GO

-- Pattern 12: FOREIGN KEY with SET DEFAULT
CREATE TABLE #FKSetDefault (
    ID INT PRIMARY KEY,
    CustomerID INT DEFAULT 1,
    CONSTRAINT FK_SetDefault FOREIGN KEY (CustomerID) 
        REFERENCES dbo.Customers(CustomerID)
        ON DELETE SET DEFAULT
        ON UPDATE SET DEFAULT
);
DROP TABLE #FKSetDefault;
GO

-- Pattern 13: FOREIGN KEY with NO ACTION (default)
CREATE TABLE #FKNoAction (
    ID INT PRIMARY KEY,
    CustomerID INT,
    CONSTRAINT FK_NoAction FOREIGN KEY (CustomerID) 
        REFERENCES dbo.Customers(CustomerID)
        ON DELETE NO ACTION
        ON UPDATE NO ACTION
);
DROP TABLE #FKNoAction;
GO

-- Pattern 14: Composite FOREIGN KEY
CREATE TABLE #CompositeFK (
    ID INT PRIMARY KEY,
    OrderID INT,
    LineNumber INT,
    CONSTRAINT FK_OrderLine FOREIGN KEY (OrderID, LineNumber)
        REFERENCES dbo.OrderDetails(OrderID, LineNumber)
);
DROP TABLE #CompositeFK;
GO

-- Pattern 15: Inline UNIQUE
CREATE TABLE #InlineUnique (
    ID INT PRIMARY KEY,
    Email VARCHAR(200) UNIQUE,
    Name VARCHAR(100)
);
DROP TABLE #InlineUnique;
GO

-- Pattern 16: Named inline UNIQUE
CREATE TABLE #NamedInlineUnique (
    ID INT PRIMARY KEY,
    Email VARCHAR(200) CONSTRAINT UQ_Email UNIQUE,
    Name VARCHAR(100)
);
DROP TABLE #NamedInlineUnique;
GO

-- Pattern 17: Table-level UNIQUE
CREATE TABLE #TableUnique (
    ID INT PRIMARY KEY,
    Email VARCHAR(200),
    Phone VARCHAR(20),
    CONSTRAINT UQ_Contact UNIQUE (Email, Phone)
);
DROP TABLE #TableUnique;
GO

-- Pattern 18: UNIQUE with options
CREATE TABLE #UniqueOptions (
    ID INT PRIMARY KEY,
    Code VARCHAR(50),
    CONSTRAINT UQ_Code UNIQUE NONCLUSTERED (Code)
        WITH (FILLFACTOR = 90)
);
DROP TABLE #UniqueOptions;
GO

-- Pattern 19: Inline CHECK
CREATE TABLE #InlineCheck (
    ID INT PRIMARY KEY,
    Age INT CHECK (Age >= 0 AND Age <= 150),
    Status VARCHAR(20) CHECK (Status IN ('Active', 'Inactive', 'Pending'))
);
DROP TABLE #InlineCheck;
GO

-- Pattern 20: Named inline CHECK
CREATE TABLE #NamedInlineCheck (
    ID INT PRIMARY KEY,
    Quantity INT CONSTRAINT CK_Quantity CHECK (Quantity > 0),
    Price DECIMAL(10,2) CONSTRAINT CK_Price CHECK (Price >= 0)
);
DROP TABLE #NamedInlineCheck;
GO

-- Pattern 21: Table-level CHECK
CREATE TABLE #TableCheck (
    ID INT PRIMARY KEY,
    StartDate DATE,
    EndDate DATE,
    MinValue INT,
    MaxValue INT,
    CONSTRAINT CK_DateRange CHECK (EndDate >= StartDate),
    CONSTRAINT CK_ValueRange CHECK (MaxValue >= MinValue)
);
DROP TABLE #TableCheck;
GO

-- Pattern 22: CHECK with complex expression
CREATE TABLE #ComplexCheck (
    ID INT PRIMARY KEY,
    Email VARCHAR(200),
    Phone VARCHAR(20),
    CONSTRAINT CK_Contact CHECK (Email IS NOT NULL OR Phone IS NOT NULL),
    CONSTRAINT CK_EmailFormat CHECK (Email LIKE '%@%.%')
);
DROP TABLE #ComplexCheck;
GO

-- Pattern 23: Inline DEFAULT
CREATE TABLE #InlineDefault (
    ID INT PRIMARY KEY,
    CreatedDate DATETIME DEFAULT GETDATE(),
    IsActive BIT DEFAULT 1,
    Status VARCHAR(20) DEFAULT 'Pending'
);
DROP TABLE #InlineDefault;
GO

-- Pattern 24: Named inline DEFAULT
CREATE TABLE #NamedInlineDefault (
    ID INT PRIMARY KEY,
    CreatedDate DATETIME CONSTRAINT DF_Created DEFAULT GETDATE(),
    ModifiedDate DATETIME CONSTRAINT DF_Modified DEFAULT GETDATE()
);
DROP TABLE #NamedInlineDefault;
GO

-- Pattern 25: DEFAULT with functions
CREATE TABLE #FunctionDefault (
    ID INT PRIMARY KEY,
    GUID UNIQUEIDENTIFIER DEFAULT NEWID(),
    SequentialGUID UNIQUEIDENTIFIER DEFAULT NEWSEQUENTIALID(),
    UserName VARCHAR(100) DEFAULT SUSER_SNAME(),
    HostName VARCHAR(100) DEFAULT HOST_NAME()
);
DROP TABLE #FunctionDefault;
GO

-- Pattern 26: ADD CONSTRAINT
ALTER TABLE dbo.Customers
ADD CONSTRAINT PK_Customers PRIMARY KEY (CustomerID);

ALTER TABLE dbo.Orders
ADD CONSTRAINT FK_Orders_Customers 
    FOREIGN KEY (CustomerID) REFERENCES dbo.Customers(CustomerID);

ALTER TABLE dbo.Products
ADD CONSTRAINT UQ_Products_SKU UNIQUE (SKU);

ALTER TABLE dbo.Employees
ADD CONSTRAINT CK_Employees_Age CHECK (Age >= 18);

ALTER TABLE dbo.Logs
ADD CONSTRAINT DF_Logs_Created DEFAULT GETDATE() FOR CreatedDate;
GO

-- Pattern 27: DROP CONSTRAINT
ALTER TABLE dbo.Customers DROP CONSTRAINT PK_Customers;
ALTER TABLE dbo.Orders DROP CONSTRAINT FK_Orders_Customers;
ALTER TABLE dbo.Products DROP CONSTRAINT UQ_Products_SKU;
ALTER TABLE dbo.Employees DROP CONSTRAINT CK_Employees_Age;
ALTER TABLE dbo.Logs DROP CONSTRAINT DF_Logs_Created;
GO

-- Pattern 28: NOCHECK / CHECK constraint
ALTER TABLE dbo.Orders NOCHECK CONSTRAINT FK_Orders_Customers;
ALTER TABLE dbo.Orders CHECK CONSTRAINT FK_Orders_Customers;
ALTER TABLE dbo.Orders NOCHECK CONSTRAINT ALL;
ALTER TABLE dbo.Orders CHECK CONSTRAINT ALL;
GO

-- Pattern 29: WITH CHECK / WITH NOCHECK
ALTER TABLE dbo.Orders WITH CHECK 
ADD CONSTRAINT FK_New FOREIGN KEY (CustomerID) REFERENCES dbo.Customers(CustomerID);

ALTER TABLE dbo.Orders WITH NOCHECK 
ADD CONSTRAINT CK_New CHECK (TotalAmount > 0);
GO

-- Pattern 30: Constraint on computed column
CREATE TABLE #ComputedCheck (
    ID INT PRIMARY KEY,
    Quantity INT,
    UnitPrice DECIMAL(10,2),
    LineTotal AS (Quantity * UnitPrice),
    CONSTRAINT CK_LineTotal CHECK (Quantity * UnitPrice <= 100000)
);
DROP TABLE #ComputedCheck;
GO
