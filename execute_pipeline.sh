#!/bin/sh


echo "=== Configuring ELT pipeline for starlink prediction ===\n\n"
cp -f default_meltano.yml elt_pipeline/meltano.yml

# Install python dependencies
echo "=== Installing python dependencies ===\n"
cd elt_pipeline
rm -f plugins/loaders/target-postgres--meltanolabs.lock plugins/utilities/dbt-postgres--dbt-labs.lock starlink_prediction.csv

python3 -m pip install --no-cache-dir -r requirements.txt

# Add extractor tap-spacexapi 
echo "=== Adding tap-spacexapi extractor ===\n"
meltano add --from-ref tap-spacexapi.yml extractor tap-spacexapi

# Add loader target-postgres to meltano
# First run local docker container with postgres

echo "=== Start docker container with postgres in local ===\n"
# Stop and remove container if already exists
docker stop meltano_postgres || true && docker rm -f meltano_postgres || true

docker-compose up -d

echo "=== Adding target-postgres loader ===\n"
meltano add loader target-postgres --variant=meltanolabs
meltano config target-postgres set user meltano
meltano config target-postgres set password password
meltano config target-postgres set database postgres
meltano config target-postgres set add_record_metadata True
meltano config target-postgres set host localhost  

echo "=== Adding dbt-postgres utility ===\n"
meltano add utility dbt-postgres
meltano invoke dbt-postgres:initialize
meltano config dbt-postgres set host localhost
meltano config dbt-postgres set port 5432
meltano config dbt-postgres set user meltano
meltano config dbt-postgres set password password
meltano config dbt-postgres set dbname postgres
meltano config dbt-postgres set schema analytics

echo "=== Fix dbt-postgres bug ===\n"
python3 fix_clean-targets.py

echo "=== Add meltano jobs for ELT pipeline ===\n"
meltano job add extract_and_load_data --tasks "tap-spacexapi target-postgres"

meltano job add transform_data --tasks "dbt-postgres:run"

meltano job add dbt_tests --tasks "dbt-postgres:test"

meltano job add generate_dbt_docs --tasks "dbt-postgres:docs-generate"

echo "\n\n"
echo "==========================================="
echo "Running the ELT pipeline, predicting starlink launches!..."
meltano run extract_and_load_data transform_data dbt_tests generate_dbt_docs
python3 ../starlink_prediction/prediction.py


echo "Pipeline successfully completed!\n"
echo "==========================================="

echo "Opening the DBT documentation in 10 seconds..."
sleep 10

meltano invoke dbt-postgres:docs-serve