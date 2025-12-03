-- Sample 156: XQuery Methods on XML Data Type
-- Category: Missing Syntax Elements / Syntax Coverage
-- Complexity: Advanced
-- Purpose: Parser testing - XQuery method syntax
-- Features: value(), query(), exist(), nodes(), modify()

-- Pattern 1: Basic value() method
DECLARE @xml XML = '<Customer ID="1"><Name>John Smith</Name><Email>john@example.com</Email></Customer>';

SELECT 
    @xml.value('(/Customer/@ID)[1]', 'INT') AS CustomerID,
    @xml.value('(/Customer/Name)[1]', 'NVARCHAR(100)') AS CustomerName,
    @xml.value('(/Customer/Email)[1]', 'NVARCHAR(200)') AS Email;
GO

-- Pattern 2: value() with different XPath expressions
DECLARE @xml XML = '
<Order>
    <Header OrderID="1001" OrderDate="2024-06-15"/>
    <Items>
        <Item ProductID="100" Qty="5" Price="10.00"/>
        <Item ProductID="101" Qty="3" Price="25.00"/>
    </Items>
    <Total>125.00</Total>
</Order>';

SELECT 
    @xml.value('(/Order/Header/@OrderID)[1]', 'INT') AS OrderID,
    @xml.value('(/Order/Header/@OrderDate)[1]', 'DATE') AS OrderDate,
    @xml.value('(/Order/Items/Item/@Qty)[1]', 'INT') AS FirstItemQty,
    @xml.value('sum(/Order/Items/Item/@Qty)', 'INT') AS TotalQty,
    @xml.value('count(/Order/Items/Item)', 'INT') AS ItemCount,
    @xml.value('(/Order/Total)[1]', 'DECIMAL(10,2)') AS Total;
GO

-- Pattern 3: query() method - returns XML
DECLARE @xml XML = '
<Customers>
    <Customer ID="1"><Name>John</Name></Customer>
    <Customer ID="2"><Name>Jane</Name></Customer>
</Customers>';

SELECT 
    @xml.query('/Customers/Customer') AS AllCustomers,
    @xml.query('/Customers/Customer[@ID=1]') AS Customer1,
    @xml.query('/Customers/Customer/Name') AS AllNames;
GO

-- Pattern 4: query() with FLWOR expression
DECLARE @xml XML = '
<Products>
    <Product ID="1" Price="10.00">Widget</Product>
    <Product ID="2" Price="25.00">Gadget</Product>
    <Product ID="3" Price="15.00">Gizmo</Product>
</Products>';

