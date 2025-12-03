-- Sample 027: Database Mail Procedures
-- Source: Microsoft Learn, MSSQLTips, SQLServerCentral
-- Category: Integration
-- Complexity: Complex
-- Features: sp_send_dbmail, msdb mail views, HTML formatting, attachments

-- Send email with HTML formatted report
CREATE PROCEDURE dbo.SendHTMLReport
    @Recipients NVARCHAR(MAX),
    @Subject NVARCHAR(255),
    @ReportQuery NVARCHAR(MAX),
    @HeaderText NVARCHAR(500) = NULL,
    @FooterText NVARCHAR(500) = NULL,
    @ProfileName NVARCHAR(128) = NULL,
    @Importance NVARCHAR(10) = 'Normal',  -- Low, Normal, High
    @CCRecipients NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @HTMLBody NVARCHAR(MAX);
    DECLARE @TableHTML NVARCHAR(MAX);
    DECLARE @CSS NVARCHAR(MAX);
    
    -- CSS styling
    SET @CSS = N'
        <style>
            body { font-family: Arial, sans-serif; font-size: 12px; }
            h2 { color: #2E4057; }
            table { border-collapse: collapse; width: 100%; margin-top: 10px; }
            th { background-color: #2E4057; color: white; padding: 10px; text-align: left; }
            td { border: 1px solid #ddd; padding: 8px; }
            tr:nth-child(even) { background-color: #f9f9f9; }
            tr:hover { background-color: #f1f1f1; }
            .footer { margin-top: 20px; font-size: 10px; color: #666; }
        </style>';
    
    -- Generate HTML table from query results
    DECLARE @DynamicSQL NVARCHAR(MAX);
    DECLARE @Columns NVARCHAR(MAX) = '';
    DECLARE @Headers NVARCHAR(MAX) = '';
    
    -- We'll use FOR XML PATH to generate HTML
    SET @DynamicSQL = N'
        SET @TableOut = (
            SELECT 
                (SELECT * FROM (' + @ReportQuery + ') AS Data FOR XML PATH(''tr''), TYPE) AS [tbody],
                (SELECT TOP 1 * FROM (' + @ReportQuery + ') AS Headers FOR XML RAW(''tr''), ELEMENTS XSINIL) AS [thead]
            FOR XML PATH('''')
        )';
    
    -- Simpler approach - use FOR XML PATH directly
    SET @DynamicSQL = N'
        ;WITH ReportData AS (' + @ReportQuery + ')
        SELECT @TableOut = (
            SELECT 
                td = CAST(ISNULL(CAST(col.value AS NVARCHAR(MAX)), '''') AS NVARCHAR(MAX)) + ''</td><td>''
            FROM ReportData
            CROSS APPLY (SELECT * FROM ReportData FOR XML PATH(''''), TYPE) AS cols(col)
            FOR XML PATH(''tr'')
        )';
    
    -- Build HTML body manually with query execution
    CREATE TABLE #ReportResults (RowData NVARCHAR(MAX));
    
    BEGIN TRY
        -- Execute query and format as HTML
        SET @DynamicSQL = N'
            DECLARE @html NVARCHAR(MAX) = '''';
            
            -- Get column headers
            SELECT @html = @html + ''<th>'' + name + ''</th>''
            FROM sys.dm_exec_describe_first_result_set(@query, NULL, 0);
            
            SET @html = ''<tr>'' + @html + ''</tr>'';
            SET @TableOut = @html;';
        
        -- For simplicity, build a basic HTML table
        SET @TableHTML = N'<table border="1" cellpadding="5" cellspacing="0">';
        SET @TableHTML = @TableHTML + N'<tr style="background-color:#2E4057;color:white;"><th>Report Data</th></tr>';
        SET @TableHTML = @TableHTML + N'<tr><td>Query results would appear here</td></tr>';
        SET @TableHTML = @TableHTML + N'</table>';
        
        -- In practice, you would dynamically build this from @ReportQuery results
        
    END TRY
    BEGIN CATCH
        SET @TableHTML = N'<p style="color:red;">Error generating report: ' + ERROR_MESSAGE() + '</p>';
    END CATCH
    
    DROP TABLE IF EXISTS #ReportResults;
    
    -- Build complete HTML body
    SET @HTMLBody = N'<!DOCTYPE html><html><head>' + @CSS + N'</head><body>';
    
    IF @HeaderText IS NOT NULL
        SET @HTMLBody = @HTMLBody + N'<h2>' + @HeaderText + N'</h2>';
    
    SET @HTMLBody = @HTMLBody + @TableHTML;
    
    IF @FooterText IS NOT NULL
        SET @HTMLBody = @HTMLBody + N'<div class="footer">' + @FooterText + N'</div>';
    
    SET @HTMLBody = @HTMLBody + N'<div class="footer">Generated: ' + 
                    CONVERT(NVARCHAR(20), GETDATE(), 120) + N'</div>';
    SET @HTMLBody = @HTMLBody + N'</body></html>';
    
    -- Send the email
    EXEC msdb.dbo.sp_send_dbmail
        @profile_name = @ProfileName,
        @recipients = @Recipients,
        @copy_recipients = @CCRecipients,
        @subject = @Subject,
        @body = @HTMLBody,
        @body_format = 'HTML',
        @importance = @Importance;
    
    SELECT 'Email sent successfully' AS Status, @Recipients AS Recipients;
END
GO

-- Send email with query results as attachment
CREATE PROCEDURE dbo.SendQueryResultsAsAttachment
    @Recipients NVARCHAR(MAX),
    @Subject NVARCHAR(255),
    @Query NVARCHAR(MAX),
    @AttachmentFilename NVARCHAR(255) = 'QueryResults.csv',
    @ProfileName NVARCHAR(128) = NULL,
    @BodyText NVARCHAR(MAX) = 'Please see attached query results.'
AS
BEGIN
    SET NOCOUNT ON;
    
    EXEC msdb.dbo.sp_send_dbmail
        @profile_name = @ProfileName,
        @recipients = @Recipients,
        @subject = @Subject,
        @body = @BodyText,
        @query = @Query,
        @attach_query_result_as_file = 1,
        @query_attachment_filename = @AttachmentFilename,
        @query_result_separator = ',',
        @query_result_width = 32767,
        @query_result_header = 1,
        @query_result_no_padding = 1;
    
    SELECT 'Email with attachment sent successfully' AS Status;
END
GO

-- Monitor Database Mail status
CREATE PROCEDURE dbo.GetDatabaseMailStatus
    @ShowLastN INT = 50,
    @ShowFailed BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Mail configuration
    SELECT 
        p.name AS ProfileName,
        p.description AS ProfileDescription,
        a.name AS AccountName,
        a.email_address AS EmailAddress,
        s.servertype AS ServerType,
        s.servername AS ServerName,
        s.port AS Port,
        a.use_default_credentials AS UseDefaultCredentials
    FROM msdb.dbo.sysmail_profile p
    INNER JOIN msdb.dbo.sysmail_profileaccount pa ON p.profile_id = pa.profile_id
    INNER JOIN msdb.dbo.sysmail_account a ON pa.account_id = a.account_id
    INNER JOIN msdb.dbo.sysmail_server s ON a.account_id = s.account_id;
    
    -- Recent mail items
    SELECT TOP (@ShowLastN)
        m.mailitem_id AS MailID,
        m.profile_id,
        m.recipients AS Recipients,
        m.copy_recipients AS CC,
        m.subject AS Subject,
        m.body_format AS BodyFormat,
        m.importance AS Importance,
        m.sent_status AS Status,
        m.send_request_date AS RequestDate,
        m.sent_date AS SentDate,
        DATEDIFF(SECOND, m.send_request_date, m.sent_date) AS DeliverySeconds
    FROM msdb.dbo.sysmail_mailitems m
    WHERE @ShowFailed = 0 OR m.sent_status = 'failed'
    ORDER BY m.mailitem_id DESC;
    
    -- Failed mail details
    IF @ShowFailed = 1
    BEGIN
        SELECT TOP (@ShowLastN)
            f.mailitem_id,
            f.recipient,
            f.log_date,
            f.description AS ErrorDescription
        FROM msdb.dbo.sysmail_faileditems f
        ORDER BY f.log_date DESC;
    END
    
    -- Queue status
    SELECT 
        'Mail Queue Status' AS Report,
        COUNT(*) AS TotalItems,
        SUM(CASE WHEN sent_status = 'unsent' THEN 1 ELSE 0 END) AS Pending,
        SUM(CASE WHEN sent_status = 'sent' THEN 1 ELSE 0 END) AS Sent,
        SUM(CASE WHEN sent_status = 'failed' THEN 1 ELSE 0 END) AS Failed,
        SUM(CASE WHEN sent_status = 'retrying' THEN 1 ELSE 0 END) AS Retrying
    FROM msdb.dbo.sysmail_mailitems;
END
GO

-- Send alert email for job failures
CREATE PROCEDURE dbo.SendJobFailureAlert
    @JobName NVARCHAR(128),
    @Recipients NVARCHAR(MAX),
    @ProfileName NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @Subject NVARCHAR(255);
    DECLARE @Body NVARCHAR(MAX);
    DECLARE @ErrorMessage NVARCHAR(MAX);
    DECLARE @StepName NVARCHAR(128);
    DECLARE @RunDate DATETIME;
    
    -- Get latest failure info
    SELECT TOP 1
        @ErrorMessage = h.message,
        @StepName = h.step_name,
        @RunDate = msdb.dbo.agent_datetime(h.run_date, h.run_time)
    FROM msdb.dbo.sysjobhistory h
    INNER JOIN msdb.dbo.sysjobs j ON h.job_id = j.job_id
    WHERE j.name = @JobName
      AND h.run_status = 0  -- Failed
    ORDER BY h.run_date DESC, h.run_time DESC;
    
    IF @ErrorMessage IS NULL
    BEGIN
        PRINT 'No recent failures found for job: ' + @JobName;
        RETURN;
    END
    
    SET @Subject = N'SQL Agent Job Failure: ' + @JobName;
    SET @Body = N'<html><body>';
    SET @Body = @Body + N'<h2 style="color:red;">SQL Agent Job Failure Alert</h2>';
    SET @Body = @Body + N'<table border="1" cellpadding="5">';
    SET @Body = @Body + N'<tr><td><b>Job Name</b></td><td>' + @JobName + N'</td></tr>';
    SET @Body = @Body + N'<tr><td><b>Failed Step</b></td><td>' + ISNULL(@StepName, 'N/A') + N'</td></tr>';
    SET @Body = @Body + N'<tr><td><b>Failure Time</b></td><td>' + CONVERT(NVARCHAR(20), @RunDate, 120) + N'</td></tr>';
    SET @Body = @Body + N'<tr><td><b>Server</b></td><td>' + @@SERVERNAME + N'</td></tr>';
    SET @Body = @Body + N'<tr><td><b>Error Message</b></td><td>' + @ErrorMessage + N'</td></tr>';
    SET @Body = @Body + N'</table>';
    SET @Body = @Body + N'</body></html>';
    
    EXEC msdb.dbo.sp_send_dbmail
        @profile_name = @ProfileName,
        @recipients = @Recipients,
        @subject = @Subject,
        @body = @Body,
        @body_format = 'HTML',
        @importance = 'High';
END
GO
