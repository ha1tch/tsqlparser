-- Sample 073: API Response Formatting
-- Source: Various - REST API patterns, MSSQLTips, Stack Overflow
-- Category: Integration
-- Complexity: Complex
-- Features: JSON response formatting, pagination, error responses, HATEOAS links

-- Format API response with pagination
CREATE PROCEDURE dbo.FormatPaginatedResponse
    @Query NVARCHAR(MAX),
    @PageNumber INT = 1,
    @PageSize INT = 25,
    @SortColumn NVARCHAR(128) = NULL,
    @SortDirection NVARCHAR(4) = 'ASC',
    @BaseUrl NVARCHAR(500) = '/api/resource'
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @TotalCount INT;
    DECLARE @TotalPages INT;
    DECLARE @Offset INT = (@PageNumber - 1) * @PageSize;
    
    -- Get total count
    SET @SQL = N'SELECT @Cnt = COUNT(*) FROM (' + @Query + ') AS CountQuery';
    EXEC sp_executesql @SQL, N'@Cnt INT OUTPUT', @Cnt = @TotalCount OUTPUT;
    
    SET @TotalPages = CEILING(CAST(@TotalCount AS FLOAT) / @PageSize);
    
    -- Build paginated query
    SET @SQL = N'
        ;WITH PagedData AS (
            SELECT *, ROW_NUMBER() OVER (ORDER BY ' + 
            ISNULL(QUOTENAME(@SortColumn), '(SELECT NULL)') + ' ' + @SortDirection + 
            ') AS RowNum
            FROM (' + @Query + ') AS BaseQuery
        )
        SELECT 
            (SELECT * FROM PagedData WHERE RowNum > @Offset AND RowNum <= @Offset + @Size FOR JSON PATH) AS data,
            (SELECT 
                @Total AS totalCount,
                @Pages AS totalPages,
                @Page AS currentPage,
                @Size AS pageSize,
                CASE WHEN @Page > 1 THEN @Url + ''?page='' + CAST(@Page - 1 AS VARCHAR(10)) + ''&size='' + CAST(@Size AS VARCHAR(10)) END AS previousPage,
                CASE WHEN @Page < @Pages THEN @Url + ''?page='' + CAST(@Page + 1 AS VARCHAR(10)) + ''&size='' + CAST(@Size AS VARCHAR(10)) END AS nextPage,
                @Url + ''?page=1&size='' + CAST(@Size AS VARCHAR(10)) AS firstPage,
                @Url + ''?page='' + CAST(@Pages AS VARCHAR(10)) + ''&size='' + CAST(@Size AS VARCHAR(10)) AS lastPage
             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS pagination';
    
    EXEC sp_executesql @SQL,
        N'@Offset INT, @Size INT, @Total INT, @Pages INT, @Page INT, @Url NVARCHAR(500)',
        @Offset = @Offset, @Size = @PageSize, @Total = @TotalCount, 
        @Pages = @TotalPages, @Page = @PageNumber, @Url = @BaseUrl;
END
GO

-- Format API error response
CREATE PROCEDURE dbo.FormatErrorResponse
    @ErrorCode NVARCHAR(50),
    @ErrorMessage NVARCHAR(MAX),
    @HttpStatus INT = 400,
    @Details NVARCHAR(MAX) = NULL,  -- JSON additional details
    @RequestId NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    SET @RequestId = ISNULL(@RequestId, CAST(NEWID() AS NVARCHAR(100)));
    
    SELECT (
        SELECT 
            @HttpStatus AS status,
            @ErrorCode AS code,
            @ErrorMessage AS message,
            @RequestId AS requestId,
            CONVERT(VARCHAR(30), SYSDATETIME(), 127) AS timestamp,
            JSON_QUERY(@Details) AS details
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    ) AS ErrorResponse;
END
GO

-- Format API success response with metadata
CREATE PROCEDURE dbo.FormatSuccessResponse
    @Data NVARCHAR(MAX),  -- JSON data
    @Message NVARCHAR(500) = 'Success',
    @HttpStatus INT = 200,
    @Links NVARCHAR(MAX) = NULL,  -- JSON HATEOAS links
    @RequestId NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    SET @RequestId = ISNULL(@RequestId, CAST(NEWID() AS NVARCHAR(100)));
    
    SELECT (
        SELECT 
            @HttpStatus AS status,
            @Message AS message,
            @RequestId AS requestId,
            CONVERT(VARCHAR(30), SYSDATETIME(), 127) AS timestamp,
            JSON_QUERY(@Data) AS data,
            JSON_QUERY(@Links) AS _links
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    ) AS SuccessResponse;
END
GO

-- Generate HATEOAS links
CREATE FUNCTION dbo.GenerateHATEOASLinks
(
    @ResourceType NVARCHAR(100),
    @ResourceId NVARCHAR(100),
    @BaseUrl NVARCHAR(500)
)
RETURNS NVARCHAR(MAX)
AS
BEGIN
    DECLARE @Links NVARCHAR(MAX);
    
    SET @Links = (
        SELECT 
            'self' AS rel,
            @BaseUrl + '/' + @ResourceType + '/' + @ResourceId AS href,
            'GET' AS method
        FOR JSON PATH
    );
    
    -- Add common links based on resource type
    SET @Links = JSON_MODIFY(@Links, 'append $', 
        JSON_QUERY('{"rel":"collection","href":"' + @BaseUrl + '/' + @ResourceType + '","method":"GET"}'));
    
    RETURN @Links;
END
GO

-- Validate and parse API request
CREATE PROCEDURE dbo.ValidateAPIRequest
    @RequestBody NVARCHAR(MAX),
    @RequiredFields NVARCHAR(MAX),  -- Comma-separated field names
    @IsValid BIT OUTPUT,
    @ValidationErrors NVARCHAR(MAX) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    SET @IsValid = 1;
    SET @ValidationErrors = '[]';
    
    DECLARE @Errors TABLE (Field NVARCHAR(100), Message NVARCHAR(500));
    
    -- Check if valid JSON
    IF ISJSON(@RequestBody) = 0
    BEGIN
        SET @IsValid = 0;
        INSERT INTO @Errors VALUES ('request', 'Invalid JSON format');
    END
    ELSE
    BEGIN
        -- Check required fields
        DECLARE @Field NVARCHAR(100);
        DECLARE @Value NVARCHAR(MAX);
        
        DECLARE FieldCursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@RequiredFields, ',');
        
        OPEN FieldCursor;
        FETCH NEXT FROM FieldCursor INTO @Field;
        
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @Value = JSON_VALUE(@RequestBody, '$.' + @Field);
            
            IF @Value IS NULL
            BEGIN
                SET @IsValid = 0;
                INSERT INTO @Errors VALUES (@Field, 'Field is required');
            END
            
            FETCH NEXT FROM FieldCursor INTO @Field;
        END
        
        CLOSE FieldCursor;
        DEALLOCATE FieldCursor;
    END
    
    -- Format validation errors
    SELECT @ValidationErrors = (SELECT Field AS field, Message AS message FROM @Errors FOR JSON PATH);
    
    IF @IsValid = 0
    BEGIN
        EXEC dbo.FormatErrorResponse 
            @ErrorCode = 'VALIDATION_ERROR',
            @ErrorMessage = 'Request validation failed',
            @HttpStatus = 400,
            @Details = @ValidationErrors;
    END
END
GO

-- Execute API endpoint with standard response
CREATE PROCEDURE dbo.ExecuteAPIEndpoint
    @EndpointName NVARCHAR(100),
    @HttpMethod NVARCHAR(10),
    @RequestBody NVARCHAR(MAX) = NULL,
    @QueryParams NVARCHAR(MAX) = NULL  -- JSON object
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @StartTime DATETIME2 = SYSDATETIME();
    DECLARE @RequestId NVARCHAR(100) = CAST(NEWID() AS NVARCHAR(100));
    DECLARE @Result NVARCHAR(MAX);
    
    BEGIN TRY
        -- Log request
        IF OBJECT_ID('dbo.APIRequestLog', 'U') IS NOT NULL
        BEGIN
            INSERT INTO dbo.APIRequestLog (RequestId, Endpoint, Method, RequestBody, QueryParams, RequestTime)
            VALUES (@RequestId, @EndpointName, @HttpMethod, @RequestBody, @QueryParams, @StartTime);
        END
        
        -- Route to appropriate handler (example pattern)
        IF @EndpointName = 'users' AND @HttpMethod = 'GET'
        BEGIN
            DECLARE @Page INT = ISNULL(JSON_VALUE(@QueryParams, '$.page'), 1);
            DECLARE @Size INT = ISNULL(JSON_VALUE(@QueryParams, '$.size'), 25);
            
            EXEC dbo.FormatPaginatedResponse 
                @Query = 'SELECT UserID, UserName, Email, CreatedDate FROM dbo.Users',
                @PageNumber = @Page,
                @PageSize = @Size,
                @BaseUrl = '/api/users';
        END
        ELSE
        BEGIN
            EXEC dbo.FormatErrorResponse 
                @ErrorCode = 'NOT_FOUND',
                @ErrorMessage = 'Endpoint not found',
                @HttpStatus = 404,
                @RequestId = @RequestId;
        END
        
    END TRY
    BEGIN CATCH
        EXEC dbo.FormatErrorResponse 
            @ErrorCode = 'INTERNAL_ERROR',
            @ErrorMessage = ERROR_MESSAGE(),
            @HttpStatus = 500,
            @RequestId = @RequestId;
    END CATCH
END
GO
