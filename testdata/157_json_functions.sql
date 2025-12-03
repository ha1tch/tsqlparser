-- Sample 157: JSON Functions
-- Category: Missing Syntax Elements / Syntax Coverage
-- Complexity: Complex
-- Purpose: Parser testing - JSON function syntax
-- Features: JSON_VALUE, JSON_QUERY, JSON_MODIFY, OPENJSON, ISJSON

-- Pattern 1: ISJSON validation
SELECT 
    ISJSON('{"name":"John"}') AS ValidJson,
    ISJSON('not json') AS InvalidJson,
    ISJSON(NULL) AS NullJson,
    ISJSON('[]') AS EmptyArray,
    ISJSON('{}') AS EmptyObject;
GO

-- Pattern 2: JSON_VALUE - extract scalar values
DECLARE @json NVARCHAR(MAX) = N'{"id":1,"name":"John Smith","email":"john@example.com","age":30}';

SELECT 
    JSON_VALUE(@json, '$.id') AS ID,
    JSON_VALUE(@json, '$.name') AS Name,
    JSON_VALUE(@json, '$.email') AS Email,
    JSON_VALUE(@json, '$.age') AS Age,
    JSON_VALUE(@json, '$.phone') AS Phone;  -- Returns NULL if not exists
GO

-- Pattern 3: JSON_VALUE with nested paths
DECLARE @json NVARCHAR(MAX) = N'{
    "customer": {
        "name": "John",
        "address": {
            "street": "123 Main St",
            "city": "New York",
            "zip": "10001"
        }
    }
}';

SELECT 
    JSON_VALUE(@json, '$.customer.name') AS CustomerName,
    JSON_VALUE(@json, '$.customer.address.city') AS City,
    JSON_VALUE(@json, '$.customer.address.zip') AS ZipCode;
GO

-- Pattern 4: JSON_VALUE with array index
DECLARE @json NVARCHAR(MAX) = N'{"items":["apple","banana","cherry"]}';

SELECT 
    JSON_VALUE(@json, '$.items[0]') AS FirstItem,
    JSON_VALUE(@json, '$.items[1]') AS SecondItem,
    JSON_VALUE(@json, '$.items[2]') AS ThirdItem;
GO

-- Pattern 5: JSON_QUERY - extract objects and arrays
DECLARE @json NVARCHAR(MAX) = N'{
    "id": 1,
    "name": "John",
    "orders": [
        {"orderId": 101, "amount": 100},
        {"orderId": 102, "amount": 200}
    ],
    "address": {"city": "NYC", "zip": "10001"}
}';

SELECT 
    JSON_QUERY(@json, '$.orders') AS Orders,
    JSON_QUERY(@json, '$.address') AS Address,
    JSON_QUERY(@json, '$.orders[0]') AS FirstOrder;
GO

-- Pattern 6: JSON_VALUE vs JSON_QUERY
DECLARE @json NVARCHAR(MAX) = N'{"value":"scalar","object":{"nested":"data"},"array":[1,2,3]}';

SELECT 
    JSON_VALUE(@json, '$.value') AS ScalarWithValue,     -- Returns 'scalar'
    JSON_QUERY(@json, '$.value') AS ScalarWithQuery,     -- Returns NULL
    JSON_VALUE(@json, '$.object') AS ObjectWithValue,    -- Returns NULL
    JSON_QUERY(@json, '$.object') AS ObjectWithQuery,    -- Returns '{"nested":"data"}'
    JSON_VALUE(@json, '$.array') AS ArrayWithValue,      -- Returns NULL
    JSON_QUERY(@json, '$.array') AS ArrayWithQuery;      -- Returns '[1,2,3]'
GO

-- Pattern 7: JSON_MODIFY - update values
DECLARE @json NVARCHAR(MAX) = N'{"name":"John","age":30}';

SELECT JSON_MODIFY(@json, '$.name', 'Jane') AS UpdatedName;
SELECT JSON_MODIFY(@json, '$.age', 31) AS UpdatedAge;
SELECT JSON_MODIFY(@json, '$.email', 'john@example.com') AS AddedEmail;
GO

-- Pattern 8: JSON_MODIFY - nested updates
DECLARE @json NVARCHAR(MAX) = N'{"customer":{"name":"John","city":"Boston"}}';

SELECT JSON_MODIFY(@json, '$.customer.city', 'New York') AS UpdatedCity;
SELECT JSON_MODIFY(@json, '$.customer.phone', '555-1234') AS AddedPhone;
GO

-- Pattern 9: JSON_MODIFY - delete (set to NULL)
DECLARE @json NVARCHAR(MAX) = N'{"name":"John","temp":"to delete","keep":"this"}';

SELECT JSON_MODIFY(@json, '$.temp', NULL) AS Deleted;
GO

-- Pattern 10: JSON_MODIFY - append to array
DECLARE @json NVARCHAR(MAX) = N'{"items":["a","b"]}';

SELECT JSON_MODIFY(@json, 'append $.items', 'c') AS Appended;
SELECT JSON_MODIFY(@json, 'append $.items', JSON_QUERY('["d","e"]')) AS AppendedMultiple;
GO

-- Pattern 11: JSON_MODIFY - strict mode
DECLARE @json NVARCHAR(MAX) = N'{"name":"John"}';

-- lax mode (default) - creates path if not exists
SELECT JSON_MODIFY(@json, 'lax $.email', 'john@example.com') AS LaxMode;

-- strict mode - fails if path doesn't exist
SELECT JSON_MODIFY(@json, 'strict $.name', 'Jane') AS StrictExisting;
-- SELECT JSON_MODIFY(@json, 'strict $.email', 'john@example.com') AS StrictNew; -- Would error
GO

