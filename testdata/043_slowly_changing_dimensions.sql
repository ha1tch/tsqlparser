-- Sample 043: Slowly Changing Dimensions (SCD)
-- Source: Kimball Group, MSSQLTips, SQLServerCentral
-- Category: ETL/Data Loading
-- Complexity: Advanced
-- Features: SCD Type 1, Type 2, Type 3, MERGE, history tracking

-- SCD Type 1: Overwrite (no history)
CREATE PROCEDURE dbo.LoadSCD_Type1
    @SourceSchema NVARCHAR(128),
    @SourceTable NVARCHAR(128),
    @TargetSchema NVARCHAR(128),
    @TargetTable NVARCHAR(128),
    @BusinessKey NVARCHAR(MAX),  -- Comma-separated
    @Columns NVARCHAR(MAX)       -- Columns to update
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @SourcePath NVARCHAR(256) = QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable);
    DECLARE @TargetPath NVARCHAR(256) = QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable);
    DECLARE @JoinCondition NVARCHAR(MAX);
    DECLARE @UpdateSet NVARCHAR(MAX);
    DECLARE @InsertColumns NVARCHAR(MAX);
    DECLARE @SourceColumns NVARCHAR(MAX);
    
    -- Build join condition
    SELECT @JoinCondition = STRING_AGG(
        't.' + QUOTENAME(LTRIM(RTRIM(value))) + ' = s.' + QUOTENAME(LTRIM(RTRIM(value))), ' AND '
    )
    FROM STRING_SPLIT(@BusinessKey, ',');
    
    -- Build update set
    SELECT @UpdateSet = STRING_AGG(
        't.' + QUOTENAME(LTRIM(RTRIM(value))) + ' = s.' + QUOTENAME(LTRIM(RTRIM(value))), ', '
    )
    FROM STRING_SPLIT(@Columns, ',');
    
    -- Build insert columns
    SET @InsertColumns = @BusinessKey + ', ' + @Columns;
    SELECT @SourceColumns = STRING_AGG('s.' + QUOTENAME(LTRIM(RTRIM(value))), ', ')
    FROM STRING_SPLIT(@InsertColumns, ',');
    
    SET @SQL = N'
    MERGE ' + @TargetPath + ' AS t
    USING ' + @SourcePath + ' AS s
    ON ' + @JoinCondition + '
    WHEN MATCHED THEN
        UPDATE SET ' + @UpdateSet + ', t.LastModifiedDate = GETDATE()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (' + @InsertColumns + ', CreatedDate, LastModifiedDate)
        VALUES (' + @SourceColumns + ', GETDATE(), GETDATE())
    OUTPUT $action AS MergeAction;';
    
    EXEC sp_executesql @SQL;
    
    SELECT @@ROWCOUNT AS RowsAffected;
END
GO

