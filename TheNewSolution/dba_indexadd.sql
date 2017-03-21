USE DBA

IF NOT EXISTS (SELECT I.index_id FROM sys.indexes I WHERE I.name = 'IDX_Data_SQLTrace_FileID_EventSequence')
	AND OBJECT_ID('Data_SQLTrace') IS NOT NULL
BEGIN

	CREATE NONCLUSTERED INDEX IDX_Data_SQLTrace_FileID_EventSequence ON Data_SQLTrace (FileID, EventSequence)

END

