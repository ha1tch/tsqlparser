-- Sample 029: Date/Time Calculation Procedures
-- Source: Various - Stack Overflow, MSSQLTips, Aaron Bertrand articles
-- Category: Reporting
-- Complexity: Complex
-- Features: Date functions, calendar tables, business day calculations, fiscal periods

-- Create calendar/date dimension table
CREATE PROCEDURE dbo.GenerateCalendarTable
    @StartDate DATE = '2020-01-01',
    @EndDate DATE = '2030-12-31',
    @FiscalYearStartMonth INT = 7  -- July
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Create calendar table
    IF OBJECT_ID('dbo.Calendar', 'U') IS NOT NULL
        DROP TABLE dbo.Calendar;
    
    CREATE TABLE dbo.Calendar (
        DateKey INT NOT NULL PRIMARY KEY,
        FullDate DATE NOT NULL,
        DayOfMonth TINYINT NOT NULL,
        DayOfYear SMALLINT NOT NULL,
        DayOfWeek TINYINT NOT NULL,
        DayName VARCHAR(10) NOT NULL,
        DayNameShort CHAR(3) NOT NULL,
        WeekOfYear TINYINT NOT NULL,
        WeekOfMonth TINYINT NOT NULL,
        MonthNumber TINYINT NOT NULL,
        MonthName VARCHAR(10) NOT NULL,
        MonthNameShort CHAR(3) NOT NULL,
        Quarter TINYINT NOT NULL,
        QuarterName CHAR(2) NOT NULL,
        Year SMALLINT NOT NULL,
        YearMonth CHAR(7) NOT NULL,
        YearQuarter CHAR(7) NOT NULL,
        IsWeekend BIT NOT NULL,
        IsWeekday BIT NOT NULL,
        IsHoliday BIT NOT NULL DEFAULT 0,
        HolidayName VARCHAR(50) NULL,
        FiscalYear SMALLINT NOT NULL,
        FiscalQuarter TINYINT NOT NULL,
        FiscalMonth TINYINT NOT NULL,
        IsFirstDayOfMonth BIT NOT NULL,
        IsLastDayOfMonth BIT NOT NULL,
        IsFirstDayOfQuarter BIT NOT NULL,
        IsLastDayOfQuarter BIT NOT NULL,
        IsFirstDayOfYear BIT NOT NULL,
        IsLastDayOfYear BIT NOT NULL
    );
    
    -- Generate dates using recursive CTE
    ;WITH DateSequence AS (
        SELECT @StartDate AS DateValue
        UNION ALL
        SELECT DATEADD(DAY, 1, DateValue)
        FROM DateSequence
        WHERE DateValue < @EndDate
    )
    INSERT INTO dbo.Calendar
    SELECT 
        CAST(FORMAT(DateValue, 'yyyyMMdd') AS INT) AS DateKey,
        DateValue AS FullDate,
        DAY(DateValue) AS DayOfMonth,
        DATEPART(DAYOFYEAR, DateValue) AS DayOfYear,
        DATEPART(WEEKDAY, DateValue) AS DayOfWeek,
        DATENAME(WEEKDAY, DateValue) AS DayName,
        LEFT(DATENAME(WEEKDAY, DateValue), 3) AS DayNameShort,
        DATEPART(WEEK, DateValue) AS WeekOfYear,
        DATEDIFF(WEEK, DATEADD(MONTH, DATEDIFF(MONTH, 0, DateValue), 0), DateValue) + 1 AS WeekOfMonth,
        MONTH(DateValue) AS MonthNumber,
        DATENAME(MONTH, DateValue) AS MonthName,
        LEFT(DATENAME(MONTH, DateValue), 3) AS MonthNameShort,
        DATEPART(QUARTER, DateValue) AS Quarter,
        'Q' + CAST(DATEPART(QUARTER, DateValue) AS CHAR(1)) AS QuarterName,
        YEAR(DateValue) AS Year,
        FORMAT(DateValue, 'yyyy-MM') AS YearMonth,
        CAST(YEAR(DateValue) AS VARCHAR(4)) + '-Q' + CAST(DATEPART(QUARTER, DateValue) AS CHAR(1)) AS YearQuarter,
        CASE WHEN DATEPART(WEEKDAY, DateValue) IN (1, 7) THEN 1 ELSE 0 END AS IsWeekend,
        CASE WHEN DATEPART(WEEKDAY, DateValue) IN (1, 7) THEN 0 ELSE 1 END AS IsWeekday,
        0 AS IsHoliday,
        NULL AS HolidayName,
        -- Fiscal year calculations
        CASE 
            WHEN MONTH(DateValue) >= @FiscalYearStartMonth 
            THEN YEAR(DateValue) + 1 
            ELSE YEAR(DateValue) 
        END AS FiscalYear,
        CASE 
            WHEN MONTH(DateValue) >= @FiscalYearStartMonth 
            THEN ((MONTH(DateValue) - @FiscalYearStartMonth) / 3) + 1
            ELSE ((MONTH(DateValue) + 12 - @FiscalYearStartMonth) / 3) + 1
        END AS FiscalQuarter,
        CASE 
            WHEN MONTH(DateValue) >= @FiscalYearStartMonth 
            THEN MONTH(DateValue) - @FiscalYearStartMonth + 1
            ELSE MONTH(DateValue) + 12 - @FiscalYearStartMonth + 1
        END AS FiscalMonth,
        CASE WHEN DAY(DateValue) = 1 THEN 1 ELSE 0 END AS IsFirstDayOfMonth,
        CASE WHEN DateValue = EOMONTH(DateValue) THEN 1 ELSE 0 END AS IsLastDayOfMonth,
        CASE WHEN DateValue = DATEADD(QUARTER, DATEDIFF(QUARTER, 0, DateValue), 0) THEN 1 ELSE 0 END AS IsFirstDayOfQuarter,
        CASE WHEN DateValue = DATEADD(DAY, -1, DATEADD(QUARTER, DATEDIFF(QUARTER, 0, DateValue) + 1, 0)) THEN 1 ELSE 0 END AS IsLastDayOfQuarter,
        CASE WHEN DateValue = DATEFROMPARTS(YEAR(DateValue), 1, 1) THEN 1 ELSE 0 END AS IsFirstDayOfYear,
        CASE WHEN DateValue = DATEFROMPARTS(YEAR(DateValue), 12, 31) THEN 1 ELSE 0 END AS IsLastDayOfYear
    FROM DateSequence
    OPTION (MAXRECURSION 0);
    
    -- Mark US Federal Holidays
    -- New Year's Day
    UPDATE dbo.Calendar SET IsHoliday = 1, HolidayName = 'New Year''s Day'
    WHERE MonthNumber = 1 AND DayOfMonth = 1;
    
    -- Independence Day
    UPDATE dbo.Calendar SET IsHoliday = 1, HolidayName = 'Independence Day'
    WHERE MonthNumber = 7 AND DayOfMonth = 4;
    
    -- Christmas
    UPDATE dbo.Calendar SET IsHoliday = 1, HolidayName = 'Christmas Day'
    WHERE MonthNumber = 12 AND DayOfMonth = 25;
    
    -- Thanksgiving (4th Thursday of November)
    UPDATE dbo.Calendar SET IsHoliday = 1, HolidayName = 'Thanksgiving'
    WHERE MonthNumber = 11 AND DayOfWeek = 5 AND DayOfMonth BETWEEN 22 AND 28;
    
    SELECT 
        COUNT(*) AS TotalDates,
        MIN(FullDate) AS StartDate,
        MAX(FullDate) AS EndDate,
        SUM(CAST(IsHoliday AS INT)) AS HolidayCount
    FROM dbo.Calendar;
