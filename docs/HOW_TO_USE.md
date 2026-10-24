# Как проходить уроки курса

Здесь описана работа ученика с уже готовым lesson: как запустить эталон,
перепечатать пример, проверить practice-версию и безопасно перейти дальше.

Инструкция для автора нового lesson находится в
[`docs/CREATE_LESSON.md`](CREATE_LESSON.md). Постоянные правила, которым следует
Codex при генерации уроков, записаны в корневом [`AGENTS.md`](../AGENTS.md).

В курсе используются три разных сущности:

- `lessons/NNN-topic` — эталонный учебный lesson;
- `practice/NNN-topic` — твоя вручную перепечатанная версия;
- `smoke.sh` — короткая сквозная проверка выбранного `main.py` на реальном
  PostgreSQL.

## Как пройти готовый урок

### 1. Запусти общую инфраструктуру

Docker Desktop должен быть запущен. Из корня курса выполни:

```bash
docker compose version
docker compose -f infrastructure/postgres/compose.yaml up -d --wait
```

Первая команда подтверждает, что доступен современный Docker Compose. Вторая
идемпотентна: уже работающий PostgreSQL не пересоздаётся.

### 2. Прочитай README урока

Сначала прочитай цель, ментальную модель и вопросы, но не изучай готовый код
построчно. До запуска сформулируй прогноз: какие строки сохранятся, где будет
commit или rollback и какое правило защищает схема.

### 3. Проверь эталонную среду

Например, для урока 002:

```bash
./lessons/002-data-integrity/smoke.sh
```

Это не заменяет практику. Эталонный smoke только подтверждает, что Docker,
Python, Psycopg и PostgreSQL связаны правильно, а ты видишь ожидаемый результат.

### 4. Перепечатай пример по этапам

Создай practice-каталог с тем же суффиксом, что у урока:

```bash
mkdir -p practice/002-data-integrity
```

Руками создай рядом два файла:

```text
practice/002-data-integrity/schema.sql
practice/002-data-integrity/main.py
```

Перепечатывай этапами из README урока. После каждого этапа остановись и объясни:

- какой SQL сейчас отправит Python;
- в какой транзакции он выполнится;
- что увидит другое соединение;
- какое состояние останется после ошибки.

Не копируй `compose.yaml`: один и тот же постоянный контейнер умеет запускать и
эталонный, и practice-файл, потому что весь репозиторий смонтирован в `/workspace`.

### 5. Проверь свою версию

```bash
./lessons/002-data-integrity/smoke.sh practice/002-data-integrity/main.py
```

Smoke сначала убирает старое состояние текущего урока, затем запускает именно
указанный файл и отдельным соединением проверяет зафиксированный результат. PASS
не может быть получен только за счёт данных от прошлого запуска.

### 6. Проведи намеренный эксперимент

Выбери поломку из README, письменно предскажи результат, измени один фрагмент и
запусти пример. После наблюдения верни рабочий вариант и снова получи `SMOKE OK`.

Урок закончен не тогда, когда код просто работает, а когда ты можешь своими
словами назвать его главный инвариант и объяснить восстановление после ошибки.

## Зачем Python-контейнер остаётся запущенным

Smoke один раз поднимает контейнер урока с техническим процессом
`sleep infinity`. Это готовое окружение с нужной версией Python и Psycopg. Каждый
`exec` запускает в нём новый независимый процесс Python:

```bash
docker compose -f lessons/002-data-integrity/compose.yaml exec app \
  python lessons/002-data-integrity/main.py
```

Можно открыть shell или Python REPL:

```bash
docker compose -f lessons/002-data-integrity/compose.yaml exec app sh
docker compose -f lessons/002-data-integrity/compose.yaml exec app python
```

Изменения файлов на macOS сразу видны внутри контейнера. Пересборка нужна только
после изменения `runtime/python/Dockerfile` или версии зависимости.

Practice-файл тоже можно быстро запустить без полного smoke:

```bash
docker compose -f lessons/002-data-integrity/compose.yaml exec app \
  python practice/002-data-integrity/main.py
```

Так удобно повторять небольшие шаги. Но итоговую проверку всё равно выполняй
через `smoke.sh`: прямой запуск не делает независимую проверку состояния БД.

## Как посмотреть данные напрямую

После smoke можно открыть `psql` внутри PostgreSQL-контейнера от имени роли
урока:

```bash
docker compose -f infrastructure/postgres/compose.yaml exec postgres \
  psql -U lesson_002_app -d lesson_002
```

Полезные команды внутри `psql`:

```sql
\dt
\d projects
\d tasks
SELECT * FROM projects;
SELECT * FROM tasks ORDER BY id;
\q
```

`\dt` показывает таблицы, `\d` — структуру и constraints, `\q` закрывает клиент.
Закрытие `psql` не останавливает PostgreSQL: завершается только одна клиентская
сессия.

## Как переходить между уроками

Просто запусти smoke следующего урока. PostgreSQL останавливать не нужно, и
Python-контейнер предыдущего урока может продолжать работать: у уроков разные
Compose-проекты, database и роли.

Если хочешь освободить немного памяти, останови только контейнер прошлого урока:

```bash
docker compose -f lessons/002-data-integrity/compose.yaml down
```

Эта команда не затронет общий PostgreSQL. Проверить его состояние можно так:

```bash
docker compose -f infrastructure/postgres/compose.yaml ps
```

Для обычного перерыва отдельная остановка не обязательна. Если всё же хочешь
остановить сервер, используй:

```bash
docker compose -f infrastructure/postgres/compose.yaml stop
```

Вернуть остановленный сервер можно командой:

```bash
docker compose -f infrastructure/postgres/compose.yaml start
```

Не используй `docker compose -f infrastructure/postgres/compose.yaml down -v`:
флаг `-v` удалит volume со всеми учебными database.

## Что присылать Codex, если возникла ошибка

Обычно достаточно написать:

```text
Я запускаю:
./lessons/002-data-integrity/smoke.sh practice/002-data-integrity/main.py

Получаю:
<вставь полный вывод ошибки>

Объясни причину, но пока не меняй файлы.
```

Полный вывод полезнее последней строки: в нём видны команда, класс ошибки
Psycopg, SQLSTATE, имя constraint и момент, на котором остановилась транзакция.

## Короткий рабочий цикл

```text
выбрать готовый lesson
        ↓
прочитать README и сделать прогноз
        ↓
запустить эталонный smoke
        ↓
перепечатать schema.sql и main.py по этапам
        ↓
запустить smoke для practice-файла
        ↓
намеренно сломать, объяснить, восстановить
        ↓
после понимания перейти к следующему lesson
```
