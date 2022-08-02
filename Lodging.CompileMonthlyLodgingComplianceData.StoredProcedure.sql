USE [Compliance]
GO
/****** Object:  StoredProcedure [Lodging].[CompileMonthlyLodgingComplianceData]    Script Date: 9/5/2017 10:47:49 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO



---- =============================================
---- Author:		Tammy Lessley
---- Create date:	20151006
---- Description:	Script for updating and compiling monthly lodging compliance data.
----				1) updates any "TurnedOn" statuses, 2) sets 2 variables, 3) loads some temp tables
----				4) pulls through the EDW lodging data, 5) pulls in the monthly Breakage data & 6) pulls in the monthly Hotwire data
----				This entire stored procedure takes approx. 8 minutes to compile 
----				and load pertinent data to Lodging.MonthlyCalculatedData
---- =============================================
CREATE  PROCEDURE [Lodging].[CompileMonthlyLodgingComplianceData]
AS
BEGIN

-----------------------------------------------------
----Update field lkup.LodgingCompliance.Filing_Companies_Compliance for those jurisidictions that have been "TurnedOn", 
----which in turn changes the companies that need to be filed
----finding those jurisdictions that have been turned on since the month end before last. E.g. between 8/30/15 and 09/30/15


UPDATE lkup.LodgingCompliance 
SET Filing_Companies_Compliance = 'TurnedOn' --those jurisdictions that are running, that now need 15330 & 61120 added to the list of companies
WHERE Customer_Collection_Turn_On_Date <= DATEADD(d, - DATEPART(d, GETDATE()), GETDATE()) --BETWEEN DATEADD(MONTH, -1, DATEADD(DAY, -DATEPART(DAY, GETDATE()), GETDATE() )) AND DATEADD(d, - DATEPART(d, GETDATE()), GETDATE()) 


UPDATE lkup.LodgingCompliance 
SET Filing_Companies_Breakage = 'TurnedOn' --those jurisdictions that are running breakage, that now need 15330 & 61120 added to the list of companies
WHERE DATEADD(YEAR, 1, Customer_Collection_Turn_On_Date) <= DATEADD(d, - DATEPART(d, GETDATE()), GETDATE()) --BETWEEN DATEADD(MONTH, -1, DATEADD(DAY, -DATEPART(DAY, GETDATE()), GETDATE() )) AND DATEADD(d, - DATEPART(d, GETDATE()), GETDATE())	
		AND Filing_Companies_Breakage NOT IN ('NotApplicable')


UPDATE lkup.LodgingCompliance 
SET Filing_Companies_Breakage = 'NotTurnedOn'  ---just to turn on these jursidictions to start running breakage
WHERE DATEADD(YEAR, 1, [Liable_Use_Date]) <= DATEADD(d, - DATEPART(d, GETDATE()), GETDATE())	--If a jurisdiction comes on board with an old liable date, we need to compare the liable date to only the end date of this range (it was previously a range of BETWEEEN, but it missed picking up and relabling Duluth)  
		AND Filing_Companies_Breakage  = 'None'


-----------------------------------------------------
---Short Term Fix: TAXSYSTEMS-920 - Turn Off Collection for Broome & the 2 Saratogas

update [lkup].[LodgingCompliance]
set Filing_Companies_Compliance = 'NotTurnedOn'

where [Jurisdiction_State] = 'NY'
and [Reporting_Jurisdiction_Name] in ('Broome', 'Saratoga Springs', 'Saratoga') 


-----------------------------------------------------
---Declaring variables for use down below
-----------------------------------------------------

DECLARE @BreakageBeginUseMonth DATE;
DECLARE @HotwireBeginUseMonth DATE;
---(3 sec)
SET @BreakageBeginUseMonth = (SELECT DISTINCT 'BeginUseMonth' =
								CONVERT(VARCHAR(10), DATEADD(DAY, -1, DATEADD(MONTH, 1,
								CAST(CAST(LEFT(BEGIN_USE_YEAR_MONTH, 4) AS VARCHAR) +  
								CAST(RIGHT(BEGIN_USE_YEAR_MONTH, 2) AS VARCHAR) + '01' AS DATETIME))), 110)
								FROM Lodging.V_Breakage);
SET @HotwireBeginUseMonth = (SELECT DISTINCT
								CONVERT(VARCHAR(10), DATEADD(DAY, -1, DATEADD(MONTH, 1, 
								CAST(CONVERT(VARCHAR(6), BEGIN_USE_DATE, 112) + '01' AS DATETIME))), 110)
								FROM  Lodging.V_Hotwire)								

-----------------------------------------------------
---Pulling data into temp tables for use down below
-----------------------------------------------------


IF OBJECT_ID('tempdb..#BUSINESS_UNIT') IS NOT NULL 
DROP TABLE #BUSINESS_UNIT;
---(237 rows, 1 sec)
SELECT	* INTO 	#BUSINESS_UNIT
FROM	(SELECT *
		FROM  OPENQUERY(TDProd, 
			   'SELECT	BUSINESS_UNIT_ID, BUSINESS_UNIT_NAME
			   FROM  P_DM_COMMON.BUSINESS_UNIT_DIM;'))A;
			   
-----------------------------------------------------
			   
IF OBJECT_ID('tempdb..#LODG_PROPERTY') IS NOT NULL 
DROP TABLE #LODG_PROPERTY;
---(658K rows, 22 sec)
SELECT	* INTO 	#LODG_PROPERTY
FROM	(SELECT *
		FROM  OPENQUERY(TDProd, 
			   'SELECT	EXPE_LODG_PROPERTY_ID, PROPERTY_CITY_NAME
			   FROM   P_DM_COMMON.LODG_PROPERTY_DIM;'))A;			   

-----------------------------------------------------
-----------Flagging/marking those bookings that net to negative within the EDW world

IF OBJECT_ID('tempdb..#Net_Negative_Margin') IS NOT NULL 
DROP TABLE #Net_Negative_Margin;
-----(919K rows, 30 sec)
SELECT * INTO #Net_Negative_Margin
FROM
	(SELECT   [BKG_ITM_ID]
			 ,'ADJ_PRICE_GA-ADJ_COST_WPriceFee_NetNeg' = CASE WHEN SUM(ROUND((ROUND((l.[ALL_OTHR_ADJ_USD] - l.[PRICE_TAX_ADJ]) + (l.[FLAT_ADJ_USD] + l.[ALL_OTHR_FEES_USD] + l.[BASE_PRICE_USD]),2) )
										- ( (l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD] + l.[TOTAL_COST_FEE_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ),2)) <= 0 THEN 'Y' ELSE 'N' END
			  ,'ADJ_PRICE_GA-ADJ_COST_GA_NetNeg' = CASE WHEN SUM(ROUND((ROUND((l.[ALL_OTHR_ADJ_USD] - l.[PRICE_TAX_ADJ]) + (l.[FLAT_ADJ_USD] + l.[ALL_OTHR_FEES_USD] + l.[BASE_PRICE_USD]),2))
									-( (l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ),2)) <= 0 THEN 'Y' ELSE 'N' END

			  ,'ADJ_PRICE_NY-ADJ_COST_WPriceFee_NetNeg' = CASE WHEN SUM(ROUND(( ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ_WZEROFLAT]),2) )
										- ((l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD] + l.[TOTAL_COST_FEE_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ),2)) <= 0 THEN 'Y' ELSE 'N' END
			  ,'ADJ_PRICE_NY-ADJ_COST_GA_NetNeg' = CASE WHEN SUM(ROUND(( ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ_WZEROFLAT]),2) )
								- ( (l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ),2)) <= 0 THEN 'Y' ELSE 'N' END
										
			  ,'ADJ_PRICE-ADJ_COST_WPriceFee_NetNeg' = CASE WHEN SUM(ROUND((ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ]) ,2) ) 
									- (	(l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD] + l.[TOTAL_COST_FEE_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ),2)) <= 0 THEN 'Y' ELSE 'N' END
			  ,'ADJ_PRICE-ADJ_COST_GA_NetNeg' = CASE WHEN SUM(ROUND((ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ]) ,2) )
								- ( (l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ),2)) <= 0 THEN 'Y' ELSE 'N' END						
		
			  ,'ADJ_PRICE_NetNeg' = CASE WHEN SUM(ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ]) ,2))
								 <= 0 THEN 'Y' ELSE 'N' END	
	  FROM [Compliance].[Lodging].[V_EDW] l
	  GROUP BY [BKG_ITM_ID]
	  )x;

---5 seconds (placing an index on the temp table enables hook up with the tables below to be more efficient
CREATE INDEX IX_NNM on #Net_Negative_Margin (BKG_ITM_ID);	

-------------------------------------
-----------Flagging/marking those bookings that net to negative within the Hotwire world

IF OBJECT_ID('tempdb..#Net_Negative_HotwireMargin') IS NOT NULL 
DROP TABLE #Net_Negative_HotwireMargin;
---(8 sec, 105K records)
SELECT * INTO #Net_Negative_HotwireMargin
FROM (	SELECT   'BKG_ITM_ID' = CAST(ISNULL(REPLACE(PURCHASE_ORDER_ID,'''',''), 0) AS BIGINT)
					 ,'ADJ_PRICE_GA-ADJ_COST_WPriceFee_NetNeg' = CASE WHEN SUM(ROUND(ROUND([EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT],2)
																- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END) ,2)) <= 0 THEN 'Y' ELSE 'N' END
					  ,'ADJ_PRICE_GA-ADJ_COST_GA_NetNeg' = CASE WHEN SUM(ROUND(ROUND([EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT],2)
														- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END) ,2)) <= 0 THEN 'Y' ELSE 'N' END

					  ,'ADJ_PRICE_NY-ADJ_COST_WPriceFee_NetNeg' = CASE WHEN SUM(ROUND(ROUND([CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)
																- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END),2)) <= 0 THEN 'Y' ELSE 'N' END
					  ,'ADJ_PRICE_NY-ADJ_COST_GA_NetNeg' = CASE WHEN SUM(ROUND(ROUND([CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)
													- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END),2)) <= 0 THEN 'Y' ELSE 'N' END
												
					  ,'ADJ_PRICE-ADJ_COST_WPriceFee_NetNeg' = CASE WHEN SUM(ROUND(ROUND([CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)
													- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END), 2)) <= 0 THEN 'Y' ELSE 'N' END
					  ,'ADJ_PRICE-ADJ_COST_GA_NetNeg' = CASE WHEN SUM(ROUND(ROUND([CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)
													- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END), 2)) <= 0 THEN 'Y' ELSE 'N' END						
					  
					  ,'ADJ_PRICE_NetNeg' = CASE WHEN SUM(ROUND([CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2))
													 <= 0 THEN 'Y' ELSE 'N' END								
													
			  FROM Compliance.Lodging.V_Hotwire
			  GROUP BY PURCHASE_ORDER_ID)x;  
			  
CREATE INDEX IX_NNHM on #Net_Negative_HotwireMargin (BKG_ITM_ID);
-----------------------------------------------------------------------------
----Compiling all the  Data needed for individual jurisdictional consideration. 
-----------------------------------------------------------------------------
-----move a copy of the raw compiled monthly data (from our 3 sources: EDW, Breakage & Hotwire), to the historical table
-----safety net: 1) the historical table has a compound primary key on 16 fields - to not accept duplicate rows
-----safety net: 2) it will only "insert into" when the maximum REPORTENDDATE is NOT the same as the LAST month end date


--INSERT INTO [Compliance].[Lodging].[MonthlyCalculatedData_Historical]
--SELECT * , GETDATE() FROM [Compliance].[Lodging].[MonthlyCalculatedData] m 
--WHERE NOT EXISTS (SELECT 'REPORTENDDATE' = MAX([REPORTENDDATE])
--				  FROM [Compliance].[Lodging].[MonthlyCalculatedData_Historical] h 
--				  WHERE m.REPORTENDDATE = h.REPORTENDDATE 
--				  OR (
--						YEAR(m.REPORTENDDATE) + 1 = YEAR(h.REPORTENDDATE) 
--						AND MONTH(m.REPORTENDDATE) = MONTH(h.REPORTENDDATE)
--						AND m.TRANS_TYP_NAME = 'Cost Adjustment'
--					  )
--				  HAVING MAX([REPORTENDDATE]) = CAST(DATEADD(d, - DATEPART(d, GETDATE()), GETDATE()) AS DATE));
				  
				  
----Once we keep a copy of the the old stuff, then we can clear out the monthly table, and reload it - with the new month data.

TRUNCATE TABLE [Compliance].[Lodging].[MonthlyCalculatedData];


-------Compiling the EDW monthly data.
---(1MM rows, 6 min)
INSERT INTO [Compliance].[Lodging].[MonthlyCalculatedData]
	(  [REPORTENDDATE]
      ,[BOOK_YEAR_MONTH]
      ,[TRANS_YEAR_MONTH]
      ,[USE_YEAR_MONTH]
      ,[BKG_ITM_ID]
      ,[ORDER_CONF_NBR]
      ,[BEGIN_USE_DATE]
      ,[END_USE_DATE]
      ,[TRANS_TYP_NAME]
      ,[EXPE_LODG_PROPERTY_ID]
      ,[LGL_ENTITY_CODE]
      ,[LGL_ENTITY_NAME]
      ,[BUSINESS_UNIT_ID]
      ,[BUSINESS_UNIT_NAME]
      ,[LODG_PROPERTY_NAME]
      ,[PROPERTY_CITY_NAME]
      ,[PROPERTY_STATE_PROVNC_NAME]
      ,[PROPERTY_POSTAL_CODE]
      ,[PRICE_CURRN_CODE]
      ,[OPER_UNIT_ID]
      ,[GL_PRODUCT_ID]
      ,[MGMT_UNIT_CODE]
      ,[ORACLE_GL_PRODUCT_CODE]
      ,[RM_NIGHT_CNT]
      ,[COMPUTED_ROOM_NIGHT_COUNT]
      ,[SALES_TAX_AREA]
      ,[COUNTY_TAX_AREA]
      ,[CITY_TAX_AREA]
      ,[GET_TAX_AREA]
      ,[SALES_TAX_RATE]
      ,[COUNTY_TAX_RATE]
      ,[CITY_TAX_RATE]
      ,[GET_TAX_RATE]
      ,[TOTAL_TAX_RATE]
      ,[BASE_PRICE_USD]
      ,[FLAT_ADJ_USD]
      ,[ALL_OTHR_ADJ_USD]
      ,[SVC_FEE_PRICE_USD]
      ,[ALL_OTHR_FEES_USD]
      ,[TOTAL_TAX_USD]
      ,[TOTAL_PRICE_USD]
      ,[BASE_COST_USD]
      ,[FLAT_COST_ADJ_USD]
      ,[OTHR_COST_ADJ_USD]
      ,[TOTAL_COST_FEE_USD]
      ,[TOTAL_COST_USD]
      ,[TAX_COLLECTED]
      ,[TOTAL_PRICE_FEE_USD]
      ,[TAX_BASE_MARGIN]
      ,[TAX_BASE_COST]
      ,[PRICE_TAX_ADJ_WZEROFLAT]
      ,[PRICE_TAX_ADJ]
      ,[COST_TAX_ADJ]
      ,[COST_TAX_ADJ_WCANCEL]
      ,[InsertedDate]
      ,[ADJ_PRICE_GA]
      ,[ADJ_PRICE_NY]
      ,[ADJ_PRICE]
      ,[ADJ_COST_WPriceFee]
      ,[ADJ_COST_GA]
      ,[ADJ_PRICE_GA-ADJ_COST_WPriceFee]
      ,[ADJ_PRICE_GA-ADJ_COST_GA]
      ,[ADJ_PRICE_NY-ADJ_COST_WPriceFee]
      ,[ADJ_PRICE_NY-ADJ_COST_GA]
      ,[ADJ_PRICE-ADJ_COST_WPriceFee]
      ,[ADJ_PRICE-ADJ_COST_GA]
      ,[ADJ_PRICE_GA-CityTaxDue]
      ,[ADJ_PRICE_GA-CountyTaxDue]
      ,[ADJ_PRICE_GA-SalesTaxDue]
      ,[ADJ_PRICE_GA-GETTaxDue]
      ,[ADJ_PRICE_GA-TotalTaxDue]
	  ,[ADJ_PRICE_NY-CityTaxDue] 
	  ,[ADJ_PRICE_NY-CountyTaxDue]
	  ,[ADJ_PRICE_NY-SalesTaxDue] 
      ,[ADJ_PRICE_NY-GETTaxDue] 
	  ,[ADJ_PRICE_NY-TotalTaxDue] 
	  ,[ADJ_PRICE-CityTaxDue] 
	  ,[ADJ_PRICE-CountyTaxDue] 
	  ,[ADJ_PRICE-SalesTaxDue] 
	  ,[ADJ_PRICE-GETTaxDue] 
	  ,[ADJ_PRICE-TotalTaxDue] 
      ,[ADJ_PRICE_GA-ADJ_COST_WPriceFee-CityTaxDue]
      ,[ADJ_PRICE_GA-ADJ_COST_WPriceFee-CountyTaxDue]
      ,[ADJ_PRICE_GA-ADJ_COST_WPriceFee-SalesTaxDue]
      ,[ADJ_PRICE_GA-ADJ_COST_WPriceFee-GETTaxDue]
      ,[ADJ_PRICE_GA-ADJ_COST_WPriceFee-TotalTaxDue]
      ,[ADJ_PRICE_GA-ADJ_COST_GA-CityTaxDue]
      ,[ADJ_PRICE_GA-ADJ_COST_GA-CountyTaxDue]
      ,[ADJ_PRICE_GA-ADJ_COST_GA-SalesTaxDue]
      ,[ADJ_PRICE_GA-ADJ_COST_GA-GETTaxDue]
      ,[ADJ_PRICE_GA-ADJ_COST_GA-TotalTaxDue]
      ,[ADJ_PRICE_NY-ADJ_COST_WPriceFee-CityTaxDue]
      ,[ADJ_PRICE_NY-ADJ_COST_WPriceFee-CountyTaxDue]
      ,[ADJ_PRICE_NY-ADJ_COST_WPriceFee-SalesTaxDue]
      ,[ADJ_PRICE_NY-ADJ_COST_WPriceFee-GETTaxDue]
      ,[ADJ_PRICE_NY-ADJ_COST_WPriceFee-TotalTaxDue]
      ,[ADJ_PRICE_NY-ADJ_COST_GA-CityTaxDue]
      ,[ADJ_PRICE_NY-ADJ_COST_GA-CountyTaxDue]
      ,[ADJ_PRICE_NY-ADJ_COST_GA-SalesTaxDue]
      ,[ADJ_PRICE_NY-ADJ_COST_GA-GETTaxDue]
      ,[ADJ_PRICE_NY-ADJ_COST_GA-TotalTaxDue]
      ,[ADJ_PRICE-ADJ_COST_WPriceFee-CityTaxDue]
      ,[ADJ_PRICE-ADJ_COST_WPriceFee-CountyTaxDue]
      ,[ADJ_PRICE-ADJ_COST_WPriceFee-SalesTaxDue]
      ,[ADJ_PRICE-ADJ_COST_WPriceFee-GETTaxDue]
      ,[ADJ_PRICE-ADJ_COST_WPriceFee-TotalTaxDue]
      ,[ADJ_PRICE-ADJ_COST_GA-CityTaxDue]
      ,[ADJ_PRICE-ADJ_COST_GA-CountyTaxDue]
      ,[ADJ_PRICE-ADJ_COST_GA-SalesTaxDue]
      ,[ADJ_PRICE-ADJ_COST_GA-GETTaxDue]
      ,[ADJ_PRICE-ADJ_COST_GA-TotalTaxDue]
      ,[ADJ_PRICE_GA-ADJ_COST_WPriceFee_NetNeg]
      ,[ADJ_PRICE_GA-ADJ_COST_GA_NetNeg]
      ,[ADJ_PRICE_NY-ADJ_COST_WPriceFee_NetNeg]
      ,[ADJ_PRICE_NY-ADJ_COST_GA_NetNeg]
      ,[ADJ_PRICE-ADJ_COST_WPriceFee_NetNeg]
      ,[ADJ_PRICE-ADJ_COST_GA_NetNeg]
      ,[ADJ_PRICE_NetNeg]
      ,[Vertex Tax Area]
      ,HotwireHotelID)
      
SELECT 
	'REPORTENDDATE' = CONVERT(VARCHAR(10), l.[REPORTENDDATE], 20)
      ,l.[BOOK_YEAR_MONTH]
      ,l.[TRANS_YEAR_MONTH]
      ,l.[USE_YEAR_MONTH]
      ,l.[BKG_ITM_ID]
      ,l.[ORDER_CONF_NBR]
      ,'BEGIN_USE_DATE' = CONVERT(VARCHAR(10), l.[BEGIN_USE_DATE], 20)
      ,'END_USE_DATE' = CONVERT(VARCHAR(10), l.[END_USE_DATE], 20)
      ,l.[TRANS_TYP_NAME]
      ,l.[EXPE_LODG_PROPERTY_ID]
      ,l.[LGL_ENTITY_CODE]
      ,'LGL_ENTITY_NAME' = REPLACE(l.[LGL_ENTITY_NAME], ',','')
      ,l.[BUSINESS_UNIT_ID]
      ,'BUSINESS_UNIT_NAME' = REPLACE(l.[BUSINESS_UNIT_NAME], ',','')
      ,'LODG_PROPERTY_NAME' = REPLACE(l.[LODG_PROPERTY_NAME], ',','')
      ,'PROPERTY_CITY_NAME' = REPLACE(REPLACE(REPLACE(l.[PROPERTY_CITY_NAME], ',',''), '-',''), '.','')
      ,l.[PROPERTY_STATE_PROVNC_NAME]
      ,l.[PROPERTY_POSTAL_CODE]
      ,l.[PRICE_CURRN_CODE]
      ,l.[OPER_UNIT_ID]
      ,l.[GL_PRODUCT_ID]
      ,l.[MGMT_UNIT_CODE]
      ,l.[ORACLE_GL_PRODUCT_CODE]
      ,l.[RM_NIGHT_CNT]
      ,'COMPUTED_ROOM_NIGHT_COUNT' = CASE WHEN [RM_NIGHT_CNT] = 0 THEN 0 ELSE (3.5*[RM_NIGHT_CNT])-(1.5*[RM_NIGHT_CNT]) END
      ,'SALES_TAX_AREA' = ISNULL(l.[SALES_TAX_AREA],'')
      ,'COUNTY_TAX_AREA' = ISNULL(r.[COUNTY TAX AREA], '')
      ,'CITY_TAX_AREA' = ISNULL(r.[CITY TAX AREA], '')
      ,'GET_TAX_AREA' = ISNULL(l.[GET_TAX_AREA], '')
      ,l.[SALES_TAX_RATE]
      ,l.[COUNTY_TAX_RATE]
      ,l.[CITY_TAX_RATE]
      ,l.[GET_TAX_RATE]
      ,l.[TOTAL_TAX_RATE]
      ,l.[BASE_PRICE_USD]
      ,l.[FLAT_ADJ_USD]
      ,l.[ALL_OTHR_ADJ_USD]
      ,l.[SVC_FEE_PRICE_USD]
      ,l.[ALL_OTHR_FEES_USD]
      ,l.[TOTAL_TAX_USD]
      ,l.[TOTAL_PRICE_USD]
      ,l.[BASE_COST_USD]
      ,l.[FLAT_COST_ADJ_USD]
      ,l.[OTHR_COST_ADJ_USD]
      ,l.[TOTAL_COST_FEE_USD]
      ,l.[TOTAL_COST_USD]
      ,l.[TAX_COLLECTED]
      ,l.[TOTAL_PRICE_FEE_USD]
      ,l.[TAX_BASE_MARGIN]
      ,l.[TAX_BASE_COST]
      ,l.[PRICE_TAX_ADJ_WZEROFLAT]
      ,l.[PRICE_TAX_ADJ]
      ,l.[COST_TAX_ADJ]
      ,l.[COST_TAX_ADJ_WCANCEL]
      ,l.[InsertedDate]
      -------Price Options
      ,'ADJ_PRICE_GA' =  ROUND((l.[ALL_OTHR_ADJ_USD] - l.[PRICE_TAX_ADJ]) + (l.[FLAT_ADJ_USD] + l.[ALL_OTHR_FEES_USD] + l.[BASE_PRICE_USD]),2)
      ,'ADJ_PRICE_NY' = ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ_WZEROFLAT]),2)
      ,'ADJ_PRICE' =  ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ]) ,2)
      -------Cost Options
      ,'ADJ_COST_WPriceFee' = (l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD] + l.[TOTAL_COST_FEE_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) 
      ,'ADJ_COST_GA' = (l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) 
      -------Margin Options
      ,'ADJ_PRICE_GA-ADJ_COST_WPriceFee' = ROUND((ROUND((l.[ALL_OTHR_ADJ_USD] - l.[PRICE_TAX_ADJ]) + (l.[FLAT_ADJ_USD] + l.[ALL_OTHR_FEES_USD] + l.[BASE_PRICE_USD]),2) )
										- ( (l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD] + l.[TOTAL_COST_FEE_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ),2)
      ,'ADJ_PRICE_GA-ADJ_COST_GA' = ROUND((ROUND((l.[ALL_OTHR_ADJ_USD] - l.[PRICE_TAX_ADJ]) + (l.[FLAT_ADJ_USD] + l.[ALL_OTHR_FEES_USD] + l.[BASE_PRICE_USD]),2))
									-( (l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ),2)

	  ,'ADJ_PRICE_NY-ADJ_COST_WPriceFee' = ROUND(( ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ_WZEROFLAT]),2) )
										- ((l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD] + l.[TOTAL_COST_FEE_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ),2)
	  ,'ADJ_PRICE_NY-ADJ_COST_GA' = ROUND(( ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ_WZEROFLAT]),2) )
								- ( (l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ),2)
								
	  ,'ADJ_PRICE-ADJ_COST_WPriceFee' = ROUND((ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ]) ,2) ) 
									- (	(l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD] + l.[TOTAL_COST_FEE_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ),2)
	  ,'ADJ_PRICE-ADJ_COST_GA' = ROUND((ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ]) ,2) )
								- ( (l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ),2)																																	
      --------Tax Due Options on Price (aka Gross/Single Remit)
      ,'ADJ_PRICE_GA-CityTaxDue' =  ROUND((ROUND((l.[ALL_OTHR_ADJ_USD] - l.[PRICE_TAX_ADJ]) + (l.[FLAT_ADJ_USD] + l.[ALL_OTHR_FEES_USD] + l.[BASE_PRICE_USD]),2))*l.[CITY_TAX_RATE],2)
      ,'ADJ_PRICE_GA-CountyTaxDue' = ROUND((ROUND((l.[ALL_OTHR_ADJ_USD] - l.[PRICE_TAX_ADJ]) + (l.[FLAT_ADJ_USD] + l.[ALL_OTHR_FEES_USD] + l.[BASE_PRICE_USD]),2))*l.[COUNTY_TAX_RATE],2)
      ,'ADJ_PRICE_GA-SalesTaxDue' = ROUND((ROUND((l.[ALL_OTHR_ADJ_USD] - l.[PRICE_TAX_ADJ]) + (l.[FLAT_ADJ_USD] + l.[ALL_OTHR_FEES_USD] + l.[BASE_PRICE_USD]),2))*l.[SALES_TAX_RATE],2)
      ,'ADJ_PRICE_GA-GETTaxDue' = ROUND((ROUND((l.[ALL_OTHR_ADJ_USD] - l.[PRICE_TAX_ADJ]) + (l.[FLAT_ADJ_USD] + l.[ALL_OTHR_FEES_USD] + l.[BASE_PRICE_USD]),2))*l.[GET_TAX_RATE],2)
      ,'ADJ_PRICE_GA-TotalTaxDue' = ROUND((ROUND((l.[ALL_OTHR_ADJ_USD] - l.[PRICE_TAX_ADJ]) + (l.[FLAT_ADJ_USD] + l.[ALL_OTHR_FEES_USD] + l.[BASE_PRICE_USD]),2))*l.[TOTAL_TAX_RATE],2)
      
      ,'ADJ_PRICE_NY-CityTaxDue' =  ROUND((ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ_WZEROFLAT]),2))*l.[CITY_TAX_RATE],2)
      ,'ADJ_PRICE_NY-CountyTaxDue' =  ROUND((ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ_WZEROFLAT]),2))*l.[COUNTY_TAX_RATE],2)
      ,'ADJ_PRICE_NY-SalesTaxDue' =  ROUND((ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ_WZEROFLAT]),2))*l.[SALES_TAX_RATE],2)
      ,'ADJ_PRICE_NY-GETTaxDue' =  ROUND((ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ_WZEROFLAT]),2))*l.[GET_TAX_RATE],2)
      ,'ADJ_PRICE_NY-TotalTaxDue' =  ROUND((ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ_WZEROFLAT]),2))*l.[TOTAL_TAX_RATE],2)
      
      ,'ADJ_PRICE-CityTaxDue' =  ROUND((ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ]) ,2))*l.[CITY_TAX_RATE],2)
      ,'ADJ_PRICE-CountyTaxDue' =  ROUND((ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ]) ,2))*l.[COUNTY_TAX_RATE],2)
      ,'ADJ_PRICE-SalesTaxDue' =  ROUND((ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ]) ,2))*l.[SALES_TAX_RATE],2)
      ,'ADJ_PRICE-GETTaxDue' =  ROUND((ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ]) ,2))*l.[GET_TAX_RATE],2)
      ,'ADJ_PRICE-TotalTaxDue' =  ROUND((ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ]) ,2))*l.[TOTAL_TAX_RATE],2)
      
      
      
      
      
      --------Tax Due Options on Margin
      ,'ADJ_PRICE_GA-ADJ_COST_WPriceFee-CityTaxDue' = ROUND((( ROUND((l.[ALL_OTHR_ADJ_USD] - l.[PRICE_TAX_ADJ]) + (l.[FLAT_ADJ_USD] + l.[ALL_OTHR_FEES_USD] + l.[BASE_PRICE_USD]),2) )
													- ( (l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD] + l.[TOTAL_COST_FEE_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ))*l.[CITY_TAX_RATE],2)
	  ,'ADJ_PRICE_GA-ADJ_COST_WPriceFee-CountyTaxDue' = ROUND((( ROUND((l.[ALL_OTHR_ADJ_USD] - l.[PRICE_TAX_ADJ]) + (l.[FLAT_ADJ_USD] + l.[ALL_OTHR_FEES_USD] + l.[BASE_PRICE_USD]),2) )
													- ( (l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD] + l.[TOTAL_COST_FEE_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ))*l.[COUNTY_TAX_RATE],2)	
	  ,'ADJ_PRICE_GA-ADJ_COST_WPriceFee-SalesTaxDue' = ROUND((( ROUND((l.[ALL_OTHR_ADJ_USD] - l.[PRICE_TAX_ADJ]) + (l.[FLAT_ADJ_USD] + l.[ALL_OTHR_FEES_USD] + l.[BASE_PRICE_USD]),2))
													- ( (l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD] + l.[TOTAL_COST_FEE_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ))*l.[SALES_TAX_RATE],2)
	  ,'ADJ_PRICE_GA-ADJ_COST_WPriceFee-GETTaxDue' = ROUND((( ROUND((l.[ALL_OTHR_ADJ_USD] - l.[PRICE_TAX_ADJ]) + (l.[FLAT_ADJ_USD] + l.[ALL_OTHR_FEES_USD] + l.[BASE_PRICE_USD]),2))
													- ( (l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD] + l.[TOTAL_COST_FEE_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ))*l.[GET_TAX_RATE],2)																																						
	  ,'ADJ_PRICE_GA-ADJ_COST_WPriceFee-TotalTaxDue' = ROUND((( ROUND((l.[ALL_OTHR_ADJ_USD] - l.[PRICE_TAX_ADJ]) + (l.[FLAT_ADJ_USD] + l.[ALL_OTHR_FEES_USD] + l.[BASE_PRICE_USD]),2) )
													- ( (l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD] + l.[TOTAL_COST_FEE_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ))*l.[TOTAL_TAX_RATE],2)	
				
	  ,'ADJ_PRICE_GA-ADJ_COST_GA-CityTaxDue' = ROUND(((ROUND((l.[ALL_OTHR_ADJ_USD] - l.[PRICE_TAX_ADJ]) + (l.[FLAT_ADJ_USD] + l.[ALL_OTHR_FEES_USD] + l.[BASE_PRICE_USD]),2))
											-( (l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ))*l.[CITY_TAX_RATE],2)	
	  ,'ADJ_PRICE_GA-ADJ_COST_GA-CountyTaxDue' = ROUND(((ROUND((l.[ALL_OTHR_ADJ_USD] - l.[PRICE_TAX_ADJ]) + (l.[FLAT_ADJ_USD] + l.[ALL_OTHR_FEES_USD] + l.[BASE_PRICE_USD]),2))
											-( (l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ))*l.[COUNTY_TAX_RATE],2)
	  ,'ADJ_PRICE_GA-ADJ_COST_GA-SalesTaxDue' = ROUND(((ROUND((l.[ALL_OTHR_ADJ_USD] - l.[PRICE_TAX_ADJ]) + (l.[FLAT_ADJ_USD] + l.[ALL_OTHR_FEES_USD] + l.[BASE_PRICE_USD]),2))
											-( (l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ))*l.[SALES_TAX_RATE],2)	
	  ,'ADJ_PRICE_GA-ADJ_COST_GA-GETTaxDue' = ROUND(((ROUND((l.[ALL_OTHR_ADJ_USD] - l.[PRICE_TAX_ADJ]) + (l.[FLAT_ADJ_USD] + l.[ALL_OTHR_FEES_USD] + l.[BASE_PRICE_USD]),2))
											-( (l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ))*l.[GET_TAX_RATE],2)	
	  ,'ADJ_PRICE_GA-ADJ_COST_GA-TotalTaxDue' = ROUND(((ROUND((l.[ALL_OTHR_ADJ_USD] - l.[PRICE_TAX_ADJ]) + (l.[FLAT_ADJ_USD] + l.[ALL_OTHR_FEES_USD] + l.[BASE_PRICE_USD]),2))
											-( (l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ))*l.[TOTAL_TAX_RATE],2)	
											
	  ,'ADJ_PRICE_NY-ADJ_COST_WPriceFee-CityTaxDue' = ROUND((( ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ_WZEROFLAT]),2) )
													- (  (l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD] + l.[TOTAL_COST_FEE_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ))*l.[CITY_TAX_RATE],2)																																																									
	  ,'ADJ_PRICE_NY-ADJ_COST_WPriceFee-CountyTaxDue' = ROUND((( ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ_WZEROFLAT]),2) )
													- (  (l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD] + l.[TOTAL_COST_FEE_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ))*l.[COUNTY_TAX_RATE],2)	
	  ,'ADJ_PRICE_NY-ADJ_COST_WPriceFee-SalesTaxDue' = ROUND((( ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ_WZEROFLAT]),2) )
													- (  (l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD] + l.[TOTAL_COST_FEE_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ))*l.[SALES_TAX_RATE],2)	
	  ,'ADJ_PRICE_NY-ADJ_COST_WPriceFee-GETTaxDue' = ROUND((( ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ_WZEROFLAT]),2) )
													- (  (l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD] + l.[TOTAL_COST_FEE_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ))*l.[GET_TAX_RATE],2)
	  ,'ADJ_PRICE_NY-ADJ_COST_WPriceFee-TotalTaxDue' = ROUND((( ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ_WZEROFLAT]),2) )
													- (  (l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD] + l.[TOTAL_COST_FEE_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ))*l.[TOTAL_TAX_RATE],2)	

	  ,'ADJ_PRICE_NY-ADJ_COST_GA-CityTaxDue' = ROUND((( ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ_WZEROFLAT]),2))
											- ( (l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ))*l.[CITY_TAX_RATE], 2)
	  ,'ADJ_PRICE_NY-ADJ_COST_GA-CountyTaxDue' = ROUND((( ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ_WZEROFLAT]),2) )
											- ( (l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ))*l.[COUNTY_TAX_RATE], 2)	
	  ,'ADJ_PRICE_NY-ADJ_COST_GA-SalesTaxDue' = ROUND((( ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ_WZEROFLAT]),2) )
											- ( (l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ))*l.[SALES_TAX_RATE], 2)	
	  ,'ADJ_PRICE_NY-ADJ_COST_GA-GETTaxDue' = ROUND((( ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ_WZEROFLAT]),2) )
											- ( (l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ))*l.[GET_TAX_RATE], 2)
	  ,'ADJ_PRICE_NY-ADJ_COST_GA-TotalTaxDue' = ROUND((( ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ_WZEROFLAT]),2) )
											- ( (l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ))*l.[TOTAL_TAX_RATE], 2)

	  ,'ADJ_PRICE-ADJ_COST_WPriceFee-CityTaxDue' = ROUND(((ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ]) ,2)) 
													- (	(l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD] + l.[TOTAL_COST_FEE_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ))*l.[CITY_TAX_RATE],2)
 	  ,'ADJ_PRICE-ADJ_COST_WPriceFee-CountyTaxDue' = ROUND(((ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ]) ,2)) 
													- (	(l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD] + l.[TOTAL_COST_FEE_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ))*l.[COUNTY_TAX_RATE],2)
 	  ,'ADJ_PRICE-ADJ_COST_WPriceFee-SalesTaxDue' = ROUND(((ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ]) ,2)) 
													- (	(l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD] + l.[TOTAL_COST_FEE_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ))*l.[SALES_TAX_RATE],2) 
 	  ,'ADJ_PRICE-ADJ_COST_WPriceFee-GETTaxDue' = ROUND(((ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ]) ,2)) 
													- (	(l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD] + l.[TOTAL_COST_FEE_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ))*l.[GET_TAX_RATE],2)													
 	  ,'ADJ_PRICE-ADJ_COST_WPriceFee-TotalTaxDue' = ROUND(((ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ]) ,2)) 
													- (	(l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD] + l.[TOTAL_COST_FEE_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ))*l.[TOTAL_TAX_RATE],2)	

	  ,'ADJ_PRICE-ADJ_COST_GA-CityTaxDue' = ROUND(((ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ]) ,2))
										- ( (l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ))*l.[CITY_TAX_RATE],2)
	  ,'ADJ_PRICE-ADJ_COST_GA-CountyTaxDue' = ROUND(((ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ]) ,2))
										- ( (l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ))*l.[COUNTY_TAX_RATE],2)
	  ,'ADJ_PRICE-ADJ_COST_GA-SalesTaxDue' = ROUND(((ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ]) ,2))
										- ( (l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ))*l.[SALES_TAX_RATE],2)
	  ,'ADJ_PRICE-ADJ_COST_GA-GETTaxDue' = ROUND(((ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ]) ,2))
										- ( (l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ))*l.[GET_TAX_RATE],2)										
	  ,'ADJ_PRICE-ADJ_COST_GA-TotalTaxDue' = ROUND(((ROUND((l.[BASE_PRICE_USD] + l.[ALL_OTHR_ADJ_USD] + l.[TOTAL_PRICE_FEE_USD]) + (l.[FLAT_ADJ_USD] - l.[PRICE_TAX_ADJ]) ,2))
										- ( (l.[BASE_COST_USD] + l.[OTHR_COST_ADJ_USD]) + (l.[FLAT_COST_ADJ_USD] - l.[COST_TAX_ADJ_WCANCEL]) ))*l.[TOTAL_TAX_RATE],2)
	  ---------Negative Margin Flagged Fields
	  ,'ADJ_PRICE_GA-ADJ_COST_WPriceFee_NetNeg' = nnm.[ADJ_PRICE_GA-ADJ_COST_WPriceFee_NetNeg]
	  ,'ADJ_PRICE_GA-ADJ_COST_GA_NetNeg' = nnm.[ADJ_PRICE_GA-ADJ_COST_GA_NetNeg]
	  ,'ADJ_PRICE_NY-ADJ_COST_WPriceFee_NetNeg' = nnm.[ADJ_PRICE_NY-ADJ_COST_WPriceFee_NetNeg]
	  ,'ADJ_PRICE_NY-ADJ_COST_GA_NetNeg' = nnm.[ADJ_PRICE_NY-ADJ_COST_GA_NetNeg]
	  ,'ADJ_PRICE-ADJ_COST_WPriceFee_NetNeg' = nnm.[ADJ_PRICE-ADJ_COST_WPriceFee_NetNeg]
	  ,'ADJ_PRICE-ADJ_COST_GA_NetNeg' = nnm.[ADJ_PRICE-ADJ_COST_GA_NetNeg]
	  ,'ADJ_PRICE_NetNeg' = nnm.[ADJ_PRICE_NetNeg]
	  ,r.[Vertex Tax Area]
	  ,'HotwireHotelID' = 0
																			      
  FROM [Compliance].[Lodging].[V_EDW] l
  LEFT JOIN #Net_Negative_Margin nnm ON l.[BKG_ITM_ID] = nnm.[BKG_ITM_ID]
  LEFT JOIN Rates.V_CSV r ON l.EXPE_LODG_PROPERTY_ID = r.[Expedia ID];

-------Compiling the Breakage Data with the Monthly EDW Compliance Data
---(660K rows, 3 minutes)
INSERT INTO [Compliance].[Lodging].[MonthlyCalculatedData]
	(  [REPORTENDDATE]
      ,[BOOK_YEAR_MONTH]
      ,[TRANS_YEAR_MONTH]
      ,[USE_YEAR_MONTH]
      ,[BKG_ITM_ID]
      ,[ORDER_CONF_NBR]
      ,[BEGIN_USE_DATE]
      ,[END_USE_DATE]
      ,[TRANS_TYP_NAME]
      ,[EXPE_LODG_PROPERTY_ID]
      ,[LGL_ENTITY_CODE]
      ,[LGL_ENTITY_NAME]
      ,[BUSINESS_UNIT_ID]
      ,[BUSINESS_UNIT_NAME]
      ,[LODG_PROPERTY_NAME]
      ,[PROPERTY_CITY_NAME]
      ,[PROPERTY_STATE_PROVNC_NAME]
      ,[PROPERTY_POSTAL_CODE]
      ,[PRICE_CURRN_CODE]
      ,[OPER_UNIT_ID]
      ,[GL_PRODUCT_ID]
      ,[MGMT_UNIT_CODE]
      ,[ORACLE_GL_PRODUCT_CODE]
      ,[RM_NIGHT_CNT]
      ,[COMPUTED_ROOM_NIGHT_COUNT]
      ,[SALES_TAX_AREA]
      ,[COUNTY_TAX_AREA]
      ,[CITY_TAX_AREA]
      ,[GET_TAX_AREA]
      ,[SALES_TAX_RATE]
      ,[COUNTY_TAX_RATE]
      ,[CITY_TAX_RATE]
      ,[GET_TAX_RATE]
      ,[TOTAL_TAX_RATE]
      ,[BASE_PRICE_USD]
      ,[FLAT_ADJ_USD]
      ,[ALL_OTHR_ADJ_USD]
      ,[SVC_FEE_PRICE_USD]
      ,[ALL_OTHR_FEES_USD]
      ,[TOTAL_TAX_USD]
      ,[TOTAL_PRICE_USD]
      ,[BASE_COST_USD]
      ,[FLAT_COST_ADJ_USD]
      ,[OTHR_COST_ADJ_USD]
      ,[TOTAL_COST_FEE_USD]
      ,[TOTAL_COST_USD]
      ,[TAX_COLLECTED]
      ,[TOTAL_PRICE_FEE_USD]
      ,[TAX_BASE_MARGIN]
      ,[TAX_BASE_COST]
      ,[PRICE_TAX_ADJ_WZEROFLAT]
      ,[PRICE_TAX_ADJ]
      ,[COST_TAX_ADJ]
      ,[COST_TAX_ADJ_WCANCEL]
      ,[InsertedDate]
      ,[ADJ_PRICE_GA]
      ,[ADJ_PRICE_NY]
      ,[ADJ_PRICE]
      ,[ADJ_COST_WPriceFee]
      ,[ADJ_COST_GA]
      ,[ADJ_PRICE_GA-ADJ_COST_WPriceFee]
      ,[ADJ_PRICE_GA-ADJ_COST_GA]
      ,[ADJ_PRICE_NY-ADJ_COST_WPriceFee]
      ,[ADJ_PRICE_NY-ADJ_COST_GA]
      ,[ADJ_PRICE-ADJ_COST_WPriceFee]
      ,[ADJ_PRICE-ADJ_COST_GA]
      ,[ADJ_PRICE_GA-CityTaxDue]
      ,[ADJ_PRICE_GA-CountyTaxDue]
      ,[ADJ_PRICE_GA-SalesTaxDue]
      ,[ADJ_PRICE_GA-GETTaxDue]
      ,[ADJ_PRICE_GA-TotalTaxDue]
      ,[ADJ_PRICE_NY-CityTaxDue] 
	  ,[ADJ_PRICE_NY-CountyTaxDue]
	  ,[ADJ_PRICE_NY-SalesTaxDue] 
      ,[ADJ_PRICE_NY-GETTaxDue] 
	  ,[ADJ_PRICE_NY-TotalTaxDue] 
	  ,[ADJ_PRICE-CityTaxDue] 
	  ,[ADJ_PRICE-CountyTaxDue] 
	  ,[ADJ_PRICE-SalesTaxDue] 
	  ,[ADJ_PRICE-GETTaxDue] 
	  ,[ADJ_PRICE-TotalTaxDue] 
      ,[ADJ_PRICE_GA-ADJ_COST_WPriceFee-CityTaxDue]
      ,[ADJ_PRICE_GA-ADJ_COST_WPriceFee-CountyTaxDue]
      ,[ADJ_PRICE_GA-ADJ_COST_WPriceFee-SalesTaxDue]
      ,[ADJ_PRICE_GA-ADJ_COST_WPriceFee-GETTaxDue]
      ,[ADJ_PRICE_GA-ADJ_COST_WPriceFee-TotalTaxDue]
      ,[ADJ_PRICE_GA-ADJ_COST_GA-CityTaxDue]
      ,[ADJ_PRICE_GA-ADJ_COST_GA-CountyTaxDue]
      ,[ADJ_PRICE_GA-ADJ_COST_GA-SalesTaxDue]
      ,[ADJ_PRICE_GA-ADJ_COST_GA-GETTaxDue]
      ,[ADJ_PRICE_GA-ADJ_COST_GA-TotalTaxDue]
      ,[ADJ_PRICE_NY-ADJ_COST_WPriceFee-CityTaxDue]
      ,[ADJ_PRICE_NY-ADJ_COST_WPriceFee-CountyTaxDue]
      ,[ADJ_PRICE_NY-ADJ_COST_WPriceFee-SalesTaxDue]
      ,[ADJ_PRICE_NY-ADJ_COST_WPriceFee-GETTaxDue]
      ,[ADJ_PRICE_NY-ADJ_COST_WPriceFee-TotalTaxDue]
      ,[ADJ_PRICE_NY-ADJ_COST_GA-CityTaxDue]
      ,[ADJ_PRICE_NY-ADJ_COST_GA-CountyTaxDue]
      ,[ADJ_PRICE_NY-ADJ_COST_GA-SalesTaxDue]
      ,[ADJ_PRICE_NY-ADJ_COST_GA-GETTaxDue]
      ,[ADJ_PRICE_NY-ADJ_COST_GA-TotalTaxDue]
      ,[ADJ_PRICE-ADJ_COST_WPriceFee-CityTaxDue]
      ,[ADJ_PRICE-ADJ_COST_WPriceFee-CountyTaxDue]
      ,[ADJ_PRICE-ADJ_COST_WPriceFee-SalesTaxDue]
      ,[ADJ_PRICE-ADJ_COST_WPriceFee-GETTaxDue]
      ,[ADJ_PRICE-ADJ_COST_WPriceFee-TotalTaxDue]
      ,[ADJ_PRICE-ADJ_COST_GA-CityTaxDue]
      ,[ADJ_PRICE-ADJ_COST_GA-CountyTaxDue]
      ,[ADJ_PRICE-ADJ_COST_GA-SalesTaxDue]
      ,[ADJ_PRICE-ADJ_COST_GA-GETTaxDue]
      ,[ADJ_PRICE-ADJ_COST_GA-TotalTaxDue]
      ,[ADJ_PRICE_GA-ADJ_COST_WPriceFee_NetNeg]
      ,[ADJ_PRICE_GA-ADJ_COST_GA_NetNeg]
      ,[ADJ_PRICE_NY-ADJ_COST_WPriceFee_NetNeg]
      ,[ADJ_PRICE_NY-ADJ_COST_GA_NetNeg]
      ,[ADJ_PRICE-ADJ_COST_WPriceFee_NetNeg]
      ,[ADJ_PRICE-ADJ_COST_GA_NetNeg]
      ,[ADJ_PRICE_NetNeg]
      ,[Vertex Tax Area]
      ,HotwireHotelID)
SELECT  
		'REPORTENDDATE' = @BreakageBeginUseMonth
		,'BOOK_YEAR_MONTH' = CAST(CONVERT(VARCHAR(6), @BreakageBeginUseMonth, 112) AS INT)
		,'TRANS_YEAR_MONTH' = 0
		,'USE_YEAR_MONTH' = BEGIN_USE_YEAR_MONTH
		,'BKG_ITM_ID' = BKG_ITM_ID
		,'ORDER_CONF_NBR' = 'na'
		,'BEGIN_USE_DATE' = @BreakageBeginUseMonth
		,'END_USE_DATE' = @BreakageBeginUseMonth
		,'TRANS_TYP_NAME' = 'Cost Adjustment'
		,'EXPE_LODG_PROPERTY_ID' = b.EXPE_LODG_PROPERTY_ID
		,'LGL_ENTITY_CODE' = LGL_ENTITY_CODE
		,'LGL_ENTITY_NAME' = LGL_ENTITY_NAME
		,'BUSINESS_UNIT_ID' = b.BUSINESS_UNIT_ID
		,'BUSINESS_UNIT_NAME' = bu.BUSINESS_UNIT_NAME
		,'LODG_PROPERTY_NAME' = LODG_PROPERTY_NAME
		,'PROPERTY_CITY_NAME' = lp.PROPERTY_CITY_NAME
		,'PROPERTY_STATE_PROVNC_NAME' = PROPERTY_STATE_PROVNC_NAME
		,'PROPERTY_POSTAL_CODE' = PROPERTY_POSTAL_CODE
		,'PRICE_CURRN_CODE' = 'na'
		,'OPER_UNIT_ID' = OPER_UNIT_ID
		,'GL_PRODUCT_ID' = GL_PRODUCT_ID
		,'MGMT_UNIT_CODE' = MGMT_UNIT_CODE
		,'ORACLE_GL_PRODUCT_CODE' = ORACLE_GL_PRODUCT_CODE
		,'RM_NIGHT_CNT' = 0
		,'COMPUTED_ROOM_NIGHT_COUNT' = 0
		,'SALES_TAX_AREA' = ISNULL(SALES_TAX_AREA_NAME, '')
		,'COUNTY_TAX_AREA' = ISNULL(r.[COUNTY TAX AREA], '')
		,'CITY_TAX_AREA' = ISNULL(r.[CITY TAX AREA], '')
		,'GET_TAX_AREA' = ISNULL(GET_TAX_AREA_NAME, '')
		,'SALES_TAX_RATE' = SALES_TAX_RATE
		,'COUNTY_TAX_RATE' = COUNTY_TAX_RATE
		,'CITY_TAX_RATE' = CITY_TAX_RATE
		,'GET_TAX_RATE' = GET_TAX_RATE
		,'TOTAL_TAX_RATE' = TOTL_TAX_RATE
		,'BASE_PRICE_USD' = 0
		,'FLAT_ADJ_USD' = 0
		,'ALL_OTHR_ADJ_USD' = 0
		,'SVC_FEE_PRICE_USD' = 0
		,'ALL_OTHR_FEES_USD' = 0
		,'TOTAL_TAX_USD' = 0
		,'TOTAL_PRICE_USD' = 0 
		,'BASE_COST_USD' = 0
		,'FLAT_COST_ADJ_USD' = 0
		,'OTHR_COST_ADJ_USD' = 0
		,'TOTAL_COST_FEE_USD' = 0
		,'TOTAL_COST_USD' = [TOTL_COST_AMT_USD]
		,'TAX_COLLECTED' = 0
		,'TOTAL_PRICE_FEE_USD' = 0
		,'TAX_BASE_MARGIN' = 0
		,'TAX_BASE_COST' = 0
		,'PRICE_TAX_ADJ_WZEROFLAT' = 0
		,'PRICE_TAX_ADJ' = 0
		,'COST_TAX_ADJ' = 0
		,'COST_TAX_ADJ_WCANCEL' = 0
		,'InsertedDate' = b.InsertedDate
		,'ADJ_PRICE_GA' = ROUND( ( ([TOTL_COST_AMT_USD])  /  (1+[TOTL_TAX_RATE]) ) ,2)
		,'ADJ_PRICE_NY' = ROUND((([TOTL_COST_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)
		,'ADJ_PRICE'	= ROUND((([TOTL_COST_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)
		,'ADJ_COST_WPriceFee'	= ROUND((([MC20TransAmtCost] + [NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)
		,'ADJ_COST_GA'			= ROUND((([MC20TransAmtCost] + [NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)
		----Margin Options
		,'ADJ_PRICE_GA-ADJ_COST_WPriceFee' =  ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)
		,'ADJ_PRICE_GA-ADJ_COST_GA' = ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)
		,'ADJ_PRICE_NY-ADJ_COST_WPriceFee' = ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)
		,'ADJ_PRICE_NY-ADJ_COST_GA' = ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)
		,'ADJ_PRICE-ADJ_COST_WPriceFee' = ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)
		,'ADJ_PRICE-ADJ_COST_GA' = ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)
		--------Tax Due Options on Price (aka Gross/Single Remit)
		,'ADJ_PRICE_GA-CityTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[CITY_TAX_RATE]),2) 
		,'ADJ_PRICE_GA-CountyTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[COUNTY_TAX_RATE]),2) 
		,'ADJ_PRICE_GA-SalesTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[SALES_TAX_RATE]),2) 
		,'ADJ_PRICE_GA-GETTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[GET_TAX_RATE]),2) 
		,'ADJ_PRICE_GA-TotalTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[TOTL_TAX_RATE]),2) 
	  
	    ,'ADJ_PRICE_NY-CityTaxDue' =  ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[CITY_TAX_RATE]),2)
	    ,'ADJ_PRICE_NY-CountyTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[COUNTY_TAX_RATE]),2)
	    ,'ADJ_PRICE_NY-SalesTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[SALES_TAX_RATE]),2)
	    ,'ADJ_PRICE_NY-GETTaxDue' =  ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[GET_TAX_RATE]),2)
	    ,'ADJ_PRICE_NY-TotalTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[TOTL_TAX_RATE]),2)
	  
	    ,'ADJ_PRICE-CityTaxDue' =  ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[CITY_TAX_RATE]),2)
	    ,'ADJ_PRICE-CountyTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[COUNTY_TAX_RATE]),2)
	    ,'ADJ_PRICE-SalesTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[SALES_TAX_RATE]),2)
	    ,'ADJ_PRICE-GETTaxDue' =  ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[GET_TAX_RATE]),2)
	    ,'ADJ_PRICE-TotalTaxDue' =  ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[TOTL_TAX_RATE]),2)		
		 
		--------Tax Due Options on Margin
		,'ADJ_PRICE_GA-ADJ_COST_WPriceFee-CityTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[CITY_TAX_RATE]),2)
		,'ADJ_PRICE_GA-ADJ_COST_WPriceFee-CountyTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[COUNTY_TAX_RATE]),2)
		,'ADJ_PRICE_GA-ADJ_COST_WPriceFee-SalesTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[SALES_TAX_RATE]),2) 
		,'ADJ_PRICE_GA-ADJ_COST_WPriceFee-GETTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[GET_TAX_RATE]),2) 
		,'ADJ_PRICE_GA-ADJ_COST_WPriceFee-TotalTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[TOTL_TAX_RATE]),2)   
		,'ADJ_PRICE_GA-ADJ_COST_GA-CityTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[CITY_TAX_RATE]),2)
		,'ADJ_PRICE_GA-ADJ_COST_GA-CountyTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[COUNTY_TAX_RATE]),2)
		,'ADJ_PRICE_GA-ADJ_COST_GA-SalesTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[SALES_TAX_RATE]),2) 
		,'ADJ_PRICE_GA-ADJ_COST_GA-GETTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[GET_TAX_RATE]),2) 
		,'ADJ_PRICE_GA-ADJ_COST_GA-TotalTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[TOTL_TAX_RATE]),2)   
		,'ADJ_PRICE_NY-ADJ_COST_WPriceFee-CityTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[CITY_TAX_RATE]),2)
		,'ADJ_PRICE_NY-ADJ_COST_WPriceFee-CountyTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[COUNTY_TAX_RATE]),2) 
		,'ADJ_PRICE_NY-ADJ_COST_WPriceFee-SalesTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[SALES_TAX_RATE]),2) 
		,'ADJ_PRICE_NY-ADJ_COST_WPriceFee-GETTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[GET_TAX_RATE]),2) 
		,'ADJ_PRICE_NY-ADJ_COST_WPriceFee-TotalTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[TOTL_TAX_RATE]),2)   
		,'ADJ_PRICE_NY-ADJ_COST_GA-CityTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[CITY_TAX_RATE]),2)
		,'ADJ_PRICE_NY-ADJ_COST_GA-CountyTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[COUNTY_TAX_RATE]),2) 
		,'ADJ_PRICE_NY-ADJ_COST_GA-SalesTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[SALES_TAX_RATE]),2) 
		,'ADJ_PRICE_NY-ADJ_COST_GA-GETTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[GET_TAX_RATE]),2) 
		,'ADJ_PRICE_NY-ADJ_COST_GA-TotalTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[TOTL_TAX_RATE]),2)  
		,'ADJ_PRICE-ADJ_COST_WPriceFee-CityTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[CITY_TAX_RATE]),2)
		,'ADJ_PRICE-ADJ_COST_WPriceFee-CountyTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[COUNTY_TAX_RATE]),2)
		,'ADJ_PRICE-ADJ_COST_WPriceFee-SalesTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[SALES_TAX_RATE]),2) 
		,'ADJ_PRICE-ADJ_COST_WPriceFee-GETTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[GET_TAX_RATE]),2) 
		,'ADJ_PRICE-ADJ_COST_WPriceFee-TotalTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[TOTL_TAX_RATE]),2)  
		,'ADJ_PRICE-ADJ_COST_GA-CityTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[CITY_TAX_RATE]),2)
		,'ADJ_PRICE-ADJ_COST_GA-CountyTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[COUNTY_TAX_RATE]),2) 
		,'ADJ_PRICE-ADJ_COST_GA-SalesTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[SALES_TAX_RATE]),2) 
		,'ADJ_PRICE-ADJ_COST_GA-GETTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[GET_TAX_RATE]),2) 
		,'ADJ_PRICE-ADJ_COST_GA-TotalTaxDue' = ROUND((ROUND((([TOTL_COST_AMT_USD]-[MC20TransAmtCost]-[NET_AP_PAYMNT_AMT_USD])  /  (1+[TOTL_TAX_RATE])),2)*[TOTL_TAX_RATE]),2) 
		---------Negative Margin Flagged Fields
		,'ADJ_PRICE_GA-ADJ_COST_WPriceFee_NetNeg' = 'N'
	    ,'ADJ_PRICE_GA-ADJ_COST_GA_NetNeg' = 'N'
	    ,'ADJ_PRICE_NY-ADJ_COST_WPriceFee_NetNeg' = 'N'
	    ,'ADJ_PRICE_NY-ADJ_COST_GA_NetNeg' = 'N'
	    ,'ADJ_PRICE-ADJ_COST_WPriceFee_NetNeg' = 'N'
	    ,'ADJ_PRICE-ADJ_COST_GA_NetNeg' = 'N' 
	    ,'ADJ_PRICE_NetNeg' = 'N'
	    ,r.[Vertex Tax Area]
	    ,'HotwireHotelID' = 0

FROM Lodging.V_Breakage	b	
LEFT JOIN #BUSINESS_UNIT bu ON b.BUSINESS_UNIT_ID = bu.BUSINESS_UNIT_ID
LEFT JOIN #LODG_PROPERTY lp ON b.EXPE_LODG_PROPERTY_ID = lp.EXPE_LODG_PROPERTY_ID
LEFT JOIN Rates.V_CSV r ON b.EXPE_LODG_PROPERTY_ID = r.[Expedia ID]

WHERE 
(CASE WHEN [GROSS_BKG_AMT_USD] < 0.01 
	THEN 'Price = 0'
	WHEN ([GROSS_BKG_AMT_USD] + [GENRIC_PAYMNT_AMT_USD]) < 0.01
	THEN 'Generic'
	ELSE 'BreakageForTax'
	END) = 'BreakageForTax';

-----------------------------------------------------------
------Insert Hotwire data into table
---(105K rows, 2 minutes)
INSERT INTO [Compliance].[Lodging].[MonthlyCalculatedData]
	(  [REPORTENDDATE]
      ,[BOOK_YEAR_MONTH]
      ,[TRANS_YEAR_MONTH]
      ,[USE_YEAR_MONTH]
      ,[BKG_ITM_ID]
      ,[ORDER_CONF_NBR]
      ,[BEGIN_USE_DATE]
      ,[END_USE_DATE]
      ,[TRANS_TYP_NAME]
      ,[EXPE_LODG_PROPERTY_ID]
      ,[LGL_ENTITY_CODE]
      ,[LGL_ENTITY_NAME]
      ,[BUSINESS_UNIT_ID]
      ,[BUSINESS_UNIT_NAME]
      ,[LODG_PROPERTY_NAME]
      ,[PROPERTY_CITY_NAME]
      ,[PROPERTY_STATE_PROVNC_NAME]
      ,[PROPERTY_POSTAL_CODE]
      ,[PRICE_CURRN_CODE]
      ,[OPER_UNIT_ID]
      ,[GL_PRODUCT_ID]
      ,[MGMT_UNIT_CODE]
      ,[ORACLE_GL_PRODUCT_CODE]
      ,[RM_NIGHT_CNT]
      ,[COMPUTED_ROOM_NIGHT_COUNT]
      ,[SALES_TAX_AREA]
      ,[COUNTY_TAX_AREA]
      ,[CITY_TAX_AREA]
      ,[GET_TAX_AREA]
      ,[SALES_TAX_RATE]
      ,[COUNTY_TAX_RATE]
      ,[CITY_TAX_RATE]
      ,[GET_TAX_RATE]
      ,[TOTAL_TAX_RATE]
      ,[BASE_PRICE_USD]
      ,[FLAT_ADJ_USD]
      ,[ALL_OTHR_ADJ_USD]
      ,[SVC_FEE_PRICE_USD]
      ,[ALL_OTHR_FEES_USD]
      ,[TOTAL_TAX_USD]
      ,[TOTAL_PRICE_USD]
      ,[BASE_COST_USD]
      ,[FLAT_COST_ADJ_USD]
      ,[OTHR_COST_ADJ_USD]
      ,[TOTAL_COST_FEE_USD]
      ,[TOTAL_COST_USD]
      ,[TAX_COLLECTED]
      ,[TOTAL_PRICE_FEE_USD]
      ,[TAX_BASE_MARGIN]
      ,[TAX_BASE_COST]
      ,[PRICE_TAX_ADJ_WZEROFLAT]
      ,[PRICE_TAX_ADJ]
      ,[COST_TAX_ADJ]
      ,[COST_TAX_ADJ_WCANCEL]
      ,[InsertedDate]
      ,[ADJ_PRICE_GA]
      ,[ADJ_PRICE_NY]
      ,[ADJ_PRICE]
      ,[ADJ_COST_WPriceFee]
      ,[ADJ_COST_GA]
      ,[ADJ_PRICE_GA-ADJ_COST_WPriceFee]
      ,[ADJ_PRICE_GA-ADJ_COST_GA]
      ,[ADJ_PRICE_NY-ADJ_COST_WPriceFee]
      ,[ADJ_PRICE_NY-ADJ_COST_GA]
      ,[ADJ_PRICE-ADJ_COST_WPriceFee]
      ,[ADJ_PRICE-ADJ_COST_GA]
      ,[ADJ_PRICE_GA-CityTaxDue]
      ,[ADJ_PRICE_GA-CountyTaxDue]
      ,[ADJ_PRICE_GA-SalesTaxDue]
      ,[ADJ_PRICE_GA-GETTaxDue]
      ,[ADJ_PRICE_GA-TotalTaxDue]
      ,[ADJ_PRICE_NY-CityTaxDue] 
	  ,[ADJ_PRICE_NY-CountyTaxDue]
	  ,[ADJ_PRICE_NY-SalesTaxDue] 
      ,[ADJ_PRICE_NY-GETTaxDue] 
	  ,[ADJ_PRICE_NY-TotalTaxDue] 
	  ,[ADJ_PRICE-CityTaxDue] 
	  ,[ADJ_PRICE-CountyTaxDue] 
	  ,[ADJ_PRICE-SalesTaxDue] 
	  ,[ADJ_PRICE-GETTaxDue] 
	  ,[ADJ_PRICE-TotalTaxDue] 
      ,[ADJ_PRICE_GA-ADJ_COST_WPriceFee-CityTaxDue]
      ,[ADJ_PRICE_GA-ADJ_COST_WPriceFee-CountyTaxDue]
      ,[ADJ_PRICE_GA-ADJ_COST_WPriceFee-SalesTaxDue]
      ,[ADJ_PRICE_GA-ADJ_COST_WPriceFee-GETTaxDue]
      ,[ADJ_PRICE_GA-ADJ_COST_WPriceFee-TotalTaxDue]
      ,[ADJ_PRICE_GA-ADJ_COST_GA-CityTaxDue]
      ,[ADJ_PRICE_GA-ADJ_COST_GA-CountyTaxDue]
      ,[ADJ_PRICE_GA-ADJ_COST_GA-SalesTaxDue]
      ,[ADJ_PRICE_GA-ADJ_COST_GA-GETTaxDue]
      ,[ADJ_PRICE_GA-ADJ_COST_GA-TotalTaxDue]
      ,[ADJ_PRICE_NY-ADJ_COST_WPriceFee-CityTaxDue]
      ,[ADJ_PRICE_NY-ADJ_COST_WPriceFee-CountyTaxDue]
      ,[ADJ_PRICE_NY-ADJ_COST_WPriceFee-SalesTaxDue]
      ,[ADJ_PRICE_NY-ADJ_COST_WPriceFee-GETTaxDue]
      ,[ADJ_PRICE_NY-ADJ_COST_WPriceFee-TotalTaxDue]
      ,[ADJ_PRICE_NY-ADJ_COST_GA-CityTaxDue]
      ,[ADJ_PRICE_NY-ADJ_COST_GA-CountyTaxDue]
      ,[ADJ_PRICE_NY-ADJ_COST_GA-SalesTaxDue]
      ,[ADJ_PRICE_NY-ADJ_COST_GA-GETTaxDue]
      ,[ADJ_PRICE_NY-ADJ_COST_GA-TotalTaxDue]
      ,[ADJ_PRICE-ADJ_COST_WPriceFee-CityTaxDue]
      ,[ADJ_PRICE-ADJ_COST_WPriceFee-CountyTaxDue]
      ,[ADJ_PRICE-ADJ_COST_WPriceFee-SalesTaxDue]
      ,[ADJ_PRICE-ADJ_COST_WPriceFee-GETTaxDue]
      ,[ADJ_PRICE-ADJ_COST_WPriceFee-TotalTaxDue]
      ,[ADJ_PRICE-ADJ_COST_GA-CityTaxDue]
      ,[ADJ_PRICE-ADJ_COST_GA-CountyTaxDue]
      ,[ADJ_PRICE-ADJ_COST_GA-SalesTaxDue]
      ,[ADJ_PRICE-ADJ_COST_GA-GETTaxDue]
      ,[ADJ_PRICE-ADJ_COST_GA-TotalTaxDue]
      ,[ADJ_PRICE_GA-ADJ_COST_WPriceFee_NetNeg]
      ,[ADJ_PRICE_GA-ADJ_COST_GA_NetNeg]
      ,[ADJ_PRICE_NY-ADJ_COST_WPriceFee_NetNeg]
      ,[ADJ_PRICE_NY-ADJ_COST_GA_NetNeg]
      ,[ADJ_PRICE-ADJ_COST_WPriceFee_NetNeg]
      ,[ADJ_PRICE-ADJ_COST_GA_NetNeg]
      ,[ADJ_PRICE_NetNeg]
      ,[Vertex Tax Area]
      ,HotwireHotelID)

SELECT 
	   'REPORTENDDATE' = @HotwireBeginUseMonth
      ,'BOOK_YEAR_MONTH' = CONVERT(VARCHAR(6), BOOK_DATE , 112) 
      ,'TRANS_YEAR_MONTH' = CONVERT(VARCHAR(6), BOOK_DATE , 112) 
      ,'USE_YEAR_MONTH' = CONVERT(VARCHAR(6), BEGIN_USE_DATE, 112)
      ,'BKG_ITM_ID' = CAST(ISNULL(REPLACE(PURCHASE_ORDER_ID,'''',''), 0) AS BIGINT)
      ,'ORDER_CONF_NBR' = REPLACE(RESERVATION_NUM, '''','')
      ,'BEGIN_USE_DATE' = CONVERT(VARCHAR(10), BEGIN_USE_DATE, 20)
      ,'END_USE_DATE' = CONVERT(VARCHAR(10), END_USE_DATE, 20)
      ,'TRANS_TYP_NAME' = STATUS_CODE_DISPLAY_NAME
      ,'EXPE_LODG_PROPERTY_ID' = 0
      ,'LGL_ENTITY_CODE' = 75110
      ,'LGL_ENTITY_NAME' = 'Hotwire Inc.'
      ,'BUSINESS_UNIT_ID' = 22101
      ,'BUSINESS_UNIT_NAME' = 'Hotwire Inc.'
      ,'LODG_PROPERTY_NAME' = HOTEL_NAME
      ,'PROPERTY_CITY_NAME' = CITY_NAME
      ,'PROPERTY_STATE_PROVNC_NAME' = STATE_CODE
      ,'PROPERTY_POSTAL_CODE' = ADDRESS_ZIP
      ,'PRICE_CURRN_CODE' = 'USD'
      ,'OPER_UNIT_ID' = 0
      ,'GL_PRODUCT_ID' = 0
      ,'MGMT_UNIT_CODE' = 0
      ,'ORACLE_GL_PRODUCT_CODE' = 0
      ,'RM_NIGHT_CNT' = RESERVATION_QUANTITY_NIGHTS
      ,'COMPUTED_ROOM_NIGHT_COUNT' = RESERVATION_QUANTITY_NIGHTS
      ,'SALES_TAX_AREA' = ISNULL(rh.[Sales Tax Area], '')
      ,'COUNTY_TAX_AREA' = ISNULL(rh.[County Tax Area], '')
      ,'CITY_TAX_AREA' = ISNULL(rh.[City Tax Area], '')
      ,'GET_TAX_AREA' = ISNULL(rh.[GET Tax Area], '')
      ,'SALES_TAX_RATE' = ISNULL(rh.[Sales Tax Rate], 0)
      ,'COUNTY_TAX_RATE' = ISNULL(rh.[County Tax Rate], 0)
      ,'CITY_TAX_RATE' = ISNULL(rh.[City Tax Rate], 0)
      ,'GET_TAX_RATE' = ISNULL(rh.[GET Tax Rate], 0)
      ,'TOTAL_TAX_RATE' = ISNULL(rh.[Total Tax Rate], 0)
      ,'BASE_PRICE_USD' =  [CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]
      ,'FLAT_ADJ_USD' = 0
      ,'ALL_OTHR_ADJ_USD' = 0
      ,'SVC_FEE_PRICE_USD' = 0
      ,'ALL_OTHR_FEES_USD' = [EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]
      ,'TOTAL_TAX_USD' = [CUSTOMER_TAX_AMOUNT]+[STATE_TAX_ON_MARGIN]+[CITY_TAX_ON_MARGIN]+[OCC_TAX_ON_MARGIN_NYC_ONLY]
      ,'TOTAL_PRICE_USD' = [CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]
      ,'BASE_COST_USD' = [COST_BASE_AMOUNT] 
      ,'FLAT_COST_ADJ_USD' = 0
      ,'OTHR_COST_ADJ_USD' = 0
      ,'TOTAL_COST_FEE_USD' = 0
      ,'TOTAL_COST_USD' = [COST_BASE_AMOUNT] + [COST_TAX_AMOUNT]
      ,'TAX_COLLECTED' = [COST_TAX_AMOUNT]
      ,'TOTAL_PRICE_FEE_USD' = [EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_FEE_AMOUNT] 
      ,'TAX_BASE_MARGIN' = 0
      ,'TAX_BASE_COST' = 0
      ,'PRICE_TAX_ADJ_WZEROFLAT' = 0
      ,'PRICE_TAX_ADJ' = 0
      ,'COST_TAX_ADJ' = 0
      ,'COST_TAX_ADJ_WCANCEL' = 0
      ,'InsertedDate' = lh.InsertedDate
      -------Price Options
      ,'ADJ_PRICE_GA' = ROUND([EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT],2)
      ,'ADJ_PRICE_NY' = ROUND([CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)
      ,'ADJ_PRICE' = ROUND([CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)
      -------Cost Options
      ,'ADJ_COST_WPriceFee' = CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN'
									THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT]
									ELSE[COST_BASE_AMOUNT]
									END
      ,'ADJ_COST_GA' = CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN'
							THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT]
							ELSE [COST_BASE_AMOUNT]
							END
	  -------Margin Options							
      ,'ADJ_PRICE_GA-ADJ_COST_WPriceFee' =  ROUND(ROUND([EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT],2)
											- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END) ,2)
      ,'ADJ_PRICE_GA-ADJ_COST_GA' = ROUND(ROUND([EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT],2)
											- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END) ,2)
      ,'ADJ_PRICE_NY-ADJ_COST_WPriceFee' = ROUND(ROUND([CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)
											- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END),2)
      ,'ADJ_PRICE_NY-ADJ_COST_GA' = ROUND(ROUND([CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)
											- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END),2)
      ,'ADJ_PRICE-ADJ_COST_WPriceFee' = ROUND(ROUND([CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)
											- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END), 2)
      ,'ADJ_PRICE-ADJ_COST_GA' = ROUND(ROUND([CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)
											- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END), 2)
      --------Tax Due Options on Price (aka Gross/Single Remit)
      ,'ADJ_PRICE_GA-CityTaxDue' =  ROUND(ROUND([EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT],2)*(ISNULL(rh.[City Tax Rate],0)) ,2)
      ,'ADJ_PRICE_GA-CountyTaxDue' = ROUND(ROUND([EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT],2)*(ISNULL(rh.[County Tax Rate],0)) ,2)
      ,'ADJ_PRICE_GA-SalesTaxDue' = ROUND(ROUND([EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT],2)*(ISNULL(rh.[Sales Tax Rate],0)) ,2)
      ,'ADJ_PRICE_GA-GETTaxDue' = ROUND(ROUND([EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT],2)*(ISNULL(rh.[GET Tax Rate],0)) ,2)
      ,'ADJ_PRICE_GA-TotalTaxDue' = ROUND(ROUND([EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT],2)*(ISNULL(rh.[Total Tax Rate],0)) ,2)
      
     ,'ADJ_PRICE_NY-CityTaxDue' = ROUND(ROUND([EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)*(ISNULL(rh.[City Tax Rate],0)) ,2)
     ,'ADJ_PRICE_NY-CountyTaxDue' = ROUND(ROUND([EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)*(ISNULL(rh.[County Tax Rate],0)) ,2)
     ,'ADJ_PRICE_NY-SalesTaxDue' = ROUND(ROUND([EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)*(ISNULL(rh.[Sales Tax Rate],0)) ,2)
     ,'ADJ_PRICE_NY-GETTaxDue' =  ROUND(ROUND([EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)*(ISNULL(rh.[GET Tax Rate],0)) ,2)
     ,'ADJ_PRICE_NY-TotalTaxDue' = ROUND(ROUND([EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)*(ISNULL(rh.[Total Tax Rate],0)) ,2)

     ,'ADJ_PRICE-CityTaxDue' =  ROUND(ROUND([EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)*(ISNULL(rh.[City Tax Rate],0)) ,2)
     ,'ADJ_PRICE-CountyTaxDue' = ROUND(ROUND([EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)*(ISNULL(rh.[County Tax Rate],0)) ,2)
     ,'ADJ_PRICE-SalesTaxDue' = ROUND(ROUND([EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)*(ISNULL(rh.[Sales Tax Rate],0)) ,2)
     ,'ADJ_PRICE-GETTaxDue' =  ROUND(ROUND([EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)*(ISNULL(rh.[GET Tax Rate],0)) ,2)
     ,'ADJ_PRICE-TotalTaxDue' =  ROUND(ROUND([EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)*(ISNULL(rh.[Total Tax Rate],0)) ,2)    
      
      --------Tax Due Options on Margin
      ,'ADJ_PRICE_GA-ADJ_COST_WPriceFee-CityTaxDue' =  ROUND((ROUND([EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT],2)
														- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END))*(ISNULL(rh.[City Tax Rate],0)),2)
      ,'ADJ_PRICE_GA-ADJ_COST_WPriceFee-CountyTaxDue' = ROUND((ROUND([EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT],2)
														- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END))*(ISNULL(rh.[County Tax Rate],0)),2)
      ,'ADJ_PRICE_GA-ADJ_COST_WPriceFee-SalesTaxDue' = ROUND((ROUND([EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT],2)
														- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END))*(ISNULL(rh.[Sales Tax Rate],0)),2)
      ,'ADJ_PRICE_GA-ADJ_COST_WPriceFee-GETTaxDue' = ROUND((ROUND([EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT],2)
														- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END))*(ISNULL(rh.[GET Tax Rate],0)),2)
      ,'ADJ_PRICE_GA-ADJ_COST_WPriceFee-TotalTaxDue' = ROUND((ROUND([EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT],2)
														- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END))*(ISNULL(rh.[Total Tax Rate],0)),2)
      
      ,'ADJ_PRICE_GA-ADJ_COST_GA-CityTaxDue' = ROUND((ROUND([EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT],2)
														- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END))*(ISNULL(rh.[City Tax Rate],0)),2)
      ,'ADJ_PRICE_GA-ADJ_COST_GA-CountyTaxDue' = ROUND((ROUND([EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT],2)
														- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END))*(ISNULL(rh.[County Tax Rate],0)),2)
      ,'ADJ_PRICE_GA-ADJ_COST_GA-SalesTaxDue' = ROUND((ROUND([EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT],2)
														- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END))*(ISNULL(rh.[Sales Tax Rate],0)),2)
      ,'ADJ_PRICE_GA-ADJ_COST_GA-GETTaxDue' = ROUND((ROUND([EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT],2)
														- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END))*(ISNULL(rh.[GET Tax Rate],0)),2)
      ,'ADJ_PRICE_GA-ADJ_COST_GA-TotalTaxDue' = ROUND((ROUND([EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT],2)
														- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END))*(ISNULL(rh.[Total Tax Rate],0)),2)
														
      ,'ADJ_PRICE_NY-ADJ_COST_WPriceFee-CityTaxDue' =  ROUND((ROUND([CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)
														- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END))*(ISNULL(rh.[City Tax Rate],0)), 2)
      ,'ADJ_PRICE_NY-ADJ_COST_WPriceFee-CountyTaxDue' = ROUND((ROUND([CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)
														- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END))*(ISNULL(rh.[County Tax Rate],0)), 2)
      ,'ADJ_PRICE_NY-ADJ_COST_WPriceFee-SalesTaxDue' = ROUND((ROUND([CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)
														- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END))*(ISNULL(rh.[Sales Tax Rate],0)), 2)
      ,'ADJ_PRICE_NY-ADJ_COST_WPriceFee-GETTaxDue' = ROUND((ROUND([CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)
														- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END))*(ISNULL(rh.[GET Tax Rate],0)), 2)
      ,'ADJ_PRICE_NY-ADJ_COST_WPriceFee-TotalTaxDue' = ROUND((ROUND([CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)
														- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END))*(ISNULL(rh.[Total Tax Rate],0)), 2)
														
      ,'ADJ_PRICE_NY-ADJ_COST_GA-CityTaxDue' = ROUND((ROUND([CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)
														- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END))*(ISNULL(rh.[City Tax Rate],0)), 2)
      ,'ADJ_PRICE_NY-ADJ_COST_GA-CountyTaxDue' = ROUND((ROUND([CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)
														- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END))*(ISNULL(rh.[County Tax Rate],0)), 2)
      ,'ADJ_PRICE_NY-ADJ_COST_GA-SalesTaxDue' = ROUND((ROUND([CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)
														- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END))*(ISNULL(rh.[Sales Tax Rate],0)), 2)
      ,'ADJ_PRICE_NY-ADJ_COST_GA-GETTaxDue' = ROUND((ROUND([CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)
														- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END))*(ISNULL(rh.[GET Tax Rate],0)), 2)
      ,'ADJ_PRICE_NY-ADJ_COST_GA-TotalTaxDue' = ROUND((ROUND([CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)
														- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END))*(ISNULL(rh.[Total Tax Rate],0)), 2)
      
      ,'ADJ_PRICE-ADJ_COST_WPriceFee-CityTaxDue' = 	ROUND((ROUND([CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)
													- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END))*(ISNULL(rh.[City Tax Rate],0)), 2) 												
      ,'ADJ_PRICE-ADJ_COST_WPriceFee-CountyTaxDue' = ROUND((ROUND([CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)
													- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END))*(ISNULL(rh.[County Tax Rate],0)), 2) 
      ,'ADJ_PRICE-ADJ_COST_WPriceFee-SalesTaxDue' = ROUND((ROUND([CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)
													- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END))*(ISNULL(rh.[Sales Tax Rate],0)), 2) 
      ,'ADJ_PRICE-ADJ_COST_WPriceFee-GETTaxDue' = ROUND((ROUND([CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)
													- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END))*(ISNULL(rh.[GET Tax Rate],0)), 2) 
      ,'ADJ_PRICE-ADJ_COST_WPriceFee-TotalTaxDue' = ROUND((ROUND([CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)
													- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END))*(ISNULL(rh.[Total Tax Rate],0)), 2) 
      
      ,'ADJ_PRICE-ADJ_COST_GA-CityTaxDue' = ROUND((ROUND([CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)
													- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END))*(ISNULL(rh.[City Tax Rate],0)), 2) 
      ,'ADJ_PRICE-ADJ_COST_GA-CountyTaxDue' = ROUND((ROUND([CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)
													- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END))*(ISNULL(rh.[County Tax Rate],0)), 2) 
      ,'ADJ_PRICE-ADJ_COST_GA-SalesTaxDue' = ROUND((ROUND([CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)
													- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END))*(ISNULL(rh.[Sales Tax Rate],0)), 2) 
      ,'ADJ_PRICE-ADJ_COST_GA-GETTaxDue' = ROUND((ROUND([CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)
													- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END))*(ISNULL(rh.[GET Tax Rate],0)), 2) 
      ,'ADJ_PRICE-ADJ_COST_GA-TotalTaxDue' = ROUND((ROUND([CUSTOMER_BASE_AMOUNT]+[MARKUP_AMOUNT]+[EAN_COMPENSATION_AMOUNT]-[CUSTOMER_DISCOUNT_AMOUNT]+[EXTRA_GUEST_CHARGES]+[UNKNOWN_PRICE_MODIFIER_AMOUNT]+[CUSTOMER_FEE_AMOUNT],2)
													- (CASE WHEN [CRS_TYPE_CODE_DESCRIPTION]='EAN' THEN [COST_BASE_AMOUNT]+[COST_TAX_AMOUNT]-[CUSTOMER_TRC_AMOUNT] ELSE[COST_BASE_AMOUNT] END))*(ISNULL(rh.[Total Tax Rate],0)), 2) 
      ---------Negative Margin Flagged Fields
      ,'ADJ_PRICE_GA-ADJ_COST_WPriceFee_NetNeg' = nnhm.[ADJ_PRICE_GA-ADJ_COST_WPriceFee_NetNeg]
      ,'ADJ_PRICE_GA-ADJ_COST_GA_NetNeg' = nnhm.[ADJ_PRICE_GA-ADJ_COST_GA_NetNeg]
      ,'ADJ_PRICE_NY-ADJ_COST_WPriceFee_NetNeg' = nnhm.[ADJ_PRICE_NY-ADJ_COST_WPriceFee_NetNeg]
      ,'ADJ_PRICE_NY-ADJ_COST_GA_NetNeg' = nnhm.[ADJ_PRICE_NY-ADJ_COST_GA_NetNeg]
      ,'ADJ_PRICE-ADJ_COST_WPriceFee_NetNeg' = nnhm.[ADJ_PRICE-ADJ_COST_WPriceFee_NetNeg]
      ,'ADJ_PRICE-ADJ_COST_GA_NetNeg' = nnhm.[ADJ_PRICE-ADJ_COST_GA_NetNeg]
      ,'ADJ_PRICE_NetNeg' = nnhm.[ADJ_PRICE_NetNeg] 
      ,rh.[Vertex Tax Area]
      ,'HotwireHotelID' = lh.HOTEL_ID
      
FROM  Lodging.V_Hotwire lh
LEFT JOIN  Rates.V_Hotwire rh ON lh.[HOTEL_ID] = rh.HotwireHotelID
LEFT JOIN  #Net_Negative_HotwireMargin nnhm ON CAST(ISNULL(REPLACE(PURCHASE_ORDER_ID,'''',''), 0) AS BIGINT) = nnhm.BKG_ITM_ID









END 




















GO
