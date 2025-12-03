-- Sample 069: Database File Management
-- Source: Microsoft Learn, MSSQLTips, Brent Ozar
-- Category: Performance
-- Complexity: Complex
-- Features: Filegroups, file growth, autogrow events, file distribution

-- Get database file information
CREATE PROCEDURE dbo.GetDatabaseFileInfo
    @DatabaseName NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    SET @DatabaseName = ISNULL(@DatabaseName, DB_NAME());
    
    SELECT 
        DB_NAME(mf.database_id) AS DatabaseName,
        mf.name AS LogicalName,
        mf.physical_name AS PhysicalPath,
        fg.name AS FileGroup,
        mf.type_desc AS FileType,
        CAST(mf.size * 8.0 / 1024 AS DECIMAL(18,2)) AS SizeMB,
        CAST(FILEPROPERTY(mf.name, 'SpaceUsed') * 8.0 / 1024 AS DECIMAL(18,2)) AS UsedMB,
        CAST((mf.size - FILEPROPERTY(mf.name, 'SpaceUsed')) * 8.0 / 1024 AS DECIMAL(18,2)) AS FreeMB,
        CAST((mf.size - FILEPROPERTY(mf.name, 'SpaceUsed')) * 100.0 / mf.size AS DECIMAL(5,2)) AS FreePercent,
        CASE mf.is_percent_growth 
            WHEN 1 THEN CAST(mf.growth AS VARCHAR(10)) + '%'
            ELSE CAST(mf.growth * 8 / 1024 AS VARCHAR(10)) + ' MB'
        END AS GrowthSetting,
        CASE 
            WHEN mf.max_size = -1 THEN 'Unlimited'
            WHEN mf.max_size = 0 THEN 'No Growth'
            ELSE CAST(mf.max_size * 8.0 / 1024 / 1024 AS VARCHAR(20)) + ' GB'
        END AS MaxSize,
        mf.is_read_only AS IsReadOnly,
        fg.is_default AS IsDefaultFileGroup
    FROM sys.master_files mf
    LEFT JOIN sys.filegroups fg ON mf.data_space_id = fg.data_space_id AND mf.database_id = DB_ID()
    WHERE mf.database_id = DB_ID(@DatabaseName)
    ORDER BY mf.type, mf.file_id;
END
GO

-- Add data file to filegroup
CREATE PROCEDURE dbo.AddDataFile
    @DatabaseName NVARCHAR(128) = NULL,
    @FileGroupName NVARCHAR(128) = 'PRIMARY',
    @LogicalName NVARCHAR(128),
    @FilePath NVARCHAR(500),
    @InitialSizeMB INT = 100,
    @GrowthMB INT = 100,
    @MaxSizeMB INT = -1  -- -1 = unlimited
AS
BEGIN
    SET NOCOUNT ON;
    
    SET @DatabaseName = ISNULL(@DatabaseName, DB_NAME());
    
    DECLARE @SQL NVARCHAR(MAX);
    
    SET @SQL = N'
        ALTER DATABASE ' + QUOTENAME(@DatabaseName) + '
        ADD FILE (
            NAME = ' + QUOTENAME(@LogicalName, '''') + ',
            FILENAME = ' + QUOTENAME(@FilePath, '''') + ',
            SIZE = ' + CAST(@InitialSizeMB AS VARCHAR(10)) + 'MB,
            FILEGROWTH = ' + CAST(@GrowthMB AS VARCHAR(10)) + 'MB' +
            CASE WHEN @MaxSizeMB > 0 
                 THEN ', MAXSIZE = ' + CAST(@MaxSizeMB AS VARCHAR(10)) + 'MB'
                 WHEN @MaxSizeMB = -1 THEN ', MAXSIZE = UNLIMITED'
                 ELSE '' 
            END + '
        ) TO FILEGROUP ' + QUOTENAME(@FileGroupName);
    
    EXEC sp_executesql @SQL;
    
    SELECT 'File added successfully' AS Status, @LogicalName AS FileName, @FileGroupName AS FileGroup;
END
GO

