# Процесс разработки

Лабораторная работа № 3 выполнена для проекта «Генератор сложных паролей». Функции реализованы в отдельных ветках, проверены через Pull Requests и объединены с `main`.

## Начальная структура

В `main` создан коммит [`feat: add basic project structure`](https://github.com/Tralalaca/password-generator-srs/commit/e786001945bf1e87cca9ef6710be101f294dc1e4) с файлами `index.html`, `style.css`, `script.js` и `.gitignore`. HTML сразу описывал элементы генератора; стили и скрипт на этом этапе были пустыми.

## Ветки, задачи и ревью

1. Ветка `codex/generate-password` → [PR #39](https://github.com/Tralalaca/password-generator-srs/pull/39) → задачи [#19–#25](https://github.com/Tralalaca/password-generator-srs/issues/19). Добавлены интерфейс, проверка ввода, четыре набора символов, исключение похожих символов и генерация через `crypto.getRandomValues`. После просмотра diff оставлены комментарии по равномерному выбору и покрытию наборов, затем обсуждения закрыты и PR объединён обычным merge.
2. Ветка `codex/password-feedback` → [PR #40](https://github.com/Tralalaca/password-generator-srs/pull/40) → задачи [#26–#28](https://github.com/Tralalaca/password-generator-srs/issues/26). Добавлены копирование, обработка его ошибки и оценка стойкости. После self-review и разрешения комментариев применён **Squash and merge**.
3. Ветка `codex/persist-settings-and-tests` → [PR #41](https://github.com/Tralalaca/password-generator-srs/pull/41) → задачи [#29–#35](https://github.com/Tralalaca/password-generator-srs/issues/29) и [#37](https://github.com/Tralalaca/password-generator-srs/issues/37). Добавлены сохранение только настроек, восстановление допустимых значений, обработка недоступного хранилища и восемь автоматических тестов. После self-review, браузерной проверки и разрешения комментариев PR объединён обычным merge.

Каждый PR содержит описание и строки `Closes #...`. Связанные задачи закрылись при объединении в `main`. Для всех трёх PR использована метка «улучшение».

## Автоматическая проверка

[`.github/workflows/ci.yml`](https://github.com/Tralalaca/password-generator-srs/blob/main/.github/workflows/ci.yml) запускается при `push` в `main` и при PR к `main`. Job `validate` проверяет наличие HTML, CSS и JavaScript, синтаксис скрипта и запускает `node --test tests/generator.test.js`. [Успешный запуск CI](https://github.com/Tralalaca/password-generator-srs/actions/runs/45338325587) подтвердил прохождение всех шагов.

## Релиз

Тег [`v1.0.0`](https://github.com/Tralalaca/password-generator-srs/releases/tag/v1.0.0) отмечает первую стабильную версию. Релиз содержит описание реализованных функций и известных ограничений. Номер версии следует формату MAJOR.MINOR.PATCH. Публикация релиза выполняется после повторного запуска проверок на помеченном тегом коммите.

## Приёмка и ограничения

Локально прошли восемь тестов Node.js. В Headless Chrome 158 на `localhost` проверены генерация, копирование, пароль длиной 128 символов, отсутствие горизонтальной прокрутки при ширине 360 пикселей и восстановление настроек без восстановления пароля. Проверка двух последних стабильных версий Chrome, Edge и Firefox на Windows/macOS, а также измерение на устройстве с 2 ГБ ОЗУ остаются в [задаче #38](https://github.com/Tralalaca/password-generator-srs/issues/38).

