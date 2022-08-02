USE [Compliance]
GO
/****** Object:  UserDefinedFunction [Compliance].[F_Audit_ADJ_PRICE_GA-ADJ_COST_GA]    Script Date: 9/5/2017 10:47:49 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO




/*
** Prod File: n/a  
** Name: UserDefinedFunction [Compliance].[F_Audit_ADJ_PRICE_GA-ADJ_COST_GA]
** Desc: Template - ADJ_PRICE_GA-ADJ_COST_GA only, for pulling fields needed to export desired jurisdictions.
** Auth: Tammy Lessley
** Date: 20151015 
**************************
** Change History
**************************
** JIRA				Date       Author			Description 
** --				--------   -------			------------------------------------
** TAXSYSTEMS-633	20170608   Tammy Lessley	Insert extra fields to pick up the Remittance Type Change data and include the Remit Type Change Logic for those jurisdictions that have changes to remit type. 

*/

CREATE FUNCTION  [Compliance].[F_Audit_ADJ_PRICE_GA-ADJ_COST_GA]
(
@Jurisdiction_State VARCHAR(50),
@Reporting_Jurisdiction_Name VARCHAR(50),
@Reporting_Jurisdiction_Type VARCHAR(50),
@Remittance_Type VARCHAR(50)	
)
RETURNS   @Temp TABLE (	[REPORTENDDATE] [date] ,
						[LGL_ENTITY_CODE] [int] ,
						[Legal Entity For Tax] [int] ,
						[LGL_ENTITY_NAME] [varchar](8000) ,
						[EXPE_LODG_PROPERTY_ID] [int] ,
						[HotwireHotelId] [int] ,
						[LODG_PROPERTY_NAME] [varchar](8000) ,
						[PROPERTY_POSTAL_CODE] [varchar](40) ,
						[VertexCity] [varchar](100)  ,
						[Vertex County] [varchar](100)  ,
						[SALES_TAX_AREA] [varchar](100)  ,
						[PROPERTY_STATE_PROVNC_NAME] [varchar](200) ,
						[BOOK_YEAR_MONTH] [int],
						[TRANS_YEAR_MONTH] [int]  ,
						[BEGIN_USE_DATE] [date] ,
						[END_USE_DATE] [date] ,
						[TRANS_TYP_NAME] [varchar](200)  ,
						[BKG_ITM_ID] [bigint] ,
						[BASE_PRICE_USD] [decimal](19, 6)  ,
						[ALL_OTHR_ADJ_USD] [decimal](19, 6)  ,
						[TOTAL_PRICE_FEE_USD] [decimal](19, 6)  ,
						[PRICE_TAX_ADJ] [decimal](19, 6)  ,
						[PRICE_TAX_ADJ_WZEROFLAT] [decimal](19, 6)  ,
						[FLAT_ADJ_USD] [decimal](19, 6)  ,
						[ALL_OTHR_FEES_USD] [decimal](19, 6)  ,
						[BASE_COST_USD] [decimal](19, 6)  ,
						[OTHR_COST_ADJ_USD] [decimal](19, 6)  ,
						[TOTAL_COST_FEE_USD] [decimal](19, 6)  ,
						[FLAT_COST_ADJ_USD] [decimal](19, 6)  ,
						[COST_TAX_ADJ_WCANCEL] [decimal](19, 6)  ,
						[TOTAL_TAX_USD] [decimal](19, 6)  ,
						[TAX_COLLECTED] [decimal](19, 6)  ,
						[Negative Margin Excl] [varchar](11)  ,
						[Adjusted Price] [decimal](22, 6) ,
						[Adjusted Cost] [decimal](22, 6) ,
						[Taxable Margin] [decimal](23, 6) ,
						[RM_NIGHT_CNT] [smallint] ,
						[COMPUTED_ROOM_NIGHT_COUNT] [numeric](9, 1) ,
						[State Tax On Margin Due] [decimal](38, 7) ,
						[County Tax On Margin Due] [decimal](38, 7) ,
						[City Tax On Margin Due] [decimal](38, 7) ,
						[Transit Tax On Margin Due] [numeric](7, 7)  ,
						[Get Tax On Margin Due] [decimal](38, 7) ,
						[Total Tax On Margin Due] [decimal](38, 7) ,
						[State Tax Rate] [decimal](19, 6)  ,
						[County Tax Rate] [decimal](19, 6)  ,
						[City Tax Rate] [decimal](19, 6)  ,
						[Transit Tax Rate] [numeric](7, 7)  ,
						[GET Tax Rate] [decimal](19, 6)  ,
						[Total Tax Rate] [decimal](19, 6)  ,
						[VertexAreaID] [int] ,
						[MGMT_UNIT_CODE] [int] ,
						[ORACLE_GL_PRODUCT_CODE] [int],
						Jurisdiction_State [VARCHAR](50),
						Reporting_Jurisdiction_Name [VARCHAR](50),
						Reporting_Jurisdiction_Type	[VARCHAR](50),
						InsertedDate [DATETIME],
						ReportingEndDate [DATE],						
						TOTAL_PRICE_USD [DECIMAL] (19,6),
						TOTAL_COST_USD [DECIMAL] (19,6),
						GET_TAX_AREA [VARCHAR](100),
						NetNegFlag [VARCHAR](1),
						-----------------------New to the list
						Remittance_Type [VARCHAR](50),
						Flat_Tax [numeric](38,10),
						Flat_Tax_Description [VARCHAR](255),
						Flat_Tax_Amount_Due [numeric](38,10) ) 
