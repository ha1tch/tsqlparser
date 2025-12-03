-- Sample 187: Table Types and Type Definitions
-- Category: DDL / Syntax Coverage
-- Complexity: Complex
-- Purpose: Parser testing - user-defined type syntax
-- Features: CREATE TYPE, table types, alias types

-- Pattern 1: Basic alias type
CREATE TYPE dbo.PhoneNumber FROM VARCHAR(20) NOT NULL;
GO
DROP TYPE dbo.PhoneNumber;
GO

-- Pattern 2: Alias type with NULL
CREATE TYPE dbo.OptionalPhone FROM VARCHAR(20) NULL;
GO
DROP TYPE dbo.OptionalPhone;
GO

-- Pattern 3: Numeric alias types
CREATE TYPE dbo.MoneyAmount FROM DECIMAL(18,2) NOT NULL;
CREATE TYPE dbo.Percentage FROM DECIMAL(5,2) NOT NULL;
CREATE TYPE dbo.Quantity FROM INT NOT NULL;
GO
DROP TYPE dbo.MoneyAmount;
DROP TYPE dbo.Percentage;
DROP TYPE dbo.Quantity;
GO

-- Pattern 4: Basic table type
CREATE TYPE dbo.CustomerTableType AS TABLE (
    CustomerID INT,
    CustomerName VARCHAR(100),
    Email VARCHAR(200)
);
GO
DROP TYPE dbo.CustomerTableType;
GO

-- Pattern 5: Table type with primary key
CREATE TYPE dbo.OrderLineType AS TABLE (
    LineNumber INT PRIMARY KEY,
    ProductID INT NOT NULL,
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(10,2) NOT NULL
);
GO
DROP TYPE dbo.OrderLineType;
GO

-- Pattern 6: Table type with multiple constraints
CREATE TYPE dbo.ProductImportType AS TABLE (
    RowID INT IDENTITY(1,1) PRIMARY KEY,
    SKU VARCHAR(50) NOT NULL UNIQUE,
    ProductName VARCHAR(200) NOT NULL,
    Price DECIMAL(10,2) CHECK (Price >= 0),
    Quantity INT DEFAULT 0
);
GO
DROP TYPE dbo.ProductImportType;
GO

-- Pattern 7: Table type with composite primary key
CREATE TYPE dbo.InventoryUpdateType AS TABLE (
    WarehouseID INT NOT NULL,
    ProductID INT NOT NULL,
    Quantity INT NOT NULL,
    PRIMARY KEY (WarehouseID, ProductID)
);
GO
DROP TYPE dbo.InventoryUpdateType;
GO

-- Pattern 8: Table type with index
CREATE TYPE dbo.IndexedTableType AS TABLE (
    ID INT PRIMARY KEY NONCLUSTERED,
    CategoryID INT,
    Value DECIMAL(10,2),
    INDEX IX_Category CLUSTERED (CategoryID)
);
GO
DROP TYPE dbo.IndexedTableType;
GO

-- Pattern 9: Table type with multiple indexes
CREATE TYPE dbo.MultiIndexType AS TABLE (
    ID INT,
    Col1 VARCHAR(50),
    Col2 INT,
    Col3 DATE,
    PRIMARY KEY CLUSTERED (ID),
    INDEX IX_Col1 NONCLUSTERED (Col1),
    INDEX IX_Col2_Col3 NONCLUSTERED (Col2, Col3)
);
GO
DROP TYPE dbo.MultiIndexType;
GO

-- Pattern 10: Using table type in procedure
CREATE TYPE dbo.CustomerInputType AS TABLE (
    CustomerName VARCHAR(100),
    Email VARCHAR(200),
    Phone VARCHAR(20)
);
GO

CREATE PROCEDURE dbo.BulkInsertCustomers
    @Customers dbo.CustomerInputType READONLY
AS
BEGIN
    INSERT INTO dbo.Customers (CustomerName, Email, Phone)
    SELECT CustomerName, Email, Phone
    FROM @Customers;
END;
GO

