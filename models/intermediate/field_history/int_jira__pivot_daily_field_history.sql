{{
    config(
        materialized='incremental',
        partition_by = {'field': 'valid_starting_on', 'data_type': 'date'},
        unique_key='issue_day_id'
    )
}}

-- latest value per issue field (already limited included fields to sprint, status, and var(issue_field_history_columns))
with daily_field_history as (

    select * 
    from {{ ref('int_jira__daily_field_history') }}

    {% if is_incremental() %}
    where valid_starting_on >= (select max(valid_starting_on) from {{ this }} )
    {% endif %}
),

pivot_out as (

    -- pivot out default columns (status and sprint) and others specified in the var(issue_field_history_columns)
    -- only days on which a field value was actively changed will have a non-null value. the nulls will need to 
    -- be backfilled in the final jira__daily_issue_field_history model
    select 
        valid_starting_on, 
        issue_id,
        max(case when lower(field_name) = 'status' then field_value end) as status,
        max(case when lower(field_name) = 'sprint' then field_value end) as sprint

        {% for col in var('issue_field_history_columns', []) -%}
        ,
            max(case when lower(field_name) = '{{ col | lower }}' then field_value end) as {{ col | replace(' ', '_') | lower }}
        {% endfor -%}

    from daily_field_history

    group by 1,2
),

final as (

    select 
        *,
        {{ dbt_utils.surrogate_key(['valid_starting_on','issue_id']) }} as issue_day_id,
        lead(valid_starting_on) over(partition by issue_id order by valid_starting_on asc) as valid_ending_on

    from pivot_out
)

select * from final 