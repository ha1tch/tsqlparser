-- Sample 148: BACKUP and RESTORE Statements
-- Category: Missing Syntax Elements
-- Complexity: Advanced
-- Purpose: Parser testing - backup and restore syntax
-- Features: Full/Diff/Log backup, restore options, point-in-time recovery

-- Pattern 1: Basic full backup
BACKUP DATABASE MyDatabase TO DISK = 'C:\Backup\MyDatabase_Full.bak';
GO

-- Pattern 2: Full backup with options
BACKUP DATABASE MyDatabase 
TO DISK = 'C:\Backup\MyDatabase_Full.bak'
WITH 
    COMPRESSION,
    INIT,
    NAME = 'MyDatabase Full Backup',
    DESCRIPTION = 'Full database backup for MyDatabase',
    STATS = 10;
GO

-- Pattern 3: Backup to multiple files (striped)
BACKUP DATABASE MyDatabase 
TO 
    DISK = 'C:\Backup\MyDatabase_Full_1.bak',
    DISK = 'D:\Backup\MyDatabase_Full_2.bak',
    DISK = 'E:\Backup\MyDatabase_Full_3.bak'
WITH COMPRESSION, INIT;
GO

-- Pattern 4: Differential backup
BACKUP DATABASE MyDatabase 
TO DISK = 'C:\Backup\MyDatabase_Diff.bak'
WITH 
    DIFFERENTIAL,
    COMPRESSION,
    INIT,
    NAME = 'MyDatabase Differential Backup';
GO

-- Pattern 5: Transaction log backup
BACKUP LOG MyDatabase 
TO DISK = 'C:\Backup\MyDatabase_Log.trn'
WITH 
    COMPRESSION,
    INIT,
    NAME = 'MyDatabase Log Backup';
GO

-- Pattern 6: Backup with COPY_ONLY (no impact on backup chain)
BACKUP DATABASE MyDatabase 
TO DISK = 'C:\Backup\MyDatabase_CopyOnly.bak'
WITH 
    COPY_ONLY,
    COMPRESSION,
    INIT;
GO

-- Pattern 7: Backup with CHECKSUM
BACKUP DATABASE MyDatabase 
TO DISK = 'C:\Backup\MyDatabase_Full.bak'
WITH 
    CHECKSUM,
    CONTINUE_AFTER_ERROR,
    COMPRESSION,
    INIT;
GO

-- Pattern 8: Backup with encryption
BACKUP DATABASE MyDatabase 
TO DISK = 'C:\Backup\MyDatabase_Encrypted.bak'
WITH 
    ENCRYPTION (
        ALGORITHM = AES_256,
        SERVER CERTIFICATE = MyBackupCert
    ),
    COMPRESSION,
    INIT;
GO

-- Pattern 9: Backup with mirror
BACKUP DATABASE MyDatabase 
TO DISK = 'C:\Backup\MyDatabase_Primary.bak'
MIRROR TO DISK = 'D:\BackupMirror\MyDatabase_Mirror.bak'
WITH 
    FORMAT,
    COMPRESSION;
GO

-- Pattern 10: Partial backup (specific filegroups)
BACKUP DATABASE MyDatabase 
FILEGROUP = 'PRIMARY',
FILEGROUP = 'FG_Data'
TO DISK = 'C:\Backup\MyDatabase_Partial.bak'
WITH INIT;
GO

-- Pattern 11: File backup
BACKUP DATABASE MyDatabase 
FILE = 'MyDatabase_Data'
TO DISK = 'C:\Backup\MyDatabase_File.bak'
WITH INIT;
GO

-- Pattern 12: Tail-log backup (for disaster recovery)
BACKUP LOG MyDatabase 
TO DISK = 'C:\Backup\MyDatabase_TailLog.trn'
WITH 
    NORECOVERY,
    NO_TRUNCATE,
    NAME = 'Tail Log Backup';
GO

-- Pattern 13: Backup with expiration
BACKUP DATABASE MyDatabase 
TO DISK = 'C:\Backup\MyDatabase_Full.bak'
WITH 
    RETAINDAYS = 30,
    INIT;
GO

-- Pattern 14: Basic restore
RESTORE DATABASE MyDatabase 
FROM DISK = 'C:\Backup\MyDatabase_Full.bak'
WITH RECOVERY;
GO

-- Pattern 15: Restore with NORECOVERY (for subsequent restores)
RESTORE DATABASE MyDatabase 
FROM DISK = 'C:\Backup\MyDatabase_Full.bak'
WITH 
    NORECOVERY,
    REPLACE;
GO

-- Pattern 16: Restore differential
RESTORE DATABASE MyDatabase 
FROM DISK = 'C:\Backup\MyDatabase_Diff.bak'
WITH NORECOVERY;
GO

-- Pattern 17: Restore transaction log
RESTORE LOG MyDatabase 
FROM DISK = 'C:\Backup\MyDatabase_Log.trn'
WITH RECOVERY;
GO

