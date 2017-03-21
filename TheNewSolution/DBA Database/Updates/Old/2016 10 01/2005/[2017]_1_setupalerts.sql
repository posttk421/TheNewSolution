/**********

This script is designed to setup Alerts for error conditions.



USE [msdb]
GO

/************
Phase 1: Clear out the old stuff
************/

/** Remove old operator**/

/** Remove old Alerts **/
IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysalerts WHERE name = 'FatalError'), 0) = 1
BEGIN
	EXEC msdb.dbo.sp_delete_alert @name = 'FatalError'
END

IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysalerts WHERE name = 'FatalErrorCurrentProcess'), 0) = 1
BEGIN
	EXEC msdb.dbo.sp_delete_alert @name = 'FatalErrorCurrentProcess'
END

IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysalerts WHERE name = 'FatalErrorDatabaseIntegritySuspect'), 0) = 1
BEGIN
	EXEC msdb.dbo.sp_delete_alert @name = 'FatalErrorDatabaseIntegritySuspect'
END

IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysalerts WHERE name = 'FatalErrorDatabaseProcess'), 0) = 1
BEGIN
	EXEC msdb.dbo.sp_delete_alert @name = 'FatalErrorDatabaseProcess'
END

IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysalerts WHERE name = 'FatalErrorHardwareError'), 0) = 1
BEGIN
	EXEC msdb.dbo.sp_delete_alert @name = 'FatalErrorHardwareError'
END

IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysalerts WHERE name = 'FatalErrorResources'), 0) = 1
BEGIN
	EXEC msdb.dbo.sp_delete_alert @name = 'FatalErrorResources'
END

IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysalerts WHERE name = 'FatalErrorTableIntegritySuspect'), 0) = 1
BEGIN
	EXEC msdb.dbo.sp_delete_alert @name = 'FatalErrorTableIntegritySuspect'
END

IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysalerts WHERE name = 'InsufficientResources'), 0) = 1
BEGIN
	EXEC msdb.dbo.sp_delete_alert @name = 'InsufficientResources'

END

IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysalerts WHERE name = 'Login Failed'), 0) = 1
BEGIN
	EXEC msdb.dbo.sp_delete_alert @name = 'Login Failed'

END

/********** 
Phase 2: Create the New Stuff

***********/

/** Add new Operator **/

IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysoperators WHERE name = 'DBA Operator'), 0) = 0
BEGIN

	/****** Object:  Operator [DBA Operator]    Script Date: 02/08/2017 1:43:49 PM ******/
	EXEC msdb.dbo.sp_add_operator @name=N'DBA Operator', 
		@enabled=1, 
		@weekday_pager_start_time=90000, 
		@weekday_pager_end_time=180000, 
		@saturday_pager_start_time=90000, 
		@saturday_pager_end_time=180000, 
		@sunday_pager_start_time=90000, 
		@sunday_pager_end_time=180000, 
		@pager_days=0, 
		@email_address=N'dustin.marzolf@setbasedmanagement.com'

END

DECLARE @ProfileName VARCHAR(200)
SET @ProfileName = (SELECT TOP 1 name FROM msdb.dbo.sysmail_profile)

EXEC master.dbo.sp_MSsetalertinfo @failsafeoperator=N'DBA Operator'
EXEC master.dbo.sp_MSsetalertinfo @notificationmethod=1
EXEC master.dbo.xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent', N'DatabaseMailProfile', N'REG_SZ', @ProfileName



IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysoperators WHERE name = 'DL-SQL DBA services'), 0) = 1
BEGIN
	EXEC msdb.dbo.sp_delete_operator @name = 'DL-SQL DBA services', @reassign_to_operator=NULL
END



/** Add New Alert Categories **/
IF ISNULL((SELECT COUNT(category_id) FROM msdb.dbo.syscategories WHERE name='[Alert By Error Number]'), 0) = 0
BEGIN

	EXEC msdb.dbo.sp_add_category
		@class=N'ALERT',
		@type=N'NONE',
		@name=N'[Alert By Error Number]';

END

IF ISNULL((SELECT COUNT(category_id) FROM msdb.dbo.syscategories WHERE name='[Alert By Severity]'), 0) = 0
BEGIN

	EXEC msdb.dbo.sp_add_category
		@class=N'ALERT',
		@type=N'NONE',
		@name=N'[Alert By Severity]';

END

/** Add New Alerts **/

--Error 823

IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysalerts WHERE name='Error Number 823'), 0) = 1
BEGIN
	EXEC msdb.dbo.sp_delete_alert @name=N'Error Number 823'
END

IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysalerts WHERE name='Error Number 823'), 0) = 0
BEGIN

	/****** Object:  Alert [Error Number 823]    Script Date: 02/08/2017 1:45:32 PM ******/
	EXEC msdb.dbo.sp_add_alert @name=N'Error Number 823', 
		@message_id=823, 
		@severity=0, 
		@enabled=1, 
		@delay_between_responses=60, 
		@include_event_description_in=5, 
		@notification_message=N'Error Number 823 has occurred.  Disk error encountered by OS sub-system while working with Database Files.', 
		@category_name=N'[Alert By Error Number]', 
		@job_id=N'00000000-0000-0000-0000-000000000000'

	EXEC msdb.dbo.sp_add_notification
        @alert_name = N'Error Number 823',
        @operator_name = N'DBA Operator',
        @notification_method = 1 ;
	
END

--Error 824

IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysalerts WHERE name='Error Number 824'), 0) = 1
BEGIN
	EXEC msdb.dbo.sp_delete_alert @name=N'Error Number 824'
END

IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysalerts WHERE name='Error Number 824'), 0) = 0
BEGIN

	/****** Object:  Alert [Error Number 824]    Script Date: 02/08/2017 2:13:02 PM ******/
	EXEC msdb.dbo.sp_add_alert @name=N'Error Number 824', 
		@message_id=824, 
		@severity=0, 
		@enabled=1, 
		@delay_between_responses=60, 
		@include_event_description_in=5, 
		@notification_message=N'Error Number 824 has occurred.  Specific page in a data file was detected to be bad.', 
		@category_name=N'[Alert By Error Number]', 
		@job_id=N'00000000-0000-0000-0000-000000000000'

	EXEC msdb.dbo.sp_add_notification
        @alert_name = N'Error Number 824',
        @operator_name = N'DBA Operator',
        @notification_method = 1 ;

END

--Error 825

IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysalerts WHERE name='Error Number 825'), 0) = 1
BEGIN
	EXEC msdb.dbo.sp_delete_alert @name=N'Error Number 825'
END

IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysalerts WHERE name='Error Number 825'), 0) = 0
BEGIN

	/****** Object:  Alert [Error Number 825]    Script Date: 02/08/2017 2:13:39 PM ******/
	EXEC msdb.dbo.sp_add_alert @name=N'Error Number 825', 
		@message_id=825, 
		@severity=0, 
		@enabled=1, 
		@delay_between_responses=60, 
		@include_event_description_in=5, 
		@notification_message=N'Error Number 825 has occurred.  Read-Retry errors, indicative of page faults.', 
		@category_name=N'[Alert By Error Number]', 
		@job_id=N'00000000-0000-0000-0000-000000000000'

	EXEC msdb.dbo.sp_add_notification
        @alert_name = N'Error Number 825',
        @operator_name = N'DBA Operator',
        @notification_method = 1 ;

END

--Severity 16

IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysalerts WHERE name='Severity 016'), 0) = 1
BEGIN
	EXEC msdb.dbo.sp_delete_alert @name=N'Severity 016'
END

IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysalerts WHERE name='Severity 016'), 0) = 0
BEGIN

	/****** Object:  Alert [Severity 016]    Script Date: 02/08/2017 2:14:58 PM ******/
	EXEC msdb.dbo.sp_add_alert @name=N'Severity 016', 
		@message_id=0, 
		@severity=16, 
		@enabled=1, 
		@delay_between_responses=60, 
		@include_event_description_in=5, 
		@notification_message=N'Severity 16 Error has occurred.  This is usually caused by user problems, i.e. invalid queries', 
		@category_name=N'[Alert By Severity]', 
		@job_id=N'00000000-0000-0000-0000-000000000000'

	EXEC msdb.dbo.sp_add_notification
        @alert_name = N'Severity 016',
        @operator_name = N'DBA Operator',
        @notification_method = 1 ;

END

--Severity 17

IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysalerts WHERE name='Severity 017'), 0) = 1
BEGIN
	EXEC msdb.dbo.sp_delete_alert @name=N'Severity 017'
END

IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysalerts WHERE name='Severity 017'), 0) = 0
BEGIN

	/****** Object:  Alert [Severity 017]    Script Date: 02/08/2017 2:15:59 PM ******/
	EXEC msdb.dbo.sp_add_alert @name=N'Severity 017', 
		@message_id=0, 
		@severity=17, 
		@enabled=1, 
		@delay_between_responses=60, 
		@include_event_description_in=5, 
		@notification_message=N'Severity 17 Error has occurred.  Server is out of a configurable resource, such as database locks.', 
		@category_name=N'[Alert By Severity]', 
		@job_id=N'00000000-0000-0000-0000-000000000000'

	EXEC msdb.dbo.sp_add_notification
        @alert_name = N'Severity 017',
        @operator_name = N'DBA Operator',
        @notification_method = 1 ;

END

--Severity 18

IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysalerts WHERE name='Severity 018'), 0) = 1
BEGIN
	EXEC msdb.dbo.sp_delete_alert @name=N'Severity 018'
END

IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysalerts WHERE name='Severity 018'), 0) = 0
BEGIN

	/****** Object:  Alert [Severity 018]    Script Date: 02/08/2017 2:35:47 PM ******/
	EXEC msdb.dbo.sp_add_alert @name=N'Severity 018', 
		@message_id=0, 
		@severity=18, 
		@enabled=1, 
		@delay_between_responses=60, 
		@include_event_description_in=5, 
		@notification_message=N'Severity 18 Error has occurred.  Usually indicates nonfatal internal software problems.', 
		@category_name=N'[Alert By Severity]', 
		@job_id=N'00000000-0000-0000-0000-000000000000'

	EXEC msdb.dbo.sp_add_notification
        @alert_name = N'Severity 018',
        @operator_name = N'DBA Operator',
        @notification_method = 1 ;

END

--Severity 19

IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysalerts WHERE name='Severity 019'), 0) = 1
BEGIN
	EXEC msdb.dbo.sp_delete_alert @name=N'Severity 019'
END

IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysalerts WHERE name='Severity 019'), 0) = 0
BEGIN

	/****** Object:  Alert [Severity 019]    Script Date: 02/08/2017 2:36:12 PM ******/
	EXEC msdb.dbo.sp_add_alert @name=N'Severity 019', 
		@message_id=0, 
		@severity=19, 
		@enabled=1, 
		@delay_between_responses=60, 
		@include_event_description_in=5, 
		@notification_message=N'Severity 19 Error has occurred.  Usually indicates that a non-configuratble resource limit has been exceeded.', 
		@category_name=N'[Alert By Severity]', 
		@job_id=N'00000000-0000-0000-0000-000000000000'

	EXEC msdb.dbo.sp_add_notification
        @alert_name = N'Severity 019',
        @operator_name = N'DBA Operator',
        @notification_method = 1 ;

END

--Severity 20

IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysalerts WHERE name='Severity 020'), 0) = 1
BEGIN
	EXEC msdb.dbo.sp_delete_alert @name=N'Severity 020'
END

IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysalerts WHERE name='Severity 020'), 0) = 0
BEGIN

	/****** Object:  Alert [Severity 020]    Script Date: 02/08/2017 2:36:40 PM ******/
	EXEC msdb.dbo.sp_add_alert @name=N'Severity 020', 
		@message_id=0, 
		@severity=20, 
		@enabled=1, 
		@delay_between_responses=60, 
		@include_event_description_in=5, 
		@notification_message=N'Severity 20 Error has occurred.  Issue with statement provided by the current process.', 
		@category_name=N'[Alert By Severity]', 
		@job_id=N'00000000-0000-0000-0000-000000000000'

	EXEC msdb.dbo.sp_add_notification
        @alert_name = N'Severity 020',
        @operator_name = N'DBA Operator',
        @notification_method = 1 ;

END

--Severity 21

IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysalerts WHERE name='Severity 021'), 0) = 1
BEGIN
	EXEC msdb.dbo.sp_delete_alert @name=N'Severity 021'
END

IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysalerts WHERE name='Severity 021'), 0) = 0
BEGIN

	/****** Object:  Alert [Severity 021]    Script Date: 02/08/2017 2:37:19 PM ******/
	EXEC msdb.dbo.sp_add_alert @name=N'Severity 021', 
		@message_id=0, 
		@severity=21, 
		@enabled=1, 
		@delay_between_responses=60, 
		@include_event_description_in=5, 
		@notification_message=N'Severity 21 Error has occurred.  An issue is present that affects all processes in a database.', 
		@category_name=N'[Alert By Severity]', 
		@job_id=N'00000000-0000-0000-0000-000000000000'

	EXEC msdb.dbo.sp_add_notification
        @alert_name = N'Severity 021',
        @operator_name = N'DBA Operator',
        @notification_method = 1 ;

