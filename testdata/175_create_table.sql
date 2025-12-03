-- Sample 175: Table Creation With All Features
-- Category: DDL / Syntax Coverage
-- Complexity: Advanced
-- Purpose: Parser testing - CREATE TABLE syntax variations
-- Features: All column options, constraints, table options

-- Pattern 1: Basic table
CREATE TABLE dbo.BasicTable (
    ID INT,
    Name VARCHAR(100),
    Value DECIMAL(10,2)
);
DROP TABLE dbo.BasicTable;
GO

-- Pattern 2: Table with primary key
CREATE TABLE dbo.TableWithPK (
    ID INT PRIMARY KEY,
    Name VARCHAR(100)
);
DROP TABLE dbo.TableWithPK;
GO

-- Pattern 3: Table with all column constraints
CREATE TABLE dbo.FullConstraints (
    ID INT IDENTITY(1,1) PRIMARY KEY,
    Email VARCHAR(200) UNIQUE NOT NULL,
    Age INT CHECK (Age >= 0 AND Age <= 150),
    Status VARCHAR(20) DEFAULT 'Active',
    CategoryID INT REFERENCES dbo.Categories(CategoryID)
);
DROP TABLE dbo.FullConstraints;
GO

-- Pattern 4: Table with named constraints
CREATE TABLE dbo.NamedConstraints (
    ID INT IDENTITY(1,1) CONSTRAINT PK_Named PRIMARY KEY,
    Email VARCHAR(200) CONSTRAINT UQ_Email UNIQUE CONSTRAINT NN_Email NOT NULL,
    Age INT CONSTRAINT CK_Age CHECK (Age >= 0),
    Status VARCHAR(20) CONSTRAINT DF_Status DEFAULT 'Active',
    ParentID INT CONSTRAINT FK_Parent REFERENCES dbo.NamedConstraints(ID)
);
DROP TABLE dbo.NamedConstraints;
GO

-- Pattern 5: Table with table-level constraints
CREATE TABLE dbo.TableLevelConstraints (
    OrderID INT NOT NULL,
    ProductID INT NOT NULL,
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(10,2),
    CONSTRAINT PK_OrderProduct PRIMARY KEY (OrderID, ProductID),
    CONSTRAINT FK_Order FOREIGN KEY (OrderID) REFERENCES dbo.Orders(OrderID),
    CONSTRAINT FK_Product FOREIGN KEY (ProductID) REFERENCES dbo.Products(ProductID),
    CONSTRAINT UQ_OrderProduct UNIQUE (OrderID, ProductID, Quantity),
    CONSTRAINT CK_Quantity CHECK (Quantity > 0),
    CONSTRAINT CK_Price CHECK (UnitPrice >= 0)
);
DROP TABLE dbo.TableLevelConstraints;
GO

-- Pattern 6: Table with computed columns
CREATE TABLE dbo.ComputedColumns (
    ID INT IDENTITY(1,1) PRIMARY KEY,
    FirstName VARCHAR(50),
    LastName VARCHAR(50),
    Quantity INT,
    UnitPrice DECIMAL(10,2),
    FullName AS (FirstName + ' ' + LastName),
    LineTotal AS (Quantity * UnitPrice),
    PersistedTotal AS (Quantity * UnitPrice) PERSISTED
);
DROP TABLE dbo.ComputedColumns;
GO

