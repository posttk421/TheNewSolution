IF(@@SERVERNAME='DMDBAUATSQL02')
BEGIN

USE [DBAMonitor]

/** Create new tables **/

CREATE TABLE [dbo].[Data_SQLTrc](
	[ServerName] [sysname] NULL,
	[TextData] [varchar](500) NULL,
	[HostName] [varchar](155) NULL,
	[ApplicationName] [varchar](255) NULL,
	[DatabaseName] [varchar](155) NULL,
	[LoginName] [varchar](155) NULL,
	[SPID] [int] NULL,
	[DateStart] [datetime] NULL,
	[EventSequence] [int] NULL,
	[ObjectID] [int] NULL,
	[ObjectID2] [bigint] NULL,
	[ObjectName] [nvarchar](500) NULL,
	[ObjectType] [int] NULL,
	[FileID] [uniqueidentifier] NULL,
	[EventCategory_Desc] [varchar](100) NULL,
	[GatheringNotes] [varchar](max) NULL
) ON [PRIMARY]


/****** Object:  Index [IX_Data_SQLTrace_DateStart_EventSequence]    Script Date: 02/08/2017 12:00:00 AM ******/
CREATE CLUSTERED INDEX [IX_Data_SQLTrace_DateStart_EventSequence] ON [dbo].[Data_SQLTrc]
(
	[DateStart] ASC,
	[EventSequence] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]


CREATE TABLE [dbo].[Data_SQLUserFrequency](
	[DateActivity] [date] NULL,
	[ServerName] [sysname] NOT NULL,
	[UserName] [varchar](500) NULL,
	[UserType] [char](2) NULL,
	[UserIsListed] [bit] NULL,
	[HostAddress] [varchar](500) NULL,
	[Status] [varchar](20) NULL,
	[Time_Earliest] [time](7) NULL,
	[Time_Latest] [time](7) NULL,
	[CountForDay] [int] NULL
) ON [PRIMARY]

/****** Object:  Index [IX_Data_SQLUserFrequency_DateActivity_UserName]    Script Date: 02/08/2017 12:00:00 AM ******/
CREATE CLUSTERED INDEX [IX_Data_SQLUserFrequency_DateActivity_UserName] ON [dbo].[Data_SQLUserFrequency]
(
	[DateActivity] ASC,
	[UserName] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]

/** New entries in TableList **/
INSERT INTO DBAMonitor.dbo.Mon_TableList
(SourceTableName, DestinationTableName, IsAccumulate, AccumulateDateFieldName)
VALUES 
('DBA.dbo.Data_SQLTrace', 'DBAMonitor.dbo.Data_SQLTrace', 1, 'DateStart')

INSERT INTO DBAMonitor.dbo.Mon_TableList
(SourceTableName, DestinationTableName, IsAccumulate, AccumulateDateFieldName)
VALUES 
('DBA.dbo.Data_SQLUserFrequency', 'DBAMonitor.dbo.Data_SQLUserFrequency', 1, 'DateActivity')

/** Remove extraneous objects **/
IF OBJECT_ID('DBAMonitor.dbo.uspDBDefrag') IS NOT NULL
BEGIN
	DROP PROCEDURE uspDBDefrag
END

IF OBJECT_ID('DBAMonitor.dbo.uspfixusers') IS NOT NULL
BEGIN
	DROP PROCEDURE uspfixusers
END

IF OBJECT_ID('DBAMonitor.dbo.sp_GetOrphUsrs') IS NOT NULL
BEGIN
	DROP PROCEDURE sp_GetOrphUsrs
END

IF OBJECT_ID('DBAMonitor.dbo.PowershellModule') IS NOT NULL
BEGIN
	DROP TABLE PowershellModule
END

/** Add new Servers to list **/
INSERT INTO Mon_ServerList
(ServerName, InstanceName, ConnectionName, ServerType, ServerPurpose, DateAdded, IsActive)
VALUES
('DMDBAPRDSQL04', NULL, 'DMDBAPRDSQL04', 'PROD', 'Fleet Management', GETDATE(), 1)

INSERT INTO Mon_ServerList
(ServerName, InstanceName, ConnectionName, ServerType, ServerPurpose, DateAdded, IsActive)
VALUES
('SAPNETDAP01', NULL, 'SAPNETDAP01', 'DEV', 'SAP BRC Integration', GETDATE(), 1)


END --End if Server is DMDBAUATSQL02