#!/usr/bin/env sh
set -eu

LESSON_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$LESSON_DIR/../.." && pwd)
INFRA_COMPOSE="$ROOT_DIR/infrastructure/postgres/compose.yaml"
LESSON_COMPOSE="$LESSON_DIR/compose.yaml"

# Можно проверить эталон либо собственную перепечатанную версию. В practice-папке
# рядом с main.py обязательно должен находиться перепечатанный schema.sql.
LESSON_FILE=${1:-lessons/002-data-integrity/main.py}

if [ ! -f "$ROOT_DIR/$LESSON_FILE" ]; then
    echo "SMOKE FAILED: файл не найден: $LESSON_FILE" >&2
    exit 1
fi

docker compose -f "$INFRA_COMPOSE" up -d --wait

docker compose -f "$INFRA_COMPOSE" exec -T postgres \
    psql --username training_admin --dbname postgres \
    < "$LESSON_DIR/bootstrap.sql"

# Удаляем результат прошлого запуска до проверки выбранного файла. Без этого
# пустой practice/main.py мог бы ложно получить PASS на старых данных.
docker compose -f "$INFRA_COMPOSE" exec -T postgres \
    psql --username training_admin --dbname lesson_002 --set ON_ERROR_STOP=1 \
    --command "DROP TABLE IF EXISTS tasks; DROP TABLE IF EXISTS projects;"

# Контейнер остаётся работать после smoke. Повторные запуски используют exec.
docker compose -f "$LESSON_COMPOSE" up -d app
docker compose -f "$LESSON_COMPOSE" exec -T app python "$LESSON_FILE"

# Отдельное соединение видит только COMMIT-результат. Одновременно проверяем:
# один project пережил RESTRICT, есть две tasks, одна открыта, сирот нет, а шесть
# именованных constraints действительно созданы выбранным schema.sql.
ACTUAL=$(
    docker compose -f "$INFRA_COMPOSE" exec -T postgres \
        psql --username training_admin --dbname lesson_002 \
        --set ON_ERROR_STOP=1 --no-align --tuples-only \
        --command "
            SELECT
                (SELECT count(*) FROM projects) || '|' ||
                (SELECT count(*) FROM tasks) || '|' ||
                (SELECT count(*) FROM tasks WHERE completed_at IS NULL) || '|' ||
                (
                    SELECT count(*)
                    FROM tasks
                    LEFT JOIN projects ON projects.id = tasks.project_id
                    WHERE projects.id IS NULL
                ) || '|' ||
                (
                    SELECT count(DISTINCT conname)
                    FROM pg_constraint
                    WHERE conrelid IN ('projects'::regclass, 'tasks'::regclass)
                      AND conname IN (
                          'projects_code_not_blank',
                          'projects_name_not_blank',
                          'projects_code_unique',
                          'tasks_title_not_blank',
                          'tasks_priority_range',
                          'tasks_project_fk'
                      )
                );
        "
)

EXPECTED="1|2|1|0|6"

if [ "$ACTUAL" != "$EXPECTED" ]; then
    echo "SMOKE FAILED: ожидалось $EXPECTED, получено $ACTUAL" >&2
    exit 1
fi

echo "SMOKE OK: 1 проект, 2 задачи, 1 открытая, 0 сирот, 6 constraints."
