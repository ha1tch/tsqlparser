-- Sample 113: Operator Precedence and Complex Boolean Expressions
-- Category: Syntax Edge Cases
-- Complexity: Advanced
-- Purpose: Parser testing - operator precedence and boolean logic
-- Features: Arithmetic precedence, boolean precedence, parentheses, bitwise ops

-- Pattern 1: Arithmetic operator precedence
SELECT 1 + 2 * 3;           -- = 7 (multiplication first)
SELECT (1 + 2) * 3;         -- = 9 (parentheses override)
SELECT 10 - 4 / 2;          -- = 8 (division first)
SELECT (10 - 4) / 2;        -- = 3
SELECT 2 * 3 + 4 * 5;       -- = 26
SELECT 10 / 2 * 5;          -- = 25 (left to right for same precedence)
SELECT 10 * 2 / 5;          -- = 4
SELECT 10 % 3 + 1;          -- = 2 (modulo before addition)
SELECT -5 * 3;              -- = -15 (unary minus)
SELECT 5 * -3;              -- = -15
SELECT --5;                 -- = 5 (double negative, but this is a comment!)
SELECT - -5;                -- = 5 (with space)
SELECT +5 + +3;             -- = 8 (unary plus)
GO

-- Pattern 2: String concatenation precedence
SELECT 'A' + 'B' + 'C';                    -- = 'ABC'
SELECT 1 + 2 + ' = Three';                 -- Error or implicit conversion
SELECT CAST(1 + 2 AS VARCHAR) + ' = Three'; -- = '3 = Three'
SELECT 'Value: ' + CAST(10 * 5 AS VARCHAR); -- = 'Value: 50'
GO

-- Pattern 3: Comparison operator chains
SELECT * FROM Numbers WHERE A = B;
SELECT * FROM Numbers WHERE A <> B;
SELECT * FROM Numbers WHERE A != B;        -- Same as <>
SELECT * FROM Numbers WHERE A < B;
SELECT * FROM Numbers WHERE A <= B;
SELECT * FROM Numbers WHERE A > B;
SELECT * FROM Numbers WHERE A >= B;
SELECT * FROM Numbers WHERE A !< B;        -- Not less than (same as >=)
SELECT * FROM Numbers WHERE A !> B;        -- Not greater than (same as <=)
GO

-- Pattern 4: Boolean operator precedence (NOT > AND > OR)
SELECT * FROM T WHERE A = 1 OR B = 2 AND C = 3;     -- AND binds tighter
SELECT * FROM T WHERE (A = 1 OR B = 2) AND C = 3;   -- Explicit grouping
SELECT * FROM T WHERE A = 1 AND B = 2 OR C = 3;     -- = (A=1 AND B=2) OR C=3
SELECT * FROM T WHERE NOT A = 1 AND B = 2;          -- = (NOT A=1) AND B=2
SELECT * FROM T WHERE NOT (A = 1 AND B = 2);        -- NOT of entire expression
SELECT * FROM T WHERE NOT A = 1 OR B = 2;           -- = (NOT A=1) OR B=2
SELECT * FROM T WHERE NOT (A = 1 OR B = 2);         -- NOT of entire expression
GO

-- Pattern 5: Complex boolean with all operators
SELECT * 
FROM Orders
WHERE 
    (Status = 'Active' AND TotalAmount > 1000)
    OR (Status = 'Pending' AND Priority = 'High')
    OR (CustomerType = 'VIP' AND NOT IsOnHold = 1)
    AND NOT (Region = 'Blocked' OR AccountStatus = 'Suspended');
GO

-- Pattern 6: Triple NOT and multiple negations
SELECT * FROM T WHERE NOT NOT A = 1;           -- Double negative
SELECT * FROM T WHERE NOT NOT NOT A = 1;       -- Triple negative
SELECT * FROM T WHERE NOT (NOT (NOT A = 1));   -- Explicit nesting
GO

-- Pattern 7: Bitwise operator precedence
SELECT 5 & 3;              -- Bitwise AND = 1
SELECT 5 | 3;              -- Bitwise OR = 7
SELECT 5 ^ 3;              -- Bitwise XOR = 6
SELECT ~5;                 -- Bitwise NOT = -6
SELECT 5 & 3 | 2;          -- = (5 & 3) | 2 = 1 | 2 = 3
SELECT 5 | 3 & 2;          -- = 5 | (3 & 2) = 5 | 2 = 7 (& before |)
SELECT 5 ^ 3 & 2;          -- = 5 ^ (3 & 2) = 5 ^ 2 = 7
SELECT ~5 & 3;             -- = (~5) & 3
SELECT 1 << 3;             -- Left shift (if supported) = 8
SELECT 8 >> 2;             -- Right shift (if supported) = 2
GO