END
GO

-- Calculate business days between two dates
CREATE FUNCTION dbo.GetBusinessDays
(
    @StartDate DATE,
    @EndDate DATE,
    @ExcludeHolidays BIT = 1
)
RETURNS INT
AS
BEGIN
    DECLARE @BusinessDays INT;
    
    IF OBJECT_ID('dbo.Calendar', 'U') IS NOT NULL
    BEGIN
        SELECT @BusinessDays = COUNT(*)
        FROM dbo.Calendar
        WHERE FullDate BETWEEN @StartDate AND @EndDate
          AND IsWeekday = 1
          AND (@ExcludeHolidays = 0 OR IsHoliday = 0);
    END
    ELSE
    BEGIN
        -- Fallback calculation without calendar table
        ;WITH DateRange AS (
            SELECT @StartDate AS DateValue
            UNION ALL
            SELECT DATEADD(DAY, 1, DateValue)
            FROM DateRange
            WHERE DateValue < @EndDate
        )
        SELECT @BusinessDays = COUNT(*)
        FROM DateRange
        WHERE DATEPART(WEEKDAY, DateValue) NOT IN (1, 7)
        OPTION (MAXRECURSION 0);
    END
    
    RETURN @BusinessDays;
END
GO

-- Add business days to a date
CREATE FUNCTION dbo.AddBusinessDays
(
    @StartDate DATE,
    @DaysToAdd INT,
    @ExcludeHolidays BIT = 1
)
RETURNS DATE
AS
BEGIN
    DECLARE @ResultDate DATE = @StartDate;
    DECLARE @DaysAdded INT = 0;
    DECLARE @Direction INT = SIGN(@DaysToAdd);
    
    SET @DaysToAdd = ABS(@DaysToAdd);
    
    WHILE @DaysAdded < @DaysToAdd
    BEGIN
        SET @ResultDate = DATEADD(DAY, @Direction, @ResultDate);
        
        -- Check if it's a business day
        IF DATEPART(WEEKDAY, @ResultDate) NOT IN (1, 7)
        BEGIN
            IF @ExcludeHolidays = 0 OR NOT EXISTS (
                SELECT 1 FROM dbo.Calendar 
                WHERE FullDate = @ResultDate AND IsHoliday = 1
            )
                SET @DaysAdded = @DaysAdded + 1;
        END
    END
    
    RETURN @ResultDate;
