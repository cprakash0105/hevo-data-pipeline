-- Test: customer_lifetime_value should never be negative
select
    customer_id,
    customer_lifetime_value
from {{ ref('customers') }}
where customer_lifetime_value < 0
