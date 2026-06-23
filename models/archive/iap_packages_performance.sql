-- breakdown of total purchase by country and product id
select
  geo.country,
  case
        when app_info.version = '0.1.10' then '0.1.9(10)'
        else app_info.version
      end as version,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_name') AS product_name,
  sum((SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'price_dollars')) as total_purchase
FROM `chef-master-8f916.analytics_448269098.events_*`
where 1=1
  and (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'price_dollars') > 0
  and event_name = 'iap_purchase'
group by all