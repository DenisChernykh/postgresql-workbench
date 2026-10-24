# Постоянный PostgreSQL для всех уроков

## Что здесь постоянно

Compose-проект `bd-training-infra` владеет ровно одним сервером PostgreSQL,
именованным volume `bd-training-postgres-17-data` и сетью `bd-training-net`.
Уроки подключаются к этой сети как к внешней, но не владеют ей и сервером.

Это даёт разные жизненные циклы:

- `lesson up/run/down` управляет только Python-контейнером урока;
- `infrastructure stop/start` управляет процессом PostgreSQL;
- удаление lesson database сбрасывает только один урок;
- volume сохраняет весь кластер даже после пересоздания контейнера сервера.

## Команды

```bash
# Запустить один раз; --wait дождётся healthcheck.
docker compose -f infrastructure/postgres/compose.yaml up -d --wait

# Посмотреть состояние и логи.
docker compose -f infrastructure/postgres/compose.yaml ps
docker compose -f infrastructure/postgres/compose.yaml logs postgres

# Подключиться администратором из контейнера (только для учебной инфраструктуры).
docker compose -f infrastructure/postgres/compose.yaml exec postgres \
  psql -U training_admin -d postgres

# Подключиться клиентом с macOS, если psql установлен локально.
psql 'postgresql://training_admin:training_admin_password@127.0.0.1:55432/postgres'
```

Полная остановка между уроками не нужна. Политика `unless-stopped` также поднимет
контейнер после перезапуска Docker Desktop, если он не был остановлен вручную.

## Осторожно со сбросом

```bash
# Сначала остановить Python-контейнер активного урока: он подключён к общей сети.
docker compose -f lessons/001-first-crud/compose.yaml down

# Контейнер PostgreSQL и сеть удалятся, данные останутся в named volume.
docker compose -f infrastructure/postgres/compose.yaml down

# Эта команда удалит ВСЕ учебные базы без восстановления из backup.
docker compose -f infrastructure/postgres/compose.yaml down -v
```

Если пропустить первый шаг, `infrastructure down` остановит PostgreSQL, но не
сможет удалить `bd-training-net` из-за активного endpoint Python-контейнера. Для
обычной паузы проще и безопаснее использовать `infrastructure stop`.

Переменные `POSTGRES_*` применяются official image только при инициализации пустого
каталога данных. Изменение пароля в `compose.yaml` не меняет уже созданную роль в
существующем volume — это позже станет отдельным упражнением про роли и ownership.

Пароли здесь намеренно простые, потому что сервер доступен только локально и в
отдельной учебной Docker-сети. Такие значения нельзя переносить в рабочую среду.

## Какие уроки нельзя запускать на общем сервере

Общий кластер подходит для SQL, моделирования, Python, транзакций, блокировок,
индексов, прав внутри database, диагностики и logical backup/restore.

Уроки по `pg_hba.conf`, WAL/PITR, replication/failover, `ALTER SYSTEM`, crash
recovery и major upgrade будут поднимать собственный одноразовый PostgreSQL с
отдельным volume. Такие упражнения намеренно меняют или ломают весь кластер и не
должны затрагивать уже пройденные уроки.
