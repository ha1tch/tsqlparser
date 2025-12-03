-- Sample 022: Database Backup and Restore Procedures
-- Source: Ola Hallengren, MSSQLTips, Microsoft Learn
-- Category: Performance
-- Complexity: Advanced
-- Features: BACKUP DATABASE, RESTORE, WITH COMPRESSION, CHECKSUM, dynamic paths

-- Perform database backup with options
CREATE PROCEDURE dbo.BackupDatabase
    @DatabaseName NVARCHAR(128),
    @BackupType NVARCHAR(10) = 'FULL',  -- FULL, DIFF, LOG
    @BackupPath NVARCHAR(500) = NULL,
    @UseCompression BIT = 1,
    @UseChecksum BIT = 1,
    @CopyOnly BIT = 0,
    @Description NVARCHAR(500) = NULL,
    @RetentionDays INT = 7
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @BackupFile NVARCHAR(500);
    DECLARE @BackupName NVARCHAR(256);
    DECLARE @StartTime DATETIME = GETDATE();
    DECLARE @FileExtension NVARCHAR(10);
    DECLARE @BackupTypeDesc NVARCHAR(20);
    
    -- Default backup path
    SET @BackupPath = ISNULL(@BackupPath, 
        (SELECT CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(500))));
    
    -- Ensure trailing backslash
    IF RIGHT(@BackupPath, 1) <> '\'
        SET @BackupPath = @BackupPath + '\';
    
    -- Set file extension and type description
    SELECT @FileExtension = CASE @BackupType
            WHEN 'FULL' THEN '.bak'
            WHEN 'DIFF' THEN '_diff.bak'
            WHEN 'LOG' THEN '.trn'
            ELSE '.bak'
        END,
        @BackupTypeDesc = CASE @BackupType
            WHEN 'FULL' THEN 'Full'
            WHEN 'DIFF' THEN 'Differential'
            WHEN 'LOG' THEN 'Transaction Log'
            ELSE 'Full'
        END;
    
    -- Build backup filename with timestamp
    SET @BackupFile = @BackupPath + @DatabaseName + '_' + 
                      @BackupTypeDesc + '_' +
                      FORMAT(GETDATE(), 'yyyyMMdd_HHmmss') + 
                      @FileExtension;
    
    SET @BackupName = @DatabaseName + ' - ' + @BackupTypeDesc + ' Backup - ' + 
                      CONVERT(NVARCHAR(20), GETDATE(), 120);
    
    -- Build backup command
    IF @BackupType = 'LOG'
    BEGIN
        SET @SQL = 'BACKUP LOG ' + QUOTENAME(@DatabaseName) + '
            TO DISK = @BackupFile
            WITH NAME = @BackupName';
    END
    ELSE IF @BackupType = 'DIFF'
    BEGIN
        SET @SQL = 'BACKUP DATABASE ' + QUOTENAME(@DatabaseName) + '
            TO DISK = @BackupFile
            WITH DIFFERENTIAL, NAME = @BackupName';
    END
    ELSE
    BEGIN
        SET @SQL = 'BACKUP DATABASE ' + QUOTENAME(@DatabaseName) + '
            TO DISK = @BackupFile
            WITH NAME = @BackupName';
    END
    
    -- Add options
    IF @UseCompression = 1
        SET @SQL = @SQL + ', COMPRESSION';
    
    IF @UseChecksum = 1
        SET @SQL = @SQL + ', CHECKSUM';
    
    IF @CopyOnly = 1
        SET @SQL = @SQL + ', COPY_ONLY';
    
    IF @Description IS NOT NULL
        SET @SQL = @SQL + ', DESCRIPTION = @Description';
    
    SET @SQL = @SQL + ', STATS = 10';
    
    BEGIN TRY
        -- Execute backup
        EXEC sp_executesql @SQL,
            N'@BackupFile NVARCHAR(500), @BackupName NVARCHAR(256), @Description NVARCHAR(500)',
            @BackupFile = @BackupFile,
            @BackupName = @BackupName,
            @Description = @Description;
        
        -- Log backup details
        SELECT 
            @DatabaseName AS DatabaseName,
            @BackupTypeDesc AS BackupType,
            @BackupFile AS BackupFile,
            @StartTime AS StartTime,
            GETDATE() AS EndTime,
            DATEDIFF(SECOND, @StartTime, GETDATE()) AS DurationSeconds,
            'Success' AS Status;
            
    END TRY
    BEGIN CATCH
        SELECT 
            @DatabaseName AS DatabaseName,
            @BackupTypeDesc AS BackupType,
            @BackupFile AS BackupFile,
            @StartTime AS StartTime,
            GETDATE() AS EndTime,
            DATEDIFF(SECOND, @StartTime, GETDATE()) AS DurationSeconds,
            'Failed' AS Status,
            ERROR_MESSAGE() AS ErrorMessage;
            
        THROW;
    END CATCH
