USE [Compliance]
GO
/****** Object:  UserDefinedFunction [Compliance].[F_JE_ADJ_PRICE_GA-ADJ_COST_GA]    Script Date: 9/5/2017 10:47:49 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO



/*
---- =============================================
---- Author:		Tammy Lessley
---- Create date:	20151015
---- Description:	Template - Popular, for pulling fields needed to export desired jurisdictions.
---- =============================================
**************************
** Change History
**************************
** JIRA				Date       Author			Description 
** --				--------   -------			------------------------------------
** TAXSYSTEMS-633	20170608   Tammy Lessley	Insert extra fields to pick up the Remittance Type Change data and include the Remit Type Change Logic for those jurisdictions that have changes to remit type. 
*/

CREATE FUNCTION  [Compliance].[F_JE_ADJ_PRICE_GA-ADJ_COST_GA]
(
@Jurisdiction_State VARCHAR(50),
@Reporting_Jurisdiction_Name VARCHAR(50),
@Reporting_Jurisdiction_Type VARCHAR(50),
@Remittance_Type VARCHAR(50)		
)
RETURNS   @Temp TABLE (	[Upl] VARCHAR(5), 
						[Conversion Type] VARCHAR(20),
						[Conversion Date] DATE,
						[Conversion Rate] VARCHAR(20),
						[Ledger] VARCHAR(20),
						[Accounting Date] DATE,
						[Currency] VARCHAR(20),
						[Company] INT,
						[Account] VARCHAR(20),
						[Department] VARCHAR(20),
						[MGMT_UNIT_CODE] VARCHAR(20),
						[Office] VARCHAR(20),
						[Project] VARCHAR(20),
						[ORACLE_GL_PRODUCT_CODE] VARCHAR(20),
						[Intercompany] VARCHAR(20),
						[Future1] VARCHAR(20),
						[Future2] VARCHAR(20),
						[Debit] NUMERIC(38,6),
						[Credit] NUMERIC(38,6),
						[Converted Debit] VARCHAR(20), 
						[Converted Credit] VARCHAR(20),
						[Description] VARCHAR(500),
						[InsertedDate] DATETIME) 
AS
BEGIN

-----open these up to test
--DECLARE @Jurisdiction_State VARCHAR(50),
--		@Reporting_Jurisdiction_Name VARCHAR(50),
--		@Reporting_Jurisdiction_Type VARCHAR(50),
--		@Remittance_Type VARCHAR(50);
-----open these up to test

DECLARE	 @Liable_Date DATE,
		 @Liable_Date_YearMonth INT,
		 @Filing_Companies_Compliance VARCHAR(50),
		 @Filing_Companies_Breakage VARCHAR(50),
		 @NegativeMarginFieldName VARCHAR(150),
		 @Negative_Margin_Exclusion VARCHAR(1),
		 @PriceFieldName VARCHAR(50),
		 @CostFieldName VARCHAR(50),
		 @TaxBaseFieldName VARCHAR(100),
		 --@Remittance_Type VARCHAR(50), ---no longer needed down here. it will be fed in from the SProc that uses the table value functions
		 @Liable_Tax_Type VARCHAR(50),
		 @ReportEndDate DATE,
		 @ReportEndDate_MonthYear VARCHAR(50),
		 @Project_Compliance VARCHAR(6),
		 @Project_Breakage VARCHAR(6),
		 @ExpenseGLAccount_Compliance INT,
		 @ExpenseGLAccount_Breakage INT,
		 @LiabilityGLAccount INT,
		 @Tax_Type_Liable1 VARCHAR(50),
		 @Tax_Type_Liable1_Limitations VARCHAR(100),
		 @Tax_Type_Liable2 VARCHAR(50),
		 @Tax_Type_Liable2_Limitations VARCHAR(100); 

-----open this up to test - jurisdiction
--SET @Jurisdiction_State = 'DC';
--SET @Reporting_Jurisdiction_Name = 'DC';
--SET @Reporting_Jurisdiction_Type = 'city';
--SET @Remittance_Type = 'dual'
-----open this up to test - jurisdiction
												