-- Create filegroup
CREATE PROCEDURE dbo.CreateFileGroup
    @DatabaseName NVARCHAR(128) = NULL,
    @FileGroupName NVARCHAR(128),
    @IsDefault BIT = 0,
    @IsReadOnly BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    SET @DatabaseName = ISNULL(@DatabaseName, DB_NAME());
    
    DECLARE @SQL NVARCHAR(MAX);
    
    -- Create filegroup
    SET @SQL = 'ALTER DATABASE ' + QUOTENAME(@DatabaseName) + ' ADD FILEGROUP ' + QUOTENAME(@FileGroupName);
    EXEC sp_executesql @SQL;
    
    -- Set as default if requested
    IF @IsDefault = 1
    BEGIN
        SET @SQL = 'ALTER DATABASE ' + QUOTENAME(@DatabaseName) + ' MODIFY FILEGROUP ' + QUOTENAME(@FileGroupName) + ' DEFAULT';
        EXEC sp_executesql @SQL;
    END
    
    -- Set as read only if requested
    IF @IsReadOnly = 1
    BEGIN
        SET @SQL = 'ALTER DATABASE ' + QUOTENAME(@DatabaseName) + ' MODIFY FILEGROUP ' + QUOTENAME(@FileGroupName) + ' READONLY';
        EXEC sp_executesql @SQL;
    END
    
    SELECT 'Filegroup created' AS Status, @FileGroupName AS FileGroupName;
END
GO

-- Analyze file growth events
CREATE PROCEDURE dbo.AnalyzeFileGrowthEvents
    @DatabaseName NVARCHAR(128) = NULL,
    @DaysBack INT = 30
AS
BEGIN
    SET NOCOUNT ON;
    
    SET @DatabaseName = ISNULL(@DatabaseName, DB_NAME());
    
    ;WITH GrowthEvents AS (
        SELECT 
            DB_NAME(database_id) AS DatabaseName,
            file_id,
            CASE is_percent_growth 
                WHEN 1 THEN 'Percent' 
                ELSE 'Fixed' 
            END AS GrowthType,
            growth,
            DATEADD(SECOND, -1 * (DATEDIFF(SECOND, GETDATE(), GETUTCDATE())), timestamp) AS EventTime
        FROM sys.fn_dblog(NULL, NULL)
        WHERE operation IN ('LOP_MODIFY_ROW')
          AND [context] = 'LCX_BOOT_PAGE'
          AND DATEADD(SECOND, -1 * (DATEDIFF(SECOND, GETDATE(), GETUTCDATE())), timestamp) >= DATEADD(DAY, -@DaysBack, GETDATE())
    )
    SELECT 
        DatabaseName,
        COUNT(*) AS GrowthEventCount,
        MIN(EventTime) AS FirstGrowth,
        MAX(EventTime) AS LastGrowth
    FROM GrowthEvents
    WHERE @DatabaseName IS NULL OR DatabaseName = @DatabaseName
    GROUP BY DatabaseName;
    
    -- Current growth settings recommendation
    SELECT 
        DB_NAME(database_id) AS DatabaseName,
        name AS FileName,
        type_desc AS FileType,
        CAST(size * 8.0 / 1024 AS DECIMAL(18,2)) AS CurrentSizeMB,
        CASE is_percent_growth 
            WHEN 1 THEN CAST(growth AS VARCHAR(10)) + '%'
            ELSE CAST(growth * 8 / 1024 AS VARCHAR(10)) + ' MB'
        END AS CurrentGrowth,
        CASE 
            WHEN is_percent_growth = 1 THEN 'Consider fixed growth (64MB-256MB for data, 64MB for log)'
            WHEN growth * 8 / 1024 < 64 THEN 'Growth too small - increase to at least 64MB'
            WHEN growth * 8 / 1024 > 1024 THEN 'Growth very large - consider smaller increments'
            ELSE 'Growth setting looks reasonable'
        END AS Recommendation
    FROM sys.master_files
    WHERE @DatabaseName IS NULL OR database_id = DB_ID(@DatabaseName);
END
GO

