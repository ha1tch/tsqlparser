-- Sample 116: AT TIME ZONE and DateTime Conversions
-- Category: Missing Syntax Elements
-- Complexity: Complex
-- Purpose: Parser testing - timezone handling and datetime operations
-- Features: AT TIME ZONE, DATETIMEOFFSET, timezone conversions, DST handling

-- Pattern 1: Basic AT TIME ZONE conversions
SELECT 
    GETDATE() AS LocalTime,
    GETDATE() AT TIME ZONE 'UTC' AS LocalAsUTC,
    GETDATE() AT TIME ZONE 'Pacific Standard Time' AS LocalAsPacific,
    GETDATE() AT TIME ZONE 'Eastern Standard Time' AS LocalAsEastern,
    GETDATE() AT TIME ZONE 'Central European Standard Time' AS LocalAsCET;
GO

-- Pattern 2: Converting between time zones
SELECT 
    SYSDATETIMEOFFSET() AS CurrentWithOffset,
    SYSDATETIMEOFFSET() AT TIME ZONE 'UTC' AS ConvertedToUTC,
    SYSDATETIMEOFFSET() AT TIME ZONE 'Tokyo Standard Time' AS ConvertedToTokyo,
    SYSDATETIMEOFFSET() AT TIME ZONE 'GMT Standard Time' AS ConvertedToGMT;
GO

-- Pattern 3: Double AT TIME ZONE (chain conversion)
SELECT 
    '2024-06-15 12:00:00' AT TIME ZONE 'UTC' AT TIME ZONE 'Pacific Standard Time' AS UTCToPacific,
    '2024-06-15 12:00:00' AT TIME ZONE 'Eastern Standard Time' AT TIME ZONE 'UTC' AS EasternToUTC,
    '2024-01-15 12:00:00' AT TIME ZONE 'Pacific Standard Time' AT TIME ZONE 'Eastern Standard Time' AS PacificToEastern;
GO

-- Pattern 4: DATETIMEOFFSET literals and operations
DECLARE @dto1 DATETIMEOFFSET = '2024-06-15 14:30:00.0000000 +05:30';
DECLARE @dto2 DATETIMEOFFSET = '2024-06-15 14:30:00.0000000 -08:00';
DECLARE @dto3 DATETIMEOFFSET = '2024-06-15T14:30:00+00:00';

SELECT 
    @dto1 AS IndiaTime,
    @dto2 AS PacificTime,
    @dto3 AS UTCTime,
    DATEDIFF(HOUR, @dto1, @dto2) AS HourDifference,
    SWITCHOFFSET(@dto1, '-08:00') AS SwitchedToPacific,
    TODATETIMEOFFSET(GETDATE(), '+00:00') AS LocalToUTCOffset;
GO

-- Pattern 5: Time zone names with spaces and special characters
SELECT 
    GETDATE() AT TIME ZONE 'Alaskan Standard Time' AS Alaska,
    GETDATE() AT TIME ZONE 'Hawaiian Standard Time' AS Hawaii,
    GETDATE() AT TIME ZONE 'Mountain Standard Time' AS Mountain,
    GETDATE() AT TIME ZONE 'Central Standard Time' AS Central,
    GETDATE() AT TIME ZONE 'Atlantic Standard Time' AS Atlantic,
    GETDATE() AT TIME ZONE 'Newfoundland Standard Time' AS Newfoundland,
    GETDATE() AT TIME ZONE 'Argentina Standard Time' AS Argentina,
    GETDATE() AT TIME ZONE 'New Zealand Standard Time' AS NewZealand,
    GETDATE() AT TIME ZONE 'India Standard Time' AS India,
    GETDATE() AT TIME ZONE 'China Standard Time' AS China;
GO

-- Pattern 6: DST handling (summer vs winter)
SELECT 
    -- Winter time (Standard Time)
    '2024-01-15 12:00:00' AT TIME ZONE 'Pacific Standard Time' AS WinterPacific,
    '2024-01-15 12:00:00' AT TIME ZONE 'Eastern Standard Time' AS WinterEastern,
    
    -- Summer time (Daylight Saving Time)
    '2024-06-15 12:00:00' AT TIME ZONE 'Pacific Standard Time' AS SummerPacific,  -- Actually PDT
    '2024-06-15 12:00:00' AT TIME ZONE 'Eastern Standard Time' AS SummerEastern;  -- Actually EDT
GO

-- Pattern 7: AT TIME ZONE in expressions and functions
SELECT 
    OrderID,
    OrderDate,
    OrderDate AT TIME ZONE 'UTC' AS OrderDateUTC,
    OrderDate AT TIME ZONE 'UTC' AT TIME ZONE 'Pacific Standard Time' AS OrderDatePacific,
    CAST(OrderDate AT TIME ZONE 'UTC' AS DATE) AS OrderDateOnly,
    DATEPART(HOUR, OrderDate AT TIME ZONE 'UTC') AS UTCHour,
    DATEDIFF(HOUR, OrderDate AT TIME ZONE 'UTC', SYSDATETIMEOFFSET()) AS HoursAgo
