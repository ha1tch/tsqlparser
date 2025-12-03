-- Sample 122: OPENXML and XML Parsing Edge Cases
-- Category: Missing Syntax Elements
-- Complexity: Advanced
-- Purpose: Parser testing - OPENXML syntax and XML processing
-- Features: OPENXML, sp_xml_preparedocument, XML flags, edge cases

-- Pattern 1: Basic OPENXML with element-centric mapping
DECLARE @xml XML = N'
<Customers>
    <Customer>
        <CustomerID>1</CustomerID>
        <Name>John Smith</Name>
        <Email>john@example.com</Email>
    </Customer>
    <Customer>
        <CustomerID>2</CustomerID>
        <Name>Jane Doe</Name>
        <Email>jane@example.com</Email>
    </Customer>
</Customers>';

DECLARE @hdoc INT;
EXEC sp_xml_preparedocument @hdoc OUTPUT, @xml;

SELECT *
FROM OPENXML(@hdoc, '/Customers/Customer', 2)  -- Flag 2 = element-centric
WITH (
    CustomerID INT,
    Name NVARCHAR(100),
    Email NVARCHAR(200)
);

EXEC sp_xml_removedocument @hdoc;
GO

-- Pattern 2: OPENXML with attribute-centric mapping
DECLARE @xml XML = N'
<Orders>
    <Order OrderID="1001" CustomerID="1" OrderDate="2024-01-15" Total="150.00"/>
    <Order OrderID="1002" CustomerID="2" OrderDate="2024-01-16" Total="275.50"/>
</Orders>';

DECLARE @hdoc INT;
EXEC sp_xml_preparedocument @hdoc OUTPUT, @xml;

SELECT *
FROM OPENXML(@hdoc, '/Orders/Order', 1)  -- Flag 1 = attribute-centric
WITH (
    OrderID INT '@OrderID',
    CustomerID INT '@CustomerID',
    OrderDate DATE '@OrderDate',
    Total MONEY '@Total'
);

EXEC sp_xml_removedocument @hdoc;
GO

-- Pattern 3: OPENXML with mixed mapping (flag 3)
DECLARE @xml XML = N'
<Products>
    <Product ProductID="100" Category="Electronics">
        <Name>Laptop</Name>
        <Price>999.99</Price>
    </Product>
</Products>';

DECLARE @hdoc INT;
EXEC sp_xml_preparedocument @hdoc OUTPUT, @xml;

SELECT *
FROM OPENXML(@hdoc, '/Products/Product', 3)  -- Flag 3 = both attribute and element
WITH (
    ProductID INT '@ProductID',
    Category NVARCHAR(50) '@Category',
    Name NVARCHAR(100) 'Name',
    Price DECIMAL(10,2) 'Price'
);

EXEC sp_xml_removedocument @hdoc;
GO

-- Pattern 4: OPENXML with explicit column patterns
DECLARE @xml XML = N'
<Root>
    <Item id="1">
        <Details>
            <SubItem>Value1</SubItem>
        </Details>
    </Item>
</Root>';

DECLARE @hdoc INT;
EXEC sp_xml_preparedocument @hdoc OUTPUT, @xml;

SELECT *
FROM OPENXML(@hdoc, '/Root/Item', 2)
WITH (
    ItemID INT '@id',
    SubItemValue NVARCHAR(50) 'Details/SubItem',
    FullXML NVARCHAR(MAX) '.'  -- Get entire node as text
);

EXEC sp_xml_removedocument @hdoc;
GO

-- Pattern 5: OPENXML with namespace
DECLARE @xml XML = N'
<ns:Root xmlns:ns="http://example.com/schema">
    <ns:Item>
        <ns:Value>Test</ns:Value>
    </ns:Item>
</ns:Root>';

DECLARE @hdoc INT;
EXEC sp_xml_preparedocument @hdoc OUTPUT, @xml, 
    '<root xmlns:ns="http://example.com/schema"/>';

SELECT *
FROM OPENXML(@hdoc, '/ns:Root/ns:Item', 2)
WITH (
    Value NVARCHAR(100) 'ns:Value'
);

EXEC sp_xml_removedocument @hdoc;
GO

-- Pattern 6: OPENXML with edge table (metaproperty columns)
DECLARE @xml XML = N'
<Data>
    <Row><Col1>A</Col1><Col2>B</Col2></Row>
    <Row><Col1>C</Col1><Col2>D</Col2></Row>
</Data>';

DECLARE @hdoc INT;
EXEC sp_xml_preparedocument @hdoc OUTPUT, @xml;

SELECT *
FROM OPENXML(@hdoc, '/Data/Row', 2)
WITH (
    id INT '@mp:id',           -- Metaproperty: node ID
    parentid INT '@mp:parentid', -- Metaproperty: parent node ID
    Col1 NVARCHAR(50),
    Col2 NVARCHAR(50)
);

EXEC sp_xml_removedocument @hdoc;
GO

