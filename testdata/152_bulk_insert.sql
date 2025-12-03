-- Sample 152: BULK INSERT and BCP Patterns
-- Category: Missing Syntax Elements
-- Complexity: Complex
-- Purpose: Parser testing - bulk data loading syntax
-- Features: BULK INSERT options, format files, error handling

-- Pattern 1: Basic BULK INSERT
BULK INSERT dbo.Customers
FROM 'C:\Data\customers.csv';
GO

-- Pattern 2: BULK INSERT with common options
BULK INSERT dbo.Customers
FROM 'C:\Data\customers.csv'
WITH (
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    FIRSTROW = 2
);
GO

-- Pattern 3: BULK INSERT with all options
BULK INSERT dbo.Orders
FROM 'C:\Data\orders.txt'
WITH (
    FIELDTERMINATOR = '\t',
    ROWTERMINATOR = '\n',
    FIRSTROW = 2,
    LASTROW = 10000,
    CODEPAGE = '65001',
    DATAFILETYPE = 'char',
    FIELDQUOTE = '"',
    FORMATFILE = 'C:\Data\orders.fmt',
    ERRORFILE = 'C:\Data\orders_errors.txt',
    MAXERRORS = 100,
    BATCHSIZE = 1000,
    TABLOCK,
    CHECK_CONSTRAINTS,
    FIRE_TRIGGERS,
    KEEPIDENTITY,
    KEEPNULLS
);
GO

-- Pattern 4: BULK INSERT with format file
BULK INSERT dbo.Products
FROM 'C:\Data\products.dat'
WITH (
    FORMATFILE = 'C:\Data\products.xml',
    ERRORFILE = 'C:\Data\products_err.txt',
    MAXERRORS = 10
);
GO

-- Pattern 5: BULK INSERT tab-delimited
BULK INSERT dbo.SalesData
FROM 'C:\Data\sales.tsv'
WITH (
    FIELDTERMINATOR = '\t',
    ROWTERMINATOR = '0x0a',
    FIRSTROW = 2,
    TABLOCK
);
GO

-- Pattern 6: BULK INSERT pipe-delimited
BULK INSERT dbo.LogData
FROM 'C:\Data\logs.txt'
WITH (
    FIELDTERMINATOR = '|',
    ROWTERMINATOR = '\r\n',
    CODEPAGE = 'ACP'
);
GO

-- Pattern 7: BULK INSERT with row terminator variations
-- Windows line ending
BULK INSERT dbo.Table1 FROM 'C:\Data\file1.txt' WITH (ROWTERMINATOR = '\r\n');

-- Unix line ending
BULK INSERT dbo.Table2 FROM 'C:\Data\file2.txt' WITH (ROWTERMINATOR = '\n');

-- Hex specification
BULK INSERT dbo.Table3 FROM 'C:\Data\file3.txt' WITH (ROWTERMINATOR = '0x0a');

-- Custom terminator
BULK INSERT dbo.Table4 FROM 'C:\Data\file4.txt' WITH (ROWTERMINATOR = '~~\n');
GO

-- Pattern 8: BULK INSERT with ORDER hint
BULK INSERT dbo.OrderedData
FROM 'C:\Data\sorted_data.csv'
WITH (
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    ORDER (ID ASC),
    TABLOCK
);
GO

-- Pattern 9: BULK INSERT with multiple ORDER columns
BULK INSERT dbo.MultiSortData
FROM 'C:\Data\multi_sorted.csv'
WITH (
    FIELDTERMINATOR = ',',
    ORDER (Region ASC, Date DESC, Amount ASC),
    TABLOCK
);
GO

-- Pattern 10: BULK INSERT from network path
BULK INSERT dbo.SharedData
FROM '\\FileServer\Share\Data\import.csv'
WITH (
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    FIRSTROW = 2
);
GO

-- Pattern 11: BULK INSERT with ROWS_PER_BATCH
BULK INSERT dbo.LargeTable
FROM 'C:\Data\large_file.csv'
WITH (
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    ROWS_PER_BATCH = 100000,
    KILOBYTES_PER_BATCH = 65536
);
GO

-- Pattern 12: BULK INSERT into temp table
CREATE TABLE #TempImport (
    Col1 INT,
    Col2 VARCHAR(100),
    Col3 DATE
);

BULK INSERT #TempImport
FROM 'C:\Data\temp_data.csv'
WITH (
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n'
);

SELECT * FROM #TempImport;
DROP TABLE #TempImport;
GO