DROP PROCEDURE dbo.BulkInsertCustomers;
DROP TYPE dbo.CustomerInputType;
GO

-- Pattern 11: Table type in function
CREATE TYPE dbo.IDListType AS TABLE (ID INT PRIMARY KEY);
GO

CREATE FUNCTION dbo.GetCustomersByIDs
(
    @IDs dbo.IDListType READONLY
)
RETURNS TABLE
AS
RETURN (
    SELECT c.*
    FROM dbo.Customers c
    INNER JOIN @IDs ids ON c.CustomerID = ids.ID
);
GO

DROP FUNCTION dbo.GetCustomersByIDs;
DROP TYPE dbo.IDListType;
GO

-- Pattern 12: Calling procedure with table type
DECLARE @NewCustomers dbo.CustomerInputType;

INSERT INTO @NewCustomers (CustomerName, Email, Phone)
VALUES 
    ('John Smith', 'john@example.com', '555-1111'),
    ('Jane Doe', 'jane@example.com', '555-2222');

EXEC dbo.BulkInsertCustomers @Customers = @NewCustomers;
GO

-- Pattern 13: CLR type reference (requires CLR assembly)
-- CREATE TYPE dbo.ComplexNumber EXTERNAL NAME MyAssembly.[Namespace.ComplexNumber];
GO

-- Pattern 14: XML schema collection type
CREATE XML SCHEMA COLLECTION dbo.CustomerSchema AS
N'<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
    <xs:element name="Customer">
        <xs:complexType>
            <xs:sequence>
                <xs:element name="Name" type="xs:string"/>
                <xs:element name="Email" type="xs:string"/>
            </xs:sequence>
            <xs:attribute name="ID" type="xs:int"/>
        </xs:complexType>
    </xs:element>
</xs:schema>';
GO

DROP XML SCHEMA COLLECTION dbo.CustomerSchema;
GO

-- Pattern 15: Table type with all data types
CREATE TYPE dbo.AllTypesTableType AS TABLE (
    Col_Int INT,
    Col_BigInt BIGINT,
    Col_Decimal DECIMAL(18,4),
    Col_Float FLOAT,
    Col_Date DATE,
    Col_DateTime2 DATETIME2(7),
    Col_VarChar VARCHAR(100),
    Col_NVarChar NVARCHAR(100),
    Col_VarBinary VARBINARY(100),
    Col_UniqueID UNIQUEIDENTIFIER DEFAULT NEWID(),
    Col_Bit BIT DEFAULT 0
);
GO
DROP TYPE dbo.AllTypesTableType;
GO

-- Pattern 16: Querying type metadata
SELECT 
    t.name AS TypeName,
    s.name AS SchemaName,
    t.is_table_type,
    t.is_user_defined,
    TYPE_NAME(t.system_type_id) AS BaseType,
    t.max_length,
    t.precision,
    t.scale,
    t.is_nullable
FROM sys.types t
INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
WHERE t.is_user_defined = 1;
GO

-- Pattern 17: Table type columns metadata
SELECT 
    tt.name AS TableTypeName,
    c.name AS ColumnName,
    TYPE_NAME(c.user_type_id) AS DataType,
    c.max_length,
    c.is_nullable,
    c.is_identity
FROM sys.table_types tt
INNER JOIN sys.columns c ON tt.type_table_object_id = c.object_id
ORDER BY tt.name, c.column_id;
GO

-- Pattern 18: ALTER TYPE (not supported - must drop and recreate)
-- Types cannot be altered if they are in use
-- Must drop dependent objects, drop type, recreate type, recreate objects
GO

-- Pattern 19: Memory-optimized table type
CREATE TYPE dbo.MemOptTableType AS TABLE (
    ID INT NOT NULL PRIMARY KEY NONCLUSTERED HASH WITH (BUCKET_COUNT = 1024),
    Value VARCHAR(100) NOT NULL
) WITH (MEMORY_OPTIMIZED = ON);
GO
DROP TYPE dbo.MemOptTableType;
GO