-- Shrink database file
CREATE PROCEDURE dbo.ShrinkDatabaseFile
    @DatabaseName NVARCHAR(128) = NULL,
    @FileName NVARCHAR(128),
    @TargetSizeMB INT,
    @TruncateOnly BIT = 0,
    @WhatIf BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    SET @DatabaseName = ISNULL(@DatabaseName, DB_NAME());
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @CurrentSizeMB DECIMAL(18,2);
    DECLARE @UsedMB DECIMAL(18,2);
    
    -- Get current size info
    SELECT 
        @CurrentSizeMB = CAST(size * 8.0 / 1024 AS DECIMAL(18,2)),
        @UsedMB = CAST(FILEPROPERTY(name, 'SpaceUsed') * 8.0 / 1024 AS DECIMAL(18,2))
    FROM sys.master_files
    WHERE database_id = DB_ID(@DatabaseName) AND name = @FileName;
    
    IF @CurrentSizeMB IS NULL
    BEGIN
        RAISERROR('File not found: %s', 16, 1, @FileName);
        RETURN;
    END
    
    -- Warning about shrinking
    SELECT 
        'WARNING: Shrinking causes fragmentation and is generally not recommended!' AS Warning,
        @FileName AS FileName,
        @CurrentSizeMB AS CurrentSizeMB,
        @UsedMB AS UsedSpaceMB,
        @TargetSizeMB AS TargetSizeMB,
        CASE 
            WHEN @TargetSizeMB < @UsedMB THEN 'Cannot shrink below used space!'
            ELSE 'Shrink is possible'
        END AS Feasibility;
    
    IF @WhatIf = 1
    BEGIN
        SELECT 'WhatIf mode - no action taken. Set @WhatIf = 0 to execute.' AS Status;
        RETURN;
    END
    
    IF @TruncateOnly = 1
    BEGIN
        SET @SQL = 'USE ' + QUOTENAME(@DatabaseName) + '; DBCC SHRINKFILE(' + QUOTENAME(@FileName, '''') + ', TRUNCATEONLY)';
    END
    ELSE
    BEGIN
        SET @SQL = 'USE ' + QUOTENAME(@DatabaseName) + '; DBCC SHRINKFILE(' + QUOTENAME(@FileName, '''') + ', ' + CAST(@TargetSizeMB AS VARCHAR(10)) + ')';
    END
    
    EXEC sp_executesql @SQL;
    
    SELECT 'Shrink operation completed' AS Status;
END
GO

-- Move objects between filegroups
CREATE PROCEDURE dbo.MoveTableToFileGroup
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @TargetFileGroup NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @PKName NVARCHAR(128);
    DECLARE @PKColumns NVARCHAR(MAX);
    DECLARE @FullPath NVARCHAR(256) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    
    -- Get primary key info
    SELECT @PKName = i.name,
           @PKColumns = STRING_AGG(QUOTENAME(c.name) + CASE WHEN ic.is_descending_key = 1 THEN ' DESC' ELSE ' ASC' END, ', ')
                        WITHIN GROUP (ORDER BY ic.key_ordinal)
    FROM sys.indexes i
    INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
    INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
    WHERE i.object_id = OBJECT_ID(@FullPath)
      AND i.is_primary_key = 1
    GROUP BY i.name;
    
    IF @PKName IS NULL
    BEGIN
        RAISERROR('Table must have a primary key to move filegroups using this method', 16, 1);
        RETURN;
    END
    
    -- Rebuild clustered index on new filegroup
    SET @SQL = N'
        ALTER TABLE ' + @FullPath + '
        DROP CONSTRAINT ' + QUOTENAME(@PKName) + ';
        
        ALTER TABLE ' + @FullPath + '
        ADD CONSTRAINT ' + QUOTENAME(@PKName) + ' PRIMARY KEY CLUSTERED (' + @PKColumns + ')
        ON ' + QUOTENAME(@TargetFileGroup);
    
    EXEC sp_executesql @SQL;
    
    SELECT 'Table moved to filegroup' AS Status, @TableName AS TableName, @TargetFileGroup AS NewFileGroup;
END
GO
