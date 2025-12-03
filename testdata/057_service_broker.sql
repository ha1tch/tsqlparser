-- Sample 057: Service Broker Messaging
-- Source: Microsoft Learn, MSSQLTips, Remus Rusanu blog
-- Category: Integration
-- Complexity: Advanced
-- Features: Service Broker queues, services, contracts, message processing

-- Setup Service Broker infrastructure
CREATE PROCEDURE dbo.SetupServiceBrokerInfrastructure
    @ServiceName NVARCHAR(128),
    @QueueName NVARCHAR(128) = NULL,
    @ContractName NVARCHAR(128) = NULL,
    @MessageTypeName NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    
    SET @QueueName = ISNULL(@QueueName, @ServiceName + 'Queue');
    SET @ContractName = ISNULL(@ContractName, @ServiceName + 'Contract');
    SET @MessageTypeName = ISNULL(@MessageTypeName, @ServiceName + 'Message');
    
    -- Enable Service Broker if not already enabled
    IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = DB_NAME() AND is_broker_enabled = 1)
    BEGIN
        SET @SQL = 'ALTER DATABASE ' + QUOTENAME(DB_NAME()) + ' SET ENABLE_BROKER WITH ROLLBACK IMMEDIATE';
        EXEC sp_executesql @SQL;
        PRINT 'Service Broker enabled';
    END
    
    -- Create message type
    IF NOT EXISTS (SELECT 1 FROM sys.service_message_types WHERE name = @MessageTypeName)
    BEGIN
        SET @SQL = 'CREATE MESSAGE TYPE ' + QUOTENAME(@MessageTypeName) + ' VALIDATION = WELL_FORMED_XML';
        EXEC sp_executesql @SQL;
        PRINT 'Message type created: ' + @MessageTypeName;
    END
    
    -- Create contract
    IF NOT EXISTS (SELECT 1 FROM sys.service_contracts WHERE name = @ContractName)
    BEGIN
        SET @SQL = 'CREATE CONTRACT ' + QUOTENAME(@ContractName) + ' (' + QUOTENAME(@MessageTypeName) + ' SENT BY INITIATOR)';
        EXEC sp_executesql @SQL;
        PRINT 'Contract created: ' + @ContractName;
    END
    
    -- Create queue
    IF NOT EXISTS (SELECT 1 FROM sys.service_queues WHERE name = @QueueName)
    BEGIN
        SET @SQL = 'CREATE QUEUE ' + QUOTENAME(@QueueName) + ' WITH STATUS = ON, RETENTION = OFF';
        EXEC sp_executesql @SQL;
        PRINT 'Queue created: ' + @QueueName;
    END
    
    -- Create service
    IF NOT EXISTS (SELECT 1 FROM sys.services WHERE name = @ServiceName)
    BEGIN
        SET @SQL = 'CREATE SERVICE ' + QUOTENAME(@ServiceName) + ' ON QUEUE ' + QUOTENAME(@QueueName) + ' (' + QUOTENAME(@ContractName) + ')';
        EXEC sp_executesql @SQL;
        PRINT 'Service created: ' + @ServiceName;
    END
    
    SELECT 'Service Broker infrastructure created' AS Status,
           @ServiceName AS ServiceName,
           @QueueName AS QueueName,
           @ContractName AS ContractName,
           @MessageTypeName AS MessageTypeName;
END
GO

-- Send a Service Broker message
CREATE PROCEDURE dbo.SendBrokerMessage
    @FromService NVARCHAR(128),
    @ToService NVARCHAR(128),
    @ContractName NVARCHAR(128),
    @MessageTypeName NVARCHAR(128),
    @MessageBody XML,
    @ConversationHandle UNIQUEIDENTIFIER OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @DialogHandle UNIQUEIDENTIFIER;
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        -- Begin dialog
        BEGIN DIALOG CONVERSATION @DialogHandle
            FROM SERVICE @FromService
            TO SERVICE @ToService
            ON CONTRACT @ContractName
            WITH ENCRYPTION = OFF;
        
        -- Send message
        SEND ON CONVERSATION @DialogHandle
            MESSAGE TYPE @MessageTypeName
            (@MessageBody);
        
        SET @ConversationHandle = @DialogHandle;
        
        COMMIT TRANSACTION;
        
        SELECT 'Message sent successfully' AS Status,
               @DialogHandle AS ConversationHandle;
               
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        SELECT 'Message send failed' AS Status,
               ERROR_MESSAGE() AS ErrorMessage;
        
        THROW;
    END CATCH
END
GO

