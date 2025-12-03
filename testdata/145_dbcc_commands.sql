-- Sample 145: DBCC Commands
-- Category: Missing Syntax Elements
-- Complexity: Advanced
-- Purpose: Parser testing - DBCC statement syntax
-- Features: DBCC for maintenance, checking, information

-- Pattern 1: DBCC CHECKDB - Database consistency check
DBCC CHECKDB('MyDatabase');
DBCC CHECKDB('MyDatabase') WITH NO_INFOMSGS;
DBCC CHECKDB('MyDatabase') WITH NO_INFOMSGS, ALL_ERRORMSGS;
DBCC CHECKDB WITH NO_INFOMSGS;  -- Current database
GO

-- Pattern 2: DBCC CHECKTABLE - Table consistency check
DBCC CHECKTABLE('dbo.Customers');
DBCC CHECKTABLE('dbo.Customers') WITH NO_INFOMSGS;
DBCC CHECKTABLE('dbo.Customers', NOINDEX);
DBCC CHECKTABLE('dbo.Orders') WITH PHYSICAL_ONLY;
GO

-- Pattern 3: DBCC CHECKALLOC - Allocation consistency
DBCC CHECKALLOC('MyDatabase');
DBCC CHECKALLOC('MyDatabase') WITH NO_INFOMSGS;
DBCC CHECKALLOC WITH NO_INFOMSGS;
GO

-- Pattern 4: DBCC CHECKCATALOG - Catalog consistency
DBCC CHECKCATALOG('MyDatabase');
DBCC CHECKCATALOG;  -- Current database
GO

-- Pattern 5: DBCC CHECKIDENT - Identity value check/reset
DBCC CHECKIDENT('dbo.Customers');  -- Check current identity
DBCC CHECKIDENT('dbo.Customers', NORESEED);  -- Check without reseeding
DBCC CHECKIDENT('dbo.Customers', RESEED);  -- Reseed to max value
DBCC CHECKIDENT('dbo.Customers', RESEED, 1000);  -- Reseed to specific value
GO

-- Pattern 6: DBCC CHECKCONSTRAINTS
DBCC CHECKCONSTRAINTS('dbo.Customers');  -- Check specific table
DBCC CHECKCONSTRAINTS WITH ALL_CONSTRAINTS;  -- All tables
DBCC CHECKCONSTRAINTS('CK_Customers_Age');  -- Specific constraint
GO

-- Pattern 7: DBCC SHRINKDATABASE
DBCC SHRINKDATABASE('MyDatabase');
DBCC SHRINKDATABASE('MyDatabase', 10);  -- Target 10% free
DBCC SHRINKDATABASE('MyDatabase', 10, NOTRUNCATE);
DBCC SHRINKDATABASE('MyDatabase', 10, TRUNCATEONLY);
GO

-- Pattern 8: DBCC SHRINKFILE
DBCC SHRINKFILE('MyDatabase_Data', 1000);  -- Shrink to 1000 MB
DBCC SHRINKFILE('MyDatabase_Log', TRUNCATEONLY);
DBCC SHRINKFILE('MyDatabase_Data', EMPTYFILE);  -- Empty the file
DBCC SHRINKFILE(1, 500);  -- By file_id
GO

-- Pattern 9: DBCC DROPCLEANBUFFERS - Clear buffer cache (testing only)
DBCC DROPCLEANBUFFERS;
DBCC DROPCLEANBUFFERS WITH NO_INFOMSGS;
GO

-- Pattern 10: DBCC FREEPROCCACHE - Clear procedure cache
DBCC FREEPROCCACHE;
DBCC FREEPROCCACHE WITH NO_INFOMSGS;
DBCC FREEPROCCACHE(0x060006007A6CC30640E15E0D000000000000000000000000);  -- Specific plan handle
GO

-- Pattern 11: DBCC FREESYSTEMCACHE
DBCC FREESYSTEMCACHE('ALL');
DBCC FREESYSTEMCACHE('SQL Plans');
DBCC FREESYSTEMCACHE('Object Plans');
GO

-- Pattern 12: DBCC UPDATEUSAGE - Space usage recalculation
DBCC UPDATEUSAGE('MyDatabase');
DBCC UPDATEUSAGE('MyDatabase', 'dbo.Customers');
DBCC UPDATEUSAGE(0) WITH NO_INFOMSGS;  -- Current database
GO

