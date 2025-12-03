-- Sample 167: Index Creation and Management Patterns
-- Category: DDL / Syntax Coverage
-- Complexity: Complex
-- Purpose: Parser testing - index syntax variations
-- Features: CREATE INDEX variations, index types, options

-- Pattern 1: Basic nonclustered index
CREATE NONCLUSTERED INDEX IX_Customers_Name
ON dbo.Customers (CustomerName);
GO

-- Pattern 2: Clustered index
CREATE CLUSTERED INDEX IX_Customers_ID
ON dbo.Customers (CustomerID);
GO

-- Pattern 3: Unique index
CREATE UNIQUE INDEX IX_Customers_Email
ON dbo.Customers (Email);
GO

-- Pattern 4: Unique nonclustered index
CREATE UNIQUE NONCLUSTERED INDEX IX_Products_SKU
ON dbo.Products (SKU);
GO

-- Pattern 5: Composite index (multiple columns)
CREATE INDEX IX_Orders_Customer_Date
ON dbo.Orders (CustomerID, OrderDate);
GO

-- Pattern 6: Index with sort order
CREATE INDEX IX_Orders_Date_Desc
ON dbo.Orders (OrderDate DESC);

CREATE INDEX IX_Products_Category_Price
ON dbo.Products (CategoryID ASC, Price DESC);
GO

-- Pattern 7: Index with included columns
CREATE INDEX IX_Orders_Customer_Incl
ON dbo.Orders (CustomerID)
INCLUDE (OrderDate, TotalAmount, Status);
GO

-- Pattern 8: Filtered index
CREATE INDEX IX_Orders_Active
ON dbo.Orders (OrderDate)
WHERE Status = 'Active';

CREATE INDEX IX_Products_InStock
ON dbo.Products (ProductName)
WHERE StockQuantity > 0 AND IsActive = 1;
GO

-- Pattern 9: Index with FILLFACTOR
CREATE INDEX IX_Customers_Fill90
ON dbo.Customers (CustomerName)
WITH (FILLFACTOR = 90);
GO

-- Pattern 10: Index with PAD_INDEX
CREATE INDEX IX_Orders_Padded
ON dbo.Orders (OrderDate)
WITH (PAD_INDEX = ON, FILLFACTOR = 80);
GO

-- Pattern 11: Index with multiple options
CREATE INDEX IX_Products_FullOptions
ON dbo.Products (CategoryID, ProductName)
WITH (
    FILLFACTOR = 90,
    PAD_INDEX = ON,
    SORT_IN_TEMPDB = ON,
    IGNORE_DUP_KEY = OFF,
    STATISTICS_NORECOMPUTE = OFF,
    DROP_EXISTING = OFF,
    ONLINE = OFF,
    ALLOW_ROW_LOCKS = ON,
    ALLOW_PAGE_LOCKS = ON,
    MAXDOP = 4
);
GO

-- Pattern 12: Index with ONLINE = ON
CREATE INDEX IX_LargeTable_Online
ON dbo.LargeTable (Column1)
WITH (ONLINE = ON);
GO

-- Pattern 13: Index with RESUMABLE
CREATE INDEX IX_Table_Resumable
ON dbo.SomeTable (Column1)
WITH (ONLINE = ON, RESUMABLE = ON, MAX_DURATION = 240);
GO

-- Pattern 14: Index on filegroup
CREATE INDEX IX_Archive_Date
ON dbo.ArchiveData (ArchiveDate)
ON [ArchiveFileGroup];
GO

-- Pattern 15: Index with DATA_COMPRESSION
CREATE INDEX IX_Compressed_Page
ON dbo.LargeTable (Column1)
WITH (DATA_COMPRESSION = PAGE);

CREATE INDEX IX_Compressed_Row
ON dbo.LargeTable (Column2)
WITH (DATA_COMPRESSION = ROW);

CREATE INDEX IX_Compressed_None
ON dbo.LargeTable (Column3)
WITH (DATA_COMPRESSION = NONE);
GO

-- Pattern 16: Partitioned index
CREATE INDEX IX_PartitionedOrders
ON dbo.Orders (OrderDate)
ON PartitionScheme(OrderDate);
GO

-- Pattern 17: Columnstore index (nonclustered)
CREATE NONCLUSTERED COLUMNSTORE INDEX IX_Sales_Columnstore
ON dbo.Sales (ProductID, CustomerID, SaleDate, Amount);
GO

