# Урок 001. Первое соединение и CRUD

## Цель

Увидеть весь путь одной операции:

```text
main.py -> Psycopg -> TCP/Docker network -> PostgreSQL -> database -> table
```

После урока нужно различать:

- server — постоянно работающий процесс PostgreSQL;
- database — изолированное пространство `lesson_001` внутри сервера;
- session/connection — один разговор Python-процесса с сервером;
- transaction — группа изменений, которая фиксируется целиком или откатывается;
- cursor — объект, который отправляет SQL и получает строки результата.

## Что делает пример

1. `bootstrap.sql` один раз создаёт database и login-role урока.
2. `schema.sql` пересоздаёт таблицу `tasks` с типами и ограничениями.
3. `main.py` открывает соединение и неявно начинает транзакцию.
4. Три основные задачи и одна временная создаются параметризованными `INSERT`.
5. `RETURNING` сразу отдаёт сгенерированные `id`.
6. `DELETE` удаляет отдельную временную задачу и возвращает её title.
7. `UPDATE` завершает одну задачу.
8. `SELECT` читает итог в заданном порядке.
9. Выход из `with psycopg.connect(...)` делает `COMMIT` и закрывает соединение.

## Порядок практики

Сначала запусти эталонный smoke из корня курса:

```bash
./lessons/001-first-crud/smoke.sh
```

Затем создай в корне курса папку `practice/001-first-crud` и руками перепечатай в
неё `schema.sql` и `main.py`. Проверить именно свой файл можно тем же smoke:

```bash
./lessons/001-first-crud/smoke.sh practice/001-first-crud/main.py
```

`compose.yaml` можно пока оставить инфраструктурным шаблоном: в нём важнее
прочитать комментарии и понять hostname.

После первого smoke Python-контейнер остаётся запущенным. Повторить пример можно
без пересборки и пересоздания контейнера:

```bash
docker compose -f lessons/001-first-crud/compose.yaml exec app \
  python lessons/001-first-crud/main.py
```

Compose сам соберёт образ при первом `up`. Явная пересборка нужна только после
изменения `runtime/python/Dockerfile` или версии Psycopg:

```bash
docker compose -f lessons/001-first-crud/compose.yaml build app
docker compose -f lessons/001-first-crud/compose.yaml up -d app
```

Открыть shell или интерактивный Python в том же окружении:

```bash
docker compose -f lessons/001-first-crud/compose.yaml exec app sh
docker compose -f lessons/001-first-crud/compose.yaml exec app python
```

Остановить текущий Python-контейнер:

```bash
docker compose -f lessons/001-first-crud/compose.yaml down
```

Эта команда не затронет PostgreSQL: он принадлежит Compose-проекту
`bd-training-infra`. Пример сам пересоздаёт свою таблицу, поэтому каждый запуск
даёт три строки.

## На что посмотреть в коде

### Почему не `localhost`

Внутри Python-контейнера `localhost` означает сам Python-контейнер. PostgreSQL
находится в другом контейнере, поэтому адрес — сетевой alias
`bd-training-postgres`, порт — внутренний `5432`.

Порт `55432` нужен только клиентам на macOS:

```text
postgresql://lesson_001_app:lesson_001_password@127.0.0.1:55432/lesson_001
```

### Почему параметры — не f-string

Неправильно:

```python
cursor.execute(f"INSERT INTO tasks (title) VALUES ('{title}')")
```

Кавычка внутри значения ломает SQL, а строка из внешнего ввода может превратиться
в SQL injection. Правильно передавать значение отдельно:

```python
cursor.execute(
    "INSERT INTO tasks (title) VALUES (%s)",
    (title,),
)
```

`%s` здесь — placeholder драйвера, а не форматирование Python.

## Намеренная поломка

После успешного запуска замени приоритет одной задачи на `9` и снова запусти код.

Предскажи до запуска:

1. Какое ограничение сработает?
2. Будут ли сохранены предыдущие `INSERT` из этой транзакции?
3. Что останется в таблице, если до ошибочного запуска там были данные?

Подсказка: `schema.sql` и все изменения выполняются внутри одной транзакции, а
исключение заставляет context manager сделать `ROLLBACK`.

После наблюдения верни приоритет в диапазон `1..5` и запусти smoke.

## Вопросы для самопроверки

1. Почему закрытие cursor не делает commit?
2. Где физически остаются строки после удаления Python-контейнера?
3. Чем `NOT NULL` отличается от `CHECK (btrim(title) <> '')`?
4. Почему `RETURNING id` лучше, чем предположить следующий id в Python?
5. Почему роль приложения не должна быть superuser?

## Что используют в рабочих проектах

- **Psycopg 3** — синхронный драйвер и ручной SQL, как в уроке;
- **asyncpg** — async-драйвер для asyncio-приложений;
- **SQLAlchemy Core** — построитель SQL и абстракция соединений;
- **SQLAlchemy ORM** — отображение строк в объекты и unit of work;
- **Alembic** — версионированные миграции схемы;
- **psycopg_pool** — пул ограниченного числа соединений.

Пока они не нужны: сначала важно видеть SQL, транзакцию и реальные данные.