SELECT @xml.query('
    for $p in /Products/Product
    where $p/@Price > 12
    order by $p/@Price descending
    return <HighPriceProduct>{string($p)}</HighPriceProduct>
') AS ExpensiveProducts;
GO

-- Pattern 5: query() with element construction
DECLARE @xml XML = '<Order><Item>Widget</Item><Item>Gadget</Item></Order>';

SELECT @xml.query('
    <ItemList>
    {
        for $item in /Order/Item
        return <Product Name="{string($item)}"/>
    }
    </ItemList>
') AS TransformedXml;
GO

-- Pattern 6: exist() method - returns 1 or 0
DECLARE @xml XML = '<Customer Active="true"><Email>test@example.com</Email></Customer>';

SELECT 
    @xml.exist('/Customer') AS CustomerExists,
    @xml.exist('/Customer/Email') AS EmailExists,
    @xml.exist('/Customer/Phone') AS PhoneExists,
    @xml.exist('/Customer[@Active="true"]') AS IsActive;
GO

-- Pattern 7: exist() in WHERE clause
DECLARE @OrdersXml TABLE (OrderID INT, OrderData XML);
INSERT INTO @OrdersXml VALUES 
    (1, '<Order><Status>Shipped</Status><Priority>High</Priority></Order>'),
    (2, '<Order><Status>Pending</Status></Order>'),
    (3, '<Order><Status>Shipped</Status></Order>');

SELECT OrderID
FROM @OrdersXml
WHERE OrderData.exist('/Order[Status="Shipped"]') = 1;

SELECT OrderID
FROM @OrdersXml
WHERE OrderData.exist('/Order/Priority') = 1;
GO

-- Pattern 8: nodes() method - shreds XML to rows
DECLARE @xml XML = '
<Customers>
    <Customer ID="1"><Name>John</Name><City>New York</City></Customer>
    <Customer ID="2"><Name>Jane</Name><City>Boston</City></Customer>
    <Customer ID="3"><Name>Bob</Name><City>Chicago</City></Customer>
</Customers>';

SELECT 
    Customer.value('@ID', 'INT') AS CustomerID,
    Customer.value('(Name)[1]', 'NVARCHAR(100)') AS Name,
    Customer.value('(City)[1]', 'NVARCHAR(100)') AS City
FROM @xml.nodes('/Customers/Customer') AS T(Customer);
GO

-- Pattern 9: nodes() with column reference
SELECT 
    c.CustomerID,
    Item.value('@ProductID', 'INT') AS ProductID,
    Item.value('@Qty', 'INT') AS Quantity
FROM dbo.Orders c
CROSS APPLY c.OrderXml.nodes('/Order/Items/Item') AS T(Item);
GO

-- Pattern 10: Nested nodes() calls
DECLARE @xml XML = '
<Orders>
    <Order ID="1">
        <Items>
            <Item ProductID="100"/>
            <Item ProductID="101"/>
        </Items>
    </Order>
    <Order ID="2">
        <Items>
            <Item ProductID="102"/>
        </Items>
    </Order>
</Orders>';

SELECT 
    OrderNode.value('@ID', 'INT') AS OrderID,
    ItemNode.value('@ProductID', 'INT') AS ProductID
FROM @xml.nodes('/Orders/Order') AS O(OrderNode)
CROSS APPLY OrderNode.nodes('Items/Item') AS I(ItemNode);
GO

-- Pattern 11: modify() method - insert
DECLARE @xml XML = '<Customer><Name>John</Name></Customer>';

SET @xml.modify('insert <Email>john@example.com</Email> into (/Customer)[1]');
SELECT @xml;

SET @xml.modify('insert <Phone>555-1234</Phone> as last into (/Customer)[1]');
SELECT @xml;

SET @xml.modify('insert <ID>1</ID> as first into (/Customer)[1]');
SELECT @xml;
GO

-- Pattern 12: modify() method - delete
DECLARE @xml XML = '<Customer><Name>John</Name><Email>john@example.com</Email><Phone>555-1234</Phone></Customer>';

SET @xml.modify('delete /Customer/Phone');
SELECT @xml;
GO

-- Pattern 13: modify() method - replace value
DECLARE @xml XML = '<Customer><Name>John</Name><Status>Active</Status></Customer>';

SET @xml.modify('replace value of (/Customer/Name/text())[1] with "Jane"');
SELECT @xml;

SET @xml.modify('replace value of (/Customer/Status/text())[1] with "Inactive"');
SELECT @xml;
GO

-- Pattern 14: modify() with variables (using sql:variable)
DECLARE @xml XML = '<Product><Price>10.00</Price></Product>';
DECLARE @newPrice DECIMAL(10,2) = 15.99;

SET @xml.modify('replace value of (/Product/Price/text())[1] with sql:variable("@newPrice")');
SELECT @xml;
GO

-- Pattern 15: modify() with sql:column
UPDATE dbo.Products
SET ProductXml.modify('
    replace value of (/Product/Price/text())[1] 
    with sql:column("NewPrice")
')
WHERE ProductID = 1;
GO

-- Pattern 16: XQuery predicates
DECLARE @xml XML = '
<Products>
    <Product ID="1" Category="Electronics" Price="100"/>
    <Product ID="2" Category="Clothing" Price="50"/>
    <Product ID="3" Category="Electronics" Price="200"/>
</Products>';

SELECT 
    @xml.query('/Products/Product[@Category="Electronics"]') AS Electronics,
    @xml.query('/Products/Product[@Price > 75]') AS Expensive,
    @xml.query('/Products/Product[position() = 1]') AS FirstProduct,
    @xml.query('/Products/Product[last()]') AS LastProduct;
GO

-- Pattern 17: XQuery functions
DECLARE @xml XML = '<Data><Value>  Hello World  </Value><Number>42</Number></Data>';

SELECT 
    @xml.value('string-length((/Data/Value)[1])', 'INT') AS StringLength,
    @xml.value('normalize-space((/Data/Value)[1])', 'NVARCHAR(100)') AS Normalized,
    @xml.value('concat((/Data/Value)[1], " - ", (/Data/Number)[1])', 'NVARCHAR(100)') AS Concatenated,
    @xml.value('substring((/Data/Value)[1], 3, 5)', 'NVARCHAR(10)') AS Substring,
    @xml.value('contains((/Data/Value)[1], "Hello")', 'BIT') AS ContainsHello;
GO

-- Pattern 18: XQuery with namespaces
DECLARE @xml XML = '
<root xmlns:ns="http://example.com/schema">
    <ns:Customer>
        <ns:Name>John</ns:Name>
    </ns:Customer>
</root>';

SELECT @xml.value('
    declare namespace ns="http://example.com/schema";
    (/root/ns:Customer/ns:Name)[1]
', 'NVARCHAR(100)') AS CustomerName;
GO

-- Pattern 19: Using WITH XMLNAMESPACES
WITH XMLNAMESPACES ('http://example.com/schema' AS ns)
SELECT 
    XmlCol.value('(/root/ns:Customer/ns:Name)[1]', 'NVARCHAR(100)') AS CustomerName
FROM dbo.XmlTable;
GO

-- Pattern 20: Complex XQuery transformation
DECLARE @xml XML = '
<Sales>
    <Sale Date="2024-01-15" Amount="100"/>
    <Sale Date="2024-01-16" Amount="150"/>
    <Sale Date="2024-02-01" Amount="200"/>
</Sales>';

SELECT @xml.query('
    <MonthlySummary>
    {
        for $month in distinct-values(/Sales/Sale/substring(@Date, 1, 7))
        let $monthSales := /Sales/Sale[substring(@Date, 1, 7) = $month]
        return 
            <Month period="{$month}">
                <Total>{sum($monthSales/@Amount)}</Total>
                <Count>{count($monthSales)}</Count>
            </Month>
    }
    </MonthlySummary>
') AS MonthlySummary;
GO