-- SCD Type 2: Add new row (full history)
CREATE PROCEDURE dbo.LoadSCD_Type2
    @SourceSchema NVARCHAR(128),
    @SourceTable NVARCHAR(128),
    @TargetSchema NVARCHAR(128),
    @TargetTable NVARCHAR(128),
    @BusinessKey NVARCHAR(MAX),
    @TrackingColumns NVARCHAR(MAX),  -- Columns that trigger new version
    @EffectiveDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @SourcePath NVARCHAR(256) = QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable);
    DECLARE @TargetPath NVARCHAR(256) = QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable);
    DECLARE @JoinCondition NVARCHAR(MAX);
    DECLARE @ChangeCondition NVARCHAR(MAX);
    DECLARE @AllColumns NVARCHAR(MAX);
    
    SET @EffectiveDate = ISNULL(@EffectiveDate, CAST(GETDATE() AS DATE));
    
    -- Build join condition
    SELECT @JoinCondition = STRING_AGG(
        't.' + QUOTENAME(LTRIM(RTRIM(value))) + ' = s.' + QUOTENAME(LTRIM(RTRIM(value))), ' AND '
    )
    FROM STRING_SPLIT(@BusinessKey, ',');
    
    -- Build change detection condition
    SELECT @ChangeCondition = STRING_AGG(
        'ISNULL(CAST(t.' + QUOTENAME(LTRIM(RTRIM(value))) + ' AS NVARCHAR(MAX)), '''') <> ' +
        'ISNULL(CAST(s.' + QUOTENAME(LTRIM(RTRIM(value))) + ' AS NVARCHAR(MAX)), '''')', ' OR '
    )
    FROM STRING_SPLIT(@TrackingColumns, ',');
    
    -- Get all columns from source
    SELECT @AllColumns = STRING_AGG(c.name, ', ')
    FROM sys.columns c
    WHERE c.object_id = OBJECT_ID(@SourcePath);
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        -- Step 1: Expire changed records
        SET @SQL = N'
        UPDATE t
        SET t.EffectiveEndDate = DATEADD(DAY, -1, @EffDate),
            t.IsCurrent = 0
        FROM ' + @TargetPath + ' t
        INNER JOIN ' + @SourcePath + ' s ON ' + @JoinCondition + '
        WHERE t.IsCurrent = 1
          AND (' + @ChangeCondition + ')';
        
        EXEC sp_executesql @SQL, N'@EffDate DATE', @EffDate = @EffectiveDate;
        
        DECLARE @ExpiredCount INT = @@ROWCOUNT;
        
        -- Step 2: Insert new versions for changed records
        SET @SQL = N'
        INSERT INTO ' + @TargetPath + ' (' + @AllColumns + ', EffectiveStartDate, EffectiveEndDate, IsCurrent)
        SELECT s.*, @EffDate, ''9999-12-31'', 1
        FROM ' + @SourcePath + ' s
        INNER JOIN ' + @TargetPath + ' t ON ' + @JoinCondition + '
        WHERE t.EffectiveEndDate = DATEADD(DAY, -1, @EffDate)
          AND t.IsCurrent = 0';
        
        EXEC sp_executesql @SQL, N'@EffDate DATE', @EffDate = @EffectiveDate;
        
        DECLARE @NewVersionCount INT = @@ROWCOUNT;
        
        -- Step 3: Insert truly new records
        SET @SQL = N'
        INSERT INTO ' + @TargetPath + ' (' + @AllColumns + ', EffectiveStartDate, EffectiveEndDate, IsCurrent)
        SELECT s.*, @EffDate, ''9999-12-31'', 1
        FROM ' + @SourcePath + ' s
        WHERE NOT EXISTS (
            SELECT 1 FROM ' + @TargetPath + ' t
            WHERE ' + @JoinCondition + '
        )';
        
        EXEC sp_executesql @SQL, N'@EffDate DATE', @EffDate = @EffectiveDate;
        
        DECLARE @NewRecordCount INT = @@ROWCOUNT;
        
        COMMIT TRANSACTION;
        
        SELECT 
            @ExpiredCount AS RecordsExpired,
            @NewVersionCount AS NewVersionsCreated,
            @NewRecordCount AS NewRecordsInserted;
            
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

