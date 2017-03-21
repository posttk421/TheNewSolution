USE [DBA]
GO

/****** Object:  StoredProcedure [dbo].[sp_logMsg]    Script Date: 02/08/2017 08:40:23 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


ALTER PROCEDURE [dbo].[sp_logMsg]
	(
	@MessageSeverity INT
	, @MessageType VARCHAR(50)
	, @MessageShort VARCHAR(200)
	, @MessageLong VARCHAR(MAX)
	, @GeneratedBy VARCHAR(100)
	)
AS

/******************

Name: sp_logMsg

Author: Dustin Marzolf

Created: 1/31/2016

Purpose: To ease logging messages from various processes.

Updated: 4/26/2016 - Dustin Marzolf
	Added ability to e-mail messages on severity 4 items as they occurred.
	Added logic to check for duplicate messages and not log them if they occurr within
		a short timeframe.

Inputs:
	@MessageSeverity INT - The severity of the message, 0-4 are approved values (see notes)
	@MessageType VARCHAR(50) - The message type (see notes for pre-approved types)
	@MessageShort VARCHAR(200) - The short description of the message.
	@Messagelong VARCHAR(MAX) - The long description of the message.
	@GeneratedBy VARCHAR(100) - The name of the originating process.
	
Output:
	None

*******************/

/**************
Notes

@MessageSeverity INT

The message severity is designed to indiate how severe the message is.  The following is the approved values.
Supported values are IntMin to IntMax, recommended values are listed below.

0 - Informational: The system is talking to itself, use for recording that a process ran at a certain time and no issues were found, etc.

1 - Low: an issue was discovered, but it's potential impact to the security, integrity and functionality of the database
	is limited.  Examples include notifications about indexes not being defragmented, etc.

2 - Medium: medium severity items.

3 - High: highly critical items.

4 - Critical: Extemely critical issues.  Examples include full disks, and other issues that would immediately affect the security, integrity and functionality 
	of the database.  Critical Issues will be logged but an e-mail will also attempt to be sent regarding the issue.  
	
If provided value is NULL, will default to 0 (Informational)
If provided value is negative, will use the absolute value (unsigned)
	
============================================================

@MessgeType VARCHAR(50)

An indication about the type of message.  Examples are listed below.  When recording a message, try and re-use types if appropriate.

--Find all types used before:
SELECT DISTINCT MessageType FROM Info_Message ORDER BY MessageType

Types:
- LoginSecurity
- PhysicalDisk
- LinkedServer

If value is NULL or blank, will be set to <Unknown>

============================================================

@GeneratedBy VARCHAR(100)

If value is NULL or blank, will be set to the SYSTEM_USER (owner of current thread) variable.

***************/

--Fix data
IF @MessageSeverity IS NULL
BEGIN
	SET @MessageSeverity = 0
END
SET @MessageSeverity = ABS(@MessageSeverity)

IF ISNULL(@MessageType, '') = ''
BEGIN
	SET @MessageType = '<Unknown>'
END

IF ISNULL(@GeneratedBy, '') = ''
BEGIN
	SET @GeneratedBy = '<' + ISNULL(CAST(SYSTEM_USER AS VARCHAR(100)), 'Unknown') + '>'
END

/** Test to see if this is a duplicate or not.
	Try to avoid duplicating messages in the log if they are the same.  
	5 Minute expiration....
	**/
DECLARE @IsDuplicate BIT
DECLARE @LastMessage DATETIME
SET @IsDuplicate = 0

SET @LastMessage = (	SELECT TOP 1 I.DateMessage
						FROM Info_Message I
						WHERE I.DateMessage >= DATEADD(HOUR, -1, GETDATE())
							AND I.MessageSeverity = @MessageSeverity
							AND I.MessageType = @MessageType
							AND I.GeneratedBy = @GeneratedBy
							AND I.MessageShort = @MessageShort
							AND SUBSTRING(ISNULL(I.MessageLong, '  '), 0, 500) = SUBSTRING(ISNULL(@MessageLong, '  '), 0, 500)
						ORDER BY I.DateMessage DESC
						)
						
IF DATEDIFF(MINUTE, ISNULL(@LastMessage, '1/1/2010'), GETDATE()) <= 5
BEGIN
	SET @IsDuplicate = 1
END

IF @IsDuplicate = 0
BEGIN

	--Begin inserting data.
	INSERT INTO Info_Message (MessageSeverity, MessageType, MessageShort, MessageLong, GeneratedBy)
	VALUES (@MessageSeverity, @MessageType, @MessageShort, @MessageLong, @GeneratedBy)
	
END

/** If the message severity if 4 then send a message.
	**/
IF @MessageSeverity = 4 AND @IsDuplicate = 0
BEGIN

	DECLARE @ProfileName SYSNAME 
	DECLARE @CRCL CHAR(2)
	DECLARE @MessageSubject VARCHAR(MAX) 
	DECLARE @MessageBody VARCHAR(MAX) 
	
	SET @ProfileName = (	SELECT TOP 1 P.name 
							FROM msdb.dbo.sysmail_profile P 
							ORDER BY CASE	WHEN P.name LIKE '%DBA%' THEN 1 
											ELSE 2 
											END
										, P.name
							)
							
	SET @CRCL = CHAR(13) + CHAR(10)						
	SET @MessageSubject = 'INFO MESSAGE: ' + @@SERVERNAME + ' Severity 4 Message - ' + @MessageType
	
	SET @MessageBody = 'Server: ' + @@SERVERNAME
						+ @CRCL + 'Generated: ' + DBA.dbo.fn_FrmtDate(GETDATE(), 0) + ' ' + DBA.dbo.fn_FrmtTime(GETDATE(), 0)
						+ @CRCL + 'User: ' + @GeneratedBy
						+ @CRCL + 'Severity: ' + CAST(@MessageSeverity AS VARCHAR(10))
						+ @CRCL + 'Message Type: ' + @MessageType
						+ @CRCL + 'Message Short: ' + ISNULL(@MessageShort, '')
						+ @CRCL
						+ @CRCL + 'Message Details Begin'
						+ @CRCL + '====================='
						+ @CRCL
						+ @CRCL + ISNULL(@MessageLong, '')
	
	IF @ProfileName IS NOT NULL
	BEGIN
	
		EXEC msdb.dbo.sp_send_dbmail
			@profile_name = @ProfileName
			, @recipients = 'dustin.marzolf@setbasedmanagement.com
			, @subject = @MessageSubject
			, @body = @MessageBody;
	
	END

END


GO


