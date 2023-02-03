WITH 

Fmctable AS ( SELECT * FROM "lla_cco_int_ana_prod"."cwp_fmc_churn_prod" WHERE month = date(dt))

,Grossadsusers as (select first_sales_chnl_bom, first_sales_chnl_eom, e_fixed_mrc, fixedaccount, fixedmainmovement,b_numrgus,e_numrgus, month from Fmctable where waterfall_flag = 'Gross Adds' and fixedmainmovement is not null)

,Saleschannel_SO AS( SELECT DISTINCT account_id,
  first_value(date_trunc('Month', (DATE(order_start_date)))) over (partition by account_id  order by completed_date)  as First_Sales_Month,
  first_value(date_trunc('Month', (DATE(order_start_date)))) over (partition by account_id  order by completed_date desc)  as Last_Sales_Month,
  first_value(channel_type) over (partition by account_id  order by completed_date) as First_Sales_Channel,
  first_value(channel_type) over (partition by account_id  order by completed_date desc) as Last_Sales_Channel
FROM "db-stage-dev"."so_hdr_cwp" 
WHERE  org_cntry = '714' AND network_type NOT IN ('LTE','MOBILE')
        AND order_status = 'COMPLETED'
        AND account_type = 'R'
        AND order_type = 'INSTALLATION'
        AND cease_reason_group IS NULL)

, ovalusers as (select distinct sales_month, month, CASE WHEN sales_channel in ('DEALER','RETAIL') THEN 'RETAIL'
 WHEN sales_channel in ('ECOMMERCE', 'VIRTUAL SALES') THEN 'DIGITAL'
 WHEN sales_channel in ('D2D') THEN sales_channel
 WHEN sales_channel in ('TELESALES' ) THEN 'TELESALES_INBOUND'
 WHEN sales_channel in ('CUSTOMER CARE', 'TECH SUPPORT', 'CALL CENTER', 'RETENTION DEPARMENT', 'ORDER MANAGEMENT', 'PROCESSING', 'DISPATCH') THEN 'TELESALES_OUTBOUND'
 END AS Sales_channel_adj,e_fixed_mrc, 
 CASE WHEN b_numrgus is null THEN 0
    else (cast(b_numrgus AS double)) end as b_numrgus_adj,
    CASE WHEN e_numrgus is null THEN 0
    else (cast(e_numrgus AS double)) end as e_numrgus_adj,
  fixedaccount,fixedmainmovement from
  (select e_fixed_mrc, fixedaccount, fixedmainmovement,b_numrgus,e_numrgus, month,
  case when fixedmainmovement = '4.New Customer' then first_sales_Month
  when fixedmainmovement = '5.Come Back to Life' then last_sales_Month  end as sales_Month, 
  case when fixedmainmovement = '4.New Customer' then first_sales_channel
   when fixedmainmovement = '5.Come Back to Life' then last_sales_channel
  end as sales_channel
  from grossadsusers left join saleschannel_so on cast(fixedaccount as bigint) = account_id ))

,Rollingwindow as ( select g.month as grossads_month, f.fixedaccount, g.e_fixed_mrc, f.month as fmc_month, f.fixedmainmovement, finalaccount  from grossadsusers g left join fmctable f on g.fixedaccount = f.fixedaccount where  
(date_diff('month',date(g.month), date(f.month)) < 6) and f.month >= g.month )

,Avg_appear as (select *, row_number() IGNORE NULLS over (partition by fixedaccount  order by month)  as avg_appear from fmctable 
having e_fixed_mrc > 0 
)
, Avg_mrc as (select fixedaccount, sum(e_fixed_mrc) as avg_mrc_month from avg_appear where avg_appear = 1 group by fixedaccount )

select distinct a.month as Date, 
case 
when first_sales_chnl_bom is not null then first_sales_chnl_bom 
when first_sales_chnl_bom is null then first_sales_chnl_eom 
end as Sales_Channel, 
sum(e_numrgus_adj - b_numrgus_adj) as Rgus,  count(distinct a.fixedaccount) as Num_Users,
round(avg(cast(avg_mrc_month as double)),0) as Avg_mrc_month,
Round((sum(e_numrgus_adj - b_numrgus_adj)/count(distinct a.fixedaccount)),2) as AVG_RGUs_User
from "lla_cco_int_ana_prod"."cwp_fmc_churn_prod" a 
left join avg_mrc b on a.fixedaccount = b.fixedaccount 
left join ovalusers c on a.fixedaccount = c.fixedaccount
where year(a.Month) = 2022 
and waterfall_flag = 'Gross Adds'

group by 1,2 order by 2,1
