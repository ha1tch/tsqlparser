-- Sample 077: Calendar and Scheduling Functions
-- Source: Various - Stack Overflow, MSSQLTips, Business calendar patterns
-- Category: Reporting
-- Complexity: Complex
-- Features: Business days, holidays, working hours, scheduling calculations

-- Create holiday table and populate with common holidays
CREATE PROCEDURE dbo.SetupHolidayCalendar
    @Year INT = NULL,
    @Country NVARCHAR(10) = 'US'
AS
BEGIN
    SET NOCOUNT ON;
    
    SET @Year = ISNULL(@Year, YEAR(GETDATE()));
    
    IF OBJECT_ID('dbo.Holidays', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.Holidays (
            HolidayID INT IDENTITY(1,1) PRIMARY KEY,
            HolidayDate DATE NOT NULL,
            HolidayName NVARCHAR(100) NOT NULL,
            Country NVARCHAR(10) NOT NULL,
            IsFloating BIT DEFAULT 0,
            UNIQUE (HolidayDate, Country)
        );
    END
    
    -- Clear existing holidays for the year
    DELETE FROM dbo.Holidays WHERE YEAR(HolidayDate) = @Year AND Country = @Country;
    
    IF @Country = 'US'
    BEGIN
        -- Fixed holidays
        INSERT INTO dbo.Holidays (HolidayDate, HolidayName, Country)
        VALUES 
            (DATEFROMPARTS(@Year, 1, 1), 'New Year''s Day', 'US'),
            (DATEFROMPARTS(@Year, 7, 4), 'Independence Day', 'US'),
            (DATEFROMPARTS(@Year, 12, 25), 'Christmas Day', 'US'),
            (DATEFROMPARTS(@Year, 11, 11), 'Veterans Day', 'US');
        
        -- MLK Day (3rd Monday of January)
        INSERT INTO dbo.Holidays (HolidayDate, HolidayName, Country, IsFloating)
        SELECT DATEADD(DAY, (16 - DATEPART(WEEKDAY, DATEFROMPARTS(@Year, 1, 1)) + 7) % 7 + 14, DATEFROMPARTS(@Year, 1, 1)),
               'Martin Luther King Jr. Day', 'US', 1;
        
        -- Presidents Day (3rd Monday of February)
        INSERT INTO dbo.Holidays (HolidayDate, HolidayName, Country, IsFloating)
        SELECT DATEADD(DAY, (16 - DATEPART(WEEKDAY, DATEFROMPARTS(@Year, 2, 1)) + 7) % 7 + 14, DATEFROMPARTS(@Year, 2, 1)),
               'Presidents Day', 'US', 1;
        
        -- Memorial Day (Last Monday of May)
        INSERT INTO dbo.Holidays (HolidayDate, HolidayName, Country, IsFloating)
        SELECT DATEADD(DAY, -((DATEPART(WEEKDAY, DATEFROMPARTS(@Year, 5, 31)) + 5) % 7), DATEFROMPARTS(@Year, 5, 31)),
               'Memorial Day', 'US', 1;
        
        -- Labor Day (1st Monday of September)
        INSERT INTO dbo.Holidays (HolidayDate, HolidayName, Country, IsFloating)
        SELECT DATEADD(DAY, (9 - DATEPART(WEEKDAY, DATEFROMPARTS(@Year, 9, 1))) % 7, DATEFROMPARTS(@Year, 9, 1)),
               'Labor Day', 'US', 1;
        
        -- Thanksgiving (4th Thursday of November)
        INSERT INTO dbo.Holidays (HolidayDate, HolidayName, Country, IsFloating)
        SELECT DATEADD(DAY, (12 - DATEPART(WEEKDAY, DATEFROMPARTS(@Year, 11, 1))) % 7 + 21, DATEFROMPARTS(@Year, 11, 1)),
               'Thanksgiving', 'US', 1;
    END
    
    SELECT COUNT(*) AS HolidaysCreated, @Year AS Year, @Country AS Country FROM dbo.Holidays WHERE YEAR(HolidayDate) = @Year AND Country = @Country;
END
GO

-- Check if date is business day
CREATE FUNCTION dbo.IsBusinessDay
(
    @Date DATE,
    @Country NVARCHAR(10) = 'US'
)
RETURNS BIT
AS
BEGIN
    -- Check if weekend
    IF DATEPART(WEEKDAY, @Date) IN (1, 7)  -- Sunday = 1, Saturday = 7
        RETURN 0;
    
    -- Check if holiday
    IF EXISTS (SELECT 1 FROM dbo.Holidays WHERE HolidayDate = @Date AND Country = @Country)
        RETURN 0;
    
    RETURN 1;
END
GO

-- Add business days to a date
CREATE FUNCTION dbo.AddBusinessDays
(
    @StartDate DATE,
    @DaysToAdd INT,
    @Country NVARCHAR(10) = 'US'
)
RETURNS DATE
AS
BEGIN
    DECLARE @ResultDate DATE = @StartDate;
    DECLARE @DaysAdded INT = 0;
    DECLARE @Direction INT = CASE WHEN @DaysToAdd >= 0 THEN 1 ELSE -1 END;
    
    SET @DaysToAdd = ABS(@DaysToAdd);
    
    WHILE @DaysAdded < @DaysToAdd
    BEGIN
        SET @ResultDate = DATEADD(DAY, @Direction, @ResultDate);
        
        IF dbo.IsBusinessDay(@ResultDate, @Country) = 1
            SET @DaysAdded = @DaysAdded + 1;
    END
    
    RETURN @ResultDate;
END
GO

-- Count business days between two dates
CREATE FUNCTION dbo.CountBusinessDays
(
    @StartDate DATE,
    @EndDate DATE,
    @Country NVARCHAR(10) = 'US'
)
RETURNS INT
AS
BEGIN
    DECLARE @BusinessDays INT = 0;
    DECLARE @CurrentDate DATE = @StartDate;
    
    IF @StartDate > @EndDate
        RETURN 0;
    
    WHILE @CurrentDate <= @EndDate
    BEGIN
        IF dbo.IsBusinessDay(@CurrentDate, @Country) = 1
            SET @BusinessDays = @BusinessDays + 1;
        
        SET @CurrentDate = DATEADD(DAY, 1, @CurrentDate);
    END
    
    RETURN @BusinessDays;
END
GO

-- Get next business day
CREATE FUNCTION dbo.GetNextBusinessDay
(
    @Date DATE,
    @Country NVARCHAR(10) = 'US'
)
RETURNS DATE
AS
BEGIN
    DECLARE @NextDate DATE = DATEADD(DAY, 1, @Date);
    
    WHILE dbo.IsBusinessDay(@NextDate, @Country) = 0
    BEGIN
        SET @NextDate = DATEADD(DAY, 1, @NextDate);
    END
    
    RETURN @NextDate;
END
GO

-- Generate schedule for recurring events
CREATE PROCEDURE dbo.GenerateRecurringSchedule
    @StartDate DATE,
    @EndDate DATE,
    @RecurrenceType NVARCHAR(20),  -- DAILY, WEEKLY, MONTHLY, YEARLY
    @Interval INT = 1,
    @DaysOfWeek NVARCHAR(50) = NULL,  -- Comma-separated: MON,TUE,WED,THU,FRI
    @DayOfMonth INT = NULL,
    @BusinessDaysOnly BIT = 0,
    @Country NVARCHAR(10) = 'US'
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @CurrentDate DATE = @StartDate;
    DECLARE @Results TABLE (OccurrenceDate DATE, DayOfWeek NVARCHAR(10));
    
    -- Parse days of week
    DECLARE @WeekDays TABLE (DayName NVARCHAR(10), DayNumber INT);
    IF @DaysOfWeek IS NOT NULL
    BEGIN
        INSERT INTO @WeekDays
        SELECT LTRIM(RTRIM(value)),
               CASE LTRIM(RTRIM(value))
                   WHEN 'SUN' THEN 1 WHEN 'MON' THEN 2 WHEN 'TUE' THEN 3
                   WHEN 'WED' THEN 4 WHEN 'THU' THEN 5 WHEN 'FRI' THEN 6
                   WHEN 'SAT' THEN 7
               END
        FROM STRING_SPLIT(@DaysOfWeek, ',');
    END
    
    WHILE @CurrentDate <= @EndDate
    BEGIN
        DECLARE @Include BIT = 0;
        
        IF @RecurrenceType = 'DAILY'
        BEGIN
            SET @Include = 1;
        END
        ELSE IF @RecurrenceType = 'WEEKLY'
        BEGIN
            IF EXISTS (SELECT 1 FROM @WeekDays WHERE DayNumber = DATEPART(WEEKDAY, @CurrentDate))
                SET @Include = 1;
        END
        ELSE IF @RecurrenceType = 'MONTHLY'
        BEGIN
            IF DAY(@CurrentDate) = ISNULL(@DayOfMonth, DAY(@StartDate))
                SET @Include = 1;
        END
        ELSE IF @RecurrenceType = 'YEARLY'
        BEGIN
            IF MONTH(@CurrentDate) = MONTH(@StartDate) AND DAY(@CurrentDate) = ISNULL(@DayOfMonth, DAY(@StartDate))
                SET @Include = 1;
        END
        
        -- Check business day constraint
        IF @Include = 1 AND @BusinessDaysOnly = 1 AND dbo.IsBusinessDay(@CurrentDate, @Country) = 0
            SET @Include = 0;
        
        IF @Include = 1
            INSERT INTO @Results VALUES (@CurrentDate, DATENAME(WEEKDAY, @CurrentDate));
        
        SET @CurrentDate = DATEADD(DAY, @Interval, @CurrentDate);
    END
    
    SELECT OccurrenceDate, DayOfWeek FROM @Results ORDER BY OccurrenceDate;
END
GO

-- Calculate working hours between two datetimes
CREATE FUNCTION dbo.CalculateWorkingHours
(
    @StartDateTime DATETIME,
    @EndDateTime DATETIME,
    @WorkDayStart TIME = '09:00',
    @WorkDayEnd TIME = '17:00',
    @Country NVARCHAR(10) = 'US'
)
RETURNS DECIMAL(10,2)
AS
BEGIN
    DECLARE @TotalHours DECIMAL(10,2) = 0;
    DECLARE @CurrentDate DATE = CAST(@StartDateTime AS DATE);
    DECLARE @EndDate DATE = CAST(@EndDateTime AS DATE);
    DECLARE @DayStart TIME;
    DECLARE @DayEnd TIME;
    
    WHILE @CurrentDate <= @EndDate
    BEGIN
        IF dbo.IsBusinessDay(@CurrentDate, @Country) = 1
        BEGIN
            -- Calculate hours for this day
            SET @DayStart = CASE 
                WHEN @CurrentDate = CAST(@StartDateTime AS DATE) 
                     AND CAST(@StartDateTime AS TIME) > @WorkDayStart 
                THEN CAST(@StartDateTime AS TIME) 
                ELSE @WorkDayStart 
            END;
            
            SET @DayEnd = CASE 
                WHEN @CurrentDate = @EndDate 
                     AND CAST(@EndDateTime AS TIME) < @WorkDayEnd 
                THEN CAST(@EndDateTime AS TIME) 
                ELSE @WorkDayEnd 
            END;
            
            IF @DayEnd > @DayStart
                SET @TotalHours = @TotalHours + DATEDIFF(MINUTE, @DayStart, @DayEnd) / 60.0;
        END
        
        SET @CurrentDate = DATEADD(DAY, 1, @CurrentDate);
    END
    
    RETURN @TotalHours;
END
GO