BEGIN

-----open these up to test
--DECLARE @Jurisdiction_State VARCHAR(50),
-- @Reporting_Jurisdiction_Name VARCHAR(50),
-- @Reporting_Jurisdiction_Type VARCHAR(50),
-- @Remittance_Type VARCHAR(50),
-----open these up to test
DECLARE	 
		 @Liable_Use_Date DATE,
		 @Liable_Book_YearMonth INT,
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
		 @Tax_Type_Liable1 VARCHAR(50),
		 @Tax_Type_Liable2 VARCHAR(50),
		 @ReportingEndDate DATE,
		 ----new
		 @Remittance_Type_Change_Year_Month INT, 
		 @Remittance_Type_Change_Order INT, 
		 @Max_Remittance_Type_Change_Order INT, 
		 @Tax_Type_Liable1_Limitations VARCHAR(100),
		 @Tax_Type_Liable2_Limitations VARCHAR(100);

-----open this up to test - jurisdiction
--SET @Jurisdiction_State = 'GA';
--SET @Reporting_Jurisdiction_Name = 'GA';
--SET @Reporting_Jurisdiction_Type = 'state';
--SET @Remittance_Type = 'dual';
-----open this up to test - jurisdiction

SET @Liable_Use_Date = (SELECT Liable_Use_Date
						FROM   lkup.LodgingCompliance 
						WHERE  Jurisdiction_State = @Jurisdiction_State
						AND Reporting_Jurisdiction_Name = @Reporting_Jurisdiction_Name
						AND Reporting_Jurisdiction_Type = @Reporting_Jurisdiction_Type
						AND Remittance_Type = @Remittance_Type);	
SET @Liable_Book_YearMonth	= ( SELECT CONVERT(VARCHAR(6), Liable_Book_Date, 112) 
								FROM   lkup.LodgingCompliance 
								WHERE  Jurisdiction_State = @Jurisdiction_State
								AND Reporting_Jurisdiction_Name = @Reporting_Jurisdiction_Name
								AND Reporting_Jurisdiction_Type = @Reporting_Jurisdiction_Type
								AND Remittance_Type = @Remittance_Type); 													
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
									WHERE Filing_Companies_Compliance = @Filing_Companies_Compliance)	   						   													