-- Pattern 18: Restore with MOVE (relocate files)
RESTORE DATABASE MyDatabase 
FROM DISK = 'C:\Backup\MyDatabase_Full.bak'
WITH 
    MOVE 'MyDatabase_Data' TO 'D:\Data\MyDatabase.mdf',
    MOVE 'MyDatabase_Log' TO 'E:\Logs\MyDatabase_log.ldf',
    RECOVERY,
    REPLACE;
GO

-- Pattern 19: Point-in-time restore
RESTORE DATABASE MyDatabase 
FROM DISK = 'C:\Backup\MyDatabase_Full.bak'
WITH NORECOVERY;

RESTORE LOG MyDatabase 
FROM DISK = 'C:\Backup\MyDatabase_Log1.trn'
WITH NORECOVERY;

RESTORE LOG MyDatabase 
FROM DISK = 'C:\Backup\MyDatabase_Log2.trn'
WITH 
    STOPAT = '2024-06-15 14:30:00',
    RECOVERY;
GO

-- Pattern 20: Restore with STANDBY
RESTORE DATABASE MyDatabase 
FROM DISK = 'C:\Backup\MyDatabase_Full.bak'
WITH 
    STANDBY = 'C:\Backup\MyDatabase_Undo.dat',
    REPLACE;
-- Database is readable in standby mode
GO

-- Pattern 21: Restore to new database name
RESTORE DATABASE MyDatabase_Copy 
FROM DISK = 'C:\Backup\MyDatabase_Full.bak'
WITH 
    MOVE 'MyDatabase_Data' TO 'D:\Data\MyDatabase_Copy.mdf',
    MOVE 'MyDatabase_Log' TO 'E:\Logs\MyDatabase_Copy_log.ldf',
    RECOVERY;
GO

-- Pattern 22: Verify backup
RESTORE VERIFYONLY 
FROM DISK = 'C:\Backup\MyDatabase_Full.bak'
WITH CHECKSUM;
GO

-- Pattern 23: Get backup file information
RESTORE HEADERONLY FROM DISK = 'C:\Backup\MyDatabase_Full.bak';
RESTORE FILELISTONLY FROM DISK = 'C:\Backup\MyDatabase_Full.bak';
RESTORE LABELONLY FROM DISK = 'C:\Backup\MyDatabase_Full.bak';
GO

-- Pattern 24: Restore from striped backup
RESTORE DATABASE MyDatabase 
FROM 
    DISK = 'C:\Backup\MyDatabase_Full_1.bak',
    DISK = 'D:\Backup\MyDatabase_Full_2.bak',
    DISK = 'E:\Backup\MyDatabase_Full_3.bak'
WITH RECOVERY;
GO

-- Pattern 25: Restore specific file
RESTORE DATABASE MyDatabase 
FILE = 'MyDatabase_Data2'
FROM DISK = 'C:\Backup\MyDatabase_Full.bak'
WITH 
    NORECOVERY,
    PARTIAL;
GO

-- Pattern 26: Restore with STATS
RESTORE DATABASE MyDatabase 
FROM DISK = 'C:\Backup\MyDatabase_Full.bak'
WITH 
    RECOVERY,
    STATS = 5;  -- Show progress every 5%
GO

-- Pattern 27: Full restore sequence
-- Step 1: Full backup restore
RESTORE DATABASE MyDatabase 
FROM DISK = 'C:\Backup\MyDatabase_Full.bak'
WITH NORECOVERY, REPLACE;

-- Step 2: Differential restore
RESTORE DATABASE MyDatabase 
FROM DISK = 'C:\Backup\MyDatabase_Diff.bak'
WITH NORECOVERY;

-- Step 3: Log restores
RESTORE LOG MyDatabase FROM DISK = 'C:\Backup\Log1.trn' WITH NORECOVERY;
RESTORE LOG MyDatabase FROM DISK = 'C:\Backup\Log2.trn' WITH NORECOVERY;
RESTORE LOG MyDatabase FROM DISK = 'C:\Backup\Log3.trn' WITH NORECOVERY;

-- Step 4: Final recovery
RESTORE DATABASE MyDatabase WITH RECOVERY;
GO

-- Pattern 28: Restore page (page-level restore)
RESTORE DATABASE MyDatabase 
PAGE = '1:56, 1:57, 1:58'
FROM DISK = 'C:\Backup\MyDatabase_Full.bak'
WITH NORECOVERY;
GO

-- Pattern 29: Backup to URL (Azure Blob Storage)
BACKUP DATABASE MyDatabase 
TO URL = 'https://myaccount.blob.core.windows.net/backup/MyDatabase.bak'
WITH 
    CREDENTIAL = 'AzureStorageCredential',
    COMPRESSION,
    STATS = 10;
GO

-- Pattern 30: Restore from URL
RESTORE DATABASE MyDatabase 
FROM URL = 'https://myaccount.blob.core.windows.net/backup/MyDatabase.bak'
WITH 
    CREDENTIAL = 'AzureStorageCredential',
    RECOVERY;
GO
