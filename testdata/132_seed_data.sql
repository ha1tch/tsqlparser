-- Sample 132: Test Data Seed Scripts
-- Category: Schema and Test Data Scripts
-- Complexity: Intermediate
-- Purpose: Parser testing - data seeding patterns for testing
-- Features: Multi-row INSERT, INSERT EXEC, data generation patterns

-- Pattern 1: Multi-row INSERT for reference data
INSERT INTO dbo.Countries (CountryCode, CountryName, Region, CurrencyCode)
VALUES 
    ('US', 'United States', 'North America', 'USD'),
    ('CA', 'Canada', 'North America', 'CAD'),
    ('MX', 'Mexico', 'North America', 'MXN'),
    ('GB', 'United Kingdom', 'Europe', 'GBP'),
    ('DE', 'Germany', 'Europe', 'EUR'),
    ('FR', 'France', 'Europe', 'EUR'),
    ('JP', 'Japan', 'Asia', 'JPY'),
    ('CN', 'China', 'Asia', 'CNY'),
    ('AU', 'Australia', 'Oceania', 'AUD'),
    ('BR', 'Brazil', 'South America', 'BRL');
GO

-- Pattern 2: Status lookup table
INSERT INTO dbo.OrderStatuses (StatusCode, StatusName, DisplayOrder, IsActive, AllowsEdit)
VALUES 
    ('NEW', 'New Order', 1, 1, 1),
    ('PND', 'Pending', 2, 1, 1),
    ('APR', 'Approved', 3, 1, 1),
    ('PRO', 'Processing', 4, 1, 0),
    ('SHP', 'Shipped', 5, 1, 0),
    ('DLV', 'Delivered', 6, 1, 0),
    ('CAN', 'Cancelled', 7, 1, 0),
    ('RET', 'Returned', 8, 1, 0),
    ('REF', 'Refunded', 9, 1, 0),
    ('ARC', 'Archived', 10, 0, 0);
GO

-- Pattern 3: Category hierarchy
INSERT INTO dbo.Categories (CategoryID, CategoryName, ParentCategoryID, Level, SortOrder)
VALUES 
    (1, 'Electronics', NULL, 0, 1),
    (2, 'Computers', 1, 1, 1),
    (3, 'Laptops', 2, 2, 1),
    (4, 'Desktops', 2, 2, 2),
    (5, 'Tablets', 2, 2, 3),
    (6, 'Phones', 1, 1, 2),
    (7, 'Smartphones', 6, 2, 1),
    (8, 'Accessories', 6, 2, 2),
    (10, 'Clothing', NULL, 0, 2),
    (11, 'Men', 10, 1, 1),
    (12, 'Women', 10, 1, 2),
    (13, 'Children', 10, 1, 3),
    (20, 'Home & Garden', NULL, 0, 3),
    (21, 'Furniture', 20, 1, 1),
    (22, 'Kitchen', 20, 1, 2);
GO

-- Pattern 4: Generate sequential test customers
;WITH Numbers AS (
    SELECT 1 AS N
    UNION ALL
    SELECT N + 1 FROM Numbers WHERE N < 100
)
INSERT INTO dbo.Customers (CustomerCode, FirstName, LastName, Email, Phone, CreatedDate)
SELECT 
    'CUST' + RIGHT('0000' + CAST(N AS VARCHAR(4)), 4),
    'FirstName' + CAST(N AS VARCHAR(10)),
    'LastName' + CAST(N AS VARCHAR(10)),
    'customer' + CAST(N AS VARCHAR(10)) + '@example.com',
    '555-' + RIGHT('0000' + CAST(N AS VARCHAR(4)), 4),
    DATEADD(DAY, -N, GETDATE())
FROM Numbers
OPTION (MAXRECURSION 100);
GO

-- Pattern 5: Products with varied prices
INSERT INTO dbo.Products (ProductCode, ProductName, CategoryID, UnitPrice, StockQuantity, ReorderLevel)
VALUES
    ('PROD001', 'Basic Widget', 3, 9.99, 100, 20),
    ('PROD002', 'Standard Widget', 3, 19.99, 75, 15),
    ('PROD003', 'Premium Widget', 3, 49.99, 50, 10),
    ('PROD004', 'Deluxe Widget', 3, 99.99, 25, 5),
    ('PROD005', 'Ultra Widget', 3, 199.99, 10, 3),
    ('PROD006', 'Basic Gadget', 4, 14.99, 200, 40),
    ('PROD007', 'Standard Gadget', 4, 29.99, 150, 30),
    ('PROD008', 'Premium Gadget', 4, 59.99, 100, 20),
    ('PROD009', 'Phone Case', 8, 12.99, 500, 100),
    ('PROD010', 'Screen Protector', 8, 7.99, 750, 150);
GO

-- Pattern 6: Generate random orders (using NEWID for randomization)
;WITH 
CustomerIDs AS (
    SELECT CustomerID, ROW_NUMBER() OVER (ORDER BY NEWID()) AS RN
    FROM dbo.Customers
),
OrderDates AS (
    SELECT DATEADD(DAY, -N, GETDATE()) AS OrderDate
    FROM (SELECT TOP 365 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS N FROM sys.objects) AS Days
)
INSERT INTO dbo.Orders (CustomerID, OrderDate, Status, TotalAmount)
SELECT TOP 500
    c.CustomerID,
    d.OrderDate,
    CASE ABS(CHECKSUM(NEWID())) % 5
        WHEN 0 THEN 'Pending'
        WHEN 1 THEN 'Processing'
        WHEN 2 THEN 'Shipped'
        WHEN 3 THEN 'Delivered'
        ELSE 'Completed'
    END,
    CAST(10 + (ABS(CHECKSUM(NEWID())) % 990) + (ABS(CHECKSUM(NEWID())) % 100) / 100.0 AS DECIMAL(10,2))
