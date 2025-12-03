-- Sample 120: Full-Text Search Predicates and Functions
-- Category: Missing Syntax Elements
-- Complexity: Advanced
-- Purpose: Parser testing - full-text search syntax
-- Features: CONTAINS, FREETEXT, CONTAINSTABLE, FREETEXTTABLE, full-text predicates

-- Pattern 1: Simple CONTAINS
SELECT ProductID, ProductName, Description
FROM Products
WHERE CONTAINS(Description, 'chocolate');
GO

-- Pattern 2: CONTAINS with multiple words (AND)
SELECT ProductID, ProductName, Description
FROM Products
WHERE CONTAINS(Description, 'chocolate AND milk');
GO

-- Pattern 3: CONTAINS with OR
SELECT ProductID, ProductName, Description
FROM Products
WHERE CONTAINS(Description, 'chocolate OR vanilla');
GO

-- Pattern 4: CONTAINS with NOT
SELECT ProductID, ProductName, Description
FROM Products
WHERE CONTAINS(Description, 'chocolate AND NOT dark');
GO

-- Pattern 5: CONTAINS with phrase (exact match)
SELECT ProductID, ProductName, Description
FROM Products
WHERE CONTAINS(Description, '"milk chocolate"');
GO

-- Pattern 6: CONTAINS with prefix term
SELECT ProductID, ProductName, Description
FROM Products
WHERE CONTAINS(Description, '"choco*"');
GO

-- Pattern 7: CONTAINS with NEAR
SELECT ProductID, ProductName, Description
FROM Products
WHERE CONTAINS(Description, 'chocolate NEAR milk');
GO

-- Pattern 8: CONTAINS with custom NEAR distance
SELECT ProductID, ProductName, Description
FROM Products
WHERE CONTAINS(Description, 'NEAR((chocolate, milk), 5)');
GO

-- Pattern 9: CONTAINS with NEAR ordered
SELECT ProductID, ProductName, Description
FROM Products
WHERE CONTAINS(Description, 'NEAR((chocolate, milk), 5, TRUE)');
GO

-- Pattern 10: CONTAINS with FORMSOF INFLECTIONAL
SELECT ProductID, ProductName, Description
FROM Products
WHERE CONTAINS(Description, 'FORMSOF(INFLECTIONAL, run)');  -- Matches run, runs, running, ran
GO

-- Pattern 11: CONTAINS with FORMSOF THESAURUS
SELECT ProductID, ProductName, Description
FROM Products
WHERE CONTAINS(Description, 'FORMSOF(THESAURUS, happy)');
GO

-- Pattern 12: CONTAINS with weighted terms
SELECT ProductID, ProductName, Description
FROM Products
WHERE CONTAINS(Description, 'ISABOUT(chocolate WEIGHT(0.9), vanilla WEIGHT(0.5))');
GO

-- Pattern 13: CONTAINS on multiple columns
SELECT ProductID, ProductName, Description
FROM Products
WHERE CONTAINS((ProductName, Description), 'chocolate');
GO

-- Pattern 14: CONTAINS with column specified
SELECT ProductID, ProductName, Description
FROM Products
WHERE CONTAINS(PROPERTY(Description, 'Title'), 'chocolate');
GO

-- Pattern 15: Simple FREETEXT
SELECT ProductID, ProductName, Description
FROM Products
WHERE FREETEXT(Description, 'sweet chocolate dessert');
GO

-- Pattern 16: FREETEXT on multiple columns
SELECT ProductID, ProductName, Description
FROM Products
WHERE FREETEXT((ProductName, Description), 'delicious sweet treats');
GO

-- Pattern 17: FREETEXT with all columns
SELECT ProductID, ProductName, Description
FROM Products
WHERE FREETEXT(*, 'chocolate dessert');
GO

-- Pattern 18: CONTAINSTABLE for ranking
SELECT 
    p.ProductID,
    p.ProductName,
    p.Description,
    ft.[KEY],
    ft.[RANK]
FROM Products p
INNER JOIN CONTAINSTABLE(Products, Description, 'chocolate') AS ft ON p.ProductID = ft.[KEY]
ORDER BY ft.[RANK] DESC;
GO

-- Pattern 19: CONTAINSTABLE with top_n_by_rank
SELECT 
    p.ProductID,
    p.ProductName,
    ft.[RANK]