-- Pattern 18: Clustered columnstore index
CREATE CLUSTERED COLUMNSTORE INDEX IX_Archive_CCI
ON dbo.ArchiveTable;
GO

-- Pattern 19: Filtered columnstore index
CREATE NONCLUSTERED COLUMNSTORE INDEX IX_Orders_CCI_Recent
ON dbo.Orders (CustomerID, OrderDate, TotalAmount)
WHERE OrderDate >= '2024-01-01';
GO

-- Pattern 20: Columnstore with compression delay
CREATE CLUSTERED COLUMNSTORE INDEX IX_CCI_Delay
ON dbo.RealtimeData
WITH (COMPRESSION_DELAY = 60);  -- minutes
GO

-- Pattern 21: XML index (primary)
CREATE PRIMARY XML INDEX IX_XML_Primary
ON dbo.XmlDocuments (XmlColumn);
GO

-- Pattern 22: XML index (secondary)
CREATE XML INDEX IX_XML_Path
ON dbo.XmlDocuments (XmlColumn)
USING XML INDEX IX_XML_Primary
FOR PATH;

CREATE XML INDEX IX_XML_Value
ON dbo.XmlDocuments (XmlColumn)
USING XML INDEX IX_XML_Primary
FOR VALUE;

CREATE XML INDEX IX_XML_Property
ON dbo.XmlDocuments (XmlColumn)
USING XML INDEX IX_XML_Primary
FOR PROPERTY;
GO

-- Pattern 23: Spatial index
CREATE SPATIAL INDEX IX_Locations_Geo
ON dbo.Locations (GeoLocation)
USING GEOGRAPHY_AUTO_GRID;

CREATE SPATIAL INDEX IX_Points_Geom
ON dbo.Points (GeomColumn)
USING GEOMETRY_AUTO_GRID
WITH (BOUNDING_BOX = (0, 0, 1000, 1000));
GO

-- Pattern 24: Full-text index
CREATE FULLTEXT INDEX ON dbo.Documents (
    Title LANGUAGE 1033,
    Content LANGUAGE 1033,
    Summary LANGUAGE 1033
)
KEY INDEX IX_Documents_PK
ON FullTextCatalog
WITH (CHANGE_TRACKING = AUTO);
GO

-- Pattern 25: Hash index (memory-optimized)
CREATE TABLE dbo.MemOptTable (
    ID INT NOT NULL PRIMARY KEY NONCLUSTERED HASH WITH (BUCKET_COUNT = 100000),
    Name VARCHAR(100) NOT NULL INDEX IX_Name NONCLUSTERED HASH WITH (BUCKET_COUNT = 50000)
) WITH (MEMORY_OPTIMIZED = ON);
GO

-- Pattern 26: DROP INDEX variations
DROP INDEX IX_Customers_Name ON dbo.Customers;
DROP INDEX IF EXISTS IX_NonExistent ON dbo.Customers;

-- Multiple indexes
DROP INDEX 
    IX_Index1 ON dbo.Table1,
    IX_Index2 ON dbo.Table2;
GO

-- Pattern 27: ALTER INDEX - REBUILD
ALTER INDEX IX_Customers_Name ON dbo.Customers REBUILD;

ALTER INDEX ALL ON dbo.Customers REBUILD;

ALTER INDEX IX_Orders_Date ON dbo.Orders REBUILD
WITH (FILLFACTOR = 90, ONLINE = ON, SORT_IN_TEMPDB = ON);
GO

-- Pattern 28: ALTER INDEX - REORGANIZE
ALTER INDEX IX_Customers_Name ON dbo.Customers REORGANIZE;

ALTER INDEX ALL ON dbo.Customers REORGANIZE;

ALTER INDEX IX_Products_Category ON dbo.Products REORGANIZE
WITH (LOB_COMPACTION = ON);
GO

-- Pattern 29: ALTER INDEX - DISABLE
ALTER INDEX IX_Customers_Name ON dbo.Customers DISABLE;

-- Must rebuild to re-enable
ALTER INDEX IX_Customers_Name ON dbo.Customers REBUILD;
GO

-- Pattern 30: ALTER INDEX - SET options
ALTER INDEX IX_Orders_Date ON dbo.Orders
SET (ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = OFF);

ALTER INDEX IX_Products_Name ON dbo.Products
SET (STATISTICS_NORECOMPUTE = ON);
GO
