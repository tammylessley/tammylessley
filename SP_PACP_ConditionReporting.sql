USE [IT_CoS]
GO

/****** Object:  StoredProcedure [CW].[sp_PACP_PipeConditionAndCriticality]    Script Date: 6/25/2021 7:53:23 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




/*
** Prod File: n/a  
** Name: sproc [CW].[sp_PACP_PipeConditionAndCriticality] 
** Location: SQL-07.IT_CoS
** Desc:  Pull all score data from PACP inspections, along with related WO details and then combine that with criticality assessment data from GIS tool that SW runs once annually
** Auth: Tammy Lessley
** Date: 20191122 
**************************
** Change History
**************************
** SysAid				Date       Author			Description 
** ------------------	--------   -------			------------------------------------
** Request 22292		20191122   Tammy Lessley	Create script
   Request 27660		20201106   Tammy Lessley	Comment out all references to "ObservDescScore <> 0".  Per Dan Sinkovich, those line items deserve to be seen. 

*/
CREATE PROCEDURE [CW].[sp_PACP_PipeConditionAndCriticality]  AS

BEGIN

/* New Temp table that all following queries will point to instead, to obtain the rightful 'F' values'
************************************************************************************************************/  

IF OBJECT_ID('tempdb..#UpdatedSTOBSERVATION') IS NOT NULL  DROP TABLE #UpdatedSTOBSERVATION;
	SELECT	* 
	INTO 	#UpdatedSTOBSERVATION 
	FROM
		(

			SELECT o.[TVID]
				  ,o.[OBSERVATIONID]
				  ,o.[DISTFROMUP]
				  ,o.[DISTFROMDOWN]
				  ,o.[OBSERVPOS]
				  ,o.[OBSERV_TYPE]
				  ,o.[OBSERVDESC]
				  ,'OBSERVDESCSCORE' = CASE WHEN LEFT(o.CONTINUOUS, 1) = 'F'
											 THEN o2.OBSERVDESCSCORE
											 ELSE o.OBSERVDESCSCORE
											 END --this will showcase the proper 'S's (those don't get altered), but it will showcase the 'F's as they are meant to be
				  ,o.[OBSERVREMARKS]
				  ,o.[CAUSE]
				  ,o.[TAPEREAD]
				  ,o.[TVTAPE]
				  ,o.[TVIMAGE]
				  ,o.[CCTVCODE]
				  ,o.[CONTINUOUS]
				  ,o.[VALUEDIMENSION1]
				  ,o.[VALUEDIMENSION2]
				  ,o.[VALUEPERCENT]
				  ,o.[JOINT]
				  ,o.[CLOCKTO]
			  FROM [CWProd].[Azteca].[STVOBSERVATION] o (nolock)  --12308
			  LEFT JOIN [CWProd].[Azteca].STVOBSERVATION o2 (nolock) ON  o.TVID = o2.TVID
																		AND	(CASE WHEN LEN(o.CONTINUOUS) = 3 --20201211
																					THEN RIGHT(o.CONTINUOUS, 2)
																					ELSE RIGHT(o.CONTINUOUS, 1)
																					END)							=  (CASE WHEN LEN(o2.CONTINUOUS) = 3 --20201211
																															THEN RIGHT(o2.CONTINUOUS, 2)
																															ELSE RIGHT(o2.CONTINUOUS, 1)
																															END)	
																	 AND LEFT(o2.CONTINUOUS, 1) = 'S' ---we only want to have the 'S' items shine through in place of all the 'F' line item scores from the "o" table.
																									  ---in other words, we need the 'S' items to stand-in for the 'F' items, b/c the 'F's are messed up

)x;
	CREATE INDEX IX_1 on #UpdatedSTOBSERVATION (TVID, CONTINUOUS); --new temp table 20201228


/* New Temp table that all following queries will point to instead, to obtain the rightful 'F' values 
************************************************************************************************************/ 


-------------------------------------------------------------------------
/* STRUCTURAL 
		1) split into structural vs operational
		2) split into continuous vs non-continuous
			a) continuous = use a formula.  
				i) formula = (    Start DistFromUp or DistFromDown
								- End   DistFromUp or DistFromDown ) 
							  / 5
			b) non-continuous = simply count the individual scores


*/
-------------------------------------------------------------------------
		/* 1 - highest score */

IF OBJECT_ID('tempdb..#StructuralHighestScore') IS NOT NULL  DROP TABLE #StructuralHighestScore;
	SELECT	* 
	INTO 	#StructuralHighestScore
	FROM		
		(
			  ---structural. first digit of QSR ... highest score for the given inspection on that asset 
			  SELECT [TVID]
					,'S1_HighestObservDescScore' = MAX(CASE WHEN [OBSERVDESCSCORE] <> 0
															THEN [OBSERVDESCSCORE]
															END)
			  FROM #UpdatedSTOBSERVATION (nolock)
			  WHERE CAUSE = 'S' 
			  --AND [OBSERVDESCSCORE] <> 0
			  AND [OBSERVDESCSCORE] IS NOT NULL
			  --AND TVID in (298)
			  GROUP BY [TVID]
		 )x;
	CREATE INDEX IX_1 on #StructuralHighestScore (TVID); --placing an index on this table, so that the subsequent query will run faster
		  -------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#StructuralHighestScoreCount_Continuous') IS NOT NULL  DROP TABLE #StructuralHighestScoreCount_Continuous;
	SELECT	* 
	INTO 	#StructuralHighestScoreCount_Continuous
	FROM		   
		  (
			  ---structural. second digit of QSR... count of how many #1's.  
			  SELECT o.[TVID]
					,'RoundedNumberOfContinuousDefects' = ISNULL(CAST(ROUND(
														(
															(MAX(CASE WHEN REPLACE(REPLACE(REPLACE(o2.CONTINUOUS, 'F', ''), 'S', ''), 'E', '')  =  RIGHT(o2.CONTINUOUS, 2) ---when both start and finish are from the same start and finish (e.g. S01 & F01, or S04 & F04)
																			AND LEFT(o.CONTINUOUS, 1) = 'F' ---we want the number of the start  
																		THEN ISNULL(o.DISTFROMUP, o.DISTFROMDOWN)
																	END))
															-
															(MAX(CASE WHEN REPLACE(REPLACE(REPLACE(o2.CONTINUOUS, 'F', ''), 'S', ''), 'E', '')  =  RIGHT(o2.CONTINUOUS, 2) ---when both start and finish are from the same start and finish (e.g. S01 & F01, or S04 & F04)
																		AND LEFT(o.CONTINUOUS, 1) = 'S' ---we want the number of the finish  
																	THEN ISNULL(o.DISTFROMUP, o.DISTFROMDOWN)
																END))
														)
														/ 5, 0) AS INT), 0)
			  FROM #UpdatedSTOBSERVATION (nolock) o
			  LEFT JOIN #UpdatedSTOBSERVATION (nolock) o2 ON o.TVID = o2.TVID AND REPLACE(REPLACE(REPLACE(o2.CONTINUOUS, 'F', ''), 'S', ''), 'E', '')  = RIGHT(o2.CONTINUOUS, 2) 
			  INNER JOIN #StructuralHighestScore nos ON o.TVID = nos.TVID AND o.[OBSERVDESCSCORE] = nos.[S1_HighestObservDescScore] ---only pull data in to the result set that applies to the #1 set above
			  WHERE o.CAUSE = 'S' ---just the structural pieces
			  AND o.CONTINUOUS IS NOT NULL ---just those continuous elements
			  --AND o.TVID in (181, 569, 689) 			  
			  GROUP BY o.[TVID]
					,RIGHT(o2.CONTINUOUS, 2)
			)x;
	CREATE INDEX IX_1 on #StructuralHighestScoreCount_Continuous (TVID); --placing an index on this table, so that the subsequent query will run faster
			-------------------------------------------------------------------------
			----counting the NON-continuous defects
IF OBJECT_ID('tempdb..#StructuralHighestScoreCount_NONContinuous') IS NOT NULL  DROP TABLE #StructuralHighestScoreCount_NONContinuous;
	SELECT	* 
	INTO 	#StructuralHighestScoreCount_NONContinuous
	FROM
			(
			  SELECT o.TVID
					,'CountOfNONContinuouseDefects' = COUNT(o.OBSERVDESCSCORE)
			  FROM #UpdatedSTOBSERVATION (nolock) o
			  INNER JOIN #StructuralHighestScore nos ON o.TVID = nos.TVID AND o.[OBSERVDESCSCORE] = nos.[S1_HighestObservDescScore] ---only pull data in for the desired score  
			  WHERE o.CAUSE = 'S' ---just the structural pieces
				AND o.CONTINUOUS IS NULL ---just those NON-continuous elements
				--AND o.TVID in (569) 
			  GROUP BY o.TVID 
			)x;
	CREATE INDEX IX_1 on #StructuralHighestScoreCount_NONContinuous (TVID); --placing an index on this table, so that the subsequent query will run faster 
			-------------------------------------------------------------------------
			----total defects
IF OBJECT_ID('tempdb..#StructuralHighestScoreCount2') IS NOT NULL  DROP TABLE #StructuralHighestScoreCount2;
	SELECT	* 
	INTO 	#StructuralHighestScoreCount2
	FROM
			(
				SELECT hs.TVID
					, hs.S1_HighestObservDescScore
					,'S2_CountHighestObservDescScore' = ISNULL(c.RoundedNumberOfContinuousDefects, 0)
													  + ISNULL(nc.CountOfNONContinuouseDefects, 0) 
				FROM #StructuralHighestScore hs
				LEFT JOIN #StructuralHighestScoreCount_Continuous c ON hs.TVID = c.TVID
				LEFT JOIN #StructuralHighestScoreCount_NONContinuous nc ON hs.TVID = nc.TVID
			) x;
	CREATE INDEX IX_1 on #StructuralHighestScoreCount2 (TVID); --placing an index on this table, so that the subsequent query will run faster 

IF OBJECT_ID('tempdb..#StructuralHighestScorePlusAlpha') IS NOT NULL  DROP TABLE #StructuralHighestScorePlusAlpha;
	SELECT	* 
	INTO 	#StructuralHighestScorePlusAlpha
	FROM
		  (
			---adding in the alpha component.  meaning, if the count is greater than 9, then it turns into an alpha
			---see IT_CoS.lkup.PACPNumberOfDefects for the correlation between the number of defects and the alpha representative
			SELECT nts.TVID
				  ,nts.[S1_HighestObservDescScore]
				  ,nts.[S2_CountHighestObservDescScore]
				  ,'S2_CountHighest_AlphaRepresentative' = CASE WHEN alpha.NumberOfDefects IS NULL ---- meaning the number of defects is less than 10
																THEN ''
																ELSE alpha.CorrespondingAlpha
																END					
			FROM #StructuralHighestScoreCount2 nts
			LEFT JOIN [IT_CoS].[lkup].[PACPNumberOfDefects] (nolock) alpha ON nts.[S2_CountHighestObservDescScore] = alpha.[NumberOfDefects]
			) x;
	CREATE INDEX IX_1 on #StructuralHighestScorePlusAlpha (TVID); --placing an index on this table, so that the subsequent query will run faster

IF OBJECT_ID('tempdb..#StructuralSecondHighestScore1') IS NOT NULL  DROP TABLE #StructuralSecondHighestScore1;
	SELECT	* 
	INTO 	#StructuralSecondHighestScore1
	FROM
		  /* 2 - second highest score */

			(
			  ---structural. 3rd digit of QSR ... second highest score for the given inspection on that asset 
			  SELECT DISTINCT [TVID]
					,'OBSERVDESCSCORE' = (CASE WHEN [OBSERVDESCSCORE] <> 0
											THEN [OBSERVDESCSCORE]
											END)			
			  FROM #UpdatedSTOBSERVATION (nolock)
			  WHERE CAUSE = 'S' 
			  --AND [OBSERVDESCSCORE] <> 0
			  AND [OBSERVDESCSCORE] IS NOT NULL
			  --AND TVID in (298, 682)
			  )x;
	CREATE INDEX IX_1 on #StructuralSecondHighestScore1 (TVID); --placing an index on this table, so that the subsequent query will run faster

IF OBJECT_ID('tempdb..#StructuralSecondHighestScore2') IS NOT NULL  DROP TABLE #StructuralSecondHighestScore2;
	SELECT	* 
	INTO 	#StructuralSecondHighestScore2
	FROM
			(
			  ---structural. 3rd digit of QSR ... second highest score for the given inspection on that asset 
			  SELECT [TVID]
					,OBSERVDESCSCORE
					,'S3_RowNumbers' = ROW_NUMBER() OVER(PARTITION BY [TVID] ORDER BY OBSERVDESCSCORE DESC)			
			  FROM #StructuralSecondHighestScore1 
			  )x;
	CREATE INDEX IX_1 on #StructuralSecondHighestScore2 (TVID); --placing an index on this table, so that the subsequent query will run faster

IF OBJECT_ID('tempdb..#StructuralSecondHighestScore3') IS NOT NULL  DROP TABLE #StructuralSecondHighestScore3;
	SELECT	* 
	INTO 	#StructuralSecondHighestScore3 
	FROM
			(
			  ---structural. 3rd digit of QSR ... second highest score for the given inspection on that asset 
			  SELECT [TVID]
					,'S3_SecondHighestObservDescScore' = OBSERVDESCSCORE			
			  FROM #StructuralSecondHighestScore2 
			  WHERE [S3_RowNumbers] = 2
			   )x;
	CREATE INDEX IX_1 on #StructuralSecondHighestScore3 (TVID); --placing an index on this table, so that the subsequent query will run faster

IF OBJECT_ID('tempdb..#StructuralSecondHighestScoreCount_Continuous') IS NOT NULL  DROP TABLE #StructuralSecondHighestScoreCount_Continuous;
	SELECT	* 
	INTO 	#StructuralSecondHighestScoreCount_Continuous 
    FROM	(
			 
			  SELECT o.[TVID]
					,'RoundedNumberOfContinuousDefects' = ISNULL(CAST(ROUND(
														(
															(MAX(CASE WHEN REPLACE(REPLACE(REPLACE(o2.CONTINUOUS, 'F', ''), 'S', ''), 'E', '')  =  RIGHT(o2.CONTINUOUS, 2) ---when both start and finish are from the same start and finish (e.g. S01 & F01, or S04 & F04)
																			AND LEFT(o.CONTINUOUS, 1) = 'F' ---we want the number of the start  
																		THEN ISNULL(o.DISTFROMUP, o.DISTFROMDOWN)
																	END))
															-
															(MAX(CASE WHEN REPLACE(REPLACE(REPLACE(o2.CONTINUOUS, 'F', ''), 'S', ''), 'E', '')  =  RIGHT(o2.CONTINUOUS, 2) ---when both start and finish are from the same start and finish (e.g. S01 & F01, or S04 & F04)
																		AND LEFT(o.CONTINUOUS, 1) = 'S' ---we want the number of the finish  
																	THEN ISNULL(o.DISTFROMUP, o.DISTFROMDOWN)
																END))
														)
														/ 5, 0) AS INT), 0)
			  FROM #UpdatedSTOBSERVATION (nolock) o
			  LEFT JOIN #UpdatedSTOBSERVATION (nolock) o2 ON o.TVID = o2.TVID AND REPLACE(REPLACE(REPLACE(o2.CONTINUOUS, 'F', ''), 'S', ''), 'E', '')  = RIGHT(o2.CONTINUOUS, 2) 
			  INNER JOIN #StructuralSecondHighestScore3 nos ON o.TVID = nos.TVID AND o.[OBSERVDESCSCORE] = nos.[S3_SecondHighestObservDescScore] ---only pull data in to the result set that applies to the #1 set above
			  WHERE o.CAUSE = 'S' ---just the structural pieces
			  AND o.CONTINUOUS IS NOT NULL ---just those continuous elements
			  --AND o.TVID in (181, 569, 689) 
			  
			  GROUP BY o.[TVID]
					,RIGHT(o2.CONTINUOUS, 2)
			)x;
	CREATE INDEX IX_1 on #StructuralSecondHighestScoreCount_Continuous (TVID); --placing an index on this table, so that the subsequent query will run faster
			-------------------------------------------------------------------------
			----counting the NON-continuous defects
IF OBJECT_ID('tempdb..#StructuralSecondHighestScoreCount_NONContinuous') IS NOT NULL  DROP TABLE #StructuralSecondHighestScoreCount_NONContinuous;
	SELECT	* 
	INTO 	#StructuralSecondHighestScoreCount_NONContinuous 
	FROM
			(
			  SELECT o.TVID
					,'CountOfNONContinuouseDefects' = COUNT(o.OBSERVDESCSCORE) 
			  FROM #UpdatedSTOBSERVATION (nolock) o
			  INNER JOIN #StructuralSecondHighestScore3 nos ON o.TVID = nos.TVID AND o.[OBSERVDESCSCORE] = nos.[S3_SecondHighestObservDescScore] ---only pull data in for the desired score  
			  WHERE o.CAUSE = 'S' ---just the structural pieces
				AND o.CONTINUOUS IS NULL ---just those NON-continuous elements
				--AND o.TVID in (569) 
			  GROUP BY o.TVID 
			)x;
	CREATE INDEX IX_1 on #StructuralSecondHighestScoreCount_NONContinuous (TVID); --placing an index on this table, so that the subsequent query will run faster 
			-------------------------------------------------------------------------
			----total defects
IF OBJECT_ID('tempdb..#StructuralSecondHighestScoreCount2') IS NOT NULL  DROP TABLE #StructuralSecondHighestScoreCount2;
	SELECT	* 
	INTO 	#StructuralSecondHighestScoreCount2 
	FROM
		  (
			  ---Operational. second digit of QSR... count of how many #1's.  
			  SELECT hs.[TVID]
					,hs.[S3_SecondHighestObservDescScore]
					,'S4_CountSecondHighestObservDescScore' = ISNULL(c.RoundedNumberOfContinuousDefects, 0)
															+ ISNULL(nc.CountOfNONContinuouseDefects, 0) 
			  FROM #StructuralSecondHighestScore3 hs
			  LEFT JOIN #StructuralSecondHighestScoreCount_Continuous c ON hs.TVID = c.TVID
			  LEFT JOIN #StructuralSecondHighestScoreCount_NONContinuous nc ON hs.TVID = nc.TVID
			)x;
	CREATE INDEX IX_1 on #StructuralSecondHighestScoreCount2 (TVID); --placing an index on this table, so that the subsequent query will run faster 
			-------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#StructuralSecondHighestScorePlusAlpha') IS NOT NULL  DROP TABLE #StructuralSecondHighestScorePlusAlpha;
	SELECT	* 
	INTO 	#StructuralSecondHighestScorePlusAlpha 
	FROM
		  (
			---adding in the alpha component.  meaning, if the count is greater than 9, then it turns into an alpha
			---see IT_CoS.lkup.PACPNumberOfDefects for the correlation between the number of defects and the alpha representative
			SELECT nts.TVID
				  ,nts.[S3_SecondHighestObservDescScore]
				  ,nts.[S4_CountSecondHighestObservDescScore]
				  ,'S4_CountSecondHighest_AlphaRepresentative' = CASE WHEN alpha.NumberOfDefects IS NULL ---- meaning the number of defects is less than 10
																THEN ''
																ELSE alpha.CorrespondingAlpha
																END
					
			FROM #StructuralSecondHighestScoreCount2 nts
			LEFT JOIN [IT_CoS].[lkup].[PACPNumberOfDefects] (nolock) alpha ON nts.[S4_CountSecondHighestObservDescScore] = alpha.[NumberOfDefects]
			)x;
	CREATE INDEX IX_1 on #StructuralSecondHighestScorePlusAlpha (TVID); --placing an index on this table, so that the subsequent query will run faster 
		 
		 /* 3 - third highest score */
		 
IF OBJECT_ID('tempdb..#StructuralThirdHighestScore1') IS NOT NULL  DROP TABLE #StructuralThirdHighestScore1;
	SELECT	* 
	INTO 	#StructuralThirdHighestScore1 
	FROM 
			(			  
			  SELECT DISTINCT [TVID]
					,'OBSERVDESCSCORE' = (CASE WHEN [OBSERVDESCSCORE] <> 0
												THEN [OBSERVDESCSCORE]
												END)			
			  FROM #UpdatedSTOBSERVATION (nolock)
			  WHERE CAUSE = 'S' 
			  --AND [OBSERVDESCSCORE] <> 0
			  AND [OBSERVDESCSCORE] IS NOT NULL
			  --AND TVID in (181, 569, 10, 689) 
			  )x;
	CREATE INDEX IX_1 on #StructuralThirdHighestScore1 (TVID); --placing an index on this table, so that the subsequent query will run faster 

IF OBJECT_ID('tempdb..#StructuralThirdHighestScore2') IS NOT NULL  DROP TABLE #StructuralThirdHighestScore2;
	SELECT	* 
	INTO 	#StructuralThirdHighestScore2 
	FROM
			(
			  SELECT [TVID]
					,OBSERVDESCSCORE
					,'S3_RowNumbers' = ROW_NUMBER() OVER(PARTITION BY [TVID] ORDER BY OBSERVDESCSCORE DESC)			
			  FROM #StructuralThirdHighestScore1 
			  )x;
	CREATE INDEX IX_1 on #StructuralThirdHighestScore2 (TVID); --placing an index on this table, so that the subsequent query will run faster 

IF OBJECT_ID('tempdb..#StructuralThirdHighestScore3') IS NOT NULL  DROP TABLE #StructuralThirdHighestScore3;
	SELECT	* 
	INTO 	#StructuralThirdHighestScore3 
	FROM
			(
			  SELECT [TVID]
					,'S3_ThirdHighestObservDescScore' = OBSERVDESCSCORE			
			  FROM #StructuralThirdHighestScore2 
			  WHERE [S3_RowNumbers] = 3
			  )x;
	CREATE INDEX IX_1 on #StructuralThirdHighestScore3 (TVID); --placing an index on this table, so that the subsequent query will run faster 

IF OBJECT_ID('tempdb..#StructuralThirdHighestScoreCount_Continuous') IS NOT NULL  DROP TABLE #StructuralThirdHighestScoreCount_Continuous;
	SELECT	* 
	INTO 	#StructuralThirdHighestScoreCount_Continuous 
	FROM
		  (
			   
			  SELECT o.[TVID]
					,'RoundedNumberOfContinuousDefects' = ISNULL(CAST(ROUND(
														(
															(MAX(CASE WHEN REPLACE(REPLACE(REPLACE(o2.CONTINUOUS, 'F', ''), 'S', ''), 'E', '')  =  RIGHT(o2.CONTINUOUS, 2) ---when both start and finish are from the same start and finish (e.g. S01 & F01, or S04 & F04)
																			AND LEFT(o.CONTINUOUS, 1) = 'F' ---we want the number of the start  
																		THEN ISNULL(o.DISTFROMUP, o.DISTFROMDOWN)
																	END))
															-
															(MAX(CASE WHEN REPLACE(REPLACE(REPLACE(o2.CONTINUOUS, 'F', ''), 'S', ''), 'E', '')  =  RIGHT(o2.CONTINUOUS, 2) ---when both start and finish are from the same start and finish (e.g. S01 & F01, or S04 & F04)
																		AND LEFT(o.CONTINUOUS, 1) = 'S' ---we want the number of the finish  
																	THEN ISNULL(o.DISTFROMUP, o.DISTFROMDOWN)
																END))
														)
														/ 5, 0) AS INT), 0)
			  FROM #UpdatedSTOBSERVATION (nolock) o
			  LEFT JOIN #UpdatedSTOBSERVATION (nolock) o2 ON o.TVID = o2.TVID AND REPLACE(REPLACE(REPLACE(o2.CONTINUOUS, 'F', ''), 'S', ''), 'E', '')  = RIGHT(o2.CONTINUOUS, 2) 
			  INNER JOIN #StructuralThirdHighestScore3 nos ON o.TVID = nos.TVID AND o.[OBSERVDESCSCORE] = nos.[S3_ThirdHighestObservDescScore] ---only pull data in to the result set that applies to the #1 set above
			  WHERE o.CAUSE = 'S' ---just the structural pieces
			  AND o.CONTINUOUS IS NOT NULL ---just those continuous elements
			  --AND o.TVID in (181, 569, 689) 
			 
			  GROUP BY o.[TVID]
					,RIGHT(o2.CONTINUOUS, 2)
			)x;
	CREATE INDEX IX_1 on #StructuralThirdHighestScoreCount_Continuous (TVID); --placing an index on this table, so that the subsequent query will run faster
			-------------------------------------------------------------------------
			----counting the NON-continuous defects
IF OBJECT_ID('tempdb..#StructuralThirdHighestScoreCount_NONContinuous') IS NOT NULL  DROP TABLE #StructuralThirdHighestScoreCount_NONContinuous;
	SELECT	* 
	INTO 	#StructuralThirdHighestScoreCount_NONContinuous 
	FROM
			(
			  SELECT o.TVID
					,'CountOfNONContinuouseDefects' = COUNT(o.OBSERVDESCSCORE)
			  FROM #UpdatedSTOBSERVATION (nolock) o
			  INNER JOIN #StructuralThirdHighestScore3 nos ON o.TVID = nos.TVID AND o.[OBSERVDESCSCORE] = nos.[S3_ThirdHighestObservDescScore] ---only pull data in for the desired score  
			  WHERE o.CAUSE = 'S' ---just the structural pieces
				AND o.CONTINUOUS IS NULL ---just those NON-continuous elements
				--AND o.TVID in (569) 
			  GROUP BY o.TVID 
			)x;
	CREATE INDEX IX_1 on #StructuralThirdHighestScoreCount_NONContinuous (TVID); --placing an index on this table, so that the subsequent query will run faster 
			-------------------------------------------------------------------------
			----total defects

IF OBJECT_ID('tempdb..#StructuralThirdHighestScoreCount2') IS NOT NULL  DROP TABLE #StructuralThirdHighestScoreCount2;
	SELECT	* 
	INTO 	#StructuralThirdHighestScoreCount2 
	FROM
		  (			 
			  SELECT hs.[TVID]
					,hs.[S3_ThirdHighestObservDescScore]
					,'S4_CountThirdHighestObservDescScore' =  ISNULL(c.RoundedNumberOfContinuousDefects, 0)
															+ ISNULL(nc.CountOfNONContinuouseDefects, 0) 
			  FROM #StructuralThirdHighestScore3 hs
			  LEFT JOIN #StructuralThirdHighestScoreCount_Continuous c ON hs.TVID = c.TVID
			  LEFT JOIN #StructuralThirdHighestScoreCount_NONContinuous nc ON hs.TVID = nc.TVID
			)x;
	CREATE INDEX IX_1 on #StructuralThirdHighestScoreCount2 (TVID); --placing an index on this table, so that the subsequent query will run faster 
			
			/* 4 - fourth highest score */
		 
IF OBJECT_ID('tempdb..#StructuralFourthHighestScore1') IS NOT NULL  DROP TABLE #StructuralFourthHighestScore1;
	SELECT	* 
	INTO 	#StructuralFourthHighestScore1 
	FROM
			(			  
			  SELECT DISTINCT [TVID]
					,'OBSERVDESCSCORE' = (CASE WHEN [OBSERVDESCSCORE] <> 0
												THEN [OBSERVDESCSCORE]
												END)		
			  FROM #UpdatedSTOBSERVATION (nolock)
			  WHERE CAUSE = 'S' 
			  --AND [OBSERVDESCSCORE] <> 0
			  AND [OBSERVDESCSCORE] IS NOT NULL
			  --AND TVID in (181, 569, 10, 689)
			 )x;
	CREATE INDEX IX_1 on #StructuralFourthHighestScore1 (TVID); --placing an index on this table, so that the subsequent query will run faster 

IF OBJECT_ID('tempdb..#StructuralFourthHighestScore2') IS NOT NULL  DROP TABLE #StructuralFourthHighestScore2;
	SELECT	* 
	INTO 	#StructuralFourthHighestScore2 
	FROM
			(
			  SELECT [TVID]
					,OBSERVDESCSCORE
					,'S3_RowNumbers' = ROW_NUMBER() OVER(PARTITION BY [TVID] ORDER BY OBSERVDESCSCORE DESC)			
			  FROM #StructuralFourthHighestScore1 
			  )x;
	CREATE INDEX IX_1 on #StructuralFourthHighestScore2 (TVID); --placing an index on this table, so that the subsequent query will run faster 

IF OBJECT_ID('tempdb..#StructuralFourthHighestScore3') IS NOT NULL  DROP TABLE #StructuralFourthHighestScore3;
	SELECT	* 
	INTO 	#StructuralFourthHighestScore3 
	FROM
			(
			  SELECT [TVID]
					,'S3_FourthHighestObservDescScore' = OBSERVDESCSCORE			
			  FROM #StructuralFourthHighestScore2 
			  WHERE [S3_RowNumbers] = 4
			  )x;
	CREATE INDEX IX_1 on #StructuralFourthHighestScore3 (TVID); --placing an index on this table, so that the subsequent query will run faster 

IF OBJECT_ID('tempdb..#StructuralFourthHighestScoreCount_Continuous') IS NOT NULL  DROP TABLE #StructuralFourthHighestScoreCount_Continuous;
	SELECT	* 
	INTO 	#StructuralFourthHighestScoreCount_Continuous 
	FROM
		  (			    
			  SELECT o.[TVID]
					,'RoundedNumberOfContinuousDefects' = ISNULL(CAST(ROUND(
														(
															(MAX(CASE WHEN REPLACE(REPLACE(REPLACE(o2.CONTINUOUS, 'F', ''), 'S', ''), 'E', '')  =  RIGHT(o2.CONTINUOUS, 2) ---when both start and finish are from the same start and finish (e.g. S01 & F01, or S04 & F04)
																			AND LEFT(o.CONTINUOUS, 1) = 'F' ---we want the number of the start  
																		THEN ISNULL(o.DISTFROMUP, o.DISTFROMDOWN)
																	END))
															-
															(MAX(CASE WHEN REPLACE(REPLACE(REPLACE(o2.CONTINUOUS, 'F', ''), 'S', ''), 'E', '')  =  RIGHT(o2.CONTINUOUS, 2) ---when both start and finish are from the same start and finish (e.g. S01 & F01, or S04 & F04)
																		AND LEFT(o.CONTINUOUS, 1) = 'S' ---we want the number of the finish  
																	THEN ISNULL(o.DISTFROMUP, o.DISTFROMDOWN)
																END))
														)
														/ 5, 0) AS INT), 0)
			  FROM #UpdatedSTOBSERVATION (nolock) o
			  LEFT JOIN #UpdatedSTOBSERVATION (nolock) o2 ON o.TVID = o2.TVID AND REPLACE(REPLACE(REPLACE(o2.CONTINUOUS, 'F', ''), 'S', ''), 'E', '')  = RIGHT(o2.CONTINUOUS, 2) 
			  INNER JOIN #StructuralFourthHighestScore3 nos ON o.TVID = nos.TVID AND o.[OBSERVDESCSCORE] = nos.S3_FourthHighestObservDescScore ---only pull data in to the result set that applies to the #1 set above
			  WHERE o.CAUSE = 'S' ---just the structural pieces
			  AND o.CONTINUOUS IS NOT NULL ---just those continuous elements
			  --AND o.TVID in (181, 569, 689) 
			  
			  GROUP BY o.[TVID]
					,RIGHT(o2.CONTINUOUS, 2)
			)x;
	CREATE INDEX IX_1 on #StructuralFourthHighestScoreCount_Continuous (TVID); --placing an index on this table, so that the subsequent query will run faster
			-------------------------------------------------------------------------
			----counting the NON-continuous defects
IF OBJECT_ID('tempdb..#StructuralFourthHighestScoreCount_NONContinuous') IS NOT NULL  DROP TABLE #StructuralFourthHighestScoreCount_NONContinuous;
	SELECT	* 
	INTO 	#StructuralFourthHighestScoreCount_NONContinuous 
	FROM
			(
			  SELECT o.TVID
					,'CountOfNONContinuouseDefects' = COUNT(o.OBSERVDESCSCORE)
			  FROM #UpdatedSTOBSERVATION (nolock) o
			  INNER JOIN #StructuralFourthHighestScore3 nos ON o.TVID = nos.TVID AND o.[OBSERVDESCSCORE] = nos.S3_FourthHighestObservDescScore ---only pull data in for the desired score  
			  WHERE o.CAUSE = 'S' ---just the structural pieces
				AND o.CONTINUOUS IS NULL ---just those NON-continuous elements
				--AND o.TVID in (569) 
			  GROUP BY o.TVID 
			)x;
	CREATE INDEX IX_1 on #StructuralFourthHighestScoreCount_NONContinuous (TVID); --placing an index on this table, so that the subsequent query will run faster 
			-------------------------------------------------------------------------
			----total defects
IF OBJECT_ID('tempdb..#StructuralFourthHighestScoreCount2') IS NOT NULL  DROP TABLE #StructuralFourthHighestScoreCount2;
	SELECT	* 
	INTO 	#StructuralFourthHighestScoreCount2 
	FROM
		  (			 
			  SELECT hs.[TVID]
					,hs.[S3_FourthHighestObservDescScore]
					,'S4_CountFourthHighestObservDescScore' =  ISNULL(c.RoundedNumberOfContinuousDefects, 0)
															 + ISNULL(nc.CountOfNONContinuouseDefects, 0) 
			  FROM #StructuralFourthHighestScore3 hs
			  LEFT JOIN #StructuralFourthHighestScoreCount_Continuous c ON hs.TVID = c.TVID
			  LEFT JOIN #StructuralFourthHighestScoreCount_NONContinuous nc ON hs.TVID = nc.TVID
			)x;
	CREATE INDEX IX_1 on #StructuralFourthHighestScoreCount2 (TVID); --placing an index on this table, so that the subsequent query will run faster 
			/* 5 - fifth highest score */
		 
IF OBJECT_ID('tempdb..#StructuralFifthHighestScore1') IS NOT NULL  DROP TABLE #StructuralFifthHighestScore1;
	SELECT	* 
	INTO 	#StructuralFifthHighestScore1 
	FROM
			(			  
			  SELECT DISTINCT [TVID]
					,'OBSERVDESCSCORE' = (CASE WHEN [OBSERVDESCSCORE] <> 0
												THEN [OBSERVDESCSCORE]
												END)			
			  FROM #UpdatedSTOBSERVATION (nolock)
			  WHERE CAUSE = 'S' 
			  --AND [OBSERVDESCSCORE] <> 0
			  AND [OBSERVDESCSCORE] IS NOT NULL
			  --AND TVID in (181, 569, 10, 689)
			  )x;
	CREATE INDEX IX_1 on #StructuralFifthHighestScore1 (TVID); --placing an index on this table, so that the subsequent query will run faster 

IF OBJECT_ID('tempdb..#StructuralFifthHighestScore2') IS NOT NULL  DROP TABLE #StructuralFifthHighestScore2;
	SELECT	* 
	INTO 	#StructuralFifthHighestScore2 
	FROM
			(
			  SELECT [TVID]
					,OBSERVDESCSCORE
					,'S3_RowNumbers' = ROW_NUMBER() OVER(PARTITION BY [TVID] ORDER BY OBSERVDESCSCORE DESC)			
			  FROM #StructuralFifthHighestScore1 
			 )x;
	CREATE INDEX IX_1 on #StructuralFifthHighestScore2 (TVID); --placing an index on this table, so that the subsequent query will run faster 

IF OBJECT_ID('tempdb..#StructuralFifthHighestScore3') IS NOT NULL  DROP TABLE #StructuralFifthHighestScore3;
	SELECT	* 
	INTO 	#StructuralFifthHighestScore3 
	FROM
			(
			  SELECT [TVID] 
					,'S3_FifthHighestObservDescScore' = OBSERVDESCSCORE			
			  FROM #StructuralFifthHighestScore2 
			  WHERE [S3_RowNumbers] = 5
			  )x;
	CREATE INDEX IX_1 on #StructuralFifthHighestScore3 (TVID); --placing an index on this table, so that the subsequent query will run faster

IF OBJECT_ID('tempdb..#StructuralFifthHighestScoreCount_Continuous') IS NOT NULL  DROP TABLE #StructuralFifthHighestScoreCount_Continuous;
	SELECT	* 
	INTO 	#StructuralFifthHighestScoreCount_Continuous 
	FROM
		  (
			    
			  SELECT o.[TVID]
					,'RoundedNumberOfContinuousDefects' = ISNULL(CAST(ROUND(
														(
															(MAX(CASE WHEN REPLACE(REPLACE(REPLACE(o2.CONTINUOUS, 'F', ''), 'S', ''), 'E', '')  =  RIGHT(o2.CONTINUOUS, 2) ---when both start and finish are from the same start and finish (e.g. S01 & F01, or S04 & F04)
																			AND LEFT(o.CONTINUOUS, 1) = 'F' ---we want the number of the start  
																		THEN ISNULL(o.DISTFROMUP, o.DISTFROMDOWN)
																	END))
															-
															(MAX(CASE WHEN REPLACE(REPLACE(REPLACE(o2.CONTINUOUS, 'F', ''), 'S', ''), 'E', '')  =  RIGHT(o2.CONTINUOUS, 2) ---when both start and finish are from the same start and finish (e.g. S01 & F01, or S04 & F04)
																		AND LEFT(o.CONTINUOUS, 1) = 'S' ---we want the number of the finish  
																	THEN ISNULL(o.DISTFROMUP, o.DISTFROMDOWN)
																END))
														)
														/ 5, 0) AS INT), 0)
			  FROM #UpdatedSTOBSERVATION (nolock) o
			  LEFT JOIN #UpdatedSTOBSERVATION (nolock) o2 ON o.TVID = o2.TVID AND REPLACE(REPLACE(REPLACE(o2.CONTINUOUS, 'F', ''), 'S', ''), 'E', '')  = RIGHT(o2.CONTINUOUS, 2) 
			  INNER JOIN #StructuralFifthHighestScore3 nos ON o.TVID = nos.TVID AND o.[OBSERVDESCSCORE] = nos.S3_FifthHighestObservDescScore ---only pull data in to the result set that applies to the #1 set above
			  WHERE o.CAUSE = 'S' ---just the structural pieces
			  AND o.CONTINUOUS IS NOT NULL ---just those continuous elements
			  --AND o.TVID in (181, 569, 689) 
			  
			  GROUP BY o.[TVID]
					,RIGHT(o2.CONTINUOUS, 2) 
			 )x;
	CREATE INDEX IX_1 on #StructuralFifthHighestScoreCount_Continuous (TVID); --placing an index on this table, so that the subsequent query will run faster
			-------------------------------------------------------------------------
			----counting the NON-continuous defects
IF OBJECT_ID('tempdb..#StructuralFifthHighestScoreCount_NONContinuous') IS NOT NULL  DROP TABLE #StructuralFifthHighestScoreCount_NONContinuous;
	SELECT	* 
	INTO 	#StructuralFifthHighestScoreCount_NONContinuous 
	FROM
			(
			  SELECT o.TVID 
					,'CountOfNONContinuouseDefects' = COUNT(o.OBSERVDESCSCORE)
			  FROM #UpdatedSTOBSERVATION (nolock) o
			  INNER JOIN #StructuralFifthHighestScore3 nos ON o.TVID = nos.TVID AND o.[OBSERVDESCSCORE] = nos.S3_FifthHighestObservDescScore ---only pull data in for the desired score  
			  WHERE o.CAUSE = 'S' ---just the structural pieces
				AND o.CONTINUOUS IS NULL ---just those NON-continuous elements
				--AND o.TVID in (569) 
			  GROUP BY o.TVID 
			 )x;
	CREATE INDEX IX_1 on #StructuralFifthHighestScoreCount_NONContinuous (TVID); --placing an index on this table, so that the subsequent query will run faster 
			-------------------------------------------------------------------------
			----total defects
IF OBJECT_ID('tempdb..#StructuralFifthHighestScoreCount2') IS NOT NULL  DROP TABLE #StructuralFifthHighestScoreCount2;
	SELECT	* 
	INTO 	#StructuralFifthHighestScoreCount2 
	FROM
		  (			 
			  SELECT hs.[TVID]
					,hs.[S3_FifthHighestObservDescScore]
					,'S4_CountFifthHighestObservDescScore' =   ISNULL(c.RoundedNumberOfContinuousDefects, 0)
															 + ISNULL(nc.CountOfNONContinuouseDefects, 0) 
			  FROM #StructuralFifthHighestScore3 hs
			  LEFT JOIN #StructuralFifthHighestScoreCount_Continuous c ON hs.TVID = c.TVID
			  LEFT JOIN #StructuralFifthHighestScoreCount_NONContinuous nc ON hs.TVID = nc.TVID
			)x;
	CREATE INDEX IX_1 on #StructuralFifthHighestScoreCount2 (TVID); --placing an index on this table, so that the subsequent query will run faster 
			----------------QSR
IF OBJECT_ID('tempdb..#StructuralQSR') IS NOT NULL  DROP TABLE #StructuralQSR;
	SELECT	* 
	INTO 	#StructuralQSR 
	FROM
		  (
			  SELECT DISTINCT
					 a.TVID
					 ,'QSR' = CAST(ISNULL(a.S1_HighestObservDescScore, '0') AS VARCHAR(10))
							+ CAST(ISNULL(CASE WHEN a.S2_CountHighestObservDescScore > 9
												THEN a.S2_CountHighest_AlphaRepresentative
												ELSE CAST(a.S2_CountHighestObservDescScore AS VARCHAR(10))
												END, '') AS VARCHAR(10))
							+ CAST(ISNULL(b.S3_SecondHighestObservDescScore, '0') AS VARCHAR(10))
							+ CAST(ISNULL(CASE WHEN b.S4_CountSecondHighestObservDescScore > 9
												THEN b.S4_CountSecondHighest_AlphaRepresentative
												ELSE CAST(b.S4_CountSecondHighestObservDescScore AS VARCHAR(10))
												END, '0') AS VARCHAR(10))

			  FROM #StructuralHighestScorePlusAlpha a
			  LEFT JOIN #StructuralSecondHighestScorePlusAlpha b ON a.TVID = b.TVID
			  --order by tvid
		  )x;
	CREATE INDEX IX_1 on #StructuralQSR (TVID); --placing an index on this table, so that the subsequent query will run faster 
	
IF OBJECT_ID('tempdb..#StructuralSPR') IS NOT NULL  DROP TABLE #StructuralSPR;
	SELECT	* 
	INTO 	#StructuralSPR 
	FROM
		(	
			SELECT DISTINCT 
				 h.tvid, 
				'SPR' = ISNULL((h.S1_HighestObservDescScore * hc.S2_CountHighestObservDescScore), 0)
					 +  ISNULL((shc.S3_SecondHighestObservDescScore * shc.S4_CountSecondHighestObservDescScore), 0)
					 +  ISNULL((th.S3_ThirdHighestObservDescScore * thc.S4_CountThirdHighestObservDescScore), 0)
					 +  ISNULL((fh.S3_FourthHighestObservDescScore * fhc.S4_CountFourthHighestObservDescScore), 0)
					 +  ISNULL((f5h.S3_FifthHighestObservDescScore * f5hc.S4_CountFifthHighestObservDescScore), 0)
			FROM #StructuralHighestScore h
			LEFT JOIN #StructuralHighestScoreCount2 hc			ON h.TVID = hc.TVID
			LEFT JOIN #StructuralSecondHighestScore3 sh			ON h.TVID = sh.TVID
			LEFT JOIN #StructuralSecondHighestScoreCount2 shc	ON h.TVID = shc.TVID
			LEFT JOIN #StructuralThirdHighestScore3 th			ON h.TVID = th.TVID
			LEFT JOIN #StructuralThirdHighestScoreCount2 thc		ON h.TVID = thc.TVID
			LEFT JOIN #StructuralFourthHighestScore3 fh			ON h.TVID = fh.TVID
			LEFT JOIN #StructuralFourthHighestScoreCount2 fhc	ON h.TVID = fhc.TVID	
			LEFT JOIN #StructuralFifthHighestScore3 f5h			ON h.TVID = f5h.TVID
			LEFT JOIN #StructuralFifthHighestScoreCount2 f5hc	ON h.TVID = f5hc.TVID
			
			--where h.TVID = 569 
		)x;
	CREATE INDEX IX_1 on #StructuralSPR (TVID); --placing an index on this table, so that the subsequent query will run faster 

IF OBJECT_ID('tempdb..#StructuralSPRI') IS NOT NULL  DROP TABLE #StructuralSPRI;
	SELECT	* 
	INTO 	#StructuralSPRI 
	FROM
		(
			SELECT DISTINCT 
				spr.TVID
				, 'SPRI' = CASE WHEN (
									  ISNULL(hc.S2_CountHighestObservDescScore, 0)
									+ ISNULL(shc.S4_CountSecondHighestObservDescScore ,0)
									+ ISNULL(thc.S4_CountThirdHighestObservDescScore , 0)
									+ ISNULL(fhc.S4_CountFourthHighestObservDescScore , 0)
									+ ISNULL(f5hc.S4_CountFifthHighestObservDescScore , 0)
									) = 0
								THEN 0
								ELSE spr.SPR /
										(
										  ISNULL(hc.S2_CountHighestObservDescScore, 0)
										+ ISNULL(shc.S4_CountSecondHighestObservDescScore ,0)
										+ ISNULL(thc.S4_CountThirdHighestObservDescScore , 0)
										+ ISNULL(fhc.S4_CountFourthHighestObservDescScore , 0)
										+ ISNULL(f5hc.S4_CountFifthHighestObservDescScore , 0)
										)
								END
				, 'StructuralDefects' = (
										  ISNULL(hc.S2_CountHighestObservDescScore, 0)
										+ ISNULL(shc.S4_CountSecondHighestObservDescScore ,0)
										+ ISNULL(thc.S4_CountThirdHighestObservDescScore , 0)
										+ ISNULL(fhc.S4_CountFourthHighestObservDescScore , 0)
										+ ISNULL(f5hc.S4_CountFifthHighestObservDescScore , 0)
										) 
				
			FROM #StructuralSPR spr
			LEFT JOIN #StructuralHighestScoreCount2 hc			ON spr.TVID = hc.TVID
			LEFT JOIN #StructuralSecondHighestScoreCount2 shc	ON spr.TVID = shc.TVID
			LEFT JOIN #StructuralThirdHighestScoreCount2 thc	ON spr.TVID = thc.TVID
			LEFT JOIN #StructuralFourthHighestScoreCount2 fhc	ON spr.TVID = fhc.TVID
			LEFT JOIN #StructuralFifthHighestScoreCount2 f5hc	ON spr.TVID = f5hc.TVID 

			--where spr.TVID = 181 

		)x;
	CREATE INDEX IX_1 on #StructuralSPRI (TVID); --placing an index on this table, so that the subsequent query will run faster 
  -------------------------------------------------------------------------
  /* OPERATIONS & MAINTENANCE 
		1) split into structural vs operational
		2) split into continuous vs non-continuous
			a) continuous = use a formula.  
				i) formula = (    Start DistFromUp or DistFromDown
								- End   DistFromUp or DistFromDown ) 
							  / 5
			b) non-continuous = simply count the individual scores
  */
  -------------------------------------------------------------------------

  /* 1 - highest score */

IF OBJECT_ID('tempdb..#OperationalHighestScore') IS NOT NULL  DROP TABLE #OperationalHighestScore;
	SELECT	* 
	INTO 	#OperationalHighestScore 
	FROM
		(
			  ---Operational. first digit of QSR ... highest score for the given inspection on that asset 
			  SELECT [TVID]
					,'OM1_HighestObservDescScore' = MAX(CASE WHEN [OBSERVDESCSCORE] <> 0
															THEN [OBSERVDESCSCORE]
															END)
			  FROM #UpdatedSTOBSERVATION (nolock)
			  WHERE CAUSE = 'O' 
			  --AND [OBSERVDESCSCORE] <> 0
			  AND [OBSERVDESCSCORE] IS NOT NULL
			  --AND TVID in (1081) --181, 569,10)
			  GROUP BY [TVID]
		)x;
	CREATE INDEX IX_1 on #OperationalHighestScore (TVID); --placing an index on this table, so that the subsequent query will run faster 
	
