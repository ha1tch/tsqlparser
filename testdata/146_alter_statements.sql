-- Sample 146: ALTER Statements Comprehensive Coverage
-- Category: Schema Scripts / DDL
-- Complexity: Complex
-- Purpose: Parser testing - all ALTER statement variations
-- Features: ALTER for all object types, options, syntax variations

-- Pattern 1: ALTER TABLE - Add columns
ALTER TABLE dbo.Customers ADD MiddleName NVARCHAR(50) NULL;
ALTER TABLE dbo.Customers ADD 
    Suffix NVARCHAR(10) NULL,
    Prefix NVARCHAR(10) NULL,
    NickName NVARCHAR(50) NULL;
GO

-- Pattern 2: ALTER TABLE - Modify column
ALTER TABLE dbo.Customers ALTER COLUMN MiddleName NVARCHAR(100);
ALTER TABLE dbo.Customers ALTER COLUMN MiddleName NVARCHAR(100) NOT NULL;
ALTER TABLE dbo.Customers ALTER COLUMN Phone VARCHAR(30) NULL;
GO

-- Pattern 3: ALTER TABLE - Drop column
ALTER TABLE dbo.Customers DROP COLUMN MiddleName;
ALTER TABLE dbo.Customers DROP COLUMN Suffix, Prefix, NickName;
GO

-- Pattern 4: ALTER TABLE - Add constraints
ALTER TABLE dbo.Customers ADD CONSTRAINT PK_Customers PRIMARY KEY (CustomerID);
ALTER TABLE dbo.Customers ADD CONSTRAINT UQ_Customers_Email UNIQUE (Email);
ALTER TABLE dbo.Customers ADD CONSTRAINT CK_Customers_Age CHECK (Age >= 0 AND Age <= 150);
ALTER TABLE dbo.Customers ADD CONSTRAINT DF_Customers_Active DEFAULT (1) FOR IsActive;
ALTER TABLE dbo.Orders ADD CONSTRAINT FK_Orders_Customers 
    FOREIGN KEY (CustomerID) REFERENCES dbo.Customers(CustomerID)
    ON DELETE CASCADE ON UPDATE CASCADE;
GO

-- Pattern 5: ALTER TABLE - Drop constraints
ALTER TABLE dbo.Customers DROP CONSTRAINT CK_Customers_Age;
ALTER TABLE dbo.Customers DROP CONSTRAINT DF_Customers_Active;
ALTER TABLE dbo.Orders DROP CONSTRAINT FK_Orders_Customers;
GO

-- Pattern 6: ALTER TABLE - Enable/Disable constraints
ALTER TABLE dbo.Customers NOCHECK CONSTRAINT CK_Customers_Age;
ALTER TABLE dbo.Customers CHECK CONSTRAINT CK_Customers_Age;
ALTER TABLE dbo.Customers NOCHECK CONSTRAINT ALL;
ALTER TABLE dbo.Customers CHECK CONSTRAINT ALL;
GO

-- Pattern 7: ALTER TABLE - Enable/Disable triggers
ALTER TABLE dbo.Customers DISABLE TRIGGER trg_Customers_Insert;
ALTER TABLE dbo.Customers ENABLE TRIGGER trg_Customers_Insert;
ALTER TABLE dbo.Customers DISABLE TRIGGER ALL;
ALTER TABLE dbo.Customers ENABLE TRIGGER ALL;
GO

-- Pattern 8: ALTER TABLE - Switch partition
ALTER TABLE dbo.SalesHistory SWITCH PARTITION 1 TO dbo.SalesArchive PARTITION 1;
ALTER TABLE dbo.SalesStaging SWITCH TO dbo.SalesHistory PARTITION 5;
GO

-- Pattern 9: ALTER TABLE - Rebuild
ALTER TABLE dbo.Customers REBUILD;
ALTER TABLE dbo.Customers REBUILD WITH (DATA_COMPRESSION = PAGE);
ALTER TABLE dbo.Customers REBUILD PARTITION = ALL WITH (DATA_COMPRESSION = ROW);
GO

