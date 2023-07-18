#!/bin/sh
SCRIPT_PATH=$(dirname "$0")
SCRIPT_PATH=$(cd "$SCRIPT_PATH" && pwd)
MIGRATIONS_PATH="$(cd "$SCRIPT_PATH/../../../astrohub/prisma/migrations" && pwd)"

exit_code=0

SQL_COMMANDS=""

# # Ensure migrations are sorted from earliest to latest
# MIGRATION_FOLDERS=$(find "$MIGRATIONS_PATH" -maxdepth 1 -type d -name '[0-9]*' | sort -n -t _ -k 1)

# # Loop through all the migration folders
# for MIGRATION_FOLDER in $MIGRATION_FOLDERS; do
#     # Get the SQL file in the current migration folder
#     SQL_FILE="$(find "$MIGRATION_FOLDER" -name '*.sql')"
#     # Append the contents of the SQL file to the SQL_COMMANDS variable
#     if [ -n "$SQL_FILE" ]; then
#         SQL_COMMANDS=$(printf "%s%s\n" "$SQL_COMMANDS" "$(cat "$SQL_FILE")")
#     fi
# done
# # Add some dummy values for org, workspace, user as well
# SQL_COMMANDS=$(printf "%s%s" "$SQL_COMMANDS" "$(cat "$SCRIPT_PATH/schema.sql")")

# echo "$SQL_COMMANDS" > "$SCRIPT_PATH/migrations_schema.sql"

echo "start test db container..."
docker run \
--name db-int-test \
-e POSTGRES_DB=core_local_test \
-e POSTGRES_PASSWORD=postgres \
-p 53335:5432 \
-d \
-v ${SCRIPT_PATH}/migrations_schema.sql:/docker-entrypoint-initdb.d/migrations_schema.sql \
ankane/pgvector

cleanup() {
  echo "cleaning up test container..."
  docker rm -fv db-int-test
}
trap cleanup EXIT

echo "Waiting for postgres to startup..."
i=1
while ! docker exec db-int-test bash -c "psql --host=localhost -U postgres" > /dev/null 2>&1; do
  if [ $i -gt 15 ]; then
    echo "dev postgres took too long to startup. Exiting..."
    exit 1
  fi
  i=$(( $i + 1 ))
  sleep 1;
done

echo "installing dependencies..."
make dep

echo "running database integration tests..."
export DATABASE_URL=postgresql://postgres:postgres@localhost:53335/core_local_test?sslmode=disable
export DEBUG_MODE=true
ginkgo run --cover --covermode atomic --coverprofile coverage_db_integration_test.txt -v --junit-report=db-int-test-report.xml --output-dir=test_results clients/database ${ARGS} || exit_code=$?
cat test_results/coverage_db_integration_test.txt | grep -v -f .codecovignore > test_results/coverage_db_integration_test.txt.tmp
mv test_results/coverage_db_integration_test.txt.tmp test_results/coverage_db_integration_test.txt

exit $exit_code