IF OBJECT_ID('tempdb..#OperationalHighestScoreCount_Continuous') IS NOT NULL  DROP TABLE #OperationalHighestScoreCount_Continuous;
	SELECT	* 
	INTO 	#OperationalHighestScoreCount_Continuous 
	FROM
		  (
			   
			  SELECT o.[TVID]
					,'RoundedNumberOfContinuousDefects' = ISNULL(CAST(ROUND(
														(
															(MAX(CASE WHEN REPLACE(REPLACE(REPLACE(o2.CONTINUOUS, 'F', ''), 'S', ''), 'E', '')  =  RIGHT(o2.CONTINUOUS, 2) ---when both start and finish are from the same start and finish (e.g. S01 & F01, or S04 & F04)
																			AND LEFT(o.CONTINUOUS, 1) = 'F' ---we want the number of the start  
																		THEN ISNULL(o.DISTFROMUP, o.DISTFROMDOWN)
																	END))
															-
															(MAX(CASE WHEN REPLACE(REPLACE(REPLACE(o2.CONTINUOUS, 'F', ''), 'S', ''), 'E', '')  =  RIGHT(o2.CONTINUOUS, 2) ---when both start and finish are from the same start and finish (e.g. S01 & F01, or S04 & F04)
																		AND LEFT(o.CONTINUOUS, 1) = 'S' ---we want the number of the finish  
																	THEN ISNULL(o.DISTFROMUP, o.DISTFROMDOWN)
																END))
														)
														/ 5, 0) AS INT), 0)
			  FROM #UpdatedSTOBSERVATION (nolock) o
			  LEFT JOIN #UpdatedSTOBSERVATION (nolock) o2 ON o.TVID = o2.TVID AND REPLACE(REPLACE(REPLACE(o2.CONTINUOUS, 'F', ''), 'S', ''), 'E', '')  = RIGHT(o2.CONTINUOUS, 2) 
			  INNER JOIN #OperationalHighestScore nos ON o.TVID = nos.TVID AND o.[OBSERVDESCSCORE] = nos.OM1_HighestObservDescScore ---only pull data in to the result set that applies to the #1 set above
			  WHERE o.CAUSE = 'O' ---just the structural pieces
			  AND o.CONTINUOUS IS NOT NULL ---just those continuous elements
			  --AND o.TVID in (1081) --181, 569, 689) 
			  
			  GROUP BY o.[TVID]
					,RIGHT(o2.CONTINUOUS, 2)
			)x;
	CREATE INDEX IX_1 on #OperationalHighestScoreCount_Continuous (TVID); --placing an index on this table, so that the subsequent query will run faster 
			-------------------------------------------------------------------------
			----counting the NON-continuous defects
