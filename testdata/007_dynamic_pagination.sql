-- Sample 007: Dynamic Pagination with Sorting and Filtering
-- Source: Various - StackOverflow, MSSQLTips, Medium articles
-- Category: Pagination
-- Complexity: Advanced
-- Features: OFFSET FETCH, Dynamic SQL, sp_executesql, Parameter validation

CREATE PROCEDURE dbo.GetPagedResults
    @TableName NVARCHAR(128),
    @PageNumber INT = 1,
    @PageSize INT = 20,
    @SortColumn NVARCHAR(128) = NULL,
    @SortOrder NVARCHAR(4) = 'ASC',
    @FilterColumn NVARCHAR(128) = NULL,
    @FilterValue NVARCHAR(500) = NULL,
    @TotalRecords INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Validate inputs
    IF @PageNumber < 1 SET @PageNumber = 1;
    IF @PageSize < 1 OR @PageSize > 1000 SET @PageSize = 20;
    IF @SortOrder NOT IN ('ASC', 'DESC') SET @SortOrder = 'ASC';
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @CountSQL NVARCHAR(MAX);
    DECLARE @Params NVARCHAR(MAX);
    DECLARE @Offset INT = (@PageNumber - 1) * @PageSize;
    
    -- Validate table exists
    IF NOT EXISTS (
        SELECT 1 FROM sys.tables 
        WHERE name = @TableName AND schema_id = SCHEMA_ID('dbo')
    )
    BEGIN
        RAISERROR('Table does not exist: %s', 16, 1, @TableName);
        RETURN;
    END
    
    -- Validate sort column exists if specified
    IF @SortColumn IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM sys.columns c
        INNER JOIN sys.tables t ON c.object_id = t.object_id
        WHERE t.name = @TableName AND c.name = @SortColumn
    )
    BEGIN
        RAISERROR('Column does not exist: %s', 16, 1, @SortColumn);
        RETURN;
    END
    
    -- Build the count query
    SET @CountSQL = N'SELECT @TotalRecords = COUNT(*) FROM ' + QUOTENAME(@TableName);
    
    IF @FilterColumn IS NOT NULL AND @FilterValue IS NOT NULL
    BEGIN
        SET @CountSQL = @CountSQL + 
            N' WHERE ' + QUOTENAME(@FilterColumn) + N' LIKE @FilterValue';
    END
    
    -- Execute count query
    SET @Params = N'@FilterValue NVARCHAR(500), @TotalRecords INT OUTPUT';
    EXEC sp_executesql @CountSQL, @Params, 
        @FilterValue = @FilterValue, 
        @TotalRecords = @TotalRecords OUTPUT;
    
    -- Build the data query
    SET @SQL = N'SELECT * FROM ' + QUOTENAME(@TableName);
    
    IF @FilterColumn IS NOT NULL AND @FilterValue IS NOT NULL
    BEGIN
        SET @SQL = @SQL + 
            N' WHERE ' + QUOTENAME(@FilterColumn) + N' LIKE @FilterValue';
    END
    
    -- Add sorting
    IF @SortColumn IS NOT NULL
    BEGIN
        SET @SQL = @SQL + N' ORDER BY ' + QUOTENAME(@SortColumn) + N' ' + @SortOrder;
    END
    ELSE
    BEGIN
        -- Default sort by first column
        SET @SQL = @SQL + N' ORDER BY (SELECT NULL)';
    END
    
    -- Add pagination
    SET @SQL = @SQL + 
        N' OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY';
    
    -- Execute data query
    SET @Params = N'@FilterValue NVARCHAR(500), @Offset INT, @PageSize INT';
    EXEC sp_executesql @SQL, @Params, 
        @FilterValue = @FilterValue, 
        @Offset = @Offset, 
        @PageSize = @PageSize;
END
GO


-- Alternative: CTE-based pagination (works with SQL 2005+)
CREATE PROCEDURE dbo.GetPagedResultsCTE
    @PageNumber INT = 1,
    @PageSize INT = 20,
    @SortColumn NVARCHAR(50) = 'ID',
    @SortDirection NVARCHAR(4) = 'ASC',
    @SearchText NVARCHAR(100) = NULL,
    @TotalCount INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @StartRow INT = (@PageNumber - 1) * @PageSize + 1;
    DECLARE @EndRow INT = @PageNumber * @PageSize;
    
    -- Get total count
    SELECT @TotalCount = COUNT(*) 
    FROM Products
    WHERE @SearchText IS NULL 
       OR ProductName LIKE '%' + @SearchText + '%'
       OR Description LIKE '%' + @SearchText + '%';
    
    -- Get paged data using CTE
    ;WITH OrderedProducts AS
    (
        SELECT 
            ProductID,
            ProductName,
            Description,
            Price,
            CategoryID,
            ROW_NUMBER() OVER (
                ORDER BY 
                    CASE WHEN @SortColumn = 'ProductName' AND @SortDirection = 'ASC' 
                         THEN ProductName END ASC,
                    CASE WHEN @SortColumn = 'ProductName' AND @SortDirection = 'DESC' 
                         THEN ProductName END DESC,
                    CASE WHEN @SortColumn = 'Price' AND @SortDirection = 'ASC' 
                         THEN Price END ASC,
                    CASE WHEN @SortColumn = 'Price' AND @SortDirection = 'DESC' 
                         THEN Price END DESC,
                    CASE WHEN @SortColumn = 'ID' AND @SortDirection = 'ASC' 
                         THEN ProductID END ASC,
                    CASE WHEN @SortColumn = 'ID' AND @SortDirection = 'DESC' 
                         THEN ProductID END DESC
            ) AS RowNum
        FROM Products
        WHERE @SearchText IS NULL 
           OR ProductName LIKE '%' + @SearchText + '%'
           OR Description LIKE '%' + @SearchText + '%'
    )
    SELECT 
        ProductID,
        ProductName,
        Description,
        Price,
        CategoryID,
        RowNum,
        @TotalCount AS TotalCount,
        CEILING(CAST(@TotalCount AS FLOAT) / @PageSize) AS TotalPages
    FROM OrderedProducts
    WHERE RowNum BETWEEN @StartRow AND @EndRow
    ORDER BY RowNum;
END
GO
