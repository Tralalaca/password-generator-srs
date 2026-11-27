-- Лабораторная работа № 4: реляционная модель настроек генератора паролей.
-- Пароли и данные буфера обмена в этой схеме не хранятся.
-- В каждом новом соединении SQLite необходимо включать внешние ключи.
PRAGMA foreign_keys = ON;

CREATE TABLE generator_configs (
    config_id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE CHECK (length(trim(name)) > 0),
    password_length INTEGER NOT NULL DEFAULT 16
        CHECK (password_length BETWEEN 6 AND 128),
    exclude_similar INTEGER NOT NULL DEFAULT 0
        CHECK (exclude_similar IN (0, 1)),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE character_types (
    type_id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT NOT NULL UNIQUE
        CHECK (code IN ('lowercase', 'uppercase', 'digits', 'symbols')),
    display_name TEXT NOT NULL UNIQUE CHECK (length(trim(display_name)) > 0)
);

-- Одна конфигурация выбирает несколько типов; один тип входит в разные
-- конфигурации. Составной PK запрещает повторное включение одного типа.
CREATE TABLE config_character_types (
    config_id INTEGER NOT NULL,
    type_id INTEGER NOT NULL,
    PRIMARY KEY (config_id, type_id),
    FOREIGN KEY (config_id) REFERENCES generator_configs(config_id)
        ON DELETE CASCADE,
    FOREIGN KEY (type_id) REFERENCES character_types(type_id)
        ON DELETE RESTRICT
) WITHOUT ROWID;

-- UNIQUE(name) и UNIQUE(code) уже создают индексы автоматически.
-- Эти индексы ускоряют сортировку конфигураций и обратный поиск по типу.
CREATE INDEX idx_generator_configs_created_at
    ON generator_configs(created_at);
CREATE INDEX idx_config_character_types_type_id
    ON config_character_types(type_id);
