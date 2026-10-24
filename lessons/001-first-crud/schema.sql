-- Первый урок должен повторяться с одинаковым результатом, поэтому перед
-- примером мы осознанно удаляем только его собственную таблицу.
DROP TABLE IF EXISTS tasks;

CREATE TABLE tasks (
    -- Identity генерирует значение на стороне БД. BIGINT оставляет большой запас,
    -- а PRIMARY KEY одновременно запрещает NULL и гарантирует уникальность.
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    -- TEXT подходит для строки переменной длины. CHECK запрещает пустую строку
    -- и строку только из пробелов — одного NOT NULL для этого недостаточно.
    title TEXT NOT NULL CHECK (btrim(title) <> ''),

    -- SMALLINT хранит целое число. Ограничение фиксирует допустимое бизнес-правило
    -- рядом с данными, поэтому его не сможет обойти другой клиент.
    priority SMALLINT NOT NULL DEFAULT 1
        CHECK (priority BETWEEN 1 AND 5),

    is_done BOOLEAN NOT NULL DEFAULT FALSE,

    -- TIMESTAMPTZ хранит момент времени. DEFAULT вычисляется сервером при INSERT.
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