SET @Filing_Companies_Compliance = (SELECT Filing_Companies_Compliance
									FROM   lkup.LodgingCompliance 
									WHERE  Jurisdiction_State = @Jurisdiction_State
									AND Reporting_Jurisdiction_Name = @Reporting_Jurisdiction_Name
									AND Reporting_Jurisdiction_Type = @Reporting_Jurisdiction_Type
									AND Remittance_Type = @Remittance_Type); 
SET @Filing_Companies_Breakage = (SELECT Filing_Companies_Breakage
								  FROM   lkup.LodgingCompliance 
							      WHERE  Jurisdiction_State = @Jurisdiction_State
							      AND Reporting_Jurisdiction_Name = @Reporting_Jurisdiction_Name
							      AND Reporting_Jurisdiction_Type = @Reporting_Jurisdiction_Type
								  AND Remittance_Type = @Remittance_Type); 								
SET @NegativeMarginFieldName = (SELECT NegativeMarginFieldName
								FROM   lkup.LodgingCompliance 
								WHERE  Jurisdiction_State = @Jurisdiction_State
								AND Reporting_Jurisdiction_Name = @Reporting_Jurisdiction_Name
								AND Reporting_Jurisdiction_Type = @Reporting_Jurisdiction_Type
								AND Remittance_Type = @Remittance_Type);									
SET @Negative_Margin_Exclusion = (SELECT Negative_Margin_Exclusion
								  FROM   lkup.LodgingCompliance 
								  WHERE  Jurisdiction_State = @Jurisdiction_State
								  AND Reporting_Jurisdiction_Name = @Reporting_Jurisdiction_Name
								  AND Reporting_Jurisdiction_Type = @Reporting_Jurisdiction_Type
								  AND Remittance_Type = @Remittance_Type);
SET @PriceFieldName = (SELECT PriceFieldName
					   FROM   lkup.LodgingCompliance 
					   WHERE  Jurisdiction_State = @Jurisdiction_State
					   AND Reporting_Jurisdiction_Name = @Reporting_Jurisdiction_Name
					   AND Reporting_Jurisdiction_Type = @Reporting_Jurisdiction_Type
					   AND Remittance_Type = @Remittance_Type);
SET @CostFieldName = (SELECT CostFieldName
					  FROM   lkup.LodgingCompliance 
					  WHERE  Jurisdiction_State = @Jurisdiction_State
					  AND Reporting_Jurisdiction_Name = @Reporting_Jurisdiction_Name
					  AND Reporting_Jurisdiction_Type = @Reporting_Jurisdiction_Type
					  AND Remittance_Type = @Remittance_Type);	
SET @TaxBaseFieldName = (SELECT TaxBaseFieldName
					     FROM   lkup.LodgingCompliance 
					     WHERE  Jurisdiction_State = @Jurisdiction_State
					     AND Reporting_Jurisdiction_Name = @Reporting_Jurisdiction_Name
					     AND Reporting_Jurisdiction_Type = @Reporting_Jurisdiction_Type
						 AND Remittance_Type = @Remittance_Type);	
SET @Remittance_Type = (SELECT Remittance_Type
					    FROM   lkup.LodgingCompliance 
					    WHERE  Jurisdiction_State = @Jurisdiction_State
					    AND Reporting_Jurisdiction_Name = @Reporting_Jurisdiction_Name
					    AND Reporting_Jurisdiction_Type = @Reporting_Jurisdiction_Type
						AND Remittance_Type = @Remittance_Type);
SET @Liable_Tax_Type = (SELECT Liable_Tax_Type
						FROM   lkup.LodgingCompliance 
						WHERE  Jurisdiction_State = @Jurisdiction_State
						AND Reporting_Jurisdiction_Name = @Reporting_Jurisdiction_Name
						AND Reporting_Jurisdiction_Type = @Reporting_Jurisdiction_Type
						AND Remittance_Type = @Remittance_Type);	
SET @ReportEndDate = (SELECT MAX(REPORTENDDATE)
					  FROM Lodging.MonthlyCalculatedData);
SET @ReportEndDate_MonthYear = (SELECT DATENAME(MONTH, MAX(REPORTENDDATE))+ CAST(YEAR(MAX(REPORTENDDATE)) AS VARCHAR)
								FROM Lodging.MonthlyCalculatedData)
