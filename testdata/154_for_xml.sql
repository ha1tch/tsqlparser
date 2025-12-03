-- Sample 154: FOR XML PATH and XML Generation Patterns
-- Category: Missing Syntax Elements / Syntax Coverage
-- Complexity: Complex
-- Purpose: Parser testing - XML generation syntax
-- Features: FOR XML modes, PATH, TYPE, ROOT, nested XML

-- Pattern 1: Basic FOR XML AUTO
SELECT CustomerID, CustomerName, Email
FROM dbo.Customers
FOR XML AUTO;
GO

-- Pattern 2: FOR XML AUTO with nested tables
SELECT c.CustomerID, c.CustomerName, o.OrderID, o.OrderDate
FROM dbo.Customers c
INNER JOIN dbo.Orders o ON c.CustomerID = o.CustomerID
FOR XML AUTO;
GO

-- Pattern 3: FOR XML RAW
SELECT CustomerID, CustomerName, Email
FROM dbo.Customers
FOR XML RAW;
GO

-- Pattern 4: FOR XML RAW with element name
SELECT CustomerID, CustomerName, Email
FROM dbo.Customers
FOR XML RAW('Customer');
GO

-- Pattern 5: FOR XML PATH basic
SELECT CustomerID, CustomerName, Email
FROM dbo.Customers
FOR XML PATH;
GO

-- Pattern 6: FOR XML PATH with row element name
SELECT CustomerID, CustomerName, Email
FROM dbo.Customers
FOR XML PATH('Customer');
GO

-- Pattern 7: FOR XML PATH with ROOT
SELECT CustomerID, CustomerName, Email
FROM dbo.Customers
FOR XML PATH('Customer'), ROOT('Customers');
GO

-- Pattern 8: FOR XML PATH with attributes (@ prefix)
SELECT 
    CustomerID AS '@ID',
    CustomerName AS '@Name',
    Email
FROM dbo.Customers
FOR XML PATH('Customer');
GO

-- Pattern 9: FOR XML PATH with nested elements (/ separator)
SELECT 
    CustomerID AS '@ID',
    CustomerName AS 'Info/Name',
    Email AS 'Contact/Email',
    Phone AS 'Contact/Phone'
FROM dbo.Customers
FOR XML PATH('Customer');
GO

-- Pattern 10: FOR XML PATH with ELEMENTS directive
SELECT CustomerID, CustomerName, Email
FROM dbo.Customers
FOR XML RAW('Customer'), ELEMENTS;
GO

-- Pattern 11: FOR XML PATH with ELEMENTS XSINIL (include NULLs)
SELECT CustomerID, CustomerName, Email, Phone
FROM dbo.Customers
FOR XML PATH('Customer'), ELEMENTS XSINIL;
GO

-- Pattern 12: FOR XML PATH with TYPE (returns XML type)
SELECT 
    (SELECT CustomerID, CustomerName 
     FROM dbo.Customers 
     FOR XML PATH('Customer'), TYPE) AS CustomerXml;
GO

-- Pattern 13: Nested FOR XML with TYPE
SELECT 
    c.CustomerID AS '@ID',
    c.CustomerName AS 'Name',
    (
        SELECT o.OrderID AS '@ID', o.OrderDate, o.TotalAmount
        FROM dbo.Orders o
        WHERE o.CustomerID = c.CustomerID
        FOR XML PATH('Order'), TYPE
    ) AS 'Orders'
FROM dbo.Customers c
FOR XML PATH('Customer'), ROOT('Customers');
GO

-- Pattern 14: Multiple nesting levels
SELECT 
    c.CategoryID AS '@ID',
    c.CategoryName AS 'Name',
    (
        SELECT 
            p.ProductID AS '@ID',
            p.ProductName AS 'Name',
            p.Price AS 'Price',
            (
                SELECT s.SupplierName AS 'Name'
                FROM dbo.Suppliers s
                WHERE s.SupplierID = p.SupplierID
                FOR XML PATH('Supplier'), TYPE
            )
        FROM dbo.Products p
        WHERE p.CategoryID = c.CategoryID
        FOR XML PATH('Product'), TYPE
    ) AS 'Products'
FROM dbo.Categories c
FOR XML PATH('Category'), ROOT('Catalog');
GO