-- Pattern 10: ALTER TABLE - Set options
ALTER TABLE dbo.Customers SET (LOCK_ESCALATION = TABLE);
ALTER TABLE dbo.Customers SET (LOCK_ESCALATION = AUTO);
ALTER TABLE dbo.Customers SET (LOCK_ESCALATION = DISABLE);
GO

-- Pattern 11: ALTER INDEX
ALTER INDEX IX_Customers_Name ON dbo.Customers REBUILD;
ALTER INDEX IX_Customers_Name ON dbo.Customers REORGANIZE;
ALTER INDEX IX_Customers_Name ON dbo.Customers DISABLE;
ALTER INDEX ALL ON dbo.Customers REBUILD;
ALTER INDEX ALL ON dbo.Customers REORGANIZE;

ALTER INDEX IX_Customers_Name ON dbo.Customers REBUILD WITH (
    FILLFACTOR = 80,
    PAD_INDEX = ON,
    SORT_IN_TEMPDB = ON,
    ONLINE = ON,
    RESUMABLE = ON,
    MAX_DURATION = 60
);
GO

-- Pattern 12: ALTER VIEW
ALTER VIEW dbo.vw_ActiveCustomers
AS
SELECT CustomerID, FirstName, LastName, Email
FROM dbo.Customers
WHERE IsActive = 1;
GO

ALTER VIEW dbo.vw_ActiveCustomers
WITH SCHEMABINDING
AS
SELECT CustomerID, FirstName, LastName, Email
FROM dbo.Customers
WHERE IsActive = 1;
GO

-- Pattern 13: ALTER PROCEDURE
ALTER PROCEDURE dbo.GetCustomerOrders
    @CustomerID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT * FROM dbo.Orders WHERE CustomerID = @CustomerID;
END;
GO

ALTER PROCEDURE dbo.GetCustomerOrders
    @CustomerID INT,
    @StartDate DATE = NULL
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SELECT * FROM dbo.Orders 
    WHERE CustomerID = @CustomerID
    AND (@StartDate IS NULL OR OrderDate >= @StartDate);
END;
GO

-- Pattern 14: ALTER FUNCTION
ALTER FUNCTION dbo.GetFullName(@FirstName NVARCHAR(50), @LastName NVARCHAR(50))
RETURNS NVARCHAR(101)
AS
BEGIN
    RETURN @FirstName + ' ' + @LastName;
END;
GO

-- Pattern 15: ALTER TRIGGER
ALTER TRIGGER dbo.trg_Customers_Insert
ON dbo.Customers
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.AuditLog (TableName, Action, RecordID)
    SELECT 'Customers', 'INSERT', CustomerID FROM inserted;
END;
GO

-- Pattern 16: ALTER DATABASE - Basic options
ALTER DATABASE MyDatabase SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
ALTER DATABASE MyDatabase SET MULTI_USER;
ALTER DATABASE MyDatabase SET READ_ONLY;
ALTER DATABASE MyDatabase SET READ_WRITE;
ALTER DATABASE MyDatabase SET OFFLINE;
ALTER DATABASE MyDatabase SET ONLINE;
GO

-- Pattern 17: ALTER DATABASE - Recovery and compatibility
ALTER DATABASE MyDatabase SET RECOVERY SIMPLE;
ALTER DATABASE MyDatabase SET RECOVERY FULL;
ALTER DATABASE MyDatabase SET RECOVERY BULK_LOGGED;
ALTER DATABASE MyDatabase SET COMPATIBILITY_LEVEL = 150;
ALTER DATABASE MyDatabase SET COMPATIBILITY_LEVEL = 160;
GO