-- Pattern 12: OPENJSON - basic usage
DECLARE @json NVARCHAR(MAX) = N'[
    {"id":1,"name":"John","age":30},
    {"id":2,"name":"Jane","age":25},
    {"id":3,"name":"Bob","age":35}
]';

SELECT * FROM OPENJSON(@json);
GO

-- Pattern 13: OPENJSON with explicit schema
DECLARE @json NVARCHAR(MAX) = N'[
    {"id":1,"name":"John","age":30},
    {"id":2,"name":"Jane","age":25}
]';

SELECT * FROM OPENJSON(@json)
WITH (
    ID INT '$.id',
    Name NVARCHAR(100) '$.name',
    Age INT '$.age'
);
GO

-- Pattern 14: OPENJSON with nested JSON
DECLARE @json NVARCHAR(MAX) = N'{
    "customer": {"id":1,"name":"John"},
    "orders": [
        {"orderId":101,"amount":100},
        {"orderId":102,"amount":200}
    ]
}';

SELECT * FROM OPENJSON(@json, '$.orders')
WITH (
    OrderID INT '$.orderId',
    Amount DECIMAL(10,2) '$.amount'
);
GO

-- Pattern 15: OPENJSON preserving JSON
SELECT * FROM OPENJSON(N'{"id":1,"data":{"nested":"value"},"items":[1,2,3]}')
WITH (
    ID INT '$.id',
    Data NVARCHAR(MAX) '$.data' AS JSON,
    Items NVARCHAR(MAX) '$.items' AS JSON
);
GO

-- Pattern 16: OPENJSON with path
DECLARE @json NVARCHAR(MAX) = N'{"response":{"data":{"users":[{"name":"John"},{"name":"Jane"}]}}}';

SELECT * FROM OPENJSON(@json, '$.response.data.users')
WITH (Name NVARCHAR(100) '$.name');
GO

-- Pattern 17: JSON in WHERE clause
DECLARE @Products TABLE (ProductID INT, ProductData NVARCHAR(MAX));
INSERT INTO @Products VALUES 
    (1, '{"name":"Widget","price":10,"category":"Electronics"}'),
    (2, '{"name":"Gadget","price":25,"category":"Electronics"}'),
    (3, '{"name":"Shirt","price":30,"category":"Clothing"}');

SELECT ProductID, JSON_VALUE(ProductData, '$.name') AS Name
FROM @Products
WHERE JSON_VALUE(ProductData, '$.category') = 'Electronics';
GO

-- Pattern 18: JSON with computed column
CREATE TABLE #JsonProducts (
    ProductID INT IDENTITY PRIMARY KEY,
    ProductData NVARCHAR(MAX),
    ProductName AS JSON_VALUE(ProductData, '$.name'),
    Price AS CAST(JSON_VALUE(ProductData, '$.price') AS DECIMAL(10,2))
);

INSERT INTO #JsonProducts (ProductData) VALUES ('{"name":"Widget","price":10.99}');
SELECT * FROM #JsonProducts;
DROP TABLE #JsonProducts;
GO

-- Pattern 19: JSON with index
CREATE TABLE #IndexedJson (
    ID INT IDENTITY PRIMARY KEY,
    JsonData NVARCHAR(MAX),
    CustomerName AS JSON_VALUE(JsonData, '$.name') PERSISTED
);

CREATE INDEX IX_CustomerName ON #IndexedJson(CustomerName);

INSERT INTO #IndexedJson (JsonData) VALUES ('{"name":"John","city":"NYC"}');
SELECT * FROM #IndexedJson WHERE CustomerName = 'John';
DROP TABLE #IndexedJson;
GO

-- Pattern 20: Combining JSON functions
DECLARE @json NVARCHAR(MAX) = N'{"id":1,"items":[{"name":"A"},{"name":"B"}]}';

-- Add new item and update id
SET @json = JSON_MODIFY(@json, '$.id', 2);
SET @json = JSON_MODIFY(@json, 'append $.items', JSON_QUERY('{"name":"C"}'));

SELECT @json AS ModifiedJson;
SELECT * FROM OPENJSON(@json, '$.items') WITH (Name NVARCHAR(50) '$.name');
GO

-- Pattern 21: JSON_PATH_EXISTS (SQL Server 2022+)
DECLARE @json NVARCHAR(MAX) = N'{"customer":{"name":"John","address":{"city":"NYC"}}}';

SELECT 
    JSON_PATH_EXISTS(@json, '$.customer') AS CustomerExists,
    JSON_PATH_EXISTS(@json, '$.customer.name') AS NameExists,
    JSON_PATH_EXISTS(@json, '$.customer.phone') AS PhoneExists,
    JSON_PATH_EXISTS(@json, '$.customer.address.city') AS CityExists;
GO

-- Pattern 22: JSON_OBJECT and JSON_ARRAY (SQL Server 2022+)
SELECT 
    JSON_OBJECT('id':1, 'name':'John', 'active':CAST(1 AS BIT)) AS JsonObj,
    JSON_ARRAY(1, 2, 3, 'four', NULL) AS JsonArr,
    JSON_ARRAY() AS EmptyArr;
GO

-- Pattern 23: Building JSON dynamically
SELECT 
    JSON_OBJECT(
        'customerId': CustomerID,
        'name': CustomerName,
        'email': Email,
        'orders': (
            SELECT JSON_ARRAY(OrderID, OrderDate, TotalAmount)
            FROM dbo.Orders o
            WHERE o.CustomerID = c.CustomerID
            FOR JSON PATH
        )
    ) AS CustomerJson
FROM dbo.Customers c;
GO
