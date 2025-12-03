-- Sample 010: XML and JSON Processing Patterns
-- Source: Various - SharePointPals, SQLShack, Stack Overflow
-- Category: XML/JSON Processing
-- Complexity: Advanced
-- Features: FOR XML PATH, FOR JSON, OPENJSON, XML.nodes(), XPath

-- Parse XML input and insert into table
CREATE PROCEDURE dbo.ParseXMLAndInsert
    @InputXML XML
AS
BEGIN
    SET NOCOUNT ON;
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        INSERT INTO dbo.Students (
            StudentID,
            FirstName,
            LastName,
            Email,
            EnrollmentDate
        )
        SELECT
            x.value('@StudentID', 'INT') AS StudentID,
            x.value('FirstName[1]', 'NVARCHAR(100)') AS FirstName,
            x.value('LastName[1]', 'NVARCHAR(100)') AS LastName,
            x.value('Email[1]', 'NVARCHAR(200)') AS Email,
            x.value('EnrollmentDate[1]', 'DATE') AS EnrollmentDate
        FROM @InputXML.nodes('/Students/Student') AS T(x);
        
        COMMIT TRANSACTION;
        
        SELECT @@ROWCOUNT AS RowsInserted;
        
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO


-- Generate XML output from query
CREATE PROCEDURE dbo.GetStudentsAsXML
    @DepartmentID INT = NULL,
    @OutputXML XML OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    SET @OutputXML = (
        SELECT 
            (
                SELECT 
                    s.StudentID AS '@StudentID',
                    s.FirstName,
                    s.LastName,
                    s.Email,
                    s.EnrollmentDate,
                    (
                        SELECT 
                            c.CourseID AS '@CourseID',
                            c.CourseName,
                            e.Grade
                        FROM dbo.Enrollments e
                        INNER JOIN dbo.Courses c ON e.CourseID = c.CourseID
                        WHERE e.StudentID = s.StudentID
                        FOR XML PATH('Course'), TYPE
                    ) AS Courses
                FROM dbo.Students s
                WHERE @DepartmentID IS NULL OR s.DepartmentID = @DepartmentID
                FOR XML PATH('Student'), TYPE
            )
        FOR XML PATH(''), ROOT('Students')
    );
END
GO


-- Parse JSON input and insert into table
CREATE PROCEDURE dbo.ParseJSONAndInsert
    @InputJSON NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        INSERT INTO dbo.Products (
            ProductID,
            ProductName,
            Price,
            CategoryID,
            Attributes
        )
        SELECT 
            ProductID,
            ProductName,
            Price,
            CategoryID,
            Attributes
        FROM OPENJSON(@InputJSON)
        WITH (
            ProductID INT '$.productId',
            ProductName NVARCHAR(100) '$.name',
            Price DECIMAL(10,2) '$.price',
            CategoryID INT '$.categoryId',
            Attributes NVARCHAR(MAX) '$.attributes' AS JSON
        );
        
        COMMIT TRANSACTION;
        
        SELECT @@ROWCOUNT AS RowsInserted;
        
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO


-- Generate JSON output from query
CREATE PROCEDURE dbo.GetProductsAsJSON
    @CategoryID INT = NULL,
    @IncludeInventory BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    IF @IncludeInventory = 1
    BEGIN
        SELECT 
            p.ProductID AS productId,
            p.ProductName AS name,
            p.Price AS price,
            c.CategoryName AS category,
            (
                SELECT 
                    i.WarehouseID AS warehouseId,
                    w.WarehouseName AS warehouseName,
                    i.Quantity AS quantity
                FROM dbo.Inventory i
                INNER JOIN dbo.Warehouses w ON i.WarehouseID = w.WarehouseID
                WHERE i.ProductID = p.ProductID
                FOR JSON PATH
            ) AS inventory
        FROM dbo.Products p
        INNER JOIN dbo.Categories c ON p.CategoryID = c.CategoryID
        WHERE @CategoryID IS NULL OR p.CategoryID = @CategoryID
        FOR JSON PATH, ROOT('products');
    END
    ELSE
    BEGIN
        SELECT 
            p.ProductID AS productId,
            p.ProductName AS name,
            p.Price AS price,
            c.CategoryName AS category
        FROM dbo.Products p
        INNER JOIN dbo.Categories c ON p.CategoryID = c.CategoryID
        WHERE @CategoryID IS NULL OR p.CategoryID = @CategoryID
        FOR JSON PATH, ROOT('products');
    END
END
GO


-- String aggregation using FOR XML PATH (legacy pattern)
CREATE PROCEDURE dbo.GetConcatenatedValues
    @GroupColumn NVARCHAR(100),
    @TableName NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Example: Get comma-separated list of product names per category
    SELECT 
        c.CategoryID,
        c.CategoryName,
        STUFF(
            (
                SELECT ', ' + p.ProductName
                FROM dbo.Products p
                WHERE p.CategoryID = c.CategoryID
                ORDER BY p.ProductName
                FOR XML PATH(''), TYPE
            ).value('.', 'NVARCHAR(MAX)'),
            1, 2, ''
        ) AS ProductList
    FROM dbo.Categories c
    ORDER BY c.CategoryName;
END
GO


-- Compare XML documents
CREATE PROCEDURE dbo.CompareXMLDocuments
    @XML1 XML,
    @XML2 XML
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @Differences TABLE (
        XPath NVARCHAR(500),
        Value1 NVARCHAR(MAX),
        Value2 NVARCHAR(MAX),
        DifferenceType NVARCHAR(50)
    );
    
    -- Find elements in XML1 not in XML2 or with different values
    ;WITH XML1Elements AS (
        SELECT 
            T.c.value('local-name(.)', 'NVARCHAR(100)') AS ElementName,
            T.c.value('.', 'NVARCHAR(MAX)') AS ElementValue,
            T.c.query('.') AS ElementXML
        FROM @XML1.nodes('//*') AS T(c)
    ),
    XML2Elements AS (
        SELECT 
            T.c.value('local-name(.)', 'NVARCHAR(100)') AS ElementName,
            T.c.value('.', 'NVARCHAR(MAX)') AS ElementValue,
            T.c.query('.') AS ElementXML
        FROM @XML2.nodes('//*') AS T(c)
    )
    INSERT INTO @Differences (XPath, Value1, Value2, DifferenceType)
    SELECT 
        x1.ElementName,
        x1.ElementValue,
        x2.ElementValue,
        CASE 
            WHEN x2.ElementName IS NULL THEN 'Missing in XML2'
            WHEN x1.ElementValue <> x2.ElementValue THEN 'Value Difference'
            ELSE 'Match'
        END
    FROM XML1Elements x1
    LEFT JOIN XML2Elements x2 ON x1.ElementName = x2.ElementName
    WHERE x2.ElementName IS NULL OR x1.ElementValue <> x2.ElementValue;
    
    SELECT * FROM @Differences;
END
GO