-- Pattern 7: Table with all data types
CREATE TABLE dbo.AllDataTypes (
    -- Exact numerics
    Col_BigInt BIGINT,
    Col_Int INT,
    Col_SmallInt SMALLINT,
    Col_TinyInt TINYINT,
    Col_Bit BIT,
    Col_Decimal DECIMAL(18,4),
    Col_Numeric NUMERIC(10,2),
    Col_Money MONEY,
    Col_SmallMoney SMALLMONEY,
    
    -- Approximate numerics
    Col_Float FLOAT,
    Col_Real REAL,
    
    -- Date and time
    Col_Date DATE,
    Col_Time TIME(7),
    Col_DateTime DATETIME,
    Col_DateTime2 DATETIME2(7),
    Col_SmallDateTime SMALLDATETIME,
    Col_DateTimeOffset DATETIMEOFFSET(7),
    
    -- Character strings
    Col_Char CHAR(10),
    Col_VarChar VARCHAR(100),
    Col_VarCharMax VARCHAR(MAX),
    Col_Text TEXT,
    
    -- Unicode strings
    Col_NChar NCHAR(10),
    Col_NVarChar NVARCHAR(100),
    Col_NVarCharMax NVARCHAR(MAX),
    Col_NText NTEXT,
    
    -- Binary
    Col_Binary BINARY(10),
    Col_VarBinary VARBINARY(100),
    Col_VarBinaryMax VARBINARY(MAX),
    Col_Image IMAGE,
    
    -- Other
    Col_UniqueIdentifier UNIQUEIDENTIFIER,
    Col_XML XML,
    Col_Geography GEOGRAPHY,
    Col_Geometry GEOMETRY,
    Col_HierarchyId HIERARCHYID,
    Col_SqlVariant SQL_VARIANT,
    Col_RowVersion ROWVERSION,
    Col_Timestamp TIMESTAMP
);
DROP TABLE dbo.AllDataTypes;
GO

-- Pattern 8: Table with IDENTITY options
CREATE TABLE dbo.IdentityOptions (
    ID1 INT IDENTITY,                    -- (1,1) default
    ID2 INT IDENTITY(100, 1),            -- Start at 100
    ID3 INT IDENTITY(1, 10),             -- Increment by 10
    ID4 INT IDENTITY(-1, -1),            -- Negative
    Name VARCHAR(100)
);
DROP TABLE dbo.IdentityOptions;
GO

-- Pattern 9: Table with NULL/NOT NULL
CREATE TABLE dbo.NullOptions (
    ID INT NOT NULL,
    Required1 VARCHAR(100) NOT NULL,
    Optional1 VARCHAR(100) NULL,
    Optional2 VARCHAR(100),  -- NULL is default
    RequiredWithDefault INT NOT NULL DEFAULT 0
);
DROP TABLE dbo.NullOptions;
GO

-- Pattern 10: Table with ROWGUIDCOL
CREATE TABLE dbo.RowGuidTable (
    ID INT IDENTITY PRIMARY KEY,
    RowGuid UNIQUEIDENTIFIER ROWGUIDCOL DEFAULT NEWID(),
    SequentialGuid UNIQUEIDENTIFIER DEFAULT NEWSEQUENTIALID(),
    Data VARCHAR(100)
);
DROP TABLE dbo.RowGuidTable;
GO

-- Pattern 11: Table with collation
CREATE TABLE dbo.CollationTable (
    ID INT PRIMARY KEY,
    Name_Default VARCHAR(100),
    Name_Binary VARCHAR(100) COLLATE Latin1_General_BIN,
    Name_CS VARCHAR(100) COLLATE Latin1_General_CS_AS,
    Name_CI VARCHAR(100) COLLATE Latin1_General_CI_AS
);
DROP TABLE dbo.CollationTable;
GO

-- Pattern 12: Table with SPARSE columns
CREATE TABLE dbo.SparseTable (
    ID INT PRIMARY KEY,
    Name VARCHAR(100) NOT NULL,
    Attr1 VARCHAR(100) SPARSE NULL,
    Attr2 INT SPARSE NULL,
    Attr3 DATETIME SPARSE NULL,
    AllSparse XML COLUMN_SET FOR ALL_SPARSE_COLUMNS
);
DROP TABLE dbo.SparseTable;
GO

-- Pattern 13: Table with filegroup
CREATE TABLE dbo.FilegroupTable (
    ID INT PRIMARY KEY,
    Name VARCHAR(100),
    LargeData VARCHAR(MAX)
) ON [PRIMARY]
TEXTIMAGE_ON [PRIMARY];
GO
DROP TABLE dbo.FilegroupTable;
GO

-- Pattern 14: Table with index in CREATE TABLE
CREATE TABLE dbo.InlineIndex (
    ID INT PRIMARY KEY NONCLUSTERED,
    CustomerID INT INDEX IX_Customer NONCLUSTERED,
    OrderDate DATE,
    Amount DECIMAL(10,2),
    INDEX IX_Date_Amount NONCLUSTERED (OrderDate, Amount)
);
DROP TABLE dbo.InlineIndex;
GO

