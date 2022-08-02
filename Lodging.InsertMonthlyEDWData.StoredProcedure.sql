USE [Compliance]
GO
/****** Object:  StoredProcedure [Lodging].[InsertMonthlyEDWData]    Script Date: 9/5/2017 10:47:49 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE  [Lodging].[InsertMonthlyEDWData]

AS
BEGIN

/*------------------------------------------------------
CREATED BY CHRIS TANIMOTO 10/2015

Tammy Lessley 05/09/2016 -- Updated and applied to monthly compliance process. 
This sproc is to be run after 12-noon on the 1st calendar day of the month.

April 2016 test - 15 minutes  1,712,722 - full states - many more transactions in CA than regular 

------------------------------------------------------*/
--Declare Variables
------------------------------------------------------
DECLARE @STARTDATE [varchar](50)
       ,@ENDDATE [varchar](50)
	   ,@STATE [varchar](128) 
	   ,@TD	[nvarchar](max)
	   ,@Name	VARCHAR(max)
	   ,@Name_ReplaceCommas nvarchar(max)
------------------------------------------------------
---get distinct list of states where we are liable
IF OBJECT_ID('tempdb..#States') IS NOT NULL DROP TABLE #States;

SELECT	* 
INTO #States
FROM (SELECT distinct 'Jurisdiction_State' = UPPER(Jurisdiction_State)
	  FROM compliance.lkup.LodgingCompliance )A;

------------------------------------------------------
SELECT @STARTDATE = CONVERT(VARCHAR(10), DATEADD(m, -1, DATEADD(d, 1, CONVERT(VARCHAR(10), DATEADD(d, -DATEPART(d, getdate()), GETDATE()), 120) )), 120) 
SELECT @ENDDATE   = CONVERT(VARCHAR(10), DATEADD(d, -DATEPART(d, getdate()), GETDATE()), 120)
---compile the list of distinct liable states into 1 long string
SELECT @Name = (SELECT  substring(
								(SELECT ',' + Jurisdiction_State 
								FROM #States
								ORDER BY Jurisdiction_State
								FOR XML PATH ('')), 2, 2000000) )