-- Pattern 18: ALTER DATABASE - Query store
ALTER DATABASE MyDatabase SET QUERY_STORE = ON;
ALTER DATABASE MyDatabase SET QUERY_STORE = OFF;
ALTER DATABASE MyDatabase SET QUERY_STORE (
    OPERATION_MODE = READ_WRITE,
    MAX_STORAGE_SIZE_MB = 1000,
    INTERVAL_LENGTH_MINUTES = 60
);
ALTER DATABASE MyDatabase SET QUERY_STORE CLEAR;
GO

-- Pattern 19: ALTER DATABASE - Files
ALTER DATABASE MyDatabase ADD FILE (
    NAME = 'MyDatabase_Data2',
    FILENAME = 'D:\Data\MyDatabase_Data2.ndf',
    SIZE = 100MB,
    MAXSIZE = 1GB,
    FILEGROWTH = 100MB
);
ALTER DATABASE MyDatabase MODIFY FILE (NAME = 'MyDatabase_Data', SIZE = 500MB);
ALTER DATABASE MyDatabase REMOVE FILE 'MyDatabase_Data2';
GO

-- Pattern 20: ALTER DATABASE - Filegroups
ALTER DATABASE MyDatabase ADD FILEGROUP FG_Historical;
ALTER DATABASE MyDatabase MODIFY FILEGROUP FG_Historical DEFAULT;
ALTER DATABASE MyDatabase MODIFY FILEGROUP FG_Historical READ_ONLY;
ALTER DATABASE MyDatabase MODIFY FILEGROUP FG_Historical READ_WRITE;
ALTER DATABASE MyDatabase REMOVE FILEGROUP FG_Historical;
GO

-- Pattern 21: ALTER DATABASE - Collation
ALTER DATABASE MyDatabase COLLATE Latin1_General_CI_AS;
GO

-- Pattern 22: ALTER LOGIN
ALTER LOGIN MyLogin WITH PASSWORD = 'NewP@ssw0rd!';
ALTER LOGIN MyLogin WITH PASSWORD = 'NewP@ssw0rd!' OLD_PASSWORD = 'OldP@ssw0rd!';
ALTER LOGIN MyLogin ENABLE;
ALTER LOGIN MyLogin DISABLE;
ALTER LOGIN MyLogin WITH DEFAULT_DATABASE = MyDatabase;
ALTER LOGIN MyLogin WITH NAME = NewLoginName;
GO

-- Pattern 23: ALTER USER
ALTER USER MyUser WITH NAME = NewUserName;
ALTER USER MyUser WITH DEFAULT_SCHEMA = Sales;
ALTER USER MyUser WITH LOGIN = MyLogin;
GO

-- Pattern 24: ALTER ROLE
ALTER ROLE db_datareader ADD MEMBER MyUser;
ALTER ROLE db_datawriter ADD MEMBER MyUser;
ALTER ROLE db_datareader DROP MEMBER MyUser;
ALTER ROLE MyCustomRole WITH NAME = RenamedRole;
GO

-- Pattern 25: ALTER SCHEMA
ALTER SCHEMA Sales TRANSFER dbo.Customers;
ALTER SCHEMA dbo TRANSFER Sales.Orders;
GO

-- Pattern 26: ALTER SEQUENCE
ALTER SEQUENCE dbo.OrderNumberSeq RESTART WITH 10000;
ALTER SEQUENCE dbo.OrderNumberSeq INCREMENT BY 5;
ALTER SEQUENCE dbo.OrderNumberSeq MINVALUE 1 MAXVALUE 99999;
ALTER SEQUENCE dbo.OrderNumberSeq CYCLE;
ALTER SEQUENCE dbo.OrderNumberSeq NO CYCLE;
GO

-- Pattern 27: ALTER SERVICE
ALTER SERVICE MyService (QUEUE = dbo.NewQueue);
GO

-- Pattern 28: ALTER QUEUE
ALTER QUEUE dbo.MyQueue WITH STATUS = ON;
ALTER QUEUE dbo.MyQueue WITH STATUS = OFF;
ALTER QUEUE dbo.MyQueue WITH ACTIVATION (STATUS = ON, MAX_QUEUE_READERS = 5);
GO
