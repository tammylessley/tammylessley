USE [Compliance]
GO
/****** Object:  UserDefinedFunction [Compliance].[F_Audit_ADJ_PRICE]    Script Date: 9/5/2017 10:47:49 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO



/*
** Prod File: n/a  
** Name: UserDefinedFunction [Compliance].[F_Audit_ADJ_PRICE]
** Desc: Template - Price only, for pulling fields needed to export desired jurisdictions.
** Auth: Tammy Lessley
** Date: 20151015 
**************************
** Change History
**************************
** JIRA				Date       Author			Description 
** --				--------   -------			------------------------------------
** TAXSYSTEMS-633	20170608   Tammy Lessley	Insert extra fields to pick up the Remittance Type Change data and include the Remit Type Change Logic for those jurisdictions that have changes to remit type. 

*/

CREATE FUNCTION  [Compliance].[F_Audit_ADJ_PRICE]
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
AS
BEGIN

---open these up to test
--DECLARE @Jurisdiction_State VARCHAR(50),
-- @Reporting_Jurisdiction_Name VARCHAR(50),
-- @Reporting_Jurisdiction_Type VARCHAR(50),
-- @Remittance_Type VARCHAR(50),
---open these up to test
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

---open this up to test - jurisdiction
--SET @Jurisdiction_State = 'NY';
--SET @Reporting_Jurisdiction_Name = 'New York';
--SET @Reporting_Jurisdiction_Type = 'city';
--SET @Remittance_Type = 'dual';
---open this up to test - jurisdiction


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
						 FROM Lodging.MonthlyCalculatedData); 	
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
-----
DECLARE @FlatTaxes table ([ExepdiaHotelID] INT INDEX IX1 NONCLUSTERED, 
						  [HotwireHotelID] INT INDEX IX2 NONCLUSTERED, 
						  [Reporting_Level] NVARCHAR(100) INDEX IX3 NONCLUSTERED, 
						  [Hotel_Source] VARCHAR(7), [Tax Area ID] INT,  [Country] VARCHAR(255),
							[State] NVARCHAR(255), [Jurisdiction Level] VARCHAR(50), [Jurisdiction Name] VARCHAR(255),[Tax Name] VARCHAR(255), [Source] VARCHAR(50), 
							[AMOUNT_PER_DAY] NUMERIC(38,10), [AMOUNT_PER_STAY] NUMERIC(38,10) ) --added remittance type

INSERT INTO @FlatTaxes
	SELECT *
	FROM [Rates].[V_FlatTaxes] (nolock)
	WHERE [Reporting_Level] IS NOT NULL; 