SET @Project_Compliance = (SELECT GL_Project_Code
						   FROM   lkup.LodgingCompliance 
						   WHERE  Jurisdiction_State = @Jurisdiction_State
						   AND Reporting_Jurisdiction_Name = @Reporting_Jurisdiction_Name
						   AND Reporting_Jurisdiction_Type = @Reporting_Jurisdiction_Type
						   AND Remittance_Type = @Remittance_Type);	
SET @Project_Breakage = (SELECT GL_Project_Code_Breakage
						   FROM   lkup.LodgingCompliance 
						   WHERE  Jurisdiction_State = @Jurisdiction_State
						   AND Reporting_Jurisdiction_Name = @Reporting_Jurisdiction_Name
						   AND Reporting_Jurisdiction_Type = @Reporting_Jurisdiction_Type
						   AND Remittance_Type = @Remittance_Type);
SET @ExpenseGLAccount_Compliance = (SELECT Account	
									FROM lkup.ExpenseGLAccount		
									WHERE Filing_Companies_Compliance = @Filing_Companies_Compliance);	   						   													
SET @ExpenseGLAccount_Breakage = (SELECT Account	
									FROM lkup.ExpenseGLAccount		
									WHERE Filing_Companies_Compliance = @Filing_Companies_Breakage);
SET @LiabilityGLAccount = (SELECT GL_Liability_Account_Code
						   FROM   lkup.LodgingCompliance 
						   WHERE  Jurisdiction_State = @Jurisdiction_State
						   AND Reporting_Jurisdiction_Name = @Reporting_Jurisdiction_Name
						   AND Reporting_Jurisdiction_Type = @Reporting_Jurisdiction_Type
						   AND Remittance_Type = @Remittance_Type);
SET @Tax_Type_Liable1 = (SELECT Tax_Type_Liable1
						   FROM   lkup.LodgingCompliance 
						   WHERE  Jurisdiction_State = @Jurisdiction_State
							AND Reporting_Jurisdiction_Name = @Reporting_Jurisdiction_Name
							AND Reporting_Jurisdiction_Type = @Reporting_Jurisdiction_Type
							AND Remittance_Type = @Remittance_Type);
SET @Tax_Type_Liable1_Limitations = (SELECT Tax_Type_Liable1_Limitations 
									   FROM   lkup.LodgingCompliance 
									   WHERE  Jurisdiction_State = @Jurisdiction_State
										AND Reporting_Jurisdiction_Name = @Reporting_Jurisdiction_Name
										AND Reporting_Jurisdiction_Type = @Reporting_Jurisdiction_Type
										AND Remittance_Type = @Remittance_Type);							
SET @Tax_Type_Liable2 = (SELECT Tax_Type_Liable2 
						   FROM   lkup.LodgingCompliance 
						   WHERE  Jurisdiction_State = @Jurisdiction_State
							AND Reporting_Jurisdiction_Name = @Reporting_Jurisdiction_Name
							AND Reporting_Jurisdiction_Type = @Reporting_Jurisdiction_Type
							AND Remittance_Type = @Remittance_Type);	
SET @Tax_Type_Liable2_Limitations = (SELECT Tax_Type_Liable2_Limitations 
									   FROM   lkup.LodgingCompliance 
									   WHERE  Jurisdiction_State = @Jurisdiction_State
										AND Reporting_Jurisdiction_Name = @Reporting_Jurisdiction_Name
										AND Reporting_Jurisdiction_Type = @Reporting_Jurisdiction_Type
										AND Remittance_Type = @Remittance_Type);						   


