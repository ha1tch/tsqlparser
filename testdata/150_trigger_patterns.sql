-- Sample 150: CREATE/ALTER TRIGGER Comprehensive Patterns
-- Category: Missing Syntax Elements / DDL
-- Complexity: Advanced
-- Purpose: Parser testing - all trigger syntax variations
-- Features: DML triggers, DDL triggers, INSTEAD OF, AFTER, FOR, nested

-- Pattern 1: Basic AFTER INSERT trigger
CREATE TRIGGER dbo.trg_Customers_AfterInsert
ON dbo.Customers
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    
    INSERT INTO dbo.AuditLog (TableName, Action, RecordID, ActionDate, ActionBy)
    SELECT 'Customers', 'INSERT', CustomerID, GETDATE(), SUSER_SNAME()
    FROM inserted;
END;
GO

-- Pattern 2: AFTER UPDATE trigger
CREATE TRIGGER dbo.trg_Customers_AfterUpdate
ON dbo.Customers
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    
    INSERT INTO dbo.AuditLog (TableName, Action, RecordID, OldValues, NewValues)
    SELECT 
        'Customers',
        'UPDATE',
        i.CustomerID,
        (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM inserted i
    INNER JOIN deleted d ON i.CustomerID = d.CustomerID;
END;
GO

-- Pattern 3: AFTER DELETE trigger
CREATE TRIGGER dbo.trg_Customers_AfterDelete
ON dbo.Customers
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;
    
    INSERT INTO dbo.DeletedRecords (TableName, RecordData, DeletedDate)
    SELECT 'Customers', (SELECT * FROM deleted FOR JSON PATH), GETDATE();
END;
GO

-- Pattern 4: Combined INSERT, UPDATE, DELETE trigger
CREATE TRIGGER dbo.trg_Orders_Audit
ON dbo.Orders
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @Action CHAR(1);
    
    IF EXISTS (SELECT 1 FROM inserted) AND EXISTS (SELECT 1 FROM deleted)
        SET @Action = 'U';
    ELSE IF EXISTS (SELECT 1 FROM inserted)
        SET @Action = 'I';
    ELSE
        SET @Action = 'D';
    
    INSERT INTO dbo.OrderAudit (OrderID, Action, ActionDate)
    SELECT 
        COALESCE(i.OrderID, d.OrderID),
        @Action,
        GETDATE()
    FROM inserted i
    FULL OUTER JOIN deleted d ON i.OrderID = d.OrderID;
END;
GO

-- Pattern 5: INSTEAD OF INSERT trigger (on view)
CREATE TRIGGER dbo.trg_vw_Customers_InsteadOfInsert
ON dbo.vw_Customers
INSTEAD OF INSERT
AS
BEGIN
    SET NOCOUNT ON;
    
    INSERT INTO dbo.Customers (FirstName, LastName, Email)
    SELECT FirstName, LastName, Email
    FROM inserted;
    
    INSERT INTO dbo.CustomerDetails (CustomerID, CreatedDate)
    SELECT SCOPE_IDENTITY(), GETDATE();
END;
GO

-- Pattern 6: INSTEAD OF UPDATE trigger
CREATE TRIGGER dbo.trg_vw_Customers_InsteadOfUpdate
ON dbo.vw_Customers
INSTEAD OF UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    
    UPDATE c
    SET 
        FirstName = i.FirstName,
        LastName = i.LastName,
        Email = i.Email,
        ModifiedDate = GETDATE()
    FROM dbo.Customers c
    INNER JOIN inserted i ON c.CustomerID = i.CustomerID;
END;
GO

-- Pattern 7: INSTEAD OF DELETE trigger
CREATE TRIGGER dbo.trg_vw_Customers_InsteadOfDelete
ON dbo.vw_Customers
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Soft delete instead of hard delete
    UPDATE c
    SET IsDeleted = 1, DeletedDate = GETDATE()
    FROM dbo.Customers c
    INNER JOIN deleted d ON c.CustomerID = d.CustomerID;
END;
GO

-- Pattern 8: Trigger with conditional logic using UPDATE()
CREATE TRIGGER dbo.trg_Employees_Salary
ON dbo.Employees
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    
    IF UPDATE(Salary)
    BEGIN
        INSERT INTO dbo.SalaryHistory (EmployeeID, OldSalary, NewSalary, ChangeDate)
        SELECT 
            i.EmployeeID,
            d.Salary,
            i.Salary,
            GETDATE()
        FROM inserted i
        INNER JOIN deleted d ON i.EmployeeID = d.EmployeeID
        WHERE i.Salary <> d.Salary;
    END
END;
GO

-- Pattern 9: Trigger with COLUMNS_UPDATED()
CREATE TRIGGER dbo.trg_Products_ColumnTracking
ON dbo.Products
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @ColumnsUpdated VARBINARY(128) = COLUMNS_UPDATED();
    
    -- Check specific columns (column ordinal positions)
    IF @ColumnsUpdated & 2 = 2  -- 2nd column (Price)
    BEGIN
        INSERT INTO dbo.PriceChangeLog (ProductID, ColumnName, OldValue, NewValue)
        SELECT i.ProductID, 'Price', CAST(d.Price AS NVARCHAR(50)), CAST(i.Price AS NVARCHAR(50))
        FROM inserted i
        INNER JOIN deleted d ON i.ProductID = d.ProductID;
    END
END;
GO

-- Pattern 10: Trigger with ROLLBACK
CREATE TRIGGER dbo.trg_Orders_ValidateAmount
ON dbo.Orders
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    
    IF EXISTS (SELECT 1 FROM inserted WHERE TotalAmount < 0)
    BEGIN
        RAISERROR('Order amount cannot be negative', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
END;
GO

-- Pattern 11: DDL Trigger on database
CREATE TRIGGER trg_DDL_TableChanges
ON DATABASE
FOR CREATE_TABLE, ALTER_TABLE, DROP_TABLE
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @EventData XML = EVENTDATA();
    
    INSERT INTO dbo.DDLAuditLog (EventType, ObjectName, LoginName, EventData, EventDate)
    SELECT 
        @EventData.value('(/EVENT_INSTANCE/EventType)[1]', 'NVARCHAR(100)'),
        @EventData.value('(/EVENT_INSTANCE/ObjectName)[1]', 'NVARCHAR(128)'),
        @EventData.value('(/EVENT_INSTANCE/LoginName)[1]', 'NVARCHAR(128)'),
        @EventData,
        GETDATE();
END;
GO

-- Pattern 12: DDL Trigger preventing operations
CREATE TRIGGER trg_DDL_PreventDrop
ON DATABASE
FOR DROP_TABLE
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @ObjectName NVARCHAR(128);
    SET @ObjectName = EVENTDATA().value('(/EVENT_INSTANCE/ObjectName)[1]', 'NVARCHAR(128)');
    
    IF @ObjectName IN ('Customers', 'Orders', 'Products')
    BEGIN
        RAISERROR('Cannot drop critical table %s', 16, 1, @ObjectName);
        ROLLBACK;
    END
END;
GO

-- Pattern 13: Server-level DDL trigger
CREATE TRIGGER trg_Server_LoginAudit
ON ALL SERVER
FOR CREATE_LOGIN, ALTER_LOGIN, DROP_LOGIN
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @EventData XML = EVENTDATA();
    
    INSERT INTO master.dbo.ServerAuditLog (EventType, ObjectName, EventData)
    SELECT 
        @EventData.value('(/EVENT_INSTANCE/EventType)[1]', 'NVARCHAR(100)'),
        @EventData.value('(/EVENT_INSTANCE/ObjectName)[1]', 'NVARCHAR(128)'),
        @EventData;
END;
GO

-- Pattern 14: Logon trigger
CREATE TRIGGER trg_LogonAudit
ON ALL SERVER
FOR LOGON
AS
BEGIN
    DECLARE @LoginName NVARCHAR(128) = ORIGINAL_LOGIN();
    DECLARE @HostName NVARCHAR(128) = HOST_NAME();
    
    -- Block certain logins from certain hosts
    IF @LoginName = 'RestrictedUser' AND @HostName NOT LIKE 'APP-SERVER%'
    BEGIN
        ROLLBACK;
    END
END;
GO

-- Pattern 15: Trigger with NOT FOR REPLICATION
CREATE TRIGGER dbo.trg_Customers_NotForReplication
ON dbo.Customers
AFTER INSERT
NOT FOR REPLICATION
AS
BEGIN
    SET NOCOUNT ON;
    -- This won't fire during replication
    INSERT INTO dbo.LocalAudit (TableName, Action)
    VALUES ('Customers', 'INSERT');
END;
GO

-- Pattern 16: Trigger with ENCRYPTION
CREATE TRIGGER dbo.trg_SecureAudit
ON dbo.SensitiveData
WITH ENCRYPTION
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    -- Trigger definition is encrypted
    INSERT INTO dbo.SecureAuditLog (EventTime) VALUES (GETDATE());
END;
GO

-- Pattern 17: Trigger with EXECUTE AS
CREATE TRIGGER dbo.trg_Orders_ProcessAs
ON dbo.Orders
WITH EXECUTE AS 'ProcessingUser'
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    -- Runs with ProcessingUser's permissions
    INSERT INTO dbo.OrderProcessingQueue (OrderID)
    SELECT OrderID FROM inserted;
END;
GO

-- Pattern 18: Nested trigger handling
CREATE TRIGGER dbo.trg_Parent_Insert
ON dbo.ParentTable
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    
    -- This insert will fire trg_Child_Insert if nested triggers are enabled
    INSERT INTO dbo.ChildTable (ParentID)
    SELECT ParentID FROM inserted;
END;
GO

-- Pattern 19: Recursive trigger handling
CREATE TRIGGER dbo.trg_Recursive
ON dbo.RecursiveTable
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Check recursion level to prevent infinite loop
    IF TRIGGER_NESTLEVEL() > 1
        RETURN;
    
    -- This update would cause recursion
    UPDATE dbo.RecursiveTable
    SET ModifiedCount = ModifiedCount + 1
    WHERE ID IN (SELECT ID FROM inserted);
END;
GO

-- Pattern 20: ALTER TRIGGER
ALTER TRIGGER dbo.trg_Customers_AfterInsert
ON dbo.Customers
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Modified logic
    INSERT INTO dbo.AuditLog (TableName, Action, RecordID, ActionDate, ActionBy, Details)
    SELECT 'Customers', 'INSERT', CustomerID, GETDATE(), SUSER_SNAME(), 
           (SELECT * FROM inserted FOR JSON PATH)
    FROM inserted;
END;
GO

-- Cleanup
DROP TRIGGER IF EXISTS dbo.trg_Customers_AfterInsert;
DROP TRIGGER IF EXISTS dbo.trg_Customers_AfterUpdate;
DROP TRIGGER IF EXISTS dbo.trg_Customers_AfterDelete;
DROP TRIGGER IF EXISTS dbo.trg_Orders_Audit;
DROP TRIGGER IF EXISTS trg_DDL_TableChanges ON DATABASE;
DROP TRIGGER IF EXISTS trg_DDL_PreventDrop ON DATABASE;
DROP TRIGGER IF EXISTS trg_Server_LoginAudit ON ALL SERVER;
DROP TRIGGER IF EXISTS trg_LogonAudit ON ALL SERVER;
GO
