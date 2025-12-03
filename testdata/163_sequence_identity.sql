-- Sample 163: Sequence and Identity Patterns
-- Category: Missing Syntax Elements / DDL
-- Complexity: Intermediate
-- Purpose: Parser testing - sequence and identity syntax
-- Features: CREATE SEQUENCE, IDENTITY, NEXT VALUE FOR, identity functions

-- Pattern 1: Basic IDENTITY column
CREATE TABLE #BasicIdentity (
    ID INT IDENTITY(1,1) PRIMARY KEY,
    Name VARCHAR(100)
);

INSERT INTO #BasicIdentity (Name) VALUES ('First'), ('Second'), ('Third');
SELECT * FROM #BasicIdentity;
DROP TABLE #BasicIdentity;
GO

-- Pattern 2: IDENTITY with different seed and increment
CREATE TABLE #CustomIdentity (
    ID INT IDENTITY(1000, 10) PRIMARY KEY,  -- Start at 1000, increment by 10
    Name VARCHAR(100)
);

INSERT INTO #CustomIdentity (Name) VALUES ('A'), ('B'), ('C');
SELECT * FROM #CustomIdentity;  -- 1000, 1010, 1020
DROP TABLE #CustomIdentity;
GO

-- Pattern 3: Negative increment
CREATE TABLE #NegativeIdentity (
    ID INT IDENTITY(0, -1) PRIMARY KEY,
    Name VARCHAR(100)
);

INSERT INTO #NegativeIdentity (Name) VALUES ('A'), ('B'), ('C');
SELECT * FROM #NegativeIdentity;  -- 0, -1, -2
DROP TABLE #NegativeIdentity;
GO

-- Pattern 4: IDENTITY with BIGINT
CREATE TABLE #BigIdentity (
    ID BIGINT IDENTITY(1,1) PRIMARY KEY,
    Data VARCHAR(100)
);
DROP TABLE #BigIdentity;
GO

-- Pattern 5: Getting identity values
CREATE TABLE #IdentityTest (
    ID INT IDENTITY(1,1) PRIMARY KEY,
    Name VARCHAR(100)
);

INSERT INTO #IdentityTest (Name) VALUES ('Test');

SELECT 
    SCOPE_IDENTITY() AS ScopeIdentity,      -- Last identity in current scope
    @@IDENTITY AS AtAtIdentity,              -- Last identity (any scope, including triggers)
    IDENT_CURRENT('#IdentityTest') AS IdentCurrent;  -- Current identity for table

DROP TABLE #IdentityTest;
GO

-- Pattern 6: IDENTITY_INSERT
CREATE TABLE #ManualIdentity (
    ID INT IDENTITY(1,1) PRIMARY KEY,
    Name VARCHAR(100)
);

-- Normal insert
INSERT INTO #ManualIdentity (Name) VALUES ('Auto 1');

-- Manual identity insert
SET IDENTITY_INSERT #ManualIdentity ON;
INSERT INTO #ManualIdentity (ID, Name) VALUES (100, 'Manual 100');
SET IDENTITY_INSERT #ManualIdentity OFF;

-- Back to auto
INSERT INTO #ManualIdentity (Name) VALUES ('Auto 101');  -- Gets 101

SELECT * FROM #ManualIdentity;
DROP TABLE #ManualIdentity;
GO

-- Pattern 7: Reseeding identity
CREATE TABLE #ReseedTest (
    ID INT IDENTITY(1,1) PRIMARY KEY,
    Name VARCHAR(100)
);

INSERT INTO #ReseedTest (Name) VALUES ('A'), ('B'), ('C');
SELECT * FROM #ReseedTest;  -- 1, 2, 3

-- Reseed to 100
DBCC CHECKIDENT ('#ReseedTest', RESEED, 100);

INSERT INTO #ReseedTest (Name) VALUES ('D');
SELECT * FROM #ReseedTest;  -- Now has ID 101

DROP TABLE #ReseedTest;
GO

-- Pattern 8: Basic SEQUENCE
CREATE SEQUENCE dbo.OrderNumberSeq
    AS INT
    START WITH 1000
    INCREMENT BY 1;

SELECT NEXT VALUE FOR dbo.OrderNumberSeq AS NextOrderNumber;
SELECT NEXT VALUE FOR dbo.OrderNumberSeq AS NextOrderNumber;
SELECT NEXT VALUE FOR dbo.OrderNumberSeq AS NextOrderNumber;

DROP SEQUENCE dbo.OrderNumberSeq;
GO

-- Pattern 9: SEQUENCE with all options
CREATE SEQUENCE dbo.FullOptionsSeq
    AS BIGINT
    START WITH 1
    INCREMENT BY 1
    MINVALUE 1
    MAXVALUE 999999999
    CYCLE
    CACHE 50;

SELECT NEXT VALUE FOR dbo.FullOptionsSeq;
DROP SEQUENCE dbo.FullOptionsSeq;
GO

-- Pattern 10: SEQUENCE NO CYCLE
CREATE SEQUENCE dbo.NoCycleSeq
    AS TINYINT
    START WITH 1
    INCREMENT BY 1
    MINVALUE 1
    MAXVALUE 255
    NO CYCLE;
    
DROP SEQUENCE dbo.NoCycleSeq;
GO

-- Pattern 11: SEQUENCE with NO CACHE
CREATE SEQUENCE dbo.NoCacheSeq
    AS INT
    START WITH 1
    INCREMENT BY 1
    NO CACHE;  -- More reliable but slower
    
DROP SEQUENCE dbo.NoCacheSeq;
GO

