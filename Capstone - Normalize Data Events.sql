

GO
----Finding the PY averages & placing in this CTE 

WITH PreviousYearAvg AS

(
		SELECT tt.[Package Size Name]
			  ,tt.[Material Id]
			  ,tt.[Brand]
			  ,tt.[ProdCategory]
			  ,tt.[SoldToCorporate Entity]
			  ,tt.[SoldToBanner]
			  ,tt.[SoldToRegional]
			  ,tt.[SoldToPartner]
			  --,tt.[Name]
			  ,'Week' = DATEPART(WEEK, tt.[Name]) ---157,651
			  ,'Year' = DATEPART(YEAR, tt.[Name])
			  ,'Value' = AVG(tt.[Value])

			  ,det.[Data Event Name]
			  --,YEAR(det.[Event Start Date]) --used this to verify the join was matched with previous year time periods
			  -----need PY weekly averages 
		  FROM [dbo].[UC_TAL_Tab4_Transposed] (nolock)  tt
		  LEFT JOIN [dbo].[UC_TAL_DataEventTracking] (nolock) det ON DATEPART(WEEK, tt.[Name])  BETWEEN DATEPART(WEEK, det.[Event Start Date] ) AND DATEPART(WEEK, det.[Event End Date] )
																									AND YEAR(tt.[Name])  = YEAR(det.[Event Start Date]) - 1
		  																							AND YEAR(tt.[Name])  = YEAR(det.[Event End Date]) - 1
		  
		  WHERE det.[Data Event Name] IS NOT NULL --only want to pull the averages for those time periods 1 year previous to the desired events
		  GROUP BY tt.[Package Size Name]
				  ,tt.[Material Id]
				  ,tt.[Brand]
				  ,tt.[ProdCategory]
				  ,tt.[SoldToCorporate Entity]
				  ,tt.[SoldToBanner]
				  ,tt.[SoldToRegional]
				  ,tt.[SoldToPartner]
				  --,tt.[Name]
				  ,DATEPART(WEEK, tt.[Name]) 
				  ,DATEPART(YEAR, tt.[Name])
				  ,det.[Data Event Name]

)

----need to apply those averages found above for those special time frames (1 year prior) to the regular dataset




SELECT tt.[Package Size Name]
	  ,tt.[Material Id]
	  ,tt.[Brand]
	  ,tt.[ProdCategory]
	  ,tt.[SoldToCorporate Entity]
	  ,tt.[SoldToBanner]
	  ,tt.[SoldToRegional]
	  ,tt.[SoldToPartner]
	  ,tt.[Name]
	  --,pya.[Data Event Name]
	  ,'Value' = CASE WHEN pya.[Value] IS NOT NULL --meaning that there is an event to overwrite with PY avg
					THEN pya.[Value]
					ELSE tt.[Value] --the original value for that given set of dimensions
					END  

FROM [dbo].[UC_TAL_Tab4_Transposed] (nolock)  tt
LEFT JOIN PreviousYearAvg pya ON  DATEPART(WEEK, tt.[Name]) = pya.[Week] --joining the known data onto the previous year special average 
							  AND DATEPART(YEAR, tt.[Name]) = pya.[Year] + 1 ---to apply it to the known 'bad' timeframe 
							  AND tt.[Package Size Name]					= pya.[Package Size Name]
							  AND tt.[Material Id]							= pya.[Material Id]
							  AND tt.[Brand]								= pya.[Brand]
							  AND tt.[ProdCategory]							= pya.[ProdCategory]
							  AND tt.[SoldToCorporate Entity]				= pya.[SoldToCorporate Entity]
							  AND tt.[SoldToBanner]							= pya.[SoldToBanner]
							  AND tt.[SoldToRegional]						= pya.[SoldToRegional]
							  AND tt.[SoldToPartner]						= pya.[SoldToPartner]
									
									
 