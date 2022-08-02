USE [IT_CoS]
GO

/****** Object:  StoredProcedure [TRAKiT].[sp_TESC_5MonthNotification]    Script Date: 6/25/2021 7:54:46 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO
















/*
** Prod File: TRAKiT_PROD
** Name: sproc TRAKiT.sp_TESC_5MonthNotification		 
** Location: SQL-07.IT_CoS		(the logic is pointed toward SQL-06 for the TRAKiT data b/c SQL-06 is not currently equipped to send emails)
** Desc: Logic to notify internal teams of the necessary TESC work required   
		
		Notes:* the first section declares variables
			  * the next section queries the list of distinct email recipients
			  * the next section starts the looping process to send each one of those distinct people, the list of their permit(s)
			  * the next section puts everything into a format that email will use (e.g. HTML) & then sends the email
			  * the loop continues for each email recipient
			  * the last section inserts the details of all permits with the timestamps into the Actions table and the Prmry_Notes table

** Usage: This will be used by ROW & Building groups. 
** Auth: Sheryle Harp, Tammy Lessley									
** Date: 20190514
**************************
** Change History								 
**************************
** TRAKiT Change Log	Date       Author			                            Description 
** ------------------	--------   -------			                            ------------------------------------
** Request #269   		20190514   Sheryle Harp, Tammy Lessley					Create sproc 
   SysAid  #21971		20190710   Tammy Lessley								Update the sproc with #PreConsThatHaveTESCs temp table that will disallow those permits that have Pre-Con meetings withOUT TESC inspections
   Change reques/Roper  20191016   Sheryle Harp, Tammy Lessley				    Update the #permitinfo and #permiinfo2												---see #PermitInfo query to see the incorporation of that logic
   Change Logic		    20191024   Sheryle Harp, Tammy Lessley	                Fixed logic for Final Building** to only show if have TESC
   Change Logic	        20200206   Sheryle Harp, Tammy Lessley	                Added Final Demo and Final Civil to logic and TESC Closeout
   Change Logic         20200218   Sheryle Harp, Tammy Lessley                  Add ST emails to notifications
   Change logic		    20200311   Sheryle Harp, Tammy Lessley		            Add Inspection Type to description and put in insp Record id for Chronology to help with Checklist report
   Change logic         20200616   Sheryle Harp, Tammy Lessley	                Corrected the 'insert' portion for primary notes so key between Action/notes in sync
						20200702   Sheryle Harp/Tammy Lessley					Remove Remarks 'Void'
						20200729   Sheryle Harp/Tammy Lessley                   Add new Erosion inspection types and adjusted logic - Building and LLE 
   Change logic 389		20200917   Sheryle Harp/Tammy Lessley				    Remove Sound Transit/LLE permits from this process since weekly inspections
   Change Logic	412		20200121   Sheryle Harp/Tammy Lessley					Change process from 5 month to 11 months due to ecologys parameters.
*/

 CREATE PROCEDURE [TRAKiT].[sp_TESC_5MonthNotification] 

AS

BEGIN ---begins the procedure

 
DECLARE
  @Email VARCHAR(80),
  @EmailSubject varchar(128),
  @BodyText nvarchar(max),
  @CurserRowNo integer = 1,
  @TableBody varchar(max);
----------------------------
---pulling all relevant info into a temp table NEEDS TO BE UPDATED INSPECTION TYPE AND COMPLETED DATE?

IF OBJECT_ID('tempdb..#PreConsThatHaveTESCs') IS NOT NULL  DROP TABLE #PreConsThatHaveTESCs;

