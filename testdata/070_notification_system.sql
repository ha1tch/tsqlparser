-- Sample 070: Email Notification System
-- Source: Microsoft Learn, MSSQLTips, Stack Overflow
-- Category: Integration
-- Complexity: Complex
-- Features: Database Mail, HTML formatting, attachment handling, templating

-- Create notification subscription table
CREATE PROCEDURE dbo.SetupNotificationSystem
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Notification templates
    IF OBJECT_ID('dbo.NotificationTemplates', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.NotificationTemplates (
            TemplateID INT IDENTITY(1,1) PRIMARY KEY,
            TemplateName NVARCHAR(100) UNIQUE NOT NULL,
            Subject NVARCHAR(500) NOT NULL,
            BodyHTML NVARCHAR(MAX) NOT NULL,
            BodyText NVARCHAR(MAX),
            IsActive BIT DEFAULT 1,
            CreatedDate DATETIME2 DEFAULT SYSDATETIME(),
            ModifiedDate DATETIME2 DEFAULT SYSDATETIME()
        );
        
        -- Insert default templates
        INSERT INTO dbo.NotificationTemplates (TemplateName, Subject, BodyHTML, BodyText)
        VALUES 
        ('JobSuccess', 'Job Completed Successfully: {{JobName}}',
         '<html><body><h2 style="color:green">Job Success</h2><p>Job <b>{{JobName}}</b> completed at {{CompletedTime}}.</p><p>Duration: {{Duration}}</p></body></html>',
         'Job {{JobName}} completed successfully at {{CompletedTime}}. Duration: {{Duration}}'),
        
        ('JobFailure', 'ALERT: Job Failed - {{JobName}}',
         '<html><body><h2 style="color:red">Job Failure Alert</h2><p>Job <b>{{JobName}}</b> failed at {{FailedTime}}.</p><p>Error: {{ErrorMessage}}</p></body></html>',
         'ALERT: Job {{JobName}} failed at {{FailedTime}}. Error: {{ErrorMessage}}'),
        
        ('DiskSpaceWarning', 'WARNING: Low Disk Space on {{ServerName}}',
         '<html><body><h2 style="color:orange">Disk Space Warning</h2><p>Server: {{ServerName}}</p><p>Drive {{DriveLetter}} has only {{FreeSpaceGB}} GB free ({{FreePercent}}%).</p></body></html>',
         'WARNING: Low disk space on {{ServerName}}. Drive {{DriveLetter}}: {{FreeSpaceGB}} GB free ({{FreePercent}}%)');
    END
    
    -- Notification subscriptions
    IF OBJECT_ID('dbo.NotificationSubscriptions', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.NotificationSubscriptions (
            SubscriptionID INT IDENTITY(1,1) PRIMARY KEY,
            TemplateName NVARCHAR(100) NOT NULL,
            EmailAddress NVARCHAR(500) NOT NULL,
            IsActive BIT DEFAULT 1,
            CreatedDate DATETIME2 DEFAULT SYSDATETIME()
        );
    END
    
    -- Notification log
    IF OBJECT_ID('dbo.NotificationLog', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.NotificationLog (
            LogID BIGINT IDENTITY(1,1) PRIMARY KEY,
            TemplateName NVARCHAR(100),
            Recipients NVARCHAR(MAX),
            Subject NVARCHAR(500),
            SentDate DATETIME2 DEFAULT SYSDATETIME(),
            Status NVARCHAR(50),
            ErrorMessage NVARCHAR(MAX),
            MailItemId INT
        );
    END
    
    SELECT 'Notification system tables created' AS Status;
END
GO

-- Send templated notification
CREATE PROCEDURE dbo.SendTemplatedNotification
    @TemplateName NVARCHAR(100),
    @Recipients NVARCHAR(MAX) = NULL,  -- NULL = use subscriptions
    @Parameters NVARCHAR(MAX) = NULL,  -- JSON: {"JobName":"MyJob","Duration":"5 min"}
    @Attachments NVARCHAR(MAX) = NULL,
    @ProfileName NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @Subject NVARCHAR(500);
    DECLARE @BodyHTML NVARCHAR(MAX);
    DECLARE @BodyText NVARCHAR(MAX);
    DECLARE @MailItemId INT;
    DECLARE @Status NVARCHAR(50) = 'Sent';
    DECLARE @ErrorMessage NVARCHAR(MAX);
    
    -- Get template
    SELECT @Subject = Subject, @BodyHTML = BodyHTML, @BodyText = BodyText
    FROM dbo.NotificationTemplates
    WHERE TemplateName = @TemplateName AND IsActive = 1;
    
    IF @Subject IS NULL
    BEGIN
        RAISERROR('Template not found or inactive: %s', 16, 1, @TemplateName);
        RETURN;
    END
    
    -- Get recipients from subscriptions if not provided
    IF @Recipients IS NULL
    BEGIN
        SELECT @Recipients = STRING_AGG(EmailAddress, ';')
        FROM dbo.NotificationSubscriptions
        WHERE TemplateName = @TemplateName AND IsActive = 1;
    END
    
    IF @Recipients IS NULL OR @Recipients = ''
    BEGIN
        RAISERROR('No recipients specified or subscribed for template: %s', 16, 1, @TemplateName);
        RETURN;
    END
    
    -- Replace parameters in template
    IF @Parameters IS NOT NULL
    BEGIN
        DECLARE @Key NVARCHAR(100), @Value NVARCHAR(MAX);
        
        DECLARE ParamCursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT [key], [value]
            FROM OPENJSON(@Parameters);
        
        OPEN ParamCursor;
        FETCH NEXT FROM ParamCursor INTO @Key, @Value;
        
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @Subject = REPLACE(@Subject, '{{' + @Key + '}}', ISNULL(@Value, ''));
            SET @BodyHTML = REPLACE(@BodyHTML, '{{' + @Key + '}}', ISNULL(@Value, ''));
            SET @BodyText = REPLACE(@BodyText, '{{' + @Key + '}}', ISNULL(@Value, ''));
            
            FETCH NEXT FROM ParamCursor INTO @Key, @Value;
        END
        
        CLOSE ParamCursor;
        DEALLOCATE ParamCursor;
    END
    
    -- Send email
    BEGIN TRY
        EXEC msdb.dbo.sp_send_dbmail
            @profile_name = @ProfileName,
            @recipients = @Recipients,
            @subject = @Subject,
            @body = @BodyHTML,
            @body_format = 'HTML',
            @file_attachments = @Attachments,
            @mailitem_id = @MailItemId OUTPUT;
        
        SET @Status = 'Sent';
    END TRY
    BEGIN CATCH
        SET @Status = 'Failed';
        SET @ErrorMessage = ERROR_MESSAGE();
    END CATCH
    
    -- Log notification
    INSERT INTO dbo.NotificationLog (TemplateName, Recipients, Subject, Status, ErrorMessage, MailItemId)
    VALUES (@TemplateName, @Recipients, @Subject, @Status, @ErrorMessage, @MailItemId);
    
    SELECT @Status AS Status, @MailItemId AS MailItemId, @ErrorMessage AS ErrorMessage;
END
GO

-- Send HTML table report via email
CREATE PROCEDURE dbo.SendQueryResultsAsEmail
    @Query NVARCHAR(MAX),
    @Recipients NVARCHAR(MAX),
    @Subject NVARCHAR(500),
    @IntroText NVARCHAR(MAX) = NULL,
    @ProfileName NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @HTML NVARCHAR(MAX);
    DECLARE @TableHTML NVARCHAR(MAX) = '';
    DECLARE @Columns NVARCHAR(MAX) = '';
    DECLARE @SQL NVARCHAR(MAX);
    
    -- Create temp table to hold results
    CREATE TABLE #Results (RowData NVARCHAR(MAX));
    
    -- Build HTML table header and rows dynamically
    SET @SQL = N'
        DECLARE @Header NVARCHAR(MAX) = '''';
        DECLARE @Rows NVARCHAR(MAX) = '''';
        
        -- This is a simplified approach - for complex queries, use FOR XML PATH
        SELECT @Header = @Header + ''<th>'' + name + ''</th>''
        FROM sys.dm_exec_describe_first_result_set(@Query, NULL, 0);
        
        SET @Header = ''<tr style="background-color:#4472C4;color:white;">'' + @Header + ''</tr>'';
        
        INSERT INTO #Results SELECT @Header;
    ';
    
    -- Execute query and format as HTML
    SET @SQL = N'
        ;WITH QueryResults AS (' + @Query + ')
        SELECT 
            ''<tr>'' + 
            (SELECT ''<td>'' + ISNULL(CAST(col AS NVARCHAR(MAX)), '''') + ''</td>''
             FROM (SELECT * FROM QueryResults) AS src
             FOR XML PATH(''''), TYPE).value(''.'', ''NVARCHAR(MAX)'') +
            ''</tr>''
        FROM QueryResults';
    
    -- Build complete HTML
    SET @HTML = N'
        <html>
        <head>
            <style>
                body { font-family: Arial, sans-serif; }
                table { border-collapse: collapse; width: 100%; }
                th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
                tr:nth-child(even) { background-color: #f2f2f2; }
                th { background-color: #4472C4; color: white; }
            </style>
        </head>
        <body>
            <p>' + ISNULL(@IntroText, '') + '</p>
            <table>
                ' + @TableHTML + '
            </table>
            <p style="color:gray;font-size:10px;">Generated at ' + CONVERT(VARCHAR(30), SYSDATETIME(), 121) + '</p>
        </body>
        </html>';
    
    -- Send email
    EXEC msdb.dbo.sp_send_dbmail
        @profile_name = @ProfileName,
        @recipients = @Recipients,
        @subject = @Subject,
        @body = @HTML,
        @body_format = 'HTML',
        @query = @Query,
        @attach_query_result_as_file = 1,
        @query_attachment_filename = 'QueryResults.csv',
        @query_result_separator = ',';
    
    DROP TABLE #Results;
    
    SELECT 'Email sent with query results' AS Status;
END
GO

-- Subscribe/unsubscribe from notifications
CREATE PROCEDURE dbo.ManageNotificationSubscription
    @Action NVARCHAR(20),  -- SUBSCRIBE, UNSUBSCRIBE, LIST
    @TemplateName NVARCHAR(100) = NULL,
    @EmailAddress NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    IF @Action = 'SUBSCRIBE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM dbo.NotificationSubscriptions WHERE TemplateName = @TemplateName AND EmailAddress = @EmailAddress)
        BEGIN
            INSERT INTO dbo.NotificationSubscriptions (TemplateName, EmailAddress)
            VALUES (@TemplateName, @EmailAddress);
            SELECT 'Subscribed successfully' AS Status;
        END
        ELSE
        BEGIN
            UPDATE dbo.NotificationSubscriptions SET IsActive = 1
            WHERE TemplateName = @TemplateName AND EmailAddress = @EmailAddress;
            SELECT 'Subscription reactivated' AS Status;
        END
    END
    ELSE IF @Action = 'UNSUBSCRIBE'
    BEGIN
        UPDATE dbo.NotificationSubscriptions SET IsActive = 0
        WHERE TemplateName = @TemplateName AND EmailAddress = @EmailAddress;
        SELECT 'Unsubscribed successfully' AS Status;
    END
    ELSE IF @Action = 'LIST'
    BEGIN
        SELECT TemplateName, EmailAddress, IsActive, CreatedDate
        FROM dbo.NotificationSubscriptions
        WHERE (@TemplateName IS NULL OR TemplateName = @TemplateName)
          AND (@EmailAddress IS NULL OR EmailAddress = @EmailAddress)
        ORDER BY TemplateName, EmailAddress;
    END
END
GO

-- Get notification history
CREATE PROCEDURE dbo.GetNotificationHistory
    @TemplateName NVARCHAR(100) = NULL,
    @DaysBack INT = 7,
    @StatusFilter NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        LogID,
        TemplateName,
        Recipients,
        Subject,
        SentDate,
        Status,
        ErrorMessage,
        MailItemId
    FROM dbo.NotificationLog
    WHERE SentDate >= DATEADD(DAY, -@DaysBack, SYSDATETIME())
      AND (@TemplateName IS NULL OR TemplateName = @TemplateName)
      AND (@StatusFilter IS NULL OR Status = @StatusFilter)
    ORDER BY SentDate DESC;
    
    -- Summary
    SELECT 
        CAST(SentDate AS DATE) AS NotificationDate,
        Status,
        COUNT(*) AS NotificationCount
    FROM dbo.NotificationLog
    WHERE SentDate >= DATEADD(DAY, -@DaysBack, SYSDATETIME())
    GROUP BY CAST(SentDate AS DATE), Status
    ORDER BY NotificationDate DESC, Status;
END
GO