FROM CustomerIDs c
CROSS JOIN OrderDates d
WHERE c.RN <= 50
ORDER BY NEWID();
GO

-- Pattern 7: Generate order details
INSERT INTO dbo.OrderDetails (OrderID, ProductID, Quantity, UnitPrice, Discount)
SELECT 
    o.OrderID,
    p.ProductID,
    1 + ABS(CHECKSUM(NEWID())) % 5 AS Quantity,
    p.UnitPrice,
    CASE WHEN ABS(CHECKSUM(NEWID())) % 10 = 0 THEN 10.00 ELSE 0.00 END AS Discount
FROM dbo.Orders o
CROSS APPLY (
    SELECT TOP (1 + ABS(CHECKSUM(NEWID())) % 3) ProductID, UnitPrice
    FROM dbo.Products
    ORDER BY NEWID()
) AS p;
GO

-- Pattern 8: Date dimension table population
;WITH Dates AS (
    SELECT CAST('2020-01-01' AS DATE) AS DateValue
    UNION ALL
    SELECT DATEADD(DAY, 1, DateValue)
    FROM Dates
    WHERE DateValue < '2025-12-31'
)
INSERT INTO dbo.DimDate (
    DateKey, FullDate, DayOfWeek, DayName, DayOfMonth, DayOfYear,
    WeekOfYear, MonthNumber, MonthName, Quarter, Year, IsWeekend, IsHoliday
)
SELECT 
    CAST(CONVERT(VARCHAR(8), DateValue, 112) AS INT) AS DateKey,
    DateValue AS FullDate,
    DATEPART(WEEKDAY, DateValue) AS DayOfWeek,
    DATENAME(WEEKDAY, DateValue) AS DayName,
    DAY(DateValue) AS DayOfMonth,
    DATEPART(DAYOFYEAR, DateValue) AS DayOfYear,
    DATEPART(WEEK, DateValue) AS WeekOfYear,
    MONTH(DateValue) AS MonthNumber,
    DATENAME(MONTH, DateValue) AS MonthName,
    DATEPART(QUARTER, DateValue) AS Quarter,
    YEAR(DateValue) AS Year,
    CASE WHEN DATEPART(WEEKDAY, DateValue) IN (1, 7) THEN 1 ELSE 0 END AS IsWeekend,
    0 AS IsHoliday
FROM Dates
OPTION (MAXRECURSION 2200);
GO

-- Pattern 9: Configuration/settings seed data
INSERT INTO dbo.AppSettings (SettingKey, SettingValue, DataType, Description, IsEncrypted)
VALUES
    ('App.Name', 'MyApplication', 'string', 'Application name', 0),
    ('App.Version', '1.0.0', 'string', 'Application version', 0),
    ('App.MaxPageSize', '100', 'int', 'Maximum page size for pagination', 0),
    ('App.DefaultPageSize', '25', 'int', 'Default page size', 0),
    ('Email.SmtpServer', 'smtp.example.com', 'string', 'SMTP server address', 0),
    ('Email.SmtpPort', '587', 'int', 'SMTP port', 0),
    ('Email.FromAddress', 'noreply@example.com', 'string', 'Default from address', 0),
    ('Security.TokenExpiry', '3600', 'int', 'Token expiry in seconds', 0),
    ('Security.MaxLoginAttempts', '5', 'int', 'Max failed login attempts', 0),
    ('Feature.EnableAudit', 'true', 'bool', 'Enable audit logging', 0);
GO

-- Pattern 10: Permission/role seed data
INSERT INTO dbo.Roles (RoleName, Description, IsSystemRole)
VALUES
    ('Administrator', 'Full system access', 1),
    ('Manager', 'Management access', 0),
    ('User', 'Standard user access', 0),
    ('ReadOnly', 'Read-only access', 0),
    ('Guest', 'Limited guest access', 0);

INSERT INTO dbo.Permissions (PermissionCode, PermissionName, Category)
VALUES
    ('USER_CREATE', 'Create Users', 'Users'),
    ('USER_READ', 'View Users', 'Users'),
    ('USER_UPDATE', 'Update Users', 'Users'),
    ('USER_DELETE', 'Delete Users', 'Users'),
    ('ORDER_CREATE', 'Create Orders', 'Orders'),
    ('ORDER_READ', 'View Orders', 'Orders'),
    ('ORDER_UPDATE', 'Update Orders', 'Orders'),
    ('ORDER_DELETE', 'Delete Orders', 'Orders'),
    ('REPORT_VIEW', 'View Reports', 'Reports'),
    ('REPORT_EXPORT', 'Export Reports', 'Reports'),
    ('ADMIN_SETTINGS', 'Manage Settings', 'Admin'),
    ('ADMIN_USERS', 'Manage Users', 'Admin');

INSERT INTO dbo.RolePermissions (RoleID, PermissionID)
SELECT r.RoleID, p.PermissionID
FROM dbo.Roles r
CROSS JOIN dbo.Permissions p
WHERE r.RoleName = 'Administrator'
UNION ALL
SELECT r.RoleID, p.PermissionID
FROM dbo.Roles r
INNER JOIN dbo.Permissions p ON p.PermissionCode LIKE '%_READ' OR p.PermissionCode LIKE '%_VIEW'
WHERE r.RoleName = 'ReadOnly';
GO

-- Pattern 11: Cleanup and reseed (for test reset)
-- TRUNCATE TABLE dbo.OrderDetails;
-- TRUNCATE TABLE dbo.Orders;
-- DELETE FROM dbo.Customers;
-- DBCC CHECKIDENT('dbo.Customers', RESEED, 0);
-- DBCC CHECKIDENT('dbo.Orders', RESEED, 0);
GO
