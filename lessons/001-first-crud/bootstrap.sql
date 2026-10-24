-- Этот файл выполняет администратор учебного кластера, а не приложение.
-- psql завершится сразу, если любая команда вернула ошибку.
\set ON_ERROR_STOP on

-- CREATE ROLE не поддерживает IF NOT EXISTS. Запрос генерирует команду только
-- тогда, когда роли ещё нет, а \gexec выполняет получившийся текст как SQL.
SELECT format(
    'CREATE ROLE %I LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS',
    'lesson_001_app',
    'lesson_001_password'
)
WHERE NOT EXISTS (
    SELECT 1
    FROM pg_roles
    WHERE rolname = 'lesson_001_app'
)
\gexec

-- Повторный bootstrap восстанавливает не только пароль, но и границу прав. Если
-- во время эксперимента роли случайно дали административный флаг, следующий
-- запуск снова сделает её обычной прикладной login-role.
ALTER ROLE lesson_001_app WITH
    LOGIN
    PASSWORD 'lesson_001_password'
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    NOREPLICATION
    NOBYPASSRLS;

-- Database — более сильная граница между уроками, чем разные таблицы в одной
-- схеме. CREATE DATABASE нельзя выполнять внутри обычного transaction block,
-- поэтому psql снова генерирует и отдельно выполняет команду через \gexec.
SELECT format(
    'CREATE DATABASE %I OWNER %I',
    'lesson_001',
    'lesson_001_app'
)
WHERE NOT EXISTS (
    SELECT 1
    FROM pg_database
    WHERE datname = 'lesson_001'
)
\gexec

ALTER DATABASE lesson_001 OWNER TO lesson_001_app;
REVOKE CONNECT ON DATABASE lesson_001 FROM PUBLIC;
GRANT CONNECT ON DATABASE lesson_001 TO lesson_001_app;