FROM Products p
INNER JOIN CONTAINSTABLE(Products, Description, 'chocolate', 10) AS ft ON p.ProductID = ft.[KEY]
ORDER BY ft.[RANK] DESC;
GO

-- Pattern 20: CONTAINSTABLE with complex search
SELECT 
    p.ProductID,
    p.ProductName,
    ft.[RANK]
FROM Products p
INNER JOIN CONTAINSTABLE(Products, Description, 
    'ISABOUT(chocolate WEIGHT(0.8), vanilla WEIGHT(0.5), strawberry WEIGHT(0.3))'
) AS ft ON p.ProductID = ft.[KEY]
ORDER BY ft.[RANK] DESC;
GO

-- Pattern 21: FREETEXTTABLE for ranking
SELECT 
    p.ProductID,
    p.ProductName,
    p.Description,
    ft.[KEY],
    ft.[RANK]
FROM Products p
INNER JOIN FREETEXTTABLE(Products, Description, 'sweet chocolate dessert') AS ft ON p.ProductID = ft.[KEY]
ORDER BY ft.[RANK] DESC;
GO

-- Pattern 22: FREETEXTTABLE with multiple columns
SELECT 
    p.ProductID,
    p.ProductName,
    ft.[RANK]
FROM Products p
INNER JOIN FREETEXTTABLE(Products, (ProductName, Description), 'delicious treats', 20) AS ft ON p.ProductID = ft.[KEY]
ORDER BY ft.[RANK] DESC;
GO

-- Pattern 23: Combining CONTAINS with other predicates
SELECT ProductID, ProductName, Description, Price
FROM Products
WHERE CONTAINS(Description, 'chocolate')
  AND Price < 10.00
  AND CategoryID = 5
  AND IsActive = 1
ORDER BY Price;
GO

-- Pattern 24: Full-text with JOIN
SELECT 
    p.ProductID,
    p.ProductName,
    c.CategoryName,
    p.Description
FROM Products p
INNER JOIN Categories c ON p.CategoryID = c.CategoryID
WHERE CONTAINS(p.Description, 'chocolate OR vanilla')
  AND c.CategoryName = 'Confectionery';
GO

-- Pattern 25: Subquery with full-text
SELECT *
FROM Orders
WHERE ProductID IN (
    SELECT ProductID
    FROM Products
    WHERE CONTAINS(Description, 'premium AND organic')
);
GO

-- Pattern 26: Full-text in CTE
;WITH ChocolateProducts AS (
    SELECT ProductID, ProductName, Description
    FROM Products
    WHERE CONTAINS(Description, 'chocolate')
)
SELECT 
    cp.ProductID,
    cp.ProductName,
    COUNT(o.OrderID) AS OrderCount
FROM ChocolateProducts cp
LEFT JOIN OrderDetails od ON cp.ProductID = od.ProductID
LEFT JOIN Orders o ON od.OrderID = o.OrderID
GROUP BY cp.ProductID, cp.ProductName;
GO

-- Pattern 27: Full-text catalog functions
SELECT 
    FULLTEXTCATALOGPROPERTY('ProductCatalog', 'ItemCount') AS ItemCount,
    FULLTEXTCATALOGPROPERTY('ProductCatalog', 'IndexSize') AS IndexSizeMB,
    FULLTEXTCATALOGPROPERTY('ProductCatalog', 'PopulateStatus') AS PopulateStatus;
GO

-- Pattern 28: Full-text index information
SELECT 
    OBJECTPROPERTY(OBJECT_ID('Products'), 'TableFullTextCatalogId') AS CatalogID,
    OBJECTPROPERTY(OBJECT_ID('Products'), 'TableHasActiveFulltextIndex') AS HasActiveIndex;
GO

-- Pattern 29: Semantic search (SQL Server 2012+)
-- SELECT *
-- FROM SEMANTICKEYPHRASETABLE(Products, Description) AS skt
-- ORDER BY skt.score DESC;

-- SELECT *
-- FROM SEMANTICSIMILARITYTABLE(Products, Description, @ProductID) AS sst
-- ORDER BY sst.score DESC;
GO

-- Pattern 30: Full-text with LANGUAGE
SELECT ProductID, ProductName, Description
FROM Products
WHERE CONTAINS(Description, 'chocolate', LANGUAGE 1033);  -- English
GO

SELECT ProductID, ProductName, Description
FROM Products
WHERE FREETEXT(Description, 'délicieux chocolat', LANGUAGE 'French');
GO