END
GO

-- Get backup history
CREATE PROCEDURE dbo.GetBackupHistory
    @DatabaseName NVARCHAR(128) = NULL,
    @BackupType NVARCHAR(10) = NULL,  -- D = Full, I = Diff, L = Log
    @StartDate DATETIME = NULL,
    @EndDate DATETIME = NULL,
    @TopN INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    
    SET @StartDate = ISNULL(@StartDate, DATEADD(DAY, -30, GETDATE()));
    SET @EndDate = ISNULL(@EndDate, GETDATE());
    
    SELECT TOP (@TopN)
        bs.database_name AS DatabaseName,
        CASE bs.type
            WHEN 'D' THEN 'Full'
            WHEN 'I' THEN 'Differential'
            WHEN 'L' THEN 'Log'
            WHEN 'F' THEN 'File/Filegroup'
            WHEN 'G' THEN 'Diff File'
            WHEN 'P' THEN 'Partial'
            WHEN 'Q' THEN 'Diff Partial'
            ELSE bs.type
        END AS BackupType,
        bs.backup_start_date AS StartTime,
        bs.backup_finish_date AS EndTime,
        DATEDIFF(SECOND, bs.backup_start_date, bs.backup_finish_date) AS DurationSeconds,
        CAST(bs.backup_size / 1024.0 / 1024.0 AS DECIMAL(18,2)) AS BackupSizeMB,
        CAST(bs.compressed_backup_size / 1024.0 / 1024.0 AS DECIMAL(18,2)) AS CompressedSizeMB,
        CASE 
            WHEN bs.backup_size > 0 
            THEN CAST(100.0 - (bs.compressed_backup_size * 100.0 / bs.backup_size) AS DECIMAL(5,2))
            ELSE 0 
        END AS CompressionRatio,
        bmf.physical_device_name AS BackupFile,
        bs.name AS BackupName,
        bs.description AS Description,
        bs.user_name AS UserName,
        bs.server_name AS ServerName,
        bs.recovery_model AS RecoveryModel,
        bs.has_backup_checksums AS HasChecksum,
        bs.is_copy_only AS IsCopyOnly,
        bs.first_lsn AS FirstLSN,
        bs.last_lsn AS LastLSN
    FROM msdb.dbo.backupset bs
    INNER JOIN msdb.dbo.backupmediafamily bmf 
        ON bs.media_set_id = bmf.media_set_id
    WHERE (@DatabaseName IS NULL OR bs.database_name = @DatabaseName)
      AND (@BackupType IS NULL OR bs.type = @BackupType)
      AND bs.backup_start_date BETWEEN @StartDate AND @EndDate
    ORDER BY bs.backup_start_date DESC;
END
GO

