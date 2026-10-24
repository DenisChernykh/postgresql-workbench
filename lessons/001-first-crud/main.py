"""Урок 001: соединение, транзакция и первый CRUD без ORM."""

import os
from pathlib import Path

import psycopg


# Конфигурацию подключения передаёт Docker Compose. Код не должен зашивать адрес
# сервера: внутри Docker это bd-training-postgres, а с macOS был бы 127.0.0.1.
DATABASE_URL = os.environ["DATABASE_URL"]


def read_schema() -> str:
    """Читает SQL относительно самого main.py, а не текущего каталога shell."""

    schema_path = Path(__file__).with_name("schema.sql")
    return schema_path.read_text(encoding="utf-8")


def main() -> None:
    # connect() открывает отдельную сессию PostgreSQL.
    #
    # Контекстный менеджер соединения задаёт важную транзакционную границу:
    # - нормальный выход из `with` -> COMMIT;
    # - исключение внутри `with`  -> ROLLBACK;
    # - после выхода соединение закрывается в обоих случаях.
    with psycopg.connect(DATABASE_URL) as connection:
        # Cursor отправляет SQL в рамках сессии connection и читает результат.
        # Его закрытие НЕ означает commit: транзакцией управляет connection выше.
        with connection.cursor() as cursor:
            cursor.execute(read_schema())

            insert_sql = """
                INSERT INTO tasks (title, priority)
                VALUES (%s, %s)
                RETURNING id, title
            """

            source_tasks = [
                ("Разобраться с соединением", 3),
                ("Понять параметризованный SQL", 5),
                ("Прочитать книгу O'Reilly про PostgreSQL", 4),
            ]

            created_ids: list[int] = []

            for title, priority in source_tasks:
                # Значения передаются ВТОРЫМ аргументом execute(). Драйвер отправляет
                # SQL и параметры раздельно. Кавычка в O'Reilly остаётся данными и
                # не может случайно изменить структуру запроса.
                cursor.execute(insert_sql, (title, priority))

                # RETURNING позволяет получить созданную строку без второго SELECT.
                task_id, created_title = cursor.fetchone()
                created_ids.append(task_id)
                print(f"Создана задача #{task_id}: {created_title}")

            # DELETE — четвёртая операция CRUD. Создадим отдельную временную
            # строку и сразу удалим именно её по id. RETURNING доказывает, какую
            # строку удалила БД, не добавляя отдельный SELECT перед удалением.
            cursor.execute(insert_sql, ("Временная задача для DELETE", 1))
            temporary_id, _ = cursor.fetchone()

            cursor.execute(
                """
                DELETE FROM tasks
                WHERE id = %s
                RETURNING title
                """,
                (temporary_id,),
            )
            (deleted_title,) = cursor.fetchone()
            print(f"Удалена временная задача #{temporary_id}: {deleted_title}")

            # UPDATE тоже параметризован. Здесь завершаем ровно первую созданную
            # задачу; id получен от самой БД, а не угадан кодом.
            cursor.execute(
                """
                UPDATE tasks
                SET is_done = TRUE
                WHERE id = %s
                """,
                (created_ids[0],),
            )

            cursor.execute(
                """
                SELECT id, title, priority, is_done
                FROM tasks
                ORDER BY priority DESC, id ASC
                """
            )

            print("\nСостояние задач внутри транзакции:")
            for task_id, title, priority, is_done in cursor.fetchall():
                mark = "x" if is_done else " "
                print(f"[{mark}] #{task_id}, приоритет {priority}: {title}")

    # К этой строке контекст connection уже выполнил COMMIT и закрыл соединение.
    print("\nТранзакция зафиксирована, соединение закрыто.")


if __name__ == "__main__":
    main()
