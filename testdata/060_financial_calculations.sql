-- Sample 060: Financial Calculations
-- Source: Various - Financial formulas, MSSQLTips, Stack Overflow
-- Category: Reporting
-- Complexity: Advanced
-- Features: Compound interest, amortization, NPV, IRR, financial date calculations

-- Calculate compound interest
CREATE FUNCTION dbo.CalculateCompoundInterest
(
    @Principal DECIMAL(18,2),
    @AnnualRate DECIMAL(10,6),
    @CompoundingPerYear INT,  -- 1=Annual, 4=Quarterly, 12=Monthly, 365=Daily
    @Years DECIMAL(10,4)
)
RETURNS DECIMAL(18,2)
AS
BEGIN
    -- A = P(1 + r/n)^(nt)
    RETURN @Principal * POWER(1 + (@AnnualRate / @CompoundingPerYear), @CompoundingPerYear * @Years);
END
GO

-- Generate loan amortization schedule
CREATE PROCEDURE dbo.GenerateAmortizationSchedule
    @Principal DECIMAL(18,2),
    @AnnualRate DECIMAL(10,6),
    @TermMonths INT,
    @StartDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    SET @StartDate = ISNULL(@StartDate, GETDATE());
    
    DECLARE @MonthlyRate DECIMAL(18,10) = @AnnualRate / 12;
    DECLARE @MonthlyPayment DECIMAL(18,2);
    
    -- Calculate monthly payment: P * [r(1+r)^n] / [(1+r)^n - 1]
    SET @MonthlyPayment = @Principal * (@MonthlyRate * POWER(1 + @MonthlyRate, @TermMonths)) 
                          / (POWER(1 + @MonthlyRate, @TermMonths) - 1);
    
    ;WITH Amortization AS (
        SELECT 
            1 AS PaymentNumber,
            DATEADD(MONTH, 1, @StartDate) AS PaymentDate,
            @MonthlyPayment AS Payment,
            @Principal * @MonthlyRate AS InterestPaid,
            @MonthlyPayment - (@Principal * @MonthlyRate) AS PrincipalPaid,
            @Principal - (@MonthlyPayment - (@Principal * @MonthlyRate)) AS RemainingBalance,
            @Principal * @MonthlyRate AS CumulativeInterest,
            @MonthlyPayment - (@Principal * @MonthlyRate) AS CumulativePrincipal
        
        UNION ALL
        
        SELECT 
            PaymentNumber + 1,
            DATEADD(MONTH, 1, PaymentDate),
            @MonthlyPayment,
            RemainingBalance * @MonthlyRate,
            @MonthlyPayment - (RemainingBalance * @MonthlyRate),
            RemainingBalance - (@MonthlyPayment - (RemainingBalance * @MonthlyRate)),
            CumulativeInterest + (RemainingBalance * @MonthlyRate),
            CumulativePrincipal + (@MonthlyPayment - (RemainingBalance * @MonthlyRate))
        FROM Amortization
        WHERE PaymentNumber < @TermMonths
    )
    SELECT 
        PaymentNumber,
        PaymentDate,
        CAST(Payment AS DECIMAL(18,2)) AS Payment,
        CAST(InterestPaid AS DECIMAL(18,2)) AS InterestPaid,
        CAST(PrincipalPaid AS DECIMAL(18,2)) AS PrincipalPaid,
        CAST(CASE WHEN RemainingBalance < 0.01 THEN 0 ELSE RemainingBalance END AS DECIMAL(18,2)) AS RemainingBalance,
        CAST(CumulativeInterest AS DECIMAL(18,2)) AS CumulativeInterest,
        CAST(CumulativePrincipal AS DECIMAL(18,2)) AS CumulativePrincipal
    FROM Amortization
    OPTION (MAXRECURSION 500);
    
    -- Summary
    SELECT 
        @Principal AS LoanAmount,
        @AnnualRate * 100 AS AnnualRatePercent,
        @TermMonths AS TermMonths,
        CAST(@MonthlyPayment AS DECIMAL(18,2)) AS MonthlyPayment,
        CAST(@MonthlyPayment * @TermMonths AS DECIMAL(18,2)) AS TotalPayments,
        CAST((@MonthlyPayment * @TermMonths) - @Principal AS DECIMAL(18,2)) AS TotalInterest;
END
GO

