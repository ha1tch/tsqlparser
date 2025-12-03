-- Sample 110: Unicode Identifiers and Special Characters
-- Category: Syntax Edge Cases
-- Complexity: Complex
-- Purpose: Parser testing - Unicode and special character handling
-- Features: Unicode table/column names, special characters, escaped identifiers

-- Pattern 1: Unicode table and column names (Chinese)
CREATE TABLE [北京销售数据] (
    [记录编号] INT IDENTITY(1,1) PRIMARY KEY,
    [客户名称] NVARCHAR(100) NOT NULL,
    [销售金额] DECIMAL(18,2),
    [销售日期] DATE,
    [备注] NVARCHAR(500)
);
GO

INSERT INTO [北京销售数据] ([客户名称], [销售金额], [销售日期])
VALUES 
    (N'张三公司', 15000.00, '2024-01-15'),
    (N'李四集团', 28000.00, '2024-01-20'),
    (N'王五贸易', 9500.00, '2024-01-25');
GO

SELECT [记录编号], [客户名称], [销售金额]
FROM [北京销售数据]
WHERE [销售金额] > 10000
ORDER BY [销售日期];
GO

-- Pattern 2: Unicode identifiers (Russian)
CREATE TABLE [Продажи] (
    [ИД] INT IDENTITY(1,1) PRIMARY KEY,
    [Клиент] NVARCHAR(100),
    [Сумма] DECIMAL(18,2),
    [Дата] DATE,
    [Статус] NVARCHAR(50)
);
GO

SELECT [ИД], [Клиент], [Сумма]
FROM [Продажи]
WHERE [Статус] = N'Завершено';
GO

-- Pattern 3: Unicode identifiers (Japanese)
CREATE TABLE [日本語テーブル] (
    [識別子] INT IDENTITY(1,1) PRIMARY KEY,
    [顧客名] NVARCHAR(100),
    [売上高] DECIMAL(18,2),
    [日付] DATE
);
GO

SELECT [識別子], [顧客名], [売上高]
FROM [日本語テーブル]
ORDER BY [日付] DESC;
GO

-- Pattern 4: Unicode identifiers (Arabic)
CREATE TABLE [جدول_المبيعات] (
    [رقم] INT IDENTITY(1,1) PRIMARY KEY,
    [اسم_العميل] NVARCHAR(100),
    [المبلغ] DECIMAL(18,2),
    [التاريخ] DATE
);
GO

-- Pattern 5: Unicode identifiers (Korean)
CREATE TABLE [판매데이터] (
    [번호] INT IDENTITY(1,1) PRIMARY KEY,
    [고객명] NVARCHAR(100),
    [매출액] DECIMAL(18,2),
    [날짜] DATE
);
GO

-- Pattern 6: Mixed Unicode and ASCII
CREATE TABLE [Sales_売上_Продажи] (
    [ID_番号_ИД] INT IDENTITY(1,1) PRIMARY KEY,
    [Name_名前_Имя] NVARCHAR(200),
    [Amount_金額_Сумма] DECIMAL(18,2)
);
GO

