USE [Compliance]
GO
/****** Object:  StoredProcedure [Lodging].[InsertTaxComplianceBreakage]    Script Date: 9/5/2017 10:47:49 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO




/*
-----Contents------
--#BREAKAGE Breakage loaded to temp table 															( 2 minutes)
--#EXCHRATE Exchange Rate loaded to temp table 														( 2 seconds)
--#GBV Booking loaded to temp table 																( 1  minute)
--#GBV2 Booking loaded to temp table with the exchange rates applied.								( 1 seconds)
--#GENPAYMENT Generic Payment loaded to temp table 													( 3 seconds)					
--#GENPAYMENT2 Generic Payment loaded to temp table with the exchange rates applied.				( 1 seconds)
--#MCLASS20 Monetary Class ID 20 loaded to temp table 												(10 seconds)
--#APRECON BookingItemID & Update Dates loaded to temp table for MAX update date					( 6 minutes)-
--#APRECON2 Stay Level Taxes found for those Max Update Date items for each booking item id			( 4 minutes)-
--#TAXRATE pull in all related tax rates (LZ table)													( 4 seconds)
--More lookup tables to speed things up (#Lgl_Entity_Dim, #Lodg_Property_Dim, #Lodg_Rate_Pln_Dim)	(18 seconds)
--Final Data Compilation & Insert into real table													(90 seconds)
------------------------------------------------------------------------------------------Total->>>  14 minutes
20160729 - Chris updated breakage script to be pulled on day 1 of close. Eg. run script on 8/1/16, and pull July 2015 breakage data
-----------------------------------------------------------------------------------------------------------------------------------------------------------
	TD - Breakage data limited to begin use month from previous month but a year ago.

    The data is loaded into a temp table, #BREAKAGE.  
	CAST(OREPLACE(substr(cast (ADD_MONTHS(BEGIN_USE_DATE_KEY , - 12) as char(10)),1,7) , ''-'', '''') AS INTEGER) will look like: 201501
	EXTRACT(YEAR FROM CURRENT_DATE) - 1 will be the previous year. e.g. if i am in 2016 now, it will show as 2015
	EXTRACT(MONTH FROM CURRENT_DATE) - 1 will be the previous month number. e.g. if i am in feb now, it will show 1
	Approx  700K  records.  2 Minutes 24 seconds. 
-----------------------------------------------------------------------------------------------------------------------------------------------------------
20170113 TAXSYSTEMS-867		TLessley	Update script to eliminate spool space errors. Namely reduced the queries to the most basic versions - used keys and more
										lkup tables from dimension tables. also took out the hard coded state values at the bottom for single remittance states. 
------------------------------------------------------------------------------------------------------------------------------------------------------------*/
CREATE PROCEDURE [Lodging].[InsertTaxComplianceBreakage]
AS


BEGIN
SET NOCOUNT ON;
------------------------------------------------------*/
--Declare Variables
------------------------------------------------------
DECLARE @STATE					varchar (128) 
	   ,@TDBreakage				nvarchar(max)
	   ,@TD_GBV					nvarchar(max)
	   ,@TD_GENPAYMENT			nvarchar(max)
	   ,@TD_Lodg_Rate_Pln_Dim	nvarchar(max)
	   ,@Name					varchar (max)
	   ,@Name_ReplaceCommas 	nvarchar(max)
	   ,@STARTDATE				varchar(50)
       ,@ENDDATE				varchar(50)
------------------------------------------------------
---get distinct list of states where we are liable
IF OBJECT_ID('tempdb..#States') IS NOT NULL DROP TABLE #States;

SELECT	* 
INTO #States
FROM (SELECT distinct 'Jurisdiction_State' = UPPER(Jurisdiction_State)
	  FROM compliance.lkup.LodgingCompliance )A;

------------------------------------------------------
---compile the list of distinct liable states into 1 long string
SELECT @Name = (SELECT  substring(
								(SELECT ',' + Jurisdiction_State 
								FROM #States
								ORDER BY Jurisdiction_State
								FOR XML PATH ('')), 2, 2000000) )
SET @Name_ReplaceCommas = REPLACE(@Name,',',''''',''''') + ''''',''''Oregon'
--select @Name_ReplaceCommas
SELECT @STARTDATE = CONVERT(VARCHAR(10), DATEADD(m, -13, DATEADD(d, 1, CONVERT(VARCHAR(10), DATEADD(d, -DATEPART(d, getdate()), GETDATE()), 120) )), 120)
SELECT @ENDDATE   = CONVERT(VARCHAR(10), DATEADD(M, -12, DATEADD(d, -DATEPART(d, getdate()), GETDATE())), 120)