-- SCD Type 3: Add new column (limited history)
CREATE PROCEDURE dbo.LoadSCD_Type3
    @SourceSchema NVARCHAR(128),
    @SourceTable NVARCHAR(128),
    @TargetSchema NVARCHAR(128),
    @TargetTable NVARCHAR(128),
    @BusinessKey NVARCHAR(MAX),
    @TrackingColumn NVARCHAR(128),
    @PreviousColumnName NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @SourcePath NVARCHAR(256) = QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable);
    DECLARE @TargetPath NVARCHAR(256) = QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable);
    DECLARE @JoinCondition NVARCHAR(MAX);
    
    -- Build join condition
    SELECT @JoinCondition = STRING_AGG(
        't.' + QUOTENAME(LTRIM(RTRIM(value))) + ' = s.' + QUOTENAME(LTRIM(RTRIM(value))), ' AND '
    )
    FROM STRING_SPLIT(@BusinessKey, ',');
    
    -- Update with previous value tracking
    SET @SQL = N'
    UPDATE t
    SET t.' + QUOTENAME(@PreviousColumnName) + ' = t.' + QUOTENAME(@TrackingColumn) + ',
        t.' + QUOTENAME(@TrackingColumn) + ' = s.' + QUOTENAME(@TrackingColumn) + ',
        t.LastChangeDate = GETDATE()
    FROM ' + @TargetPath + ' t
    INNER JOIN ' + @SourcePath + ' s ON ' + @JoinCondition + '
    WHERE ISNULL(CAST(t.' + QUOTENAME(@TrackingColumn) + ' AS NVARCHAR(MAX)), '''') <> 
          ISNULL(CAST(s.' + QUOTENAME(@TrackingColumn) + ' AS NVARCHAR(MAX)), '''')';
    
    EXEC sp_executesql @SQL;
    
    SELECT @@ROWCOUNT AS RecordsUpdated;
END
GO

-- SCD Type 6: Hybrid (combines 1, 2, and 3)
CREATE PROCEDURE dbo.LoadSCD_Type6
    @SourceSchema NVARCHAR(128),
    @SourceTable NVARCHAR(128),
    @TargetSchema NVARCHAR(128),
    @TargetTable NVARCHAR(128),
    @BusinessKey NVARCHAR(MAX),
    @Type1Columns NVARCHAR(MAX),      -- Overwrite, update all versions
    @Type2Columns NVARCHAR(MAX),      -- Add new row
    @CurrentValueColumn NVARCHAR(128), -- Current value column name
    @EffectiveDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @SourcePath NVARCHAR(256) = QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable);
    DECLARE @TargetPath NVARCHAR(256) = QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable);
    DECLARE @JoinCondition NVARCHAR(MAX);
    DECLARE @Type2ChangeCondition NVARCHAR(MAX);
    DECLARE @Type1UpdateSet NVARCHAR(MAX);
    
    SET @EffectiveDate = ISNULL(@EffectiveDate, CAST(GETDATE() AS DATE));
    
    -- Build conditions
    SELECT @JoinCondition = STRING_AGG(
        't.' + QUOTENAME(LTRIM(RTRIM(value))) + ' = s.' + QUOTENAME(LTRIM(RTRIM(value))), ' AND '
    )
    FROM STRING_SPLIT(@BusinessKey, ',');
    
    SELECT @Type2ChangeCondition = STRING_AGG(
        'ISNULL(CAST(t.' + QUOTENAME(LTRIM(RTRIM(value))) + ' AS NVARCHAR(MAX)), '''') <> ' +
        'ISNULL(CAST(s.' + QUOTENAME(LTRIM(RTRIM(value))) + ' AS NVARCHAR(MAX)), '''')', ' OR '
    )
    FROM STRING_SPLIT(@Type2Columns, ',');
    
    SELECT @Type1UpdateSet = STRING_AGG(
        QUOTENAME(LTRIM(RTRIM(value))) + ' = s.' + QUOTENAME(LTRIM(RTRIM(value))), ', '
    )
    FROM STRING_SPLIT(@Type1Columns, ',');
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        -- Step 1: Type 1 updates across all versions
        SET @SQL = N'
        UPDATE t
        SET ' + @Type1UpdateSet + '
        FROM ' + @TargetPath + ' t
        INNER JOIN ' + @SourcePath + ' s ON ' + @JoinCondition;
        
        EXEC sp_executesql @SQL;
        
        -- Step 2: Update current value column for all historical records
        SET @SQL = N'
        UPDATE t
        SET t.' + QUOTENAME(@CurrentValueColumn) + ' = curr.' + QUOTENAME(@CurrentValueColumn) + '
        FROM ' + @TargetPath + ' t
        INNER JOIN (
            SELECT ' + @BusinessKey + ', ' + QUOTENAME(@CurrentValueColumn) + '
            FROM ' + @SourcePath + '
        ) curr ON ' + REPLACE(@JoinCondition, 't.', 'curr.');
        
        EXEC sp_executesql @SQL;
        
        -- Step 3: Handle Type 2 changes (same as SCD Type 2)
        -- ... (similar logic to LoadSCD_Type2)
        
        COMMIT TRANSACTION;
        
        SELECT 'SCD Type 6 load completed' AS Status;
        
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
