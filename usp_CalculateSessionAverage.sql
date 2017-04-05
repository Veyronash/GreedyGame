USE [DBName]
GO

/****** Object:  StoredProcedure [dbo].[usp_CalculateSessionAverage]    Script Date: 4/4/2017 6:07:33 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/* ===================================================================================================================================================
Project Name: GreedyGame
Module Name: Session
Purpose:      
	This stored procedure calculates number of sessions (valid and total) of a game and the average session time(only valid)

Parameter Info
   None

Return Info
   ON Success: 0
   ON Error: 1

Called by SP/ Package: Sample.dtsx

Test Scripts
   EXEC [dbo].[usp_CalculateSessionAverage]

Execution Time
	1 - 9 seconds
      

Revision History:
Date                       Author            Description
=======================================================================================================================================================
<April 4, 2017>          Palash Baranwal		Created
=======================================================================================================================================================*/
CREATE PROCEDURE [dbo].[usp_CalculateSessionAverage]
AS
BEGIN
	IF OBJECT_ID(N'tempdb..#MinimumStop', N'U') IS NOT NULL
	BEGIN
		DROP TABLE #MinimumStop
	END;

	SELECT T1.id
		,T1.ai5
		,T1.TIMESTAMP AS EventStart
		,MIN(T2.TIMESTAMP) AS EventStop
	INTO #MinimumStop
	FROM dbo.Test2 T1 WITH (NOLOCK)
	INNER JOIN dbo.Test2 T2
		ON T1.id = T2.id
			AND T1.ai5 = T2.ai5
	WHERE T1.TIMESTAMP < T2.TIMESTAMP
		AND T1.EVENT1 = 'ggstart'
		AND T2.event1 = 'ggstop'
	GROUP BY T1.id
		,T1.ai5
		,T1.TIMESTAMP
	ORDER BY T1.id
		,T1.ai5
		,T1.TIMESTAMP

	IF OBJECT_ID(N'tempdb..#MinimumStart', N'U') IS NOT NULL
	BEGIN
		DROP TABLE #MinimumStart
	END;

	WITH CTE
	AS (
		SELECT id
			,ai5
			,EventStart
			,EventStop
			,DATEDIFF(S, EventStart, EventStop) AS TimeDiff
			,ROW_NUMBER() OVER (
				PARTITION BY id
				,ai5
				,EventStop ORDER BY EventStart ASC
				) RNStop
		FROM #MinimumStop
		)
	SELECT id
		,ai5
		,EventStart
		,EventStop
		,TimeDiff
	INTO #MinimumStart
	FROM CTE
	WHERE RNStop = 1

	IF OBJECT_ID(N'tempdb..#ConsecutiveDiff', N'U') IS NOT NULL
	BEGIN
		DROP TABLE #ConsecutiveDiff
	END;

	SELECT ID
		,ai5
		,EventStart
		,EventStop
		,TimeDiff
		,ROW_NUMBER() OVER (
			PARTITION BY ID
			,ai5 ORDER BY EventStart ASC
			) RNStart
		,ISNULL(DATEDIFF(ss, EventStop, lead(EventStart) OVER (
					PARTITION BY id
					,ai5 ORDER BY EventStart
					)), 31) AS CD
	INTO #ConsecutiveDiff
	FROM #MinimumStart

	
	IF OBJECT_ID(N'tempdb..#CalcFinalStop', N'U') IS NOT NULL
	BEGIN
		DROP TABLE #CalcFinalStop
	END;

	SELECT t1.id
		,t1.ai5
		,t1.EventStart
		,MIN(MinStop.EventStop) AS EventFinalStop
	INTO #CalcFinalStop
	FROM #ConsecutiveDiff t1
	LEFT JOIN #ConsecutiveDiff t2
		ON t1.id = t2.id
			AND t1.ai5 = t2.ai5
			AND (t1.RNStart - 1) = t2.RNStart
	INNER JOIN #ConsecutiveDiff MinStop
		ON t1.id = MinStop.id
			AND t1.ai5 = MinStop.ai5
			AND MinStop.EventStop > t1.EventStart
			AND MinStop.CD > 30
	WHERE t1.RNStart = 1
		OR t2.CD > 30
	GROUP BY t1.id
		,t1.ai5
		,t1.EventStart
	ORDER BY t1.id
		,t1.ai5
		,t1.EventStart;

	IF OBJECT_ID(N'[tmp].[GameSession]', N'U') IS NOT NULL
	BEGIN
		DROP TABLE [tmp].[GameSession]
	END;

	WITH Final
	AS (
		SELECT t6.id
			,t6.ai5
			,t6.EventStart
			,T6.EventFinalStop
			,SUM(t5.TimeDiff) AS TIME
			,CASE 
				WHEN SUM(t5.TimeDiff) > 60
					THEN 1
				ELSE 0
				END AS IsValid
		FROM #CalcFinalStop T6
		INNER JOIN #ConsecutiveDiff T5
			ON T6.ID = T5.ID
				AND T6.AI5 = T5.AI5
				AND T6.EventFinalStop >= t5.EventStop
		GROUP BY t6.id
			,t6.ai5
			,t6.EventStart
			,T6.EventFinalStop
		)
	SELECT ID AS GameID
		,COUNT(ID) AS 'Total Session'
		,COUNT(CASE 
				WHEN IsValid = 1
					THEN 1
				ELSE NULL
				END) AS 'Valid Session'
		,ISNULL((
				SUM(CASE 
						WHEN IsValid = 1
							THEN TIME
						ELSE NULL
						END) / COUNT(CASE 
						WHEN IsValid = 1
							THEN 1
						ELSE NULL
						END)
				), 0) AS 'Session Average'
	INTO [tmp].[GameSession]
	FROM Final
	WHERE TIME > 0
	GROUP BY ID
	ORDER BY COUNT(ID) DESC

	/*----Alter schema ---*/
	BEGIN TRY
		BEGIN TRANSACTION

		IF OBJECT_ID(N'[dbo].[GameSession]', N'U') IS NOT NULL
		BEGIN
			DROP TABLE [dbo].[GameSession];
		END;

		ALTER SCHEMA dbo TRANSFER [tmp].[GameSession];

		COMMIT TRANSACTION
	END TRY

	BEGIN CATCH
		ROLLBACK TRANSACTION
	END CATCH

	IF OBJECT_ID(N'tempdb..#MinimumStop', N'U') IS NOT NULL
	BEGIN
		DROP TABLE #MinimumStop
	END;

	IF OBJECT_ID(N'tempdb..#MinimumStart', N'U') IS NOT NULL
	BEGIN
		DROP TABLE #MinimumStart
	END;

	IF OBJECT_ID(N'tempdb..#ConsecutiveDiff', N'U') IS NOT NULL
	BEGIN
		DROP TABLE #ConsecutiveDiff
	END;

	IF OBJECT_ID(N'tempdb..#CalcFinalStop', N'U') IS NOT NULL
	BEGIN
		DROP TABLE #CalcFinalStop
	END;

END

GO


