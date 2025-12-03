-- Sample 075: Server Configuration Management
-- Source: Microsoft Learn, Glenn Berry, MSSQLTips
-- Category: Performance
-- Complexity: Complex
-- Features: sp_configure, server properties, configuration auditing

-- Get all server configurations with recommendations
CREATE PROCEDURE dbo.GetServerConfiguration
    @ShowAllOptions BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        c.name AS ConfigOption,
        c.value AS ConfiguredValue,
        c.value_in_use AS RunningValue,
        c.minimum AS MinValue,
        c.maximum AS MaxValue,
        c.is_dynamic AS IsDynamic,
        c.is_advanced AS IsAdvanced,
        c.description AS Description,
        CASE 
            WHEN c.name = 'max server memory (MB)' AND c.value_in_use = 2147483647 THEN
                'WARNING: Max memory not set - should be configured based on server memory'
            WHEN c.name = 'cost threshold for parallelism' AND c.value_in_use = 5 THEN
                'Consider increasing from default (5) to 25-50 for OLTP workloads'
            WHEN c.name = 'max degree of parallelism' AND c.value_in_use = 0 THEN
                'Consider setting MAXDOP based on CPU cores'
            WHEN c.name = 'optimize for ad hoc workloads' AND c.value_in_use = 0 THEN
                'Consider enabling for workloads with many single-use queries'
            WHEN c.name = 'remote admin connections' AND c.value_in_use = 0 THEN
                'Consider enabling DAC for emergency access'
            WHEN c.name = 'backup compression default' AND c.value_in_use = 0 THEN
                'Consider enabling for faster backups and less storage'
            ELSE 'OK'
        END AS Recommendation
    FROM sys.configurations c
    WHERE @ShowAllOptions = 1 
       OR c.name IN (
           'max server memory (MB)', 'min server memory (MB)', 
           'max degree of parallelism', 'cost threshold for parallelism',
           'optimize for ad hoc workloads', 'remote admin connections',
           'backup compression default', 'clr enabled', 'xp_cmdshell',
           'Database Mail XPs', 'Agent XPs', 'show advanced options'
       )
    ORDER BY c.name;
END
GO