-- Restore database with options
CREATE PROCEDURE dbo.RestoreDatabase
    @DatabaseName NVARCHAR(128),
    @BackupFile NVARCHAR(500),
    @NewDatabaseName NVARCHAR(128) = NULL,
    @DataFilePath NVARCHAR(500) = NULL,
    @LogFilePath NVARCHAR(500) = NULL,
    @WithRecovery BIT = 1,
    @WithReplace BIT = 0,
    @StandbyFile NVARCHAR(500) = NULL,
    @StopAt DATETIME = NULL,
    @GenerateScriptOnly BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FileListSQL NVARCHAR(MAX);
    DECLARE @MoveClause NVARCHAR(MAX) = '';
    
    -- Get file list from backup
    DECLARE @FileList TABLE (
        LogicalName NVARCHAR(128),
        PhysicalName NVARCHAR(260),
        Type CHAR(1),
        FileGroupName NVARCHAR(128),
        Size NUMERIC(20,0),
        MaxSize NUMERIC(20,0),
        FileID BIGINT,
        CreateLSN NUMERIC(25,0),
        DropLSN NUMERIC(25,0),
        UniqueID UNIQUEIDENTIFIER,
        ReadOnlyLSN NUMERIC(25,0),
        ReadWriteLSN NUMERIC(25,0),
        BackupSizeInBytes BIGINT,
        SourceBlockSize INT,
        FileGroupID INT,
        LogGroupGUID UNIQUEIDENTIFIER,
        DifferentialBaseLSN NUMERIC(25,0),
        DifferentialBaseGUID UNIQUEIDENTIFIER,
        IsReadOnly BIT,
        IsPresent BIT,
        TDEThumbprint VARBINARY(32),
        SnapshotURL NVARCHAR(360)
    );
    
    INSERT INTO @FileList
    EXEC('RESTORE FILELISTONLY FROM DISK = ''' + @BackupFile + '''');
    
    SET @NewDatabaseName = ISNULL(@NewDatabaseName, @DatabaseName);
    
    -- Build MOVE clauses if paths specified or restoring to different name
    IF @DataFilePath IS NOT NULL OR @LogFilePath IS NOT NULL OR @NewDatabaseName <> @DatabaseName
    BEGIN
        SELECT @MoveClause = @MoveClause + 
            ', MOVE ''' + LogicalName + ''' TO ''' +
            CASE Type
                WHEN 'D' THEN ISNULL(@DataFilePath, 
                    (SELECT CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS NVARCHAR(500))))
                WHEN 'L' THEN ISNULL(@LogFilePath,
                    (SELECT CAST(SERVERPROPERTY('InstanceDefaultLogPath') AS NVARCHAR(500))))
            END +
            @NewDatabaseName + 
            CASE Type 
                WHEN 'D' THEN '.mdf'
                WHEN 'L' THEN '_log.ldf'
            END + ''''
        FROM @FileList;
    END
    
    -- Build restore command
    SET @SQL = 'RESTORE DATABASE ' + QUOTENAME(@NewDatabaseName) + '
        FROM DISK = ''' + @BackupFile + '''
        WITH ';
    
    IF @WithRecovery = 1
        SET @SQL = @SQL + 'RECOVERY';
    ELSE IF @StandbyFile IS NOT NULL
        SET @SQL = @SQL + 'STANDBY = ''' + @StandbyFile + '''';
    ELSE
        SET @SQL = @SQL + 'NORECOVERY';
    
    IF @WithReplace = 1
        SET @SQL = @SQL + ', REPLACE';
    
    IF @StopAt IS NOT NULL
        SET @SQL = @SQL + ', STOPAT = ''' + CONVERT(NVARCHAR(30), @StopAt, 121) + '''';
    
    SET @SQL = @SQL + @MoveClause + ', STATS = 10';
    
    IF @GenerateScriptOnly = 1
    BEGIN
        -- Just return the script
        SELECT @SQL AS RestoreScript;
        SELECT * FROM @FileList;
    END
    ELSE
    BEGIN
        -- Execute restore
        BEGIN TRY
            EXEC sp_executesql @SQL;
            
            SELECT 
                @NewDatabaseName AS DatabaseName,
                @BackupFile AS BackupFile,
                'Restored successfully' AS Status;
        END TRY
        BEGIN CATCH
            SELECT 
                @NewDatabaseName AS DatabaseName,
                @BackupFile AS BackupFile,
                'Failed' AS Status,
                ERROR_MESSAGE() AS ErrorMessage;
            
            THROW;
        END CATCH
    END
END
GO

-- Verify backup integrity
CREATE PROCEDURE dbo.VerifyBackup
    @BackupFile NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @StartTime DATETIME = GETDATE();
    
    BEGIN TRY
        -- Verify backup
        SET @SQL = 'RESTORE VERIFYONLY FROM DISK = ''' + @BackupFile + ''' WITH CHECKSUM';
        EXEC sp_executesql @SQL;
        
        -- Get backup header info
        DECLARE @HeaderInfo TABLE (
            BackupName NVARCHAR(128),
            BackupDescription NVARCHAR(255),
            BackupType SMALLINT,
            ExpirationDate DATETIME,
            Compressed BIT,
            Position SMALLINT,
            DeviceType TINYINT,
            UserName NVARCHAR(128),
            ServerName NVARCHAR(128),
            DatabaseName NVARCHAR(128),
            DatabaseVersion INT,
            DatabaseCreationDate DATETIME,
            BackupSize NUMERIC(20,0),
            FirstLSN NUMERIC(25,0),
            LastLSN NUMERIC(25,0),
            CheckpointLSN NUMERIC(25,0),
            DatabaseBackupLSN NUMERIC(25,0),
            BackupStartDate DATETIME,
            BackupFinishDate DATETIME,
            SortOrder SMALLINT,
            CodePage SMALLINT,
            UnicodeLocaleId INT,
            UnicodeComparisonStyle INT,
            CompatibilityLevel TINYINT,
            SoftwareVendorId INT,
            SoftwareVersionMajor INT,
            SoftwareVersionMinor INT,
            SoftwareVersionBuild INT,
            MachineName NVARCHAR(128),
            Flags INT,
            BindingID UNIQUEIDENTIFIER,
            RecoveryForkID UNIQUEIDENTIFIER,
            Collation NVARCHAR(128),
            FamilyGUID UNIQUEIDENTIFIER,
            HasBulkLoggedData BIT,
            IsSnapshot BIT,
            IsReadOnly BIT,
            IsSingleUser BIT,
            HasBackupChecksums BIT,
            IsDamaged BIT,
            BeginsLogChain BIT,
            HasIncompleteMetaData BIT,
            IsForceOffline BIT,
            IsCopyOnly BIT,
            FirstRecoveryForkID UNIQUEIDENTIFIER,
            ForkPointLSN NUMERIC(25,0),
            RecoveryModel NVARCHAR(60),
            DifferentialBaseLSN NUMERIC(25,0),
            DifferentialBaseGUID UNIQUEIDENTIFIER,
            BackupTypeDescription NVARCHAR(60),
            BackupSetGUID UNIQUEIDENTIFIER,
            CompressedBackupSize NUMERIC(20,0),
            Containment TINYINT,
            KeyAlgorithm NVARCHAR(32),
            EncryptorThumbprint VARBINARY(20),
            EncryptorType NVARCHAR(32)
        );
        
        INSERT INTO @HeaderInfo
        EXEC('RESTORE HEADERONLY FROM DISK = ''' + @BackupFile + '''');
        
        SELECT 
            'VALID' AS VerifyStatus,
            @BackupFile AS BackupFile,
            BackupName,
            DatabaseName,
            BackupTypeDescription AS BackupType,
            BackupStartDate,
            BackupFinishDate,
            CAST(BackupSize / 1024.0 / 1024.0 AS DECIMAL(18,2)) AS BackupSizeMB,
            CAST(CompressedBackupSize / 1024.0 / 1024.0 AS DECIMAL(18,2)) AS CompressedSizeMB,
            HasBackupChecksums,
            RecoveryModel,
            DATEDIFF(SECOND, @StartTime, GETDATE()) AS VerifyDurationSeconds
        FROM @HeaderInfo;
        
    END TRY
    BEGIN CATCH
        SELECT 
            'INVALID' AS VerifyStatus,
            @BackupFile AS BackupFile,
            ERROR_MESSAGE() AS ErrorMessage,
            DATEDIFF(SECOND, @StartTime, GETDATE()) AS VerifyDurationSeconds;
    END CATCH
END
GO
