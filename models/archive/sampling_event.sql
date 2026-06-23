WITH
  RankedData AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY event_name ORDER BY RAND()) AS rn
  FROM
    `chef-master-8f916.analytics_448269098.events_202604*`)
SELECT
  *
FROM
  RankedData
WHERE
  rn <= 3
  and event_name in ('claim_all_mission_rewards','claim_last_welcome_quest_reward','claim_mission_reward','claim_season_reward','claim_welcome_quest_reward','currency_earned','currency_spent','daily_reward_claimed','iap_purchase','object_level_purchase','staff_level_purchase')
