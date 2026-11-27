-- Данные для проверки схемы. Выполнять после schema.sql в новой БД.
PRAGMA foreign_keys = ON;
BEGIN TRANSACTION;

INSERT INTO character_types (code, display_name) VALUES
    ('lowercase', 'Строчные буквы'),
    ('uppercase', 'Заглавные буквы'),
    ('digits', 'Цифры'),
    ('symbols', 'Специальные символы');

-- Первая строка соответствует настройкам по умолчанию в script.js.
INSERT INTO generator_configs (name, password_length, exclude_similar) VALUES
    ('По умолчанию', 16, 0),
    ('Без похожих символов', 24, 1);

INSERT INTO config_character_types (config_id, type_id)
SELECT c.config_id, t.type_id
FROM generator_configs AS c
CROSS JOIN character_types AS t
WHERE c.name = 'По умолчанию'
   OR (c.name = 'Без похожих символов'
       AND t.code IN ('lowercase', 'uppercase', 'digits'));

COMMIT;
