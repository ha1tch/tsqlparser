-- Sample 135: Date and Time Functions Comprehensive Coverage
-- Category: Pure Logic / Syntax Coverage
-- Complexity: Complex
-- Purpose: Parser testing - all date/time functions
-- Features: All T-SQL date/time functions, patterns, calculations

-- Pattern 1: Current date/time functions
SELECT 
    GETDATE() AS GetDate,
    GETUTCDATE() AS GetUtcDate,
    SYSDATETIME() AS SysDateTime,
    SYSUTCDATETIME() AS SysUtcDateTime,
    SYSDATETIMEOFFSET() AS SysDateTimeOffset,
    CURRENT_TIMESTAMP AS CurrentTimestamp;
GO

-- Pattern 2: Date construction functions
SELECT 
    DATEFROMPARTS(2024, 6, 15) AS DateFromParts,
    DATETIME2FROMPARTS(2024, 6, 15, 14, 30, 45, 123456, 6) AS DateTime2FromParts,
    DATETIMEFROMPARTS(2024, 6, 15, 14, 30, 45, 500) AS DateTimeFromParts,
    DATETIMEOFFSETFROMPARTS(2024, 6, 15, 14, 30, 45, 0, 5, 30, 0) AS DateTimeOffsetFromParts,
    SMALLDATETIMEFROMPARTS(2024, 6, 15, 14, 30) AS SmallDateTimeFromParts,
    TIMEFROMPARTS(14, 30, 45, 123456, 6) AS TimeFromParts;
GO

-- Pattern 3: DATEPART function with all parts
DECLARE @dt DATETIME2 = '2024-06-15 14:30:45.1234567';
SELECT 
    DATEPART(YEAR, @dt) AS Year,
    DATEPART(QUARTER, @dt) AS Quarter,
    DATEPART(MONTH, @dt) AS Month,
    DATEPART(DAYOFYEAR, @dt) AS DayOfYear,
    DATEPART(DAY, @dt) AS Day,
    DATEPART(WEEK, @dt) AS Week,
    DATEPART(WEEKDAY, @dt) AS Weekday,
    DATEPART(HOUR, @dt) AS Hour,
    DATEPART(MINUTE, @dt) AS Minute,
    DATEPART(SECOND, @dt) AS Second,
    DATEPART(MILLISECOND, @dt) AS Millisecond,
    DATEPART(MICROSECOND, @dt) AS Microsecond,
    DATEPART(NANOSECOND, @dt) AS Nanosecond,
    DATEPART(ISO_WEEK, @dt) AS ISOWeek;
GO

-- Pattern 4: DATENAME function
DECLARE @dt DATETIME2 = '2024-06-15 14:30:45';
SELECT 
    DATENAME(YEAR, @dt) AS Year,
    DATENAME(MONTH, @dt) AS MonthName,
    DATENAME(WEEKDAY, @dt) AS DayName,
    DATENAME(DAYOFYEAR, @dt) AS DayOfYear;
GO

-- Pattern 5: Shorthand date functions
SELECT 
    YEAR(GETDATE()) AS CurrentYear,
    MONTH(GETDATE()) AS CurrentMonth,
    DAY(GETDATE()) AS CurrentDay;
GO

-- Pattern 6: DATEADD with all intervals
DECLARE @dt DATETIME2 = '2024-06-15 14:30:45';
SELECT 
    DATEADD(YEAR, 1, @dt) AS AddYear,
    DATEADD(QUARTER, 1, @dt) AS AddQuarter,
    DATEADD(MONTH, 1, @dt) AS AddMonth,
    DATEADD(DAYOFYEAR, 1, @dt) AS AddDayOfYear,
    DATEADD(DAY, 1, @dt) AS AddDay,
    DATEADD(WEEK, 1, @dt) AS AddWeek,
    DATEADD(WEEKDAY, 1, @dt) AS AddWeekday,
    DATEADD(HOUR, 1, @dt) AS AddHour,
    DATEADD(MINUTE, 30, @dt) AS AddMinute,
    DATEADD(SECOND, 30, @dt) AS AddSecond,
    DATEADD(MILLISECOND, 500, @dt) AS AddMillisecond,
    DATEADD(MICROSECOND, 500, @dt) AS AddMicrosecond,
    DATEADD(NANOSECOND, 500, @dt) AS AddNanosecond;