END
GO

-- Get date range boundaries
CREATE PROCEDURE dbo.GetDateRangeBoundaries
    @RangeType NVARCHAR(50),  -- Today, Yesterday, ThisWeek, LastWeek, ThisMonth, LastMonth, 
                               -- ThisQuarter, LastQuarter, ThisYear, LastYear, Last7Days, Last30Days
    @ReferenceDate DATE = NULL,
    @StartDate DATE OUTPUT,
    @EndDate DATE OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    SET @ReferenceDate = ISNULL(@ReferenceDate, GETDATE());
    
    SELECT @StartDate = CASE @RangeType
        WHEN 'Today' THEN @ReferenceDate
        WHEN 'Yesterday' THEN DATEADD(DAY, -1, @ReferenceDate)
        WHEN 'ThisWeek' THEN DATEADD(DAY, 1 - DATEPART(WEEKDAY, @ReferenceDate), @ReferenceDate)
        WHEN 'LastWeek' THEN DATEADD(DAY, 1 - DATEPART(WEEKDAY, @ReferenceDate) - 7, @ReferenceDate)
        WHEN 'ThisMonth' THEN DATEFROMPARTS(YEAR(@ReferenceDate), MONTH(@ReferenceDate), 1)
        WHEN 'LastMonth' THEN DATEADD(MONTH, -1, DATEFROMPARTS(YEAR(@ReferenceDate), MONTH(@ReferenceDate), 1))
        WHEN 'ThisQuarter' THEN DATEADD(QUARTER, DATEDIFF(QUARTER, 0, @ReferenceDate), 0)
        WHEN 'LastQuarter' THEN DATEADD(QUARTER, DATEDIFF(QUARTER, 0, @ReferenceDate) - 1, 0)
        WHEN 'ThisYear' THEN DATEFROMPARTS(YEAR(@ReferenceDate), 1, 1)
        WHEN 'LastYear' THEN DATEFROMPARTS(YEAR(@ReferenceDate) - 1, 1, 1)
        WHEN 'Last7Days' THEN DATEADD(DAY, -6, @ReferenceDate)
        WHEN 'Last30Days' THEN DATEADD(DAY, -29, @ReferenceDate)
        WHEN 'Last90Days' THEN DATEADD(DAY, -89, @ReferenceDate)
        WHEN 'Last365Days' THEN DATEADD(DAY, -364, @ReferenceDate)
        ELSE @ReferenceDate
    END;
    
    SELECT @EndDate = CASE @RangeType
        WHEN 'Today' THEN @ReferenceDate
        WHEN 'Yesterday' THEN DATEADD(DAY, -1, @ReferenceDate)
        WHEN 'ThisWeek' THEN DATEADD(DAY, 7 - DATEPART(WEEKDAY, @ReferenceDate), @ReferenceDate)
        WHEN 'LastWeek' THEN DATEADD(DAY, 7 - DATEPART(WEEKDAY, @ReferenceDate) - 7, @ReferenceDate)
        WHEN 'ThisMonth' THEN EOMONTH(@ReferenceDate)
        WHEN 'LastMonth' THEN DATEADD(DAY, -1, DATEFROMPARTS(YEAR(@ReferenceDate), MONTH(@ReferenceDate), 1))
        WHEN 'ThisQuarter' THEN DATEADD(DAY, -1, DATEADD(QUARTER, DATEDIFF(QUARTER, 0, @ReferenceDate) + 1, 0))
        WHEN 'LastQuarter' THEN DATEADD(DAY, -1, DATEADD(QUARTER, DATEDIFF(QUARTER, 0, @ReferenceDate), 0))
        WHEN 'ThisYear' THEN DATEFROMPARTS(YEAR(@ReferenceDate), 12, 31)
        WHEN 'LastYear' THEN DATEFROMPARTS(YEAR(@ReferenceDate) - 1, 12, 31)
        WHEN 'Last7Days' THEN @ReferenceDate
        WHEN 'Last30Days' THEN @ReferenceDate
        WHEN 'Last90Days' THEN @ReferenceDate
        WHEN 'Last365Days' THEN @ReferenceDate
        ELSE @ReferenceDate
    END;
