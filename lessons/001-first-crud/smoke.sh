#!/usr/bin/env sh
set -eu

# Вычисляем абсолютные пути, чтобы smoke работал из любого текущего каталога.
LESSON_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$LESSON_DIR/../.." && pwd)
INFRA_COMPOSE="$ROOT_DIR/infrastructure/postgres/compose.yaml"
LESSON_COMPOSE="$LESSON_DIR/compose.yaml"

# По умолчанию запускаем эталон. Первый аргумент позволяет тем же smoke проверить
# перепечатанный файл, например practice/001-first-crud/main.py.
LESSON_FILE=${1:-lessons/001-first-crud/main.py}

if [ ! -f "$ROOT_DIR/$LESSON_FILE" ]; then
    echo "SMOKE FAILED: файл не найден: $LESSON_FILE" >&2
    exit 1
fi

# Команда идемпотентна: если общий PostgreSQL уже работает, он не пересоздаётся.
# Важно: здесь нет `down`, поэтому база останется работать после smoke.
docker compose -f "$INFRA_COMPOSE" up -d --wait

# Администратор создаёт изолированные database и role. SQL поступает через stdin,
# поэтому его не нужно монтировать в постоянный контейнер PostgreSQL.
docker compose -f "$INFRA_COMPOSE" exec -T postgres \
    psql --username training_admin --dbname postgres \
    < "$LESSON_DIR/bootstrap.sql"

# Удаляем результат предыдущего запуска до проверки выбранного файла. Иначе
# пустой practice/main.py мог бы получить ложный PASS на старых трёх строках.
docker compose -f "$INFRA_COMPOSE" exec -T postgres \
    psql --username training_admin --dbname lesson_001 --set ON_ERROR_STOP=1 \
    --command "DROP TABLE IF EXISTS tasks;"

# Python-контейнер текущего урока тоже поднимается один раз. Его основной процесс
# `sleep infinity` держит готовое окружение для повторных запусков, shell и REPL.
docker compose -f "$LESSON_COMPOSE" up -d app

# Каждый exec запускает новый Python-процесс в уже готовом контейнере. Путь
# задаётся относительно корня курса, который смонтирован как /workspace.
docker compose -f "$LESSON_COMPOSE" exec -T app python "$LESSON_FILE"

# Smoke проверяет один наблюдаемый итог, а не внутреннее устройство функций.
# -A: без выравнивания; -t: без заголовка и служебных строк.
ACTUAL=$(
    docker compose -f "$INFRA_COMPOSE" exec -T postgres \
        psql --username training_admin --dbname lesson_001 --no-align --tuples-only \
        --set ON_ERROR_STOP=1 \
        --command "SELECT count(*) || '|' || count(*) FILTER (WHERE is_done) FROM tasks;"
)

EXPECTED="3|1"

if [ "$ACTUAL" != "$EXPECTED" ]; then
    echo "SMOKE FAILED: ожидалось $EXPECTED, получено $ACTUAL" >&2
    exit 1
fi

echo "SMOKE OK: найдено 3 задачи, из них выполнена 1."