GO

-- Pattern 7: DATEDIFF and DATEDIFF_BIG
DECLARE @d1 DATETIME2 = '2020-01-01';
DECLARE @d2 DATETIME2 = '2024-06-15 14:30:45';
SELECT 
    DATEDIFF(YEAR, @d1, @d2) AS DiffYears,
    DATEDIFF(MONTH, @d1, @d2) AS DiffMonths,
    DATEDIFF(DAY, @d1, @d2) AS DiffDays,
    DATEDIFF(HOUR, @d1, @d2) AS DiffHours,
    DATEDIFF(MINUTE, @d1, @d2) AS DiffMinutes,
    DATEDIFF(SECOND, @d1, @d2) AS DiffSeconds,
    DATEDIFF_BIG(MILLISECOND, @d1, @d2) AS DiffMilliseconds,
    DATEDIFF_BIG(MICROSECOND, @d1, @d2) AS DiffMicroseconds;
GO

-- Pattern 8: DATETRUNC function (SQL Server 2022+)
DECLARE @dt DATETIME2 = '2024-06-15 14:30:45.1234567';
SELECT 
    DATETRUNC(YEAR, @dt) AS TruncYear,
    DATETRUNC(QUARTER, @dt) AS TruncQuarter,
    DATETRUNC(MONTH, @dt) AS TruncMonth,
    DATETRUNC(WEEK, @dt) AS TruncWeek,
    DATETRUNC(DAY, @dt) AS TruncDay,
    DATETRUNC(HOUR, @dt) AS TruncHour,
    DATETRUNC(MINUTE, @dt) AS TruncMinute;
GO

-- Pattern 9: EOMONTH function
SELECT 
    EOMONTH(GETDATE()) AS EndOfCurrentMonth,
    EOMONTH(GETDATE(), 1) AS EndOfNextMonth,
    EOMONTH(GETDATE(), -1) AS EndOfLastMonth,
    EOMONTH('2024-02-15') AS EndOfFeb2024;  -- 2024 is leap year
GO

-- Pattern 10: ISDATE validation
SELECT 
    ISDATE('2024-06-15') AS ValidDate,
    ISDATE('2024-02-30') AS InvalidDate,
    ISDATE('20240615') AS CompactDate,
    ISDATE('not a date') AS TextNotDate,
    ISDATE(NULL) AS NullDate;
GO

-- Pattern 11: Date formatting with CONVERT styles
DECLARE @dt DATETIME = '2024-06-15 14:30:45';
SELECT 
    CONVERT(VARCHAR(10), @dt, 101) AS US_mmddyyyy,
    CONVERT(VARCHAR(10), @dt, 103) AS UK_ddmmyyyy,
    CONVERT(VARCHAR(10), @dt, 104) AS German_ddmmyyyy,
    CONVERT(VARCHAR(10), @dt, 111) AS Japan_yyyymmdd,
    CONVERT(VARCHAR(10), @dt, 112) AS ISO_yyyymmdd,
    CONVERT(VARCHAR(19), @dt, 120) AS ODBC_yyyy_mm_dd,
    CONVERT(VARCHAR(23), @dt, 121) AS ODBC_with_ms,
    CONVERT(VARCHAR(25), @dt, 126) AS ISO8601;
GO

-- Pattern 12: Date formatting with FORMAT function
SELECT 
    FORMAT(GETDATE(), 'd') AS ShortDate,
    FORMAT(GETDATE(), 'D') AS LongDate,
    FORMAT(GETDATE(), 'f') AS FullDateTime,
    FORMAT(GETDATE(), 'yyyy-MM-dd') AS CustomYMD,
    FORMAT(GETDATE(), 'dd/MM/yyyy HH:mm:ss') AS CustomDMYHMS,
    FORMAT(GETDATE(), 'MMMM dd, yyyy') AS MonthNameDayYear,
    FORMAT(GETDATE(), 'ddd, MMM d, yyyy') AS AbbrevDayMonth;
GO

