-- Sample 194: Comments and Documentation Patterns
-- Category: Syntax Coverage / Metadata
-- Complexity: Intermediate
-- Purpose: Parser testing - comment syntax and extended properties
-- Features: Single-line, multi-line comments, extended properties

-- Pattern 1: Single-line comment
SELECT * FROM dbo.Customers; -- This is an inline comment
GO

-- Pattern 2: Comment on separate line
-- This comment describes the following query
SELECT CustomerID, CustomerName FROM dbo.Customers;
GO

-- Pattern 3: Multiple single-line comments
-- Query: Get active customers
-- Author: DBA Team
-- Date: 2024-06-15
-- Purpose: Dashboard display
SELECT * FROM dbo.Customers WHERE IsActive = 1;
GO

-- Pattern 4: Block comment
/* 
   This is a multi-line block comment
   that spans multiple lines.
   It can contain SQL keywords like SELECT, FROM, WHERE
   without being executed.
*/
SELECT * FROM dbo.Products;
GO

-- Pattern 5: Inline block comment
SELECT CustomerID, /* CustomerName, */ Email FROM dbo.Customers;
GO

-- Pattern 6: Nested comments (NOT supported in standard SQL)
-- SQL Server does NOT support nested block comments
/* Outer comment
   /* Inner comment - This will cause an error! */
*/
GO

-- Pattern 7: Comment out code block
/*
SELECT * FROM dbo.OldTable;
DELETE FROM dbo.TempData;
TRUNCATE TABLE dbo.LogEntries;
*/
GO

-- Pattern 8: Header comment block
/******************************************************************************
 * Procedure: dbo.GetCustomerOrders
 * Description: Retrieves all orders for a given customer
 * Parameters:
 *   @CustomerID - The unique identifier of the customer
 * Returns: Result set of orders
 * Author: Development Team
 * Created: 2024-01-15
 * Modified: 2024-06-15 - Added status filter
 ******************************************************************************/
GO

-- Pattern 9: TODO comments
-- TODO: Add pagination support
-- FIXME: This query is slow, needs optimization
-- HACK: Temporary workaround for bug #1234
-- NOTE: This assumes all prices are in USD
SELECT * FROM dbo.Products;
GO

-- Pattern 10: Extended property on table
EXEC sp_addextendedproperty 
    @name = N'MS_Description', 
    @value = N'Contains customer information including contact details',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'Customers';
GO

-- Pattern 11: Extended property on column
EXEC sp_addextendedproperty 
    @name = N'MS_Description', 
    @value = N'Primary key - unique customer identifier',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'Customers',
    @level2type = N'COLUMN', @level2name = N'CustomerID';
GO

-- Pattern 12: Extended property on stored procedure
EXEC sp_addextendedproperty 
    @name = N'MS_Description', 
    @value = N'Retrieves customer order history with optional date filtering',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'PROCEDURE', @level1name = N'GetCustomerOrders';
GO

-- Pattern 13: Custom extended properties
EXEC sp_addextendedproperty 
    @name = N'Author', 
    @value = N'John Smith',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'Customers';

EXEC sp_addextendedproperty 
    @name = N'Version', 
    @value = N'1.0.0',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'Customers';

EXEC sp_addextendedproperty 
    @name = N'LastModified', 
    @value = N'2024-06-15',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'Customers';
GO

-- Pattern 14: Update extended property
EXEC sp_updateextendedproperty 
    @name = N'MS_Description', 
    @value = N'Updated description for customers table',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'Customers';
GO

-- Pattern 15: Drop extended property
EXEC sp_dropextendedproperty 
    @name = N'MS_Description',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'Customers';
GO

-- Pattern 16: Query extended properties
SELECT 
    OBJECT_NAME(ep.major_id) AS ObjectName,
    ep.name AS PropertyName,
    ep.value AS PropertyValue
FROM sys.extended_properties ep
WHERE ep.class = 1  -- Object or column
ORDER BY ObjectName, PropertyName;
GO

-- Pattern 17: fn_listextendedproperty
SELECT *
FROM fn_listextendedproperty(
    NULL,  -- property name (NULL for all)
    'SCHEMA', 'dbo',
    'TABLE', 'Customers',
    NULL, NULL  -- column level
);
GO

-- Pattern 18: Documentation in procedure
CREATE PROCEDURE dbo.DocumentedProc
    @CustomerID INT,  -- Customer identifier
    @StartDate DATE = NULL,  -- Optional start date filter
    @EndDate DATE = NULL  -- Optional end date filter
AS
BEGIN
    /*
    ============================================================================
    Procedure: dbo.DocumentedProc
    Description: 
        Retrieves customer orders within an optional date range.
        If no dates provided, returns all orders.
    
    Parameters:
        @CustomerID - Required. The customer to query.
        @StartDate - Optional. Filter orders on or after this date.
        @EndDate - Optional. Filter orders on or before this date.
    
    Returns:
        Result set with columns: OrderID, OrderDate, TotalAmount, Status
    
    Example:
        EXEC dbo.DocumentedProc @CustomerID = 1, @StartDate = '2024-01-01'
    
    Change History:
        2024-01-15 - Initial creation
        2024-03-20 - Added date filtering
        2024-06-15 - Performance optimization
    ============================================================================
    */
    
    SELECT OrderID, OrderDate, TotalAmount, Status
    FROM dbo.Orders
    WHERE CustomerID = @CustomerID
      AND (@StartDate IS NULL OR OrderDate >= @StartDate)
      AND (@EndDate IS NULL OR OrderDate <= @EndDate)
    ORDER BY OrderDate DESC;
END;
GO

DROP PROCEDURE dbo.DocumentedProc;
GO

-- Pattern 19: Region comments (for code folding in SSMS)
-- #region Customer Queries
SELECT * FROM dbo.Customers;
SELECT * FROM dbo.CustomerAddresses;
-- #endregion

-- #region Order Queries  
SELECT * FROM dbo.Orders;
SELECT * FROM dbo.OrderDetails;
-- #endregion
GO

-- Pattern 20: ASCII art separator
-- ============================================================
-- ==================== SECTION: CUSTOMERS ====================
-- ============================================================
GO
