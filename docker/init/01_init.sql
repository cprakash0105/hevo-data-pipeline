-- Create tables
CREATE TABLE raw_customers (
    id INTEGER PRIMARY KEY,
    first_name VARCHAR(50),
    last_name VARCHAR(50)
);

CREATE TABLE raw_orders (
    id INTEGER PRIMARY KEY,
    user_id INTEGER,
    order_date DATE,
    status VARCHAR(50)
);

CREATE TABLE raw_payments (
    id INTEGER PRIMARY KEY,
    order_id INTEGER,
    payment_method VARCHAR(50),
    amount INTEGER
);

-- Load CSV data
COPY raw_customers(id, first_name, last_name)
FROM '/tmp/data/raw_customers.csv' DELIMITER ',' CSV HEADER;

COPY raw_orders(id, user_id, order_date, status)
FROM '/tmp/data/raw_orders.csv' DELIMITER ',' CSV HEADER;

COPY raw_payments(id, order_id, payment_method, amount)
FROM '/tmp/data/raw_payments.csv' DELIMITER ',' CSV HEADER;

-- Create publication for logical replication (required by Hevo)
CREATE PUBLICATION hevo_publication FOR ALL TABLES;
