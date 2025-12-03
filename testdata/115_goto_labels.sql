-- Sample 115: GOTO Statements and Labels
-- Category: Missing Syntax Elements
-- Complexity: Intermediate
-- Purpose: Parser testing - GOTO and label syntax
-- Features: Labels, GOTO, control flow with labels

-- Pattern 1: Simple GOTO
DECLARE @x INT = 0;

StartLoop:
SET @x = @x + 1;
SELECT @x AS CurrentValue;

IF @x < 5
    GOTO StartLoop;

SELECT 'Loop completed' AS Status;
GO

-- Pattern 2: GOTO for early exit
DECLARE @Status VARCHAR(20) = 'Invalid';
DECLARE @Value INT = -5;

IF @Value < 0
    GOTO ErrorHandler;

IF @Value > 100
    GOTO ErrorHandler;

SET @Status = 'Valid';
GOTO EndProc;

ErrorHandler:
SET @Status = 'Error: Invalid value';
SELECT @Status AS ErrorMessage;

EndProc:
SELECT @Status AS FinalStatus;
GO

-- Pattern 3: Multiple labels
DECLARE @Step INT = 1;

Step1:
SELECT 'Executing Step 1';
SET @Step = 2;
GOTO Step2;

Step3:
SELECT 'Executing Step 3';
SET @Step = 4;
GOTO EndSteps;

Step2:
SELECT 'Executing Step 2';
SET @Step = 3;
GOTO Step3;

EndSteps:
SELECT 'All steps completed', @Step AS FinalStep;
GO

-- Pattern 4: GOTO in error handling pattern (pre-TRY/CATCH style)
DECLARE @Error INT;
DECLARE @RowCount INT;

-- Step 1
INSERT INTO #TempTable (Value) VALUES (1);
SELECT @Error = @@ERROR, @RowCount = @@ROWCOUNT;
IF @Error <> 0 GOTO ErrorHandler;

-- Step 2
UPDATE #TempTable SET Value = Value + 1;
SELECT @Error = @@ERROR, @RowCount = @@ROWCOUNT;
IF @Error <> 0 GOTO ErrorHandler;

-- Step 3
DELETE FROM #TempTable WHERE Value > 10;
SELECT @Error = @@ERROR, @RowCount = @@ROWCOUNT;
IF @Error <> 0 GOTO ErrorHandler;

-- Success
SELECT 'All operations completed successfully' AS Result;
GOTO EndProc;

ErrorHandler:
SELECT 'Error occurred', @Error AS ErrorCode;
-- Rollback or cleanup here

EndProc:
SELECT 'Procedure finished' AS Status;
GO

-- Pattern 5: GOTO with nested IF
DECLARE @A INT = 1, @B INT = 2, @C INT = 3;

IF @A = 1
BEGIN
    IF @B = 2
    BEGIN
        IF @C = 3
            GOTO AllMatch;
        ELSE
            GOTO CNotMatch;
    END
    ELSE
        GOTO BNotMatch;
END
ELSE
    GOTO ANotMatch;

AllMatch:
SELECT 'All values match expected';
GOTO EndCheck;

ANotMatch:
SELECT 'A does not match';
GOTO EndCheck;

BNotMatch:
SELECT 'B does not match';
GOTO EndCheck;

CNotMatch:
SELECT 'C does not match';
GOTO EndCheck;

EndCheck:
SELECT 'Check completed';
GO

-- Pattern 6: Label naming variations
ValidLabel1:
SELECT 1;

Label_With_Underscores:
SELECT 2;

Label123WithNumbers:
SELECT 3;

_LabelStartingWithUnderscore:
SELECT 4;

-- LongerLabelNameThatIsStillValidInSQLServer:
-- SELECT 5;
GO

-- Pattern 7: GOTO in WHILE loop (alternative exit)
DECLARE @Counter INT = 0;
DECLARE @Found BIT = 0;

SearchLoop:
WHILE @Counter < 100
BEGIN
    SET @Counter = @Counter + 1;
    
    -- Simulate finding something
    IF @Counter = 42
    BEGIN
        SET @Found = 1;
        GOTO FoundIt;
    END
END

-- Not found
SELECT 'Value not found in range' AS Result;
GOTO EndSearch;

FoundIt:
SELECT 'Found at position', @Counter AS Position;

EndSearch:
SELECT 'Search completed', @Found AS WasFound;
GO

-- Pattern 8: GOTO skipping code blocks
DECLARE @SkipOptional BIT = 1;

SELECT 'Required Step 1';

IF @SkipOptional = 1
    GOTO SkipOptionalSteps;

SELECT 'Optional Step A';
SELECT 'Optional Step B';
SELECT 'Optional Step C';

SkipOptionalSteps:
SELECT 'Required Step 2';
GO

-- Pattern 9: Labels in stored procedure
CREATE PROCEDURE dbo.GotoExample
    @InputValue INT,
    @OutputMessage VARCHAR(100) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Validation
    IF @InputValue IS NULL
    BEGIN
        SET @OutputMessage = 'Input cannot be NULL';
        GOTO ExitProc;
    END
    
    IF @InputValue < 0
    BEGIN
        SET @OutputMessage = 'Input cannot be negative';
        GOTO ExitProc;
    END
    
    IF @InputValue > 1000
    BEGIN
        SET @OutputMessage = 'Input exceeds maximum';
        GOTO ExitProc;
    END
    
    -- Process valid input
    SET @OutputMessage = 'Processed value: ' + CAST(@InputValue * 2 AS VARCHAR(20));
    
    ExitProc:
    RETURN;
END;
GO

-- Pattern 10: GOTO cannot jump into or out of TRY/CATCH
-- This shows valid structure (GOTO within same block)
BEGIN TRY
    DECLARE @Val INT = 1;
    
    IF @Val = 1
        GOTO InsideTry;
    
    SELECT 'This is skipped';
    
    InsideTry:
    SELECT 'Inside TRY block';
END TRY
BEGIN CATCH
    InCatch:
    SELECT ERROR_MESSAGE();
END CATCH;
GO

-- Pattern 11: Forward and backward GOTO
DECLARE @Direction VARCHAR(10) = 'forward';

IF @Direction = 'backward'
    GOTO BackwardTarget;

SELECT 'Going forward';
GOTO ForwardTarget;

BackwardTarget:
SELECT 'Reached backward target';
GOTO EndDemo;

ForwardTarget:
SELECT 'Reached forward target';
-- GOTO BackwardTarget;  -- Could loop back

EndDemo:
SELECT 'End of demo';
GO
