-- Только администратор учебного кластера создаёт database и login-role урока.
\set ON_ERROR_STOP on

-- CREATE ROLE не имеет IF NOT EXISTS, поэтому psql сначала получает текст
-- команды из SELECT, а затем выполняет его через \gexec.
SELECT format(
    'CREATE ROLE %I LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS',
    'lesson_002_app',
    'lesson_002_password'
)
WHERE NOT EXISTS (
    SELECT 1
    FROM pg_roles
    WHERE rolname = 'lesson_002_app'
)
\gexec

-- Возвращает и пароль, и безопасные флаги. Это делает bootstrap повторяемым даже
-- после ручного эксперимента с ALTER ROLE.
ALTER ROLE lesson_002_app WITH
    LOGIN
    PASSWORD 'lesson_002_password'
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    NOREPLICATION
    NOBYPASSRLS;

-- CREATE DATABASE нельзя выполнять внутри transaction block. Каждая команда,
-- сгенерированная \gexec, выполняется psql отдельно в режиме autocommit.
SELECT format(
    'CREATE DATABASE %I OWNER %I',
    'lesson_002',
    'lesson_002_app'
)
WHERE NOT EXISTS (
    SELECT 1
    FROM pg_database
    WHERE datname = 'lesson_002'
)
\gexec

ALTER DATABASE lesson_002 OWNER TO lesson_002_app;
REVOKE CONNECT ON DATABASE lesson_002 FROM PUBLIC;
GRANT CONNECT ON DATABASE lesson_002 TO lesson_002_app;
