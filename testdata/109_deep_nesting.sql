-- Sample 109: Deep Nesting and Complex Expressions
-- Category: Syntax Edge Cases
-- Complexity: Advanced
-- Purpose: Parser stress testing - deeply nested structures
-- Features: Nested subqueries, nested CASE, complex boolean logic, deep parentheses

-- Pattern 1: Deeply nested subqueries (5 levels)
SELECT 
    CustomerID,
    CustomerName,
    (
        SELECT COUNT(*)
        FROM dbo.Orders o1
        WHERE o1.CustomerID = c.CustomerID
        AND o1.TotalAmount > (
            SELECT AVG(TotalAmount)
            FROM dbo.Orders o2
            WHERE o2.CustomerID = c.CustomerID
            AND o2.OrderDate > (
                SELECT MIN(OrderDate)
                FROM dbo.Orders o3
                WHERE o3.CustomerID = c.CustomerID
                AND o3.Status IN (
                    SELECT Status
                    FROM dbo.OrderStatuses os
                    WHERE os.IsActive = 1
                    AND os.StatusCategory = (
                        SELECT TOP 1 StatusCategory
                        FROM dbo.StatusCategories sc
                        WHERE sc.IsDefault = 1
                    )
                )
            )
        )
    ) AS AboveAvgOrderCount
FROM dbo.Customers c
WHERE c.IsActive = 1;
GO

-- Pattern 2: Nested CASE expressions (5 levels deep)
SELECT 
    OrderID,
    OrderDate,
    TotalAmount,
    CASE 
        WHEN TotalAmount >= 10000 THEN
            CASE 
                WHEN CustomerType = 'Wholesale' THEN
                    CASE 
                        WHEN PaymentTerms = 'Net30' THEN
                            CASE 
                                WHEN CreditScore >= 800 THEN
                                    CASE 
                                        WHEN OrderCount > 100 THEN 'Platinum-Elite'
                                        WHEN OrderCount > 50 THEN 'Platinum-Premier'
                                        ELSE 'Platinum-Standard'
                                    END
                                WHEN CreditScore >= 700 THEN 'Gold-Wholesale'
                                ELSE 'Silver-Wholesale'
                            END
                        WHEN PaymentTerms = 'Net15' THEN 'Gold-Quick'
                        ELSE 'Standard-Wholesale'
                    END
                WHEN CustomerType = 'Retail' THEN
                    CASE 
                        WHEN LoyaltyPoints > 10000 THEN 'VIP-Retail'
                        ELSE 'Premium-Retail'
                    END
                ELSE 'Other-Large'
            END
        WHEN TotalAmount >= 1000 THEN
            CASE 
                WHEN RepeatCustomer = 1 THEN 'Valued'
                ELSE 'Standard'
            END
        ELSE 'Basic'
    END AS CustomerClassification
FROM dbo.Orders o
INNER JOIN dbo.Customers c ON o.CustomerID = c.CustomerID;
GO

-- Pattern 3: Deep parenthetical nesting in boolean expressions
SELECT *
FROM dbo.Products
WHERE (
    (
        (
            (
                (CategoryID = 1 AND Price > 10)
                OR (CategoryID = 2 AND Price > 20)
            )
            AND (
                (StockQuantity > 0 AND IsActive = 1)
                OR (BackorderAllowed = 1)
            )
        )
        OR (
            (
                (CategoryID IN (3, 4, 5))
                AND (
                    (Price BETWEEN 5 AND 50)
                    OR (IsOnSale = 1 AND SalePrice BETWEEN 3 AND 40)
                )
            )
        )
    )
    AND (
        (
            (SupplierID IN (SELECT SupplierID FROM dbo.ActiveSuppliers))
            OR (SupplierID IS NULL AND InHouseManufactured = 1)
        )
    )
);
GO

-- Pattern 4: Complex arithmetic expressions
SELECT 
    ProductID,
    ProductName,
    Price,
    Cost,
    Quantity,
    (
        ((Price - Cost) / NULLIF(Cost, 0) * 100) * 
        (1 + (CASE WHEN Quantity > 100 THEN 0.05 ELSE 0 END)) *
        (1 - (CASE WHEN DaysInInventory > 90 THEN 0.1 ELSE 0 END)) *
        (
            (1 + SeasonalFactor / 100) * 
            (1 + TrendFactor / 100) *
            (1 - (RiskFactor / 100 / 2))
        )
    ) AS AdjustedMarginPercent,
    (
        (Price * Quantity) - 
        (Cost * Quantity) - 
        (
            (
                (Price * Quantity * TaxRate / 100) +
                (Price * Quantity * ShippingRate / 100) +
                (Cost * Quantity * HandlingRate / 100)
            ) * (1 + OverheadMultiplier)
        )
    ) AS NetProfit
FROM dbo.ProductAnalysis;
GO

-- Pattern 5: Nested aggregate functions (via subqueries)
SELECT 
    c.CategoryName,
    (
        SELECT AVG(SubTotal)
        FROM (
            SELECT SUM(od.Quantity * od.UnitPrice) AS SubTotal
            FROM dbo.OrderDetails od
            INNER JOIN dbo.Products p ON od.ProductID = p.ProductID
            WHERE p.CategoryID = c.CategoryID
            GROUP BY od.OrderID
        ) AS OrderTotals
    ) AS AvgOrderValue,
    (
        SELECT MAX(DailyCount)
        FROM (
            SELECT COUNT(*) AS DailyCount
            FROM dbo.Orders o
            INNER JOIN dbo.OrderDetails od ON o.OrderID = od.OrderID
            INNER JOIN dbo.Products p ON od.ProductID = p.ProductID
            WHERE p.CategoryID = c.CategoryID
            GROUP BY CAST(o.OrderDate AS DATE)
        ) AS DailyCounts
    ) AS PeakDailyOrders
