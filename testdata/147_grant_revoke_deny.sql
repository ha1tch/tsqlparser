-- Sample 147: GRANT, REVOKE, DENY Permission Statements
-- Category: Missing Syntax Elements
-- Complexity: Complex
-- Purpose: Parser testing - security permission syntax
-- Features: All permission statement variations, WITH GRANT OPTION, CASCADE

-- Pattern 1: Basic GRANT on table
GRANT SELECT ON dbo.Customers TO AppUser;
GRANT INSERT ON dbo.Customers TO AppUser;
GRANT UPDATE ON dbo.Customers TO AppUser;
GRANT DELETE ON dbo.Customers TO AppUser;
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.Customers TO AppUser;
GO

-- Pattern 2: GRANT with column-level permissions
GRANT SELECT ON dbo.Customers (CustomerID, FirstName, LastName) TO ReportUser;
GRANT UPDATE ON dbo.Customers (Email, Phone) TO SupportUser;
GO

-- Pattern 3: GRANT on multiple objects
GRANT SELECT ON dbo.Customers TO AppUser;
GRANT SELECT ON dbo.Orders TO AppUser;
GRANT SELECT ON dbo.Products TO AppUser;
GO

-- Pattern 4: GRANT to multiple principals
GRANT SELECT ON dbo.Customers TO AppUser, ReportUser, AnalystUser;
GRANT EXECUTE ON dbo.GetCustomerOrders TO AppUser, ServiceAccount;
GO

-- Pattern 5: GRANT on stored procedure
GRANT EXECUTE ON dbo.GetCustomerOrders TO AppUser;
GRANT EXECUTE ON OBJECT::dbo.ProcessOrder TO AppUser;
GO

-- Pattern 6: GRANT on function
GRANT EXECUTE ON dbo.fn_GetFullName TO AppUser;
GRANT SELECT ON dbo.fn_GetOrders TO AppUser;  -- Table-valued function
GRANT REFERENCES ON dbo.fn_GetFullName TO AppUser;
GO

-- Pattern 7: GRANT on schema
GRANT SELECT ON SCHEMA::Sales TO ReportUser;
GRANT INSERT, UPDATE, DELETE ON SCHEMA::Sales TO DataEntryUser;
GRANT EXECUTE ON SCHEMA::Sales TO AppUser;
GO

-- Pattern 8: GRANT WITH GRANT OPTION
GRANT SELECT ON dbo.Customers TO TeamLead WITH GRANT OPTION;
GRANT EXECUTE ON dbo.GetCustomerOrders TO TeamLead WITH GRANT OPTION;
GO

-- Pattern 9: GRANT database-level permissions
GRANT CREATE TABLE TO Developer;
GRANT CREATE VIEW TO Developer;
GRANT CREATE PROCEDURE TO Developer;
GRANT CREATE FUNCTION TO Developer;
GRANT ALTER ANY SCHEMA TO DbAdmin;
GRANT BACKUP DATABASE TO BackupOperator;
GRANT BACKUP LOG TO BackupOperator;
GO

-- Pattern 10: GRANT server-level permissions
GRANT VIEW SERVER STATE TO MonitoringUser;
GRANT ALTER ANY DATABASE TO DbAdmin;
GRANT CREATE ANY DATABASE TO DbAdmin;
GRANT CONNECT SQL TO AppLogin;
GRANT VIEW ANY DEFINITION TO Developer;
GO

-- Pattern 11: Basic DENY
DENY SELECT ON dbo.Customers TO RestrictedUser;
DENY DELETE ON dbo.Orders TO StandardUser;
DENY EXECUTE ON dbo.DeleteAllData TO PUBLIC;
GO

-- Pattern 12: DENY column-level
DENY SELECT ON dbo.Customers (SSN, CreditCardNumber) TO ReportUser;
DENY UPDATE ON dbo.Employees (Salary, BonusAmount) TO ManagerUser;
GO

-- Pattern 13: DENY on schema
DENY SELECT ON SCHEMA::HR TO ExternalUser;
DENY INSERT, UPDATE, DELETE ON SCHEMA::Finance TO ReadOnlyUser;
GO

-- Pattern 14: DENY CASCADE
DENY SELECT ON dbo.Customers TO TeamLead CASCADE;
-- Removes permission from TeamLead and anyone they granted to
GO