-- Update server configuration
CREATE PROCEDURE dbo.UpdateServerConfiguration
    @ConfigOption NVARCHAR(128),
    @NewValue INT,
    @WhatIf BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @CurrentValue INT;
    DECLARE @IsAdvanced BIT;
    DECLARE @IsDynamic BIT;
    DECLARE @SQL NVARCHAR(MAX);
    
    -- Get current settings
    SELECT @CurrentValue = value_in_use, @IsAdvanced = is_advanced, @IsDynamic = is_dynamic
    FROM sys.configurations
    WHERE name = @ConfigOption;
    
    IF @CurrentValue IS NULL
    BEGIN
        RAISERROR('Configuration option not found: %s', 16, 1, @ConfigOption);
        RETURN;
    END
    
    -- Show what would happen
    SELECT 
        @ConfigOption AS ConfigOption,
        @CurrentValue AS CurrentValue,
        @NewValue AS NewValue,
        @IsAdvanced AS IsAdvanced,
        @IsDynamic AS IsDynamic,
        CASE WHEN @IsDynamic = 0 THEN 'Requires SQL Server restart to take effect' ELSE 'Takes effect immediately' END AS Note;
    
    IF @WhatIf = 1
    BEGIN
        SELECT 'WhatIf mode - no changes made. Set @WhatIf = 0 to apply.' AS Status;
        RETURN;
    END
    
    -- Log the change
    IF OBJECT_ID('dbo.ConfigurationChangeLog', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.ConfigurationChangeLog (
            LogID INT IDENTITY(1,1) PRIMARY KEY,
            ChangeTime DATETIME2 DEFAULT SYSDATETIME(),
            ConfigOption NVARCHAR(128),
            OldValue INT,
            NewValue INT,
            ChangedBy NVARCHAR(128) DEFAULT SUSER_SNAME()
        );
    END
    
    INSERT INTO dbo.ConfigurationChangeLog (ConfigOption, OldValue, NewValue)
    VALUES (@ConfigOption, @CurrentValue, @NewValue);
    
    -- Enable advanced options if needed
    IF @IsAdvanced = 1
    BEGIN
        EXEC sp_configure 'show advanced options', 1;
        RECONFIGURE;
    END
    
    -- Apply the change
    EXEC sp_configure @ConfigOption, @NewValue;
    RECONFIGURE;
    
    SELECT 'Configuration updated successfully' AS Status;
END
GO

-- Get server properties
CREATE PROCEDURE dbo.GetServerProperties
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        SERVERPROPERTY('ServerName') AS ServerName,
        SERVERPROPERTY('MachineName') AS MachineName,
        SERVERPROPERTY('InstanceName') AS InstanceName,
        SERVERPROPERTY('Edition') AS Edition,
        SERVERPROPERTY('ProductVersion') AS ProductVersion,
        SERVERPROPERTY('ProductLevel') AS ProductLevel,
        SERVERPROPERTY('ProductUpdateLevel') AS UpdateLevel,
        SERVERPROPERTY('EngineEdition') AS EngineEdition,
        SERVERPROPERTY('Collation') AS ServerCollation,
        SERVERPROPERTY('IsClustered') AS IsClustered,
        SERVERPROPERTY('IsHadrEnabled') AS IsHadrEnabled,
        SERVERPROPERTY('HadrManagerStatus') AS HadrManagerStatus,
        SERVERPROPERTY('IsFullTextInstalled') AS IsFullTextInstalled,
        SERVERPROPERTY('IsIntegratedSecurityOnly') AS IsWindowsAuthOnly,
        SERVERPROPERTY('IsSingleUser') AS IsSingleUser,
        SERVERPROPERTY('ProcessID') AS ProcessID,
        SERVERPROPERTY('ResourceLastUpdateDateTime') AS ResourceLastUpdate;
    
    -- CPU and memory info
    SELECT 
        cpu_count AS LogicalCPUs,
        hyperthread_ratio AS HyperthreadRatio,
        cpu_count / hyperthread_ratio AS PhysicalCPUs,
        physical_memory_kb / 1024 AS PhysicalMemoryMB,
        committed_kb / 1024 AS CommittedMemoryMB,
        committed_target_kb / 1024 AS TargetMemoryMB,
        virtual_machine_type_desc AS VMType,
        softnuma_configuration_desc AS SoftNUMAConfig,
        sql_memory_model_desc AS MemoryModel
    FROM sys.dm_os_sys_info;
END
GO

-- Export server configuration
CREATE PROCEDURE dbo.ExportServerConfiguration
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @Scripts TABLE (ScriptOrder INT, Category NVARCHAR(50), Script NVARCHAR(MAX));
    
    -- sp_configure settings
    INSERT INTO @Scripts
    SELECT 
        1 AS ScriptOrder,
        'sp_configure' AS Category,
        'EXEC sp_configure ''' + name + ''', ' + CAST(value_in_use AS VARCHAR(20)) + '; RECONFIGURE;' AS Script
    FROM sys.configurations
    WHERE value <> value_in_use OR value_in_use <> 0;
    
    -- Database settings
    INSERT INTO @Scripts
    SELECT 
        2,
        'Database Settings',
        'ALTER DATABASE ' + QUOTENAME(name) + ' SET RECOVERY ' + recovery_model_desc + ';'
    FROM sys.databases
    WHERE database_id > 4;
    
    INSERT INTO @Scripts
    SELECT 
        2,
        'Database Settings',
        'ALTER DATABASE ' + QUOTENAME(name) + ' SET COMPATIBILITY_LEVEL = ' + CAST(compatibility_level AS VARCHAR(10)) + ';'
    FROM sys.databases
    WHERE database_id > 4;
    
    -- Return scripts
    SELECT Category, Script 
    FROM @Scripts 
    ORDER BY ScriptOrder, Category, Script;
END
GO

-- Compare configuration to best practices
CREATE PROCEDURE dbo.CompareConfigToBestPractices
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @Results TABLE (
        Category NVARCHAR(50),
        CheckName NVARCHAR(200),
        CurrentValue NVARCHAR(100),
        RecommendedValue NVARCHAR(100),
        Status NVARCHAR(20),
        Priority NVARCHAR(20)
    );
    
    -- Max server memory
    INSERT INTO @Results
    SELECT 
        'Memory',
        'Max Server Memory',
        CAST(value_in_use AS NVARCHAR(100)),
        'Set to leave 4GB or 10% for OS',
        CASE WHEN value_in_use = 2147483647 THEN 'FAIL' ELSE 'PASS' END,
        'HIGH'
    FROM sys.configurations WHERE name = 'max server memory (MB)';
    
    -- Cost threshold for parallelism
    INSERT INTO @Results
    SELECT 
        'Parallelism',
        'Cost Threshold for Parallelism',
        CAST(value_in_use AS NVARCHAR(100)),
        '25-50 for OLTP',
        CASE WHEN value_in_use <= 5 THEN 'REVIEW' ELSE 'PASS' END,
        'MEDIUM'
    FROM sys.configurations WHERE name = 'cost threshold for parallelism';
    
    -- Max degree of parallelism
    INSERT INTO @Results
    SELECT 
        'Parallelism',
        'Max Degree of Parallelism',
        CAST(value_in_use AS NVARCHAR(100)),
        'Based on core count (usually 4-8)',
        CASE WHEN value_in_use = 0 THEN 'REVIEW' ELSE 'PASS' END,
        'MEDIUM'
    FROM sys.configurations WHERE name = 'max degree of parallelism';
    
    -- Optimize for ad hoc
    INSERT INTO @Results
    SELECT 
        'Memory',
        'Optimize for Ad Hoc Workloads',
        CAST(value_in_use AS NVARCHAR(100)),
        '1 (enabled)',
        CASE WHEN value_in_use = 0 THEN 'REVIEW' ELSE 'PASS' END,
        'LOW'
    FROM sys.configurations WHERE name = 'optimize for ad hoc workloads';
    
    -- Remote DAC
    INSERT INTO @Results
    SELECT 
        'Security',
        'Remote Admin Connections (DAC)',
        CAST(value_in_use AS NVARCHAR(100)),
        '1 (enabled)',
        CASE WHEN value_in_use = 0 THEN 'REVIEW' ELSE 'PASS' END,
        'LOW'
    FROM sys.configurations WHERE name = 'remote admin connections';
    
    -- Backup compression
    INSERT INTO @Results
    SELECT 
        'Backup',
        'Backup Compression Default',
        CAST(value_in_use AS NVARCHAR(100)),
        '1 (enabled)',
        CASE WHEN value_in_use = 0 THEN 'REVIEW' ELSE 'PASS' END,
        'LOW'
    FROM sys.configurations WHERE name = 'backup compression default';
    
    SELECT * FROM @Results ORDER BY 
        CASE Priority WHEN 'HIGH' THEN 1 WHEN 'MEDIUM' THEN 2 ELSE 3 END,
        Category, CheckName;
END
GO