-- Pattern 13: BULK INSERT with error handling
BEGIN TRY
    BULK INSERT dbo.ImportTable
    FROM 'C:\Data\import.csv'
    WITH (
        FIELDTERMINATOR = ',',
        ROWTERMINATOR = '\n',
        MAXERRORS = 0,
        ERRORFILE = 'C:\Data\errors.txt'
    );
    
    PRINT 'Import successful. Rows imported: ' + CAST(@@ROWCOUNT AS VARCHAR(20));
END TRY
BEGIN CATCH
    PRINT 'Import failed: ' + ERROR_MESSAGE();
END CATCH
GO

-- Pattern 14: BULK INSERT in transaction
BEGIN TRANSACTION;

BEGIN TRY
    BULK INSERT dbo.TransactionalImport
    FROM 'C:\Data\transactional.csv'
    WITH (
        FIELDTERMINATOR = ',',
        ROWTERMINATOR = '\n',
        TABLOCK
    );
    
    -- Validate imported data
    IF EXISTS (SELECT 1 FROM dbo.TransactionalImport WHERE Amount < 0)
    BEGIN
        RAISERROR('Invalid data detected', 16, 1);
    END
    
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    ROLLBACK TRANSACTION;
    THROW;
END CATCH
GO

-- Pattern 15: OPENROWSET BULK for single file read
SELECT *
FROM OPENROWSET(
    BULK 'C:\Data\customers.csv',
    FORMATFILE = 'C:\Data\customers.fmt',
    FIRSTROW = 2
) AS ImportData;
GO

-- Pattern 16: OPENROWSET BULK with inline schema
SELECT *
FROM OPENROWSET(
    BULK 'C:\Data\simple.csv',
    SINGLE_CLOB
) AS FileContent;
GO

-- Pattern 17: OPENROWSET BULK for binary file
SELECT BulkColumn
FROM OPENROWSET(
    BULK 'C:\Data\document.pdf',
    SINGLE_BLOB
) AS FileData;
GO

-- Pattern 18: OPENROWSET BULK for NVARCHAR content
SELECT BulkColumn
FROM OPENROWSET(
    BULK 'C:\Data\unicode.txt',
    SINGLE_NCLOB
) AS FileContent;
GO

-- Pattern 19: INSERT with OPENROWSET BULK
INSERT INTO dbo.Documents (FileName, FileContent)
SELECT 
    'report.pdf',
    BulkColumn
FROM OPENROWSET(
    BULK 'C:\Data\report.pdf',
    SINGLE_BLOB
) AS FileData;
GO

-- Pattern 20: BULK INSERT with Azure Blob Storage
BULK INSERT dbo.CloudData
FROM 'myfile.csv'
WITH (
    DATA_SOURCE = 'AzureBlobStorage',
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    FIRSTROW = 2
);
GO

-- Pattern 21: Sample format file content (XML)
/*
<?xml version="1.0"?>
<BCPFORMAT xmlns="http://schemas.microsoft.com/sqlserver/2004/bulkload/format">
  <RECORD>
    <FIELD ID="1" xsi:type="CharTerm" TERMINATOR="," MAX_LENGTH="12"/>
    <FIELD ID="2" xsi:type="CharTerm" TERMINATOR="," MAX_LENGTH="100"/>
    <FIELD ID="3" xsi:type="CharTerm" TERMINATOR="\r\n" MAX_LENGTH="10"/>
  </RECORD>
  <ROW>
    <COLUMN SOURCE="1" NAME="ID" xsi:type="SQLINT"/>
    <COLUMN SOURCE="2" NAME="Name" xsi:type="SQLNVARCHAR"/>
    <COLUMN SOURCE="3" NAME="Date" xsi:type="SQLDATE"/>
  </ROW>
</BCPFORMAT>
*/
GO

-- Pattern 22: Stored procedure for bulk import
CREATE PROCEDURE dbo.ImportCSVFile
    @FilePath NVARCHAR(500),
    @TableName NVARCHAR(128),
    @HasHeader BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FirstRow INT = CASE WHEN @HasHeader = 1 THEN 2 ELSE 1 END;
    
    SET @SQL = N'
        BULK INSERT ' + QUOTENAME(@TableName) + N'
        FROM ''' + @FilePath + N'''
        WITH (
            FIELDTERMINATOR = '','',
            ROWTERMINATOR = ''\n'',
            FIRSTROW = ' + CAST(@FirstRow AS NVARCHAR(10)) + N',
            TABLOCK,
            MAXERRORS = 100
        )';
    
    EXEC sp_executesql @SQL;
    
    SELECT @@ROWCOUNT AS RowsImported;
END;
GO

DROP PROCEDURE IF EXISTS dbo.ImportCSVFile;
GO