SET @Name_ReplaceCommas = REPLACE(@Name,',',''''',''''') + ''''',''''Oregon'
select @Name_ReplaceCommas
------------------------------------------------------
--Pull Data for State and Period (Key values are pulled later in the script)
------------------------------------------------------
SELECT @TD        = 'SELECT *    
						FROM 
							OPENQUERY(TDprod, 
										''SELECT
										rnt.Trans_date_Key (FORMAT ''''yyyymm'''') (Char(6)) AS TRANS_YEAR_MONTH,
										rnt.USE_DATE_KEY (FORMAT ''''yyyymm'''') (Char(6)) AS USE_YEAR_MONTH,
										rnt.BKG_ITM_ID,
										rnt.Order_Conf_NBR,
										rnt.Begin_Use_Date_KEY AS BEGIN_USE_DATE,
										rnt.END_USE_DATE_KEY AS END_USE_DATE,
										rnt.TRANS_TYP_KEY,
										EXPE_LODG_PROPERTY_ID,
										rnt.LGL_ENTITY_KEY,
										rnt.PRICE_CURRN_KEY,
										rnt.OPER_UNIT_KEY,
										rnt.GL_PRODUCT_KEY,
										rnt.MGMT_UNIT_KEY,
										rnt.ORACLE_GL_PRODUCT_KEY,
										rnt.BK_DATE_KEY AS BK_DATE,
										rnt.BUSINESS_UNIT_KEY,
										SUM(rnt.RM_NIGHT_CNT) RM_NIGHT_CNT,
										SUM(rnt.BASE_PRICE_AMT_LOCAL) BASE_PRICE_AMT_LOCAL,
										SUM(rnt.OTHR_PRICE_ADJ_AMT_LOCAL) OTHR_PRICE_ADJ_AMT_LOCAL,
										SUM(rnt.PNLTY_PRICE_ADJ_AMT_LOCAL) PNLTY_PRICE_ADJ_AMT_LOCAL,
										SUM(rnt.EXPE_PNLTY_PRICE_ADJ_AMT_LOCAL) EXPE_PNLTY_PRICE_ADJ_AMT_LOCAL,
										SUM(rnt.TOTL_PRICE_ADJ_AMT_LOCAL) TOTL_PRICE_ADJ_AMT_LOCAL,
										SUM(rnt.SVC_FEE_PRICE_AMT_LOCAL) SVC_FEE_PRICE_AMT_LOCAL,
										SUM(rnt.TOTL_FEE_PRICE_AMT_LOCAL) TOTL_FEE_PRICE_AMT_LOCAL,
										SUM(rnt.TOTL_TAX_PRICE_AMT_LOCAL) TOTL_TAX_PRICE_AMT_LOCAL,
										SUM(rnt.GROSS_BKG_AMT_LOCAL) GROSS_BKG_AMT_LOCAL,
										SUM(rnt.BASE_COST_AMT_USD) BASE_COST_AMT_USD,
										SUM(rnt.OTHR_COST_ADJ_AMT_USD) OTHR_COST_ADJ_AMT_USD,
										SUM(rnt.SUPPL_COST_ADJ_AMT_USD) SUPPL_COST_ADJ_AMT_USD,
										SUM(rnt.TOTL_COST_ADJ_AMT_USD) TOTL_COST_ADJ_AMT_USD,
										SUM(rnt.TOTL_COST_AMT_USD) TOTL_COST_AMT_USD,
										SUM(rnt.TOTL_FEE_COST_AMT_USD) TOTL_FEE_COST_AMT_USD,
										SUM(rnt.TOTL_TAX_COST_AMT_USD) TOTL_TAX_COST_AMT_USD,
										SUM(rnt.SVC_CHRG_PRICE_AMT_LOCAL) SVC_CHRG_PRICE_AMT_LOCAL,
										SUM(rnt.CNCL_CHG_FEE_PRICE_AMT_LOCAL) CNCL_CHG_FEE_PRICE_AMT_LOCAL

										FROM P_DM_BKG_LODG.LODG_RM_NIGHT_TRANS_FACT rnt
										JOIN P_DM_COMMON.LODG_PROPERTY_DIM lpd           ON 				lpd.lodg_Property_Key = rnt.lodg_property_key
										JOIN P_DM_COMMON.PRODUCT_LN_DIM pld				 ON 				pld.PRODUCT_LN_KEY	  = rnt.PRODUCT_LN_KEY

										WHERE

										(
												(
													rnt.USE_DATE_KEY between '''''+ @startdate +''''' and '''''+ @enddate +'''''
													AND rnt.TRANS_DATE_KEY <= '''''+ @enddate +'''''
												)
											OR
												(
													rnt.USE_DATE_KEY < '''''+ @startdate +''''' 
													AND rnt.Trans_Date_Key between '''''+ @startdate +''''' and '''''+ @enddate +'''''
												)
										)
										AND pld.Business_Model_Name=''''Merchant''''
										AND pld.Business_Model_SUBTYP_Name <> ''''Opaque Merchant''''
										AND pld.Product_LN_NAME = ''''Lodging''''
										AND 
										(
												((
													UPPER(TRIM(OREPLACE(lpd.property_state_provnc_name, CHR(9), NULL))) IN (''''' + @Name_ReplaceCommas +''''') 
													AND UPPER(lpd.property_cntry_name) IN (''''USA'''', ''''UNITED STATES OF AMERICA'''')
												))
												
												OR 
												
												((
													UPPER(TRIM(lpd.property_cntry_name)) IN (''''PR'''', ''''PUERTO RICO'''')
												)) 
										)

										GROUP BY 
										rnt.Trans_date_Key,
										rnt.USE_DATE_KEY,
										rnt.BKG_ITM_ID,
										rnt.Order_Conf_NBR,
										rnt.Begin_Use_Date_KEY,
										rnt.END_USE_DATE_KEY,
										rnt.TRANS_TYP_KEY,
										lpd.EXPE_LODG_PROPERTY_ID,
										rnt.LGL_ENTITY_KEY,
										rnt.PRICE_CURRN_KEY,
										rnt.OPER_UNIT_KEY,
										rnt.GL_PRODUCT_KEY,
										rnt.MGMT_UNIT_KEY,
										rnt.ORACLE_GL_PRODUCT_KEY,
										rnt.BK_DATE_KEY,
										rnt.BUSINESS_UNIT_KEY'')' 

---------------------------------------------
IF OBJECT_ID('tempdb..#KEYPULL') IS NOT NULL 
DROP TABLE #KEYPULL;
---------------------------------------------
CREATE TABLE #KEYPULL(
	[TRANS_YEAR_MONTH] [char](6) NOT NULL,
	[USE_YEAR_MONTH] [char](6) NOT NULL,
	[BKG_ITM_ID] [int] NOT NULL,
	[ORDER_CONF_NBR] [varchar](50) NULL,
	[BEGIN_USE_DATE] [datetime] NOT NULL,
	[END_USE_DATE] [datetime] NOT NULL,
	[TRANS_TYP_KEY] [smallint] NOT NULL,
	[EXPE_LODG_PROPERTY_ID] [int] NULL,
	[LGL_ENTITY_KEY] [smallint] NOT NULL,
	[PRICE_CURRN_KEY] [smallint] NOT NULL,
	[OPER_UNIT_KEY] [smallint] NOT NULL,
	[GL_PRODUCT_KEY] [smallint] NOT NULL,
	[MGMT_UNIT_KEY] [smallint] NOT NULL,
	[ORACLE_GL_PRODUCT_KEY] [smallint] NOT NULL,
	[BK_DATE] [datetime] NOT NULL,
	[BUSINESS_UNIT_KEY] [smallint] NOT NULL,
	[RM_NIGHT_CNT] [int] NOT NULL,
	[BASE_PRICE_AMT_LOCAL] [numeric](38, 4) NOT NULL,
	[OTHR_PRICE_ADJ_AMT_LOCAL] [numeric](38, 4) NOT NULL,
	[PNLTY_PRICE_ADJ_AMT_LOCAL] [numeric](38, 4) NOT NULL,
	[EXPE_PNLTY_PRICE_ADJ_AMT_LOCAL] [numeric](38, 4) NOT NULL,
	[TOTL_PRICE_ADJ_AMT_LOCAL] [numeric](38, 4) NOT NULL,
	[SVC_FEE_PRICE_AMT_LOCAL] [numeric](38, 4) NOT NULL,
	[TOTL_FEE_PRICE_AMT_LOCAL] [numeric](38, 4) NOT NULL,
	[TOTL_TAX_PRICE_AMT_LOCAL] [numeric](38, 4) NOT NULL,
	[GROSS_BKG_AMT_LOCAL] [numeric](38, 4) NOT NULL,
	[BASE_COST_AMT_USD] [numeric](38, 4) NOT NULL,
	[OTHR_COST_ADJ_AMT_USD] [numeric](38, 4) NOT NULL,
	[SUPPL_COST_ADJ_AMT_USD] [numeric](38, 4) NOT NULL,
	[TOTL_COST_ADJ_AMT_USD] [numeric](38, 4) NOT NULL,
	[TOTL_COST_AMT_USD] [numeric](38, 4) NOT NULL,
	[TOTL_FEE_COST_AMT_USD] [numeric](38, 4) NOT NULL,
	[TOTL_TAX_COST_AMT_USD] [numeric](38, 4) NOT NULL,
	[SVC_CHRG_PRICE_AMT_LOCAL] [numeric](38, 4) NOT NULL,
	[CNCL_CHG_FEE_PRICE_AMT_LOCAL] [numeric](38, 4) NOT NULL
) 

INSERT INTO #KEYPULL
EXEC (@TD)
----select @td
--------------------------------------------------------------------

IF OBJECT_ID('tempdb..#lodgpropkey') IS NOT NULL 
DROP TABLE #lodgpropkey;
SELECT	*
INTO #lodgpropkey
FROM

       (SELECT *
       FROM 
              OPENQUERY(tdprod,  
      'SELECT *  
		FROM P_DM_COMMON.LODG_PROPERTY_DIM pd 
		;'))X
									

CREATE INDEX IX_1 on #lodgpropkey (expe_lodg_property_id);
-------------------------------

CREATE INDEX IX_14 on #KEYPULL (
TRANS_YEAR_MONTH,
USE_YEAR_MONTH,
BKG_ITM_ID,
Order_Conf_NBR,
Begin_Use_Date,
END_USE_DATE,
TRANS_TYP_KEY,
LGL_ENTITY_KEY,
PRICE_CURRN_KEY,
OPER_UNIT_KEY,
GL_PRODUCT_KEY,
MGMT_UNIT_KEY,
ORACLE_GL_PRODUCT_KEY,
BK_DATE);
-------------------------------------------------------------------------------------------------------------
--Begin KEY PULLS
-------------------------------------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#TRANSTYPEDIM') IS NOT NULL 
DROP TABLE #TRANSTYPEDIM;
SELECT	*
INTO #TRANSTYPEDIM
FROM

(SELECT *
	FROM 
		OPENQUERY(TDprod, 
'SELECT 
TRANS_TYP_DIM.TRANS_TYP_KEY,
TRANS_TYP_DIM.TRANS_TYP_NAME
FROM P_DM_COMMON.TRANS_TYP_DIM;'))x

CREATE INDEX IX_1 on #TRANSTYPEDIM (TRANS_TYP_KEY);

-------------------------------------------------------------------------------------------------------------
--KEY PULLS Continue
-------------------------------------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#LGLENT') IS NOT NULL 
DROP TABLE #LGLENT;
SELECT	*
INTO #LGLENT
FROM

(SELECT *
	FROM 
		OPENQUERY(TDprod, 
'SELECT
LGL_ENTITY_DIM.LGL_ENTITY_KEY,
LGL_ENTITY_DIM.LGL_ENTITY_CODE,
LGL_ENTITY_DIM.LGL_ENTITY_NAME
FROM P_DM_COMMON.LGL_ENTITY_DIM;'))X
CREATE INDEX IX_1 on #LGLENT (LGL_ENTITY_KEY);
-------------------------------------------------------------------------------------------------------------
--KEY PULLS Continue
-------------------------------------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#PCC') IS NOT NULL 
DROP TABLE #PCC;
SELECT	*
INTO #PCC
FROM

(SELECT *
	FROM 
		OPENQUERY(TDprod, 
'SELECT
PRICE_CURRN_DIM.PRICE_CURRN_CODE,
PRICE_CURRN_DIM.PRICE_CURRN_KEY
FROM P_DM_BKG_LODG.PRICE_CURRN_DIM;'))x
CREATE INDEX IX_1 on #PCC (PRICE_CURRN_KEY);
-------------------------------------------------------------------------------------------------------------
--KEY PULLS Continue
-------------------------------------------------------------------------------------------------------------
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
--KEY PULLS Continue
-------------------------------------------------------------------------------------------------------------
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
--KEY PULLS Continue
-------------------------------------------------------------------------------------------------------------
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
--KEY PULLS Continue
-------------------------------------------------------------------------------------------------------------
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
-------------------------------------------------------------------------------------------------------------
--MERGE EVERYTHING TOGETHER
-------------------------------------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#TESTTEMP') IS NOT NULL 
DROP TABLE #TESTTEMP;
SELECT *
INTO #TESTTEMP
FROM
(SELECT

rnt.TRANS_YEAR_MONTH,
rnt.USE_YEAR_MONTH,
rnt.BKG_ITM_ID,
rnt.Order_Conf_NBR,
rnt.BEGIN_USE_DATE,
rnt.END_USE_DATE,
ttd.TRANS_TYP_NAME,
rnt.EXPE_LODG_PROPERTY_ID,
lgl.LGL_ENTITY_CODE,
lgl.LGL_ENTITY_NAME,
pcc.PRICE_CURRN_CODE,
oud.OPER_UNIT_ID,
gpd.GL_PRODUCT_ID,
mud.MGMT_UNIT_CODE,
ogp.ORACLE_GL_PRODUCT_CODE,
rnt.BK_DATE,
bud.Business_Unit_ID,
bud.Business_Unit_name,
SUM(rnt.RM_NIGHT_CNT) RM_NIGHT_CNT,
SUM(rnt.BASE_PRICE_AMT_LOCAL) BASE_PRICE_AMT_LOCAL,
SUM(rnt.OTHR_PRICE_ADJ_AMT_LOCAL) OTHR_PRICE_ADJ_AMT_LOCAL,
SUM(rnt.PNLTY_PRICE_ADJ_AMT_LOCAL) PNLTY_PRICE_ADJ_AMT_LOCAL,
SUM(rnt.EXPE_PNLTY_PRICE_ADJ_AMT_LOCAL) EXPE_PNLTY_PRICE_ADJ_AMT_LOCAL,
SUM(rnt.TOTL_PRICE_ADJ_AMT_LOCAL) TOTL_PRICE_ADJ_AMT_LOCAL,
SUM(rnt.SVC_FEE_PRICE_AMT_LOCAL) SVC_FEE_PRICE_AMT_LOCAL,
SUM(rnt.TOTL_FEE_PRICE_AMT_LOCAL) TOTL_FEE_PRICE_AMT_LOCAL,
SUM(rnt.TOTL_TAX_PRICE_AMT_LOCAL) TOTL_TAX_PRICE_AMT_LOCAL,
SUM(rnt.GROSS_BKG_AMT_LOCAL) GROSS_BKG_AMT_LOCAL,
SUM(rnt.BASE_COST_AMT_USD) BASE_COST_AMT_USD,
SUM(rnt.OTHR_COST_ADJ_AMT_USD) OTHR_COST_ADJ_AMT_USD,
SUM(rnt.SUPPL_COST_ADJ_AMT_USD) SUPPL_COST_ADJ_AMT_USD,
SUM(rnt.TOTL_COST_ADJ_AMT_USD) TOTL_COST_ADJ_AMT_USD,
SUM(rnt.TOTL_COST_AMT_USD) TOTL_COST_AMT_USD,
SUM(rnt.TOTL_FEE_COST_AMT_USD) TOTL_FEE_COST_AMT_USD,
SUM(rnt.TOTL_TAX_COST_AMT_USD) TOTL_TAX_COST_AMT_USD,
SUM(rnt.SVC_CHRG_PRICE_AMT_LOCAL) SVC_CHRG_PRICE_AMT_LOCAL,
SUM(rnt.CNCL_CHG_FEE_PRICE_AMT_LOCAL) CNCL_CHG_FEE_PRICE_AMT_LOCAL

FROM #KEYPULL rnt
JOIN #TRANSTYPEDIM ttd			ON rnt.trans_typ_key=ttd.Trans_typ_key
JOIN #LGLENT lgl				ON rnt.LGL_ENTITY_KEY=lgl.LGL_ENTITY_KEY
JOIN #PCC    pcc				ON rnt.PRICE_CURRN_KEY=pcc.PRICE_CURRN_KEY
JOIN #OperatingUnitDim oud		ON rnt.OPER_UNIT_KEY=oud.OPER_UNIT_KEY
JOIN #GLPRODUCTID gpd    	    ON rnt.GL_PRODUCT_KEY=gpd.GL_PRODUCT_KEY
JOIN #MGMT mud					ON rnt.MGMT_UNIT_KEY=mud.MGMT_UNIT_KEY
JOIN #OracleGL ogp				ON rnt.ORACLE_GL_PRODUCT_KEY=ogp.ORACLE_GL_PRODUCT_KEY
JOIN #BusinessUnit bud			ON rnt.BUSINESS_UNIT_KEY=bud.BUSINESS_UNIT_KEY

GROUP BY 
rnt.TRANS_YEAR_MONTH,
rnt.USE_YEAR_MONTH,
rnt.BKG_ITM_ID,
rnt.Order_Conf_NBR,
rnt.BEGIN_USE_DATE,
rnt.END_USE_DATE,
ttd.TRANS_TYP_NAME,
rnt.EXPE_LODG_PROPERTY_ID,
lgl.LGL_ENTITY_CODE,
lgl.LGL_ENTITY_NAME,
pcc.PRICE_CURRN_CODE,
oud.OPER_UNIT_ID,
gpd.GL_PRODUCT_ID,
mud.MGMT_UNIT_CODE,
ogp.ORACLE_GL_PRODUCT_CODE,
rnt.BK_DATE,
bud.Business_Unit_ID,
bud.Business_Unit_name)X


-------------------------------------------------------------------------------------------------------------
--Modify Temp Table to match DB2 Script
----0:00 with DC
-------------------------------------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#Modify') IS NOT NULL 
DROP TABLE #Modify;
SELECT *
INTO #MODIFY
FROM
(SELECT
       trans_year_month
      ,use_year_month
      ,bkg_itm_id  
      ,order_conf_nbr			
      ,min(begin_use_date)				   as begin_use_date
      ,max(end_use_date)				   as end_use_date
      ,trans_typ_name					   as trans_typ_name
      ,max(expe_lodg_property_id)		   as expe_lodg_property_id
      ,max(lgl_entity_code)				   as lgl_entity_code
      ,max(lgl_entity_name)				   as lgl_entity_name
      ,max(business_unit_id)			   as business_unit_id
      ,max(business_unit_name)			   as business_unit_name
      ,max(price_currn_code)			   as price_currn_code
      ,max(oper_unit_id)				   as oper_unit_id
      ,max(gl_product_id)				   as gl_product_id
      ,max(mgmt_unit_code)				   as mgmt_unit_code
      ,max(oracle_gl_product_code)		   as oracle_gl_product_code
      ,max(bk_date)						   as  bk_date
      ,sum(rm_night_cnt)                   as rm_night_cnt
      ,sum(base_price_amt_local)           as base_price_amt_local
      ,sum(othr_price_adj_amt_local)       as othr_price_adj_amt_local
      ,sum(pnlty_price_adj_amt_local)      as pnlty_price_adj_amt_local
      ,sum(expe_pnlty_price_adj_amt_local) as expe_pnlty_price_adj_amt_local
      ,sum(totl_price_adj_amt_local)       as totl_price_adj_amt_local
      ,sum(svc_fee_price_amt_local)        as svc_fee_price_amt_local
      ,sum(totl_fee_price_amt_local)       as totl_fee_price_amt_local
      ,sum(totl_tax_price_amt_local)       as totl_tax_price_amt_local
      ,sum(gross_bkg_amt_local)            as gross_bkg_amt_local
      ,sum(base_cost_amt_usd)              as base_cost_amt_usd
      ,sum(othr_cost_adj_amt_usd)          as othr_cost_adj_amt_usd
      ,sum(suppl_cost_adj_amt_usd)         as suppl_cost_adj_amt_usd
      ,sum(totl_cost_adj_amt_usd)          as totl_cost_adj_amt_usd
      ,sum(totl_cost_amt_usd)              as totl_cost_amt_usd
      ,sum(totl_fee_cost_amt_usd)          as totl_fee_cost_amt_usd
      ,sum(totl_tax_cost_amt_usd)          as totl_tax_cost_amt_usd
      ,sum(svc_chrg_price_amt_local)       as svc_chrg_price_amt_local
      ,sum(cncl_chg_fee_price_amt_local)   as cncl_chg_fee_price_amt_local
	FROM #TESTTEMP
	GROUP BY 
	   trans_year_month 
      ,use_year_month
      ,trans_typ_name
      ,bkg_itm_id
      ,order_conf_nbr)X

CREATE INDEX IX_3 on #MODIFY (expe_lodg_property_id,price_currn_code,bk_date);


-------------------------------------------------------------------------------------------------------------
--Assemble currency code stuff
----2:03 with DC Data
-------------------------------------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#T1') IS NOT NULL 
DROP TABLE #T1;
SELECT *
INTO #T1
FROM
(SELECT DISTINCT price_currn_code, 
		bk_date
	    FROM #TESTTEMP)C
---------------------------

---------------------------
IF OBJECT_ID('tempdb..#ExchangeRates') IS NOT NULL 
DROP TABLE #ExchangeRates;
SELECT	*
INTO #ExchangeRates
FROM

(SELECT *
	FROM 
		OPENQUERY(TDprod, 
'SELECT * 
FROM P_ADS_COMMON.DAILY_EXCH_RATE WHERE TO_CURRN_CODE=''USD''
ORDER BY EXCH_RATE_DATE;'))X

CREATE INDEX IX_3 on #ExchangeRates (from_currn_code,to_currn_code,exch_rate_date);
---------------------------

---------------------------
IF OBJECT_ID('tempdb..#T2') IS NOT NULL 
DROP TABLE #T2;
SELECT *
INTO #T2
FROM
(SELECT  t.price_currn_code as from_currn_code
		,t.bk_date as exch_rate_date
		,coalesce(er.exch_rate, 0) as usd_ex_rate
        ,row_number() over (partition by t.price_currn_code, t.bk_date order by er.exch_rate_date desc) as rn
 FROM #T1 t
 JOIN #ExchangeRates er 
	ON      er.from_currn_code = t.price_currn_code
        and er.to_currn_code  = 'USD'
        and er.exch_rate_date <= t.bk_date)e

---------------------------
IF OBJECT_ID('tempdb..#Daily_Exch_rate') IS NOT NULL 
DROP TABLE #Daily_Exch_rate;
SELECT *
INTO #Daily_Exch_rate
FROM
(select
       from_currn_code
      ,exch_rate_date
      ,usd_ex_rate AS usd_ex_rate
   from #T2
   where rn=1)p
CREATE INDEX IX_3 on #Daily_Exch_rate (from_currn_code,exch_rate_date,usd_ex_rate);
-------------------------------------------------------------------------------------------------------------
--Pull it all together
-------------------------------------------------------------------------------------------------------------
INSERT INTO Lodging.EDW
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
      ,[InsertedDate])



SELECT
       CONVERT(VARCHAR(10), DATEADD(d, -DATEPART(d, getdate()), GETDATE()), 120)                                     as reportenddate
      ,LEFT(CONVERT(varchar, a.bk_date,112),6)                                                                       as book_year_month      
      ,a.trans_year_month                                                                                            as trans_year_month
      ,a.use_year_month                                                                                              as use_year_month
      ,a.bkg_itm_id                                                                                                  as bkg_itm_id
      ,a.order_conf_nbr																								 as order_conf_nbr	
      ,a.begin_use_date                                                                                              as begin_use_date
      ,a.end_use_date                                                                                                as end_use_date
      ,a.trans_typ_name                                                                                              as trans_typ_name
      ,a.expe_lodg_property_id                                                                                       as expe_lodg_property_id
      ,a.lgl_entity_code                                                                                             as lgl_entity_code
      ,a.lgl_entity_name                                                                                             as lgl_entity_name
      ,a.business_unit_id                                                                                            as business_unit_id
      ,a.business_unit_name                                                                                          as business_unit_name
      ,b.lodg_property_name                                                                                          as lodg_property_name
      ,b.property_city_name                                                                                          as property_city_name
      ,replace(case when UPPER(b.property_cntry_name) = 'PUERTO RICO'
			then 'PR'
			when UPPER(b.property_cntry_name) = 'OREGON'
			then 'OR'
			else b.property_state_provnc_name
			end, char(9), '')				                                                                         as property_state_provnc_name
      ,left(b.property_postal_code,5)                                                                                as property_postal_code
      ,a.price_currn_code                                                                                            as price_currn_code
      ,a.oper_unit_id                                                                                                as oper_unit_id
      ,a.gl_product_id                                                                                               as gl_product_id
      ,a.mgmt_unit_code                                                                                              as mgmt_unit_code
      ,a.oracle_gl_product_code                                                                                      as oracle_gl_product_code
      ,a.rm_night_cnt                                                                                                as rm_night_cnt
      ,r.[sales tax area]                                                                                            as sales_tax_area
      ,r.[county tax area]                                                                                           as county_tax_area
      ,r.[city tax area]                                                                                             as city_tax_area
      ,r.[get tax area]                                                                                              as get_tax_area
      ,r.[sales tax rate]                                                                                            as sales_tax_rate
      ,r.[county tax rate]                                                                                           as county_tax_rate
      ,r.[city tax rate]                                                                                             as city_tax_rate
      ,r.[get tax rate]                                                                                              as get_tax_rate
      ,r.[total tax rate]                                                                                            as total_tax_rate
      ,isnull((a.base_price_amt_local*coalesce(der.usd_ex_rate,0)),0)                                                as base_price_usd
      ,isnull(((a.othr_price_adj_amt_local+a.pnlty_price_adj_amt_local+a.expe_pnlty_price_adj_amt_local)
		*coalesce(der.usd_ex_rate,0)),0)																			 as flat_adj_usd
      ,isnull(((a.totl_price_adj_amt_local-a.othr_price_adj_amt_local-a.pnlty_price_adj_amt_local
         - a.expe_pnlty_price_adj_amt_local)*coalesce(der.usd_ex_rate,0)), 0)                                        as all_othr_adj_usd
      ,isnull((a.svc_fee_price_amt_local*coalesce(der.usd_ex_rate,0)),0)                                             as svc_fee_price_usd
      ,isnull(((a.totl_fee_price_amt_local-a.svc_fee_price_amt_local)*coalesce(der.usd_ex_rate,0)), 0)               as all_othr_fees_usd
      ,isnull((a.totl_tax_price_amt_local*coalesce(der.usd_ex_rate,0)), 0)                                           as total_tax_usd
      ,isnull((a.gross_bkg_amt_local*coalesce(der.usd_ex_rate,0)), 0)                                                as total_price_usd
      ,isnull((a.base_cost_amt_usd), 0)                                                                              as base_cost_usd
      ,isnull((a.othr_cost_adj_amt_usd + a.suppl_cost_adj_amt_usd), 0)                                               as flat_cost_adj_usd
      ,isnull((a.totl_cost_adj_amt_usd - a.othr_cost_adj_amt_usd - a.suppl_cost_adj_amt_usd), 0)                     as othr_cost_adj_usd
      ,isnull((a.totl_fee_cost_amt_usd), 0)                                                                          as total_cost_fee_usd
      ,isnull((a.totl_cost_amt_usd), 0)                                                                              as total_cost_usd
      ,isnull((a.totl_tax_cost_amt_usd), 0)                                                                          as tax_collected
      ,isnull((a.totl_fee_price_amt_local*coalesce(der.usd_ex_rate,0)), 0)                                           as total_price_fee_usd
      ,isnull(((a.base_price_amt_local*coalesce(der.usd_ex_rate,0))+((a.totl_price_adj_amt_local-a.othr_price_adj_amt_local
         -a.pnlty_price_adj_amt_local-a.expe_pnlty_price_adj_amt_local)*coalesce(der.usd_ex_rate,0))
         +(a.totl_fee_cost_amt_usd)), 0)                                                                             as tax_base_margin
      ,isnull(((a.base_cost_amt_usd)+(a.totl_cost_adj_amt_usd-a.othr_cost_adj_amt_usd-a.suppl_cost_adj_amt_usd)
         + (a.totl_fee_price_amt_local*coalesce(der.usd_ex_rate,0))), 0)                                             as tax_base_cost
      ,isnull(case when a.trans_typ_name in ('Purchase','Rebook')
				then 0
				when ((a.othr_price_adj_amt_local+a.pnlty_price_adj_amt_local
					   +a.expe_pnlty_price_adj_amt_local)*coalesce(der.usd_ex_rate,0))=0
				then 0
				else ((a.othr_price_adj_amt_local+a.pnlty_price_adj_amt_local
					   +a.expe_pnlty_price_adj_amt_local)*coalesce(der.usd_ex_rate,0))
					   -(((a.othr_price_adj_amt_local+a.pnlty_price_adj_amt_local
					   +a.expe_pnlty_price_adj_amt_local)*coalesce(der.usd_ex_rate,0))
					   /(1+v.[total tax rate])) 
				end , 0)                                                                                             as price_tax_adj_wzeroflat
      ,isnull(case when a.trans_typ_name in ('Purchase','Rebook')
				then 0
				else ((a.othr_price_adj_amt_local+a.pnlty_price_adj_amt_local
					   +a.expe_pnlty_price_adj_amt_local)*coalesce(der.usd_ex_rate,0))
					   -(((a.othr_price_adj_amt_local+a.pnlty_price_adj_amt_local
					   +a.expe_pnlty_price_adj_amt_local)*coalesce(der.usd_ex_rate,0))
					   /(1+v.[total tax rate])) 
				end, 0)                                                                                              as price_tax_adj
      ,isnull(case when a.trans_typ_name in ('Purchase','Rebook')
				then 0
				when (a.othr_cost_adj_amt_usd + a.suppl_cost_adj_amt_usd)=0
				then 0
				else (a.othr_cost_adj_amt_usd + a.suppl_cost_adj_amt_usd)
					  -((a.othr_cost_adj_amt_usd + a.suppl_cost_adj_amt_usd)
					   /(1+v.[total tax rate])) 
			end, 0)                                                                                                  as cost_tax_adj
      ,isnull(case when a.trans_typ_name ='Cancel'
				then (a.othr_cost_adj_amt_usd + a.suppl_cost_adj_amt_usd)
					  -((a.othr_cost_adj_amt_usd + a.suppl_cost_adj_amt_usd)
					   /(1+v.[total tax rate])) 
				else 0
			end, 0)                                                                                                  as cost_tax_adj_wcancel
      ,GETDATE()
      
   from #Modify a
   join #lodgpropkey b					on a.expe_lodg_property_id = b.expe_lodg_property_id  
   left join compliance.Rates.V_CSV r	on a.expe_lodg_property_id = r.[Expedia ID]   ---bring all booking data over. the risk in doing a left join
																						---is that some of the hotels with bookings in those states, do not have corresponding rates
																						---in the rate tables in the compliance db. but we would rather have all the transactions, no matter
																						---if there are corresponding rates. which could be applied later if need be.  
   left join #Daily_Exch_rate der		on der.from_currn_code = a.price_currn_code
											and der.exch_rate_date = a.bk_date
   left join [Rates].[V_ActiveHotel_VSC_Total] v ON b.expe_lodg_property_id = v.[Hotel ID]



END










GO