INSERT INTO @Temp (	[Upl], 
					[Conversion Type],
					[Conversion Date],
					[Conversion Rate],
					[Ledger],
					[Accounting Date],
					[Currency],
					[Company],
					[Account],
					[Department],
					[MGMT_UNIT_CODE],
					[Office],
					[Project],
					[ORACLE_GL_PRODUCT_CODE],
					[Intercompany],
					[Future1],
					[Future2],
					[Debit],
					[Credit],
					[Converted Debit], 
					[Converted Credit],
					[Description],
					[InsertedDate])

			
			SELECT  ------Debit side of JE
					 'Upl' = ''
					,'Conversion Type' = 'Corporate'
					,'Conversion Date' = @ReportEndDate
					,'Conversion Rate' = ''
					,'Ledger' = CASE WHEN l.[LGL_ENTITY_CODE] IS NOT NULL
									 THEN l.Ledger
									 ELSE 'UNKNOWN'
									 END
					,'Accounting Date' = @ReportEndDate
					,'Currency' = 'USD'
					,'Company' = c.[LGL_ENTITY_CODE]
					,'Account' = CASE WHEN a.[MGMT_UNIT_CODE] IS NOT NULL
									  THEN a.[Account]
									  WHEN TRANS_TYP_NAME <> 'Cost Adjustment' 
									  THEN @ExpenseGLAccount_Compliance
									  WHEN TRANS_TYP_NAME = 'Cost Adjustment' 
									  THEN @ExpenseGLAccount_Breakage
									  END
					,'Department' = '00000'
					,'MGMT_UNIT_CODE' = CAST(c.MGMT_UNIT_CODE AS VARCHAR)
					,'Office' = '00000'
					,'Project' = '000000'
					,'ORACLE_GL_PRODUCT_CODE' = CAST(ORACLE_GL_PRODUCT_CODE AS VARCHAR)
					,'Intercompany' = '00000'
					,'Future1' = '00000'
					,'Future2' = '0000' 
					,'Debit' = CASE WHEN 
									   (SUM(CASE WHEN @Reporting_Jurisdiction_Type = 'county' AND @Reporting_Jurisdiction_Name <> 'all' AND (@Tax_Type_Liable1 IS NULL OR @Tax_Type_Liable2 IS NULL)
												THEN [County Tax On Margin Due]
												WHEN @Reporting_Jurisdiction_Type = 'city' AND @Reporting_Jurisdiction_Name <> 'all' AND (@Tax_Type_Liable1 IS NULL OR @Tax_Type_Liable2 IS NULL)
												THEN [City Tax On Margin Due]				
												WHEN @Reporting_Jurisdiction_Type = 'state'
												THEN [State Tax On Margin Due]
												WHEN @Reporting_Jurisdiction_Type = 'all' 
												THEN [Total Tax On Margin Due]
												WHEN @Reporting_Jurisdiction_Type = 'city' AND @Reporting_Jurisdiction_Name <> 'all' AND @Tax_Type_Liable1 = 'city' AND @Tax_Type_Liable2 = 'county'
												THEN [City Tax On Margin Due] + [County Tax On Margin Due] 
												END)) > 0
									THEN (SUM(CASE WHEN @Reporting_Jurisdiction_Type = 'county' AND @Reporting_Jurisdiction_Name <> 'all' AND (@Tax_Type_Liable1 IS NULL OR @Tax_Type_Liable2 IS NULL)
												THEN [County Tax On Margin Due]
												WHEN @Reporting_Jurisdiction_Type = 'city' AND @Reporting_Jurisdiction_Name <> 'all' AND (@Tax_Type_Liable1 IS NULL OR @Tax_Type_Liable2 IS NULL)
												THEN [City Tax On Margin Due]				
												WHEN @Reporting_Jurisdiction_Type = 'state'
												THEN [State Tax On Margin Due]
												WHEN @Reporting_Jurisdiction_Type = 'all' 
												THEN [Total Tax On Margin Due]
												WHEN @Reporting_Jurisdiction_Type = 'city' AND @Reporting_Jurisdiction_Name <> 'all' AND @Tax_Type_Liable1 = 'city' AND @Tax_Type_Liable2 = 'county'
												THEN [City Tax On Margin Due] + [County Tax On Margin Due] 
												END))
									ELSE 0
									END
					,'Credit' = CASE WHEN 
									   (SUM(CASE WHEN @Reporting_Jurisdiction_Type = 'county' AND @Reporting_Jurisdiction_Name <> 'all' AND (@Tax_Type_Liable1 IS NULL OR @Tax_Type_Liable2 IS NULL)
												THEN [County Tax On Margin Due]
												WHEN @Reporting_Jurisdiction_Type = 'city' AND @Reporting_Jurisdiction_Name <> 'all' AND (@Tax_Type_Liable1 IS NULL OR @Tax_Type_Liable2 IS NULL)
												THEN [City Tax On Margin Due]				
												WHEN @Reporting_Jurisdiction_Type = 'state'
												THEN [State Tax On Margin Due]
												WHEN @Reporting_Jurisdiction_Type = 'all' 
												THEN [Total Tax On Margin Due]
												WHEN @Reporting_Jurisdiction_Type = 'city' AND @Reporting_Jurisdiction_Name <> 'all' AND @Tax_Type_Liable1 = 'city' AND @Tax_Type_Liable2 = 'county'
												THEN [City Tax On Margin Due] + [County Tax On Margin Due] 
												END)) < 0
									THEN -(SUM(CASE WHEN @Reporting_Jurisdiction_Type = 'county' AND @Reporting_Jurisdiction_Name <> 'all' AND (@Tax_Type_Liable1 IS NULL OR @Tax_Type_Liable2 IS NULL)
												THEN [County Tax On Margin Due]
												WHEN @Reporting_Jurisdiction_Type = 'city' AND @Reporting_Jurisdiction_Name <> 'all' AND (@Tax_Type_Liable1 IS NULL OR @Tax_Type_Liable2 IS NULL)
												THEN [City Tax On Margin Due]				
												WHEN @Reporting_Jurisdiction_Type = 'state'
												THEN [State Tax On Margin Due]
												WHEN @Reporting_Jurisdiction_Type = 'all' 
												THEN [Total Tax On Margin Due]
												WHEN @Reporting_Jurisdiction_Type = 'city' AND @Reporting_Jurisdiction_Name <> 'all' AND @Tax_Type_Liable1 = 'city' AND @Tax_Type_Liable2 = 'county'
												THEN [City Tax On Margin Due] + [County Tax On Margin Due] 
												END))
									ELSE 0									
									END	
				   ,'Converted Debit' = ''
				   ,'Converted Credit' = ''
				   ,'Description' = CASE WHEN TRANS_TYP_NAME <> 'Cost Adjustment'
										 THEN @Jurisdiction_State + '.' + @Reporting_Jurisdiction_Name + '.' + @Reporting_Jurisdiction_Type + '_' + @Remittance_Type + '.Tax' + @ReportEndDate_MonthYear
										 WHEN TRANS_TYP_NAME = 'Cost Adjustment'
										 THEN @Jurisdiction_State + '.' + @Reporting_Jurisdiction_Name + '.' + @Reporting_Jurisdiction_Type + '_' + @Remittance_Type + '.BrkTax' + @ReportEndDate_MonthYear
										 END
				  ,'InsertedDate' = GETDATE()										 
										
										

			FROM Compliance.[F_Audit_ADJ_PRICE_GA-ADJ_COST_GA] (@Jurisdiction_State, @Reporting_Jurisdiction_Name, @Reporting_Jurisdiction_Type, @Remittance_Type) c
			LEFT JOIN lkup.Ledger l ON c.LGL_ENTITY_CODE = l.LGL_ENTITY_CODE
			LEFT JOIN lkup.AccountSpecialMU a ON c.[MGMT_UNIT_CODE] = a.[MGMT_UNIT_CODE]
			 
			WHERE c.[LGL_ENTITY_CODE] <> 15330
				AND (CASE WHEN @Negative_Margin_Exclusion = 'Y' AND (CASE WHEN NetNegFlag = 'N' -----these are the trans that are do NOT net to a negative for the month
																										-----so they can be INCLUDED for those special jurisdictions
																				THEN 'NetPositive' 
																				ELSE 'NetNegative' 
																				END) = 'NetPositive'
									THEN 'Y'
									ELSE 'N'
									END	) = @Negative_Margin_Exclusion
			GROUP BY c.[LGL_ENTITY_CODE]
					,c.MGMT_UNIT_CODE
					,ORACLE_GL_PRODUCT_CODE
					,(CASE WHEN TRANS_TYP_NAME <> 'Cost Adjustment'
									  THEN @Project_Compliance
									  WHEN TRANS_TYP_NAME = 'Cost Adjustment'
									  THEN @Project_Breakage
									  END)
					,(CASE WHEN TRANS_TYP_NAME <> 'Cost Adjustment'
										 THEN @Jurisdiction_State + '.' + @Reporting_Jurisdiction_Name + '.' + @Reporting_Jurisdiction_Type + '_' + @Remittance_Type + '.Tax' + @ReportEndDate_MonthYear
										 WHEN TRANS_TYP_NAME = 'Cost Adjustment'
										 THEN @Jurisdiction_State + '.' + @Reporting_Jurisdiction_Name + '.' + @Reporting_Jurisdiction_Type + '_' + @Remittance_Type + '.BrkTax' + @ReportEndDate_MonthYear
										 END)	
					,(CASE WHEN l.[LGL_ENTITY_CODE] IS NOT NULL
									 THEN l.Ledger
									 ELSE 'UNKNOWN'
									 END)	
					,(CASE WHEN a.[MGMT_UNIT_CODE] IS NOT NULL
									  THEN a.[Account]
									  WHEN TRANS_TYP_NAME <> 'Cost Adjustment' 
									  THEN @ExpenseGLAccount_Compliance
									  WHEN TRANS_TYP_NAME = 'Cost Adjustment' 
									  THEN @ExpenseGLAccount_Breakage
									  END)						 						 
										 		 
			HAVING (SUM(CASE WHEN @Reporting_Jurisdiction_Type = 'county' AND @Reporting_Jurisdiction_Name <> 'all' AND (@Tax_Type_Liable1 IS NULL OR @Tax_Type_Liable2 IS NULL)
												THEN [County Tax On Margin Due]
												WHEN @Reporting_Jurisdiction_Type = 'city' AND @Reporting_Jurisdiction_Name <> 'all' AND (@Tax_Type_Liable1 IS NULL OR @Tax_Type_Liable2 IS NULL)
												THEN [City Tax On Margin Due]				
												WHEN @Reporting_Jurisdiction_Type = 'state'
												THEN [State Tax On Margin Due]
												WHEN @Reporting_Jurisdiction_Type = 'all' 
												THEN [Total Tax On Margin Due]
												WHEN @Reporting_Jurisdiction_Type = 'city' AND @Reporting_Jurisdiction_Name <> 'all' AND @Tax_Type_Liable1 = 'city' AND @Tax_Type_Liable2 = 'county'
												THEN [City Tax On Margin Due] + [County Tax On Margin Due] 
												END)) <> 0