END
GO

-- Get period-over-period comparison dates
CREATE PROCEDURE dbo.GetComparisonPeriod
    @StartDate DATE,
    @EndDate DATE,
    @ComparisonType NVARCHAR(50),  -- PriorPeriod, PriorYear, PriorMonth, PriorWeek
    @CompStartDate DATE OUTPUT,
    @CompEndDate DATE OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @DaysDiff INT = DATEDIFF(DAY, @StartDate, @EndDate);
    
    SELECT 
        @CompStartDate = CASE @ComparisonType
            WHEN 'PriorPeriod' THEN DATEADD(DAY, -@DaysDiff - 1, @StartDate)
            WHEN 'PriorYear' THEN DATEADD(YEAR, -1, @StartDate)
            WHEN 'PriorMonth' THEN DATEADD(MONTH, -1, @StartDate)
            WHEN 'PriorWeek' THEN DATEADD(WEEK, -1, @StartDate)
            ELSE DATEADD(DAY, -@DaysDiff - 1, @StartDate)
        END,
        @CompEndDate = CASE @ComparisonType
            WHEN 'PriorPeriod' THEN DATEADD(DAY, -1, @StartDate)
            WHEN 'PriorYear' THEN DATEADD(YEAR, -1, @EndDate)
            WHEN 'PriorMonth' THEN DATEADD(MONTH, -1, @EndDate)
            WHEN 'PriorWeek' THEN DATEADD(WEEK, -1, @EndDate)
            ELSE DATEADD(DAY, -1, @StartDate)
        END;
END
GO
