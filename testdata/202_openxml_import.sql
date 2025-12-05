-- Parse XML using OPENXML (legacy pattern)
CREATE PROCEDURE dbo.ImportEmployeesXml
    @XmlData NVARCHAR(MAX)
AS
BEGIN
    DECLARE @idoc INT
    
    -- Prepare XML document
    EXEC sp_xml_preparedocument @idoc OUTPUT, @XmlData
    
    -- Extract data using OPENXML
    SELECT *
    FROM OPENXML(@idoc, '/employees/employee', 2)
    WITH (
        EmployeeId INT '@id',
        FirstName NVARCHAR(50) 'firstName',
        LastName NVARCHAR(50) 'lastName',
        Email NVARCHAR(100) 'email',
        Department NVARCHAR(50) 'department',
        HireDate DATE 'hireDate',
        Salary DECIMAL(10,2) 'salary'
    )
    ORDER BY LastName, FirstName
    
    -- Remove XML document from memory
    EXEC sp_xml_removedocument @idoc
END