-- Pattern 15: Basic REVOKE
REVOKE SELECT ON dbo.Customers FROM AppUser;
REVOKE INSERT, UPDATE ON dbo.Customers FROM AppUser;
REVOKE EXECUTE ON dbo.GetCustomerOrders FROM AppUser;
GO

-- Pattern 16: REVOKE GRANT OPTION FOR
REVOKE GRANT OPTION FOR SELECT ON dbo.Customers FROM TeamLead;
-- TeamLead keeps SELECT but can no longer grant it
GO

-- Pattern 17: REVOKE CASCADE
REVOKE SELECT ON dbo.Customers FROM TeamLead CASCADE;
-- Revokes from TeamLead and everyone they granted to
GO

-- Pattern 18: GRANT on type
GRANT EXECUTE ON TYPE::dbo.OrderDetailsType TO AppUser;
GRANT REFERENCES ON TYPE::dbo.AddressType TO Developer;
GO

-- Pattern 19: GRANT on XML schema collection
GRANT ALTER ON XML SCHEMA COLLECTION::dbo.CustomerXmlSchema TO Developer;
GRANT REFERENCES ON XML SCHEMA COLLECTION::dbo.OrderXmlSchema TO AppUser;
GO

-- Pattern 20: GRANT on sequence
GRANT UPDATE ON OBJECT::dbo.OrderNumberSequence TO AppUser;
GO

-- Pattern 21: GRANT on certificate
GRANT CONTROL ON CERTIFICATE::MyCertificate TO DbAdmin;
GRANT VIEW DEFINITION ON CERTIFICATE::MyCertificate TO Auditor;
GO

-- Pattern 22: GRANT on asymmetric key
GRANT CONTROL ON ASYMMETRIC KEY::MyAsymKey TO SecurityAdmin;
GRANT VIEW DEFINITION ON ASYMMETRIC KEY::MyAsymKey TO Auditor;
GO

-- Pattern 23: GRANT on symmetric key
GRANT VIEW DEFINITION ON SYMMETRIC KEY::MySymKey TO Auditor;
GO

-- Pattern 24: Role-based permission patterns
-- Create custom role
CREATE ROLE DataReader;
GRANT SELECT ON SCHEMA::dbo TO DataReader;

CREATE ROLE DataWriter;
GRANT INSERT, UPDATE, DELETE ON SCHEMA::dbo TO DataWriter;

CREATE ROLE AppExecutor;
GRANT EXECUTE ON SCHEMA::dbo TO AppExecutor;

-- Add users to roles
ALTER ROLE DataReader ADD MEMBER ReportUser;
ALTER ROLE DataWriter ADD MEMBER DataEntryUser;
ALTER ROLE AppExecutor ADD MEMBER AppServiceAccount;
GO

-- Pattern 25: GRANT IMPERSONATE
GRANT IMPERSONATE ON USER::AppServiceUser TO AppLogin;
GRANT IMPERSONATE ON LOGIN::sa TO EmergencyAdmin;
GO

-- Pattern 26: GRANT TAKE OWNERSHIP
GRANT TAKE OWNERSHIP ON SCHEMA::Sales TO DbOwner;
GRANT TAKE OWNERSHIP ON OBJECT::dbo.CriticalTable TO DbAdmin;
GO

-- Pattern 27: GRANT to application role
GRANT SELECT ON dbo.Customers TO AppRole;
GRANT EXECUTE ON dbo.GetCustomerOrders TO AppRole;
GO

-- Pattern 28: GRANT on linked server
GRANT CONNECT ON SERVER::LinkedServerName TO AppLogin;
GO

-- Pattern 29: GRANT on endpoint
GRANT CONNECT ON ENDPOINT::DatabaseMirroringEndpoint TO MirrorLogin;
GO

-- Pattern 30: Permission checking
SELECT 
    HAS_PERMS_BY_NAME('dbo.Customers', 'OBJECT', 'SELECT') AS CanSelect,
    HAS_PERMS_BY_NAME('dbo.Customers', 'OBJECT', 'INSERT') AS CanInsert,
    HAS_PERMS_BY_NAME('dbo.Customers', 'OBJECT', 'UPDATE') AS CanUpdate,
    HAS_PERMS_BY_NAME('dbo.Customers', 'OBJECT', 'DELETE') AS CanDelete;
GO

-- Cleanup roles
DROP ROLE IF EXISTS DataReader;
DROP ROLE IF EXISTS DataWriter;
DROP ROLE IF EXISTS AppExecutor;
GO
