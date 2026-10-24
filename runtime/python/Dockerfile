FROM python:3.13.14-slim-bookworm

# Не создаём __pycache__ в примонтированном уроке и сразу показываем print в логах.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Единственная внешняя Python-зависимость на старте курса — драйвер PostgreSQL.
# Extra `binary` добавляет готовую libpq-сборку: не нужен компилятор в учебном образе.
RUN python -m pip install --no-cache-dir "psycopg[binary]==3.3.4"

WORKDIR /lesson
CMD ["python", "main.py"]

