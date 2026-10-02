## Database Connections

This project uses {{DB_LABEL}}.

When connecting to the PostgreSQL container from the host machine (e.g., DBeaver, pg_dump, or psql), use host `127.0.0.1` and the host port from the root `.env`. Docker exposes the database over TCP only.

From within the Docker network (e.g., in `laravel/.env`), use the Docker Compose service name `db` as the host and port `5432`.

To open a psql shell inside the container:

```bash
docker compose exec db psql -U {{PROJECT_NAME}} -d {{PROJECT_NAME}}
```

## PostgreSQL Conventions

Text comparison is case-sensitive in PostgreSQL. Use `ILIKE` (or `whereLike(..., caseSensitive: false)`) for case-insensitive searches rather than assuming MySQL's default collation behavior.

Create any required extensions (e.g., `postgis`, `pg_trgm`, `fuzzystrmatch`) in a migration with `DB::statement('CREATE EXTENSION IF NOT EXISTS ...')`, even if the Docker image already provides them, so that production databases end up with the same extensions. Creating an extension usually requires a superuser. The Docker database user is a superuser; on production servers, an administrator may need to create extensions once before migrations run.