USE [Compliance]
GO
/****** Object:  StoredProcedure [Lodging].[CompileAndReconcileMonthlyData]    Script Date: 9/5/2017 10:47:49 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


/*
** Prod File: n/a  
** Name: [Lodging].[CompileAndReconcileMonthlyData] 
** Desc: Compile And Reconcile Monthly Data (21ish minutes... need to trim down the time some more) ---10 minutes in the new server
** Auth: Tammy Lessley
** Date: 20151022 
**************************
** Change History
**************************
** JIRA				Date       Author			Description 
** --				--------   -------			------------------------------------
** TAXSYSTEMS-633	20170608   Tammy Lessley	Insert extra fields to pick up the Remittance Type Change data and include the Remit Type Change Logic for those jurisdictions that have changes to remit type. 

*/
CREATE PROCEDURE [Lodging].[CompileAndReconcileMonthlyData]
AS 

BEGIN ---- PROCEDURE

---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
--#1----TO BEGIN THE FIRST LOOPING JOB (Adj Price - Adj Cost w Price Fee)
/* Each loop listed below, does the following:
	Declares a table called "List" (or some derevation therein), fills it up with a ranking of all the similar margin jurisdictions.
	That list is used 
*/
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
BEGIN 
DECLARE @List table (Ranking INT, Jurisdiction_State VARCHAR(5), [Reporting_Jurisdiction_Name] VARCHAR(50),[Reporting_Jurisdiction_Type] VARCHAR(50), [Remittance_Type] VARCHAR(50) ) --added remittance type

INSERT INTO @List
	SELECT 'Ranking' = RANK () OVER ( PARTITION BY TaxBaseFieldName ORDER BY [Jurisdiction_State], [Reporting_Jurisdiction_Name], [Reporting_Jurisdiction_Type], [Remittance_Type]),--added remittance type
		   Jurisdiction_State, [Reporting_Jurisdiction_Name], [Reporting_Jurisdiction_Type], [Remittance_Type] --added remittance type
	FROM [Compliance].[lkup].[LodgingCompliance]
	WHERE TaxBaseFieldName = 'ADJ_PRICE-ADJ_COST_WPriceFee'
		  AND Template_Type = 'Popular'	
	ORDER BY Ranking

---------------------------------------------------------------------------------

DECLARE @RankingMin INT,
		@RankingMax INT,
		@State	VARCHAR(50),
		@Name	VARCHAR(50),
		@Type	VARCHAR(50),
		@RemitType VARCHAR(50), ---added remittance type
		@Negative_Margin_Exclusion VARCHAR(1);

SELECT @RankingMin = MIN(Ranking), @RankingMax = MAX(Ranking)  FROM @List WHILE @RankingMin <= @RankingMax  ----this sets up the loop at the beginning count (1), 
																											----and ensures that it stops when it gets to the end of the List