-- Calculate Net Present Value (NPV)
CREATE FUNCTION dbo.CalculateNPV
(
    @DiscountRate DECIMAL(10,6),
    @CashFlows NVARCHAR(MAX)  -- Comma-separated cash flows
)
RETURNS DECIMAL(18,2)
AS
BEGIN
    DECLARE @NPV DECIMAL(18,4) = 0;
    DECLARE @Period INT = 0;
    
    SELECT @NPV = @NPV + (CAST(value AS DECIMAL(18,2)) / POWER(1 + @DiscountRate, @Period + ROW_NUMBER() OVER (ORDER BY (SELECT NULL))))
    FROM STRING_SPLIT(@CashFlows, ',');
    
    RETURN @NPV;
END
GO

-- Calculate Internal Rate of Return (IRR) using Newton-Raphson
CREATE PROCEDURE dbo.CalculateIRR
    @CashFlows NVARCHAR(MAX),  -- Comma-separated, first value is initial investment (negative)
    @MaxIterations INT = 100,
    @Tolerance DECIMAL(18,10) = 0.0000001
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @CashFlowTable TABLE (Period INT, CashFlow DECIMAL(18,2));
    DECLARE @Rate DECIMAL(18,10) = 0.1;  -- Initial guess
    DECLARE @Iteration INT = 0;
    DECLARE @NPV DECIMAL(18,10);
    DECLARE @Derivative DECIMAL(18,10);
    DECLARE @NewRate DECIMAL(18,10);
    
    -- Parse cash flows
    INSERT INTO @CashFlowTable (Period, CashFlow)
    SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1, CAST(value AS DECIMAL(18,2))
    FROM STRING_SPLIT(@CashFlows, ',');
    
    -- Newton-Raphson iteration
    WHILE @Iteration < @MaxIterations
    BEGIN
        -- Calculate NPV at current rate
        SELECT @NPV = SUM(CashFlow / POWER(1 + @Rate, Period))
        FROM @CashFlowTable;
        
        -- Check for convergence
        IF ABS(@NPV) < @Tolerance
            BREAK;
        
        -- Calculate derivative
        SELECT @Derivative = SUM(-Period * CashFlow / POWER(1 + @Rate, Period + 1))
        FROM @CashFlowTable
        WHERE Period > 0;
        
        -- Update rate
        SET @NewRate = @Rate - (@NPV / NULLIF(@Derivative, 0));
        
        IF ABS(@NewRate - @Rate) < @Tolerance
            BREAK;
        
        SET @Rate = @NewRate;
        SET @Iteration = @Iteration + 1;
    END
    
    SELECT 
        CAST(@Rate * 100 AS DECIMAL(10,4)) AS IRR_Percent,
        @Iteration AS Iterations,
        CASE WHEN @Iteration < @MaxIterations THEN 'Converged' ELSE 'Max iterations reached' END AS Status;
END
GO

-- Calculate depreciation
CREATE PROCEDURE dbo.CalculateDepreciation
    @AssetCost DECIMAL(18,2),
    @SalvageValue DECIMAL(18,2),
    @UsefulLifeYears INT,
    @Method NVARCHAR(20) = 'STRAIGHT_LINE',  -- STRAIGHT_LINE, DECLINING_BALANCE, SUM_OF_YEARS
    @DecliningRate DECIMAL(5,2) = 2.0  -- For declining balance (e.g., 2.0 = double declining)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @DepreciableAmount DECIMAL(18,2) = @AssetCost - @SalvageValue;
    
    ;WITH Years AS (
        SELECT 1 AS Year
        UNION ALL
        SELECT Year + 1 FROM Years WHERE Year < @UsefulLifeYears
    ),
    Depreciation AS (
        SELECT 
            Year,
            CASE @Method
                WHEN 'STRAIGHT_LINE' THEN 
                    @DepreciableAmount / @UsefulLifeYears
                WHEN 'DECLINING_BALANCE' THEN
                    CASE Year
                        WHEN 1 THEN @AssetCost * (@DecliningRate / @UsefulLifeYears)
                        ELSE NULL  -- Will be calculated recursively
                    END
                WHEN 'SUM_OF_YEARS' THEN
                    @DepreciableAmount * (@UsefulLifeYears - Year + 1.0) / 
                    ((@UsefulLifeYears * (@UsefulLifeYears + 1)) / 2.0)
            END AS AnnualDepreciation
        FROM Years
    )
    SELECT 
        Year,
        CAST(AnnualDepreciation AS DECIMAL(18,2)) AS AnnualDepreciation,
        CAST(SUM(AnnualDepreciation) OVER (ORDER BY Year) AS DECIMAL(18,2)) AS AccumulatedDepreciation,
        CAST(@AssetCost - SUM(AnnualDepreciation) OVER (ORDER BY Year) AS DECIMAL(18,2)) AS BookValue
    FROM Depreciation
    ORDER BY Year;
    
    -- Summary
    SELECT 
        @AssetCost AS AssetCost,
        @SalvageValue AS SalvageValue,
        @DepreciableAmount AS DepreciableAmount,
        @UsefulLifeYears AS UsefulLifeYears,
        @Method AS DepreciationMethod;