IF OBJECT_ID('tempdb..#OperationalHighestScoreCount_NONContinuous') IS NOT NULL  DROP TABLE #OperationalHighestScoreCount_NONContinuous;
	SELECT	* 
	INTO 	#OperationalHighestScoreCount_NONContinuous 
	FROM
			(
			  SELECT o.TVID
					,'CountOfNONContinuouseDefects' = COUNT(o.OBSERVDESCSCORE)
			  FROM #UpdatedSTOBSERVATION (nolock) o
			  INNER JOIN #OperationalHighestScore nos ON o.TVID = nos.TVID AND o.[OBSERVDESCSCORE] = nos.OM1_HighestObservDescScore ---only pull data in for the desired score  
			  WHERE o.CAUSE = 'O' ---just the structural pieces
				AND o.CONTINUOUS IS NULL ---just those NON-continuous elements
				--AND o.TVID in (569) 
			  GROUP BY o.TVID 
			)x;
	CREATE INDEX IX_1 on #OperationalHighestScoreCount_NONContinuous (TVID); --placing an index on this table, so that the subsequent query will run faster  
			-------------------------------------------------------------------------
			----total defects
IF OBJECT_ID('tempdb..#OperationalHighestScoreCount2') IS NOT NULL  DROP TABLE #OperationalHighestScoreCount2;
	SELECT	* 
	INTO 	#OperationalHighestScoreCount2 
	FROM
			(
				SELECT hs.TVID
					, hs.OM1_HighestObservDescScore
					,'OM2_CountHighestObservDescScore' = ISNULL(c.RoundedNumberOfContinuousDefects, 0)
													  + ISNULL(nc.CountOfNONContinuouseDefects, 0) 
				FROM #OperationalHighestScore hs
				LEFT JOIN #OperationalHighestScoreCount_Continuous c ON hs.TVID = c.TVID
				LEFT JOIN #OperationalHighestScoreCount_NONContinuous nc ON hs.TVID = nc.TVID
				--where hs.TVID = 1081
			)x;
	CREATE INDEX IX_1 on #OperationalHighestScoreCount2 (TVID); --placing an index on this table, so that the subsequent query will run faster  

