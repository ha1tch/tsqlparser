-- Sample 196: Batch Separators and Script Structure
-- Category: Syntax Coverage / Script Patterns
-- Complexity: Intermediate
-- Purpose: Parser testing - GO and batch handling
-- Features: GO, batch scope, script organization

-- Pattern 1: Basic GO separator
SELECT 'First batch';
GO
SELECT 'Second batch';
GO

-- Pattern 2: GO with count
PRINT 'This will execute 3 times';
GO 3

-- Pattern 3: Variable scope across batches
DECLARE @Var1 INT = 100;
SELECT @Var1 AS VarInSameBatch;
GO

-- @Var1 is not accessible here - new batch
-- SELECT @Var1;  -- Would cause error
DECLARE @Var1 INT = 200;  -- Must redeclare
SELECT @Var1 AS VarInNewBatch;
GO

-- Pattern 4: Temp table across batches
CREATE TABLE #TempAcrossBatches (ID INT);
GO

INSERT INTO #TempAcrossBatches VALUES (1);
GO

SELECT * FROM #TempAcrossBatches;
GO

DROP TABLE #TempAcrossBatches;
GO

-- Pattern 5: CREATE must be first statement in batch
-- These require GO before them:
GO
CREATE PROCEDURE dbo.MustBeFirst AS SELECT 1;
GO
DROP PROCEDURE dbo.MustBeFirst;
GO

GO
CREATE VIEW dbo.MustBeFirstView AS SELECT 1 AS Col;
GO
DROP VIEW dbo.MustBeFirstView;
GO

GO
CREATE FUNCTION dbo.MustBeFirstFunc() RETURNS INT AS BEGIN RETURN 1; END;
GO
DROP FUNCTION dbo.MustBeFirstFunc;
GO

GO
CREATE TRIGGER dbo.MustBeFirstTrigger ON dbo.Customers FOR INSERT AS SELECT 1;
GO
DROP TRIGGER dbo.MustBeFirstTrigger;
GO

-- Pattern 6: Error handling in batches
SELECT 'This will succeed';
GO

-- Error in this batch won't affect previous or next batches
-- SELECT * FROM NonExistentTable;
GO

SELECT 'This still executes after previous batch error';
GO

-- Pattern 7: Script sections with comments
-- ============================================
-- Section 1: Schema Creation
-- ============================================
GO
PRINT 'Creating schema objects...';
GO

-- ============================================
-- Section 2: Data Loading
-- ============================================
GO
PRINT 'Loading data...';
GO

-- ============================================
-- Section 3: Cleanup
-- ============================================
GO
PRINT 'Cleanup complete.';
GO

-- Pattern 8: Conditional batch execution with SQLCMD
-- These only work in SQLCMD mode:
/*
:setvar DatabaseName "MyDB"
:setvar SchemaName "dbo"

USE $(DatabaseName);
GO

SELECT * FROM $(SchemaName).Customers;
GO

:on error exit
:r .\AnotherScript.sql
*/
GO

-- Pattern 9: Multiple statements in one batch
DECLARE @Count INT;
SELECT @Count = COUNT(*) FROM dbo.Customers;
PRINT 'Customer count: ' + CAST(@Count AS VARCHAR(10));
IF @Count > 100
    PRINT 'Large customer base';
ELSE
    PRINT 'Small customer base';
GO

-- Pattern 10: Transaction across batches (not typical)
BEGIN TRANSACTION;
GO

INSERT INTO dbo.Customers (CustomerName) VALUES ('Test1');
GO

INSERT INTO dbo.Customers (CustomerName) VALUES ('Test2');
GO

-- Transaction still open
IF @@TRANCOUNT > 0
    ROLLBACK TRANSACTION;
GO

-- Pattern 11: Deployment script pattern
PRINT '======================================';
PRINT 'Starting deployment...';
PRINT 'Date: ' + CONVERT(VARCHAR, GETDATE(), 120);
PRINT '======================================';
GO

-- Check prerequisites
IF DB_ID('TargetDB') IS NULL
BEGIN
    RAISERROR('Target database does not exist', 16, 1);
    -- In SQLCMD: :on error exit would stop here
END
GO

-- Apply changes
PRINT 'Applying schema changes...';
GO

-- Verify changes
PRINT 'Verifying changes...';
GO

PRINT '======================================';
PRINT 'Deployment complete!';
PRINT '======================================';
GO

-- Pattern 12: Stored procedure with multiple batches
-- Procedure definition requires single batch
CREATE PROCEDURE dbo.MultiStepProc
AS
BEGIN
    -- All logic must be in one batch
    DECLARE @Step INT = 1;
    
    PRINT 'Step ' + CAST(@Step AS VARCHAR);
    SET @Step = @Step + 1;
    
    PRINT 'Step ' + CAST(@Step AS VARCHAR);
    SET @Step = @Step + 1;
    
    PRINT 'Step ' + CAST(@Step AS VARCHAR);
END;
GO

EXEC dbo.MultiStepProc;
GO

DROP PROCEDURE dbo.MultiStepProc;
GO

-- Pattern 13: USE statement requires own batch sometimes
USE master;
GO

USE tempdb;
GO

-- Pattern 14: Batch-level SET options
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

SELECT * FROM dbo.Customers;
GO

-- Pattern 15: Script template structure
/*
================================================================================
Script Name: Example Script
Description: Demonstrates script structure
Author: Developer Name
Created: 2024-06-15
Modified: 2024-06-15

Change History:
Date        Author      Description
----------  ----------  -------------------------------------------------------
2024-06-15  Dev         Initial creation
================================================================================
*/
GO

-- Pre-execution checks
PRINT 'Performing pre-execution checks...';
GO

-- Main script body
PRINT 'Executing main script...';
GO

-- Post-execution verification
PRINT 'Verifying execution...';
GO

-- End of script
PRINT 'Script completed successfully.';
GO