-- Pattern 12: Using SEQUENCE in INSERT
CREATE SEQUENCE dbo.CustomerSeq AS INT START WITH 1;

CREATE TABLE #SeqCustomers (
    CustomerID INT PRIMARY KEY,
    CustomerName VARCHAR(100)
);

INSERT INTO #SeqCustomers (CustomerID, CustomerName)
VALUES (NEXT VALUE FOR dbo.CustomerSeq, 'Customer A');

INSERT INTO #SeqCustomers (CustomerID, CustomerName)
VALUES (NEXT VALUE FOR dbo.CustomerSeq, 'Customer B');

SELECT * FROM #SeqCustomers;

DROP TABLE #SeqCustomers;
DROP SEQUENCE dbo.CustomerSeq;
GO

-- Pattern 13: SEQUENCE as default constraint
CREATE SEQUENCE dbo.AutoSeq AS INT START WITH 1;

CREATE TABLE #AutoSeqTable (
    ID INT PRIMARY KEY DEFAULT (NEXT VALUE FOR dbo.AutoSeq),
    Name VARCHAR(100)
);

INSERT INTO #AutoSeqTable (Name) VALUES ('Auto 1'), ('Auto 2');
SELECT * FROM #AutoSeqTable;

DROP TABLE #AutoSeqTable;
DROP SEQUENCE dbo.AutoSeq;
GO

-- Pattern 14: SEQUENCE in SELECT with OVER
CREATE SEQUENCE dbo.RowSeq AS INT START WITH 1;

SELECT 
    NEXT VALUE FOR dbo.RowSeq OVER (ORDER BY CustomerName) AS RowNum,
    CustomerID,
    CustomerName
FROM dbo.Customers
ORDER BY CustomerName;

DROP SEQUENCE dbo.RowSeq;
GO

-- Pattern 15: Multiple sequences in one statement
CREATE SEQUENCE dbo.Seq1 AS INT START WITH 100;
CREATE SEQUENCE dbo.Seq2 AS INT START WITH 200;

SELECT 
    NEXT VALUE FOR dbo.Seq1 AS ID1,
    NEXT VALUE FOR dbo.Seq2 AS ID2;

DROP SEQUENCE dbo.Seq1;
DROP SEQUENCE dbo.Seq2;
GO

-- Pattern 16: Querying sequence metadata
SELECT 
    name,
    start_value,
    increment,
    minimum_value,
    maximum_value,
    is_cycling,
    current_value
FROM sys.sequences
WHERE schema_id = SCHEMA_ID('dbo');
GO

-- Pattern 17: ALTER SEQUENCE
CREATE SEQUENCE dbo.AlterableSeq AS INT START WITH 1;

-- Restart the sequence
ALTER SEQUENCE dbo.AlterableSeq RESTART WITH 100;

-- Change increment
ALTER SEQUENCE dbo.AlterableSeq INCREMENT BY 5;

-- Change min/max
ALTER SEQUENCE dbo.AlterableSeq
    MINVALUE 0
    MAXVALUE 10000;

-- Enable cycling
ALTER SEQUENCE dbo.AlterableSeq CYCLE;

-- Change cache
ALTER SEQUENCE dbo.AlterableSeq CACHE 100;

DROP SEQUENCE dbo.AlterableSeq;
GO

-- Pattern 18: sp_sequence_get_range for batch allocation
CREATE SEQUENCE dbo.BatchSeq AS BIGINT START WITH 1;

DECLARE @FirstValue SQL_VARIANT, @LastValue SQL_VARIANT;

EXEC sp_sequence_get_range 
    @sequence_name = N'dbo.BatchSeq',
    @range_size = 100,
    @range_first_value = @FirstValue OUTPUT,
    @range_last_value = @LastValue OUTPUT;

SELECT 
    @FirstValue AS FirstAllocated,
    @LastValue AS LastAllocated;

DROP SEQUENCE dbo.BatchSeq;
GO

-- Pattern 19: IDENTITY vs SEQUENCE comparison
-- IDENTITY: Table-specific, auto-insert, gaps on rollback
-- SEQUENCE: Shared across tables, explicit use, more control

CREATE SEQUENCE dbo.SharedSeq AS INT START WITH 1;

CREATE TABLE #Orders (
    OrderID INT PRIMARY KEY DEFAULT (NEXT VALUE FOR dbo.SharedSeq),
    OrderDate DATE
);

CREATE TABLE #Invoices (
    InvoiceID INT PRIMARY KEY DEFAULT (NEXT VALUE FOR dbo.SharedSeq),
    InvoiceDate DATE
);

INSERT INTO #Orders (OrderDate) VALUES (GETDATE());   -- Gets 1
INSERT INTO #Invoices (InvoiceDate) VALUES (GETDATE()); -- Gets 2
INSERT INTO #Orders (OrderDate) VALUES (GETDATE());   -- Gets 3

SELECT 'Orders' AS TableName, * FROM #Orders
UNION ALL
SELECT 'Invoices', InvoiceID, InvoiceDate FROM #Invoices;

DROP TABLE #Orders;
DROP TABLE #Invoices;
DROP SEQUENCE dbo.SharedSeq;
GO

-- Pattern 20: IDENT_INCR and IDENT_SEED functions
CREATE TABLE #IdentInfo (
    ID INT IDENTITY(100, 5) PRIMARY KEY,
    Name VARCHAR(100)
);

SELECT 
    IDENT_SEED('#IdentInfo') AS Seed,      -- 100
    IDENT_INCR('#IdentInfo') AS Increment; -- 5

DROP TABLE #IdentInfo;
GO