FROM dbo.Categories c;
GO

-- Pattern 6: Complex string concatenation with nested functions
SELECT 
    CustomerID,
    UPPER(
        LTRIM(RTRIM(
            COALESCE(
                NULLIF(
                    CONCAT(
                        CASE WHEN Title IS NOT NULL THEN Title + ' ' ELSE '' END,
                        FirstName,
                        CASE WHEN MiddleName IS NOT NULL THEN ' ' + LEFT(MiddleName, 1) + '.' ELSE '' END,
                        ' ',
                        LastName,
                        CASE WHEN Suffix IS NOT NULL THEN ', ' + Suffix ELSE '' END
                    ),
                    ''
                ),
                CONCAT('Customer #', CAST(CustomerID AS VARCHAR(10)))
            )
        ))
    ) AS FormattedName,
    REPLACE(
        REPLACE(
            REPLACE(
                REPLACE(
                    LOWER(
                        CONCAT(FirstName, '.', LastName, '@', CompanyDomain)
                    ),
                    ' ', ''
                ),
                '''', ''
            ),
            '-', ''
        ),
        '..', '.'
    ) AS GeneratedEmail
FROM dbo.Customers;
GO

-- Pattern 7: Complex date calculations
SELECT 
    OrderID,
    OrderDate,
    DATEADD(
        DAY,
        CASE 
            WHEN DATENAME(WEEKDAY, 
                DATEADD(DAY, 
                    CASE ShippingMethod
                        WHEN 'Express' THEN 1
                        WHEN 'Standard' THEN 5
                        WHEN 'Economy' THEN 10
                        ELSE 7
                    END,
                    OrderDate
                )
            ) = 'Saturday' THEN 2
            WHEN DATENAME(WEEKDAY,
                DATEADD(DAY,
                    CASE ShippingMethod
                        WHEN 'Express' THEN 1
                        WHEN 'Standard' THEN 5
                        WHEN 'Economy' THEN 10
                        ELSE 7
                    END,
                    OrderDate
                )
            ) = 'Sunday' THEN 1
            ELSE 0
        END,
        DATEADD(DAY,
            CASE ShippingMethod
                WHEN 'Express' THEN 1
                WHEN 'Standard' THEN 5
                WHEN 'Economy' THEN 10
                ELSE 7
            END,
            OrderDate
        )
    ) AS EstimatedDeliveryDate
FROM dbo.Orders;
GO

-- Pattern 8: Complex COALESCE/NULLIF chain
SELECT 
    ProductID,
    COALESCE(
        NULLIF(
            COALESCE(
                NULLIF(
                    COALESCE(
                        NULLIF(DisplayPrice, 0),
                        NULLIF(SalePrice, 0)
                    ),
                    0
                ),
                NULLIF(
                    COALESCE(
                        NULLIF(WholesalePrice * 1.5, 0),
                        NULLIF(Cost * 2, 0)
                    ),
                    0
                )
            ),
            0
        ),
        9.99  -- Default price
    ) AS EffectivePrice
FROM dbo.Products;
GO

-- Pattern 9: Nested window functions (via derived tables)
SELECT 
    OrderID,
    CustomerID,
    OrderDate,
    TotalAmount,
    RunningTotal,
    AvgRunningTotal
FROM (
    SELECT 
        OrderID,
        CustomerID,
        OrderDate,
        TotalAmount,
        SUM(TotalAmount) OVER (
            PARTITION BY CustomerID 
            ORDER BY OrderDate 
            ROWS UNBOUNDED PRECEDING
        ) AS RunningTotal,
        AVG(
            SUM(TotalAmount) OVER (
                PARTITION BY CustomerID 
                ORDER BY OrderDate 
                ROWS UNBOUNDED PRECEDING
            )
        ) OVER (
            PARTITION BY CustomerID
        ) AS AvgRunningTotal
    FROM dbo.Orders
) AS OrdersWithRunning
ORDER BY CustomerID, OrderDate;
GO

-- Pattern 10: Complex EXISTS with multiple conditions
SELECT c.*
FROM dbo.Customers c
WHERE EXISTS (
    SELECT 1
    FROM dbo.Orders o
    WHERE o.CustomerID = c.CustomerID
    AND o.TotalAmount > 1000
    AND EXISTS (
        SELECT 1
        FROM dbo.OrderDetails od
        WHERE od.OrderID = o.OrderID
        AND od.Quantity > 10
        AND EXISTS (
            SELECT 1
            FROM dbo.Products p
            WHERE p.ProductID = od.ProductID
            AND p.CategoryID IN (
                SELECT CategoryID
                FROM dbo.Categories cat
                WHERE cat.IsPremium = 1
                AND EXISTS (
                    SELECT 1
                    FROM dbo.CategoryPromotions cp
                    WHERE cp.CategoryID = cat.CategoryID
                    AND cp.IsActive = 1
                )
            )
        )
    )
);
GO
