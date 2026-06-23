{# Extracts the value of a single action_type from a Meta actions ARRAY<STRUCT<action_type, value>>. #}
{% macro meta_get_action(actions_col, action_type) %}
  (
    select sum(a.value)
    from unnest({{ actions_col }}) as a
    where a.action_type = '{{ action_type }}'
  )
{% endmacro %}