-- Pattern 8: Mixed arithmetic and bitwise
SELECT 2 + 3 & 5;          -- Arithmetic before bitwise
SELECT (2 + 3) & 5;        -- = 5 & 5 = 5
SELECT 2 & 3 + 5;          -- = 2 & 8 = 0
SELECT 10 * 2 & 15;        -- = 20 & 15 = 4
GO

-- Pattern 9: Comparison with arithmetic
SELECT * FROM T WHERE A + B = C;
SELECT * FROM T WHERE A = B + C;
SELECT * FROM T WHERE A + B = C + D;
SELECT * FROM T WHERE A * B > C / D;
SELECT * FROM T WHERE A + B * C = D;   -- = A + (B*C) = D
GO

-- Pattern 10: BETWEEN precedence
SELECT * FROM T WHERE A BETWEEN 1 AND 10;
SELECT * FROM T WHERE A + 5 BETWEEN 1 AND 10;
SELECT * FROM T WHERE A BETWEEN 1 AND 5 + 5;
SELECT * FROM T WHERE A BETWEEN 1 + 0 AND 5 + 5;
SELECT * FROM T WHERE A BETWEEN B AND C + D;
SELECT * FROM T WHERE NOT A BETWEEN 1 AND 10;
SELECT * FROM T WHERE A NOT BETWEEN 1 AND 10;
GO

-- Pattern 11: IN precedence
SELECT * FROM T WHERE A IN (1, 2, 3);
SELECT * FROM T WHERE A + 1 IN (1, 2, 3);
SELECT * FROM T WHERE A IN (1, 2, 1 + 2);
SELECT * FROM T WHERE NOT A IN (1, 2, 3);
SELECT * FROM T WHERE A NOT IN (1, 2, 3);
SELECT * FROM T WHERE A IN (1, 2, 3) AND B = 1;
SELECT * FROM T WHERE A = 1 OR B IN (2, 3);
GO

-- Pattern 12: LIKE precedence
SELECT * FROM T WHERE A LIKE 'test%';
SELECT * FROM T WHERE A + 'suffix' LIKE 'test%';
SELECT * FROM T WHERE NOT A LIKE 'test%';
SELECT * FROM T WHERE A NOT LIKE 'test%';
SELECT * FROM T WHERE A LIKE 'test%' AND B = 1;
SELECT * FROM T WHERE A = 1 OR B LIKE 'test%';
GO

-- Pattern 13: IS NULL precedence
SELECT * FROM T WHERE A IS NULL;
SELECT * FROM T WHERE A IS NOT NULL;
SELECT * FROM T WHERE NOT A IS NULL;           -- Same as IS NOT NULL
SELECT * FROM T WHERE A IS NULL AND B = 1;
SELECT * FROM T WHERE A = 1 OR B IS NULL;
SELECT * FROM T WHERE A IS NULL OR B IS NULL AND C = 1;
GO

-- Pattern 14: Subquery in expressions
SELECT * FROM T WHERE A = (SELECT MAX(B) FROM U);
SELECT * FROM T WHERE A + (SELECT MAX(B) FROM U) > 10;
SELECT * FROM T WHERE (SELECT COUNT(*) FROM U WHERE U.ID = T.ID) > 0;
SELECT * FROM T WHERE A IN (SELECT B FROM U) AND C = 1;
SELECT * FROM T WHERE EXISTS (SELECT 1 FROM U) OR A = 1;
GO

-- Pattern 15: CASE expression precedence
SELECT CASE WHEN A = 1 THEN 'One' ELSE 'Other' END + ' value';
SELECT 'Value: ' + CASE WHEN A = 1 THEN 'One' ELSE 'Other' END;
SELECT CASE WHEN A = 1 THEN 10 ELSE 20 END * 2;
SELECT 2 * CASE WHEN A = 1 THEN 10 ELSE 20 END;
SELECT CASE WHEN A = 1 AND B = 2 THEN 'Both' ELSE 'Not' END;
SELECT CASE WHEN A = 1 OR B = 2 THEN 'Either' ELSE 'Neither' END;
GO

-- Pattern 16: Parentheses stress test
SELECT ((((1))));
SELECT ((1 + 2) * (3 + 4));
SELECT (((A + B) * (C + D)) / ((E + F) * (G + H)));
SELECT (SELECT (SELECT (SELECT 1)));
GO

-- Pattern 17: ALL/ANY/SOME with comparisons
SELECT * FROM T WHERE A > ALL (SELECT B FROM U);
SELECT * FROM T WHERE A > ANY (SELECT B FROM U);
SELECT * FROM T WHERE A > SOME (SELECT B FROM U);
SELECT * FROM T WHERE A = ANY (SELECT B FROM U);
SELECT * FROM T WHERE NOT A > ALL (SELECT B FROM U);
GO
