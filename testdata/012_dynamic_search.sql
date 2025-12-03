-- Sample 012: Dynamic Search with Optional Filters
-- Source: Erland Sommarskog (sommarskog.se/dyn-search.html), Stack Overflow
-- Category: Dynamic SQL
-- Complexity: Advanced
-- Features: Dynamic SQL, sp_executesql, OPTION(RECOMPILE), Parameter sniffing mitigation

-- Pattern 1: Static SQL with OPTION(RECOMPILE)
-- Best for moderate number of parameters, good plan each time
CREATE PROCEDURE dbo.SearchProducts_Static
    @ProductName NVARCHAR(100) = NULL,
    @CategoryID INT = NULL,
    @SupplierID INT = NULL,
    @MinPrice DECIMAL(18,2) = NULL,
    @MaxPrice DECIMAL(18,2) = NULL,
    @InStock BIT = NULL,
    @CreatedAfter DATE = NULL,
    @CreatedBefore DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        p.ProductID,
        p.ProductName,
        p.CategoryID,
        c.CategoryName,
        p.SupplierID,
        s.SupplierName,
        p.UnitPrice,
        p.UnitsInStock,
        p.CreatedDate
    FROM dbo.Products p
    INNER JOIN dbo.Categories c ON p.CategoryID = c.CategoryID
    INNER JOIN dbo.Suppliers s ON p.SupplierID = s.SupplierID
    WHERE (@ProductName IS NULL OR p.ProductName LIKE '%' + @ProductName + '%')
      AND (@CategoryID IS NULL OR p.CategoryID = @CategoryID)
      AND (@SupplierID IS NULL OR p.SupplierID = @SupplierID)
      AND (@MinPrice IS NULL OR p.UnitPrice >= @MinPrice)
      AND (@MaxPrice IS NULL OR p.UnitPrice <= @MaxPrice)
      AND (@InStock IS NULL OR 
           (@InStock = 1 AND p.UnitsInStock > 0) OR 
           (@InStock = 0 AND p.UnitsInStock = 0))
      AND (@CreatedAfter IS NULL OR p.CreatedDate >= @CreatedAfter)
      AND (@CreatedBefore IS NULL OR p.CreatedDate <= @CreatedBefore)
    ORDER BY p.ProductName
    OPTION (RECOMPILE);  -- Get optimal plan for actual parameter values
END
GO

-- Pattern 2: Dynamic SQL for complex scenarios
-- Best when many optional parameters or complex logic
CREATE PROCEDURE dbo.SearchProducts_Dynamic
    @ProductName NVARCHAR(100) = NULL,
    @CategoryID INT = NULL,
    @SupplierID INT = NULL,
    @MinPrice DECIMAL(18,2) = NULL,
    @MaxPrice DECIMAL(18,2) = NULL,
    @InStock BIT = NULL,
    @CreatedAfter DATE = NULL,
    @CreatedBefore DATE = NULL,
    @SortColumn NVARCHAR(50) = 'ProductName',
    @SortDirection NVARCHAR(4) = 'ASC',
    @Debug BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @Params NVARCHAR(MAX);
    DECLARE @Where NVARCHAR(MAX) = N'';
    DECLARE @OrderBy NVARCHAR(200);
    
    -- Build base query
    SET @SQL = N'
        SELECT 
            p.ProductID,
            p.ProductName,
            p.CategoryID,
            c.CategoryName,
            p.SupplierID,
            s.SupplierName,
            p.UnitPrice,
            p.UnitsInStock,
            p.CreatedDate
        FROM dbo.Products p
        INNER JOIN dbo.Categories c ON p.CategoryID = c.CategoryID
        INNER JOIN dbo.Suppliers s ON p.SupplierID = s.SupplierID
        WHERE 1 = 1';
    
    -- Build WHERE clause dynamically
    IF @ProductName IS NOT NULL
        SET @Where = @Where + N' AND p.ProductName LIKE ''%'' + @ProductName + ''%''';
    
    IF @CategoryID IS NOT NULL
        SET @Where = @Where + N' AND p.CategoryID = @CategoryID';
    
    IF @SupplierID IS NOT NULL
        SET @Where = @Where + N' AND p.SupplierID = @SupplierID';
    
    IF @MinPrice IS NOT NULL
        SET @Where = @Where + N' AND p.UnitPrice >= @MinPrice';
    
    IF @MaxPrice IS NOT NULL
        SET @Where = @Where + N' AND p.UnitPrice <= @MaxPrice';
    
    IF @InStock = 1
        SET @Where = @Where + N' AND p.UnitsInStock > 0';
    ELSE IF @InStock = 0
        SET @Where = @Where + N' AND p.UnitsInStock = 0';
    
    IF @CreatedAfter IS NOT NULL
        SET @Where = @Where + N' AND p.CreatedDate >= @CreatedAfter';
    
    IF @CreatedBefore IS NOT NULL
        SET @Where = @Where + N' AND p.CreatedDate <= @CreatedBefore';
    
    -- Validate and build ORDER BY
    SET @OrderBy = CASE @SortColumn
        WHEN 'ProductName' THEN 'p.ProductName'
        WHEN 'CategoryName' THEN 'c.CategoryName'
        WHEN 'SupplierName' THEN 's.SupplierName'
        WHEN 'UnitPrice' THEN 'p.UnitPrice'
        WHEN 'UnitsInStock' THEN 'p.UnitsInStock'
        WHEN 'CreatedDate' THEN 'p.CreatedDate'
        ELSE 'p.ProductName'
    END;
    
    SET @OrderBy = @OrderBy + CASE 
        WHEN @SortDirection = 'DESC' THEN ' DESC'
        ELSE ' ASC'
    END;
    
    -- Combine query parts
    SET @SQL = @SQL + @Where + N' ORDER BY ' + @OrderBy;
    
    -- Define parameters
    SET @Params = N'
        @ProductName NVARCHAR(100),
        @CategoryID INT,
        @SupplierID INT,
        @MinPrice DECIMAL(18,2),
        @MaxPrice DECIMAL(18,2),
        @CreatedAfter DATE,
        @CreatedBefore DATE';
    
    -- Debug mode
    IF @Debug = 1
    BEGIN
        PRINT @SQL;
        PRINT @Params;
    END
    
    -- Execute
    EXEC sp_executesql @SQL, @Params,
        @ProductName = @ProductName,
        @CategoryID = @CategoryID,
        @SupplierID = @SupplierID,
        @MinPrice = @MinPrice,
        @MaxPrice = @MaxPrice,
        @CreatedAfter = @CreatedAfter,
        @CreatedBefore = @CreatedBefore;
END
GO

-- Pattern 3: Using table variable for IN clause
CREATE PROCEDURE dbo.SearchProductsByCategories
    @CategoryList NVARCHAR(MAX),  -- Comma-separated list
    @ProductName NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Parse comma-separated list into table
    DECLARE @Categories TABLE (CategoryID INT);
    
    INSERT INTO @Categories (CategoryID)
    SELECT CAST(value AS INT)
    FROM STRING_SPLIT(@CategoryList, ',')
    WHERE RTRIM(LTRIM(value)) <> '';
    
    SELECT 
        p.ProductID,
        p.ProductName,
        c.CategoryName,
        p.UnitPrice
    FROM dbo.Products p
    INNER JOIN dbo.Categories c ON p.CategoryID = c.CategoryID
    WHERE p.CategoryID IN (SELECT CategoryID FROM @Categories)
      AND (@ProductName IS NULL OR p.ProductName LIKE '%' + @ProductName + '%')
    ORDER BY c.CategoryName, p.ProductName;
END
GO