IF OBJECT_ID('tempdb..#OperationalHighestScorePlusAlpha') IS NOT NULL  DROP TABLE #OperationalHighestScorePlusAlpha;
	SELECT	* 
	INTO 	#OperationalHighestScorePlusAlpha 
	FROM
		  (
			---adding in the alpha component.  meaning, if the count is greater than 9, then it turns into an alpha
			---see IT_CoS.lkup.PACPNumberOfDefects for the correlation between the number of defects and the alpha representative
			SELECT nts.TVID
				  ,nts.[OM1_HighestObservDescScore]
				  ,nts.[OM2_CountHighestObservDescScore]
				  ,'OM2_CountHighest_AlphaRepresentative' = CASE WHEN alpha.NumberOfDefects IS NULL ---- meaning the number of defects is less than 10
																THEN ''
																ELSE alpha.CorrespondingAlpha
																END
					
			FROM #OperationalHighestScoreCount2 nts
			LEFT JOIN [IT_CoS].[lkup].[PACPNumberOfDefects] (nolock) alpha ON nts.[OM2_CountHighestObservDescScore] = alpha.[NumberOfDefects]
			)x;
	CREATE INDEX IX_1 on #OperationalHighestScorePlusAlpha (TVID); --placing an index on this table, so that the subsequent query will run faster  
		
		/* 2 - second highest score */

