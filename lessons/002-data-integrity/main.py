"""Урок 002: целостность данных и связи между таблицами."""

import os
from pathlib import Path

import psycopg


DATABASE_URL = os.environ["DATABASE_URL"]


def read_schema() -> str:
    """Находит schema.sql рядом с эталонным или перепечатанным main.py."""

    return Path(__file__).with_name("schema.sql").read_text(encoding="utf-8")


def demonstrate_violation(
    label: str,
    sql: str,
    params: tuple[object, ...],
    expected_error: type[psycopg.Error],
    diagnostic_field: str,
    expected_diagnostic: str,
    show_aborted_state: bool = False,
) -> None:
    """Запускает одну ошибочную команду в отдельной транзакции.

    После серверной ошибки транзакция PostgreSQL считается прерванной. Поэтому
    каждая демонстрация открывает отдельное соединение и явно делает ROLLBACK
    перед следующим примером.
    """

    with psycopg.connect(DATABASE_URL) as connection:
        with connection.cursor() as cursor:
            try:
                cursor.execute(sql, params)

            except expected_error as error:
                # PostgreSQL передаёт структурированную диагностику. Для
                # именованных UNIQUE/CHECK/FK это constraint_name, для NOT NULL
                # в PostgreSQL 17 — column_name.
                actual_diagnostic = getattr(error.diag, diagnostic_field)

                if actual_diagnostic != expected_diagnostic:
                    raise RuntimeError(
                        f"Сработало не то ограничение: {actual_diagnostic!r}"
                    ) from error

                print(
                    f"Ожидаемо отклонено [{label}]: "
                    f"{type(error).__name__}, SQLSTATE={error.sqlstate}, "
                    f"{diagnostic_field}={actual_diagnostic}"
                )

                if show_aborted_state:
                    # Python уже поймал первую ошибку, но PostgreSQL всё ещё
                    # считает транзакцию прерванной. До rollback даже SELECT 1
                    # будет отклонён с SQLSTATE 25P02.
                    try:
                        cursor.execute("SELECT 1")
                    except psycopg.errors.InFailedSqlTransaction as aborted:
                        print(
                            "До ROLLBACK следующий SQL отклонён: "
                            f"{type(aborted).__name__}, SQLSTATE={aborted.sqlstate}"
                        )
                    else:
                        raise RuntimeError(
                            "Прерванная транзакция неожиданно выполнила SELECT"
                        )

                connection.rollback()

                if show_aborted_state:
                    # Проверяем recovery на том же connection: после rollback
                    # новый SELECT должен успешно начать новую транзакцию.
                    cursor.execute("SELECT 1")
                    if cursor.fetchone() != (1,):
                        raise RuntimeError("SELECT после ROLLBACK вернул не 1")
                    print("После ROLLBACK тот же connection выполнил SELECT 1.")

                print("ROLLBACK завершил ошибочную транзакцию.\n")

            else:
                # Защита учебного сценария: если constraint удалили, потенциально
                # плохая строка всё равно не должна попасть в итоговое состояние.
                connection.rollback()
                raise RuntimeError(f"Constraint не сработал: {label}")


def create_valid_data() -> int:
    """Пересоздаёт схему и фиксирует один проект с двумя задачами."""

    with psycopg.connect(DATABASE_URL) as connection:
        with connection.cursor() as cursor:
            cursor.execute(read_schema())

            cursor.execute(
                """
                INSERT INTO projects (code, name)
                VALUES (%s, %s)
                RETURNING id
                """,
                ("DB-COURSE", "Практика PostgreSQL"),
            )
            (project_id,) = cursor.fetchone()

            # Первая задача остаётся открытой: completed_at = NULL.
            # Вторая завершена серверным CURRENT_TIMESTAMP.
            cursor.execute(
                """
                INSERT INTO tasks (project_id, title, priority, completed_at)
                VALUES
                    (%s, %s, %s, NULL),
                    (%s, %s, %s, CURRENT_TIMESTAMP)
                """,
                (
                    project_id,
                    "Перепечатать schema.sql",
                    3,
                    project_id,
                    "Разобрать ограничения",
                    5,
                ),
            )

    # После выхода connection сделал COMMIT. Ошибочные попытки ниже увидят эти
    # данные из других соединений и не смогут откатить эту транзакцию.
    return project_id


def print_valid_state() -> None:
    """Читает только состояние, которое прошло все ограничения."""

    with psycopg.connect(DATABASE_URL) as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT
                    title,
                    priority,
                    completed_at IS NULL AS is_open
                FROM tasks
                ORDER BY priority DESC
                """
            )

            print("\nВ базе остались только валидные строки:")
            for title, priority, is_open in cursor.fetchall():
                state = "открыта" if is_open else "завершена"
                print(f"{priority} | {state} | {title}")


def main() -> None:
    project_id = create_valid_data()
    print("Валидные проект и две задачи зафиксированы.\n")

    demonstrate_violation(
        "NOT NULL: title отсутствует",
        "INSERT INTO tasks (project_id, title, priority) VALUES (%s, %s, %s)",
        (project_id, None, 3),
        psycopg.errors.NotNullViolation,
        "column_name",
        "title",
        show_aborted_state=True,
    )

    demonstrate_violation(
        "CHECK: title состоит из пробелов",
        "INSERT INTO tasks (project_id, title, priority) VALUES (%s, %s, %s)",
        (project_id, "   ", 3),
        psycopg.errors.CheckViolation,
        "constraint_name",
        "tasks_title_not_blank",
    )

    demonstrate_violation(
        "CHECK: priority вне диапазона",
        "INSERT INTO tasks (project_id, title, priority) VALUES (%s, %s, %s)",
        (project_id, "Слишком важная задача", 9),
        psycopg.errors.CheckViolation,
        "constraint_name",
        "tasks_priority_range",
    )

    demonstrate_violation(
        "UNIQUE: код проекта повторяется",
        "INSERT INTO projects (code, name) VALUES (%s, %s)",
        ("DB-COURSE", "Дубликат"),
        psycopg.errors.UniqueViolation,
        "constraint_name",
        "projects_code_unique",
    )

    demonstrate_violation(
        "FOREIGN KEY: project отсутствует",
        "INSERT INTO tasks (project_id, title, priority) VALUES (%s, %s, %s)",
        (project_id + 10_000, "Задача без проекта", 2),
        psycopg.errors.ForeignKeyViolation,
        "constraint_name",
        "tasks_project_fk",
    )

    demonstrate_violation(
        "ON DELETE RESTRICT: у project есть tasks",
        "DELETE FROM projects WHERE id = %s",
        (project_id,),
        psycopg.errors.ForeignKeyViolation,
        "constraint_name",
        "tasks_project_fk",
    )

    print_valid_state()
    print("\nВсе ошибочные транзакции откатились отдельно.")


if __name__ == "__main__":
    main()