--------------------------------
-----E.G. DC, HI, ETC (LARGEST POPULATION OF JURISDICTIONS HERE
--------------------------------
BEGIN		
		
		---compile compliance AUDIT data - put into a temp table (more efficient to put data into temp and then into table, instead of straight into a table)
		---pulling these 3 parameters based off of the rank in the List
		SELECT @State	= (SELECT Jurisdiction_State			FROM @List WHERE Ranking = @RankingMin)
		SELECT @Name	= (SELECT Reporting_Jurisdiction_Name	FROM @List WHERE Ranking = @RankingMin)
		SELECT @Type	= (SELECT Reporting_Jurisdiction_Type	FROM @List WHERE Ranking = @RankingMin)
		SELECT @RemitType	= (SELECT [Remittance_Type]			FROM @List WHERE Ranking = @RankingMin) ---added remittance type
		SET @Negative_Margin_Exclusion = (SELECT Negative_Margin_Exclusion
										  FROM   lkup.LodgingCompliance 
										  WHERE  Jurisdiction_State = @State
										  AND Reporting_Jurisdiction_Name = @Name
										  AND Reporting_Jurisdiction_Type = @Type
										  AND [Remittance_Type] = @RemitType); ---added remittance type
		

		---insert the data into the temp tables based off of the parameters chosen above, by the ranking, thrown into the functions
		SELECT * INTO #TempAudit		FROM (SELECT * FROM Compliance.[F_Audit_ADJ_PRICE-ADJ_COST_WPriceFee]	(@State,@Name,@Type,@RemitType) )x ---added remittance type
		SELECT * INTO #TempJE			FROM (SELECT * FROM Compliance.[F_JE_ADJ_PRICE-ADJ_COST_WPriceFee]		(@State,@Name,@Type,@RemitType) )x ---added remittance type
		SELECT * INTO #TempJE_15330		FROM (SELECT * FROM Compliance.[F_JE15330_ADJ_PRICE-ADJ_COST_WPriceFee] (@State,@Name,@Type,@RemitType) )x ---added remittance type

		----------------------------------------------------------------------------------------
		--------------------
		----RECONCILIATION between Compliance and JE's details - then compile and insert the reconciliation into table
		--------------------


		SELECT * INTO #JE_ComparisonTemp FROM 
		----Compile Expense (P&L) Side of JE Data from temp tables
		(SELECT DISTINCT  'JE_Company' = Company
						 ,'JE_Description' = CASE WHEN [Description] LIKE '%Brk%'
												  THEN 'Breakage'
												  WHEN [Description] NOT LIKE '%Brk%'
												  THEN 'Compliance'
												  END
						 ,'JE_JurisdictionState' = PARSENAME([Description], 4)
						 ,'JE_JurisdictionName'  = PARSENAME([Description], 3)
						 ,'JE_JurisdictionType'  = substring(PARSENAME([Description], 2), 1, charindex('_', PARSENAME([Description], 2))-1)
						 ,'JE_Amount' = SUM(Debit - Credit)
						 ,'JE_ReportDate' = ISNULL([Accounting Date],(SELECT MAX([Accounting Date]) FROM #TempJE))
		FROM #TempJE
		WHERE LEFT(Account, 4) <> 2088 ---the function pulls all sides of the JE, this clause allows us to grab just the P&L portion - the portion with the true legal entities still attached 
		GROUP BY Company
				 ,(CASE WHEN [Description] LIKE '%Brk%'
												  THEN 'Breakage'
												  WHEN [Description] NOT LIKE '%Brk%'
												  THEN 'Compliance'
												  END)
				 ,PARSENAME([Description], 4)
				 ,PARSENAME([Description], 3)
				 ,substring(PARSENAME([Description], 2), 1, charindex('_', PARSENAME([Description], 2))-1)
				 ,[Accounting Date]
		UNION ALL 
		SELECT DISTINCT   Company
						 ,CASE WHEN [Description] LIKE '%Brk%'
												  THEN 'Breakage'
												  WHEN [Description] NOT LIKE '%Brk%'
												  THEN 'Compliance'
												  END
						 ,PARSENAME([Description], 4)
						 ,PARSENAME([Description], 3)
						 ,substring(PARSENAME([Description], 2), 1, charindex('_', PARSENAME([Description], 2))-1)
						 ,SUM(Debit - Credit)
						 ,[Accounting Date]
		FROM #TempJE_15330
		WHERE LEFT(Account, 4) <> 2088
		GROUP BY Company
				 ,(CASE WHEN [Description] LIKE '%Brk%'
												  THEN 'Breakage'
												  WHEN [Description] NOT LIKE '%Brk%'
												  THEN 'Compliance'
												  END)
				 ,PARSENAME([Description], 4)
				 ,PARSENAME([Description], 3)
				 ,substring(PARSENAME([Description], 2), 1, charindex('_', PARSENAME([Description], 2))-1)
				 ,[Accounting Date])x  

		--Compare the Audit Files with the JE's 


		SELECT * INTO #Audit_ComparisonTemp FROM 
		(SELECT  'Audit_Company' = [LGL_ENTITY_CODE]
				,'Audit_Description' = CASE WHEN [TRANS_TYP_NAME] = 'Cost Adjustment'
									  THEN 'Breakage'
									  ELSE 'Compliance'
									  END
				,'Audit_Jurisdiction_State' = Jurisdiction_State
				,'Audit_Jurisdiction_Name' = Reporting_Jurisdiction_Name
				,'Audit_Jurisdiction_Type' = Reporting_Jurisdiction_Type 
				,'Audit_Remittance_Type' = [Remittance_Type] ---added remittance type
				,'Audit_Amount' = SUM(CASE WHEN  (Reporting_Jurisdiction_Type = 'county' AND Reporting_Jurisdiction_Name <> 'all')
											THEN [County Tax On Margin Due]
											WHEN (Reporting_Jurisdiction_Type = 'city' AND Reporting_Jurisdiction_Name <> 'all')
											THEN [City Tax On Margin Due] 			
											WHEN Reporting_Jurisdiction_Type = 'state'
											THEN [State Tax On Margin Due]
											WHEN Reporting_Jurisdiction_Type = 'get'
											THEN [Get Tax On Margin Due]
											WHEN (Reporting_Jurisdiction_Type = 'all' OR Reporting_Jurisdiction_Name = 'all')
											THEN [Total Tax On Margin Due]
											END)
				,'Audit_ReportDate' = MAX([REPORTENDDATE])
									 									
		FROM #TempAudit
		WHERE 	(CASE WHEN @Negative_Margin_Exclusion = 'Y' AND (CASE WHEN NetNegFlag = 'N' -----these are the trans that are do NOT net to a negative for the month
																									-----so they can be INCLUDED for those special jurisdictions
																			THEN 'NetPositive' 
																			ELSE 'NetNegative' 
																			END) = 'NetPositive'
								THEN 'Y'
								ELSE 'N'
								END	) = @Negative_Margin_Exclusion
		GROUP BY 
				[LGL_ENTITY_CODE]
				,(CASE WHEN [TRANS_TYP_NAME] = 'Cost Adjustment'
									  THEN 'Breakage'
									  ELSE 'Compliance'
									  END)
				,Jurisdiction_State
				,Reporting_Jurisdiction_Name
				,Reporting_Jurisdiction_Type
				,[Remittance_Type])x ---added remittance type

		-----Insert High Level Reconciliation Numbers, into table

		IF EXISTS 
			(SELECT 'ComparedAmounts' = SUM(ISNULL(Audit_Amount, 0) - ISNULL(JE_Amount,0))
			 FROM #Audit_ComparisonTemp a
			 LEFT JOIN #JE_ComparisonTemp j ON a.Audit_Company = j.JE_Company 
												AND a.Audit_Description = j.JE_Description
												AND a.Audit_Jurisdiction_State = j.JE_JurisdictionState
												AND a.Audit_Jurisdiction_Name = j.JE_JurisdictionName
												AND a.Audit_Jurisdiction_Type = j.JE_JurisdictionType
			 HAVING SUM(ISNULL((Audit_Amount - JE_Amount), 0)) BETWEEN -2 AND 2)	--------------2 dollar buffer - to check between the JE & Audit totals. if they are more than that, then it will log an error								

			INSERT INTO Reconciliation.LodgingComparison
					([Audit_Company]
					  ,[Audit_Description]
					  ,[Audit_Jurisdiction_State]
					  ,[Audit_Jurisdiction_Name]
					  ,[Audit_Jurisdiction_Type]
					  ,[Audit_Remittance_Type] ---added remittance type
					  ,[Audit_Amount]
					  ,[Audit_ReportDate]
					  ,[JE_Company]
					  ,[JE_Description]
					  ,[JE_JurisdictionState]
					  ,[JE_JurisdictionName]
					  ,[JE_JurisdictionType]
					  ,[JE_Remittance_Type]---added remittance type
					  ,[JE_Amount]
					  ,[JE_ReportDate]
					  ,[ComparedAmounts]
					  ,[InsertedDate])

			SELECT	 Audit_Company
					,Audit_Description
					,Audit_Jurisdiction_State
					,Audit_Jurisdiction_Name
					,Audit_Jurisdiction_Type
					,[Audit_Remittance_Type] ---added remittance type
					,Audit_Amount
					,Audit_ReportDate
					,JE_Company
					,JE_Description
					,JE_JurisdictionState
					,JE_JurisdictionName
					,JE_JurisdictionType
					,[Audit_Remittance_Type] ---added remittance type --this will be equivalent for the margin model passing through this section, one at a time
					,JE_Amount
					,JE_ReportDate
					,'ComparedAmounts' = ISNULL(Audit_Amount, 0) - ISNULL(JE_Amount,0)
					,'InsertedDate' = GETDATE()
			 
			FROM #Audit_ComparisonTemp a
			LEFT JOIN #JE_ComparisonTemp j ON a.Audit_Company = j.JE_Company 
												AND a.Audit_Description = j.JE_Description
												AND a.Audit_Jurisdiction_State = j.JE_JurisdictionState
												AND a.Audit_Jurisdiction_Name = j.JE_JurisdictionName
												AND a.Audit_Jurisdiction_Type = j.JE_JurisdictionType
		ELSE 
		INSERT INTO Reconciliation.[LodgingComparison_Errors] 
		( [Audit_Company]
		  ,[Audit_Description]
		  ,[Audit_Jurisdiction_State]
		  ,[Audit_Jurisdiction_Name]
		  ,[Audit_Jurisdiction_Type]
		  ,[Audit_Remittance_Type] ---added remittance type
		  ,[Audit_Amount]
		  ,[Audit_ReportDate]
		  ,[JE_Company]
		  ,[JE_Description]
		  ,[JE_JurisdictionState]
		  ,[JE_JurisdictionName]
		  ,[JE_JurisdictionType]
		  ,[JE_Remittance_Type] ---added remittance type
		  ,[JE_Amount]
		  ,[JE_ReportDate]
		  ,[ComparedAmounts]
		  ,[InsertedDate]
		  ,[Note])
		(SELECT Audit_Company
				,Audit_Description
				,Audit_Jurisdiction_State
				,Audit_Jurisdiction_Name
				,Audit_Jurisdiction_Type
				,[Audit_Remittance_Type] ---added remittance type
				,Audit_Amount
				,Audit_ReportDate
				,JE_Company
				,JE_Description
				,JE_JurisdictionState
				,JE_JurisdictionName
				,JE_JurisdictionType
				,[Audit_Remittance_Type] ---added remittance type --this will be equivalent for the margin model passing through this section, one at a time
				,JE_Amount
				,JE_ReportDate
				,'ComparedAmounts' = ISNULL(Audit_Amount, 0) - ISNULL(JE_Amount,0)
				,'InsertedDate' = GETDATE()
				,'Note' = 'Does Not Match'
		FROM #Audit_ComparisonTemp a
			LEFT JOIN #JE_ComparisonTemp j ON a.Audit_Company = j.JE_Company 
												AND a.Audit_Description = j.JE_Description
												AND a.Audit_Jurisdiction_State = j.JE_JurisdictionState
												AND a.Audit_Jurisdiction_Name = j.JE_JurisdictionName
												AND a.Audit_Jurisdiction_Type = j.JE_JurisdictionType  )									
											
		--------------------------------------
		----take data from the temp tables, and insert into real tables (these will be the detailed tables)

		INSERT INTO Filed.LodgingCompliance	SELECT * FROM #TempAudit 
		INSERT INTO Filed.Lodging_JE		SELECT * FROM #TempJE 
		INSERT INTO Filed.Lodging_JE_15330	SELECT * FROM #TempJE_15330  
		
		---clears out the temp tables for each loop, so that each jurisdiction gets treated seperately for the reconciliation process
		IF OBJECT_ID('tempdb..#TempAudit')				IS NOT NULL DROP TABLE #TempAudit;
		IF OBJECT_ID('tempdb..#TempJE')					IS NOT NULL DROP TABLE #TempJE;
		IF OBJECT_ID('tempdb..#TempJE_15330')			IS NOT NULL DROP TABLE #TempJE_15330;
		IF OBJECT_ID('tempdb..#Audit_ComparisonTemp')	IS NOT NULL DROP TABLE #Audit_ComparisonTemp;
		IF OBJECT_ID('tempdb..#JE_ComparisonTemp')		IS NOT NULL DROP TABLE #JE_ComparisonTemp;

-------------------------------------------------------------------------------------------------------------------------------------


SET @RankingMin = @RankingMin+1 --------this helps the loop continue upwards in count
END 
END; ---end the first loop


---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
--#2----TO BEGIN THE SECOND LOOPING JOB (ADJ_PRICE_GA - ADJ_COST_GA)
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
BEGIN 
DECLARE @ListGA table (Ranking INT, Jurisdiction_State VARCHAR(5), [Reporting_Jurisdiction_Name] VARCHAR(50),[Reporting_Jurisdiction_Type] VARCHAR(50), [Remittance_Type] VARCHAR(50)  )--added remittance type

INSERT INTO @ListGA
	SELECT 'Ranking' = RANK () OVER ( PARTITION BY TaxBaseFieldName ORDER BY [Jurisdiction_State], [Reporting_Jurisdiction_Name], [Reporting_Jurisdiction_Type], [Remittance_Type]),--added remittance type
		   Jurisdiction_State, [Reporting_Jurisdiction_Name], [Reporting_Jurisdiction_Type], [Remittance_Type] --added remittance type
	FROM [Compliance].[lkup].[LodgingCompliance]
	WHERE TaxBaseFieldName = 'ADJ_PRICE_GA-ADJ_COST_GA'
		  AND Template_Type = 'Popular'
	ORDER BY Ranking


---------------------------------------------------------------------------------


DECLARE @RankingMinGA INT,
		@RankingMaxGA INT,
		@StateGA	VARCHAR(50),
		@NameGA		VARCHAR(50),
		@TypeGA		VARCHAR(50),
		@RemitTypeGA VARCHAR(50), ---added remittance type
		@Negative_Margin_ExclusionGA VARCHAR(1);

SELECT @RankingMinGA = MIN(Ranking), @RankingMaxGA = MAX(Ranking)  FROM @ListGA WHILE @RankingMinGA <= @RankingMaxGA  ----this sets up the loop at the beginning count (1)
--------------------------------
------E.G. GA related jurisdictions
--------------------------------
BEGIN		
		
		---compile compliance AUDIT data - put into a temp table (more efficient to put data into temp and then into table, instead of straight into a table)
		SELECT @StateGA	= (SELECT Jurisdiction_State			FROM @ListGA WHERE Ranking = @RankingMinGA)
		SELECT @NameGA	= (SELECT Reporting_Jurisdiction_Name	FROM @ListGA WHERE Ranking = @RankingMinGA)
		SELECT @TypeGA	= (SELECT Reporting_Jurisdiction_Type	FROM @ListGA WHERE Ranking = @RankingMinGA)
		SELECT @RemitTypeGA	= (SELECT [Remittance_Type]			FROM @ListGA WHERE Ranking = @RankingMinGA) ---added remittance type
		SET @Negative_Margin_ExclusionGA = (SELECT Negative_Margin_Exclusion
											  FROM   lkup.LodgingCompliance 
											  WHERE  Jurisdiction_State = @StateGA
											  AND Reporting_Jurisdiction_Name = @NameGA
											  AND Reporting_Jurisdiction_Type = @TypeGA
											  AND [Remittance_Type] = @RemitTypeGA); ---added remittance type

		SELECT * INTO #TempAuditGA			FROM (SELECT * FROM Compliance.[F_Audit_ADJ_PRICE_GA-ADJ_COST_GA]	(@StateGA,@NameGA,@TypeGA,@RemitTypeGA) )x ---added remittance type
		SELECT * INTO #TempJEGA				FROM (SELECT * FROM Compliance.[F_JE_ADJ_PRICE_GA-ADJ_COST_GA]		(@StateGA,@NameGA,@TypeGA,@RemitTypeGA) )x ---added remittance type
		SELECT * INTO #TempJE_15330GA		FROM (SELECT * FROM Compliance.[F_JE15330_ADJ_PRICE_GA-ADJ_COST_GA] (@StateGA,@NameGA,@TypeGA,@RemitTypeGA) )x ---added remittance type 


		----------------------------------------------------------------------------------------
		--------------------
		----RECONCILIATION between Compliance and JE's details - then compile and insert the reconciliation into table
		--------------------


		SELECT * INTO #JE_ComparisonTempGA FROM 
		----Compile Expense Side of JE Data from temp tables
		(SELECT DISTINCT  'JE_Company' = Company
						 ,'JE_Description' = CASE WHEN [Description] LIKE '%Brk%'
												  THEN 'Breakage'
												  WHEN [Description] NOT LIKE '%Brk%'
												  THEN 'Compliance'
												  END
						 ,'JE_JurisdictionState' = PARSENAME([Description], 4)
						 ,'JE_JurisdictionName'  = PARSENAME([Description], 3)
						 ,'JE_JurisdictionType'  = substring(PARSENAME([Description], 2), 1, charindex('_', PARSENAME([Description], 2))-1)
						 ,'JE_Amount' = SUM(Debit - Credit)
						 ,'JE_ReportDate' = ISNULL([Accounting Date],(SELECT MAX([Accounting Date]) FROM #TempJEGA))
		FROM #TempJEGA
		WHERE LEFT(Account, 4) <> 2088
		GROUP BY Company
				 ,(CASE WHEN [Description] LIKE '%Brk%'
												  THEN 'Breakage'
												  WHEN [Description] NOT LIKE '%Brk%'
												  THEN 'Compliance'
												  END)
				 ,PARSENAME([Description], 4)
				 ,PARSENAME([Description], 3)
				 ,substring(PARSENAME([Description], 2), 1, charindex('_', PARSENAME([Description], 2))-1)
				 ,[Accounting Date]
		UNION ALL 
		SELECT DISTINCT   Company
						 ,CASE WHEN [Description] LIKE '%Brk%'
												  THEN 'Breakage'
												  WHEN [Description] NOT LIKE '%Brk%'
												  THEN 'Compliance'
												  END
						 ,PARSENAME([Description], 4)
						 ,PARSENAME([Description], 3)
						 ,substring(PARSENAME([Description], 2), 1, charindex('_', PARSENAME([Description], 2))-1)
						 ,SUM(Debit - Credit)
						 ,[Accounting Date]
		FROM #TempJE_15330GA
		WHERE LEFT(Account, 4) <> 2088
		GROUP BY Company
				 ,(CASE WHEN [Description] LIKE '%Brk%'
												  THEN 'Breakage'
												  WHEN [Description] NOT LIKE '%Brk%'
												  THEN 'Compliance'
												  END)
				 ,PARSENAME([Description], 4)
				 ,PARSENAME([Description], 3)
				 ,substring(PARSENAME([Description], 2), 1, charindex('_', PARSENAME([Description], 2))-1)
				 ,[Accounting Date])x 

		--Compare the Audit Files with the JE's 


		SELECT * INTO #Audit_ComparisonTempGA FROM 
		(SELECT  'Audit_Company' = [LGL_ENTITY_CODE]
				,'Audit_Description' = CASE WHEN [TRANS_TYP_NAME] = 'Cost Adjustment'
									  THEN 'Breakage'
									  ELSE 'Compliance'
									  END
				,'Audit_Jurisdiction_State' = Jurisdiction_State
				,'Audit_Jurisdiction_Name' = Reporting_Jurisdiction_Name
				,'Audit_Jurisdiction_Type' = Reporting_Jurisdiction_Type
				,'Audit_Remittance_Type' = [Remittance_Type] ---added remittance type
				,'Audit_Amount' = SUM(CASE WHEN  (Reporting_Jurisdiction_Type = 'county' AND Reporting_Jurisdiction_Name <> 'all') 
											THEN [County Tax On Margin Due]
											WHEN (Reporting_Jurisdiction_Type = 'city' AND Reporting_Jurisdiction_Name <> 'all') AND Reporting_Jurisdiction_Name <> 'Rome'
											THEN [City Tax On Margin Due] 			
											WHEN Reporting_Jurisdiction_Type = 'state'
											THEN [State Tax On Margin Due]
											WHEN Reporting_Jurisdiction_Type = 'get'
											THEN [Get Tax On Margin Due]
											WHEN (Reporting_Jurisdiction_Type = 'all' OR Reporting_Jurisdiction_Name = 'all')
											THEN [Total Tax On Margin Due]
											WHEN Reporting_Jurisdiction_Type = 'city' AND Reporting_Jurisdiction_Name <> 'all' AND Reporting_Jurisdiction_Name = 'Rome'
											THEN [City Tax On Margin Due] + [County Tax On Margin Due]
											END)
				,'Audit_ReportDate' = MAX([REPORTENDDATE])
									 									
		FROM #TempAuditGA
		WHERE 	(CASE WHEN @Negative_Margin_ExclusionGA = 'Y' AND (CASE WHEN NetNegFlag = 'N' -----these are the trans that are do NOT net to a negative for the month
																									-----so they can be INCLUDED for those special jurisdictions
																			THEN 'NetPositive' 
																			ELSE 'NetNegative' 
																			END) = 'NetPositive'
								THEN 'Y'
								ELSE 'N'
								END	) = @Negative_Margin_ExclusionGA
		GROUP BY 
				[LGL_ENTITY_CODE]
				,(CASE WHEN [TRANS_TYP_NAME] = 'Cost Adjustment'
									  THEN 'Breakage'
									  ELSE 'Compliance'
									  END)
				,Jurisdiction_State
				,Reporting_Jurisdiction_Name
				,Reporting_Jurisdiction_Type
				,[Remittance_Type])x ---added remittance type	

		-----Insert High Level Reconciliation Numbers, into table

		IF EXISTS 
			(SELECT 'ComparedAmounts' = SUM(ISNULL(Audit_Amount, 0) - ISNULL(JE_Amount,0))
			 FROM #Audit_ComparisonTempGA a
			 LEFT JOIN #JE_ComparisonTempGA j ON a.Audit_Company = j.JE_Company 
												AND a.Audit_Description = j.JE_Description
												AND a.Audit_Jurisdiction_State = j.JE_JurisdictionState
												AND a.Audit_Jurisdiction_Name = j.JE_JurisdictionName
												AND a.Audit_Jurisdiction_Type = j.JE_JurisdictionType
			 HAVING SUM(ISNULL((Audit_Amount - JE_Amount), 0)) BETWEEN -2 AND 2)	--------------2 dollar buffer								

			INSERT INTO Reconciliation.LodgingComparison
					([Audit_Company]
					  ,[Audit_Description]
					  ,[Audit_Jurisdiction_State]
					  ,[Audit_Jurisdiction_Name]
					  ,[Audit_Jurisdiction_Type]
					  ,[Audit_Remittance_Type] ---added remittance type
					  ,[Audit_Amount]
					  ,[Audit_ReportDate]
					  ,[JE_Company]
					  ,[JE_Description]
					  ,[JE_JurisdictionState]
					  ,[JE_JurisdictionName]
					  ,[JE_JurisdictionType]
					  ,[JE_Remittance_Type]---added remittance type
					  ,[JE_Amount]
					  ,[JE_ReportDate]
					  ,[ComparedAmounts]
					  ,[InsertedDate])

			SELECT	 Audit_Company
					,Audit_Description
					,Audit_Jurisdiction_State
					,Audit_Jurisdiction_Name
					,Audit_Jurisdiction_Type
					,[Audit_Remittance_Type] ---added remittance type
					,Audit_Amount
					,Audit_ReportDate
					,JE_Company
					,JE_Description
					,JE_JurisdictionState
					,JE_JurisdictionName
					,JE_JurisdictionType
					,[Audit_Remittance_Type] ---added remittance type --this will be equivalent for the margin model passing through this section, one at a time
					,JE_Amount
					,JE_ReportDate
					,'ComparedAmounts' = ISNULL(Audit_Amount, 0) - ISNULL(JE_Amount,0)
					,'InsertedDate' = GETDATE()
			 
			FROM #Audit_ComparisonTempGA a
			LEFT JOIN #JE_ComparisonTempGA j ON a.Audit_Company = j.JE_Company 
												AND a.Audit_Description = j.JE_Description
												AND a.Audit_Jurisdiction_State = j.JE_JurisdictionState
												AND a.Audit_Jurisdiction_Name = j.JE_JurisdictionName
												AND a.Audit_Jurisdiction_Type = j.JE_JurisdictionType
		ELSE 
		INSERT INTO Reconciliation.[LodgingComparison_Errors] 
		( [Audit_Company]
		  ,[Audit_Description]
		  ,[Audit_Jurisdiction_State]
		  ,[Audit_Jurisdiction_Name]
		  ,[Audit_Jurisdiction_Type]
		  ,[Audit_Remittance_Type] ---added remittance type
		  ,[Audit_Amount]
		  ,[Audit_ReportDate]
		  ,[JE_Company]
		  ,[JE_Description]
		  ,[JE_JurisdictionState]
		  ,[JE_JurisdictionName]
		  ,[JE_JurisdictionType]
		  ,[JE_Remittance_Type] ---added remittance type
		  ,[JE_Amount]
		  ,[JE_ReportDate]
		  ,[ComparedAmounts]
		  ,[InsertedDate]
		  ,[Note])
		(SELECT Audit_Company
				,Audit_Description
				,Audit_Jurisdiction_State
				,Audit_Jurisdiction_Name
				,Audit_Jurisdiction_Type
				,[Audit_Remittance_Type] ---added remittance type
				,Audit_Amount
				,Audit_ReportDate
				,JE_Company
				,JE_Description
				,JE_JurisdictionState
				,JE_JurisdictionName
				,JE_JurisdictionType
				,[Audit_Remittance_Type] ---added remittance type --this will be equivalent for the margin model passing through this section, one at a time
				,JE_Amount
				,JE_ReportDate
				,'ComparedAmounts' = ISNULL(Audit_Amount, 0) - ISNULL(JE_Amount,0)
				,'InsertedDate' = GETDATE()
				,'Note' = 'Does Not Match'
		FROM #Audit_ComparisonTempGA a
			LEFT JOIN #JE_ComparisonTempGA j ON a.Audit_Company = j.JE_Company 
												AND a.Audit_Description = j.JE_Description
												AND a.Audit_Jurisdiction_State = j.JE_JurisdictionState
												AND a.Audit_Jurisdiction_Name = j.JE_JurisdictionName
												AND a.Audit_Jurisdiction_Type = j.JE_JurisdictionType  )									
											
		--------------------------------------
		----take data from the temp tables, and insert into real tables (these will be the detailed tables)

		INSERT INTO Filed.LodgingCompliance	SELECT * FROM #TempAuditGA
		INSERT INTO Filed.Lodging_JE		SELECT * FROM #TempJEGA
		INSERT INTO Filed.Lodging_JE_15330	SELECT * FROM #TempJE_15330GA


		IF OBJECT_ID('tempdb..#TempAuditGA')			IS NOT NULL DROP TABLE #TempAuditGA;
		IF OBJECT_ID('tempdb..#TempJEGA')				IS NOT NULL DROP TABLE #TempJEGA;
		IF OBJECT_ID('tempdb..#TempJE_15330GA')			IS NOT NULL DROP TABLE #TempJE_15330GA;
		IF OBJECT_ID('tempdb..#Audit_ComparisonTempGA') IS NOT NULL DROP TABLE #Audit_ComparisonTempGA;
		IF OBJECT_ID('tempdb..#JE_ComparisonTempGA')	IS NOT NULL DROP TABLE #JE_ComparisonTempGA;
-------------------------------------------------------------------------------------------------------------------------------------


SET @RankingMinGA = @RankingMinGA + 1 --------this helps the loop continue upwards in count
END 
END; ---end the second loop


---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
--#3----TO BEGIN THE THIRD LOOPING JOB (ADJ_PRICE_NY-ADJ_COST_WPriceFee) 
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
BEGIN 
DECLARE @ListNY table (Ranking INT, Jurisdiction_State VARCHAR(5), [Reporting_Jurisdiction_Name] VARCHAR(50),[Reporting_Jurisdiction_Type] VARCHAR(50), [Remittance_Type] VARCHAR(50)  )--added remittance type

INSERT INTO @ListNY
	SELECT 'Ranking' = RANK () OVER ( PARTITION BY TaxBaseFieldName ORDER BY [Jurisdiction_State], [Reporting_Jurisdiction_Name], [Reporting_Jurisdiction_Type], [Remittance_Type]), --added remittance type
		   Jurisdiction_State, [Reporting_Jurisdiction_Name], [Reporting_Jurisdiction_Type], [Remittance_Type]--added remittance type
	FROM [Compliance].[lkup].[LodgingCompliance]
	WHERE TaxBaseFieldName = 'ADJ_PRICE_NY-ADJ_COST_WPriceFee'
		  AND Template_Type = 'Popular'
	ORDER BY Ranking


---------------------------------------------------------------------------------


DECLARE @RankingMinNY INT,
		@RankingMaxNY INT,
		@StateNY	VARCHAR(50),
		@NameNY		VARCHAR(50),
		@TypeNY		VARCHAR(50),
		@RemitTypeNY VARCHAR(50),--added remittance type
		@Negative_Margin_ExclusionNY VARCHAR(1);

SELECT @RankingMinNY = MIN(Ranking), @RankingMaxNY = MAX(Ranking)  FROM @ListNY WHILE @RankingMinNY <= @RankingMaxNY  ----this sets up the loop at the beginning count (1)
--------------------------------
------E.G. NY
--------------------------------
BEGIN		
		
		---compile compliance AUDIT data - put into a temp table (more efficient to put data into temp and then into table, instead of straight into a table)
		SELECT @StateNY	= (SELECT Jurisdiction_State			FROM @ListNY WHERE Ranking = @RankingMinNY)
		SELECT @NameNY	= (SELECT Reporting_Jurisdiction_Name	FROM @ListNY WHERE Ranking = @RankingMinNY)
		SELECT @TypeNY	= (SELECT Reporting_Jurisdiction_Type	FROM @ListNY WHERE Ranking = @RankingMinNY)
		SELECT @RemitTypeNY	= (SELECT [Remittance_Type]			FROM @ListNY WHERE Ranking = @RankingMinNY) ---added remittance type
		SET @Negative_Margin_ExclusionNY = (SELECT Negative_Margin_Exclusion
										  FROM   lkup.LodgingCompliance 
										  WHERE  Jurisdiction_State = @StateNY
										  AND Reporting_Jurisdiction_Name = @NameNY
										  AND Reporting_Jurisdiction_Type = @TypeNY
										  AND [Remittance_Type] = @RemitTypeNY); ---added remittance type

			
		SELECT * INTO #TempAuditNY			FROM (SELECT * FROM Compliance.[F_Audit_ADJ_PRICE_NY-ADJ_COST_WPriceFee]	(@StateNY,@NameNY,@TypeNY,@RemitTypeNY) )x---added remittance type
		SELECT * INTO #TempJENY				FROM (SELECT * FROM Compliance.[F_JE_ADJ_PRICE_NY-ADJ_COST_WPriceFee]		(@StateNY,@NameNY,@TypeNY,@RemitTypeNY) )x---added remittance type
		SELECT * INTO #TempJE_15330NY		FROM (SELECT * FROM Compliance.[F_JE15330_ADJ_PRICE_NY-ADJ_COST_WPriceFee]	(@StateNY,@NameNY,@TypeNY,@RemitTypeNY) )x---added remittance type


		----------------------------------------------------------------------------------------
		--------------------
		----RECONCILIATION between Compliance and JE's details - then compile and insert the reconciliation into table
		--------------------


		SELECT * INTO #JE_ComparisonTempNY FROM 
		----Compile Expense Side of JE Data from temp tables
		(SELECT DISTINCT  'JE_Company' = Company
						 ,'JE_Description' = CASE WHEN [Description] LIKE '%Brk%'
												  THEN 'Breakage'
												  WHEN [Description] NOT LIKE '%Brk%'
												  THEN 'Compliance'
												  END
						 ,'JE_JurisdictionState' = PARSENAME([Description], 4)
						 ,'JE_JurisdictionName'  = PARSENAME([Description], 3)
						 ,'JE_JurisdictionType'  = substring(PARSENAME([Description], 2), 1, charindex('_', PARSENAME([Description], 2))-1)
						 ,'JE_Amount' = SUM(Debit - Credit)
						 ,'JE_ReportDate' = ISNULL([Accounting Date],(SELECT MAX([Accounting Date]) FROM #TempJENY))
		FROM #TempJENY
		WHERE LEFT(Account, 4) <> 2088
		GROUP BY Company
				 ,(CASE WHEN [Description] LIKE '%Brk%'
												  THEN 'Breakage'
												  WHEN [Description] NOT LIKE '%Brk%'
												  THEN 'Compliance'
												  END)
				 ,PARSENAME([Description], 4)
				 ,PARSENAME([Description], 3)
				 ,substring(PARSENAME([Description], 2), 1, charindex('_', PARSENAME([Description], 2))-1)
				 ,[Accounting Date]
		UNION ALL 
		SELECT DISTINCT   Company
						 ,CASE WHEN [Description] LIKE '%Brk%'
												  THEN 'Breakage'
												  WHEN [Description] NOT LIKE '%Brk%'
												  THEN 'Compliance'
												  END
						 ,PARSENAME([Description], 4)
						 ,PARSENAME([Description], 3)
						 ,substring(PARSENAME([Description], 2), 1, charindex('_', PARSENAME([Description], 2))-1)
						 ,SUM(Debit - Credit)
						 ,[Accounting Date]
		FROM #TempJE_15330NY
		WHERE LEFT(Account, 4) <> 2088
		GROUP BY Company
				 ,(CASE WHEN [Description] LIKE '%Brk%'
												  THEN 'Breakage'
												  WHEN [Description] NOT LIKE '%Brk%'
												  THEN 'Compliance'
												  END)
				 ,PARSENAME([Description], 4)
				 ,PARSENAME([Description], 3)
				 ,substring(PARSENAME([Description], 2), 1, charindex('_', PARSENAME([Description], 2))-1)
				 ,[Accounting Date])x 

		--Compare the Audit Files with the JE's 


		SELECT * INTO #Audit_ComparisonTempNY FROM 
		(SELECT  'Audit_Company' = [LGL_ENTITY_CODE]
				,'Audit_Description' = CASE WHEN [TRANS_TYP_NAME] = 'Cost Adjustment'
									  THEN 'Breakage'
									  ELSE 'Compliance'
									  END
				,'Audit_Jurisdiction_State' = Jurisdiction_State
				,'Audit_Jurisdiction_Name' = Reporting_Jurisdiction_Name
				,'Audit_Jurisdiction_Type' = Reporting_Jurisdiction_Type
				,'Audit_Remittance_Type' = [Remittance_Type] ---added remittance type
				,'Audit_Amount' = SUM(CASE WHEN  (Reporting_Jurisdiction_Type = 'county' AND Reporting_Jurisdiction_Name <> 'all')
											THEN [County Tax On Margin Due]
											WHEN (Reporting_Jurisdiction_Type = 'city' AND Reporting_Jurisdiction_Name <> 'all')
											THEN [City Tax On Margin Due] 			
											WHEN Reporting_Jurisdiction_Type = 'state'
											THEN [State Tax On Margin Due]
											WHEN Reporting_Jurisdiction_Type = 'get'
											THEN [Get Tax On Margin Due]
											WHEN (Reporting_Jurisdiction_Type = 'all' OR Reporting_Jurisdiction_Name = 'all')
											THEN [Total Tax On Margin Due]
											END)
				,'Audit_ReportDate' = MAX([REPORTENDDATE]) 
									 									
		FROM #TempAuditNY
		WHERE 	(CASE WHEN @Negative_Margin_ExclusionNY = 'Y' AND (CASE WHEN NetNegFlag = 'N' -----these are the trans that are do NOT net to a negative for the month
																									-----so they can be INCLUDED for those special jurisdictions
																			THEN 'NetPositive' 
																			ELSE 'NetNegative' 
																			END) = 'NetPositive'
								THEN 'Y'
								ELSE 'N'
								END	) = @Negative_Margin_ExclusionNY
		GROUP BY 
				[LGL_ENTITY_CODE]
				,(CASE WHEN [TRANS_TYP_NAME] = 'Cost Adjustment'
									  THEN 'Breakage'
									  ELSE 'Compliance'
									  END)
				,Jurisdiction_State
				,Reporting_Jurisdiction_Name
				,Reporting_Jurisdiction_Type
				,[Remittance_Type])x ---added remittance type	

		-----Insert High Level Reconciliation Numbers, into table

		IF EXISTS 
			(SELECT 'ComparedAmounts' = SUM(ISNULL(Audit_Amount, 0) - ISNULL(JE_Amount,0))
			 FROM #Audit_ComparisonTempNY a
			 LEFT JOIN #JE_ComparisonTempNY j ON a.Audit_Company = j.JE_Company 
												AND a.Audit_Description = j.JE_Description
												AND a.Audit_Jurisdiction_State = j.JE_JurisdictionState
												AND a.Audit_Jurisdiction_Name = j.JE_JurisdictionName
												AND a.Audit_Jurisdiction_Type = j.JE_JurisdictionType
			 HAVING SUM(ISNULL((Audit_Amount - JE_Amount), 0)) BETWEEN -2 AND 2)	--------------2 dollar buffer								

			INSERT INTO Reconciliation.LodgingComparison
					([Audit_Company]
					  ,[Audit_Description]
					  ,[Audit_Jurisdiction_State]
					  ,[Audit_Jurisdiction_Name]
					  ,[Audit_Jurisdiction_Type]
					  ,[Audit_Remittance_Type] ---added remittance type
					  ,[Audit_Amount]
					  ,[Audit_ReportDate]
					  ,[JE_Company]
					  ,[JE_Description]
					  ,[JE_JurisdictionState]
					  ,[JE_JurisdictionName]
					  ,[JE_JurisdictionType]
					  ,[JE_Remittance_Type]---added remittance type
					  ,[JE_Amount]
					  ,[JE_ReportDate]
					  ,[ComparedAmounts]
					  ,[InsertedDate])

			SELECT	 Audit_Company
					,Audit_Description
					,Audit_Jurisdiction_State
					,Audit_Jurisdiction_Name
					,Audit_Jurisdiction_Type
					,[Audit_Remittance_Type] ---added remittance type
					,Audit_Amount
					,Audit_ReportDate
					,JE_Company
					,JE_Description
					,JE_JurisdictionState
					,JE_JurisdictionName
					,JE_JurisdictionType
					,[Audit_Remittance_Type] ---added remittance type --this will be equivalent for the margin model passing through this section, one at a time
					,JE_Amount
					,JE_ReportDate
					,'ComparedAmounts' = ISNULL(Audit_Amount, 0) - ISNULL(JE_Amount,0)
					,'InsertedDate' = GETDATE()
			 
			FROM #Audit_ComparisonTempNY a
			LEFT JOIN #JE_ComparisonTempNY j ON a.Audit_Company = j.JE_Company 
												AND a.Audit_Description = j.JE_Description
												AND a.Audit_Jurisdiction_State = j.JE_JurisdictionState
												AND a.Audit_Jurisdiction_Name = j.JE_JurisdictionName
												AND a.Audit_Jurisdiction_Type = j.JE_JurisdictionType
		ELSE 
		INSERT INTO Reconciliation.[LodgingComparison_Errors] 
		( [Audit_Company]
		  ,[Audit_Description]
		  ,[Audit_Jurisdiction_State]
		  ,[Audit_Jurisdiction_Name]
		  ,[Audit_Jurisdiction_Type]
		  ,[Audit_Remittance_Type] ---added remittance type
		  ,[Audit_Amount]
		  ,[Audit_ReportDate]
		  ,[JE_Company]
		  ,[JE_Description]
		  ,[JE_JurisdictionState]
		  ,[JE_JurisdictionName]
		  ,[JE_JurisdictionType]
		  ,[JE_Remittance_Type] ---added remittance type
		  ,[JE_Amount]
		  ,[JE_ReportDate]
		  ,[ComparedAmounts]
		  ,[InsertedDate]
		  ,[Note])
		(SELECT Audit_Company
				,Audit_Description
				,Audit_Jurisdiction_State
				,Audit_Jurisdiction_Name
				,Audit_Jurisdiction_Type
				,[Audit_Remittance_Type] ---added remittance type
				,Audit_Amount
				,Audit_ReportDate
				,JE_Company
				,JE_Description
				,JE_JurisdictionState
				,JE_JurisdictionName
				,JE_JurisdictionType
				,[Audit_Remittance_Type] ---added remittance type --this will be equivalent for the margin model passing through this section, one at a time
				,JE_Amount
				,JE_ReportDate
				,'ComparedAmounts' = ISNULL(Audit_Amount, 0) - ISNULL(JE_Amount,0)
				,'InsertedDate' = GETDATE()
				,'Note' = 'Does Not Match'
		FROM #Audit_ComparisonTempNY a
			LEFT JOIN #JE_ComparisonTempNY j ON a.Audit_Company = j.JE_Company 
												AND a.Audit_Description = j.JE_Description
												AND a.Audit_Jurisdiction_State = j.JE_JurisdictionState
												AND a.Audit_Jurisdiction_Name = j.JE_JurisdictionName
												AND a.Audit_Jurisdiction_Type = j.JE_JurisdictionType  )									
											
		--------------------------------------
		----take data from the temp tables, and insert into real tables (these will be the detailed tables)

		INSERT INTO Filed.LodgingCompliance	SELECT * FROM #TempAuditNY
		INSERT INTO Filed.Lodging_JE		SELECT * FROM #TempJENY
		INSERT INTO Filed.Lodging_JE_15330	SELECT * FROM #TempJE_15330NY
		
		IF OBJECT_ID('tempdb..#TempAuditNY')			IS NOT NULL DROP TABLE #TempAuditNY;
		IF OBJECT_ID('tempdb..#TempJENY')				IS NOT NULL DROP TABLE #TempJENY;
		IF OBJECT_ID('tempdb..#TempJE_15330NY')			IS NOT NULL DROP TABLE #TempJE_15330NY;
		IF OBJECT_ID('tempdb..#Audit_ComparisonTempNY') IS NOT NULL DROP TABLE #Audit_ComparisonTempNY;
		IF OBJECT_ID('tempdb..#JE_ComparisonTempNY')	IS NOT NULL DROP TABLE #JE_ComparisonTempNY;

-------------------------------------------------------------------------------------------------------------------------------------


SET @RankingMinNY = @RankingMinNY + 1 --------this helps the loop continue upwards in count
END 
END; ---end the third loop


---------------------------------------------------------------------------------
--#4----TO BEGIN THE FOURTH LOOPING JOB (ADJ_PRICE) 
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
BEGIN 
DECLARE @List4 table (Ranking INT, Jurisdiction_State VARCHAR(5), [Reporting_Jurisdiction_Name] VARCHAR(50),[Reporting_Jurisdiction_Type] VARCHAR(50),[Remittance_Type] VARCHAR(50)  )---added remittance type

INSERT INTO @List4
	SELECT 'Ranking' = RANK () OVER ( PARTITION BY TaxBaseFieldName ORDER BY [Jurisdiction_State], [Reporting_Jurisdiction_Name], [Reporting_Jurisdiction_Type],[Remittance_Type]),---added remittance type
		   Jurisdiction_State, [Reporting_Jurisdiction_Name], [Reporting_Jurisdiction_Type],[Remittance_Type]---added remittance type
	FROM [Compliance].[lkup].[LodgingCompliance]
	WHERE TaxBaseFieldName = 'ADJ_PRICE'
	ORDER BY Ranking


---------------------------------------------------------------------------------


DECLARE @RankingMin4	INT,
		@RankingMax4	INT,
		@State4			VARCHAR(50),
		@Name4			VARCHAR(50),
		@Type4			VARCHAR(50),
		@RemitType4		VARCHAR(50),---added remittance type
		@Negative_Margin_Exclusion4 VARCHAR(1);

SELECT @RankingMin4 = MIN(Ranking), @RankingMax4 = MAX(Ranking)  FROM @List4 WHILE @RankingMin4 <= @RankingMax4  ----this sets up the loop at the beginning count (1)
--------------------------------
------OR/SC
--------------------------------
BEGIN		
		
		---compile compliance AUDIT data - put into a temp table (more efficient to put data into temp and then into table, instead of straight into a table)
		SELECT @State4	= (SELECT Jurisdiction_State			FROM @List4 WHERE Ranking = @RankingMin4)
		SELECT @Name4	= (SELECT Reporting_Jurisdiction_Name	FROM @List4 WHERE Ranking = @RankingMin4)
		SELECT @Type4	= (SELECT Reporting_Jurisdiction_Type	FROM @List4 WHERE Ranking = @RankingMin4)
		SELECT @RemitType4	= (SELECT [Remittance_Type]			FROM @List4 WHERE Ranking = @RankingMin4) ---added remittance type
		SET @Negative_Margin_Exclusion4 = (SELECT Negative_Margin_Exclusion
										  FROM   lkup.LodgingCompliance 
										  WHERE  Jurisdiction_State = @State4
										  AND Reporting_Jurisdiction_Name = @Name4
										  AND Reporting_Jurisdiction_Type = @Type4
										  AND [Remittance_Type] = @RemitType4);---added remittance type

			
				
		SELECT * INTO #TempAudit4			FROM (SELECT * FROM Compliance.[F_Audit_ADJ_PRICE]		(@State4,@Name4,@Type4,@RemitType4) )x
		SELECT * INTO #TempJE4				FROM (SELECT * FROM Compliance.[F_JE_ADJ_PRICE]			(@State4,@Name4,@Type4,@RemitType4) )x
		SELECT * INTO #TempJE_153304		FROM (SELECT * FROM Compliance.[F_JE15330_ADJ_PRICE]	(@State4,@Name4,@Type4,@RemitType4) )x 
		----------------------------------------------------------------------------------------

		----------------------------------------------------------------------------------------
		--------------------
		----RECONCILIATION between Compliance and JE's details - then compile and insert the reconciliation into table
		--------------------


		SELECT * INTO #JE_ComparisonTemp4 FROM 
		----Compile Expense Side of JE Data from temp tables
		(SELECT DISTINCT  'JE_Company' = Company
						 ,'JE_Description' =  'Compliance'
						 ,'JE_JurisdictionState' = PARSENAME([Description], 4)
						 ,'JE_JurisdictionName'  = PARSENAME([Description], 3)
						 ,'JE_JurisdictionType'  = substring(PARSENAME([Description], 2), 1, charindex('_', PARSENAME([Description], 2))-1)
						 ,'JE_Amount' = SUM(Debit - Credit)
						 ,'JE_ReportDate' = ISNULL([Accounting Date],(SELECT MAX([Accounting Date]) FROM #TempJE4))
		FROM #TempJE4
		WHERE LEFT(Account, 4) <> 2088
			AND PARSENAME([Description], 1) NOT LIKE '%FlatTax%' ---added this here so that the flat taxes can be reconcilled separately
		GROUP BY Company
				 ,PARSENAME([Description], 4)
				 ,PARSENAME([Description], 3)
				 ,substring(PARSENAME([Description], 2), 1, charindex('_', PARSENAME([Description], 2))-1)
				 ,[Accounting Date]
		UNION ALL 
		SELECT DISTINCT   Company
						 ,'Compliance'
						 ,PARSENAME([Description], 4)
						 ,PARSENAME([Description], 3)
						 ,substring(PARSENAME([Description], 2), 1, charindex('_', PARSENAME([Description], 2))-1)
						 ,SUM(Debit - Credit)
						 ,[Accounting Date]
		FROM #TempJE_153304
		WHERE LEFT(Account, 4) <> 2088
			AND PARSENAME([Description], 1) NOT LIKE '%FlatTax%' ---added this here so that the flat taxes can be reconcilled separately
		GROUP BY Company
				 ,PARSENAME([Description], 4)
				 ,PARSENAME([Description], 3)
				 ,substring(PARSENAME([Description], 2), 1, charindex('_', PARSENAME([Description], 2))-1)
				 ,[Accounting Date])x 

		--Compare the Audit Files with the JE's 


		SELECT * INTO #Audit_ComparisonTemp4 FROM 
		(SELECT  'Audit_Company' = [LGL_ENTITY_CODE]
				,'Audit_Description' = 'Compliance'
				,'Audit_Jurisdiction_State' = Jurisdiction_State
				,'Audit_Jurisdiction_Name' = Reporting_Jurisdiction_Name
				,'Audit_Jurisdiction_Type' = Reporting_Jurisdiction_Type
				,'Audit_Remittance_Type' = [Remittance_Type] ---added remittance type
				,'Audit_Amount' = SUM(CASE WHEN  (Reporting_Jurisdiction_Type = 'county' )
											THEN [County Tax On Margin Due]
											WHEN (Reporting_Jurisdiction_Type = 'city' )
											THEN [City Tax On Margin Due] 			
											WHEN Reporting_Jurisdiction_Type = 'state'
											THEN [State Tax On Margin Due]
											WHEN Reporting_Jurisdiction_Type = 'get'
											THEN [Get Tax On Margin Due]
											WHEN (Reporting_Jurisdiction_Type = 'all' )
											THEN [Total Tax On Margin Due]
											END)
				,'Audit_ReportDate' = MAX([REPORTENDDATE])
									 									
		FROM #TempAudit4
		WHERE 	(CASE WHEN @Negative_Margin_Exclusion4 = 'Y' AND (CASE WHEN NetNegFlag = 'N' -----these are the trans that are do NOT net to a negative for the month
																									-----so they can be INCLUDED for those special jurisdictions
																			THEN 'NetPositive' 
																			ELSE 'NetNegative' 
																			END) = 'NetPositive'
								THEN 'Y'
								ELSE 'N'
								END	) = @Negative_Margin_Exclusion4
		GROUP BY 
				[LGL_ENTITY_CODE]
				,Jurisdiction_State
				,Reporting_Jurisdiction_Name
				,Reporting_Jurisdiction_Type
				,[Remittance_Type])x ---added remittance type	

		-----Insert High Level Reconciliation Numbers, into table

		IF EXISTS 
			(SELECT 'ComparedAmounts' = SUM(ISNULL(Audit_Amount, 0) - ISNULL(JE_Amount,0))
			 FROM #Audit_ComparisonTemp4 a
			 LEFT JOIN #JE_ComparisonTemp4 j ON a.Audit_Company = j.JE_Company 
												AND a.Audit_Description = j.JE_Description
												AND a.Audit_Jurisdiction_State = j.JE_JurisdictionState
												AND a.Audit_Jurisdiction_Name = j.JE_JurisdictionName
												AND a.Audit_Jurisdiction_Type = j.JE_JurisdictionType
			 HAVING SUM(ISNULL((Audit_Amount - JE_Amount), 0)) BETWEEN -2 AND 2)	--------------2 dollar buffer								

			INSERT INTO Reconciliation.LodgingComparison
					([Audit_Company]
					  ,[Audit_Description]
					  ,[Audit_Jurisdiction_State]
					  ,[Audit_Jurisdiction_Name]
					  ,[Audit_Jurisdiction_Type]
					  ,[Audit_Remittance_Type] ---added remittance type
					  ,[Audit_Amount]
					  ,[Audit_ReportDate]
					  ,[JE_Company]
					  ,[JE_Description]
					  ,[JE_JurisdictionState]
					  ,[JE_JurisdictionName]
					  ,[JE_JurisdictionType]
					  ,[JE_Remittance_Type]---added remittance type
					  ,[JE_Amount]
					  ,[JE_ReportDate]
					  ,[ComparedAmounts]
					  ,[InsertedDate])

			SELECT	 Audit_Company
					,Audit_Description
					,Audit_Jurisdiction_State
					,Audit_Jurisdiction_Name
					,Audit_Jurisdiction_Type
					,[Audit_Remittance_Type] ---added remittance type
					,Audit_Amount
					,Audit_ReportDate
					,JE_Company
					,JE_Description
					,JE_JurisdictionState
					,JE_JurisdictionName
					,JE_JurisdictionType
					,[Audit_Remittance_Type] ---added remittance type --this will be equivalent for the margin model passing through this section, one at a time
					,JE_Amount
					,JE_ReportDate
					,'ComparedAmounts' = ISNULL(Audit_Amount, 0) - ISNULL(JE_Amount,0)
					,'InsertedDate' = GETDATE()
			 
			FROM #Audit_ComparisonTemp4 a
			LEFT JOIN #JE_ComparisonTemp4 j ON a.Audit_Company = j.JE_Company 
												AND a.Audit_Description = j.JE_Description
												AND a.Audit_Jurisdiction_State = j.JE_JurisdictionState
												AND a.Audit_Jurisdiction_Name = j.JE_JurisdictionName
												AND a.Audit_Jurisdiction_Type = j.JE_JurisdictionType
		ELSE 
		INSERT INTO Reconciliation.[LodgingComparison_Errors] 
		( [Audit_Company]
		  ,[Audit_Description]
		  ,[Audit_Jurisdiction_State]
		  ,[Audit_Jurisdiction_Name]
		  ,[Audit_Jurisdiction_Type]
		  ,[Audit_Remittance_Type] ---added remittance type
		  ,[Audit_Amount]
		  ,[Audit_ReportDate]
		  ,[JE_Company]
		  ,[JE_Description]
		  ,[JE_JurisdictionState]
		  ,[JE_JurisdictionName]
		  ,[JE_JurisdictionType]
		  ,[JE_Remittance_Type] ---added remittance type
		  ,[JE_Amount]
		  ,[JE_ReportDate]
		  ,[ComparedAmounts]
		  ,[InsertedDate]
		  ,[Note])
		(SELECT Audit_Company
				,Audit_Description
				,Audit_Jurisdiction_State
				,Audit_Jurisdiction_Name
				,Audit_Jurisdiction_Type
				,[Audit_Remittance_Type] ---added remittance type
				,Audit_Amount
				,Audit_ReportDate
				,JE_Company
				,JE_Description
				,JE_JurisdictionState
				,JE_JurisdictionName
				,JE_JurisdictionType
				,[Audit_Remittance_Type] ---added remittance type --this will be equivalent for the margin model passing through this section, one at a time
				,JE_Amount
				,JE_ReportDate
				,'ComparedAmounts' = ISNULL(Audit_Amount, 0) - ISNULL(JE_Amount,0)
				,'InsertedDate' = GETDATE()
				,'Note' = 'Does Not Match'
		FROM #Audit_ComparisonTemp4 a
			LEFT JOIN #JE_ComparisonTemp4 j ON a.Audit_Company = j.JE_Company 
												AND a.Audit_Description = j.JE_Description
												AND a.Audit_Jurisdiction_State = j.JE_JurisdictionState
												AND a.Audit_Jurisdiction_Name = j.JE_JurisdictionName
												AND a.Audit_Jurisdiction_Type = j.JE_JurisdictionType  )									
											
		--------------------------------------
		----take data from the temp tables, and insert into real tables (these will be the detailed tables)
		
		IF OBJECT_ID('tempdb..#Audit_ComparisonTemp4')	IS NOT NULL DROP TABLE #Audit_ComparisonTemp4;
		IF OBJECT_ID('tempdb..#JE_ComparisonTemp4')		IS NOT NULL DROP TABLE #JE_ComparisonTemp4;

-------------------------------------------------------------------------------------------------------------------------------------
--now do the reconciliation for the flat taxes portion of the compliance report and the JE's

		--------------------
		----RECONCILIATION between Compliance and JE's details - then compile and insert the reconciliation into table
		--------------------


		SELECT * INTO #JE_ComparisonTempFlat4 FROM 
		----Compile Expense Side of JE Data from temp tables
		(SELECT DISTINCT  'JE_Company' = Company
						 ,'JE_Description' =  'FlatTaxes'
						 ,'JE_JurisdictionState' = PARSENAME([Description], 4)
						 ,'JE_JurisdictionName'  = PARSENAME([Description], 3)
						 ,'JE_JurisdictionType'  = substring(PARSENAME([Description], 2), 1, charindex('_', PARSENAME([Description], 2))-1)
						 ,'JE_Amount' = SUM(Debit - Credit)
						 ,'JE_ReportDate' = ISNULL([Accounting Date],(SELECT MAX([Accounting Date]) FROM #TempJE4))
		FROM #TempJE4
		WHERE LEFT(Account, 4) <> 2088
			AND PARSENAME([Description], 1) LIKE '%FlatTax%' ---added this here so that the flat taxes can be reconcilled separately
		GROUP BY Company
				 ,PARSENAME([Description], 4)
				 ,PARSENAME([Description], 3)
				 ,substring(PARSENAME([Description], 2), 1, charindex('_', PARSENAME([Description], 2))-1)
				 ,[Accounting Date]
		UNION ALL 
		SELECT DISTINCT   Company
						 ,'FlatTaxes'
						 ,PARSENAME([Description], 4)
						 ,PARSENAME([Description], 3)
						 ,substring(PARSENAME([Description], 2), 1, charindex('_', PARSENAME([Description], 2))-1)
						 ,SUM(Debit - Credit)
						 ,[Accounting Date]
		FROM #TempJE_153304
		WHERE LEFT(Account, 4) <> 2088
			AND PARSENAME([Description], 1) LIKE '%FlatTax%' ---added this here so that the flat taxes can be reconcilled separately
		GROUP BY Company
				 ,PARSENAME([Description], 4)
				 ,PARSENAME([Description], 3)
				 ,substring(PARSENAME([Description], 2), 1, charindex('_', PARSENAME([Description], 2))-1)
				 ,[Accounting Date])x 

		--Compare the Audit Files with the JE's 


		SELECT * INTO #Audit_ComparisonTempFlat4 FROM 
		(SELECT  'Audit_Company' = [LGL_ENTITY_CODE]
				,'Audit_Description' = 'FlatTaxes'
				,'Audit_Jurisdiction_State' = Jurisdiction_State
				,'Audit_Jurisdiction_Name' = Reporting_Jurisdiction_Name
				,'Audit_Jurisdiction_Type' = Reporting_Jurisdiction_Type
				,'Audit_Remittance_Type' = [Remittance_Type] ---added remittance type
				,'Audit_Amount' = SUM(Flat_Tax_Amount_Due)
				,'Audit_ReportDate' = MAX([REPORTENDDATE])
									 									
		FROM #TempAudit4
		WHERE 	(CASE WHEN @Negative_Margin_Exclusion4 = 'Y' AND (CASE WHEN NetNegFlag = 'N' -----these are the trans that are do NOT net to a negative for the month
																									-----so they can be INCLUDED for those special jurisdictions
																			THEN 'NetPositive' 
																			ELSE 'NetNegative' 
																			END) = 'NetPositive'
								THEN 'Y'
								ELSE 'N'
								END	) = @Negative_Margin_Exclusion4
		GROUP BY 
				[LGL_ENTITY_CODE]
				,Jurisdiction_State
				,Reporting_Jurisdiction_Name
				,Reporting_Jurisdiction_Type
				,[Remittance_Type])x ---added remittance type	

		-----Insert High Level Reconciliation Numbers, into table

		IF EXISTS 
			(SELECT 'ComparedAmounts' = SUM(ISNULL(Audit_Amount, 0) - ISNULL(JE_Amount,0))
			 FROM #Audit_ComparisonTempFlat4 a
			 LEFT JOIN #JE_ComparisonTempFlat4 j ON a.Audit_Company = j.JE_Company 
													AND a.Audit_Description = j.JE_Description
													AND a.Audit_Jurisdiction_State = j.JE_JurisdictionState
													AND a.Audit_Jurisdiction_Name = j.JE_JurisdictionName
													AND a.Audit_Jurisdiction_Type = j.JE_JurisdictionType
			 HAVING SUM(ISNULL((Audit_Amount - JE_Amount), 0)) BETWEEN -2 AND 2)	--------------2 dollar buffer								

			INSERT INTO Reconciliation.LodgingComparison
					([Audit_Company]
					  ,[Audit_Description]
					  ,[Audit_Jurisdiction_State]
					  ,[Audit_Jurisdiction_Name]
					  ,[Audit_Jurisdiction_Type]
					  ,[Audit_Remittance_Type] ---added remittance type
					  ,[Audit_Amount]
					  ,[Audit_ReportDate]
					  ,[JE_Company]
					  ,[JE_Description]
					  ,[JE_JurisdictionState]
					  ,[JE_JurisdictionName]
					  ,[JE_JurisdictionType]
					  ,[JE_Remittance_Type]---added remittance type
					  ,[JE_Amount]
					  ,[JE_ReportDate]
					  ,[ComparedAmounts]
					  ,[InsertedDate])

			SELECT	 Audit_Company
					,Audit_Description
					,Audit_Jurisdiction_State
					,Audit_Jurisdiction_Name
					,Audit_Jurisdiction_Type
					,[Audit_Remittance_Type] ---added remittance type
					,Audit_Amount
					,Audit_ReportDate
					,JE_Company
					,JE_Description
					,JE_JurisdictionState
					,JE_JurisdictionName
					,JE_JurisdictionType
					,[Audit_Remittance_Type] ---added remittance type --this will be equivalent for the margin model passing through this section, one at a time
					,JE_Amount
					,JE_ReportDate
					,'ComparedAmounts' = ISNULL(Audit_Amount, 0) - ISNULL(JE_Amount,0)
					,'InsertedDate' = GETDATE()
			 
			FROM #Audit_ComparisonTempFlat4 a
			LEFT JOIN #JE_ComparisonTempFlat4 j ON a.Audit_Company = j.JE_Company 
												AND a.Audit_Description = j.JE_Description
												AND a.Audit_Jurisdiction_State = j.JE_JurisdictionState
												AND a.Audit_Jurisdiction_Name = j.JE_JurisdictionName
												AND a.Audit_Jurisdiction_Type = j.JE_JurisdictionType
		ELSE 
		INSERT INTO Reconciliation.[LodgingComparison_Errors] 
		( [Audit_Company]
		  ,[Audit_Description]
		  ,[Audit_Jurisdiction_State]
		  ,[Audit_Jurisdiction_Name]
		  ,[Audit_Jurisdiction_Type]
		  ,[Audit_Remittance_Type] ---added remittance type
		  ,[Audit_Amount]
		  ,[Audit_ReportDate]
		  ,[JE_Company]
		  ,[JE_Description]
		  ,[JE_JurisdictionState]
		  ,[JE_JurisdictionName]
		  ,[JE_JurisdictionType]
		  ,[JE_Remittance_Type] ---added remittance type
		  ,[JE_Amount]
		  ,[JE_ReportDate]
		  ,[ComparedAmounts]
		  ,[InsertedDate]
		  ,[Note])
		(SELECT Audit_Company
				,Audit_Description
				,Audit_Jurisdiction_State
				,Audit_Jurisdiction_Name
				,Audit_Jurisdiction_Type
				,[Audit_Remittance_Type] ---added remittance type
				,Audit_Amount
				,Audit_ReportDate
				,JE_Company
				,JE_Description
				,JE_JurisdictionState
				,JE_JurisdictionName
				,JE_JurisdictionType
				,[Audit_Remittance_Type] ---added remittance type --this will be equivalent for the margin model passing through this section, one at a time
				,JE_Amount
				,JE_ReportDate
				,'ComparedAmounts' = ISNULL(Audit_Amount, 0) - ISNULL(JE_Amount,0)
				,'InsertedDate' = GETDATE()
				,'Note' = 'Does Not Match'
		FROM #Audit_ComparisonTempFlat4 a
			LEFT JOIN #JE_ComparisonTempFlat4 j ON a.Audit_Company = j.JE_Company 
												AND a.Audit_Description = j.JE_Description
												AND a.Audit_Jurisdiction_State = j.JE_JurisdictionState
												AND a.Audit_Jurisdiction_Name = j.JE_JurisdictionName
												AND a.Audit_Jurisdiction_Type = j.JE_JurisdictionType  )									
											
		--------------------------------------
		----take data from the temp tables, and insert into real tables (these will be the detailed tables)

		INSERT INTO Filed.LodgingCompliance					SELECT * FROM #TempAudit4
		INSERT INTO Filed.Lodging_JE						SELECT * FROM #TempJE4
		INSERT INTO Filed.Lodging_JE_15330					SELECT * FROM #TempJE_153304 
		
		IF OBJECT_ID('tempdb..#TempAudit4')					IS NOT NULL DROP TABLE #TempAudit4;
		IF OBJECT_ID('tempdb..#TempJE4')					IS NOT NULL DROP TABLE #TempJE4;
		IF OBJECT_ID('tempdb..#TempJE_153304')				IS NOT NULL DROP TABLE #TempJE_153304;
		IF OBJECT_ID('tempdb..#Audit_ComparisonTempFlat4')	IS NOT NULL DROP TABLE #Audit_ComparisonTempFlat4;
		IF OBJECT_ID('tempdb..#JE_ComparisonTempFlat4')		IS NOT NULL DROP TABLE #JE_ComparisonTempFlat4;


		

SET @RankingMin4 = @RankingMin4 + 1 --------this helps the loop continue upwards in count
END 
END ---end the fourth loop

---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
--#5----TO BEGIN THE FIFTH LOOPING JOB (ADJ_PRICE-ADJ_COST_GA) 
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
BEGIN 
DECLARE @List5 table (Ranking INT, Jurisdiction_State VARCHAR(5), [Reporting_Jurisdiction_Name] VARCHAR(50),[Reporting_Jurisdiction_Type] VARCHAR(50), [Remittance_Type] VARCHAR(50)  )---added remittance type

INSERT INTO @List5
	SELECT 'Ranking' = RANK () OVER ( PARTITION BY TaxBaseFieldName ORDER BY [Jurisdiction_State], [Reporting_Jurisdiction_Name], [Reporting_Jurisdiction_Type], [Remittance_Type]),---added remittance type
		   Jurisdiction_State, [Reporting_Jurisdiction_Name], [Reporting_Jurisdiction_Type], [Remittance_Type]---added remittance type
	FROM [Compliance].[lkup].[LodgingCompliance]
	WHERE TaxBaseFieldName = 'ADJ_PRICE-ADJ_COST_GA'
	ORDER BY Ranking


---------------------------------------------------------------------------------


DECLARE @RankingMin5	INT,
		@RankingMax5	INT,
		@State5			VARCHAR(50),
		@Name5			VARCHAR(50),
		@Type5			VARCHAR(50),
		@RemitType5		VARCHAR(50),---added remittance type
		@Negative_Margin_Exclusion5 VARCHAR(1);

SELECT @RankingMin5 = MIN(Ranking), @RankingMax5 = MAX(Ranking)  FROM @List5 WHILE @RankingMin5 <= @RankingMax5  ----this sets up the loop at the beginning count (1)
--------------------------------
------WY
--------------------------------
BEGIN		
		
		---compile compliance AUDIT data - put into a temp table (more efficient to put data into temp and then into table, instead of straight into a table)
		SELECT @State5	= (SELECT Jurisdiction_State			FROM @List5 WHERE Ranking = @RankingMin5)
		SELECT @Name5	= (SELECT Reporting_Jurisdiction_Name	FROM @List5 WHERE Ranking = @RankingMin5)
		SELECT @Type5	= (SELECT Reporting_Jurisdiction_Type	FROM @List5 WHERE Ranking = @RankingMin5)
		SELECT @RemitType5	= (SELECT [Remittance_Type]			FROM @ListNY WHERE Ranking = @RankingMin5) ---added remittance type
		SET @Negative_Margin_Exclusion5 = (SELECT Negative_Margin_Exclusion
										  FROM   lkup.LodgingCompliance 
										  WHERE  Jurisdiction_State = @State5
										  AND Reporting_Jurisdiction_Name = @Name5
										  AND Reporting_Jurisdiction_Type = @Type5
										  AND [Remittance_Type] = @RemitType5);---added remittance type
		
		
		SELECT * INTO #TempAudit5			FROM (SELECT * FROM Compliance.[F_Audit_ADJ_PRICE-ADJ_COST_GA]		(@State5,@Name5,@Type5,@RemitType5) )x---added remittance type
		SELECT * INTO #TempJE5				FROM (SELECT * FROM Compliance.[F_JE_ADJ_PRICE-ADJ_COST_GA]			(@State5,@Name5,@Type5,@RemitType5) )x---added remittance type
		SELECT * INTO #TempJE_153305		FROM (SELECT * FROM Compliance.[F_JE15330_ADJ_PRICE-ADJ_COST_GA]	(@State5,@Name5,@Type5,@RemitType5) )x---added remittance type


		----------------------------------------------------------------------------------------
		--------------------
		----RECONCILIATION between Compliance and JE's details - then compile and insert the reconciliation into table
		--------------------


		SELECT * INTO #JE_ComparisonTemp5 FROM 
		----Compile Expense Side of JE Data from temp tables
		(SELECT DISTINCT  'JE_Company' = Company
						 ,'JE_Description' = CASE WHEN [Description] LIKE '%Brk%'
												  THEN 'Breakage'
												  WHEN [Description] NOT LIKE '%Brk%'
												  THEN 'Compliance'
												  END
						 ,'JE_JurisdictionState' = PARSENAME([Description], 4)
						 ,'JE_JurisdictionName'  = PARSENAME([Description], 3)
						 ,'JE_JurisdictionType'  = substring(PARSENAME([Description], 2), 1, charindex('_', PARSENAME([Description], 2))-1)
						 ,'JE_Amount' = SUM(Debit - Credit)
						 ,'JE_ReportDate' = ISNULL([Accounting Date],(SELECT MAX([Accounting Date]) FROM #TempJE5))
		FROM #TempJE5
		WHERE LEFT(Account, 4) <> 2088
		GROUP BY Company
				 ,(CASE WHEN [Description] LIKE '%Brk%'
												  THEN 'Breakage'
												  WHEN [Description] NOT LIKE '%Brk%'
												  THEN 'Compliance'
												  END)
				 ,PARSENAME([Description], 4)
				 ,PARSENAME([Description], 3)
				 ,substring(PARSENAME([Description], 2), 1, charindex('_', PARSENAME([Description], 2))-1)
				 ,[Accounting Date]
		UNION ALL 
		SELECT DISTINCT   Company
						 ,CASE WHEN [Description] LIKE '%Brk%'
												  THEN 'Breakage'
												  WHEN [Description] NOT LIKE '%Brk%'
												  THEN 'Compliance'
												  END
						 ,PARSENAME([Description], 4)
						 ,PARSENAME([Description], 3)
						 ,substring(PARSENAME([Description], 2), 1, charindex('_', PARSENAME([Description], 2))-1)
						 ,SUM(Debit - Credit)
						 ,[Accounting Date]
		FROM #TempJE_153305
		WHERE LEFT(Account, 4) <> 2088
		GROUP BY Company
				 ,(CASE WHEN [Description] LIKE '%Brk%'
												  THEN 'Breakage'
												  WHEN [Description] NOT LIKE '%Brk%'
												  THEN 'Compliance'
												  END)
				 ,PARSENAME([Description], 4)
				 ,PARSENAME([Description], 3)
				 ,substring(PARSENAME([Description], 2), 1, charindex('_', PARSENAME([Description], 2))-1)
				 ,[Accounting Date])x 

		--Compare the Audit Files with the JE's 


		SELECT * INTO #Audit_ComparisonTemp5 FROM 
		(SELECT  'Audit_Company' = [LGL_ENTITY_CODE]
				,'Audit_Description' = CASE WHEN [TRANS_TYP_NAME] = 'Cost Adjustment'
									  THEN 'Breakage'
									  ELSE 'Compliance'
									  END
				,'Audit_Jurisdiction_State' = Jurisdiction_State
				,'Audit_Jurisdiction_Name' = Reporting_Jurisdiction_Name
				,'Audit_Jurisdiction_Type' = Reporting_Jurisdiction_Type
				,'Audit_Remittance_Type' = [Remittance_Type] ---added remittance type
				,'Audit_Amount' = SUM(CASE WHEN  (Reporting_Jurisdiction_Type = 'county' AND Reporting_Jurisdiction_Name <> 'all')
											THEN [County Tax On Margin Due]
											WHEN (Reporting_Jurisdiction_Type = 'city' AND Reporting_Jurisdiction_Name <> 'all')
											THEN [City Tax On Margin Due] 			
											WHEN Reporting_Jurisdiction_Type = 'state'
											THEN [State Tax On Margin Due]
											WHEN Reporting_Jurisdiction_Type = 'get'
											THEN [Get Tax On Margin Due]
											WHEN (Reporting_Jurisdiction_Type = 'all' OR Reporting_Jurisdiction_Name = 'all')
											THEN [Total Tax On Margin Due]
											END)
				,'Audit_ReportDate' = MAX([REPORTENDDATE])
									 									
		FROM #TempAudit5
		WHERE 	(CASE WHEN @Negative_Margin_Exclusion5 = 'Y' AND (CASE WHEN NetNegFlag = 'N' -----these are the trans that are do NOT net to a negative for the month
																									-----so they can be INCLUDED for those special jurisdictions
																			THEN 'NetPositive' 
																			ELSE 'NetNegative' 
																			END) = 'NetPositive'
								THEN 'Y'
								ELSE 'N'
								END	) = @Negative_Margin_Exclusion5
		GROUP BY 
				[LGL_ENTITY_CODE]
				,(CASE WHEN [TRANS_TYP_NAME] = 'Cost Adjustment'
									  THEN 'Breakage'
									  ELSE 'Compliance'
									  END)
				,Jurisdiction_State
				,Reporting_Jurisdiction_Name
				,Reporting_Jurisdiction_Type
				,[Remittance_Type])x ---added remittance type	

		-----Insert High Level Reconciliation Numbers, into table

		IF EXISTS 
			(SELECT 'ComparedAmounts' = SUM(ISNULL(Audit_Amount, 0) - ISNULL(JE_Amount,0))
			 FROM #Audit_ComparisonTemp5 a
			 LEFT JOIN #JE_ComparisonTemp5 j ON a.Audit_Company = j.JE_Company 
												AND a.Audit_Description = j.JE_Description
												AND a.Audit_Jurisdiction_State = j.JE_JurisdictionState
												AND a.Audit_Jurisdiction_Name = j.JE_JurisdictionName
												AND a.Audit_Jurisdiction_Type = j.JE_JurisdictionType
			 HAVING SUM(ISNULL((Audit_Amount - JE_Amount), 0)) BETWEEN -2 AND 2)	--------------2 dollar buffer								

			INSERT INTO Reconciliation.LodgingComparison
					([Audit_Company]
					  ,[Audit_Description]
					  ,[Audit_Jurisdiction_State]
					  ,[Audit_Jurisdiction_Name]
					  ,[Audit_Jurisdiction_Type]
					  ,[Audit_Remittance_Type] ---added remittance type
					  ,[Audit_Amount]
					  ,[Audit_ReportDate]
					  ,[JE_Company]
					  ,[JE_Description]
					  ,[JE_JurisdictionState]
					  ,[JE_JurisdictionName]
					  ,[JE_JurisdictionType]
					  ,[JE_Remittance_Type]---added remittance type
					  ,[JE_Amount]
					  ,[JE_ReportDate]
					  ,[ComparedAmounts]
					  ,[InsertedDate])

			SELECT	 Audit_Company
					,Audit_Description
					,Audit_Jurisdiction_State
					,Audit_Jurisdiction_Name
					,Audit_Jurisdiction_Type
					,[Audit_Remittance_Type] ---added remittance type
					,Audit_Amount
					,Audit_ReportDate
					,JE_Company
					,JE_Description
					,JE_JurisdictionState
					,JE_JurisdictionName
					,JE_JurisdictionType
					,[Audit_Remittance_Type] ---added remittance type --this will be equivalent for the margin model passing through this section, one at a time
					,JE_Amount
					,JE_ReportDate
					,'ComparedAmounts' = ISNULL(Audit_Amount, 0) - ISNULL(JE_Amount,0)
					,'InsertedDate' = GETDATE()
			 
			FROM #Audit_ComparisonTemp5 a
			LEFT JOIN #JE_ComparisonTemp5 j ON a.Audit_Company = j.JE_Company 
												AND a.Audit_Description = j.JE_Description
												AND a.Audit_Jurisdiction_State = j.JE_JurisdictionState
												AND a.Audit_Jurisdiction_Name = j.JE_JurisdictionName
												AND a.Audit_Jurisdiction_Type = j.JE_JurisdictionType
		ELSE 
		INSERT INTO Reconciliation.[LodgingComparison_Errors] 
		( [Audit_Company]
		  ,[Audit_Description]
		  ,[Audit_Jurisdiction_State]
		  ,[Audit_Jurisdiction_Name]
		  ,[Audit_Jurisdiction_Type]
		  ,[Audit_Remittance_Type] ---added remittance type
		  ,[Audit_Amount]
		  ,[Audit_ReportDate]
		  ,[JE_Company]
		  ,[JE_Description]
		  ,[JE_JurisdictionState]
		  ,[JE_JurisdictionName]
		  ,[JE_JurisdictionType]
		  ,[JE_Remittance_Type] ---added remittance type
		  ,[JE_Amount]
		  ,[JE_ReportDate]
		  ,[ComparedAmounts]
		  ,[InsertedDate]
		  ,[Note])
		(SELECT Audit_Company
				,Audit_Description
				,Audit_Jurisdiction_State
				,Audit_Jurisdiction_Name
				,Audit_Jurisdiction_Type
				,[Audit_Remittance_Type] ---added remittance type
				,Audit_Amount
				,Audit_ReportDate
				,JE_Company
				,JE_Description
				,JE_JurisdictionState
				,JE_JurisdictionName
				,JE_JurisdictionType
				,[Audit_Remittance_Type] ---added remittance type --this will be equivalent for the margin model passing through this section, one at a time
				,JE_Amount
				,JE_ReportDate
				,'ComparedAmounts' = ISNULL(Audit_Amount, 0) - ISNULL(JE_Amount,0)
				,'InsertedDate' = GETDATE()
				,'Note' = 'Does Not Match'
		FROM #Audit_ComparisonTemp5 a
			LEFT JOIN #JE_ComparisonTemp5 j ON a.Audit_Company = j.JE_Company 
												AND a.Audit_Description = j.JE_Description
												AND a.Audit_Jurisdiction_State = j.JE_JurisdictionState
												AND a.Audit_Jurisdiction_Name = j.JE_JurisdictionName
												AND a.Audit_Jurisdiction_Type = j.JE_JurisdictionType  )									
											
		--------------------------------------
		----take data from the temp tables, and insert into real tables (these will be the detailed tables)

		INSERT INTO Filed.LodgingCompliance	SELECT * FROM #TempAudit5
		INSERT INTO Filed.Lodging_JE		SELECT * FROM #TempJE5
		INSERT INTO Filed.Lodging_JE_15330	SELECT * FROM #TempJE_153305
		
		IF OBJECT_ID('tempdb..#TempAudit5')				IS NOT NULL DROP TABLE #TempAudit5;
		IF OBJECT_ID('tempdb..#TempJE5')				IS NOT NULL DROP TABLE #TempJE5;
		IF OBJECT_ID('tempdb..#TempJE_153305')			IS NOT NULL DROP TABLE #TempJE_153305;
		IF OBJECT_ID('tempdb..#Audit_ComparisonTemp5')	IS NOT NULL DROP TABLE #Audit_ComparisonTemp5;
		IF OBJECT_ID('tempdb..#JE_ComparisonTemp5')		IS NOT NULL DROP TABLE #JE_ComparisonTemp5;

-------------------------------------------------------------------------------------------------------------------------------------


SET @RankingMin5 = @RankingMin5 + 1 --------this helps the loop continue upwards in count
END 
END ---end the fifth loop



END ---PROCEDURE

















GO