-- Receive and process Service Broker messages
CREATE PROCEDURE dbo.ReceiveBrokerMessages
    @QueueName NVARCHAR(128),
    @MaxMessages INT = 10,
    @WaitTimeout INT = 5000  -- milliseconds
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @ConversationHandle UNIQUEIDENTIFIER;
    DECLARE @MessageTypeName NVARCHAR(256);
    DECLARE @MessageBody XML;
    DECLARE @ProcessedCount INT = 0;
    
    -- Create table to hold messages
    CREATE TABLE #Messages (
        conversation_handle UNIQUEIDENTIFIER,
        message_type_name NVARCHAR(256),
        message_body VARBINARY(MAX)
    );
    
    SET @SQL = N'
        WAITFOR (
            RECEIVE TOP (@MaxMsgs)
                conversation_handle,
                message_type_name,
                message_body
            FROM ' + QUOTENAME(@QueueName) + '
            INTO #Messages
        ), TIMEOUT @Timeout';
    
    EXEC sp_executesql @SQL,
        N'@MaxMsgs INT, @Timeout INT',
        @MaxMsgs = @MaxMessages,
        @Timeout = @WaitTimeout;
    
    -- Process each message
    DECLARE MsgCursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT conversation_handle, message_type_name, CAST(message_body AS XML)
        FROM #Messages;
    
    OPEN MsgCursor;
    FETCH NEXT FROM MsgCursor INTO @ConversationHandle, @MessageTypeName, @MessageBody;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF @MessageTypeName = 'http://schemas.microsoft.com/SQL/ServiceBroker/EndDialog'
        BEGIN
            END CONVERSATION @ConversationHandle;
        END
        ELSE IF @MessageTypeName = 'http://schemas.microsoft.com/SQL/ServiceBroker/Error'
        BEGIN
            -- Log error
            PRINT 'Error in conversation: ' + CAST(@ConversationHandle AS NVARCHAR(50));
            END CONVERSATION @ConversationHandle;
        END
        ELSE
        BEGIN
            -- Process business message
            -- Add your message processing logic here
            SET @ProcessedCount = @ProcessedCount + 1;
        END
        
        FETCH NEXT FROM MsgCursor INTO @ConversationHandle, @MessageTypeName, @MessageBody;
    END
    
    CLOSE MsgCursor;
    DEALLOCATE MsgCursor;
    
    -- Return received messages
    SELECT 
        conversation_handle AS ConversationHandle,
        message_type_name AS MessageType,
        CAST(message_body AS XML) AS MessageBody
    FROM #Messages;
    
    SELECT @ProcessedCount AS MessagesProcessed;
    
    DROP TABLE #Messages;
END
GO

-- End a conversation
CREATE PROCEDURE dbo.EndBrokerConversation
    @ConversationHandle UNIQUEIDENTIFIER,
    @WithCleanup BIT = 0,
    @ErrorCode INT = NULL,
    @ErrorMessage NVARCHAR(3000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    BEGIN TRY
        IF @ErrorCode IS NOT NULL
        BEGIN
            END CONVERSATION @ConversationHandle
                WITH ERROR = @ErrorCode
                DESCRIPTION = @ErrorMessage;
        END
        ELSE IF @WithCleanup = 1
        BEGIN
            END CONVERSATION @ConversationHandle WITH CLEANUP;
        END
        ELSE
        BEGIN
            END CONVERSATION @ConversationHandle;
        END
        
        SELECT 'Conversation ended successfully' AS Status;
    END TRY
    BEGIN CATCH
        SELECT 'Failed to end conversation' AS Status,
               ERROR_MESSAGE() AS ErrorMessage;
    END CATCH
END
GO

-- Get Service Broker status
CREATE PROCEDURE dbo.GetServiceBrokerStatus
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Database broker status
    SELECT 
        name AS DatabaseName,
        is_broker_enabled AS BrokerEnabled,
        service_broker_guid AS BrokerGUID
    FROM sys.databases
    WHERE database_id = DB_ID();
    
    -- Services
    SELECT 
        s.name AS ServiceName,
        q.name AS QueueName,
        q.is_receive_enabled AS ReceiveEnabled,
        q.is_enqueue_enabled AS EnqueueEnabled,
        q.is_activation_enabled AS ActivationEnabled
    FROM sys.services s
    INNER JOIN sys.service_queues q ON s.service_queue_id = q.object_id;
    
    -- Queue message counts
    SELECT 
        q.name AS QueueName,
        p.rows AS MessageCount
    FROM sys.service_queues q
    INNER JOIN sys.partitions p ON q.object_id = p.object_id
    WHERE p.index_id IN (0, 1);
    
    -- Active conversations
    SELECT 
        conversation_handle,
        is_initiator,
        s.name AS ServiceName,
        far_service AS FarService,
        state_desc AS State,
        lifetime AS Lifetime
    FROM sys.conversation_endpoints ce
    LEFT JOIN sys.services s ON ce.service_id = s.service_id
    ORDER BY lifetime DESC;
    
    -- Transmission queue (pending messages)
    SELECT 
        conversation_handle,
        to_service_name AS ToService,
        is_conversation_error AS IsError,
        transmission_status AS Status,
        DATALENGTH(message_body) AS MessageSizeBytes
    FROM sys.transmission_queue;
END
GO

-- Cleanup orphaned conversations
CREATE PROCEDURE dbo.CleanupOrphanedConversations
    @OlderThanHours INT = 24
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @Count INT = 0;
    DECLARE @Handle UNIQUEIDENTIFIER;
    
    DECLARE ConvCursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT conversation_handle
        FROM sys.conversation_endpoints
        WHERE state IN ('DI', 'DO', 'ER', 'CD')  -- Disconnected states
           OR (state = 'CO' AND DATEDIFF(HOUR, lifetime, GETDATE()) > @OlderThanHours);
    
    OPEN ConvCursor;
    FETCH NEXT FROM ConvCursor INTO @Handle;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            END CONVERSATION @Handle WITH CLEANUP;
            SET @Count = @Count + 1;
        END TRY
        BEGIN CATCH
            -- Continue on error
        END CATCH
        
        FETCH NEXT FROM ConvCursor INTO @Handle;
    END
    
    CLOSE ConvCursor;
    DEALLOCATE ConvCursor;
    
    SELECT @Count AS ConversationsCleaned;
END
GO