-- Pattern 7: OPENXML with overflow column
DECLARE @xml XML = N'
<Items>
    <Item ID="1" Name="Test" Extra1="Val1" Extra2="Val2" Extra3="Val3"/>
</Items>';

DECLARE @hdoc INT;
EXEC sp_xml_preparedocument @hdoc OUTPUT, @xml;

SELECT *
FROM OPENXML(@hdoc, '/Items/Item', 1)
WITH (
    ID INT '@ID',
    Name NVARCHAR(50) '@Name',
    Overflow NVARCHAR(MAX) '@mp:xmltext'  -- All unmapped content
);

EXEC sp_xml_removedocument @hdoc;
GO

-- Pattern 8: OPENXML inserting into table
DECLARE @xml XML = N'
<NewCustomers>
    <Customer><Name>Alice</Name><Email>alice@test.com</Email></Customer>
    <Customer><Name>Bob</Name><Email>bob@test.com</Email></Customer>
</NewCustomers>';

DECLARE @hdoc INT;
EXEC sp_xml_preparedocument @hdoc OUTPUT, @xml;

CREATE TABLE #ImportedCustomers (
    Name NVARCHAR(100),
    Email NVARCHAR(200)
);

INSERT INTO #ImportedCustomers (Name, Email)
SELECT Name, Email
FROM OPENXML(@hdoc, '/NewCustomers/Customer', 2)
WITH (
    Name NVARCHAR(100),
    Email NVARCHAR(200)
);

SELECT * FROM #ImportedCustomers;
DROP TABLE #ImportedCustomers;

EXEC sp_xml_removedocument @hdoc;
GO

-- Pattern 9: OPENXML with CDATA sections
DECLARE @xml XML = N'
<Data>
    <Item><![CDATA[<script>alert("test")</script>]]></Item>
    <Item><![CDATA[Special chars: <>&"'']]></Item>
</Data>';

DECLARE @hdoc INT;
EXEC sp_xml_preparedocument @hdoc OUTPUT, @xml;

SELECT *
FROM OPENXML(@hdoc, '/Data/Item', 2)
WITH (
    Content NVARCHAR(MAX) '.'
);

EXEC sp_xml_removedocument @hdoc;
GO

-- Pattern 10: Modern alternative - nodes() method
DECLARE @xml XML = N'
<Employees>
    <Employee ID="1"><Name>John</Name><Dept>IT</Dept></Employee>
    <Employee ID="2"><Name>Jane</Name><Dept>HR</Dept></Employee>
</Employees>';

SELECT 
    emp.value('@ID', 'INT') AS EmployeeID,
    emp.value('(Name)[1]', 'NVARCHAR(100)') AS Name,
    emp.value('(Dept)[1]', 'NVARCHAR(50)') AS Department
FROM @xml.nodes('/Employees/Employee') AS T(emp);
GO

-- Pattern 11: Complex nested OPENXML
DECLARE @xml XML = N'
<Orders>
    <Order OrderID="1">
        <Customer>John</Customer>
        <Items>
            <Item ProductID="100" Qty="2"/>
            <Item ProductID="101" Qty="1"/>
        </Items>
    </Order>
</Orders>';

DECLARE @hdoc INT;
EXEC sp_xml_preparedocument @hdoc OUTPUT, @xml;

-- Get orders
SELECT *
FROM OPENXML(@hdoc, '/Orders/Order', 2)
WITH (
    OrderID INT '@OrderID',
    Customer NVARCHAR(100) 'Customer'
);

-- Get items (nested)
SELECT *
FROM OPENXML(@hdoc, '/Orders/Order/Items/Item', 1)
WITH (
    OrderID INT '../../@OrderID',  -- Navigate up
    ProductID INT '@ProductID',
    Qty INT '@Qty'
);

EXEC sp_xml_removedocument @hdoc;
GO

-- Pattern 12: OPENXML flags comparison
DECLARE @xml XML = N'<Row attr="A"><elem>B</elem></Row>';
DECLARE @hdoc INT;
EXEC sp_xml_preparedocument @hdoc OUTPUT, @xml;

-- Flag 0: Default (attribute-centric)
SELECT 'Flag 0' AS Mode, * FROM OPENXML(@hdoc, '/Row', 0) WITH (attr NVARCHAR(10), elem NVARCHAR(10));

-- Flag 1: Attribute-centric
SELECT 'Flag 1' AS Mode, * FROM OPENXML(@hdoc, '/Row', 1) WITH (attr NVARCHAR(10) '@attr', elem NVARCHAR(10));

-- Flag 2: Element-centric
SELECT 'Flag 2' AS Mode, * FROM OPENXML(@hdoc, '/Row', 2) WITH (attr NVARCHAR(10), elem NVARCHAR(10) 'elem');

-- Flag 3: Both
SELECT 'Flag 3' AS Mode, * FROM OPENXML(@hdoc, '/Row', 3) WITH (attr NVARCHAR(10) '@attr', elem NVARCHAR(10) 'elem');

EXEC sp_xml_removedocument @hdoc;
GO
