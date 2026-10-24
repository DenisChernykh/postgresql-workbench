-- Сначала удаляется дочерняя таблица: её FOREIGN KEY зависит от projects.
-- CASCADE здесь не нужен — мы явно контролируем порядок удаления объектов.
DROP TABLE IF EXISTS tasks;
DROP TABLE IF EXISTS projects;

CREATE TABLE projects (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    -- NOT NULL запрещает отсутствие значения, но само по себе разрешает ''.
    code TEXT NOT NULL,
    name TEXT NOT NULL,

    -- Явные имена constraints попадут в диагностику ошибки PostgreSQL.
    CONSTRAINT projects_code_not_blank CHECK (btrim(code) <> ''),
    CONSTRAINT projects_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT projects_code_unique UNIQUE (code)
);

CREATE TABLE tasks (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    project_id BIGINT NOT NULL,
    title TEXT NOT NULL,
    priority SMALLINT NOT NULL DEFAULT 1,

    -- NULL здесь несёт смысл: задача ещё не завершена. Это не ошибка данных.
    completed_at TIMESTAMPTZ,

    -- CHECK и NOT NULL дополняют друг друга. Результат CHECK для NULL равен
    -- UNKNOWN, а не FALSE, поэтому без NOT NULL значение NULL прошло бы проверку.
    CONSTRAINT tasks_title_not_blank CHECK (btrim(title) <> ''),
    CONSTRAINT tasks_priority_range CHECK (priority BETWEEN 1 AND 5),

    -- FOREIGN KEY не позволяет ссылаться на отсутствующий project.
    -- RESTRICT также запрещает удалить project, пока у него существуют tasks.
    CONSTRAINT tasks_project_fk
        FOREIGN KEY (project_id)
        REFERENCES projects (id)
        ON DELETE RESTRICT
);