-- Pattern 7: Special characters in identifiers (spaces, punctuation)
CREATE TABLE [Table With Spaces] (
    [Column With Spaces] INT,
    [Column-With-Dashes] VARCHAR(50),
    [Column.With.Dots] VARCHAR(50),
    [Column@With@At] VARCHAR(50),
    [Column#With#Hash] VARCHAR(50),
    [Column$With$Dollar] VARCHAR(50),
    [Column_With_Underscore] VARCHAR(50)
);
GO

SELECT 
    [Column With Spaces],
    [Column-With-Dashes],
    [Column.With.Dots]
FROM [Table With Spaces];
GO

-- Pattern 8: Reserved words as identifiers
CREATE TABLE [SELECT] (
    [FROM] INT PRIMARY KEY,
    [WHERE] VARCHAR(100),
    [ORDER] INT,
    [BY] VARCHAR(50),
    [GROUP] INT,
    [HAVING] VARCHAR(100),
    [JOIN] INT,
    [ON] VARCHAR(50),
    [AND] BIT,
    [OR] BIT,
    [NOT] BIT,
    [NULL] VARCHAR(10),
    [TABLE] VARCHAR(100),
    [INDEX] INT,
    [KEY] VARCHAR(50),
    [PRIMARY] BIT,
    [FOREIGN] BIT,
    [CREATE] DATETIME,
    [ALTER] DATETIME,
    [DROP] BIT,
    [INSERT] INT,
    [UPDATE] DATETIME,
    [DELETE] BIT
);
GO

SELECT 
    [FROM],
    [WHERE],
    [ORDER],
    [GROUP]
FROM [SELECT]
WHERE [AND] = 1 OR [OR] = 1
ORDER BY [ORDER];
GO

-- Pattern 9: Numbers and underscores in identifiers
CREATE TABLE [_LeadingUnderscore] (
    [_Column1] INT,
    [__DoubleUnderscore] INT,
    [Column_1_2_3] INT,
    [123StartWithNumber] INT,  -- Note: Must be bracketed
    [Column123End] INT,
    [_1_2_3_] INT
);
GO

-- Pattern 10: Very long identifiers (near 128 char limit)
CREATE TABLE [ThisIsAVeryLongTableNameThatApproachesTheMaximumIdentifierLengthAllowedInSQLServerWhichIs128Characters_Almost] (
    [ThisIsAlsoAVeryLongColumnNameThatApproachesTheMaximumIdentifierLengthAllowedInSQLServerOfOneHundredTwentyEightChars] INT
);
GO

-- Pattern 11: Emoji and special Unicode (SQL Server 2019+ with UTF-8)
CREATE TABLE [📊DataTable📈] (
    [ID] INT IDENTITY(1,1) PRIMARY KEY,
    [Status✓] NVARCHAR(50),
    [Priority⚡] INT,
    [Notes📝] NVARCHAR(MAX)
);
GO

-- Pattern 12: Bracket escaping within identifiers
CREATE TABLE [Table[With]Brackets] (
    [Column[1]] INT,
    [Column]]Escaped] INT,
    [Col[umn]Name] VARCHAR(50)
);
GO

-- Pattern 13: Unicode string literals
SELECT 
    N'Hello, 世界!' AS ChineseGreeting,
    N'Привет мир!' AS RussianGreeting,
    N'こんにちは世界！' AS JapaneseGreeting,
    N'مرحبا بالعالم' AS ArabicGreeting,
    N'안녕하세요 세계!' AS KoreanGreeting,
    N'שלום עולם' AS HebrewGreeting,
    N'Γεια σου κόσμε!' AS GreekGreeting,
    N'สวัสดีโลก!' AS ThaiGreeting;
GO

-- Pattern 14: Unicode in LIKE patterns
SELECT *
FROM [北京销售数据]
WHERE [客户名称] LIKE N'%公司%'
   OR [客户名称] LIKE N'%集团%';
GO

-- Pattern 15: Case sensitivity with Unicode (depends on collation)
SELECT 
    [客户名称],
    [销售金额]
FROM [北京销售数据]
WHERE [客户名称] COLLATE Latin1_General_BIN = N'张三公司';
GO

-- Cleanup (optional)
-- DROP TABLE IF EXISTS [北京销售数据];
-- DROP TABLE IF EXISTS [Продажи];
-- DROP TABLE IF EXISTS [日本語テーブル];
-- DROP TABLE IF EXISTS [جدول_المبيعات];
-- DROP TABLE IF EXISTS [판매데이터];
-- DROP TABLE IF EXISTS [Sales_売上_Продажи];
-- DROP TABLE IF EXISTS [Table With Spaces];
-- DROP TABLE IF EXISTS [SELECT];
-- DROP TABLE IF EXISTS [_LeadingUnderscore];
-- DROP TABLE IF EXISTS [ThisIsAVeryLongTableNameThatApproachesTheMaximumIdentifierLengthAllowedInSQLServerWhichIs128Characters_Almost];
-- DROP TABLE IF EXISTS [📊DataTable📈];
-- DROP TABLE IF EXISTS [Table[With]Brackets];
GO