SELECT	* 
INTO 	#PreConsThatHaveTESCs
FROM
	  (SELECT DISTINCT insp.[ActivityID]
						,'Flag' = CASE WHEN insp.InspectionType = 'PRE-CON MEETING'  ---add 3 new dudes
								   AND  (insp2.InspectionType LIKE '%TESC%' OR Insp2.InspectionType IN ('Erosion Control'))  -- removed 9.17.20 'LLE Erosion Control' since not following LLE with Master permit DEV19-0183
								   AND (INSP2.REMARKS NOT LIKE '%VOID%' OR Insp2.REMARKS IS NULL) --6.22.20
					               THEN 'PRE-CON'
								   WHEN INSP.InspectionType IN ('Final Building**', 'Final Demo**', 'Final Civil**') ---add 3 new dudes 
								   --AND insp.RESULT = 'PASSED'   --- Do we need? want to be reviewed every 11 months
								   AND (INSP2.InspectionType LIKE '%TESC%' OR Insp2.InspectionType IN ('Erosion Control'))  --'LLE Erosion Control' removed 9.17.20  ---AND insp2.COMPLETED_DATE IS NOT NULL 6.24.20 decided they did not want this to restrictive
								   AND (INSP2.REMARKS NOT LIKE '%VOID%' OR Insp2.REMARKS IS NULL) --6.22.20
								   THEN 'FINAL'
								   END

            FROM [SQL-06].[TRAKiT_PROD].dbo.Inspections insp with (nolock) 
            LEFT JOIN [SQL-06].[TRAKiT_PROD].dbo.Inspections insp2 with (nolock) ON insp.ActivityID = insp2.ActivityID 
                                                                                 AND (INSP2.InspectionType LIKE '%TESC%' OR insp2.InspectionType IN ('Erosion Control'))  --'LLE Erosion Control' removed 9.17.20 --added 7.28.20 SB specific? 
																				 
		--7.13.20 what needs to be added below? 

            WHERE insp.InspectionType IN ('PRE-CON MEETING', 'Final Building**', 'Final Demo**', 'Final Civil**') 
			--If has pre-con and Tesc then we want to review (but must have TESC/erosion along with Pre-con) narrow results but could be more rigid
           	AND insp2.InspectionType IS NOT NULL

            )x;

IF OBJECT_ID('tempdb..#PermitInfo') IS NOT NULL  DROP TABLE #PermitInfo;

