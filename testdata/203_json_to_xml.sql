-- Convert JSON data to XML format
CREATE PROCEDURE dbo.ConvertJsonToXml
    @JsonData NVARCHAR(MAX),
    @XmlResult XML OUTPUT
AS
BEGIN
    -- Shred JSON into temp table
    CREATE TABLE #Data (
        ItemId INT,
        ItemName NVARCHAR(100),
        Quantity INT,
        Price DECIMAL(10,2)
    )
    
    INSERT INTO #Data (ItemId, ItemName, Quantity, Price)
    SELECT 
        ItemId,
        ItemName,
        Quantity,
        Price
    FROM OPENJSON(@JsonData, '$.items')
    WITH (
        ItemId INT '$.id',
        ItemName NVARCHAR(100) '$.name',
        Quantity INT '$.quantity',
        Price DECIMAL(10,2) '$.price'
    )
    
    -- Convert to XML
    SET @XmlResult = (
        SELECT 
            ItemId AS '@id',
            ItemName AS 'name',
            Quantity AS 'qty',
            Price AS 'price',
            Quantity * Price AS 'total'
        FROM #Data
        ORDER BY ItemId
        FOR XML PATH('item'), ROOT('items'), ELEMENTS
    )
    
    DROP TABLE #Data
END
