-- Sample 033: Encryption and Data Protection
-- Source: Microsoft Learn, MSSQLTips, SQLShack
-- Category: Security
-- Complexity: Advanced
-- Features: Symmetric keys, certificates, ENCRYPTBYKEY, DECRYPTBYKEY, hashing

-- Setup encryption infrastructure
CREATE PROCEDURE dbo.SetupEncryptionInfrastructure
    @MasterKeyPassword NVARCHAR(128),
    @CertificateName NVARCHAR(128) = 'DataEncryptionCert',
    @SymmetricKeyName NVARCHAR(128) = 'DataEncryptionKey'
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    
    BEGIN TRY
        -- Create database master key if not exists
        IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
        BEGIN
            SET @SQL = 'CREATE MASTER KEY ENCRYPTION BY PASSWORD = ''' + 
                       REPLACE(@MasterKeyPassword, '''', '''''') + '''';
            EXEC sp_executesql @SQL;
            PRINT 'Database master key created';
        END
        ELSE
            PRINT 'Database master key already exists';
        
        -- Create certificate if not exists
        IF NOT EXISTS (SELECT 1 FROM sys.certificates WHERE name = @CertificateName)
        BEGIN
            SET @SQL = 'CREATE CERTIFICATE ' + QUOTENAME(@CertificateName) + '
                WITH SUBJECT = ''Data Encryption Certificate'',
                EXPIRY_DATE = ''2099-12-31''';
            EXEC sp_executesql @SQL;
            PRINT 'Certificate created: ' + @CertificateName;
        END
        ELSE
            PRINT 'Certificate already exists: ' + @CertificateName;
        
        -- Create symmetric key if not exists
        IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = @SymmetricKeyName)
        BEGIN
            SET @SQL = 'CREATE SYMMETRIC KEY ' + QUOTENAME(@SymmetricKeyName) + '
                WITH ALGORITHM = AES_256
                ENCRYPTION BY CERTIFICATE ' + QUOTENAME(@CertificateName);
            EXEC sp_executesql @SQL;
            PRINT 'Symmetric key created: ' + @SymmetricKeyName;
        END
        ELSE
            PRINT 'Symmetric key already exists: ' + @SymmetricKeyName;
        
        -- Return status
        SELECT 
            'Encryption infrastructure ready' AS Status,
            @CertificateName AS Certificate,
            @SymmetricKeyName AS SymmetricKey;
            
    END TRY
    BEGIN CATCH
        SELECT 
            'Setup failed' AS Status,
            ERROR_MESSAGE() AS ErrorMessage;
        THROW;
    END CATCH
END
GO

-- Encrypt sensitive data
CREATE PROCEDURE dbo.EncryptValue
    @PlainText NVARCHAR(MAX),
    @SymmetricKeyName NVARCHAR(128) = 'DataEncryptionKey',
    @EncryptedValue VARBINARY(MAX) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @KeyGuid UNIQUEIDENTIFIER;
    
    -- Get key GUID
    SELECT @KeyGuid = key_guid 
    FROM sys.symmetric_keys 
    WHERE name = @SymmetricKeyName;
    
    IF @KeyGuid IS NULL
    BEGIN
        RAISERROR('Symmetric key not found: %s', 16, 1, @SymmetricKeyName);
        RETURN;
    END
    
    -- Open the key
    SET @SQL = 'OPEN SYMMETRIC KEY ' + QUOTENAME(@SymmetricKeyName) + 
               ' DECRYPTION BY CERTIFICATE DataEncryptionCert';
    EXEC sp_executesql @SQL;
    
    -- Encrypt
    SELECT @EncryptedValue = ENCRYPTBYKEY(@KeyGuid, @PlainText);
    
    -- Close the key
    SET @SQL = 'CLOSE SYMMETRIC KEY ' + QUOTENAME(@SymmetricKeyName);
    EXEC sp_executesql @SQL;
END
GO

-- Decrypt sensitive data
CREATE PROCEDURE dbo.DecryptValue
    @EncryptedValue VARBINARY(MAX),
    @SymmetricKeyName NVARCHAR(128) = 'DataEncryptionKey',
    @DecryptedValue NVARCHAR(MAX) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    
    -- Open the key
    SET @SQL = 'OPEN SYMMETRIC KEY ' + QUOTENAME(@SymmetricKeyName) + 
               ' DECRYPTION BY CERTIFICATE DataEncryptionCert';
    EXEC sp_executesql @SQL;
    
    -- Decrypt
    SELECT @DecryptedValue = CAST(DECRYPTBYKEY(@EncryptedValue) AS NVARCHAR(MAX));
    
    -- Close the key
    SET @SQL = 'CLOSE SYMMETRIC KEY ' + QUOTENAME(@SymmetricKeyName);
    EXEC sp_executesql @SQL;
END
GO

-- Hash a value (one-way, for passwords etc.)
CREATE FUNCTION dbo.HashValue
(
    @PlainText NVARCHAR(MAX),
    @Algorithm NVARCHAR(20) = 'SHA2_256',  -- MD5, SHA1, SHA2_256, SHA2_512
    @Salt NVARCHAR(100) = NULL
)
RETURNS VARBINARY(64)
AS
BEGIN
    DECLARE @ValueToHash NVARCHAR(MAX);
    
    SET @ValueToHash = ISNULL(@Salt, '') + @PlainText;
    
    RETURN HASHBYTES(@Algorithm, @ValueToHash);
END
GO

-- Create or verify password hash
CREATE PROCEDURE dbo.ManagePasswordHash
    @Action NVARCHAR(20),  -- HASH, VERIFY
    @Password NVARCHAR(128),
    @StoredHash VARBINARY(64) = NULL,  -- For VERIFY
    @NewHash VARBINARY(64) = NULL OUTPUT,
    @Salt NVARCHAR(100) = NULL OUTPUT,
    @IsValid BIT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    IF @Action = 'HASH'
    BEGIN
        -- Generate salt
        SET @Salt = CAST(NEWID() AS NVARCHAR(36)) + CAST(NEWID() AS NVARCHAR(36));
        SET @Salt = LEFT(@Salt, 32);
        
        -- Generate hash
        SET @NewHash = HASHBYTES('SHA2_512', @Salt + @Password);
        
        SELECT 
            @NewHash AS PasswordHash,
            @Salt AS Salt,
            'Store both hash and salt securely' AS Instructions;
    END
    ELSE IF @Action = 'VERIFY'
    BEGIN
        DECLARE @ComputedHash VARBINARY(64);
        
        IF @Salt IS NULL OR @StoredHash IS NULL
        BEGIN
            SET @IsValid = 0;
            SELECT 'Salt and StoredHash are required for verification' AS Message;
            RETURN;
        END
        
        SET @ComputedHash = HASHBYTES('SHA2_512', @Salt + @Password);
        
        SET @IsValid = CASE WHEN @ComputedHash = @StoredHash THEN 1 ELSE 0 END;
        
        SELECT 
            @IsValid AS IsValid,
            CASE @IsValid WHEN 1 THEN 'Password verified' ELSE 'Password mismatch' END AS Message;
    END
END
GO

-- Encrypt column data in bulk
CREATE PROCEDURE dbo.EncryptColumnData
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @SourceColumn NVARCHAR(128),
    @TargetColumn NVARCHAR(128),
    @SymmetricKeyName NVARCHAR(128) = 'DataEncryptionKey',
    @CertificateName NVARCHAR(128) = 'DataEncryptionCert',
    @BatchSize INT = 1000
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @KeyGuid UNIQUEIDENTIFIER;
    DECLARE @RowsUpdated INT = 0;
    DECLARE @TotalUpdated INT = 0;
    
    -- Get key GUID
    SELECT @KeyGuid = key_guid 
    FROM sys.symmetric_keys 
    WHERE name = @SymmetricKeyName;
    
    -- Open the key
    SET @SQL = 'OPEN SYMMETRIC KEY ' + QUOTENAME(@SymmetricKeyName) + 
               ' DECRYPTION BY CERTIFICATE ' + QUOTENAME(@CertificateName);
    EXEC sp_executesql @SQL;
    
    -- Update in batches
    SET @RowsUpdated = 1;
    WHILE @RowsUpdated > 0
    BEGIN
        SET @SQL = '
            UPDATE TOP (@BatchSize) ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + '
            SET ' + QUOTENAME(@TargetColumn) + ' = ENCRYPTBYKEY(@KeyGuid, CAST(' + QUOTENAME(@SourceColumn) + ' AS NVARCHAR(MAX)))
            WHERE ' + QUOTENAME(@TargetColumn) + ' IS NULL
              AND ' + QUOTENAME(@SourceColumn) + ' IS NOT NULL';
        
        EXEC sp_executesql @SQL,
            N'@BatchSize INT, @KeyGuid UNIQUEIDENTIFIER',
            @BatchSize = @BatchSize,
            @KeyGuid = @KeyGuid;
        
        SET @RowsUpdated = @@ROWCOUNT;
        SET @TotalUpdated = @TotalUpdated + @RowsUpdated;
        
        IF @RowsUpdated > 0
            WAITFOR DELAY '00:00:00.100';
    END
    
    -- Close the key
    SET @SQL = 'CLOSE SYMMETRIC KEY ' + QUOTENAME(@SymmetricKeyName);
    EXEC sp_executesql @SQL;
    
    SELECT @TotalUpdated AS RowsEncrypted;
END
GO

-- Audit encryption keys and certificates
CREATE PROCEDURE dbo.AuditEncryptionObjects
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Master keys
    SELECT 
        'Master Key' AS ObjectType,
        name AS ObjectName,
        create_date AS CreateDate,
        modify_date AS ModifyDate,
        key_length AS KeyLength,
        algorithm_desc AS Algorithm,
        CASE is_master_key_encrypted_by_server 
            WHEN 1 THEN 'Yes' ELSE 'No' 
        END AS EncryptedByServer
    FROM sys.symmetric_keys
    WHERE name = '##MS_DatabaseMasterKey##';
    
    -- Certificates
    SELECT 
        'Certificate' AS ObjectType,
        name AS ObjectName,
        subject AS Subject,
        start_date AS ValidFrom,
        expiry_date AS ValidTo,
        CASE 
            WHEN expiry_date < GETDATE() THEN 'EXPIRED'
            WHEN expiry_date < DATEADD(MONTH, 3, GETDATE()) THEN 'EXPIRING SOON'
            ELSE 'Valid'
        END AS Status,
        pvt_key_encryption_type_desc AS PrivateKeyEncryption
    FROM sys.certificates;
    
    -- Symmetric keys
    SELECT 
        'Symmetric Key' AS ObjectType,
        sk.name AS ObjectName,
        sk.algorithm_desc AS Algorithm,
        sk.key_length AS KeyLength,
        sk.create_date AS CreateDate,
        c.name AS EncryptedByCertificate
    FROM sys.symmetric_keys sk
    LEFT JOIN sys.key_encryptions ke ON sk.symmetric_key_id = ke.key_id
    LEFT JOIN sys.certificates c ON ke.thumbprint = c.thumbprint
    WHERE sk.name <> '##MS_DatabaseMasterKey##';
    
    -- Asymmetric keys
    SELECT 
        'Asymmetric Key' AS ObjectType,
        name AS ObjectName,
        algorithm_desc AS Algorithm,
        key_length AS KeyLength,
        pvt_key_encryption_type_desc AS PrivateKeyEncryption
    FROM sys.asymmetric_keys;
END
GO