SELECT	* 
INTO 	#PermitInfo
FROM

		(
			    SELECT 'PermitNo' = i.[ActivityID]
					  ,'PermitType' = pm.PermitType
					  ,'ApplicantName' = pm.APPLICANT_NAME
					  ,'Address' = pm.SITE_ADDR
					  ,'PermitStatus' = pm.[STATUS]
					  ,'PermitFinaled' = pm.FINALED
					  ,'InspectionType' = i.[InspectionType]
					  ,'LastInspDate' = CAST (i.[COMPLETED_DATE] AS DATE)
					  ,'ExpDate' = CAST (pm.[EXPIRED] AS DATE)
					  ,'Result' = i.[RESULT]
					  ,'Inspector' = i.[INSPECTOR]
					  ---we want to send emails to the correct Inspection email box
					 
					   ,'email' = CASE ---WHEN (pm.Description LIKE '%Sound%Transit%'  or  pm.permitsubtype LIKE '%LLE%')
							--		  AND pm.PermitType NOT LIKE '%RIGHT%OF%WAY%USE%'
							--		  THEN 'lrail@shorelinewa.gov' --- just changed 9.8.20 should we remove this?

									  --WHEN pm.PermitType LIKE '%RIGHT%OF%WAY%USE%'--This is specifically for ROW only
									  -- AND pm.permitsubtype = 'SOUND TRANSIT LLE' 
									  --THEN 'lrailrow@shorelinewa.gov'  ---do we need to remove this too? emailed Roper questions
									  
									  WHEN pm.PermitType LIKE '%RIGHT%OF%WAY%USE%' 
									  AND (pm.Description NOT LIKE '%Sound%Transit%'  or  pm.permitsubtype NOT LIKE '%LLE%')
									  THEN 'ROW@shorelinewa.gov' 
									  
									  WHEN  pm.PermitType NOT LIKE '%RIGHT%OF%WAY%USE%' 
									  AND (pm.Description NOT LIKE '%Sound%Transit%'  or  pm.permitsubtype NOT LIKE '%LLE%')
									  THEN  'Inspection@shorelinewa.gov'

									 
								 END
					  ---partition (group) by the permit number, then sorting the completed date + time to find the most recent (e.g. DESC), 
					  ---then using the record id as the tie breaker (if there are multiple inspections on the same date)
					  ,'TheMostRecent' = ROW_NUMBER() OVER (PARTITION BY i.[ActivityID] 
															ORDER BY (CASE WHEN LEN(i.COMPLETED_TIME) < 3 ---those with only the AM / PM letters, and no numbers
																			THEN i.[COMPLETED_DATE] +  '00:01 AM'
																			ELSE ISNULL(i.[COMPLETED_DATE], '00:01 AM')
																			END) DESC, 
																		i.RECORDID ASC) --tie breaker
				    ,i.RECORDID
			  FROM [SQL-06].[TRAKiT_PROD].[dbo].[Permit_Main] pm with (nolock)
			  LEFT JOIN [SQL-06].[TRAKiT_PROD].[dbo].[Inspections] i with (nolock) ON i.ActivityID = pm.[PERMIT_NO]  
  
 
			  WHERE  i.[COMPLETED_DATE] IS NOT NULL ---the inspection has been completed
			  AND pm.[FINALED] IS NULL ---the permit is not finaled
			  AND pm.STATUS = 'Issued' ---the permit is still active
			  AND (pm.permitsubtype NOT LIKE '%LLE%' AND pm.description NOT LIKE '%LLE%')
			  AND ( ----this pulls only the combos of permits & inspection types that are applicable to this process
						   CASE WHEN pm.[PermitType] IN ('Single Family-Simple', 'Single Family-Complex','Demolition', 
														 'Commercial', 'Multi-Family', 'Mixed Use','Misc Structure',
														 'Townhouse-SF Attached', 'Tree Removal','Site Development',
														 'Clearing and Grading') 
									  --AND i.InspectionType IN ('Pre-Con Meeting', 'TESC') --old version of line 20190710
									  AND i.InspectionType IN ('TESC', 'Erosion Control') --'LLE Erosion Control') --removed LLE from 11 month follow up as they review often
									  AND (i.REMARKS NOT LIKE '%VOID%' OR i.REMARKS IS NULL) --added 7.12.30
								  THEN 'Y'

								  
								 ----new section for the PreConsThatHaveTESCs logic 20190710
								 WHEN pm.[PermitType] IN ('Single Family-Simple', 'Single Family-Complex','Demolition', 
														 'Commercial', 'Multi-Family', 'Mixed Use','Misc Structure',
														 'Townhouse-SF Attached', 'Tree Removal','Site Development',
														 'Clearing and Grading') 
										AND i.[ActivityID] IN (SELECT DISTINCT [ActivityID] FROM #PreConsThatHaveTESCs WHERE Flag = 'Pre-Con')
										AND i.InspectionType IN ('PRE-CON MEETING')
								 THEN 'Y'

								 WHEN i.InspectionType IN ('Erosion CTL Start','Erosion Control','Erosion CTL Final') -- 9.17.20 removed 'LLE Erosion CTL Start''LLE Erosion Control''LLE Erosion CTL Final'
					             THEN 'Y' ---added 7.29.20

								 WHEN pm.PermitType IN ('Single Family-Simple', 'Single Family-Complex','Demolition', 
														'Commercial', 'Multi-Family', 'Mixed Use','Misc Structure',
														'Townhouse-SF Attached', 'Tree Removal','Site Development',
														'Clearing and Grading') 
									  AND i.InspectionType IN ('Final Building**', 'Final Demo**', 'Final Civil**')
									  AND i.[ActivityID] IN (SELECT DISTINCT [ActivityID] FROM #PreConsThatHaveTESCs WHERE Flag = 'Final')-- only want those that have a TESC Insp. 10.24.19

									  --AND I.[RESULT] <> 'PASSED' subsequent temp table addresses this logic
								 THEN 'Y'        
								 WHEN pm.PermitType IN ('Right-of-way Use') 
									  AND i.InspectionType IN  ('TESC', 'Row TESC Initial', 'Row TESC Monitor', 'ROW TESC CLOSEOUT')
								 THEN 'Y'
	   							 END
						 ) = 'Y'  
						 
					)x;

CREATE INDEX IX_1 on #PermitInfo (PermitNo); --placing an index on this table, so that the subsequent query will run faster 
---------------
---pulling all relevant info into a second temp table. using the above temp table and then isolating just those Most Recent inspections to compare against the 11 month time period
---------------

IF OBJECT_ID('tempdb..#PermitInfo2') IS NOT NULL  DROP TABLE #PermitInfo2;

SELECT	* 
INTO 	#PermitInfo2
FROM

		(
			  SELECT p.PermitNo
					,p.PermitType
					,p.ApplicantName
					,p.Address
					,p.PermitStatus
					,p.PermitFinaled
					,p.InspectionType
					,'LastInspDate' = CAST(p.LastInspDate AS VARCHAR(10))
					,'ExpDate' = CAST(p.ExpDate AS VARCHAR(10))
					,p.Result
					,p.Inspector
					,p.email
					,p.TheMostRecent
					,p.recordID
			  FROM #PermitInfo p
			  WHERE p.TheMostRecent = 1 ---the number 1's are the winners/most recent inspections for our purposes
			  AND p.ExpDate > CAST(GETDATE() as DATE) 
			  AND p.LastInspDate = CAST(DATEADD(MM, -11, GETDATE()) as DATE)		-------change from 5 months to 11 months 1.5.21 
			  --Breaking these pieces out as they do not follow normal TESC patterns
			  AND (CASE WHEN p.InspectionType IN ('ROW TESC CLOSEOUT', 'final building**', 'Final Demo**', 'Final Civil**','Erosion CTL Final') --'LLE Erosion CTL Final' removed 9.17.20
						     AND p.result = 'passed' 
					    THEN 'N'
						WHEN p.InspectionType IN ('ROW TESC CLOSEOUT', 'final building**', 'Final Demo**', 'Final Civil**', 'Erosion CTL Final') --'LLE Erosion CTL Final' removed 9.17.20
							AND p.Result <> 'passed'
						THEN 'Y'
						
						ELSE 'Y'  --This picks up ALL other TESC inspections in the family.
						END) ='Y'
					)x;

					





CREATE INDEX IX_2 on #PermitInfo2 (PermitNo); --placing an index on this table, so that the subsequent query will run faster

--------------------------
---begining of the looping process to feed these rows through the process below
  DECLARE LoopingProcessTESC5MonthNotification CURSOR FOR 

			----- this data feeds the email process and then feeds the insert process below.  
			----- This is a distinct list of people - for email purposes we do a seperate query to pull the full detail for the insertion process below 
  			SELECT DISTINCT Email
			FROM #PermitInfo2
			



  OPEN LoopingProcessTESC5MonthNotification ---allows the above select query to be used to populate the variables declared at the top of this script
  
  FETCH NEXT 
  -----recommend - update the FROM line below
  FROM LoopingProcessTESC5MonthNotification INTO @Email
											---this is written so that each of these variables are supposed to be in line with the select query fields above.
											---if we add or subtract from the query directly above, then this line needs to be updated to accommodate those changes


  WHILE @@FETCH_STATUS = 0 ---we only want the loop to run while things are executing successfully (e.g. equal to zero)
					
				
	------------------------this is the activity happening within each individual loop, for each distinct email recipient

				BEGIN
						-------verbiage in email
						SET	@EmailSubject = 'TESC Monitoring Inspection(s) Due' 
						
						-----This puts the special, grouped permit data for each email recipient into the proper table data (td) format 
						SET @TableBody = cast( (
													SELECT td = PermitNo + '</td><td>' + PermitType + '</td><td>' + InspectionType + '</td><td>' + ApplicantName  + '</td><td>' + Address  + '</td><td>' + LastInspDate + '</td><td>' + ExpDate 
													FROM ( 
															--------------insert the info here to pull into the display table section 
															SELECT DISTINCT 
																PermitNo,
																PermitType,
																InspectionType,
																ApplicantName, 
																Address,
																LastInspDate,
																ExpDate

															FROM #PermitInfo2
															WHERE Email = @Email
														  ) as d 

													for xml path( 'tr' ), type ) as varchar(max) ) 

													----tr is table rows
													----th is table header (seen below)
													----cellpadding is the amount of white space around the data within the cell
													----cellspacing is the amount of white space between table cells
												
																						
																												
						SET @BodyText = '<br><b>The purpose of this email is for your team to create/schedule/perform the next Monitoring TESC Inspection(s) for the below listed permit(s). These are to be done according to your department guidelines and are required to comply with our NPDES Permit.

										<br><br>Applicable permit(s): <ol>' + 
										
										'<table cellpadding="2" cellspacing="2" border="1">'
										  + '<tr><th>Permit Number</th><th>Permit Type</th><th>Insp Type</th><th>Applicant Name</th><th>Address</th><th>Last Insp. Date</th><th>Exp Date</th></tr>'
										  + replace( replace( @TableBody, '&lt;', '<' ), '&gt;', '>' )
										  + '</table> </ol>'	
										  --<br>'			  
																			
						
									  
						EXEC msdb.dbo.sp_send_dbmail 
							   @profile_Name ='SMTP',
							   @recipients = @Email, 
							   --@copy_recipients = 'sharp@shorelinewa.gov', -- include the ROW on all email correspondence for visibility
							   @blind_copy_recipients = 'sharp@shorelinewa.gov', --For me to review and make sure working, THEN REMOVE SH
							   @subject = @EmailSubject,
							   @body = @BodyText, 
							   @body_format = 'HTML',
							   @from_address = 'noreply@shorelinewa.gov',  ---having this present does not show in your sent box
							   @importance = 'HIGH'
							   --@reply_to = 'ROW@shorelinewa.gov' ----this needs to be in here, otherwise when people click reply to the message in their email, it will default to "no-reply@shorelinewa.gov"
							   
			  
					  SET @CurserRowNo = @CurserRowNo + 1 ---increases the loop to go do the next one in line
			  
					  FETCH NEXT 
			  
					  FROM LoopingProcessTESC5MonthNotification INTO @Email --, @PermitType  ---this is written so that each of these variables are supposed to be in line with the first select query fields above
			  
			  END --- end the loop
	
	CLOSE LoopingProcessTESC5MonthNotification		---closes the cursor
	DEALLOCATE LoopingProcessTESC5MonthNotification;	---removes a cursor reference - releasing it



/* 
==============================================================================
section for devoted to the insertion into chronology related tables 

Action_Description does not display on the website. Prmry_Notes is where the description is held and displayed for the users.
==============================================================================
*/ 
				
				
					  --This inserts the data into chronology
						INSERT INTO [SQL-06].[TRAKiT_PROD].[dbo].[Actions] 
									(
										ActivityID, 
										ActivityTypeID,
										Action_Date,
										Action_TYPE,
										Action_By,
										RECORDID,
										Completed_date,
										ACTION_DESCRIPTION
									)

								SELECT DISTINCT
										PermitNo,															---ActivityID
										1,																	---ActivityTypeID
										CAST(GETDATE() as DATE),											---Action_Date
										'EMAIL',															---Action_Type
										'TESC',																---Action_By
										recordid, 		                                                    ---RecordID
										CAST(GETDATE() as DATE),											---Completed_Date
										inspectionType + ' Monitor 11 Month Reminder '	+ LastInspDate		---Action_Description
								

								FROM #PermitInfo2



						--This inserts note data into chronology (Actions) to know where the email was sent
						INSERT INTO [SQL-06].[TRAKiT_PROD].[dbo].[Prmry_Notes] 
									(
										ActivityGroup, 
										ActivityNo, 
										ActivityRecordID, 
										SubGroup, 
										SubGroupRecordID, 
										UserID,
										DateEntered,
										Notes,
										MarkupStatus,
										eNotified
									)

						SELECT DISTINCT
										'PERMIT',																---ActivityGroup
										PermitNo,																---ActivityNo
										recordid,																---ActivityRecordID
										'ACTION',																---SubGroup
										Recordid, 																---SubGroupRecordID
										'TESC',																	---UserID
										GETDATE(),																---DateEntered
										inspectionType + ' Monitor 11 Month Reminder '	+ LastInspDate,		    ---Notes
										0,																		---MarkupStatus
										0																		---eNotified
										---If no email listed, notice will be emailed to sharp@shorelinewa.gov. If email kicked back it will be sent to ROW@shorelinewa.gov.
								

								FROM #PermitInfo2

END ---end the procedure



GO