SET @ExpenseGLAccount_Breakage = (SELECT Account	
									FROM lkup.ExpenseGLAccount		
									WHERE Filing_Companies_Compliance = @Filing_Companies_Breakage)
SET @Tax_Type_Liable1 = (SELECT Tax_Type_Liable1
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
SET @ReportingEndDate = (SELECT CAST(CONVERT(VARCHAR(10), MAX(REPORTENDDATE), 126) as DATE)
						 FROM Lodging.MonthlyCalculatedData) 															
-----new 						 	
SET @Remittance_Type_Change_Year_Month = (SELECT CONVERT(VARCHAR(6), Remittance_Type_Change_Date, 112) 
										   FROM   lkup.LodgingCompliance 
										   WHERE  Jurisdiction_State = @Jurisdiction_State
											AND Reporting_Jurisdiction_Name = @Reporting_Jurisdiction_Name
											AND Reporting_Jurisdiction_Type = @Reporting_Jurisdiction_Type
											AND Remittance_Type = @Remittance_Type);
SET @Remittance_Type_Change_Order = (SELECT Remittance_Type_Change_Order 
						   FROM   lkup.LodgingCompliance 
						   WHERE  Jurisdiction_State = @Jurisdiction_State
							AND Reporting_Jurisdiction_Name = @Reporting_Jurisdiction_Name
							AND Reporting_Jurisdiction_Type = @Reporting_Jurisdiction_Type
							AND Remittance_Type = @Remittance_Type);	
SET @Max_Remittance_Type_Change_Order = (SELECT MAX(Remittance_Type_Change_Order) --want to know what is the max value for this city... 
										  FROM   lkup.LodgingCompliance 
										  WHERE  Jurisdiction_State = @Jurisdiction_State
											AND Reporting_Jurisdiction_Name = @Reporting_Jurisdiction_Name
											AND Reporting_Jurisdiction_Type = @Reporting_Jurisdiction_Type ---how many rows with this state, name & type? more than one?? do not include the remit type in here.
											);
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


INSERT INTO @Temp ([REPORTENDDATE], 
					[LGL_ENTITY_CODE],
					[Legal Entity For Tax],
					[LGL_ENTITY_NAME],
					[EXPE_LODG_PROPERTY_ID],
					[HotwireHotelId],
					[LODG_PROPERTY_NAME],
					[PROPERTY_POSTAL_CODE],
					[VertexCity],
					[Vertex County],
					[SALES_TAX_AREA],
					[PROPERTY_STATE_PROVNC_NAME],
					[BOOK_YEAR_MONTH],
					[TRANS_YEAR_MONTH],
					[BEGIN_USE_DATE],
					[END_USE_DATE],
					[TRANS_TYP_NAME],
					[BKG_ITM_ID],
					[BASE_PRICE_USD],
					[ALL_OTHR_ADJ_USD],
					[TOTAL_PRICE_FEE_USD],
					[PRICE_TAX_ADJ],
					[PRICE_TAX_ADJ_WZEROFLAT],
					[FLAT_ADJ_USD],
					[ALL_OTHR_FEES_USD],
					[BASE_COST_USD],
					[OTHR_COST_ADJ_USD],
					[TOTAL_COST_FEE_USD],
					[FLAT_COST_ADJ_USD],
					[COST_TAX_ADJ_WCANCEL],
					[TOTAL_TAX_USD],
					[TAX_COLLECTED],
					[Negative Margin Excl],
					[Adjusted Price],
					[Adjusted Cost],
					[Taxable Margin],
					[RM_NIGHT_CNT],
					[COMPUTED_ROOM_NIGHT_COUNT],
					[State Tax On Margin Due],
					[County Tax On Margin Due],
					[City Tax On Margin Due],
					[Transit Tax On Margin Due],
					[Get Tax On Margin Due],
					[Total Tax On Margin Due],
					[State Tax Rate],
					[County Tax Rate],
					[City Tax Rate],
					[Transit Tax Rate],
					[GET Tax Rate],
					[Total Tax Rate],
					[VertexAreaID],
					MGMT_UNIT_CODE,
					ORACLE_GL_PRODUCT_CODE,
					Jurisdiction_State,
					Reporting_Jurisdiction_Name,
					Reporting_Jurisdiction_Type,
					InsertedDate,
					ReportingEndDate,
					TOTAL_PRICE_USD,
					TOTAL_COST_USD,
					GET_TAX_AREA,
					NetNegFlag,
					-----------------new to the list	
					Remittance_Type,
					Flat_Tax,
					Flat_Tax_Description,
					Flat_Tax_Amount_Due	
					)

			SELECT 
					'REPORTENDDATE' = mcd.[REPORTENDDATE]
					,'LGL_ENTITY_CODE' = mcd.[LGL_ENTITY_CODE]
					,'Legal Entity For Tax' = CASE WHEN l.LegalEntity IS NOT NULL	
													THEN l.LegalEntityForTax
												ELSE mcd.[LGL_ENTITY_CODE]
												END
					,'LGL_ENTITY_NAME' = mcd.[LGL_ENTITY_NAME]
					,'EXPE_LODG_PROPERTY_ID' = mcd.[EXPE_LODG_PROPERTY_ID]
					,'HotwireHotelId' = mcd.[HotwireHotelId]
					,'LODG_PROPERTY_NAME' = mcd.[LODG_PROPERTY_NAME]
					,'PROPERTY_POSTAL_CODE' = mcd.[PROPERTY_POSTAL_CODE]
					,'VertexCity' = mcd.CITY_TAX_AREA
					,'Vertex County' = mcd.COUNTY_TAX_AREA
					,'SALES_TAX_AREA' = mcd.[SALES_TAX_AREA]
					,'PROPERTY_STATE_PROVNC_NAME' = mcd.[PROPERTY_STATE_PROVNC_NAME]
					,'BOOK_YEAR_MONTH' = mcd.BOOK_YEAR_MONTH
					,'TRANS_YEAR_MONTH' = mcd.[TRANS_YEAR_MONTH]
					,'BEGIN_USE_DATE' = mcd.[BEGIN_USE_DATE]
					,'END_USE_DATE' = mcd.[END_USE_DATE]
					,'TRANS_TYP_NAME' = mcd.[TRANS_TYP_NAME]
					,'BKG_ITM_ID' = mcd.[BKG_ITM_ID]
					,'BASE_PRICE_USD' = SUM(mcd.[BASE_PRICE_USD]) ---E.G. of booking that has similar everything, except USE_YEAR_MONTH. that field not being here in this query, allows rows that appear to be duplicates 
																  ---to show through. need to sum up those here. [BKG_ITM_ID] =  613709244
					,'ALL_OTHR_ADJ_USD' = SUM(mcd.[ALL_OTHR_ADJ_USD])
					,'TOTAL_PRICE_FEE_USD' = SUM(mcd.[TOTAL_PRICE_FEE_USD])
					,'PRICE_TAX_ADJ' = SUM(mcd.[PRICE_TAX_ADJ])
					,'PRICE_TAX_ADJ_WZEROFLAT' = SUM(mcd.[PRICE_TAX_ADJ_WZEROFLAT])
					,'FLAT_ADJ_USD' = SUM(mcd.[FLAT_ADJ_USD])
					,'ALL_OTHR_FEES_USD' = SUM(mcd.[ALL_OTHR_FEES_USD])
					,'BASE_COST_USD' = SUM(mcd.[BASE_COST_USD])
					,'OTHR_COST_ADJ_USD' = SUM(mcd.[OTHR_COST_ADJ_USD])
					,'TOTAL_COST_FEE_USD' = SUM(mcd.[TOTAL_COST_FEE_USD])
					,'FLAT_COST_ADJ_USD' = SUM(mcd.[FLAT_COST_ADJ_USD])
					,'COST_TAX_ADJ_WCANCEL' = SUM(mcd.[COST_TAX_ADJ_WCANCEL])
					,'TOTAL_TAX_USD' = SUM(mcd.[TOTAL_TAX_USD])
					,'TAX_COLLECTED' = SUM(mcd.[TAX_COLLECTED])
					,'Negative Margin Excl' = CASE WHEN [ADJ_PRICE_GA-ADJ_COST_GA_NetNeg] = 'N' -----these are the trans that are do 
																								-----NOT net to a negative for the month
																								-----so they can be INCLUDED for those 
																								-----special jurisdictions
													THEN 'NetPositive' 
													ELSE 'NetNegative' 
													END
					,'Adjusted Price' = SUM(mcd.ADJ_PRICE_GA)
					,'Adjusted Cost' = SUM(mcd.ADJ_COST_GA)
					,'Taxable Margin' = SUM(mcd.[ADJ_PRICE_GA-ADJ_COST_GA])
					,'RM_NIGHT_CNT' = SUM(mcd.[RM_NIGHT_CNT])
					,'COMPUTED_ROOM_NIGHT_COUNT' = SUM(mcd.[COMPUTED_ROOM_NIGHT_COUNT])
					,'State Tax On Margin Due' = SUM(mcd.[ADJ_PRICE_GA-ADJ_COST_GA-SalesTaxDue])
					,'County Tax On Margin Due' = SUM(mcd.[ADJ_PRICE_GA-ADJ_COST_GA-CountyTaxDue])
					,'City Tax On Margin Due' = SUM(mcd.[ADJ_PRICE_GA-ADJ_COST_GA-CityTaxDue])
					,'Transit Tax On Margin Due' = 0.0000000
					,'Get Tax On Margin Due' = SUM(mcd.[ADJ_PRICE_GA-ADJ_COST_GA-GETTaxDue])
					,'Total Tax On Margin Due' = SUM(mcd.[ADJ_PRICE_GA-ADJ_COST_GA-TotalTaxDue])
					,'State Tax Rate' = ISNULL(mcd.[SALES_TAX_RATE],0)
					,'County Tax Rate' = ISNULL(mcd.[COUNTY_TAX_RATE], 0)
					,'City Tax Rate' = ISNULL(mcd.[CITY_TAX_RATE], 0)
					,'Transit Tax Rate' = 0.0000000
					,'GET Tax Rate' = ISNULL(mcd.[GET_TAX_RATE], 0)
					,'Total Tax Rate' = ISNULL(mcd.[TOTAL_TAX_RATE], 0)
					,'VertexAreaID' = mcd.[Vertex Tax Area]
					,'MGMT_UNIT_CODE' = mcd.MGMT_UNIT_CODE
					,'ORACLE_GL_PRODUCT_CODE' = mcd.ORACLE_GL_PRODUCT_CODE
					,'Jurisdiction_State' = @Jurisdiction_State 
					,'Reporting_Jurisdiction_Name' = @Reporting_Jurisdiction_Name 
					,'Reporting_Jurisdiction_Type' = @Reporting_Jurisdiction_Type 
					,'InsertedDate' = GETDATE()
					,'ReportingEndDate' = @ReportingEndDate
					,'TOTAL_PRICE_USD' = SUM(mcd.TOTAL_PRICE_USD)
					,'TOTAL_COST_USD' = SUM(mcd.TOTAL_COST_USD)
					,GET_TAX_AREA 
					,'NetNeg' = [ADJ_PRICE_GA-ADJ_COST_GA_NetNeg]
					,'Remittance_Type' = @Remittance_Type ---new to list
					,'Flat_Tax' = 0							---typically only single remit jurisdictions pay flat taxes. created a holding field if that ever changes 
					,'Flat_Tax_Description' = ''			---typically only single remit jurisdictions pay flat taxes. created a holding field if that ever changes 
					,'Flat_Tax_Amount_Due' = 0				---typically only single remit jurisdictions pay flat taxes. created a holding field if that ever changes 


			FROM Lodging.MonthlyCalculatedData mcd 
			LEFT JOIN lkup.LegalEntityForTax l ON mcd.LGL_ENTITY_CODE = l.LegalEntity

			WHERE mcd.PROPERTY_STATE_PROVNC_NAME IN (SELECT DISTINCT Jurisdiction_State FROM lkup.LodgingCompliance WHERE TaxBaseFieldName = 'ADJ_PRICE_GA-ADJ_COST_GA')

				  AND mcd.[PROPERTY_STATE_PROVNC_NAME] = @Jurisdiction_State ----to catch the state needed
				  AND (
				  
												(
													(
													  ((CASE WHEN @Reporting_Jurisdiction_Type = 'county' AND @Reporting_Jurisdiction_Name <> 'all'
																  AND @Reporting_Jurisdiction_Name NOT IN (SELECT DISTINCT [Reporting_Jurisdiction_Name] FROM lkup.Rome_GA)
															THEN mcd.COUNTY_TAX_AREA
															WHEN @Reporting_Jurisdiction_Type = 'city' AND @Reporting_Jurisdiction_Name <> 'all'
																 AND @Reporting_Jurisdiction_Name NOT IN (SELECT DISTINCT [Reporting_Jurisdiction_Name] FROM lkup.Rome_GA)
															THEN mcd.CITY_TAX_AREA				
															WHEN @Reporting_Jurisdiction_Type = 'state'
																 AND @Reporting_Jurisdiction_Name NOT IN (SELECT DISTINCT [Reporting_Jurisdiction_Name] FROM lkup.Rome_GA)
															THEN @Jurisdiction_State
															END) = @Reporting_Jurisdiction_Name)
															
													OR
														((CASE WHEN @Reporting_Jurisdiction_Type = 'all' OR @Reporting_Jurisdiction_Name = 'all'
															THEN @Jurisdiction_State
															END) = @Jurisdiction_State)
													)  
								
													
												)--------------this catches all the normal (non-Rome) jurisdictions
								
								OR					
												
												(
													(
														 (@Tax_Type_Liable1 = 'city' OR @Tax_Type_Liable2 = 'county')
														  --AND (mcd.COUNTY_TAX_AREA = @Reporting_Jurisdiction_Name OR mcd.CITY_TAX_AREA = @Reporting_Jurisdiction_Name)
														
													) 
												AND	 
												
													(mcd.CITY_TAX_AREA NOT IN (SELECT DISTINCT  CITY_TAX_AREA
																				FROM Lodging.MonthlyCalculatedData 
																				WHERE PROPERTY_STATE_PROVNC_NAME = @Jurisdiction_State
																					AND CITY_TAX_AREA	IN (SELECT [Cities] 
																												FROM [Compliance].[lkup].[Rome_GA] 
																												WHERE [YesNo] = 'N' 
																		  										AND [Reporting_Jurisdiction_Name] = @Reporting_Jurisdiction_Name) 
																		  )
													)------------this catches weirdos like Rome. 
												)
												
				  )
				  							
				  AND (
					   (mcd.[LGL_ENTITY_CODE] IN (SELECT Company
												  FROM lkup.FilingCompanies
												  WHERE Filing_Companies_Compliance = @Filing_Companies_Compliance)
						AND mcd.TRANS_TYP_NAME <> 'Cost Adjustment') -----------to catch the compliance companies
					  OR
					   (mcd.[LGL_ENTITY_CODE] IN (SELECT Company
												  FROM lkup.FilingCompanies
												  WHERE Filing_Companies_Compliance = @Filing_Companies_Breakage)	
						AND mcd.TRANS_TYP_NAME = 'Cost Adjustment')  -----------to catch the compliance companies for breakage
					  )
											
				  AND	(CASE WHEN mcd.TRANS_TYP_NAME = 'Cost Adjustment' AND mcd.[ADJ_PRICE_GA-ADJ_COST_GA] <> 0
							  THEN 'Y'
							  WHEN mcd.TRANS_TYP_NAME <> 'Cost Adjustment'
							  THEN 'Y'
							  END) = 'Y' ------to eliminate the excess breakage lines of zero value												

					  
				  AND mcd.END_USE_DATE >= @Liable_Use_Date


				  ----this new change remit type section only deals with book year  ... 
				  AND (
						 (@Remittance_Type_Change_Order >=  @Max_Remittance_Type_Change_Order ---- meaning that the remit type sequence is NOT the lesser of the family (aka it has NOT been superceeded) 
							AND 
						  mcd.BOOK_YEAR_MONTH >= @Liable_Book_YearMonth)		 ---this simple line works great if the row being run through has NOT been superceeded.... 

						 OR

						 (@Remittance_Type_Change_Order < @Max_Remittance_Type_Change_Order ---- meaning that the remit type sequence is the lesser of the family (aka it has been superceeded) 
							AND 
						  mcd.BOOK_YEAR_MONTH <  @Remittance_Type_Change_Year_Month) ----then only allow the book year month to reach the max, which is the change remit date

					  )		



			GROUP BY 
					mcd.[REPORTENDDATE]
					,mcd.[LGL_ENTITY_CODE]
					,(CASE WHEN l.LegalEntity IS NOT NULL	
													THEN l.LegalEntityForTax
												ELSE mcd.[LGL_ENTITY_CODE]
												END)
					,mcd.[LGL_ENTITY_NAME]
					,mcd.[EXPE_LODG_PROPERTY_ID]
					,mcd.[HotwireHotelId]
					,mcd.[LODG_PROPERTY_NAME]
					,mcd.[PROPERTY_POSTAL_CODE]
					,mcd.CITY_TAX_AREA
					,mcd.COUNTY_TAX_AREA
					,mcd.[SALES_TAX_AREA]
					,mcd.[PROPERTY_STATE_PROVNC_NAME]
					,mcd.BOOK_YEAR_MONTH
					,mcd.[TRANS_YEAR_MONTH]
					,mcd.[BEGIN_USE_DATE]
					,mcd.[END_USE_DATE]
					,mcd.[TRANS_TYP_NAME]
					,mcd.[BKG_ITM_ID]
					,(CASE WHEN [ADJ_PRICE_GA-ADJ_COST_GA_NetNeg] = 'N' -----these are the trans that are do 
																								-----NOT net to a negative for the month
																								-----so they can be INCLUDED for those 
																								-----special jurisdictions
													THEN 'NetPositive' 
													ELSE 'NetNegative' 
													END)
					,ISNULL(mcd.[SALES_TAX_RATE],0)
					,ISNULL(mcd.[COUNTY_TAX_RATE], 0)
					,ISNULL(mcd.[CITY_TAX_RATE], 0)
					,ISNULL(mcd.[GET_TAX_RATE], 0)
					,ISNULL(mcd.[TOTAL_TAX_RATE], 0)
					,mcd.[Vertex Tax Area]
					,mcd.MGMT_UNIT_CODE
					,mcd.ORACLE_GL_PRODUCT_CODE
					,GET_TAX_AREA
					,[ADJ_PRICE_GA-ADJ_COST_GA_NetNeg]
					--,'Flat_Tax' = 0							---will need to join the Rates.V_FlatTaxes to this query 
					--,'Flat_Tax_Description' = 'placeholder' ---will need to join the Rates.V_FlatTaxes to this query 
					--,'Flat_Tax_Amount_Due' = 0				---will need to join the Rates.V_FlatTaxes to this query 



RETURN

END





















GO
