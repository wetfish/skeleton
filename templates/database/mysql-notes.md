## Database Connections

This project uses MySQL 8.0.

When connecting to the MySQL container from the host machine (e.g., DBeaver, mysqldump, or other database tools), use `127.0.0.1` instead of `localhost`. MySQL interprets `localhost` as a Unix socket connection, but Docker exposes the database over TCP only. Using `localhost` will result in "connection refused" errors.

From within the Docker network (e.g., in `laravel/.env`), use the Docker Compose service name `db` as the host.

To open a MySQL shell inside the container:

```bash
docker compose exec db mysql -u {{PROJECT_NAME}} -p {{PROJECT_NAME}}
```