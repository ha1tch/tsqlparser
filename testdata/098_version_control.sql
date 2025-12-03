-- Sample 098: Database Version Control and Migration
-- Source: Various - Flyway/Liquibase patterns, DbUp patterns, Migration best practices
-- Category: Deployment
-- Complexity: Advanced
-- Features: Schema versioning, migration scripts, rollback support, deployment tracking

-- Setup migration infrastructure
CREATE PROCEDURE dbo.SetupMigrationInfrastructure
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Migration history table
    IF OBJECT_ID('dbo.MigrationHistory', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.MigrationHistory (
            MigrationID INT IDENTITY(1,1) PRIMARY KEY,
            Version NVARCHAR(50) NOT NULL,
            ScriptName NVARCHAR(256) NOT NULL,
            Description NVARCHAR(500),
            Checksum NVARCHAR(64),
            AppliedOn DATETIME2 DEFAULT SYSDATETIME(),
            AppliedBy NVARCHAR(128) DEFAULT SUSER_SNAME(),
            ExecutionTimeMs INT,
            Status NVARCHAR(20) DEFAULT 'Success',
            RollbackScript NVARCHAR(MAX),
            CONSTRAINT UQ_MigrationHistory_Version UNIQUE (Version)
        );
        
        CREATE INDEX IX_MigrationHistory_AppliedOn ON dbo.MigrationHistory (AppliedOn);
    END
    
    -- Schema snapshots for comparison
    IF OBJECT_ID('dbo.SchemaSnapshots', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.SchemaSnapshots (
            SnapshotID INT IDENTITY(1,1) PRIMARY KEY,
            SnapshotName NVARCHAR(100),
            Version NVARCHAR(50),
            CreatedOn DATETIME2 DEFAULT SYSDATETIME(),
            SchemaDefinition NVARCHAR(MAX),  -- JSON representation
            ObjectCount INT
        );
    END
    
    SELECT 'Migration infrastructure created' AS Status;
END
GO

-- Get current database version
CREATE PROCEDURE dbo.GetDatabaseVersion
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT TOP 1
        Version AS CurrentVersion,
        ScriptName AS LastMigration,
        AppliedOn AS LastAppliedOn,
        AppliedBy
    FROM dbo.MigrationHistory
    WHERE Status = 'Success'
    ORDER BY AppliedOn DESC;
    
    -- Migration summary
    SELECT 
        COUNT(*) AS TotalMigrations,
        MIN(AppliedOn) AS FirstMigration,
        MAX(AppliedOn) AS LastMigration,
        SUM(CASE WHEN Status = 'Success' THEN 1 ELSE 0 END) AS Successful,
        SUM(CASE WHEN Status = 'Failed' THEN 1 ELSE 0 END) AS Failed
    FROM dbo.MigrationHistory;
END
GO

-- Apply migration script
CREATE PROCEDURE dbo.ApplyMigration
    @Version NVARCHAR(50),
    @ScriptName NVARCHAR(256),
    @Description NVARCHAR(500),
    @MigrationScript NVARCHAR(MAX),
    @RollbackScript NVARCHAR(MAX) = NULL,
    @Force BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @StartTime DATETIME2 = SYSDATETIME();
    DECLARE @Checksum NVARCHAR(64);
    DECLARE @MigrationID INT;
    DECLARE @Status NVARCHAR(20) = 'Success';
    DECLARE @ErrorMessage NVARCHAR(MAX);
    
    -- Calculate checksum
    SET @Checksum = CONVERT(NVARCHAR(64), HASHBYTES('SHA2_256', @MigrationScript), 2);
    
    -- Check if already applied
    IF EXISTS (SELECT 1 FROM dbo.MigrationHistory WHERE Version = @Version)
    BEGIN
        IF @Force = 0
        BEGIN
            SELECT 'Migration already applied' AS Status, @Version AS Version;
            RETURN;
        END
        ELSE
        BEGIN
            -- Remove existing record for re-run
            DELETE FROM dbo.MigrationHistory WHERE Version = @Version;
        END
    END
    
    -- Check version order
    DECLARE @LastVersion NVARCHAR(50);
    SELECT TOP 1 @LastVersion = Version FROM dbo.MigrationHistory WHERE Status = 'Success' ORDER BY AppliedOn DESC;
    
    IF @LastVersion IS NOT NULL AND @Version < @LastVersion AND @Force = 0
    BEGIN
        RAISERROR('Version %s is older than current version %s. Use @Force=1 to override.', 16, 1, @Version, @LastVersion);
        RETURN;
    END
    
    -- Begin migration
    BEGIN TRY
        BEGIN TRANSACTION;
        
        -- Execute migration script
        EXEC sp_executesql @MigrationScript;
        
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        
        SET @Status = 'Failed';
        SET @ErrorMessage = ERROR_MESSAGE();
    END CATCH
    
    -- Record migration
    INSERT INTO dbo.MigrationHistory (Version, ScriptName, Description, Checksum, ExecutionTimeMs, Status, RollbackScript)
    VALUES (
        @Version, 
        @ScriptName, 
        @Description, 
        @Checksum,
        DATEDIFF(MILLISECOND, @StartTime, SYSDATETIME()),
        @Status,
        @RollbackScript
    );
    
    SET @MigrationID = SCOPE_IDENTITY();
    
    IF @Status = 'Failed'
    BEGIN
        RAISERROR('Migration failed: %s', 16, 1, @ErrorMessage);
        RETURN;
    END
    
    SELECT 
        @MigrationID AS MigrationID,
        @Version AS Version,
        @Status AS Status,
        DATEDIFF(MILLISECOND, @StartTime, SYSDATETIME()) AS ExecutionTimeMs;
END
GO

-- Rollback migration
CREATE PROCEDURE dbo.RollbackMigration
    @Version NVARCHAR(50),
    @Force BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @RollbackScript NVARCHAR(MAX);
    DECLARE @ScriptName NVARCHAR(256);
    
    -- Get rollback script
    SELECT @RollbackScript = RollbackScript, @ScriptName = ScriptName
    FROM dbo.MigrationHistory
    WHERE Version = @Version AND Status = 'Success';
    
    IF @RollbackScript IS NULL
    BEGIN
        IF @Force = 0
        BEGIN
            RAISERROR('No rollback script available for version %s', 16, 1, @Version);
            RETURN;
        END
        ELSE
        BEGIN
            SELECT 'No rollback script; marked as rolled back' AS Status;
            UPDATE dbo.MigrationHistory SET Status = 'RolledBack' WHERE Version = @Version;
            RETURN;
        END
    END
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        EXEC sp_executesql @RollbackScript;
        
        UPDATE dbo.MigrationHistory SET Status = 'RolledBack' WHERE Version = @Version;
        
        COMMIT TRANSACTION;
        
        SELECT 'Rollback successful' AS Status, @Version AS Version;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        RAISERROR('Rollback failed: %s', 16, 1, ERROR_MESSAGE());
    END CATCH
END
GO

-- Create schema snapshot
CREATE PROCEDURE dbo.CreateSchemaSnapshot
    @SnapshotName NVARCHAR(100),
    @Version NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SchemaJSON NVARCHAR(MAX);
    DECLARE @ObjectCount INT;
    
    -- Capture schema as JSON
    SELECT @SchemaJSON = (
        SELECT 
            'Tables' AS ObjectType,
            (
                SELECT 
                    s.name AS SchemaName,
                    t.name AS TableName,
                    (
                        SELECT 
                            c.name AS ColumnName,
                            TYPE_NAME(c.user_type_id) AS DataType,
                            c.max_length AS MaxLength,
                            c.is_nullable AS IsNullable,
                            c.is_identity AS IsIdentity
                        FROM sys.columns c
                        WHERE c.object_id = t.object_id
                        FOR JSON PATH
                    ) AS Columns
                FROM sys.tables t
                INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
                FOR JSON PATH
            ) AS Tables,
            (
                SELECT 
                    s.name AS SchemaName,
                    p.name AS ProcedureName,
                    m.definition AS Definition
                FROM sys.procedures p
                INNER JOIN sys.schemas s ON p.schema_id = s.schema_id
                INNER JOIN sys.sql_modules m ON p.object_id = m.object_id
                FOR JSON PATH
            ) AS Procedures
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );
    
    SELECT @ObjectCount = COUNT(*) 
    FROM sys.objects 
    WHERE type IN ('U', 'P', 'V', 'FN', 'IF', 'TF');
    
    INSERT INTO dbo.SchemaSnapshots (SnapshotName, Version, SchemaDefinition, ObjectCount)
    VALUES (@SnapshotName, @Version, @SchemaJSON, @ObjectCount);
    
    SELECT SCOPE_IDENTITY() AS SnapshotID, @SnapshotName AS SnapshotName, @ObjectCount AS ObjectCount;
END
GO

-- Compare schema versions
CREATE PROCEDURE dbo.CompareSchemaVersions
    @SnapshotID1 INT,
    @SnapshotID2 INT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @Schema1 NVARCHAR(MAX), @Schema2 NVARCHAR(MAX);
    DECLARE @Name1 NVARCHAR(100), @Name2 NVARCHAR(100);
    
    SELECT @Schema1 = SchemaDefinition, @Name1 = SnapshotName FROM dbo.SchemaSnapshots WHERE SnapshotID = @SnapshotID1;
    SELECT @Schema2 = SchemaDefinition, @Name2 = SnapshotName FROM dbo.SchemaSnapshots WHERE SnapshotID = @SnapshotID2;
    
    -- Compare tables
    SELECT 
        ISNULL(t1.TableName, t2.TableName) AS TableName,
        CASE 
            WHEN t1.TableName IS NULL THEN 'Added in ' + @Name2
            WHEN t2.TableName IS NULL THEN 'Removed in ' + @Name2
            ELSE 'Exists in both'
        END AS Status
    FROM OPENJSON(@Schema1, '$.Tables') WITH (TableName NVARCHAR(128) '$.TableName') t1
    FULL OUTER JOIN OPENJSON(@Schema2, '$.Tables') WITH (TableName NVARCHAR(128) '$.TableName') t2
        ON t1.TableName = t2.TableName
    WHERE t1.TableName IS NULL OR t2.TableName IS NULL;
END
GO

-- Get pending migrations
CREATE PROCEDURE dbo.GetPendingMigrations
    @MigrationsPath NVARCHAR(500) = NULL  -- For file-based migrations
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Return applied migrations for comparison
    SELECT 
        Version,
        ScriptName,
        AppliedOn,
        Status,
        Checksum
    FROM dbo.MigrationHistory
    ORDER BY Version;
END
GO