IF OBJECT_ID('tempdb..#OperationalSecondHighestScore1') IS NOT NULL  DROP TABLE #OperationalSecondHighestScore1;
	SELECT	* 
	INTO 	#OperationalSecondHighestScore1 
	FROM
			(
			  ---Operational. 3rd digit of QSR ... second highest score for the given inspection on that asset 
			  SELECT DISTINCT [TVID]
					,'OBSERVDESCSCORE' = (CASE WHEN [OBSERVDESCSCORE] <> 0
												THEN [OBSERVDESCSCORE]
												END)		
			  FROM #UpdatedSTOBSERVATION (nolock)
			  WHERE CAUSE = 'O' 
			  --AND [OBSERVDESCSCORE] <> 0
			  AND [OBSERVDESCSCORE] IS NOT NULL
			  --AND TVID in (181, 569,10)
			 )x;
	CREATE INDEX IX_1 on #OperationalSecondHighestScore1 (TVID); --placing an index on this table, so that the subsequent query will run faster  

IF OBJECT_ID('tempdb..#OperationalSecondHighestScore2') IS NOT NULL  DROP TABLE #OperationalSecondHighestScore2;
	SELECT	* 
	INTO 	#OperationalSecondHighestScore2 
	FROM
			(
			  ---Operational. 3rd digit of QSR ... second highest score for the given inspection on that asset 
			  SELECT [TVID]
					,OBSERVDESCSCORE
					,'OM3_RowNumbers' = ROW_NUMBER() OVER(PARTITION BY [TVID] ORDER BY OBSERVDESCSCORE DESC)			
			  FROM #OperationalSecondHighestScore1 
			 )x;
	CREATE INDEX IX_1 on #OperationalSecondHighestScore2 (TVID); --placing an index on this table, so that the subsequent query will run faster  

IF OBJECT_ID('tempdb..#OperationalSecondHighestScore3') IS NOT NULL  DROP TABLE #OperationalSecondHighestScore3;
	SELECT	* 
	INTO 	#OperationalSecondHighestScore3 
	FROM
			(
			  ---Operational. 3rd digit of QSR ... second highest score for the given inspection on that asset 
			  SELECT [TVID]
					,'OM3_SecondHighestObservDescScore' = OBSERVDESCSCORE			
			  FROM #OperationalSecondHighestScore2 
			  WHERE [OM3_RowNumbers] = 2
			  )x;
	CREATE INDEX IX_1 on #OperationalSecondHighestScore3 (TVID); --placing an index on this table, so that the subsequent query will run faster  

IF OBJECT_ID('tempdb..#OperationalSecondHighestScoreCount_Continuous') IS NOT NULL  DROP TABLE #OperationalSecondHighestScoreCount_Continuous;
	SELECT	* 
	INTO 	#OperationalSecondHighestScoreCount_Continuous 
	FROM
		  (
			    
			  SELECT o.[TVID]
					,'RoundedNumberOfContinuousDefects' = ISNULL(CAST(ROUND(
														(
															(MAX(CASE WHEN REPLACE(REPLACE(REPLACE(o2.CONTINUOUS, 'F', ''), 'S', ''), 'E', '')  =  RIGHT(o2.CONTINUOUS, 2) ---when both start and finish are from the same start and finish (e.g. S01 & F01, or S04 & F04)
																			AND LEFT(o.CONTINUOUS, 1) = 'F' ---we want the number of the start  
																		THEN ISNULL(o.DISTFROMUP, ISNULL(o.DISTFROMDOWN,0))
																	END))
															-
															(MAX(CASE WHEN REPLACE(REPLACE(REPLACE(o2.CONTINUOUS, 'F', ''), 'S', ''), 'E', '')  =  RIGHT(o2.CONTINUOUS, 2) ---when both start and finish are from the same start and finish (e.g. S01 & F01, or S04 & F04)
																		AND LEFT(o.CONTINUOUS, 1) = 'S' ---we want the number of the finish  
																	THEN ISNULL(o.DISTFROMUP, ISNULL(o.DISTFROMDOWN,0))
																END))
														)
														/ 5, 0) AS INT), 0)
			  FROM #UpdatedSTOBSERVATION (nolock) o
			  LEFT JOIN #UpdatedSTOBSERVATION (nolock) o2 ON o.TVID = o2.TVID AND REPLACE(REPLACE(REPLACE(o2.CONTINUOUS, 'F', ''), 'S', ''), 'E', '')  = RIGHT(o2.CONTINUOUS, 2) 
			  INNER JOIN #OperationalSecondHighestScore3 nos ON o.TVID = nos.TVID AND o.[OBSERVDESCSCORE] = nos.OM3_SecondHighestObservDescScore ---only pull data in to the result set that applies to the #1 set above
			  WHERE o.CAUSE = 'O' ---just the structural pieces
			  AND o.CONTINUOUS IS NOT NULL ---just those continuous elements
			  --AND o.TVID in (181, 569, 689) 
			  
			  GROUP BY o.[TVID]
					,RIGHT(o2.CONTINUOUS, 2)
			 )x;
	CREATE INDEX IX_1 on #OperationalSecondHighestScoreCount_Continuous (TVID); --placing an index on this table, so that the subsequent query will run faster 
			-------------------------------------------------------------------------
			----counting the NON-continuous defects
IF OBJECT_ID('tempdb..#OperationalSecondHighestScoreCount_NONContinuous') IS NOT NULL  DROP TABLE #OperationalSecondHighestScoreCount_NONContinuous;
	SELECT	* 
	INTO 	#OperationalSecondHighestScoreCount_NONContinuous 
	FROM
			(
			  SELECT o.TVID
					,'CountOfNONContinuouseDefects' = COUNT(o.OBSERVDESCSCORE)
			  FROM #UpdatedSTOBSERVATION (nolock) o
			  INNER JOIN #OperationalSecondHighestScore3 nos ON o.TVID = nos.TVID AND o.[OBSERVDESCSCORE] = nos.OM3_SecondHighestObservDescScore ---only pull data in for the desired score  
			  WHERE o.CAUSE = 'O' ---just the structural pieces
				AND o.CONTINUOUS IS NULL ---just those NON-continuous elements
				--AND o.TVID in (569) 
			  GROUP BY o.TVID 
			 )x;
	CREATE INDEX IX_1 on #OperationalSecondHighestScoreCount_NONContinuous (TVID); --placing an index on this table, so that the subsequent query will run faster 
			-------------------------------------------------------------------------
			----total defects
IF OBJECT_ID('tempdb..#OperationalSecondHighestScoreCount2') IS NOT NULL  DROP TABLE #OperationalSecondHighestScoreCount2;
	SELECT	* 
	INTO 	#OperationalSecondHighestScoreCount2 
	FROM
			(
				SELECT hs.TVID
					, hs.OM3_SecondHighestObservDescScore
					,'OM4_CountSecondHighestObservDescScore' = ISNULL(c.RoundedNumberOfContinuousDefects, 0)
													   + ISNULL(nc.CountOfNONContinuouseDefects, 0) 
				FROM #OperationalSecondHighestScore3 hs
				LEFT JOIN #OperationalSecondHighestScoreCount_Continuous c ON hs.TVID = c.TVID
				LEFT JOIN #OperationalSecondHighestScoreCount_NONContinuous nc ON hs.TVID = nc.TVID
			)x;
	CREATE INDEX IX_1 on #OperationalSecondHighestScoreCount2 (TVID); --placing an index on this table, so that the subsequent query will run faster 

IF OBJECT_ID('tempdb..#OperationalSecondHighestScorePlusAlpha') IS NOT NULL  DROP TABLE #OperationalSecondHighestScorePlusAlpha;
	SELECT	* 
	INTO 	#OperationalSecondHighestScorePlusAlpha 
	FROM
		  (
			---adding in the alpha component.  meaning, if the count is greater than 9, then it turns into an alpha
			---see IT_CoS.lkup.PACPNumberOfDefects for the correlation between the number of defects and the alpha representative
			SELECT nts.TVID
				  ,nts.[OM3_SecondHighestObservDescScore]
				  ,nts.[OM4_CountSecondHighestObservDescScore]
				  ,'OM4_CountSecondHighest_AlphaRepresentative' = CASE WHEN alpha.NumberOfDefects IS NULL ---- meaning the number of defects is less than 10
																THEN ''
																ELSE alpha.CorrespondingAlpha
																END
					
			FROM #OperationalSecondHighestScoreCount2 nts
			LEFT JOIN [IT_CoS].[lkup].[PACPNumberOfDefects] (nolock) alpha ON nts.[OM4_CountSecondHighestObservDescScore] = alpha.[NumberOfDefects]
			)x;
	CREATE INDEX IX_1 on #OperationalSecondHighestScorePlusAlpha (TVID); --placing an index on this table, so that the subsequent query will run faster 
			
			/* 3 - third highest score */
			
IF OBJECT_ID('tempdb..#OperationalThirdHighestScore1') IS NOT NULL  DROP TABLE #OperationalThirdHighestScore1;
	SELECT	* 
	INTO 	#OperationalThirdHighestScore1 
	FROM
			(
			  ---Operational. 3rd digit of QSR ... Third highest score for the given inspection on that asset 
			  SELECT DISTINCT [TVID]
					,'OBSERVDESCSCORE' = (CASE WHEN [OBSERVDESCSCORE] <> 0
												THEN [OBSERVDESCSCORE]
												END)			
			  FROM #UpdatedSTOBSERVATION (nolock)
			  WHERE CAUSE = 'O' 
			  --AND [OBSERVDESCSCORE] <> 0
			  AND [OBSERVDESCSCORE] IS NOT NULL
			  --AND TVID in (181, 569,10)
			  )x;
	CREATE INDEX IX_1 on #OperationalThirdHighestScore1 (TVID); --placing an index on this table, so that the subsequent query will run faster 

