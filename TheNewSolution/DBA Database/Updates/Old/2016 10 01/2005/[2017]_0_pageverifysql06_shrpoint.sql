IF(@@SERVERNAME='DMDBAPRDSQL06\SHRPOINT')
BEGIN

USE [master]

ALTER DATABASE [NW2010ProdDB] SET PAGE_VERIFY CHECKSUM  WITH NO_WAIT;
ALTER DATABASE [wss_content_PRD_Intranet] SET PAGE_VERIFY CHECKSUM  WITH NO_WAIT;

END