-- Pattern 13: Date arithmetic patterns
DECLARE @dt DATE = '2024-06-15';
SELECT 
    @dt AS OriginalDate,
    DATEADD(DAY, -DATEPART(WEEKDAY, @dt) + 1, @dt) AS StartOfWeek,
    DATEADD(DAY, -DAY(@dt) + 1, @dt) AS StartOfMonth,
    DATEFROMPARTS(YEAR(@dt), 1, 1) AS StartOfYear,
    DATEFROMPARTS(YEAR(@dt), ((MONTH(@dt)-1)/3)*3+1, 1) AS StartOfQuarter,
    EOMONTH(@dt) AS EndOfMonth,
    DATEFROMPARTS(YEAR(@dt), 12, 31) AS EndOfYear;
GO

-- Pattern 14: Working day calculations
DECLARE @startDate DATE = '2024-06-01';
DECLARE @endDate DATE = '2024-06-30';
SELECT 
    (DATEDIFF(DAY, @startDate, @endDate) + 1)
    - (DATEDIFF(WEEK, @startDate, @endDate) * 2)
    - (CASE WHEN DATENAME(WEEKDAY, @startDate) = 'Sunday' THEN 1 ELSE 0 END)
    - (CASE WHEN DATENAME(WEEKDAY, @endDate) = 'Saturday' THEN 1 ELSE 0 END)
    AS BusinessDays;
GO

-- Pattern 15: Age calculation
DECLARE @birthDate DATE = '1990-06-15';
DECLARE @asOfDate DATE = '2024-06-14';
SELECT 
    DATEDIFF(YEAR, @birthDate, @asOfDate) 
    - CASE 
        WHEN DATEADD(YEAR, DATEDIFF(YEAR, @birthDate, @asOfDate), @birthDate) > @asOfDate 
        THEN 1 
        ELSE 0 
      END AS AgeInYears;
GO

-- Pattern 16: Date overlap detection
DECLARE @start1 DATE = '2024-01-01', @end1 DATE = '2024-06-30';
DECLARE @start2 DATE = '2024-04-01', @end2 DATE = '2024-12-31';
SELECT 
    CASE WHEN @start1 <= @end2 AND @end1 >= @start2 THEN 'Overlaps' ELSE 'No Overlap' END AS OverlapStatus,
    CASE WHEN @start1 <= @end2 AND @end1 >= @start2 
         THEN DATEDIFF(DAY, 
              CASE WHEN @start1 > @start2 THEN @start1 ELSE @start2 END,
              CASE WHEN @end1 < @end2 THEN @end1 ELSE @end2 END) + 1
         ELSE 0 
    END AS OverlapDays;
GO

-- Pattern 17: Fiscal year calculations
DECLARE @fiscalYearStart INT = 4;  -- April
DECLARE @dt DATE = '2024-06-15';
SELECT 
    CASE 
        WHEN MONTH(@dt) >= @fiscalYearStart THEN YEAR(@dt)
        ELSE YEAR(@dt) - 1
    END AS FiscalYear,
    CASE 
        WHEN MONTH(@dt) >= @fiscalYearStart THEN MONTH(@dt) - @fiscalYearStart + 1
        ELSE MONTH(@dt) + 12 - @fiscalYearStart + 1
    END AS FiscalMonth;
GO

-- Pattern 18: Time zone conversion
SELECT 
    GETDATE() AS LocalTime,
    GETDATE() AT TIME ZONE 'UTC' AS LocalAsUTC,
    SYSDATETIMEOFFSET() AT TIME ZONE 'Pacific Standard Time' AS Pacific,
    CAST(GETDATE() AS DATETIMEOFFSET) AT TIME ZONE 'Eastern Standard Time' AS Eastern;
GO

-- Pattern 19: SWITCHOFFSET and TODATETIMEOFFSET
SELECT 
    SYSDATETIMEOFFSET() AS Current,
    SWITCHOFFSET(SYSDATETIMEOFFSET(), '+00:00') AS SwitchedToUTC,
    TODATETIMEOFFSET(GETDATE(), '-05:00') AS WithESTOffset;
GO

-- Pattern 20: Date literals and parsing
SELECT 
    CAST('2024-06-15' AS DATE) AS ISODate,
    CAST('06/15/2024' AS DATE) AS USDate,
    CAST('15/06/2024' AS DATE) AS EuroDate,  -- Depends on settings
    CAST('June 15, 2024' AS DATE) AS TextDate,
    PARSE('15 June 2024' AS DATE USING 'en-GB') AS ParsedDate,
    TRY_PARSE('invalid' AS DATE) AS TryParseInvalid,
    TRY_CONVERT(DATE, 'invalid') AS TryConvertInvalid;
GO
