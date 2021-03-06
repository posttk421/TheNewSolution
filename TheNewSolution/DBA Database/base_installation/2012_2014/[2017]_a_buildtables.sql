USE [DBA]
GO
/****** Object:  Table [dbo].[Audit_LoginDatabase]    Script Date: 8/6/2016 3:37:42 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE [dbo].[Audit_LoginDatabase](
	[LoginName] [sysname] NOT NULL,
	[DatabaseName] [sysname] NOT NULL,
	[ServerName] [sysname] NOT NULL,
	[DateGathered] [datetime] NULL,
	[DateCreated] [datetime] NULL,
	[DateModified] [datetime] NULL,
	[TypeDesc] [varchar](100) NULL,
	[IsDBOwner] [bit] NULL,
	[IsAccessAdmin] [bit] NULL,
	[IsSecurityAdmin] [bit] NULL,
	[IsDDLAdmin] [bit] NULL,
	[IsBackupOperator] [bit] NULL,
	[IsDataReader] [bit] NULL,
	[IsDataWriter] [bit] NULL,
	[IsDenyDataReader] [bit] NULL,
	[IsDenyDataWriter] [bit] NULL
) ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
/****** Object:  Table [dbo].[Audit_LoginServer]    Script Date: 8/6/2016 3:37:42 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE [dbo].[Audit_LoginServer](
	[LoginName] [sysname] NOT NULL,
	[ServerName] [sysname] NOT NULL DEFAULT (@@SERVERNAME),
	[DateGathered] [datetime] NULL,
	[DateCreated] [datetime] NULL,
	[DateModified] [datetime] NULL,
	[DefaultDatabase] [sysname] NULL,
	[TypeDesc] [varchar](100) NULL,
	[IsDisabled] [bit] NULL,
	[IsSysAdmin] [bit] NULL,
	[IsSecurityAdmin] [bit] NULL,
	[IsServerAdmin] [bit] NULL,
	[IsSetupAdmin] [bit] NULL,
	[IsProcessAdmin] [bit] NULL,
	[IsDBCreator] [bit] NULL,
	[IsBulkAdmin] [bit] NULL
) ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
/****** Object:  Table [dbo].[Data_AgtJobHist]    Script Date: 8/6/2016 3:37:42 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE [dbo].[Data_AgtJobHist](
	[ServerName] [sysname] NOT NULL,
	[Job_ID] [uniqueidentifier] NOT NULL,
	[DateGathered] [datetime] NULL,
	[StepID] [int] NOT NULL,
	[StepName] [varchar](500) NULL,
	[StepMessage] [varchar](max) NULL,
	[RunStatus] [int] NULL,
	[DateStarted] [datetime] NULL,
	[RunDuration_Second] [bigint] NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
/****** Object:  Table [dbo].[Data_AgtJoblist]   Script Date: 8/6/2016 3:37:42 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE [dbo].[Data_AgentJobList](
	[ServerName] [sysname] NOT NULL,
	[DateAdded] [datetime] NOT NULL,
	[ListedInServer] [bit] NULL,
	[JobName] [sysname] NOT NULL,
	[Job_ID] [uniqueidentifier] NOT NULL,
	[JobDescription] [varchar](1000) NULL,
	[JobIsEnabled] [bit] NULL,
	[OwnerName] [sysname] NULL,
	[DateCreated] [datetime] NULL,
	[DateModified] [datetime] NULL,
	[VersionNumber] [int] NULL,
	[StepCount_All] [int] NULL,
	[StepCount_SSIS] [int] NULL,
	[StepCount_CMDExec] [int] NULL,
	[StepCount_PShell] [int] NULL,
	[StepCount_TSQL] [int] NULL,
	[StepCount_Others] [int] NULL,
	[DateLastRun] [datetime] NULL,
	[LastRunOutcome] [int] NULL,
	[LastRunDuration_Second] [bigint] NULL,
	[NextRunTime] [datetime] NULL,
UNIQUE NONCLUSTERED 
(
	[Job_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
/****** Object:  Table [dbo].[Data_bckhist]    Script Date: 8/6/2016 3:37:42 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE [dbo].[Data_bckhist](
	[ServerName] [sysname] NOT NULL DEFAULT (@@SERVERNAME),
	[DateGathered] [datetime] NOT NULL,
	[DatabaseName] [varchar](200) NOT NULL,
	[BackupType] [char](1) NULL,
	[BackupType_Desc] [varchar](50) NULL,
	[MediaCount] [int] NULL,
	[BackupSize_Bytes] [numeric](18, 0) NULL,
	[BckupSizeGB] [decimal](10, 2) NULL,
	[DateStart] [datetime] NULL,
	[DateFinish] [datetime] NULL,
	[Duration_Minutes] [int] NULL,
	[CompressedSize_Bytes] [numeric](18, 0) NULL,
	[CompressedSizeGB] [decimal](10, 2) NULL,
	[IsDamaged] [bit] NULL,
	[CompressionRatio] [decimal](5, 2) NULL
) ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
/****** Object:  Table [dbo].[Data_bckMedFiles]    Script Date: 8/6/2016 3:37:42 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE [dbo].[Data_bckMedFiles](
	[ServerName] [sysname] NOT NULL DEFAULT (@@SERVERNAME),
	[DatabaseName] [sysname] NOT NULL,
	[MediaSetID] [int] NOT NULL,
	[FamilySeqNumber] [int] NOT NULL,
	[FilePathName] [varchar](1000) NOT NULL,
	[DateFileDeleted] [datetime] NULL
) ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
/****** Object:  Table [dbo].[Data_BackupSet]    Script Date: 8/6/2016 3:37:42 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE [dbo].[Data_BackupSet](
	[ServerName] [sysname] NOT NULL DEFAULT (@@SERVERNAME),
	[DateGathered] [datetime] NOT NULL DEFAULT (getdate()),
	[DatabaseName] [sysname] NOT NULL,
	[BackupSetUUID] [uniqueidentifier] NOT NULL,
	[MediaSetID] [int] NULL,
	[BackupType] [char](1) NULL,
	[BackupType_Desc] [varchar](10) NULL,
	[DateBackupStart] [datetime] NULL,
	[DateBackupEnd] [datetime] NULL,
	[BackupSize] [numeric](18, 0) NULL,
	[DatabaseRecoveryModel] [varchar](10) NULL,
	[DateBackupSetExpires] [datetime] NULL,
	[IsDailyBackup] [bit] NULL,
	[IsWeeklyBackup] [bit] NULL,
	[IsMonthlyBackup] [bit] NULL
) ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
/****** Object:  Table [dbo].[Data_Database]    Script Date: 8/6/2016 3:37:42 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE [dbo].[Data_Database](
	[ServerName] [sysname] NOT NULL DEFAULT (@@SERVERNAME),
	[DateGathered] [datetime] NULL,
	[DatabaseName] [sysname] NOT NULL,
	[IsSystemDatabase] [bit] NULL,
	[State_Desc] [varchar](100) NULL,
	[Collation] [varchar](100) NULL,
	[UserAccessLevel] [varchar](100) NULL,
	[RecoveryModel] [varchar](100) NULL,
	[CompatibilityLevel] [varchar](10) NULL,
	[DateCreated] [datetime] NULL,
	[DateLastFullBackup] [datetime] NULL,
	[DateLastTRNBackup] [datetime] NULL,
	[DateLastDIFFBackup] [datetime] NULL,
	[DateLastRestored] [datetime] NULL
) ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
/****** Object:  Table [dbo].[Data_dbFiles]   Script Date: 8/6/2016 3:37:42 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE [dbo].[Data_DatabaseFiles](
	[ServerName] [sysname] NOT NULL DEFAULT (@@SERVERNAME),
	[DatabaseName] [sysname] NOT NULL,
	[DateGathered] [datetime] NOT NULL DEFAULT (getdate()),
	[FileGUID] [uniqueidentifier] NULL,
	[FileType] [char](4) NULL,
	[PathToFile] [varchar](1000) NULL,
	[NameOfFile] [sysname] NULL,
	[FileGroupName] [sysname] NULL,
	[SpaceUsedOnDisk_MB] [decimal](10, 2) NULL,
	[SpaceUsedInFile_MB] [decimal](10, 2) NULL,
	[SpaceFreeInFile_MB] [decimal](10, 2) NULL,
	[AutoExpandStatus] [bit] NULL,
	[GrowthStatus] [int] NULL,
	[Growth] [int] NULL,
	[Growth_InPercent] [decimal](10, 2) NULL,
	[Growth_InMB] [decimal](10, 2) NULL,
	[Growth_Desc] [varchar](100) NULL,
	[MaxFileSize] [int] NULL,
	[MaxFileSize_Desc] [varchar](100) NULL
) ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
/****** Object:  Table [dbo].[Data_ObjBckupHist]   Script Date: 8/6/2016 3:37:42 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE [dbo].[Data_ObjectBackupHistory](
	[ServerName] [sysname] NOT NULL DEFAULT (@@SERVERNAME),
	[DateAdded] [datetime] NOT NULL,
	[ObjectType] [varchar](100) NOT NULL,
	[ObjectName] [varchar](200) NULL,
	[FilePath] [varchar](2000) NOT NULL,
	[DateRemoved] [datetime] NULL
) ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
/****** Object:  Table [dbo].[Data_SQLLog]    Script Date: 8/6/2016 3:37:42 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE [dbo].[Data_SQLLog](
	[ServerName] [sysname] NOT NULL DEFAULT (@@SERVERNAME),
	[LogDate] [datetime] NULL,
	[ProcessInfo] [varchar](10) NULL,
	[Text] [varchar](8000) NULL,
	[UserName] [varchar](500) NULL,
	[HostAddress] [varchar](500) NULL,
	[Status] [varchar](20) NULL
) ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
/****** Object:  Table [dbo].[Data_SQLTrc]    Script Date: 8/6/2016 3:37:42 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE [dbo].[Data_SQLTrc](
	[ServerName] [sysname] NOT NULL DEFAULT (@@SERVERNAME),
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
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
/****** Object:  Table [dbo].[Data_SQLUsrFrequncy]   Script Date: 8/6/2016 3:37:42 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE [dbo].[Data_SQLUserFrequency](
	[DateActivity] [date] NULL,
	[ServerName] [sysname] NOT NULL DEFAULT (@@SERVERNAME),
	[UserName] [varchar](500) NULL,
	[UserType] [char](2) NULL,
	[UserIsListed] [bit] NULL,
	[HostAddress] [varchar](500) NULL,
	[Status] [varchar](20) NULL,
	[Time_Earliest] [time](7) NULL,
	[Time_Latest] [time](7) NULL,
	[CountForDay] [int] NULL
) ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
/****** Object:  Table [dbo].[Data_SysDsk]    Script Date: 8/6/2016 3:37:42 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE [dbo].[Data_SysDsk](
	[ServerName] [varchar](100) NULL,
	[DateGathered] [datetime] NULL,
	[DriveLetter] [varchar](10) NULL,
	[VolumeName] [varchar](100) NULL,
	[Capacity_GB] [decimal](10, 3) NULL,
	[Used_GB] [decimal](10, 3) NULL,
	[Freespace_GB] [decimal](10, 3) NULL,
	[FreeSpace_Percent]  AS ((isnull([Freespace_GB],(0.0))/isnull([Capacity_GB],isnull([Freespace_GB],(0.0))))*(100)) PERSISTED
) ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
/****** Object:  Table [dbo].[LoginDb_Info]   Script Date: 8/6/2016 3:37:42 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE [dbo].[Info_LoginDatabase](
	[LoginName] [sysname] NOT NULL,
	[DatabaseName] [sysname] NOT NULL,
	[OriginalScript] [varchar](max) NULL,
	[OriginalScript_DateTime] [datetime] NULL,
	[LastScript_DateTime] [datetime] NULL,
	[LastScript] [varchar](max) NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
/****** Object:  Table [dbo].[LoginDbObj_Info]    Script Date: 8/6/2016 3:37:42 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE [dbo].[LoginDbObj_Info](
	[LoginName] [sysname] NOT NULL,
	[DatabaseName] [sysname] NOT NULL,
	[OriginalScript] [varchar](max) NULL,
	[OriginalScript_DateTime] [datetime] NULL,
	[LastScript_DateTime] [datetime] NULL,
	[LastScript] [varchar](max) NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
/****** Object:  Table [dbo].[LoginSrv_Info]    Script Date: 8/6/2016 3:37:42 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE [dbo].[LoginSrv_Info](
	[LoginName] [sysname] NOT NULL,
	[LoginType_Desc] [nvarchar](128) NOT NULL,
	[OriginalScript] [varchar](max) NULL,
	[OriginalScript_DateTime] [datetime] NULL,
	[LastScript_DateTime] [datetime] NULL,
	[LastScript] [varchar](max) NULL,
PRIMARY KEY CLUSTERED 
(
	[LoginName] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
/****** Object:  Table [dbo].[Msg_Info]    Script Date: 8/6/2016 3:37:42 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE [dbo].[Msg_Info](
	[DateMessage] [datetime] NOT NULL DEFAULT (getdate()),
	[ServerName] [varchar](100) NOT NULL DEFAULT (@@SERVERNAME),
	[MessageSeverity] [int] NOT NULL,
	[MessageType] [varchar](50) NULL,
	[MessageShort] [varchar](200) NULL,
	[MessageLong] [varchar](max) NULL,
	[GeneratedBy] [varchar](100) NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
/****** Object:  Table [dbo].[SrvHardware_Info]    Script Date: 8/6/2016 3:37:42 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE [dbo].[SrvHardware_Info](
	[Name] [varchar](100) NOT NULL,
	[OriginalValue] [varchar](200) NOT NULL,
	[OriginalValue_DateTime] [datetime] NULL,
	[LastValue] [varchar](200) NULL,
	[LastValue_DateTime] [datetime] NULL,
	[ServerName] [sysname] NULL,
PRIMARY KEY CLUSTERED 
(
	[Name] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
/****** Object:  Table [dbo].[SQlInst_Info]   Script Date: 8/6/2016 3:37:42 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE [dbo].[Info_SQLInstance](
	[IndexID] [int] IDENTITY(1,1) NOT NULL,
	[Name] [varchar](100) NOT NULL,
	[ServerName] [sysname] NOT NULL DEFAULT (@@SERVERNAME),
	[OriginalValue] [varchar](200) NULL,
	[OriginalValue_DateTime] [datetime] NULL,
	[LastValue] [varchar](200) NULL,
	[LastValue_DateTime] [datetime] NULL,
PRIMARY KEY CLUSTERED 
(
	[Name] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
/****** Object:  Table [dbo].[ChkDB_Mnt]    Script Date: 8/6/2016 3:37:42 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[ChkDB_Mnt](
	[ServerName] [sysname] NOT NULL,
	[DateGathered] [datetime] NOT NULL,
	[DatabaseName] [sysname] NOT NULL,
	[RowID] [int] NULL,
	[Error] [int] NULL,
	[Level] [int] NULL,
	[State] [int] NULL,
	[MessageText] [nvarchar](2048) NULL,
	[RepairLevel] [nvarchar](22) NULL,
	[Status] [int] NULL,
	[Dbid] [int] NULL,
	[ObjectID] [int] NULL,
	[IndexID] [int] NULL,
	[PartitionID] [bigint] NULL,
	[AllocUnitID] [bigint] NULL,
	[File] [smallint] NULL,
	[Page] [int] NULL,
	[Slot] [int] NULL,
	[RefFile] [int] NULL,
	[RefPage] [int] NULL,
	[RefSlot] [int] NULL,
	[Allocation] [smallint] NULL,
	[OutCome]  AS (case when [Error]=(8989) AND [MessageText] like '% 0 allocation errors and 0 consistency errors%' then (0) when [Error]<>(8989) then NULL else (1) end)
) ON [PRIMARY]

GO
/****** Object:  Table [dbo].[DbFile_Mnt]    Script Date: 8/6/2016 3:37:42 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE [dbo].[DbFile_Mnt](
	[DatabaseFileID] [uniqueidentifier] NOT NULL,
	[ServerName] [sysname] NOT NULL,
	[DatabaseName] [sysname] NOT NULL,
	[DateGathered] [datetime] NOT NULL,
	[FileGUID] [uniqueidentifier] NULL,
	[FileType] [char](4) NULL,
	[NameOfFile] [sysname] NULL,
	[SpaceUsedOnDisk_MB] [decimal](10, 2) NULL,
	[SpaceUsedInFile_MB] [decimal](10, 2) NULL,
	[SpaceFreeInFile_MB] [decimal](10, 2) NULL,
PRIMARY KEY CLUSTERED 
(
	[DatabaseFileID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
/****** Object:  Table [dbo].[Indx_Mnt]    Script Date: 8/6/2016 3:37:42 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE [dbo].[Indx_Mnt](
	[Mnt_IndexID] [int] IDENTITY(1,1) NOT NULL,
	[ServerName] [sysname] NULL,
	[DatabaseName] [varchar](250) NULL,
	[SchemaName] [varchar](250) NULL,
	[ObjectName] [varchar](250) NULL,
	[IndexName] [varchar](250) NULL,
	[FragmentationLevel] [float] NULL,
	[DateStart] [datetime] NULL,
	[DateEnd] [datetime] NULL,
	[SQLStatement] [varchar](max) NULL,
PRIMARY KEY CLUSTERED 
(
	[Mnt_IndexID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
/****** Object:  Table [dbo].[SQLTrcFile_Mnt]    Script Date: 8/6/2016 3:37:42 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE [dbo].[SQLTrcFile_Mnt](
	[FileID] [uniqueidentifier] NOT NULL DEFAULT (newsequentialid()),
	[FilePath] [varchar](500) NOT NULL,
	[Start_Time] [datetime] NULL,
	[DateLastRead] [datetime] NULL,
	[IsValid] [bit] NOT NULL DEFAULT ((1)),
PRIMARY KEY CLUSTERED 
(
	[FileID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
/****** Object:  Table [dbo].[Opt]    Script Date: 8/6/2016 3:37:42 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE [dbo].[Opt](
	[OptionLevel] [varchar](20) NOT NULL,
	[OptionName] [varchar](200) NOT NULL,
	[OptionValue] [varchar](200) NULL,
	[OptionDescription] [varchar](max) NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
/****** Object:  Table [dbo].[Opt_db]    Script Date: 8/6/2016 3:37:42 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE [dbo].[Opt_db](
	[DatabaseName] [varchar](200) NOT NULL,
	[BackupTypeMonday] [char](1) NOT NULL,
	[BackupTypeTuesday] [char](1) NOT NULL,
	[BackupTypeWednesday] [char](1) NOT NULL,
	[BackupTypeThursday] [char](1) NOT NULL,
	[BackupTypeFriday] [char](1) NOT NULL,
	[BackupTypeSaturday] [char](1) NOT NULL,
	[BackupTypeSunday] [char](1) NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[DatabaseName] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
/****** Object:  Table [dbo].[PwrshellMod]    Script Date: 8/6/2016 3:37:42 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE [dbo].[PwrshellMod](
	[ModuleName] [varchar](100) NOT NULL,
	[ModuleText] [varchar](max) NULL,
	[DateLastUpdated] [datetime] NULL,
PRIMARY KEY CLUSTERED 
(
	[ModuleName] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
ALTER TABLE [dbo].[SrvHardware_Info] ADD  DEFAULT (@@SERVERNAME) FOR [ServerName]
GO
ALTER TABLE [dbo].[DbFile_Mnt] ADD  DEFAULT (newsequentialid()) FOR [DatabaseFileID]
GO
ALTER TABLE [dbo].[DbFile_Mnt] ADD  DEFAULT (@@SERVERNAME) FOR [ServerName]
GO
ALTER TABLE [dbo].[DbFile_Mnt] ADD  DEFAULT (getdate()) FOR [DateGathered]
GO