IF OBJECT_ID('tempdb..#OperationalThirdHighestScore2') IS NOT NULL  DROP TABLE #OperationalThirdHighestScore2;
	SELECT	* 
	INTO 	#OperationalThirdHighestScore2 
	FROM
			(
			  ---Operational. 3rd digit of QSR ... Third highest score for the given inspection on that asset 
			  SELECT [TVID]
					,OBSERVDESCSCORE
					,'OM3_RowNumbers' = ROW_NUMBER() OVER(PARTITION BY [TVID] ORDER BY OBSERVDESCSCORE DESC)			
			  FROM #OperationalThirdHighestScore1 
			  )x;
	CREATE INDEX IX_1 on #OperationalThirdHighestScore2 (TVID); --placing an index on this table, so that the subsequent query will run faster 

IF OBJECT_ID('tempdb..#OperationalThirdHighestScore3') IS NOT NULL  DROP TABLE #OperationalThirdHighestScore3;
	SELECT	* 
	INTO 	#OperationalThirdHighestScore3 
	FROM
			(
			  ---Operational. 3rd digit of QSR ... Third highest score for the given inspection on that asset 
			  SELECT [TVID] 
					,'OM3_ThirdHighestObservDescScore' = OBSERVDESCSCORE			
			  FROM #OperationalThirdHighestScore2 
			  WHERE [OM3_RowNumbers] = 3
			  )x;
	CREATE INDEX IX_1 on #OperationalThirdHighestScore3 (TVID); --placing an index on this table, so that the subsequent query will run faster 

IF OBJECT_ID('tempdb..#OperationalThirdHighestScoreCount_Continuous') IS NOT NULL  DROP TABLE #OperationalThirdHighestScoreCount_Continuous;
	SELECT	* 
	INTO 	#OperationalThirdHighestScoreCount_Continuous 
	FROM
		  (
			  
			  SELECT o.[TVID]
					,'RoundedNumberOfContinuousDefects' = ISNULL(CAST(ROUND(
														(
															(MAX(CASE WHEN REPLACE(REPLACE(REPLACE(o2.CONTINUOUS, 'F', ''), 'S', ''), 'E', '')  =  RIGHT(o2.CONTINUOUS, 2) ---when both start and finish are from the same start and finish (e.g. S01 & F01, or S04 & F04)
																			AND LEFT(o.CONTINUOUS, 1) = 'F' ---we want the number of the start  
																		THEN ISNULL(o.DISTFROMUP, o.DISTFROMDOWN)
																	END))
															-
															(MAX(CASE WHEN REPLACE(REPLACE(REPLACE(o2.CONTINUOUS, 'F', ''), 'S', ''), 'E', '')  =  RIGHT(o2.CONTINUOUS, 2) ---when both start and finish are from the same start and finish (e.g. S01 & F01, or S04 & F04)
																		AND LEFT(o.CONTINUOUS, 1) = 'S' ---we want the number of the finish  
																	THEN ISNULL(o.DISTFROMUP, o.DISTFROMDOWN)
																END))
														)
														/ 5, 0) AS INT), 0)
			  FROM #UpdatedSTOBSERVATION (nolock) o
			  LEFT JOIN #UpdatedSTOBSERVATION (nolock) o2 ON o.TVID = o2.TVID AND REPLACE(REPLACE(REPLACE(o2.CONTINUOUS, 'F', ''), 'S', ''), 'E', '')  = RIGHT(o2.CONTINUOUS, 2) 
			  INNER JOIN #OperationalThirdHighestScore3 nos ON o.TVID = nos.TVID AND o.[OBSERVDESCSCORE] = nos.OM3_ThirdHighestObservDescScore ---only pull data in to the result set that applies to the #1 set above
			  WHERE o.CAUSE = 'O' ---just the structural pieces
			  AND o.CONTINUOUS IS NOT NULL ---just those continuous elements
			  --AND o.TVID in (181, 569, 689) 
			  
			  GROUP BY o.[TVID]
					,RIGHT(o2.CONTINUOUS, 2)
			)x;
	CREATE INDEX IX_1 on #OperationalThirdHighestScoreCount_Continuous (TVID); --placing an index on this table, so that the subsequent query will run faster
			-------------------------------------------------------------------------
			----counting the NON-continuous defects
IF OBJECT_ID('tempdb..#OperationalThirdHighestScoreCount_NONContinuous') IS NOT NULL  DROP TABLE #OperationalThirdHighestScoreCount_NONContinuous;
	SELECT	* 
	INTO 	#OperationalThirdHighestScoreCount_NONContinuous 
	FROM
			(
			  SELECT o.TVID
					,'CountOfNONContinuouseDefects' = COUNT(o.OBSERVDESCSCORE)
			  FROM #UpdatedSTOBSERVATION (nolock) o
			  INNER JOIN #OperationalThirdHighestScore3 nos ON o.TVID = nos.TVID AND o.[OBSERVDESCSCORE] = nos.OM3_ThirdHighestObservDescScore ---only pull data in for the desired score  
			  WHERE o.CAUSE = 'O' ---just the structural pieces
				AND o.CONTINUOUS IS NULL ---just those NON-continuous elements
				--AND o.TVID in (569) 
			  GROUP BY o.TVID 
			)x;
	CREATE INDEX IX_1 on #OperationalThirdHighestScoreCount_NONContinuous (TVID); --placing an index on this table, so that the subsequent query will run faster
			-------------------------------------------------------------------------
			----total defects
IF OBJECT_ID('tempdb..#OperationalThirdHighestScoreCount2') IS NOT NULL  DROP TABLE #OperationalThirdHighestScoreCount2;
	SELECT	* 
	INTO 	#OperationalThirdHighestScoreCount2 
	FROM
			(
				SELECT hs.TVID
					, hs.OM3_ThirdHighestObservDescScore
					,'OM4_CountThirdHighestObservDescScore' = ISNULL(c.RoundedNumberOfContinuousDefects, 0)
														    + ISNULL(nc.CountOfNONContinuouseDefects, 0) 
				FROM #OperationalThirdHighestScore3 hs
				LEFT JOIN #OperationalThirdHighestScoreCount_Continuous c ON hs.TVID = c.TVID
				LEFT JOIN #OperationalThirdHighestScoreCount_NONContinuous nc ON hs.TVID = nc.TVID

				--where ha.tvid = 569
			)x;
	CREATE INDEX IX_1 on #OperationalThirdHighestScoreCount2 (TVID); --placing an index on this table, so that the subsequent query will run faster
			
		  	/* 4 - fourth highest score */ 

IF OBJECT_ID('tempdb..#OperationalFourthHighestScore1') IS NOT NULL  DROP TABLE #OperationalFourthHighestScore1;
	SELECT	* 
	INTO 	#OperationalFourthHighestScore1 
	FROM
			(
			  ---Operational. 3rd digit of QSR ... Fourth highest score for the given inspection on that asset 
			  SELECT DISTINCT [TVID]
					,'OBSERVDESCSCORE' = (CASE WHEN [OBSERVDESCSCORE] <> 0
												THEN [OBSERVDESCSCORE]
												END)			
			  FROM #UpdatedSTOBSERVATION (nolock)
			  WHERE CAUSE = 'O' 
			  --AND [OBSERVDESCSCORE] <> 0
			  AND [OBSERVDESCSCORE] IS NOT NULL
			  --AND TVID in (181, 569,10)
			  )x;
	CREATE INDEX IX_1 on #OperationalFourthHighestScore1 (TVID); --placing an index on this table, so that the subsequent query will run faster

IF OBJECT_ID('tempdb..#OperationalFourthHighestScore2') IS NOT NULL  DROP TABLE #OperationalFourthHighestScore2;
	SELECT	* 
	INTO 	#OperationalFourthHighestScore2 
	FROM
			(
			  ---Operational. 3rd digit of QSR ... Fourth highest score for the given inspection on that asset 
			  SELECT [TVID]
					,OBSERVDESCSCORE
					,'OM3_RowNumbers' = ROW_NUMBER() OVER(PARTITION BY [TVID] ORDER BY OBSERVDESCSCORE DESC)			
			  FROM #OperationalFourthHighestScore1 
			  )x;
	CREATE INDEX IX_1 on #OperationalFourthHighestScore2 (TVID); --placing an index on this table, so that the subsequent query will run faster

IF OBJECT_ID('tempdb..#OperationalFourthHighestScore3') IS NOT NULL  DROP TABLE #OperationalFourthHighestScore3;
	SELECT	* 
	INTO 	#OperationalFourthHighestScore3 
	FROM
			(
			  ---Operational. 3rd digit of QSR ... Fourth highest score for the given inspection on that asset 
			  SELECT [TVID] 
					,'OM3_FourthHighestObservDescScore' = OBSERVDESCSCORE			
			  FROM #OperationalFourthHighestScore2 
			  WHERE [OM3_RowNumbers] = 4
			   )x;
	CREATE INDEX IX_1 on #OperationalFourthHighestScore3 (TVID); --placing an index on this table, so that the subsequent query will run faster
		  	
IF OBJECT_ID('tempdb..#OperationalFourthHighestScoreCount_Continuous') IS NOT NULL  DROP TABLE #OperationalFourthHighestScoreCount_Continuous;
	SELECT	* 
	INTO 	#OperationalFourthHighestScoreCount_Continuous 
	FROM
		  (
			  
			  SELECT o.[TVID]
					,'RoundedNumberOfContinuousDefects' = ISNULL(CAST(ROUND(
														(
															(MAX(CASE WHEN REPLACE(REPLACE(REPLACE(o2.CONTINUOUS, 'F', ''), 'S', ''), 'E', '')  =  RIGHT(o2.CONTINUOUS, 2) ---when both start and finish are from the same start and finish (e.g. S01 & F01, or S04 & F04)
																			AND LEFT(o.CONTINUOUS, 1) = 'F' ---we want the number of the start  
																		THEN ISNULL(o.DISTFROMUP, o.DISTFROMDOWN)
																	END))
															-
															(MAX(CASE WHEN REPLACE(REPLACE(REPLACE(o2.CONTINUOUS, 'F', ''), 'S', ''), 'E', '')  =  RIGHT(o2.CONTINUOUS, 2) ---when both start and finish are from the same start and finish (e.g. S01 & F01, or S04 & F04)
																		AND LEFT(o.CONTINUOUS, 1) = 'S' ---we want the number of the finish  
																	THEN ISNULL(o.DISTFROMUP, o.DISTFROMDOWN)
																END))
														)
														/ 5, 0) AS INT), 0)
			  FROM #UpdatedSTOBSERVATION (nolock) o
			  LEFT JOIN #UpdatedSTOBSERVATION (nolock) o2 ON o.TVID = o2.TVID AND REPLACE(REPLACE(REPLACE(o2.CONTINUOUS, 'F', ''), 'S', ''), 'E', '')  = RIGHT(o2.CONTINUOUS, 2) 
			  INNER JOIN #OperationalFourthHighestScore3 nos ON o.TVID = nos.TVID AND o.[OBSERVDESCSCORE] = nos.OM3_FourthHighestObservDescScore ---only pull data in to the result set that applies to the #1 set above
			  WHERE o.CAUSE = 'O' ---just the structural pieces
			  AND o.CONTINUOUS IS NOT NULL ---just those continuous elements
			  --AND o.TVID in (181, 569, 689) 
			  
			  GROUP BY o.[TVID]
					,RIGHT(o2.CONTINUOUS, 2)
			)x;
	CREATE INDEX IX_1 on #OperationalFourthHighestScoreCount_Continuous (TVID); --placing an index on this table, so that the subsequent query will run faster
			-------------------------------------------------------------------------
			----counting the NON-continuous defects
IF OBJECT_ID('tempdb..#OperationalFourthHighestScoreCount_NONContinuous') IS NOT NULL  DROP TABLE #OperationalFourthHighestScoreCount_NONContinuous;
	SELECT	* 
	INTO 	#OperationalFourthHighestScoreCount_NONContinuous 
	FROM
			(
			  SELECT o.TVID
					,'CountOfNONContinuouseDefects' = COUNT(o.OBSERVDESCSCORE)
			  FROM #UpdatedSTOBSERVATION (nolock) o
			  INNER JOIN #OperationalFourthHighestScore3 nos ON o.TVID = nos.TVID AND o.[OBSERVDESCSCORE] = nos.OM3_FourthHighestObservDescScore ---only pull data in for the desired score  
			  WHERE o.CAUSE = 'O' ---just the structural pieces
				AND o.CONTINUOUS IS NULL ---just those NON-continuous elements
				--AND o.TVID in (569) 
			  GROUP BY o.TVID 
			)x;
	CREATE INDEX IX_1 on #OperationalFourthHighestScoreCount_NONContinuous (TVID); --placing an index on this table, so that the subsequent query will run faster
			-------------------------------------------------------------------------
			----total defects