-- Pattern 13: DBCC SHOWCONTIG - Fragmentation info (deprecated)
DBCC SHOWCONTIG('dbo.Customers');
DBCC SHOWCONTIG('dbo.Customers') WITH TABLERESULTS;
DBCC SHOWCONTIG('dbo.Customers') WITH ALL_INDEXES;
DBCC SHOWCONTIG('dbo.Customers', 1);  -- Specific index
GO

-- Pattern 14: DBCC IND - Index page info (undocumented but common)
DBCC IND('MyDatabase', 'dbo.Customers', 1);  -- Index_id 1
DBCC IND('MyDatabase', 'dbo.Customers', -1);  -- All indexes
GO

-- Pattern 15: DBCC PAGE - Read page data (undocumented)
DBCC TRACEON(3604);  -- Direct output to client
DBCC PAGE('MyDatabase', 1, 256, 3);  -- FileID, PageID, PrintOption
DBCC TRACEOFF(3604);
GO

-- Pattern 16: DBCC SQLPERF
DBCC SQLPERF(LOGSPACE);  -- Log space usage
DBCC SQLPERF('sys.dm_os_wait_stats', CLEAR);  -- Clear wait stats
DBCC SQLPERF('sys.dm_os_latch_stats', CLEAR);
GO

-- Pattern 17: DBCC INPUTBUFFER and OUTPUTBUFFER
DBCC INPUTBUFFER(55);  -- SPID 55's last input
DBCC OUTPUTBUFFER(55);  -- SPID 55's output buffer
GO

-- Pattern 18: DBCC OPENTRAN
DBCC OPENTRAN;  -- Current database
DBCC OPENTRAN('MyDatabase');
DBCC OPENTRAN WITH TABLERESULTS;
GO

-- Pattern 19: DBCC USEROPTIONS
DBCC USEROPTIONS;
GO

-- Pattern 20: DBCC PROCCACHE
DBCC PROCCACHE;  -- Procedure cache statistics
GO

-- Pattern 21: DBCC SHOW_STATISTICS
DBCC SHOW_STATISTICS('dbo.Customers', 'IX_Customers_Name');
DBCC SHOW_STATISTICS('dbo.Customers', 'IX_Customers_Name') WITH HISTOGRAM;
DBCC SHOW_STATISTICS('dbo.Customers', 'IX_Customers_Name') WITH DENSITY_VECTOR;
DBCC SHOW_STATISTICS('dbo.Customers', 'IX_Customers_Name') WITH STAT_HEADER;
GO

-- Pattern 22: DBCC DBREINDEX (deprecated, use ALTER INDEX)
DBCC DBREINDEX('dbo.Customers', 'IX_Customers_Name', 80);  -- 80% fill factor
DBCC DBREINDEX('dbo.Customers', '', 90);  -- All indexes
GO

-- Pattern 23: DBCC INDEXDEFRAG (deprecated, use ALTER INDEX REORGANIZE)
DBCC INDEXDEFRAG('MyDatabase', 'dbo.Customers', 'IX_Customers_Name');
DBCC INDEXDEFRAG('MyDatabase', 'dbo.Customers', 'IX_Customers_Name') WITH NO_INFOMSGS;
GO

-- Pattern 24: DBCC TRACEON/TRACEOFF
DBCC TRACEON(1204);  -- Deadlock info
DBCC TRACEON(1222);  -- Detailed deadlock info
DBCC TRACEON(3604);  -- Direct output to client
DBCC TRACEON(1204, 1222, -1);  -- Multiple flags, -1 for global

DBCC TRACESTATUS;  -- Show active trace flags
DBCC TRACESTATUS(-1);  -- Global flags
DBCC TRACESTATUS(1204, 1222);  -- Specific flags

DBCC TRACEOFF(1204);
DBCC TRACEOFF(1204, 1222, -1);
GO

-- Pattern 25: DBCC LOGINFO
DBCC LOGINFO;  -- VLF information for current database
DBCC LOGINFO('MyDatabase');
GO

-- Pattern 26: DBCC HELP
DBCC HELP('CHECKDB');
DBCC HELP('?');  -- List all DBCC commands
GO

-- Pattern 27: DBCC CLEANTABLE - Reclaim space from dropped columns
DBCC CLEANTABLE('MyDatabase', 'dbo.Customers');
DBCC CLEANTABLE('MyDatabase', 'dbo.Customers', 10000);  -- Batch size
GO
