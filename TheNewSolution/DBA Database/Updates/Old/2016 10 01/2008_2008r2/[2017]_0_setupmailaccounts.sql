/** Fix Mail Accounts

	This script will accomplish two objectives.

	1 - Fix existing mail accounts so that the name in the from address
		field will appear as the instance name.

	2 - If DB Mail is not configured, enable it and then create an account.

**/

/** 1 - Update the existing account to show the instance name when sending mail **/

DECLARE @AID INT
DECLARE @SrvrName NVARCHAR(100)

SET @SrvrName = UPPER(@@SERVERNAME)

DECLARE curAccounts CURSOR LOCAL STATIC FORWARD_ONLY

FOR SELECT account_id
	FROM msdb.dbo.sysmail_account
	WHERE display_name <> @SrvrName

OPEN curAccounts

FETCH NEXT FROM curAccounts
INTO @AID

WHILE @@FETCH_STATUS = 0
BEGIN

	EXEC msdb.dbo.sysmail_update_account_sp @account_id = @AID, @display_name = @SrvrName

	FETCH NEXT FROM curAccounts
	INTO @AID

END

CLOSE curAccounts
DEALLOCATE curAccounts

/** 2 - If there are no mail accounts, then create the one below.  **/
IF ISNULL((SELECT COUNT(profile_id) FROM msdb.dbo.sysmail_profile), 0) <> 0
BEGIN
	--If there is already an account, then do not create another one.
	SET NOEXEC ON	
END

use master
go
sp_configure 'show advanced options',1
go
reconfigure with override
go
sp_configure 'Database Mail XPs',1
--go
--sp_configure 'SQL Mail XPs',0
go
reconfigure
go

DECLARE @SrvrName VARCHAR(200)
SET @SrvrName = UPPER(@@SERVERNAME)

--#################################################################################################
-- BEGIN Mail Settings SQL Administrator Profile
--#################################################################################################
IF NOT EXISTS(SELECT * FROM msdb.dbo.sysmail_profile WHERE  name = 'SQL Administrator Profile') 
  BEGIN
    --CREATE Profile [SQL Administrator Profile]
    EXECUTE msdb.dbo.sysmail_add_profile_sp
      @profile_name = 'SQL Administrator Profile',
      @description  = 'Profile used for administrative mail.';
  END --IF EXISTS profile
  
  IF NOT EXISTS(SELECT * FROM msdb.dbo.sysmail_account WHERE name = 'DBA Mail')
  BEGIN
    --CREATE Account [DBA Mail]
    EXECUTE msdb.dbo.sysmail_add_account_sp
    @account_name            = 'DBA Mail',
    @email_address           = 'dustin.marzolf@setbasedmanagement.com,
    @display_name            = @SrvrName,
    @replyto_address         = 'dustin.marzolf@setbasedmanagement.com,
    @description             = 'Mail account for administrative e-mail.',
    @mailserver_name         = 'Smtp.acfnt.com',
    @mailserver_type         = 'SMTP',
    @port                    = '25',
    @username                =  NULL ,
    @password                =  NULL , 
    @use_default_credentials =  0 ,
    @enable_ssl              =  0 ;
  END --IF EXISTS  account
  
IF NOT EXISTS(SELECT *
              FROM msdb.dbo.sysmail_profileaccount pa
                INNER JOIN msdb.dbo.sysmail_profile p ON pa.profile_id = p.profile_id
                INNER JOIN msdb.dbo.sysmail_account a ON pa.account_id = a.account_id  
              WHERE p.name = 'SQL Administrator Profile'
                AND a.name = 'DBA Mail') 
  BEGIN
    -- Associate Account [DBA Mail] to Profile [SQL Administrator Profile]
    EXECUTE msdb.dbo.sysmail_add_profileaccount_sp
      @profile_name = 'SQL Administrator Profile',
      @account_name = 'DBA Mail',
      @sequence_number = 1 ;
  END --IF EXISTS associate accounts to profiles
--#################################################################################################
-- Drop Settings For SQL Administrator Profile
--#################################################################################################
/*
IF EXISTS(SELECT *
            FROM msdb.dbo.sysmail_profileaccount pa
              INNER JOIN msdb.dbo.sysmail_profile p ON pa.profile_id = p.profile_id
              INNER JOIN msdb.dbo.sysmail_account a ON pa.account_id = a.account_id  
            WHERE p.name = 'SQL Administrator Profile'
              AND a.name = 'DBA Mail')
  BEGIN
    EXECUTE msdb.dbo.sysmail_delete_profileaccount_sp @profile_name = 'SQL Administrator Profile',@account_name = 'DBA Mail'
  END 
IF EXISTS(SELECT * FROM msdb.dbo.sysmail_account WHERE  name = 'DBA Mail')
  BEGIN
    EXECUTE msdb.dbo.sysmail_delete_account_sp @account_name = 'DBA Mail'
  END
IF EXISTS(SELECT * FROM msdb.dbo.sysmail_profile WHERE  name = 'SQL Administrator Profile') 
  BEGIN
    EXECUTE msdb.dbo.sysmail_delete_profile_sp @profile_name = 'SQL Administrator Profile'
  END
*/
  
--Put the execution status back.
SET NOEXEC OFF