IF OBJECT_ID('tempdb..#OperationalFourthHighestScoreCount2') IS NOT NULL  DROP TABLE #OperationalFourthHighestScoreCount2;
	SELECT	* 
	INTO 	#OperationalFourthHighestScoreCount2 
	FROM
			(
		  
			  SELECT hs.[TVID]
					,hs.[OM3_FourthHighestObservDescScore]
					,'OM4_CountFourthHighestObservDescScore' =  ISNULL(c.RoundedNumberOfContinuousDefects, 0)
															  + ISNULL(nc.CountOfNONContinuouseDefects, 0) 

			  FROM #OperationalFourthHighestScore3 hs			  
			  LEFT JOIN #OperationalHighestScoreCount_Continuous c ON hs.TVID = c.TVID
			  LEFT JOIN #OperationalHighestScoreCount_NONContinuous nc ON hs.TVID = nc.TVID

		  )x;
	CREATE INDEX IX_1 on #OperationalFourthHighestScoreCount2 (TVID); --placing an index on this table, so that the subsequent query will run faster		
		  		  			
			/* 5 - fifth highest score */ 

IF OBJECT_ID('tempdb..#OperationalFifthHighestScore1') IS NOT NULL  DROP TABLE #OperationalFifthHighestScore1;
	SELECT	* 
	INTO 	#OperationalFifthHighestScore1 
	FROM
			(
			  ---Operational. 3rd digit of QSR ... Fifth highest score for the given inspection on that asset 
			  SELECT DISTINCT [TVID]
					,'OBSERVDESCSCORE' = (CASE WHEN [OBSERVDESCSCORE] <> 0
											THEN [OBSERVDESCSCORE]
											END)		
			  FROM #UpdatedSTOBSERVATION (nolock)
			  WHERE CAUSE = 'O' 
			  --AND [OBSERVDESCSCORE] <> 0
			  AND [OBSERVDESCSCORE] IS NOT NULL
			  --AND TVID in (181, 569,10)
			  )x;
	CREATE INDEX IX_1 on #OperationalFifthHighestScore1 (TVID); --placing an index on this table, so that the subsequent query will run faster		

IF OBJECT_ID('tempdb..#OperationalFifthHighestScore2') IS NOT NULL  DROP TABLE #OperationalFifthHighestScore2;
	SELECT	* 
	INTO 	#OperationalFifthHighestScore2 
	FROM
			(
			  ---Operational. 3rd digit of QSR ... Fifth highest score for the given inspection on that asset 
			  SELECT [TVID]
					,OBSERVDESCSCORE
					,'OM3_RowNumbers' = ROW_NUMBER() OVER(PARTITION BY [TVID] ORDER BY OBSERVDESCSCORE DESC)			
			  FROM #OperationalFifthHighestScore1 
			   )x;
	CREATE INDEX IX_1 on #OperationalFifthHighestScore2 (TVID); --placing an index on this table, so that the subsequent query will run faster	

IF OBJECT_ID('tempdb..#OperationalFifthHighestScore3') IS NOT NULL  DROP TABLE #OperationalFifthHighestScore3;
	SELECT	* 
	INTO 	#OperationalFifthHighestScore3 
	FROM
			(
			  ---Operational. 3rd digit of QSR ... Fifth highest score for the given inspection on that asset 
			  SELECT [TVID] 
					,'OM3_FifthHighestObservDescScore' = OBSERVDESCSCORE			
			  FROM #OperationalFifthHighestScore2 
			  WHERE [OM3_RowNumbers] = 5
			   )x;
	CREATE INDEX IX_1 on #OperationalFifthHighestScore3 (TVID); --placing an index on this table, so that the subsequent query will run faster

IF OBJECT_ID('tempdb..#OperationalFifthHighestScoreCount_Continuous') IS NOT NULL  DROP TABLE #OperationalFifthHighestScoreCount_Continuous;
	SELECT	* 
	INTO 	#OperationalFifthHighestScoreCount_Continuous 
	FROM
		  (
			  ---structural. second digit of QSR... count of how many #1's.  
			  SELECT o.[TVID]
					,'RoundedNumberOfContinuousDefects' = ISNULL(CAST(ROUND(
														(
															(MAX(CASE WHEN REPLACE(REPLACE(REPLACE(o2.CONTINUOUS, 'F', ''), 'S', ''), 'E', '')  =  RIGHT(o2.CONTINUOUS, 2) ---when both start and finish are from the same start and finish (e.g. S01 & F01, or S04 & F04)
																			AND LEFT(o.CONTINUOUS, 1) = 'F' ---we want the number of the start  
																		THEN ISNULL(o.DISTFROMUP, o.DISTFROMDOWN)
																	END))
															-
															(MAX(CASE WHEN REPLACE(REPLACE(REPLACE(o2.CONTINUOUS, 'F', ''), 'S', ''), 'E', '')  =  RIGHT(o2.CONTINUOUS, 2) ---when both start and finish are from the same start and finish (e.g. S01 & F01, or S04 & F04)
																		AND LEFT(o.CONTINUOUS, 1) = 'S' ---we want the number of the finish  
																	THEN ISNULL(o.DISTFROMUP, o.DISTFROMDOWN)
																END))
														)
														/ 5, 0) AS INT), 0)
			  FROM #UpdatedSTOBSERVATION (nolock) o
			  LEFT JOIN #UpdatedSTOBSERVATION (nolock) o2 ON o.TVID = o2.TVID AND REPLACE(REPLACE(REPLACE(o2.CONTINUOUS, 'F', ''), 'S', ''), 'E', '')  = RIGHT(o2.CONTINUOUS, 2) 
			  INNER JOIN #OperationalFifthHighestScore3 nos ON o.TVID = nos.TVID AND o.[OBSERVDESCSCORE] = nos.OM3_FifthHighestObservDescScore ---only pull data in to the result set that applies to the #1 set above
			  WHERE o.CAUSE = 'O' ---just the structural pieces
			  AND o.CONTINUOUS IS NOT NULL ---just those continuous elements
			  --AND o.TVID in (181, 569, 689) 
			  
			  GROUP BY o.[TVID]
					,RIGHT(o2.CONTINUOUS, 2)
			 )x;
	CREATE INDEX IX_1 on #OperationalFifthHighestScoreCount_Continuous (TVID); --placing an index on this table, so that the subsequent query will run faster
			-------------------------------------------------------------------------
			----counting the NON-continuous defects
IF OBJECT_ID('tempdb..#OperationalFifthHighestScoreCount_NONContinuous') IS NOT NULL  DROP TABLE #OperationalFifthHighestScoreCount_NONContinuous;
	SELECT	* 
	INTO 	#OperationalFifthHighestScoreCount_NONContinuous 
	FROM
			(
			  SELECT o.TVID
					,'CountOfNONContinuouseDefects' = COUNT(o.OBSERVDESCSCORE)
			  FROM #UpdatedSTOBSERVATION (nolock) o
			  INNER JOIN #OperationalFifthHighestScore3 nos ON o.TVID = nos.TVID AND o.[OBSERVDESCSCORE] = nos.OM3_FifthHighestObservDescScore ---only pull data in for the desired score  
			  WHERE o.CAUSE = 'O' ---just the structural pieces
				AND o.CONTINUOUS IS NULL ---just those NON-continuous elements
				--AND o.TVID in (569) 
			  GROUP BY o.TVID 
			)x;
	CREATE INDEX IX_1 on #OperationalFifthHighestScoreCount_NONContinuous (TVID); --placing an index on this table, so that the subsequent query will run faster
			-------------------------------------------------------------------------
			----total defects
IF OBJECT_ID('tempdb..#OperationalFifthHighestScoreCount2') IS NOT NULL  DROP TABLE #OperationalFifthHighestScoreCount2;
	SELECT	* 
	INTO 	#OperationalFifthHighestScoreCount2 
	FROM
			(
		  
			  SELECT hs.[TVID]
					,hs.OM3_FifthHighestObservDescScore
					,'OM4_CountFifthHighestObservDescScore' = ISNULL(c.RoundedNumberOfContinuousDefects, 0)
															+ ISNULL(nc.CountOfNONContinuouseDefects, 0) 

			  FROM #OperationalFifthHighestScore3 hs 
			  LEFT JOIN #OperationalFifthHighestScoreCount_Continuous c ON hs.TVID = c.TVID
			  LEFT JOIN #OperationalFifthHighestScoreCount_NONContinuous nc ON hs.TVID = nc.TVID
		  )x;
	CREATE INDEX IX_1 on #OperationalFifthHighestScoreCount2 (TVID); --placing an index on this table, so that the subsequent query will run faster	
		  
		  -------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#OperationalQMR') IS NOT NULL  DROP TABLE #OperationalQMR;
	SELECT	* 
	INTO 	#OperationalQMR 
	FROM
		  (
			  SELECT DISTINCT
					 a.TVID
					 ,'QMR' = CAST(ISNULL(CAST(a.OM1_HighestObservDescScore AS VARCHAR(1)) , '') AS VARCHAR(10))
							+ CAST(ISNULL(CASE WHEN a.OM2_CountHighestObservDescScore > 9
												THEN a.OM2_CountHighest_AlphaRepresentative
												ELSE CAST(a.OM2_CountHighestObservDescScore AS VARCHAR(10))
												END , '') AS VARCHAR(10))
							+ CAST(ISNULL(CAST(b.OM3_SecondHighestObservDescScore AS VARCHAR(1)), '0') AS VARCHAR(10))
							+ CAST(ISNULL(CASE WHEN b.OM4_CountSecondHighestObservDescScore > 9
												THEN b.OM4_CountSecondHighest_AlphaRepresentative
												ELSE CAST(b.OM4_CountSecondHighestObservDescScore AS VARCHAR(10))
												END, '0') AS VARCHAR(10))

			  FROM #OperationalHighestScorePlusAlpha a
			  LEFT JOIN #OperationalSecondHighestScorePlusAlpha b ON a.TVID = b.TVID 

		  )x;
	CREATE INDEX IX_1 on #OperationalQMR (TVID); --placing an index on this table, so that the subsequent query will run faster	

IF OBJECT_ID('tempdb..#OperationalMPR') IS NOT NULL  DROP TABLE #OperationalMPR;
	SELECT	* 
	INTO 	#OperationalMPR 
	FROM
		  (
			SELECT DISTINCT 
				  h.TVID, 
				  'MPR' = ISNULL((h.OM1_HighestObservDescScore * hc.OM2_CountHighestObservDescScore), 0)
						+ ISNULL((sh.OM3_SecondHighestObservDescScore * shc.OM4_CountSecondHighestObservDescScore), 0)
						+ ISNULL((th.OM3_ThirdHighestObservDescScore * thc.OM4_CountThirdHighestObservDescScore), 0)
						+ ISNULL((fh.OM3_FourthHighestObservDescScore * fhc.OM4_CountFourthHighestObservDescScore ), 0)
						+ ISNULL((f5h.OM3_FifthHighestObservDescScore * f5hc.OM4_CountFifthHighestObservDescScore), 0)
				
			FROM #OperationalHighestScore h
			LEFT JOIN #OperationalHighestScoreCount2 hc			ON h.TVID = hc.TVID
			LEFT JOIN #OperationalSecondHighestScore3 sh			ON h.TVID = sh.TVID
			LEFT JOIN #OperationalSecondHighestScoreCount2 shc	ON h.TVID = shc.TVID
			LEFT JOIN #OperationalThirdHighestScore3 th			ON h.TVID = th.TVID
			LEFT JOIN #OperationalThirdHighestScoreCount2 thc	ON h.TVID = thc.TVID
			LEFT JOIN #OperationalFourthHighestScore3 fh			ON h.TVID = fh.TVID
			LEFT JOIN #OperationalFourthHighestScoreCount2 fhc	ON h.TVID = fhc.TVID 
			LEFT JOIN #OperationalFifthHighestScore3 f5h			ON h.TVID = f5h.TVID
			LEFT JOIN #OperationalFifthHighestScoreCount2 f5hc	ON h.TVID = f5hc.TVID
			
			--where h.TVID = 181
		  )x;
	CREATE INDEX IX_1 on #OperationalMPR (TVID); --placing an index on this table, so that the subsequent query will run faster	