-- Pattern 15: Table with data compression
CREATE TABLE dbo.CompressedTable (
    ID INT PRIMARY KEY,
    Data VARCHAR(1000)
) WITH (DATA_COMPRESSION = PAGE);
GO
DROP TABLE dbo.CompressedTable;
GO

-- Pattern 16: Memory-optimized table
CREATE TABLE dbo.MemoryOptimizedTable (
    ID INT NOT NULL PRIMARY KEY NONCLUSTERED HASH WITH (BUCKET_COUNT = 10000),
    Name VARCHAR(100) NOT NULL,
    Value INT
) WITH (
    MEMORY_OPTIMIZED = ON,
    DURABILITY = SCHEMA_AND_DATA
);
GO
DROP TABLE dbo.MemoryOptimizedTable;
GO

-- Pattern 17: Temporal table
CREATE TABLE dbo.TemporalTable (
    ID INT PRIMARY KEY,
    Name VARCHAR(100),
    Value DECIMAL(10,2),
    ValidFrom DATETIME2 GENERATED ALWAYS AS ROW START NOT NULL,
    ValidTo DATETIME2 GENERATED ALWAYS AS ROW END NOT NULL,
    PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo)
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.TemporalTableHistory));
GO
ALTER TABLE dbo.TemporalTable SET (SYSTEM_VERSIONING = OFF);
DROP TABLE dbo.TemporalTable;
DROP TABLE dbo.TemporalTableHistory;
GO

-- Pattern 18: Table with masked columns
CREATE TABLE dbo.MaskedTable (
    ID INT PRIMARY KEY,
    Email VARCHAR(200) MASKED WITH (FUNCTION = 'email()'),
    SSN VARCHAR(11) MASKED WITH (FUNCTION = 'partial(0,"XXX-XX-",4)'),
    Salary DECIMAL(10,2) MASKED WITH (FUNCTION = 'default()'),
    BirthDate DATE MASKED WITH (FUNCTION = 'default()'),
    RandomValue INT MASKED WITH (FUNCTION = 'random(1, 100)')
);
DROP TABLE dbo.MaskedTable;
GO

-- Pattern 19: Table with encrypted columns
CREATE TABLE dbo.EncryptedTable (
    ID INT PRIMARY KEY,
    SSN VARCHAR(11) ENCRYPTED WITH (
        COLUMN_ENCRYPTION_KEY = CEK_Auto1,
        ENCRYPTION_TYPE = DETERMINISTIC,
        ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
    ),
    Salary INT ENCRYPTED WITH (
        COLUMN_ENCRYPTION_KEY = CEK_Auto1,
        ENCRYPTION_TYPE = RANDOMIZED,
        ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
    )
);
DROP TABLE dbo.EncryptedTable;
GO

-- Pattern 20: Graph table (node)
CREATE TABLE dbo.PersonNode (
    ID INT PRIMARY KEY,
    Name VARCHAR(100)
) AS NODE;
GO
DROP TABLE dbo.PersonNode;
GO

-- Pattern 21: Graph table (edge)
CREATE TABLE dbo.FriendEdge (
    Since DATE
) AS EDGE;
GO
DROP TABLE dbo.FriendEdge;
GO

-- Pattern 22: Partitioned table
CREATE TABLE dbo.PartitionedTable (
    ID INT,
    OrderDate DATE,
    Amount DECIMAL(10,2)
) ON PartitionScheme(OrderDate);
GO

-- Pattern 23: Table with FILETABLE
CREATE TABLE dbo.Documents AS FILETABLE
WITH (
    FILETABLE_DIRECTORY = 'Documents',
    FILETABLE_COLLATE_FILENAME = database_default
);
GO
DROP TABLE dbo.Documents;
GO

-- Pattern 24: CREATE TABLE AS SELECT
SELECT CustomerID, CustomerName, Email
INTO dbo.CustomerBackup
FROM dbo.Customers
WHERE IsActive = 1;
GO
DROP TABLE dbo.CustomerBackup;
GO