FROM Orders
WHERE OrderDate AT TIME ZONE 'UTC' >= '2024-01-01 00:00:00 +00:00';
GO

-- Pattern 8: Variable time zone
DECLARE @UserTimeZone NVARCHAR(100) = 'Pacific Standard Time';
DECLARE @EventTimeUTC DATETIME2 = '2024-06-15 18:00:00';

SELECT 
    @EventTimeUTC AS EventUTC,
    @EventTimeUTC AT TIME ZONE 'UTC' AT TIME ZONE @UserTimeZone AS EventLocalTime;
GO

-- Pattern 9: SWITCHOFFSET function
SELECT 
    SYSDATETIMEOFFSET() AS Current,
    SWITCHOFFSET(SYSDATETIMEOFFSET(), '+00:00') AS SwitchedToUTC,
    SWITCHOFFSET(SYSDATETIMEOFFSET(), '-05:00') AS SwitchedToEST,
    SWITCHOFFSET(SYSDATETIMEOFFSET(), '+05:30') AS SwitchedToIST,
    SWITCHOFFSET(SYSDATETIMEOFFSET(), '+09:00') AS SwitchedToJST;
GO

-- Pattern 10: TODATETIMEOFFSET function
SELECT 
    GETDATE() AS LocalDateTime,
    TODATETIMEOFFSET(GETDATE(), '+00:00') AS AsUTCOffset,
    TODATETIMEOFFSET(GETDATE(), '-08:00') AS AsPacificOffset,
    TODATETIMEOFFSET(GETDATE(), DATENAME(TZOFFSET, SYSDATETIMEOFFSET())) AS WithLocalOffset;
GO

-- Pattern 11: Extracting offset information
DECLARE @dto DATETIMEOFFSET = SYSDATETIMEOFFSET();

SELECT 
    @dto AS FullValue,
    DATEPART(TZOFFSET, @dto) AS OffsetMinutes,
    DATEPART(TZOFFSET, @dto) / 60 AS OffsetHours,
    DATENAME(TZOFFSET, @dto) AS OffsetString,
    CAST(@dto AS DATETIME2) AS WithoutOffset,
    CAST(@dto AS DATE) AS DateOnly,
    CAST(@dto AS TIME) AS TimeOnly;
GO

-- Pattern 12: Time zone in table column
CREATE TABLE #EventsWithTimeZone (
    EventID INT IDENTITY(1,1),
    EventName NVARCHAR(100),
    EventTimeUTC DATETIME2,
    EventTimeZone NVARCHAR(100),
    CreatedAt DATETIMEOFFSET DEFAULT SYSDATETIMEOFFSET()
);

INSERT INTO #EventsWithTimeZone (EventName, EventTimeUTC, EventTimeZone)
VALUES 
    ('Conference Call', '2024-06-15 14:00:00', 'Eastern Standard Time'),
    ('Product Launch', '2024-06-20 09:00:00', 'Pacific Standard Time'),
    ('Webinar', '2024-06-25 16:00:00', 'UTC');

SELECT 
    EventID,
    EventName,
    EventTimeUTC,
    EventTimeZone,
    EventTimeUTC AT TIME ZONE 'UTC' AT TIME ZONE EventTimeZone AS LocalEventTime
FROM #EventsWithTimeZone;

DROP TABLE #EventsWithTimeZone;
GO

-- Pattern 13: AT TIME ZONE with aggregates
SELECT 
    CAST(OrderDate AT TIME ZONE 'UTC' AT TIME ZONE 'Pacific Standard Time' AS DATE) AS OrderDatePacific,
    COUNT(*) AS OrderCount,
    SUM(TotalAmount) AS TotalRevenue
FROM Orders
GROUP BY CAST(OrderDate AT TIME ZONE 'UTC' AT TIME ZONE 'Pacific Standard Time' AS DATE)
ORDER BY OrderDatePacific;
GO

-- Pattern 14: Current time in multiple zones (dashboard style)
SELECT 
    'UTC' AS TimeZone, CAST(SYSDATETIMEOFFSET() AT TIME ZONE 'UTC' AS TIME) AS CurrentTime
UNION ALL
SELECT 'New York', CAST(SYSDATETIMEOFFSET() AT TIME ZONE 'Eastern Standard Time' AS TIME)
UNION ALL
SELECT 'Los Angeles', CAST(SYSDATETIMEOFFSET() AT TIME ZONE 'Pacific Standard Time' AS TIME)
UNION ALL
SELECT 'London', CAST(SYSDATETIMEOFFSET() AT TIME ZONE 'GMT Standard Time' AS TIME)
UNION ALL
SELECT 'Tokyo', CAST(SYSDATETIMEOFFSET() AT TIME ZONE 'Tokyo Standard Time' AS TIME)
UNION ALL
SELECT 'Sydney', CAST(SYSDATETIMEOFFSET() AT TIME ZONE 'AUS Eastern Standard Time' AS TIME);
GO