-- Pattern 15: FOR XML EXPLICIT
SELECT 
    1 AS Tag,
    NULL AS Parent,
    CustomerID AS [Customer!1!ID],
    CustomerName AS [Customer!1!Name!ELEMENT]
FROM dbo.Customers
FOR XML EXPLICIT;
GO

-- Pattern 16: String concatenation with FOR XML PATH (common pattern)
SELECT 
    CustomerID,
    STUFF(
        (SELECT ', ' + ProductName
         FROM dbo.Orders o
         INNER JOIN dbo.OrderDetails od ON o.OrderID = od.OrderID
         INNER JOIN dbo.Products p ON od.ProductID = p.ProductID
         WHERE o.CustomerID = c.CustomerID
         FOR XML PATH('')), 
        1, 2, ''
    ) AS ProductList
FROM dbo.Customers c;
GO

-- Pattern 17: FOR XML PATH with empty element name (no wrapper)
SELECT 
    CustomerID,
    (SELECT ProductName + ', '
     FROM dbo.Products
     WHERE CategoryID = 1
     FOR XML PATH('')) AS ProductNames
FROM dbo.Customers;
GO

-- Pattern 18: FOR XML with namespace
WITH XMLNAMESPACES (
    'http://schemas.example.com/customer' AS ns
)
SELECT 
    CustomerID AS 'ns:ID',
    CustomerName AS 'ns:Name'
FROM dbo.Customers
FOR XML PATH('ns:Customer'), ROOT('ns:Customers');
GO

-- Pattern 19: FOR XML with default namespace
WITH XMLNAMESPACES (
    DEFAULT 'http://schemas.example.com/customer'
)
SELECT CustomerID, CustomerName
FROM dbo.Customers
FOR XML PATH('Customer'), ROOT('Customers');
GO

-- Pattern 20: FOR XML with BINARY BASE64
SELECT 
    DocumentID,
    DocumentName,
    FileContent  -- VARBINARY column
FROM dbo.Documents
FOR XML PATH('Document'), BINARY BASE64;
GO

-- Pattern 21: Complex business document generation
SELECT 
    o.OrderID AS 'Header/OrderNumber',
    o.OrderDate AS 'Header/OrderDate',
    c.CustomerName AS 'Header/Customer/Name',
    c.Email AS 'Header/Customer/Email',
    (
        SELECT 
            ROW_NUMBER() OVER (ORDER BY od.LineNumber) AS '@LineNum',
            p.ProductName AS 'Product',
            od.Quantity AS 'Quantity',
            od.UnitPrice AS 'UnitPrice',
            od.Quantity * od.UnitPrice AS 'LineTotal'
        FROM dbo.OrderDetails od
        INNER JOIN dbo.Products p ON od.ProductID = p.ProductID
        WHERE od.OrderID = o.OrderID
        FOR XML PATH('Line'), TYPE
    ) AS 'Lines',
    o.TotalAmount AS 'Summary/Total',
    o.TaxAmount AS 'Summary/Tax',
    o.TotalAmount + o.TaxAmount AS 'Summary/GrandTotal'
FROM dbo.Orders o
INNER JOIN dbo.Customers c ON o.CustomerID = c.CustomerID
WHERE o.OrderID = 1001
FOR XML PATH('Order'), ROOT('OrderDocument');
GO

-- Pattern 22: FOR XML with CDATA (requires string manipulation)
SELECT 
    ProductID,
    '<![CDATA[' + Description + ']]>' AS Description
FROM dbo.Products
FOR XML PATH('Product'), TYPE;
GO

-- Pattern 23: Combining FOR XML results
SELECT 
    (SELECT CustomerID, CustomerName FROM dbo.Customers FOR XML PATH('Customer'), TYPE) AS Customers,
    (SELECT ProductID, ProductName FROM dbo.Products FOR XML PATH('Product'), TYPE) AS Products
FOR XML PATH('Data'), ROOT('Export');
GO

-- Pattern 24: FOR XML with computed expressions
SELECT 
    CustomerID AS '@ID',
    UPPER(CustomerName) AS 'Name',
    YEAR(CreatedDate) AS 'YearJoined',
    CASE IsActive WHEN 1 THEN 'Active' ELSE 'Inactive' END AS 'Status'
FROM dbo.Customers
FOR XML PATH('Customer');
GO