-----

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
					,'BASE_PRICE_USD' = mcd.[BASE_PRICE_USD]
					,'ALL_OTHR_ADJ_USD' = mcd.[ALL_OTHR_ADJ_USD]
					,'TOTAL_PRICE_FEE_USD' = mcd.[TOTAL_PRICE_FEE_USD]
					,'PRICE_TAX_ADJ' = mcd.[PRICE_TAX_ADJ]
					,'PRICE_TAX_ADJ_WZEROFLAT' = mcd.[PRICE_TAX_ADJ_WZEROFLAT]
					,'FLAT_ADJ_USD' = mcd.[FLAT_ADJ_USD]
					,'ALL_OTHR_FEES_USD' = mcd.[ALL_OTHR_FEES_USD]
					,'BASE_COST_USD' = mcd.[BASE_COST_USD]
					,'OTHR_COST_ADJ_USD' = mcd.[OTHR_COST_ADJ_USD]
					,'TOTAL_COST_FEE_USD' = mcd.[TOTAL_COST_FEE_USD]
					,'FLAT_COST_ADJ_USD' = mcd.[FLAT_COST_ADJ_USD]
					,'COST_TAX_ADJ_WCANCEL' = mcd.[COST_TAX_ADJ_WCANCEL]
					,'TOTAL_TAX_USD' = mcd.[TOTAL_TAX_USD]
					,'TAX_COLLECTED' = mcd.[TAX_COLLECTED]
					,'Negative Margin Excl' = CASE WHEN [ADJ_PRICE_NetNeg] = 'N' -----these are the trans that are do 
																								-----NOT net to a negative for the month
																								-----so they can be INCLUDED for those 
																								-----special jurisdictions
													THEN 'NetPositive' 
													ELSE 'NetNegative' 
													END
					,'Adjusted Price' = mcd.ADJ_PRICE
					,'Adjusted Cost' = 0								
					,'Taxable Margin' = mcd.ADJ_PRICE
					,'RM_NIGHT_CNT' = mcd.[RM_NIGHT_CNT]
					,'COMPUTED_ROOM_NIGHT_COUNT' = mcd.[COMPUTED_ROOM_NIGHT_COUNT]
					,'State Tax On Margin Due' = mcd.[ADJ_PRICE-SalesTaxDue]
					,'County Tax On Margin Due' = mcd.[ADJ_PRICE-CountyTaxDue]
					,'City Tax On Margin Due' = mcd.[ADJ_PRICE-CityTaxDue]
					,'Transit Tax On Margin Due' = 0.0000000
					,'Get Tax On Margin Due' = mcd.[ADJ_PRICE-GETTaxDue]
					,'Total Tax On Margin Due' = mcd.[ADJ_PRICE-TotalTaxDue] 	
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
					,TOTAL_PRICE_USD
					,TOTAL_COST_USD
					,GET_TAX_AREA 
					,'NetNeg' = [ADJ_PRICE_NetNeg]
					,'Remittance_Type' = @Remittance_Type ---new to list
					
					-----flat taxes applied to NON-breakage transactions...only for NY Single remit - right? 
					,'Flat_Tax' = CASE WHEN fte.[ExepdiaHotelID] IS NOT NULL THEN ISNULL(fte.[AMOUNT_PER_DAY], 0)  ---when there is a matching flat tax for the Expedia hotel, put it here
									   WHEN fth.[HotwireHotelID] IS NOT NULL THEN ISNULL(fth.[AMOUNT_PER_DAY], 0)  ---when there is a matching flat tax for the Hotwire hotel, put it here
									   ELSE 0 END
					,'Flat_Tax_Description' = CASE WHEN fte.[ExepdiaHotelID] IS NOT NULL THEN ISNULL(fte.[Tax Name], '')  ---when there is a matching flat tax desc for the Expedia hotel, put it here
												   WHEN fth.[HotwireHotelID] IS NOT NULL THEN ISNULL(fth.[Tax Name], '')  ---when there is a matching flat tax desc for the Hotwire hotel, put it here
												   ELSE '' END
					,'Flat_Tax_Amount_Due' = ( CASE WHEN fte.[ExepdiaHotelID] IS NOT NULL THEN ISNULL(fte.[AMOUNT_PER_DAY], 0)  ---when there is a matching flat tax for the Expedia hotel, put it here
									                WHEN fth.[HotwireHotelID] IS NOT NULL THEN ISNULL(fth.[AMOUNT_PER_DAY], 0)  ---when there is a matching flat tax for the Hotwire hotel, put it here
									                ELSE 0 END) * mcd.[RM_NIGHT_CNT] 


			FROM Lodging.MonthlyCalculatedData mcd 
			LEFT JOIN lkup.LegalEntityForTax l ON mcd.LGL_ENTITY_CODE = l.LegalEntity
			--connect the flat tax for the Expedia hotel per reporting level
			LEFT JOIN @FlatTaxes fte ON mcd.[EXPE_LODG_PROPERTY_ID] = fte.[ExepdiaHotelID] AND fte.[ExepdiaHotelID] <> 0 AND @Reporting_Jurisdiction_Type = fte.[Reporting_Level] 
			--connect the flat tax for the Hotwire hotel per reporting level
			LEFT JOIN @FlatTaxes fth ON mcd.[HotwireHotelId]		= fth.[HotwireHotelID] AND fth.[HotwireHotelID] <> 0 AND @Reporting_Jurisdiction_Type = fth.[Reporting_Level] 

			LEFT JOIN (SELECT ORDER_CONF_NBR 
						FROM Lodging.MonthlyCalculatedData mcd 
						WHERE mcd.[LGL_ENTITY_CODE] = '75110') x ON mcd.ORDER_CONF_NBR = x.ORDER_CONF_NBR 
																 AND mcd.[LGL_ENTITY_CODE] = '14101' ------Take out the duplicates between 14101 & 75110 (hotwire will file for those bookings)
			
			
			
			
			WHERE mcd.PROPERTY_STATE_PROVNC_NAME IN (SELECT DISTINCT Jurisdiction_State FROM lkup.LodgingCompliance WHERE TaxBaseFieldName = 'ADJ_PRICE')

				  AND mcd.[PROPERTY_STATE_PROVNC_NAME] = @Jurisdiction_State ----to catch the state needed
				  ---updating logic here to catch jurisdictions that extra logic - e.g. Broome, Saratoga, New York city, etc
				 AND (
				  
				  
							   (
								  (CASE WHEN @Reporting_Jurisdiction_Type = 'county' AND @Reporting_Jurisdiction_Name <> 'all'
										THEN mcd.COUNTY_TAX_AREA
										WHEN @Reporting_Jurisdiction_Type = 'city' AND @Reporting_Jurisdiction_Name <> 'all'
										THEN mcd.CITY_TAX_AREA				
										WHEN @Reporting_Jurisdiction_Type = 'state'
										THEN @Jurisdiction_State
										END) = @Reporting_Jurisdiction_Name -------to catch the appropriate city, county or state population
										
								OR
									(CASE WHEN @Reporting_Jurisdiction_Type = 'all' OR @Reporting_Jurisdiction_Name = 'all'
										THEN @Jurisdiction_State
										END) = @Jurisdiction_State --------to catch any properties that have been coded as 'all' for Jurisdiction_Name
								) -------------to catch all the normal guys - like Broome, etc
								 
						OR
					 
								(
									(@Tax_Type_Liable2 = 'city' AND @Tax_Type_Liable2_Limitations = mcd.CITY_TAX_AREA)
									OR 
									(@Tax_Type_Liable1 = 'county' AND @Tax_Type_Liable2_Limitations = mcd.COUNTY_TAX_AREA)
									OR
									(@Tax_Type_Liable1 = 'city' AND @Tax_Type_Liable1_Limitations = mcd.SALES_TAX_AREA)
								)-------------to catch all the special stories - like Saratoga County - that also needs to include Saratoga city records, specifically
					 
					  )	 		
					  

				  AND mcd.TRANS_TYP_NAME <> 'Cost Adjustment' ---note to self: perhaps use the Filing_Companies_Breakage field in conjunction with 
															  ---this to let the single stuff plus the breakage stuff flow through. 
				  AND x.ORDER_CONF_NBR IS NULL --takes care of the duplicate records between TS & HW

				  AND mcd.END_USE_DATE >= @Liable_Use_Date 
				  
				  
				  ----this new change remit type section only deals with book year  ... 
				  AND (
						 (@Remittance_Type_Change_Order >=  @Max_Remittance_Type_Change_Order ---- meaning that the remit type sequence is NOT the lesser of the family (aka it has been superceeded) 
							AND 
						  mcd.BOOK_YEAR_MONTH >= @Liable_Book_YearMonth)		 ---this simple line works great if the row being run through has NOT been superceeded.... 

						 OR

						 (@Remittance_Type_Change_Order < @Max_Remittance_Type_Change_Order ---- meaning that the remit type sequence is the lesser of the family (aka it has been superceeded) 
							AND 
						  mcd.BOOK_YEAR_MONTH <  @Remittance_Type_Change_Year_Month) ----then only allow the book year month to reach the max, which is the change remit date

					  )				
				 

				order by BOOK_YEAR_MONTH desc


RETURN

END























GO