END
GO

-- Calculate moving averages for financial data
CREATE PROCEDURE dbo.CalculateMovingAverages
    @TableName NVARCHAR(128),
    @SchemaName NVARCHAR(128) = 'dbo',
    @DateColumn NVARCHAR(128),
    @ValueColumn NVARCHAR(128),
    @Periods NVARCHAR(50) = '7,30,90'  -- Comma-separated periods
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @AvgColumns NVARCHAR(MAX) = '';
    
    -- Build moving average columns
    SELECT @AvgColumns = @AvgColumns + 
        'AVG(CAST(' + QUOTENAME(@ValueColumn) + ' AS FLOAT)) OVER (ORDER BY ' + QUOTENAME(@DateColumn) + 
        ' ROWS BETWEEN ' + CAST(CAST(value AS INT) - 1 AS VARCHAR(10)) + ' PRECEDING AND CURRENT ROW) AS MA_' + value + ', '
    FROM STRING_SPLIT(@Periods, ',');
    
    SET @AvgColumns = LEFT(@AvgColumns, LEN(@AvgColumns) - 1);
    
    SET @SQL = N'
        SELECT 
            ' + QUOTENAME(@DateColumn) + ',
            ' + QUOTENAME(@ValueColumn) + ',
            ' + @AvgColumns + '
        FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + '
        ORDER BY ' + QUOTENAME(@DateColumn);
    
    EXEC sp_executesql @SQL;
END
GO

-- Calculate financial ratios
CREATE PROCEDURE dbo.CalculateFinancialRatios
    @Revenue DECIMAL(18,2),
    @CostOfGoodsSold DECIMAL(18,2),
    @OperatingExpenses DECIMAL(18,2),
    @TotalAssets DECIMAL(18,2),
    @TotalLiabilities DECIMAL(18,2),
    @CurrentAssets DECIMAL(18,2),
    @CurrentLiabilities DECIMAL(18,2),
    @Inventory DECIMAL(18,2),
    @ShareholdersEquity DECIMAL(18,2)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @GrossProfit DECIMAL(18,2) = @Revenue - @CostOfGoodsSold;
    DECLARE @OperatingIncome DECIMAL(18,2) = @GrossProfit - @OperatingExpenses;
    
    SELECT 
        -- Profitability Ratios
        CAST(@GrossProfit * 100.0 / NULLIF(@Revenue, 0) AS DECIMAL(10,2)) AS GrossProfitMargin,
        CAST(@OperatingIncome * 100.0 / NULLIF(@Revenue, 0) AS DECIMAL(10,2)) AS OperatingMargin,
        CAST(@OperatingIncome * 100.0 / NULLIF(@TotalAssets, 0) AS DECIMAL(10,2)) AS ReturnOnAssets,
        CAST(@OperatingIncome * 100.0 / NULLIF(@ShareholdersEquity, 0) AS DECIMAL(10,2)) AS ReturnOnEquity,
        
        -- Liquidity Ratios
        CAST(@CurrentAssets / NULLIF(@CurrentLiabilities, 0) AS DECIMAL(10,2)) AS CurrentRatio,
        CAST((@CurrentAssets - @Inventory) / NULLIF(@CurrentLiabilities, 0) AS DECIMAL(10,2)) AS QuickRatio,
        
        -- Leverage Ratios
        CAST(@TotalLiabilities / NULLIF(@TotalAssets, 0) AS DECIMAL(10,2)) AS DebtToAssets,
        CAST(@TotalLiabilities / NULLIF(@ShareholdersEquity, 0) AS DECIMAL(10,2)) AS DebtToEquity,
        
        -- Efficiency Ratios
        CAST(@Revenue / NULLIF(@TotalAssets, 0) AS DECIMAL(10,2)) AS AssetTurnover,
        CAST(@CostOfGoodsSold / NULLIF(@Inventory, 0) AS DECIMAL(10,2)) AS InventoryTurnover;
END
GO
