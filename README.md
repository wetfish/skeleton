# Skeleton

A starter template for building Laravel applications with AI-assisted development and Docker-driven local environments. Clone this repo, rename a few things, and you're ready to start building — no need to install specific versions of PHP, MySQL, or web servers on your local machine.

## What's Included

- **Dockerized development environment** — PHP 8.5-FPM, Nginx, and MySQL 8.0 configured and ready to go. Run `docker compose up -d` and start working.
- **AI development conventions** — a documented set of best practices for building Laravel apps with Claude, refined across multiple production projects.
- **Documentation structure** — numbered markdown files in `docs/` for tracking your database schema, services, routes, frontend patterns, and feature roadmap as the project grows.

## Quick Start

### 1. Clone and rename

```bash
git clone git@github.com:youruser/skeleton.git my-new-project
cd my-new-project
rm -rf .git && git init
```

### 2. Find and replace

Search the entire project for `myproject` and replace it with your project name (lowercase, no spaces). This covers container names, database credentials, the Docker network, and Nginx config.

Files that contain `myproject`:

```text
docker-compose.yml
docker/nginx/default.conf
README.md
```

Also update the host port mappings in `docker-compose.yml` to avoid conflicts with other projects running on your machine. The defaults are:

| Service | Host Port | Container Port |
|---------|-----------|----------------|
| Nginx   | 8080      | 80             |
| MySQL   | 3406      | 3306           |

### 3. Install Laravel

```bash
docker compose up -d
docker compose exec app composer create-project laravel/laravel .
```

### 4. Configure the environment

Update `laravel/.env` to use the Docker container names:

```ini
DB_CONNECTION=mysql
DB_HOST=myproject-db
DB_PORT=3306
DB_DATABASE=myproject
DB_USERNAME=myproject
DB_PASSWORD=secret
SESSION_DRIVER=file
```

### 5. Run migrations

```bash
docker compose exec app php artisan migrate
```

### 6. Build frontend assets

From the host machine:

```bash
cd laravel && npm install && npm run build && cd ..
```

Access the app at `http://localhost:8080`.

## Project Structure

```text
├── Dockerfile              # PHP 8.5-FPM with Laravel extensions and Composer
├── docker-compose.yml      # App, Nginx, and MySQL services
├── docker/
│   ├── nginx/
│   │   └── default.conf    # Nginx server block → laravel/public
│   └── php/
│       └── custom.ini      # PHP overrides (memory_limit, etc.)
├── docs/
│   ├── 01-database-schema.md
│   ├── 02-services-and-commands.md
│   ├── 03-routes-and-controllers.md
│   ├── 04-frontend.md
│   ├── 05-ai-development-notes.md
│   └── 06-planned-features.md
├── laravel/                # Laravel install directory (empty until step 3)
└── README.md               # This file (replace with your project README)
```

## Docker Environment

| Container       | Image                  | Purpose                                      |
|-----------------|------------------------|----------------------------------------------|
| myproject-app   | php:8.5-fpm (custom)   | PHP-FPM with Laravel extensions and Composer  |
| myproject-nginx | nginx:alpine           | Serves `laravel/public/`, proxies PHP to app  |
| myproject-db    | mysql:8.0              | MySQL database                                |

| Config File              | Purpose                                          |
|--------------------------|--------------------------------------------------|
| `docker/nginx/default.conf` | Nginx server block pointing to `laravel/public` |
| `docker/php/custom.ini`     | PHP overrides (memory_limit = 512M)             |

## Artisan Commands

All artisan commands run through the `app` container. The working directory is already set to the Laravel project root:

```bash
docker compose exec app php artisan migrate
docker compose exec app php artisan make:model Example -m
docker compose exec app php artisan tinker
```

On production servers where Laravel runs directly, drop the Docker prefix:

```bash
php artisan migrate
```

## Documentation

The `docs/` directory contains numbered markdown files for project documentation. Start with `05-ai-development-notes.md` which is pre-filled with conventions for AI-assisted development. The rest are blank templates — fill them in as your project takes shape.

## Projects Built With This Template

- **[Andon Alert](https://github.com/youruser/andonalert)** — Factory notification system for reporting issues to supervisors
- **[EzTaxes](https://github.com/youruser/eztaxes)** — S-Corp tax management dashboard with Gusto, Coinbase, and CashApp integrations
