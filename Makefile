.PHONY: help setup run test freshness docs clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

setup: ## Install dbt and dependencies
	pip install dbt-snowflake
	cd dbt_project && dbt deps

debug: ## Test Snowflake connection
	cd dbt_project && dbt debug

run: ## Run all dbt models
	cd dbt_project && dbt run

test: ## Run all dbt tests
	cd dbt_project && dbt test

freshness: ## Check source data freshness
	cd dbt_project && dbt source freshness

docs: ## Generate and serve dbt documentation
	cd dbt_project && dbt docs generate && dbt docs serve

clean: ## Remove dbt build artifacts
	rm -rf dbt_project/target dbt_project/dbt_packages dbt_project/logs

full: run test freshness ## Run models, tests, and freshness check

docker-up: ## Start PostgreSQL container
	cd docker && docker-compose up -d

docker-down: ## Stop PostgreSQL container
	cd docker && docker-compose down

docker-verify: ## Verify data in PostgreSQL
	docker exec hevo_postgres psql -U hevo_user -d hevo_db -c "SELECT 'raw_customers' as tbl, count(*) FROM raw_customers UNION ALL SELECT 'raw_orders', count(*) FROM raw_orders UNION ALL SELECT 'raw_payments', count(*) FROM raw_payments;"
