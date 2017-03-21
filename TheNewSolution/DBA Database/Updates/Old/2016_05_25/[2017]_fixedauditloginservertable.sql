
USE [DBA]

SELECT * INTO #AuditTemp FROM Audit_LoginServer

DROP TABLE Audit_LoginServer

CREATE TABLE [dbo].[Audit_LoginServer](
	[LoginName] [sysname] NOT NULL,
	[ServerName] [sysname] NOT NULL,
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
	[IsBulkAdmin] [bit] NULL,
) ON [PRIMARY]

SET ANSI_PADDING OFF

ALTER TABLE [dbo].[Audit_LoginServer] ADD  DEFAULT (@@SERVERNAME) FOR [ServerName]

INSERT INTO Audit_LoginServer SELECT * FROM #AuditTemp

DROP TABLE #AuditTemp