END

--Severity 22

IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysalerts WHERE name='Severity 022'), 0) = 1
BEGIN
	EXEC msdb.dbo.sp_delete_alert @name=N'Severity 022'
END

IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysalerts WHERE name='Severity 022'), 0) = 0
BEGIN

	/****** Object:  Alert [Severity 022]    Script Date: 02/08/2017 2:37:42 PM ******/
	EXEC msdb.dbo.sp_add_alert @name=N'Severity 022', 
		@message_id=0, 
		@severity=22, 
		@enabled=1, 
		@delay_between_responses=60, 
		@include_event_description_in=5, 
		@notification_message=N'Severity 22 Error has occurred.  A table or index has been damaged.  Restart the server and perform DBCC CHECKDB.', 
		@category_name=N'[Alert By Severity]', 
		@job_id=N'00000000-0000-0000-0000-000000000000'

	EXEC msdb.dbo.sp_add_notification
        @alert_name = N'Severity 022',
        @operator_name = N'DBA Operator',
        @notification_method = 1 ;

END

--Severity 23

IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysalerts WHERE name='Severity 023'), 0) = 1
BEGIN
	EXEC msdb.dbo.sp_delete_alert @name=N'Severity 023'
END

IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysalerts WHERE name='Severity 023'), 0) = 0
BEGIN

	/****** Object:  Alert [Severity 023]    Script Date: 02/08/2017 2:38:05 PM ******/
	EXEC msdb.dbo.sp_add_alert @name=N'Severity 023', 
		@message_id=0, 
		@severity=23, 
		@enabled=1, 
		@delay_between_responses=60, 
		@include_event_description_in=5, 
		@notification_message=N'Severity 23 Error has occurred.  Indicates a suspect database.  Use DBCC CHECKDB', 
		@category_name=N'[Alert By Severity]', 
		@job_id=N'00000000-0000-0000-0000-000000000000'

	EXEC msdb.dbo.sp_add_notification
        @alert_name = N'Severity 023',
        @operator_name = N'DBA Operator',
        @notification_method = 1 ;

END

--Severity 24

IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysalerts WHERE name='Severity 024'), 0) = 1
BEGIN
	EXEC msdb.dbo.sp_delete_alert @name=N'Severity 024'
END

IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysalerts WHERE name='Severity 024'), 0) = 0
BEGIN

	/****** Object:  Alert [Severity 024]    Script Date: 02/08/2017 2:38:36 PM ******/
	EXEC msdb.dbo.sp_add_alert @name=N'Severity 024', 
		@message_id=0, 
		@severity=24, 
		@enabled=1, 
		@delay_between_responses=60, 
		@include_event_description_in=5, 
		@notification_message=N'Severity 24 Error has occurred.  A hardware problem.', 
		@category_name=N'[Alert By Severity]', 
		@job_id=N'00000000-0000-0000-0000-000000000000'

	EXEC msdb.dbo.sp_add_notification
        @alert_name = N'Severity 024',
        @operator_name = N'DBA Operator',
        @notification_method = 1 ;

END

--Severity 25

IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysalerts WHERE name='Severity 025'), 0) = 1
BEGIN
	EXEC msdb.dbo.sp_delete_alert @name=N'Severity 025'
END	

IF ISNULL((SELECT COUNT(id) FROM msdb.dbo.sysalerts WHERE name='Severity 025'), 0) = 0
BEGIN

	/****** Object:  Alert [Severity 025]    Script Date: 02/08/2017 2:38:59 PM ******/
	EXEC msdb.dbo.sp_add_alert @name=N'Severity 025', 
		@message_id=0, 
		@severity=25, 
		@enabled=1, 
		@delay_between_responses=60, 
		@include_event_description_in=5, 
		@notification_message=N'Severity 25 Error has occurred.  System error.  You win a prize; these should not happen... ever.', 
		@category_name=N'[Alert By Severity]', 
		@job_id=N'00000000-0000-0000-0000-000000000000'

	EXEC msdb.dbo.sp_add_notification
        @alert_name = N'Severity 025',
        @operator_name = N'DBA Operator',
        @notification_method = 1 ;

END