------------------------------------------------------
--Pull Data for State and Period (Key values are pulled later in the script)
------------------------------------------------------
SELECT @TDBreakage = 
					'SELECT *
						  FROM 
						  OPENQUERY(TDPROD,  							
								   ''SELECT	 bki.BUSINESS_UNIT_KEY
											,bki.LODG_PROPERTY_KEY
											,lpd.EXPE_LODG_PROPERTY_ID
											,CAST(OREPLACE(substr(cast((BEGIN_USE_DATE_KEY) as char(10)),1,7) , ''''-'''', '''''''') AS INTEGER) BEGIN_USE_YEAR_MONTH
											,bki.BKG_ITM_ID
											,bki.OPER_UNIT_KEY
											,bid.AP_LGL_OBLIG_IND
											,bki.GL_PRODUCT_KEY
											,bki.LGL_ENTITY_KEY
											,bki.MGMT_UNIT_KEY
											,bki.ORACLE_GL_PRODUCT_KEY
											,sum(bki.NET_AP_COST_AMT_USD) NET_AP_COST_AMT_USD
											,sum(bki.ACCRUED_COST_AMT_USD) ACCRUED_COST_AMT_USD
											,sum(bki.AP_COST_ADJ_AMT_USD) AP_COST_ADJ_AMT_USD
											,sum(bki.NET_AP_PAYMNT_AMT_USD) NET_AP_PAYMNT_AMT_USD
											,sum(bki.NET_BRKAGE_AMT_USD) NET_BRKAGE_AMT_USD
											

									FROM	P_DM_FIN.BRKAGE_BKG_ITM_FACT bki
											JOIN P_DM_FIN.BRKAGE_IND_DIM bid			ON bid.BRKAGE_IND_KEY=bki.BRKAGE_IND_KEY
											JOIN P_DM_COMMON.LODG_PROPERTY_DIM lpd		ON lpd.LODG_PROPERTY_KEY = bki.LODG_PROPERTY_KEY
											
									
									WHERE   bki.BEGIN_USE_DATE_KEY between ''''' + @STARTDATE + ''''' AND   ''''' + @ENDDATE   + '''''
											AND 	(
															((UPPER(TRIM(lpd.property_state_provnc_name)) IN (''''' + @Name_ReplaceCommas +''''') 
															AND UPPER(lpd.property_cntry_name) IN (''''USA'''', ''''UNITED STATES OF AMERICA'''')))
														OR
															((UPPER(TRIM(lpd.property_cntry_name)) IN (''''PR'''', ''''PUERTO RICO''''))) 
																												
													)
											
											
							
									GROUP BY bki.BUSINESS_UNIT_KEY
											,bki.LODG_PROPERTY_KEY
											,lpd.EXPE_LODG_PROPERTY_ID
											,CAST(OREPLACE(substr(cast ((BEGIN_USE_DATE_KEY) as char(10)),1,7) , ''''-'''', '''''''') AS INTEGER)
											,bki.BKG_ITM_ID
											,bki.OPER_UNIT_KEY
											,bid.AP_LGL_OBLIG_IND
											,bki.LGL_ENTITY_KEY
											,bki.GL_PRODUCT_KEY
											,bki.MGMT_UNIT_KEY
											,bki.ORACLE_GL_PRODUCT_KEY'')'  



---------------------------------------------
IF OBJECT_ID('tempdb..#TD_Breakage') IS NOT NULL 
DROP TABLE #TD_Breakage;

CREATE TABLE #TD_Breakage
(
	BUSINESS_UNIT_KEY varchar(50) null
	,LODG_PROPERTY_KEY int null
	,EXPE_LODG_PROPERTY_ID int null
	,BEGIN_USE_YEAR_MONTH int null
	,BKG_ITM_ID int null
	,OPER_UNIT_KEY smallint null
	,AP_LGL_OBLIG_IND varchar(100) null
	,GL_PRODUCT_KEY varchar(100) null
	,LGL_ENTITY_KEY varchar(50)
	,MGMT_UNIT_KEY varchar(50)
	,ORACLE_GL_PRODUCT_KEY varchar(100) null 
	,NET_AP_COST_AMT_USD numeric (31,4)
	,ACCRUED_COST_AMT_USD numeric (31,4)
	,AP_COST_ADJ_AMT_USD numeric (31,4)
	,NET_AP_PAYMNT_AMT_USD numeric (31,4)
	,NET_BRKAGE_AMT_USD numeric (31,4)
	
)



INSERT INTO #TD_Breakage
EXEC (@TDBreakage)  ----good

---------------------------------------------


CREATE INDEX IX_2 on #TD_Breakage (BKG_ITM_ID, LODG_PROPERTY_KEY);


/*-----------------------------------------------------------------------------------------------------------------------------------------------------------
TD - USD Exchange Rate limited to exchange rate dates to USD.
-----------------------------------------------------------------------------------------------------------------------------------------------------------*/
IF OBJECT_ID('tempdb..#EXCHRATE') IS NOT NULL DROP TABLE #EXCHRATE;

SELECT 	*
INTO #EXCHRATE
FROM 	(SELECT *
		 FROM OPENQUERY(TDPROD,   
			   'SELECT DISTINCT
					   der.EXCH_RATE_DATE
					  ,pcd.PRICE_CURRN_KEY
					  ,coalesce(der.EXCH_RATE, 0) USD_EXCH_RATE
				
				FROM P_DM_COMMON.DAILY_EXCH_RATE der
					 JOIN P_DM_COMMON.PRICE_CURRN_DIM pcd ON pcd.PRICE_CURRN_CODE=der.FROM_CURRN_CODE
						
				WHERE der.TO_CURRN_CODE = ''USD'';'))A;

CREATE INDEX IX_3 on #EXCHRATE (EXCH_RATE_DATE, PRICE_CURRN_KEY);
           
/*-----------------------------------------------------------------------------------------------------------------------------------------------------------
#GBV - TD - Lodging booking data limited to begin use month from previous month but a year ago

	The data is also limited to Merchant/Non-Opaque 
	EXTRACT(YEAR FROM CURRENT_DATE) - 1 will be the previous year. e.g. if i am in 2016 now, it will show as 2015
	EXTRACT(MONTH FROM CURRENT_DATE) - 1 will be the previous month number. e.g. if i am in feb now, it will show 1
	Approx 700K records. 31 seconds 				
------------------------------------------------------------------------------------------------------------------------------------------------------------*/
SELECT @TD_GBV = 
					'SELECT *
								 FROM OPENQUERY(TDPROD, 						    
								   ''SELECT
											rtf.BKG_ITM_ID
											,rtf.LODG_RATE_PLN_KEY
											,rtf.PRICE_CURRN_KEY
											,rtf.BK_DATE_KEY						
											,SUM(rtf.RM_NIGHT_CNT) RM_NIGHT_CNT
											,SUM(rtf.GROSS_BKG_AMT_LOCAL) GROSS_BKG_AMT_LOCAL
											,SUM(rtf.TOTL_COST_AMT_USD) TOTL_COST_AMT_USD
											,SUM(rtf.TOTL_TAX_COST_AMT_USD) TOTL_TAX_COST_AMT_USD
									FROM
											P_DM_BKG_LODG.LODG_RM_TRANS_FACT rtf
											JOIN P_DM_COMMON.PRODUCT_LN_DIM pld				ON pld.PRODUCT_LN_KEY=rtf.PRODUCT_LN_KEY
											JOIN P_DM_COMMON.LODG_PROPERTY_DIM lpd			ON lpd.LODG_PROPERTY_KEY = rtf.LODG_PROPERTY_KEY
																	
									WHERE pld.BUSINESS_MODEL_NAME = ''''Merchant''''
										  AND pld.BUSINESS_MODEL_SUBTYP_NAME <> ''''Opaque Merchant''''
										  AND rtf.BEGIN_USE_DATE_KEY between ''''' + @STARTDATE + ''''' AND   ''''' + @ENDDATE   + '''''
										  AND 	(
														((UPPER(TRIM(lpd.property_state_provnc_name)) IN (''''' + @Name_ReplaceCommas +''''') 
															AND UPPER(lpd.property_cntry_name) IN (''''USA'''', ''''UNITED STATES OF AMERICA'''')))
														
														OR 
														
														((UPPER(TRIM(lpd.property_cntry_name)) IN (''''PR'''', ''''PUERTO RICO''''))) 
													)

									GROUP BY rtf.BKG_ITM_ID
											,rtf.PRICE_CURRN_KEY
											,rtf.BK_DATE_KEY
											,rtf.LODG_RATE_PLN_KEY;'')'
											

---------------------------------------------
IF OBJECT_ID('tempdb..#TD_GBV') IS NOT NULL 
DROP TABLE #TD_GBV;

CREATE TABLE #TD_GBV
(	 BKG_ITM_ID int null
	,LODG_RATE_PLN_KEY int null
	,PRICE_CURRN_KEY varchar(100) null
	,BK_DATE_KEY datetime null						
	,RM_NIGHT_CNT int null
	,GROSS_BKG_AMT_LOCAL numeric (31,4)
	,TOTL_COST_AMT_USD numeric (31,4)
	,TOTL_TAX_COST_AMT_USD numeric (31,4)
)



INSERT INTO #TD_GBV
EXEC (@TD_GBV)  

---------------------------------------------											
											

CREATE INDEX IX_4 on #TD_GBV (BK_DATE_KEY,PRICE_CURRN_KEY); --good

/*-----------------------------------------------------------------------------------------------------------------------------------------------------------
#GBV2 - TD - Lodging booking data limited to begin use month from previous month but a year ago, with the exchange rates applied.
Approx 700K records. less than 1 second
------------------------------------------------------------------------------------------------------------------------------------------------------------*/
IF OBJECT_ID('tempdb..#GBV2') IS NOT NULL DROP TABLE #GBV2;

SELECT 	*
INTO #GBV2
FROM 	(SELECT  g.BKG_ITM_ID
				,g.LODG_RATE_PLN_KEY
				,SUM(g.RM_NIGHT_CNT) RM_NIGHT_CNT
				,SUM(ISNULL(g.GROSS_BKG_AMT_LOCAL,0) * ISNULL(e.USD_EXCH_RATE, 0)) GROSS_BKG_AMT_USD
				,SUM(g.TOTL_COST_AMT_USD) TOTL_COST_AMT_USD
				,SUM(g.TOTL_TAX_COST_AMT_USD)TOTL_TAX_COST_AMT_USD
			
			FROM #TD_GBV g
				 LEFT JOIN #EXCHRATE e ON g.BK_DATE_KEY = e.EXCH_RATE_DATE AND g.PRICE_CURRN_KEY = e.PRICE_CURRN_KEY
				
			GROUP BY g.BKG_ITM_ID, g.LODG_RATE_PLN_KEY)x;

CREATE INDEX GBV2_1 on #GBV2 (BKG_ITM_ID);	

/*-------------------------------------------------------------------------------------------------------------------------------------------------------------
TD - Generic payment data is limited to begin use month from previous month but a year ago
Approx 45K records. 3 seconds. 				
---------------------------------------------------------------------------------------------------------------------------------------------------------------*/
SELECT @TD_GENPAYMENT = 
					'SELECT *
						  FROM 
						   OPENQUERY(TDPROD,
								   ''SELECT
											gpf.MATCHED_BKG_ITM_ID
											,gpf.BK_DATE_KEY
											,gpf.GENRIC_PAYMNT_CURRN_KEY
											,sum(gpf.GENRIC_PAYMNT_AMT_LOCAL)GENRIC_PAYMNT_AMT_LOCAL

									FROM P_DM_PAYMNT_GENERIC.GENRIC_PAYMNT_FACT gpf
										 JOIN P_DM_COMMON.PRODUCT_LN_DIM pld			ON gpf.PRODUCT_LN_KEY=pld.PRODUCT_LN_KEY 
										 JOIN P_DM_COMMON.LODG_PROPERTY_DIM lpd			ON lpd.LODG_PROPERTY_KEY = gpf.LODG_PROPERTY_KEY
																
									WHERE gpf.BEGIN_USE_DATE_KEY between ''''' + @STARTDATE + ''''' AND   ''''' + @ENDDATE   + '''''
										  AND pld.BUSINESS_MODEL_NAME = ''''Merchant''''
										  AND pld.BUSINESS_MODEL_SUBTYP_NAME <> ''''Opaque Merchant''''
										  AND 	(
														((UPPER(TRIM(lpd.property_state_provnc_name)) IN (''''' + @Name_ReplaceCommas +''''') 
															AND UPPER(lpd.property_cntry_name) IN (''''USA'''', ''''UNITED STATES OF AMERICA'''')))
														
														OR 
														
														((UPPER(TRIM(lpd.property_cntry_name)) IN (''''PR'''', ''''PUERTO RICO''''))) 
													)
													
									GROUP BY gpf.MATCHED_BKG_ITM_ID
											,gpf.GENRIC_PAYMNT_CURRN_KEY
											,gpf.BK_DATE_KEY ;'')' 


---------------------------------------------
IF OBJECT_ID('tempdb..#TD_GENPAYMENT') IS NOT NULL 
DROP TABLE #TD_GENPAYMENT;

CREATE TABLE #TD_GENPAYMENT
(	 MATCHED_BKG_ITM_ID int null
	,BK_DATE_KEY datetime null						
	,GENRIC_PAYMNT_CURRN_KEY varchar(10) null
	,GENRIC_PAYMNT_AMT_LOCAL numeric (31,4)
)



INSERT INTO #TD_GENPAYMENT
EXEC (@TD_GENPAYMENT)  

---------------------------------------------

CREATE INDEX IX_3 on #TD_GENPAYMENT (BK_DATE_KEY,GENRIC_PAYMNT_CURRN_KEY);

/*-----------------------------------------------------------------------------------------------------------------------------------------------------------
#GENPAYMENT2 - TD - Generic payment data is limited to begin use month from previous month but a year ago - with exchange rates applied  
Approx 45K rows. Less than 1 second. 
------------------------------------------------------------------------------------------------------------------------------------------------------------*/
IF OBJECT_ID('tempdb..#GENPAYMENT2') IS NOT NULL DROP TABLE #GENPAYMENT2;

SELECT 	*
INTO #GENPAYMENT2
FROM	
			(SELECT gp.MATCHED_BKG_ITM_ID
				  ,SUM(ISNULL(gp.GENRIC_PAYMNT_AMT_LOCAL, 0) * ISNULL(e.USD_EXCH_RATE,0)) GENRIC_PAYMNT_AMT_USD

			FROM #TD_GENPAYMENT gp	  
			LEFT JOIN #EXCHRATE e ON gp.BK_DATE_KEY = e.EXCH_RATE_DATE AND gp.GENRIC_PAYMNT_CURRN_KEY = e.PRICE_CURRN_KEY

			GROUP BY gp.MATCHED_BKG_ITM_ID)x;

CREATE INDEX GENPAYMENT2_1 on #GENPAYMENT2 (MATCHED_BKG_ITM_ID);			
/*-----------------------------------------------------------------------------------------------------------------------------------------------------------
SQL CHWXSQLNRT039.BookingImp - Monetary Class ID 20 or taxes from the booking amount table.  
 
 The data is limited to lodging booking amounts when to transactions that have monetary class id = 20. 
 The data is also limited to the booking item id's (BKG_ITM_ID) from the #BREAKAGE temp table 

 Monetary class 20 = Tax on margin, typically paid by Expedia. Charges imposed by a government entity.
 Booking System ID 1 = Lodging Booking


Approx 321k  records. 10 seconds  
------------------------------------------------------------------------------------------------------------------------------------------------------------*/
IF OBJECT_ID('tempdb..#MCLASS20') IS NOT NULL DROP TABLE #MCLASS20;

SELECT 	*
INTO #MCLASS20 
FROM  (SELECT	ba.BookingItemID
				,SUM(ba.TransactionAmtCost)MC20TransAmtCost
	 
	   FROM #TD_Breakage b
	   JOIN [CHWXSQLNRT050.DataWareHouse.ExpEcn.com].BookingImp.dbo.BookingAmount_Archive ba WITH (NOLOCK) ON ba.BookingItemID = b.BKG_ITM_ID
	  
	 
	   WHERE ba.MonetaryClassID = 20 
		   AND ba.BookingSystemID = 1
	
	   GROUP BY BookingItemID) x;




CREATE INDEX IX_1 on #MCLASS20 (BookingItemID);

/*---------------------------------------------------------------------------------------------------------------------------------------------------------------
CHWXSQLNRT037 - APRecon data is limited to begin use month from previous month but a year ago.  The begin use date is converted to "yyyymm" format.  
				The query is grabbing each unique vendor invoice number with the latest update time stamp, this is to reduce the same invoice being accounted for
				multiple times.  There will be times when the same invoice number will appear multiple times with different stay level taxes but with the same time
				stamp.  In this scenario, the stay level taxes will be added together. 
				
				Methodology
				1.	Pull unique vendor invoice numbers within each booking item id
				2.	If a vendor invoice number with the same stay level taxes appear multiple times with different update timestamps then pull the invoice number 
					with the latest update timestamp
				3.	If a vendor invoice number appears multiple times but they have different stay level taxes and different update timestamps then pull the 
					invoice number with the latest timestamp
				4.	If a vendor invoice number appears multiple times but they have the same update timestamps then sum the stay level taxes
				5.	If a booking item id has multiple vendor invoice numbers then follow steps 2 through 4 and sum the stay level taxes 
----------------------------------------------------------------------------------------------------------------------------------------------------------------*/
---700K rows. 14 minutes. 
IF OBJECT_ID('tempdb..#APRECON') IS NOT NULL DROP TABLE #APRECON;

SELECT 	* 
INTO #APRECON 
FROM 	(SELECT	
			bi.BookingItemId 
			,MAX(LVI.APRUPDATEDATE)APRUpdateDate 
		
		FROM  
			[CHWXSQLNRT037.DataWareHouse.ExpEcn.com].APRECON.dbo.LodgingItem bi WITH (NOLOCK) 
			LEFT JOIN [CHWXSQLNRT037.DataWareHouse.ExpEcn.com].APRECON.DBO.LodgingVendorInvoice lvi WITH (NOLOCK) ON bi.BookingItemId = lvi.BookingItemId 
			INNER JOIN #TD_Breakage tb ON bi.BookingItemId = tb.BKG_ITM_ID
		
		
		GROUP BY BI.BookingItemId)AP; 

CREATE INDEX APRECON_1 on #APRECON (BookingItemId);
			
---145K rows. 4 minutes. 
IF OBJECT_ID('tempdb..#APRECON2') IS NOT NULL DROP TABLE #APRECON2;


SELECT 	* 
INTO #APRECON2 
FROM 	(SELECT	
			a.BookingItemId 
			,SUM(LVI.STAYLEVELTAXES) StayLevelTaxes 
		
		FROM #APRECON a
			 JOIN [CHWXSQLNRT037.DataWareHouse.ExpEcn.com].APRECON.DBO.LodgingVendorInvoice lvi WITH (NOLOCK) ON a.BookingItemId = lvi.BookingItemId and a.APRUpdateDate = lvi.APRUpdateDate 
			
		GROUP BY a.BookingItemId)AP; 

CREATE INDEX APRECON_2 on #APRECON2 (BookingItemId);

/*---------------------------------------------------------------------------------------------------------------------------------------------------------------

-- 6/14/16: point to the Beardsley rate tables in Compliance database for rates. Master Rate Tool is no longer active. Therefore the LZ table is stale as well. 
--approx 25K records. 1 seconds. 
----------------------------------------------------------------------------------------------------------------------------------------------------------------*/
IF OBJECT_ID('tempdb..#TAXRATE') IS NOT NULL DROP TABLE #TAXRATE;

SELECT	* 
INTO #TAXRATE
FROM	(SELECT *
		 FROM [Compliance].[Rates].[V_CSV])A;

CREATE INDEX IX_1 on #TAXRATE ([Expedia ID]);

/*---------------------------------------------------------------------------------------------------------------------------------------------------------------
--Section 7.5:  Adding in some more lookup values
----------------------------------------------------------------------------------------------------------------------------------------------------------------*/
--approx 600 records. 15 second. 
IF OBJECT_ID('tempdb..#Lgl_Entity_Dim') IS NOT NULL DROP TABLE #Lgl_Entity_Dim;

SELECT	*
INTO #Lgl_Entity_Dim
FROM (SELECT *
		FROM OPENQUERY(TDPROD,
						'SELECT *
						 FROM P_DM_COMMON.LGL_ENTITY_DIM;'))x

CREATE INDEX Lgl_Entity_Dim_1 on #Lgl_Entity_Dim (LGL_ENTITY_KEY);
-------------------------------------------------------------------------------------------------------------
--approx 1MM records. 2 minutes. 
IF OBJECT_ID('tempdb..#Lodg_Property_Dim') IS NOT NULL DROP TABLE #Lodg_Property_Dim;

SELECT *
INTO #Lodg_Property_Dim
FROM (SELECT *
		FROM OPENQUERY(TDPROD,
						'SELECT *
						 FROM P_DM_COMMON.LODG_PROPERTY_DIM lpd; '))x 

CREATE INDEX Lodg_Property_Dim_1 on #Lodg_Property_Dim (LODG_PROPERTY_KEY); 
-------------------------------------------------------------------------------------------------------------
----400 rows. 1 second.
IF OBJECT_ID('tempdb..#OperatingUnitDim') IS NOT NULL 
DROP TABLE #OperatingUnitDim;
SELECT	*
INTO #OperatingUnitDim
FROM

(SELECT *
	FROM 
		OPENQUERY(TDprod, 
'SELECT
OPER_UNIT_DIM.OPER_UNIT_KEY,
OPER_UNIT_DIM.OPER_UNIT_ID
FROM P_DM_COMMON.OPER_UNIT_DIM;'))x

CREATE INDEX IX_1 on #OperatingUnitDim (OPER_UNIT_KEY);
-------------------------------------------------------------------------------------------------------------
--KEY PULLS Continue
-------------------------------------------------------------------------------------------------------------
----300 rows. 4 seconds. 
IF OBJECT_ID('tempdb..#GLPRODUCTID') IS NOT NULL 
DROP TABLE #GLPRODUCTID;
SELECT	*
INTO #GLPRODUCTID
FROM

(SELECT *
	FROM 
		OPENQUERY(TDprod, 
'SELECT
GL_PRODUCT_DIM.GL_PRODUCT_KEY,
GL_PRODUCT_DIM.GL_PRODUCT_ID
FROM P_DM_COMMON.GL_PRODUCT_DIM;'))x

CREATE INDEX IX_1 on #GLPRODUCTID (GL_PRODUCT_KEY);

-------------------------------------------------------------------------------------------------------------
---460 rows. 1 second.
IF OBJECT_ID('tempdb..#MGMT') IS NOT NULL 
DROP TABLE #MGMT;
SELECT	*
INTO #MGMT
FROM

(SELECT *
	FROM 
		OPENQUERY(TDprod, 
'SELECT
MGMT_UNIT_DIM.MGMT_UNIT_KEY,
MGMT_UNIT_DIM.MGMT_UNIT_CODE
FROM P_DM_COMMON.MGMT_UNIT_DIM;'))x

CREATE INDEX IX_1 on #MGMT (MGMT_UNIT_KEY);

-------------------------------------------------------------------------------------------------------------
----250 rows. 4 seconds. 
IF OBJECT_ID('tempdb..#ORACLEGL') IS NOT NULL 
DROP TABLE #ORACLEGL;
SELECT	*
INTO #ORACLEGL
FROM

(SELECT *
	FROM 
		OPENQUERY(TDprod, 
'SELECT
ORACLE_GL_PRODUCT_DIM.ORACLE_GL_PRODUCT_KEY,
ORACLE_GL_PRODUCT_DIM.ORACLE_GL_PRODUCT_CODE
FROM P_DM_COMMON.ORACLE_GL_PRODUCT_DIM;'))x

CREATE INDEX IX_1 on #ORACLEGL (ORACLE_GL_PRODUCT_KEY);

-------------------------------------------------------------------------------------------------------------
-----240 rows. 5 seconds. 
IF OBJECT_ID('tempdb..#BusinessUnit') IS NOT NULL 
DROP TABLE #BusinessUnit;
SELECT	*
INTO #BusinessUnit
FROM

(SELECT *
	FROM 
		OPENQUERY(TDprod, 
'Select 
BUSINESS_UNIT_DIM.BUSINESS_UNIT_KEY,
BUSINESS_UNIT_DIM.BUSINESS_UNIT_ID,
BUSINESS_UNIT_DIM.BUSINESS_UNIT_NAME
FROM P_DM_COMMON.BUSINESS_UNIT_DIM;'))X

CREATE INDEX IX_1 on #BusinessUnit (BUSINESS_UNIT_KEY);
------------------------------------------------------------------------
-- approx 1MM  records. 1 minute. 
SELECT @TD_Lodg_Rate_Pln_Dim = 
					'SELECT *
						  FROM OPENQUERY(TDPROD, 
										   ''SELECT	RATE_PLN_LODG_PROPERTY_KEY, LODG_RM_TYP_ID, LODG_RATE_PLN_KEY
											   FROM P_DM_LODG_PROPERTY.LODG_RATE_PLN_DIM lr
											   JOIN P_DM_COMMON.LODG_PROPERTY_DIM lpd			ON lpd.LODG_PROPERTY_KEY = lr.RATE_PLN_LODG_PROPERTY_KEY
											   WHERE (
														((UPPER(TRIM(lpd.property_state_provnc_name)) IN (''''' + @Name_ReplaceCommas +''''') 
															AND UPPER(lpd.property_cntry_name) IN (''''USA'''', ''''UNITED STATES OF AMERICA'''')))
														
														OR 
														
														((UPPER(TRIM(lpd.property_cntry_name)) IN (''''PR'''', ''''PUERTO RICO''''))) 
													);'')'

---------------------------------------------
IF OBJECT_ID('tempdb..#Lodg_Rate_Pln_Dim') IS NOT NULL 
DROP TABLE #Lodg_Rate_Pln_Dim;

CREATE TABLE #Lodg_Rate_Pln_Dim
(	 RATE_PLN_LODG_PROPERTY_KEY int null
	,LODG_RM_TYP_ID int null
	,LODG_RATE_PLN_KEY int null
)

INSERT INTO #Lodg_Rate_Pln_Dim
EXEC (@TD_Lodg_Rate_Pln_Dim)  

CREATE INDEX IX_1 on #Lodg_Rate_Pln_Dim (RATE_PLN_LODG_PROPERTY_KEY,LODG_RATE_PLN_KEY);

/*---------------------------------------------------------------------------------------------------------------------------------------------------------------
Putting all the data together at the booking item id level
Approx 514k records. 1.5 minutes. 
----------------------------------------------------------------------------------------------------------------------------------------------------------------*/


INSERT INTO Compliance.Lodging.Breakage
	(
	 BUSINESS_UNIT_ID
	,EXPE_LODG_PROPERTY_ID
	,PROPERTY_STATE_PROVNC_NAME
	,BEGIN_USE_YEAR_MONTH
	,BKG_ITM_ID
	,OPER_UNIT_ID
	,AP_LGL_OBLIG_IND
	,GL_PRODUCT_ID
	,SALES_TAX_AREA_NAME
	,COUNTY_TAX_AREA_NAME
	,CITY_TAX_AREA_NAME
	,GET_TAX_AREA_NAME
	,TOTL_TAX_RATE
	,SALES_TAX_RATE
	,COUNTY_TAX_RATE
	,CITY_TAX_RATE
	,GET_TAX_RATE
	,NET_AP_COST_AMT_USD
	,ACCRUED_COST_AMT_USD
	,AP_COST_ADJ_AMT_USD
	,NET_AP_PAYMNT_AMT_USD
	,NET_BRKAGE_AMT_USD
	,GROSS_BKG_AMT_USD
	,TOTL_COST_AMT_USD
	,TOTL_TAX_COST_AMT_USD
	,GENRIC_PAYMNT_AMT_USD
	,STAYLEVELTAXES
	,MC20TransAmtCost
	,LoadDate
	,LGL_ENTITY_CODE
	,MGMT_UNIT_CODE
	,ORACLE_GL_PRODUCT_CODE
	,LGL_ENTITY_NAME
	,LODG_PROPERTY_NAME
	,PROPERTY_POSTAL_CODE
	,RM_NIGHT_CNT
	,ComputedRoomCount
	,InsertedDate
	)


SELECT  
	'BUSINESS_UNIT_ID' = CAST(bu.BUSINESS_UNIT_ID AS VARCHAR(50))
	,tr.[Expedia ID] EXPE_LODG_PROPERTY_ID
	,REPLACE(tr.[State], ',', '') PROPERTY_STATE_PROVNC_NAME
	,b.BEGIN_USE_YEAR_MONTH
	,b.BKG_ITM_ID
	,'OPER_UNIT_ID' = ou.OPER_UNIT_ID
	,b.AP_LGL_OBLIG_IND
	,gl.GL_PRODUCT_ID
	,REPLACE(tr.[SALES TAX AREA], ',','') SALES_TAX_AREA_NAME
	,REPLACE(tr.[COUNTY TAX AREA], ',','') COUNTY_TAX_AREA_NAME
	,REPLACE(tr.[CITY TAX AREA], ',','') CITY_TAX_AREA_NAME
	,REPLACE(tr.[GET TAX AREA], ',','') GET_TAX_AREA_NAME
	,COALESCE(tr.[TOTAL TAX RATE],0)TOTL_TAX_RATE
	,COALESCE(tr.[SALES TAX RATE],0)SALES_TAX_RATE
	,COALESCE(tr.[COUNTY TAX RATE],0)COUNTY_TAX_RATE
	,COALESCE(tr.[CITY TAX RATE],0)CITY_TAX_RATE
	,COALESCE(tr.[GET TAX RATE],0)GET_TAX_RATE
	,COALESCE(b.NET_AP_COST_AMT_USD,0)NET_AP_COST_AMT_USD
	,COALESCE(b.ACCRUED_COST_AMT_USD,0)ACCRUED_COST_AMT_USD
	,COALESCE(b.AP_COST_ADJ_AMT_USD,0)AP_COST_ADJ_AMT_USD
	,COALESCE(b.NET_AP_PAYMNT_AMT_USD,0)NET_AP_PAYMNT_AMT_USD
	,COALESCE(b.NET_BRKAGE_AMT_USD,0)NET_BRKAGE_AMT_USD
	,COALESCE(g.GROSS_BKG_AMT_USD,0)GROSS_BKG_AMT_USD
	,COALESCE(g.TOTL_COST_AMT_USD,0)TOTL_COST_AMT_USD
	,COALESCE(g.TOTL_TAX_COST_AMT_USD,0)TOTL_TAX_COST_AMT_USD
	,COALESCE(gp.GENRIC_PAYMNT_AMT_USD,0)GENRIC_PAYMNT_AMT_USD
	,COALESCE(ap.STAYLEVELTAXES,0)STAYLEVELTAXES
	,COALESCE(mc.MC20TransAmtCost,0)MC20TransAmtCost
	,GETDATE() LoadDate
	,le.LGL_ENTITY_CODE
	,mu.MGMT_UNIT_CODE
	,ogl.ORACLE_GL_PRODUCT_CODE
	,REPLACE(le.LGL_ENTITY_NAME, ',','') LGL_ENTITY_NAME
	,REPLACE(lp.LODG_PROPERTY_NAME, ',','') LODG_PROPERTY_NAME
	,REPLACE(lp.PROPERTY_POSTAL_CODE, ',','') PROPERTY_POSTAL_CODE
	,g.RM_NIGHT_CNT
	,'ComputedRoomCount' = CAST(CASE WHEN (case when 
												(case	when OccupancyTaxPerDayAmt is null		 then 0 
														when (OccupancyTaxPerDayAmt - 1.5)/2 = 0 then 0 
														else floor((floor(abs((OccupancyTaxPerDayAmt - 1.5)/2)))/abs((OccupancyTaxPerDayAmt - 1.5)/2)) 
														end) = 1
											then (OccupancyTaxPerDayAmt - 1.5)/2
											else 0
											end) <> 0
								THEN
										(case when 
													(case when OccupancyTaxPerDayAmt is null		then 0
														  when (OccupancyTaxPerDayAmt - 1.5)/2 = 0	then 0
														  else floor((floor(abs((OccupancyTaxPerDayAmt - 1.5)/2)))/abs((OccupancyTaxPerDayAmt - 1.5)/2)) 
														  end) = 1
											  then (OccupancyTaxPerDayAmt - 1.5)/2
											  else 0
											  end) * g.RM_NIGHT_CNT
								ELSE 2*g.RM_NIGHT_CNT
							END AS SMALLINT)
   ,'InsertedDate' = GETDATE()							


FROM #TD_BREAKAGE b
	LEFT JOIN #Lodg_Property_Dim lp																	ON b.LODG_PROPERTY_KEY = lp.LODG_PROPERTY_KEY -- code added 9/8/14 tl
	JOIN #TAXRATE tr																				ON lp.EXPE_LODG_PROPERTY_ID = tr.[Expedia ID]  --Join to CSV upload file grab tax rates
	LEFT JOIN #Lgl_Entity_Dim le																	ON b.LGL_ENTITY_KEY  = le.LGL_ENTITY_KEY -- code added 9/8/14 tl
	LEFT JOIN #GBV2 g																				ON g.BKG_ITM_ID = b.BKG_ITM_ID
	LEFT JOIN #GENPAYMENT2 gp																		ON gp.MATCHED_BKG_ITM_ID = b.BKG_ITM_ID
	LEFT JOIN #APRECON2 ap																			ON ap.BOOKINGITEMID = b.BKG_ITM_ID
	LEFT JOIN #MCLASS20 mc																			ON mc.BookingItemID = b.BKG_ITM_ID
	LEFT JOIN #Lodg_Rate_Pln_Dim lrp																ON lrp.RATE_PLN_LODG_PROPERTY_KEY = lp.LODG_PROPERTY_KEY  -- code added 9/9/14
																										AND lrp.LODG_RATE_PLN_KEY =	g.LODG_RATE_PLN_KEY	
	LEFT JOIN [CHWXSQLNRT050.DataWarehouse.ExpEcn.com].LodgingInventoryImp.dbo.RoomType rt (nolock)	ON rt.SKUGroupID = lp.EXPE_LODG_PROPERTY_ID -- code added 9/9/14
																									    AND rt.[RoomTypeID] = lrp.LODG_RM_TYP_ID
	LEFT JOIN #OperatingUnitDim ou																	ON b.OPER_UNIT_KEY = ou.OPER_UNIT_KEY	
	LEFT JOIN #BusinessUnit bu																		ON b.BUSINESS_UNIT_KEY = bu.BUSINESS_UNIT_KEY
	LEFT JOIN #GLPRODUCTID gl																		ON b.GL_PRODUCT_KEY = gl.GL_PRODUCT_KEY
	LEFT JOIN #MGMT mu																				ON b.MGMT_UNIT_KEY = mu.MGMT_UNIT_KEY
	LEFT JOIN #ORACLEGL ogl																			ON b.ORACLE_GL_PRODUCT_KEY = ogl.ORACLE_GL_PRODUCT_KEY
																																																		
	
WHERE tr.[State] NOT IN (  SELECT DISTINCT 'Jurisdiction_State' = UPPER(Jurisdiction_State)
							  FROM compliance.lkup.LodgingCompliance l
							  WHERE  l.[Remittance_Type] = 'gross'
							  and [Reporting_Jurisdiction_Name] = 'all'
							  ) --20160729 TL updated - Oregon breakage no more, Oregon jurisdiction turned to single 7/1/15 
								--20170111 TL Updated - pull dynamically based off of the remittance type in the lkup table
---------------------------------------------------------------------------------------------




END



GO