UNION ALL 			 						

		SELECT  ------CREDIT side of JE
				 'Upl' = ''
				,'Conversion Type' = 'Corporate'
				,'Conversion Date' = @ReportEndDate
				,'Conversion Rate' = ''
				,'Ledger' = CASE WHEN l.[LGL_ENTITY_CODE] IS NOT NULL AND c.[LGL_ENTITY_CODE] <> 61120
								 THEN l.Ledger
								 WHEN l.[LGL_ENTITY_CODE] IS NOT NULL AND c.[LGL_ENTITY_CODE] = 61120
								 THEN 'US PL'
								 ELSE 'UNKNOWN'
								 END
				,'Accounting Date' = @ReportEndDate
				,'Currency' = 'USD'
				,'Company' = CASE WHEN c.[LGL_ENTITY_CODE] = 61120
								  THEN 61110
								  ELSE c.[LGL_ENTITY_CODE]
								  END
				,'Account' = @LiabilityGLAccount						
				,'Department' = '00000'
				,'MGMT_UNIT_CODE' = '0000'
				,'Office' = '00000'
				,'Project' = CASE WHEN TRANS_TYP_NAME <> 'Cost Adjustment'
								  THEN @Project_Compliance
								  WHEN TRANS_TYP_NAME = 'Cost Adjustment'
								  THEN @Project_Breakage
								  END
				,'ORACLE_GL_PRODUCT_CODE' = '000000'
				,'Intercompany' = '00000'
				,'Future1' = '00000'
				,'Future2' = '0000' 
				,'Debit' = CASE WHEN 
								   (SUM(CASE WHEN @Reporting_Jurisdiction_Type = 'county' AND @Reporting_Jurisdiction_Name <> 'all' AND (@Tax_Type_Liable1 IS NULL OR @Tax_Type_Liable2 IS NULL)
											THEN [County Tax On Margin Due]
											WHEN @Reporting_Jurisdiction_Type = 'city' AND @Reporting_Jurisdiction_Name <> 'all' AND (@Tax_Type_Liable1 IS NULL OR @Tax_Type_Liable2 IS NULL)
											THEN [City Tax On Margin Due]				
											WHEN @Reporting_Jurisdiction_Type = 'state'
											THEN [State Tax On Margin Due]
											WHEN @Reporting_Jurisdiction_Type = 'all' 
											THEN [Total Tax On Margin Due]
											WHEN @Reporting_Jurisdiction_Type = 'city' AND @Reporting_Jurisdiction_Name <> 'all' AND @Tax_Type_Liable1 = 'city' AND @Tax_Type_Liable2 = 'county'
											THEN [City Tax On Margin Due] + [County Tax On Margin Due] 
											END)) < 0
								THEN -(SUM(CASE WHEN @Reporting_Jurisdiction_Type = 'county' AND @Reporting_Jurisdiction_Name <> 'all' AND (@Tax_Type_Liable1 IS NULL OR @Tax_Type_Liable2 IS NULL)
											THEN [County Tax On Margin Due]
											WHEN @Reporting_Jurisdiction_Type = 'city' AND @Reporting_Jurisdiction_Name <> 'all' AND (@Tax_Type_Liable1 IS NULL OR @Tax_Type_Liable2 IS NULL)
											THEN [City Tax On Margin Due]				
											WHEN @Reporting_Jurisdiction_Type = 'state'
											THEN [State Tax On Margin Due]
											WHEN @Reporting_Jurisdiction_Type = 'all' 
											THEN [Total Tax On Margin Due]
											WHEN @Reporting_Jurisdiction_Type = 'city' AND @Reporting_Jurisdiction_Name <> 'all' AND @Tax_Type_Liable1 = 'city' AND @Tax_Type_Liable2 = 'county'
											THEN [City Tax On Margin Due] + [County Tax On Margin Due] 
											END))
								ELSE 0
								END
				,'Credit' = CASE WHEN 
								   (SUM(CASE WHEN @Reporting_Jurisdiction_Type = 'county' AND @Reporting_Jurisdiction_Name <> 'all' AND (@Tax_Type_Liable1 IS NULL OR @Tax_Type_Liable2 IS NULL)
											THEN [County Tax On Margin Due]
											WHEN @Reporting_Jurisdiction_Type = 'city' AND @Reporting_Jurisdiction_Name <> 'all' AND (@Tax_Type_Liable1 IS NULL OR @Tax_Type_Liable2 IS NULL)
											THEN [City Tax On Margin Due]				
											WHEN @Reporting_Jurisdiction_Type = 'state'
											THEN [State Tax On Margin Due]
											WHEN @Reporting_Jurisdiction_Type = 'all' 
											THEN [Total Tax On Margin Due]
											WHEN @Reporting_Jurisdiction_Type = 'city' AND @Reporting_Jurisdiction_Name <> 'all' AND @Tax_Type_Liable1 = 'city' AND @Tax_Type_Liable2 = 'county'
											THEN [City Tax On Margin Due] + [County Tax On Margin Due]
											END)) > 0
								THEN (SUM(CASE WHEN @Reporting_Jurisdiction_Type = 'county' AND @Reporting_Jurisdiction_Name <> 'all'  AND (@Tax_Type_Liable1 IS NULL OR @Tax_Type_Liable2 IS NULL)
											THEN [County Tax On Margin Due]
											WHEN @Reporting_Jurisdiction_Type = 'city' AND @Reporting_Jurisdiction_Name <> 'all' AND (@Tax_Type_Liable1 IS NULL OR @Tax_Type_Liable2 IS NULL)
											THEN [City Tax On Margin Due]				
											WHEN @Reporting_Jurisdiction_Type = 'state'
											THEN [State Tax On Margin Due]
											WHEN @Reporting_Jurisdiction_Type = 'all' 
											THEN [Total Tax On Margin Due]
											WHEN @Reporting_Jurisdiction_Type = 'city' AND @Reporting_Jurisdiction_Name <> 'all' AND @Tax_Type_Liable1 = 'city' AND @Tax_Type_Liable2 = 'county'
											THEN [City Tax On Margin Due] + [County Tax On Margin Due] 
											END))
								ELSE 0									
								END	
			   ,'Converted Debit' = ''
			   ,'Converted Credit' = ''
			   ,'Description' = CASE WHEN TRANS_TYP_NAME <> 'Cost Adjustment'
										 THEN @Jurisdiction_State + '.' + @Reporting_Jurisdiction_Name + '.' + @Reporting_Jurisdiction_Type + '_' + @Remittance_Type + '.Tax' + @ReportEndDate_MonthYear
										 WHEN TRANS_TYP_NAME = 'Cost Adjustment'
										 THEN @Jurisdiction_State + '.' + @Reporting_Jurisdiction_Name + '.' + @Reporting_Jurisdiction_Type + '_' + @Remittance_Type + '.BrkTax' + @ReportEndDate_MonthYear
										 END
			  ,'InsertedDate' = GETDATE()									
									

		FROM Compliance.[F_Audit_ADJ_PRICE_GA-ADJ_COST_GA] (@Jurisdiction_State, @Reporting_Jurisdiction_Name, @Reporting_Jurisdiction_Type, @Remittance_Type) c
		LEFT JOIN lkup.Ledger l ON c.LGL_ENTITY_CODE = l.LGL_ENTITY_CODE
		LEFT JOIN lkup.AccountSpecialMU a ON c.[MGMT_UNIT_CODE] = a.[MGMT_UNIT_CODE]
		 
		WHERE c.[LGL_ENTITY_CODE] <> 15330
			AND (CASE WHEN @Negative_Margin_Exclusion = 'Y' AND (CASE WHEN NetNegFlag = 'N' -----these are the trans that are do NOT net to a negative for the month
																										-----so they can be INCLUDED for those special jurisdictions
																				THEN 'NetPositive' 
																				ELSE 'NetNegative' 
																				END) = 'NetPositive'
									THEN 'Y'
									ELSE 'N'
									END	) = @Negative_Margin_Exclusion
		GROUP BY (CASE WHEN c.[LGL_ENTITY_CODE] = 61120
								  THEN 61110
								  ELSE c.[LGL_ENTITY_CODE]
								  END)
				,(CASE WHEN TRANS_TYP_NAME <> 'Cost Adjustment'
								  THEN @Project_Compliance
								  WHEN TRANS_TYP_NAME = 'Cost Adjustment'
								  THEN @Project_Breakage
								  END)
				,(CASE WHEN TRANS_TYP_NAME <> 'Cost Adjustment'
										 THEN @Jurisdiction_State + '.' + @Reporting_Jurisdiction_Name + '.' + @Reporting_Jurisdiction_Type + '_' + @Remittance_Type + '.Tax' + @ReportEndDate_MonthYear
										 WHEN TRANS_TYP_NAME = 'Cost Adjustment'
										 THEN @Jurisdiction_State + '.' + @Reporting_Jurisdiction_Name + '.' + @Reporting_Jurisdiction_Type + '_' + @Remittance_Type + '.BrkTax' + @ReportEndDate_MonthYear
										 END)	
				,(CASE WHEN l.[LGL_ENTITY_CODE] IS NOT NULL AND c.[LGL_ENTITY_CODE] <> 61120
								 THEN l.Ledger
								 WHEN l.[LGL_ENTITY_CODE] IS NOT NULL AND c.[LGL_ENTITY_CODE] = 61120
								 THEN 'US PL'
								 ELSE 'UNKNOWN'
								 END)	
							 						 
									 		 
		HAVING (SUM(CASE WHEN @Reporting_Jurisdiction_Type = 'county' AND @Reporting_Jurisdiction_Name <> 'all' AND (@Tax_Type_Liable1 IS NULL OR @Tax_Type_Liable2 IS NULL)
											THEN [County Tax On Margin Due]
											WHEN @Reporting_Jurisdiction_Type = 'city' AND @Reporting_Jurisdiction_Name <> 'all' AND (@Tax_Type_Liable1 IS NULL OR @Tax_Type_Liable2 IS NULL)
											THEN [City Tax On Margin Due]				
											WHEN @Reporting_Jurisdiction_Type = 'state'
											THEN [State Tax On Margin Due]
											WHEN @Reporting_Jurisdiction_Type = 'all' 
											THEN [Total Tax On Margin Due]
											WHEN @Reporting_Jurisdiction_Type = 'city' AND @Reporting_Jurisdiction_Name <> 'all' AND @Tax_Type_Liable1 = 'city' AND @Tax_Type_Liable2 = 'county'
											THEN [City Tax On Margin Due] + [County Tax On Margin Due] 
											END)) <> 0

ORDER BY Description, Ledger, Company DESC, Account DESC


RETURN

END



















GO