IF OBJECT_ID('tempdb..#OperationalMPRI') IS NOT NULL  DROP TABLE #OperationalMPRI;
	SELECT	* 
	INTO 	#OperationalMPRI 
	FROM
		  (
			SELECT DISTINCT 
				  mpr.TVID,
				 'MPRI' = CASE WHEN	( ISNULL(hc.OM2_CountHighestObservDescScore , 0)
									+ ISNULL(shc.OM4_CountSecondHighestObservDescScore , 0)
									+ ISNULL(thc.OM4_CountThirdHighestObservDescScore , 0)
									+ ISNULL(fhc.OM4_CountFourthHighestObservDescScore , 0)
									+ ISNULL(f5hc.OM4_CountFifthHighestObservDescScore , 0)
									) = 0
								THEN 0
								ELSE mpr.MPR / ( ISNULL(hc.OM2_CountHighestObservDescScore , 0)
												+ ISNULL(shc.OM4_CountSecondHighestObservDescScore , 0)
												+ ISNULL(thc.OM4_CountThirdHighestObservDescScore , 0)
												+ ISNULL(fhc.OM4_CountFourthHighestObservDescScore , 0)
												+ ISNULL(f5hc.OM4_CountFifthHighestObservDescScore , 0)
												) 
								END,
								--hc.OM2_CountHighestObservDescScore,
								--shc.OM4_CountSecondHighestObservDescScore,
								--thc.OM4_CountThirdHighestObservDescScore,
								--fhc.OM4_CountFourthHighestObservDescScore,
								--f5hc.OM4_CountFifthHighestObservDescScore,
				 'OperationalDefects' = ( ISNULL(hc.OM2_CountHighestObservDescScore , 0)
										+ ISNULL(shc.OM4_CountSecondHighestObservDescScore , 0)
										+ ISNULL(thc.OM4_CountThirdHighestObservDescScore , 0)
										+ ISNULL(fhc.OM4_CountFourthHighestObservDescScore , 0)
										+ ISNULL(f5hc.OM4_CountFifthHighestObservDescScore , 0)
										)

			FROM #OperationalMPR mpr
			LEFT JOIN #OperationalHighestScoreCount2 hc			ON mpr.TVID = hc.TVID
			LEFT JOIN #OperationalSecondHighestScoreCount2 shc	ON mpr.TVID = shc.TVID
			LEFT JOIN #OperationalThirdHighestScoreCount2 thc	ON mpr.TVID = thc.TVID
			LEFT JOIN #OperationalFourthHighestScoreCount2 fhc	ON mpr.TVID = fhc.TVID 
			LEFT JOIN #OperationalFifthHighestScoreCount2 f5hc	ON mpr.TVID = f5hc.TVID 

			--where mpr.TVID = 181

		 )x;
	CREATE INDEX IX_1 on #OperationalMPRI (TVID); --placing an index on this table, so that the subsequent query will run faster	



	-----------COMPILE 
IF OBJECT_ID('tempdb..#CompileRatings') IS NOT NULL  DROP TABLE #CompileRatings;
	SELECT	* 
	INTO 	#CompileRatings 
	FROM
	(
		SELECT  
				'TVID' = CASE WHEN qsr.TVID IS NOT NULL	
								THEN qsr.TVID
								ELSE qmr.TVID
								END
				--------structural
				, 'QSR' = ISNULL(qsr.QSR, 0)
				, 'SPR' = ISNULL(spr.SPR, 0)
				, 'SPRI' = ISNULL(spri.SPRI, 0)
				------operational
				, 'QMR' = ISNULL(qmr.QMR, 0)
				, 'MPR' = ISNULL(mpr.MPR, 0)
				, 'MPRI' = ISNULL(mpri.MPRI, 0)
				------structural + operational
				,'OPR' = ISNULL(spr.SPR, 0) + ISNULL(mpr.MPR, 0) 
				,'OPRI' = CASE WHEN (ISNULL(StructuralDefects, 0) +  ISNULL(mpri.OperationalDefects, 0)) = 0
								THEN 0
								ELSE (ISNULL(spr.SPR, 0) + ISNULL(mpr.MPR, 0))
										/ 
									 (ISNULL(StructuralDefects, 0) +  ISNULL(mpri.OperationalDefects, 0)) 
								END

		FROM #StructuralQSR qsr
		LEFT JOIN #StructuralSPR spr		ON qsr.TVID = spr.TVID
		LEFT JOIN #StructuralSPRI spri		ON qsr.TVID = spri.TVID
		FULL OUTER JOIN #OperationalQMR qmr	ON qsr.TVID = qmr.TVID ----doing a full outer join, just in case there isn't any structural things for a given asset/inspection 
		LEFT JOIN #OperationalMPR mpr		ON qmr.TVID = mpr.TVID ---connecting to the first operational table
		LEFT JOIN #OperationalMPRI mpri		ON qmr.TVID = mpri.TVID
	
		----1328 in 

		--where qsr.TVID IN ( 181, 569, 1081) 
	 )x;
	CREATE INDEX IX_1 on #CompileRatings (TVID); --placing an index on this table, so that the subsequent query will run faster


IF OBJECT_ID('tempdb..#WO_Comments') IS NOT NULL  DROP TABLE #WO_Comments;

SELECT	*  INTO	#WO_Comments FROM
(
	SELECT r1.WORKORDERID
		, 'Comments' = REPLACE(
								SUBSTRING((SELECT ' ' + [COMMENTS] + ' ' 
								FROM CWProd.[Azteca].[WORKORDERCOMMENT] (nolock) r
					
								WHERE r.WORKORDERID = r1.WORKORDERID 
					
								ORDER BY DATECREATED
								FOR XML PATH ('')), 2, 2000000)
								, '&#x0D;', '')

	FROM CWProd.[Azteca].[WORKORDERCOMMENT] (nolock) r1
	GROUP BY r1.WORKORDERID
) x;

--------------------------------------------------------------------------------
----Go get the Custom Field information for "CONDITION ASSESSMENT" Work Order 

EXEC [CW].[sp_CustomFieldResults] @Description = 'CONDITION ASSESSMENT'

--------------------------------------------------------------------------------

IF OBJECT_ID('tempdb..#ProblemSummary') IS NOT NULL  DROP TABLE #ProblemSummary;

SELECT	*  INTO	#ProblemSummary FROM
(
		SELECT sto1.TVID
				, 'ProblemSummary' = REPLACE(SUBSTRING((SELECT
															  ISNULL(sto.OBSERV_TYPE, '')
															+ ' '
															+ ISNULL(sto.OBSERVDESC, '')
															+ ' '
															+ CASE WHEN sto.VALUEPERCENT > 0
																	THEN CAST(sto.VALUEPERCENT AS VARCHAR(6)) + '%'
																	ELSE ''
																	END
															+ ' '
															+ ISNULL(sto.OBSERVREMARKS, '')
															+ CHAR(10) 
														FROM CWProd.Azteca.STVOBSERVATION (nolock) sto
														WHERE sto.TVID = sto1.TVID
														AND sto.OBSERVDESCSCORE > 0
														ORDER BY sto.OBSERVATIONID
														FOR XML PATH ('')), 1, 2000000)
														, '&#x0D;', '')
		FROM CWProd.Azteca.STVOBSERVATION (nolock) sto1
		GROUP BY TVID

) x;

IF OBJECT_ID('tempdb..#CriticalityScores') IS NOT NULL  DROP TABLE #CriticalityScores;

SELECT	*  INTO	#CriticalityScores FROM ----want to pull the most recent scores for any given asset

(		SELECT DISTINCT  c.*
		FROM GIS.SWPipeCriticalityScores (nolock) c
		INNER JOIN (SELECT c.AssetID
						 ,'MostRecent' = MAX(c.UpdatedDate)
					FROM GIS.SWPipeCriticalityScores (nolock) c
					GROUP BY c.AssetID)								mr ON c.AssetID = mr.AssetID
																	  AND c.UpdatedDate = mr.MostRecent

)x;

	/* Inspect PACP info + Conditional Assessment info + GIS Criticality Tool info */ 

	SELECT DISTINCT 
		  'PACP_WorkOrderID' = CAST(tv.WORKORDERID as INT)
		, 'TVID' = tv.TVID
		, 'AssetID' = tv.PIPE_ID
		, 'QSR' = cr.QSR
		, 'QMR' = cr.QMR
		, 'SPR' = cr.SPR
		, 'MPR' = cr.MPR
		, 'OPR' = cr.OPR
		, 'SPRI' = cr.SPRI
		, 'MPRI' = cr.MPRI
		, 'OPRI' = cr.OPRI
		, 'Diam' = tv.DIAMETER
		, 'Material' = tv.MATERIAL
		, 'DateInspected' = tv.TVDATE
		, 'LengthInspected' = tv.TOTAL_LENGTH ---total tv length 	
		, 'GISPipeLength (Ft)' = tv.PIPE_LENGTH
		, 'PercentInspected' = ISNULL(tv.TOTAL_LENGTH, 0) / 
														(CASE WHEN tv.PIPE_LENGTH IS NULL
																THEN .00001
																WHEN tv.PIPE_LENGTH = 0
																THEN .00001
																ELSE tv.PIPE_LENGTH
																END)

		, 'ProblemSummary' = ps.ProblemSummary
		, 'FieldCrewNotes(WorkOrderComments)' = ISNULL(woc.Comments, '')
		, 'DrainageBasin' = tv.DRAINAGEAREA
		, 'Link' = tv.VIDEOLOCATION 
		--------------------------------------- WO details
		, 'ProjectName' = CASE WHEN wo3.ProjectName IS NULL 
								THEN 'No Project'
								WHEN wo3.ProjectName = ''
								THEN 'No Project'
								ELSE wo3.ProjectName
								END
		, 'MaintenanceZone' = wo3.MAPPAGE

		-------------------------------------- Conditional Assessment (CA) Work Order info
		, 'CA_WorkOrderID' = wo2.WORKORDERID
		, 'CA_ReviewedBy' = wo2.WORKCOMPLETEDBY
		, 'CA_DateInspected' = CAST(wo2.ACTUALFINISHDATE AS DATE)
		, 'CA_InspectionComplete' = r.[INSPECTION COMPLETE]
		, 'CA_UtilityCrossbore' = r.[UTILITY CROSSBORE]
		, 'CA_StormwaterConnections' = r.[STORMWATER CONNECTION(S)]
		, 'CA_MajorVoid' = r.[MAJOR VOID]
		, 'CA_CriticalityScore' = r.[CRITICALITY SCORE]
		, 'CA_StructuralConditionScore' = r.[STRUCTURAL CONDITION SCORE]
		, 'CA_StructuralPScore' = ISNULL(r.[STRUCTURAL PSCORE] , '')
		, 'CA_RehabilitationType' = r.[REHABILITATION TYPE]
		, 'CA_MaintenanceConditionScore' = r.[MAINTENANCE CONDITION SCORE] 
		, 'CA_MaintenancePScore' = ISNULL(r.[MAINTENANCE PSCORE], '')
		, 'CA_MaintenanceType' = r.[MAINTENANCE TYPE]
		, 'CA_NeedsFurtherEvaluation' = r.[NEEDS FURTHER EVALUATION]
		, 'CA_Explain' = r.[Explain]
		--------------------------------------Surface Water runs a criticality GIS tool once a year. ingest the file as CSV into [IT_CoS].[GIS].[SWPipeCriticalityScores]
		, 'GISTool_OwnedBy' = pcs.OwnedBy
		, 'GISTool_OperatedBy' = pcs.OperatedBy
		, 'GISTool_ArtWithin30BufferOfArterial' = pcs.ART
		, 'GISTool_CrossWithin5BufferOfRailroadOrPavement' = pcs.[CROSS]
		, 'GISTool_Diam' = pcs.Diam
		, 'GISTool_Slope23' = pcs.Slope
		, 'GISTool_FSEAreaWithin5BufferOfSlideErodeOrFlood' = pcs.FSEArea
		, 'GISTool_SFlowIntersectionOFStreamNoBuffer' = pcs.SFlow
		, 'GISTool_InfraCriticalInfrastructureParcelsWithin20Buffer' = pcs.Infra
		, 'GISTool_Misc1IfSlopeFSEAreaSFlowAndInfraAre1Max1' = pcs.Misc
		, 'GISTool_Criticality' = pcs.Crit

		
		



	FROM #CompileRatings cr
	LEFT JOIN CWProd.Azteca.STVINSPECTION (nolock) tv			ON cr.TVID			= tv.TVID
	LEFT JOIN #WO_Comments woc									ON tv.WORKORDERID	= woc.WORKORDERID ---parent (INSPECT PACP) wo information			30142
	LEFT JOIN CWProd.Azteca.WORKORDER (nolock) wo				ON tv.WORKORDERID	= wo.SOURCEWOID ---using this join to find the parent record... so the next join can connect to the children
	LEFT JOIN ##Results r										ON wo.WORKORDERID	= r.WORKORDERID	---child (CONDITION ASSESSMENT) wo information	33456
	LEFT JOIN CWProd.Azteca.WORKORDER (nolock) wo2				ON r.WORKORDERID	= wo2.WORKORDERID
																AND wo2.STATUS <> 'CANCEL'
	LEFT JOIN #CriticalityScores pcs							ON tv.PIPE_ID		= pcs.AssetID 
																--AND YEAR(tv.TVDATE) = YEAR(pcs.CreatedDate) ---matching up the year that the inspection happened, with the year that the GIS Tool info was generated by SW
	LEFT JOIN #ProblemSummary ps								ON tv.TVID			= ps.TVID
	LEFT JOIN CWProd.Azteca.WORKORDER (nolock) wo3				ON tv.WORKORDERID	= wo3.WORKORDERID ---need WO details for the PACP Inspect WO
	
	
	--where tv.WORKORDERID = 29964

	--ORDER BY CAST(tv.WORKORDERID as INT), tv.TVID

----testing 
	--where tv.WORKORDERID = 29485
	--where cr.TVID IN ( 1250)
	--where tv.PIPE_ID like  '%142%'
	 --order by WorkOrderID

	 END
GO


