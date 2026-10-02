#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Skeleton — Laravel Project Scaffolding Tool
# https://github.com/wetfish/skeleton
# =============================================================================

# Resolve the real path of this script (follows symlinks)
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
TEMPLATES_DIR="$SCRIPT_DIR/templates"
LICENSES_DIR="$TEMPLATES_DIR/licenses"
DATABASE_DIR="$TEMPLATES_DIR/database"
VERSION_FILE="$SCRIPT_DIR/VERSION"

# Read version
if [[ -f "$VERSION_FILE" ]]; then
    SKELETON_VERSION="$(cat "$VERSION_FILE")"
else
    SKELETON_VERSION="unknown"
fi

# Safe files that are expected in a target directory
SAFE_FILES=(".git" ".gitignore" "LICENSE" "README.md" ".env" ".env.example")

# Files that skeleton copies — used for conflict detection
SKELETON_FILES=("Dockerfile" "docker-compose.yml" "docker" "docs")

# Skeleton repo marker files — used for self-detection
SKELETON_MARKERS=("install.sh" "skeleton.sh" "templates")

# Port ranges
NGINX_PORT_DEFAULT=8080
NGINX_PORT_MIN=8080
NGINX_PORT_MAX=8480

# Database engine settings — populated by configure_database()
DB_ENGINE=""
DB_LABEL=""
DB_IMAGE=""
DB_CONNECTION=""
DB_INTERNAL_PORT=""
DB_PORT_DEFAULT=""
DB_PORT_MIN=""
DB_PORT_MAX=""
DB_PHP_EXTENSION=""
DB_SYSTEM_PACKAGES=""
DB_FRAGMENT=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No color

# =============================================================================
# Utility Functions
# =============================================================================

print_header() {
    local line1="Skeleton v${SKELETON_VERSION}"
    local line2="Laravel Project Scaffolding Tool"
    local width=40

    # Pad each line to center it within the box
    local pad1=$(( (width - ${#line1}) / 2 ))
    local pad2=$(( (width - ${#line2}) / 2 ))

    echo ""
    echo -e "${CYAN}${BOLD}╔$(printf '═%.0s' $(seq 1 $width))╗${NC}"
    printf "${CYAN}${BOLD}║%*s%-*s║${NC}\n" "$pad1" "" "$(( width - pad1 ))" "$line1"
    printf "${CYAN}${BOLD}║%*s%-*s║${NC}\n" "$pad2" "" "$(( width - pad2 ))" "$line2"
    echo -e "${CYAN}${BOLD}╚$(printf '═%.0s' $(seq 1 $width))╝${NC}"
    echo ""
}

show_help() {
    print_header
    cat <<EOF
Usage: skeleton [OPTIONS]

Scaffolds a new Laravel project with a Dockerized development environment
and AI development conventions.

Options:
  --help        Show this help message
  --version     Show version number

Interactive Setup:
  Running 'skeleton' with no options starts the interactive setup wizard:

  1. Project directory    — use current directory or specify a path
  2. Conflict check       — warns if target has files that would be overwritten
  3. Project name         — lowercase name for containers, database, and network
  4. Database engine      — MySQL 8.0, PostgreSQL 17, or PostgreSQL 17 + PostGIS
  5. Nginx host port      — default (8080), random (8080-8480), or custom
  6. Database host port   — default, random, or custom (MySQL 3306, PostgreSQL 5432)
  7. README               — preserves existing or generates a new one
  8. License              — AGPL-3.0, GPL-3.0, MIT, BSD-3-Clause, custom, or none
  9. Laravel installation — optionally installs Laravel and configures the database

Installation:
  git clone https://github.com/wetfish/skeleton.git
  cd skeleton
  ./install.sh

  This creates a symlink in ~/.local/bin so 'skeleton' is available everywhere.
  Update anytime with 'cd skeleton && git pull'.

Uninstallation:
  ./install.sh --uninstall

Full documentation: https://github.com/wetfish/skeleton
EOF
    exit 0
}

show_version() {
    echo "skeleton v${SKELETON_VERSION}"
    exit 0
}

generate_password() {
    local length="${1:-32}"
    head -c 512 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c "$length"
}

random_port() {
    local min="$1"
    local max="$2"
    echo $(( RANDOM % (max - min + 1) + min ))
}

is_skeleton_repo() {
    local dir="$1"
    local real_dir
    real_dir="$(readlink -f "$dir")"

    # Check if target resolves to the same directory as the script
    if [[ "$real_dir" == "$SCRIPT_DIR" ]]; then
        return 0
    fi

    # Check for skeleton marker files
    local marker_count=0
    for marker in "${SKELETON_MARKERS[@]}"; do
        if [[ -e "$dir/$marker" ]]; then
            ((marker_count++))
        fi
    done

    # If all markers are present, this is almost certainly the skeleton repo
    if [[ "$marker_count" -eq "${#SKELETON_MARKERS[@]}" ]]; then
        return 0
    fi

    return 1
}

validate_project_name() {
    local name="$1"

    if [[ -z "$name" ]]; then
        echo "Project name cannot be empty."
        return 1
    fi

    if [[ ${#name} -lt 2 || ${#name} -gt 50 ]]; then
        echo "Project name must be between 2 and 50 characters."
        return 1
    fi

    if [[ ! "$name" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ && ${#name} -gt 1 ]]; then
        echo "Project name must be lowercase alphanumeric with hyphens, and cannot start or end with a hyphen."
        return 1
    fi

    if [[ ${#name} -eq 1 && ! "$name" =~ ^[a-z0-9]$ ]]; then
        echo "Single character project names must be alphanumeric."
        return 1
    fi

    return 0
}

is_safe_file() {
    local filename="$1"
    for safe in "${SAFE_FILES[@]}"; do
        if [[ "$filename" == "$safe" ]]; then
            return 0
        fi
    done
    return 1
}

is_conflict_file() {
    local filename="$1"
    for conflict in "${SKELETON_FILES[@]}"; do
        if [[ "$filename" == "$conflict" ]]; then
            return 0
        fi
    done
    return 1
}

is_yes() {
    local input="${1,,}"  # lowercase
    [[ "$input" == "y" || "$input" == "yes" ]]
}

# =============================================================================
# Conflict Check
# =============================================================================

check_conflicts() {
    local dir="$1"
    local conflicts=()
    local other_files=()

    # List all files and directories in target (excluding . and ..)
    if [[ -d "$dir" ]]; then
        while IFS= read -r entry; do
            local basename
            basename="$(basename "$entry")"

            if is_safe_file "$basename"; then
                continue
            elif is_conflict_file "$basename"; then
                conflicts+=("$basename")
            else
                other_files+=("$basename")
            fi
        done < <(find "$dir" -maxdepth 1 -mindepth 1 2>/dev/null)
    fi

    if [[ ${#conflicts[@]} -gt 0 ]]; then
        echo ""
        echo -e "${YELLOW}${BOLD}Warning:${NC} The following files/directories will be overwritten:"
        for f in "${conflicts[@]}"; do
            echo -e "  ${RED}• $f${NC}"
        done
        echo ""
        read -rp "Continue and overwrite these files? (y/n): " confirm
        if ! is_yes "$confirm"; then
            echo "Setup cancelled."
            exit 0
        fi
    elif [[ ${#other_files[@]} -gt 0 ]]; then
        echo ""
        echo -e "${YELLOW}Note:${NC} Directory is not empty, but no conflicts detected."
        echo "  Other files found: ${other_files[*]}"
        echo ""
        read -rp "Continue? (y/n): " confirm
        if ! is_yes "$confirm"; then
            echo "Setup cancelled."
            exit 0
        fi
    fi
}

# =============================================================================
# Database Engine
# =============================================================================

configure_database() {
    DB_ENGINE="$1"

    case "$DB_ENGINE" in
        mysql)
            DB_LABEL="MySQL 8.0"
            DB_IMAGE="mysql:8.0"
            DB_CONNECTION="mysql"
            DB_INTERNAL_PORT=3306
            DB_PORT_DEFAULT=3306
            DB_PORT_MIN=3306
            DB_PORT_MAX=3706
            DB_PHP_EXTENSION="pdo_mysql"
            DB_SYSTEM_PACKAGES=""
            DB_FRAGMENT="mysql"
            ;;
        pgsql)
            DB_LABEL="PostgreSQL 17"
            DB_IMAGE="postgres:17"
            DB_CONNECTION="pgsql"
            DB_INTERNAL_PORT=5432
            DB_PORT_DEFAULT=5432
            DB_PORT_MIN=5432
            DB_PORT_MAX=5832
            DB_PHP_EXTENSION="pdo_pgsql"
            DB_SYSTEM_PACKAGES="libpq-dev"
            DB_FRAGMENT="pgsql"
            ;;
        postgis)
            DB_LABEL="PostgreSQL 17 + PostGIS 3.5"
            DB_IMAGE="postgis/postgis:17-3.5"
            DB_CONNECTION="pgsql"
            DB_INTERNAL_PORT=5432
            DB_PORT_DEFAULT=5432
            DB_PORT_MIN=5432
            DB_PORT_MAX=5832
            DB_PHP_EXTENSION="pdo_pgsql"
            DB_SYSTEM_PACKAGES="libpq-dev"
            DB_FRAGMENT="pgsql"
            ;;
        *)
            echo -e "${RED}Unknown database engine: $DB_ENGINE${NC}" >&2
            exit 1
            ;;
    esac
}

select_database() {
    echo ""
    echo -e "${BOLD}Step 3: Database Engine${NC}"
    echo ""
    echo "  1) MySQL 8.0"
    echo "  2) PostgreSQL 17"
    echo "  3) PostgreSQL 17 + PostGIS 3.5 (geographic queries)"
    echo ""

    local db_choice
    while true; do
        read -rp "Choose [1/2/3]: " db_choice
        case "$db_choice" in
            1) configure_database "mysql"; break ;;
            2) configure_database "pgsql"; break ;;
            3) configure_database "postgis"; break ;;
            *) echo -e "${RED}Please enter 1, 2, or 3.${NC}" ;;
        esac
    done

    echo -e "Database: ${GREEN}$DB_LABEL${NC}"
}

# Replace the line containing a {{PLACEHOLDER}} with the contents of a fragment file.
# Each fragment line is indented to match the placeholder, so fragments can be
# written at column 0 (e.g. "db:" lands under "services:" in docker-compose.yml).
insert_fragment() {
    local file="$1"
    local placeholder="$2"
    local fragment="$3"
    local tmp

    if [[ ! -f "$fragment" ]]; then
        echo -e "${RED}Template fragment not found: $fragment${NC}" >&2
        exit 1
    fi

    tmp="$(mktemp)"

    awk -v ph="$placeholder" -v frag="$fragment" '
        index($0, ph) {
            match($0, /^[ \t]*/)
            indent = substr($0, 1, RLENGTH)
            while ((getline line < frag) > 0) {
                if (line == "") print ""
                else print indent line
            }
            close(frag)
            next
        }
        { print }
    ' "$file" > "$tmp"

    # Write back with cat to preserve the original file permissions
    cat "$tmp" > "$file"
    rm -f "$tmp"
}

# Replace single-value {{PLACEHOLDERS}} with the configured values
substitute_placeholders() {
    local file="$1"
    local project_name="$2"

    sed -i \
        -e "s|{{DB_IMAGE}}|${DB_IMAGE}|g" \
        -e "s|{{DB_LABEL}}|${DB_LABEL}|g" \
        -e "s|{{DB_PHP_EXTENSION}}|${DB_PHP_EXTENSION}|g" \
        -e "s|{{PROJECT_NAME}}|${project_name}|g" \
        "$file"
}

# Check whether the database container is accepting TCP connections.
# Checking over TCP (not the socket) skips the temporary server that the
# MySQL and PostgreSQL images run during first-time initialization.
db_is_ready() {
    local target_dir="$1"
    local project_name="$2"
    local db_password="$3"

    if [[ "$DB_CONNECTION" == "pgsql" ]]; then
        (cd "$target_dir" && docker compose exec -T db \
            pg_isready -h 127.0.0.1 -U "$project_name" -d "$project_name" -q)
    else
        (cd "$target_dir" && docker compose exec -T db \
            mysqladmin ping -h 127.0.0.1 -u"$project_name" -p"$db_password" --silent)
    fi
}

# =============================================================================
# Port Selection
# =============================================================================

prompt_port() {
    local label="$1"
    local default="$2"
    local min="$3"
    local max="$4"

    echo "" >&2
    echo -e "${BOLD}$label host port:${NC}" >&2
    echo "  1) Default ($default)" >&2
    echo "  2) Random ($min-$max)" >&2
    echo "  3) Enter a specific port" >&2
    echo "" >&2

    while true; do
        read -rp "Choose [1/2/3]: " choice
        case "$choice" in
            1)
                echo "$default"
                return
                ;;
            2)
                local port
                port="$(random_port "$min" "$max")"
                echo -e "${GREEN}Selected random port: $port${NC}" >&2
                echo "$port"
                return
                ;;
            3)
                read -rp "Enter port number: " custom_port
                if [[ "$custom_port" =~ ^[0-9]+$ && "$custom_port" -ge 1024 && "$custom_port" -le 65535 ]]; then
                    echo "$custom_port"
                    return
                else
                    echo -e "${RED}Invalid port. Must be a number between 1024 and 65535.${NC}" >&2
                fi
                ;;
            *)
                echo -e "${RED}Please enter 1, 2, or 3.${NC}" >&2
                ;;
        esac
    done
}

# =============================================================================
# Template Copy & Substitution
# =============================================================================

copy_templates() {
    local target_dir="$1"
    local project_name="$2"

    echo ""
    echo -e "${CYAN}Copying template files...${NC}"

    # Copy everything from templates/ preserving directory structure
    # (templates/database/ holds engine fragments and is never copied directly)
    cp -r "$TEMPLATES_DIR/Dockerfile" "$target_dir/"
    cp -r "$TEMPLATES_DIR/docker-compose.yml" "$target_dir/"
    cp -r "$TEMPLATES_DIR/docker" "$target_dir/"
    cp -r "$TEMPLATES_DIR/docs" "$target_dir/"

    echo -e "${CYAN}Configuring ${DB_LABEL}...${NC}"

    # Insert the engine-specific compose service and documentation notes
    insert_fragment "$target_dir/docker-compose.yml" "{{DB_SERVICE}}" "$DATABASE_DIR/${DB_FRAGMENT}.yml"
    insert_fragment "$target_dir/docs/05-ai-development-notes.md" "{{DB_CONNECTION_NOTES}}" "$DATABASE_DIR/${DB_FRAGMENT}-notes.md"

    # System packages needed to compile the PHP database driver (none for MySQL)
    if [[ -n "$DB_SYSTEM_PACKAGES" ]]; then
        sed -i "s|{{DB_SYSTEM_PACKAGES}}|${DB_SYSTEM_PACKAGES}|" "$target_dir/Dockerfile"
    else
        sed -i '/{{DB_SYSTEM_PACKAGES}}/d' "$target_dir/Dockerfile"
    fi

    substitute_placeholders "$target_dir/Dockerfile" "$project_name"
    substitute_placeholders "$target_dir/docker-compose.yml" "$project_name"
    substitute_placeholders "$target_dir/docs/05-ai-development-notes.md" "$project_name"

    # Only copy .gitignore if one doesn't already exist
    if [[ ! -f "$target_dir/.gitignore" ]]; then
        cp "$TEMPLATES_DIR/.gitignore" "$target_dir/"
    fi
}

generate_env() {
    local target_dir="$1"
    local project_name="$2"
    local nginx_port="$3"
    local db_port="$4"
    local db_password="$5"

    echo -e "${CYAN}Generating .env configuration...${NC}"

    cat > "$target_dir/.env" <<EOF
# Project configuration (generated by skeleton)
APP_NAME=${project_name}
NGINX_PORT=${nginx_port}
DB_CONNECTION=${DB_CONNECTION}
DB_PORT=${db_port}
DB_DATABASE=${project_name}
DB_USERNAME=${project_name}
DB_PASSWORD=${db_password}
EOF
}

generate_env_example() {
    local target_dir="$1"

    cat > "$target_dir/.env.example" <<EOF
# Project configuration — copy to .env and fill in your values
APP_NAME=skeleton
NGINX_PORT=8080
DB_CONNECTION=${DB_CONNECTION}
DB_PORT=${DB_PORT_DEFAULT}
DB_DATABASE=skeleton
DB_USERNAME=skeleton
DB_PASSWORD=changeme
EOF
}

# =============================================================================
# README Generation
# =============================================================================

generate_readme() {
    local target_dir="$1"
    local project_name="$2"
    local description="$3"
    local nginx_port="$4"
    local db_port="$5"

    cat > "$target_dir/README.md" <<EOF
# ${project_name}

${description}

## Quick Start (Docker — Development)

Start the Docker environment:

\`\`\`bash
docker compose up -d
\`\`\`

Run migrations and seed default data:

\`\`\`bash
docker compose exec app php artisan migrate --seed
\`\`\`

Build frontend assets (run from host machine):

\`\`\`bash
cd laravel && npm install && npm run build && cd ..
\`\`\`

Access the app at \`http://localhost:${nginx_port}\`.

## Docker Environment

| Container | Image | Purpose | Ports |
|-----------|-------|---------|-------|
| ${project_name}-app | php:8.5-fpm (custom) | PHP-FPM with Laravel extensions and Composer | 9000 (internal) |
| ${project_name}-nginx | nginx:alpine | Serves \`laravel/public/\`, proxies PHP to app | ${nginx_port} → 80 |
| ${project_name}-db | ${DB_IMAGE} | ${DB_LABEL} database | ${db_port} → ${DB_INTERNAL_PORT} |

## Environment Configuration

Docker Compose reads from the root \`.env\` file for container names, ports, and database credentials. This file is gitignored and generated during project setup. See \`.env.example\` for the expected variables.

Laravel's own \`laravel/.env\` handles application-level config (app key, database connection, session driver, etc.) and is also gitignored.

From the host machine, the database (${DB_LABEL}) is accessible at \`127.0.0.1:${db_port}\`.

## Artisan Commands

All artisan commands run through the \`app\` container:

\`\`\`bash
docker compose exec app php artisan migrate
docker compose exec app php artisan make:model Example -m
docker compose exec app php artisan tinker
\`\`\`

On production servers, drop the Docker prefix:

\`\`\`bash
php artisan migrate
\`\`\`

## Documentation

Detailed technical documentation lives in the [\`docs/\`](docs/) directory:

- [Database Schema](docs/01-database-schema.md) — table definitions, model relationships, cascade behavior
- [Services & Commands](docs/02-services-and-commands.md) — service classes, artisan commands, business logic
- [Routes & Controllers](docs/03-routes-and-controllers.md) — full route listing, controller responsibilities, request flows
- [Frontend](docs/04-frontend.md) — Tailwind/Vite setup, Blade templates, view structure, UI conventions
- [AI Development Notes](docs/05-ai-development-notes.md) — conventions for AI-assisted development with Claude
- [Planned Features](docs/06-planned-features.md) — future feature roadmap
EOF
}

# =============================================================================
# License Generation
# =============================================================================

get_available_licenses() {
    # List license template files from the licenses directory
    if [[ -d "$LICENSES_DIR" ]]; then
        find "$LICENSES_DIR" -maxdepth 1 -type f -printf '%f\n' | sort
    fi
}

generate_license() {
    local target_dir="$1"
    local license_file="$2"
    local copyright_holder="$3"
    local year
    year="$(date +%Y)"

    if [[ "$license_file" == "custom" ]]; then
        local custom_path
        read -rp "Enter path to your license file: " custom_path
        if [[ -f "$custom_path" ]]; then
            cp "$custom_path" "$target_dir/LICENSE"
        else
            echo -e "${RED}File not found: $custom_path${NC}"
            echo "Skipping license generation."
            return 1
        fi
    else
        local template="$LICENSES_DIR/$license_file"
        if [[ ! -f "$template" ]]; then
            echo -e "${RED}License template not found: $template${NC}"
            return 1
        fi
        sed -e "s/{{YEAR}}/$year/g" -e "s/{{COPYRIGHT_HOLDER}}/$copyright_holder/g" \
            "$template" > "$target_dir/LICENSE"
    fi
}

# =============================================================================
# Laravel Installation
# =============================================================================

install_laravel() {
    local target_dir="$1"
    local project_name="$2"
    local db_password="$3"
    local nginx_port="$4"

    echo ""
    echo -e "${CYAN}Creating laravel directory...${NC}"
    mkdir -p "$target_dir/laravel"

    echo ""
    echo -e "${CYAN}Starting Docker environment...${NC}"
    (cd "$target_dir" && docker compose up -d)

    echo ""
    echo -e "${CYAN}Waiting for containers to start...${NC}"
    sleep 5

    echo ""
    echo -e "${CYAN}Installing Laravel...${NC}"
    (cd "$target_dir" && docker compose exec app composer create-project laravel/laravel .)

    # Verify .env exists (composer create-project copies .env.example to .env)
    if [[ ! -f "$target_dir/laravel/.env" ]]; then
        if [[ -f "$target_dir/laravel/.env.example" ]]; then
            cp "$target_dir/laravel/.env.example" "$target_dir/laravel/.env"
        else
            echo -e "${RED}Warning: No .env or .env.example found after Laravel install.${NC}"
            return 1
        fi
    fi

    # Generate application key
    echo ""
    echo -e "${CYAN}Generating application key...${NC}"
    (cd "$target_dir" && docker compose exec app php artisan key:generate)

    # Update .env with Docker database configuration
    echo ""
    echo -e "${CYAN}Configuring database connection...${NC}"
    local env_file="$target_dir/laravel/.env"

    # Strip any existing DB_, SESSION_DRIVER, and APP_URL lines
    sed -i '/^DB_CONNECTION=/d' "$env_file"
    sed -i '/^DB_HOST=/d' "$env_file"
    sed -i '/^DB_PORT=/d' "$env_file"
    sed -i '/^DB_DATABASE=/d' "$env_file"
    sed -i '/^DB_USERNAME=/d' "$env_file"
    sed -i '/^DB_PASSWORD=/d' "$env_file"
    sed -i '/^SESSION_DRIVER=/d' "$env_file"
    sed -i 's|^APP_URL=.*|APP_URL=http://localhost:'"${nginx_port}"'|' "$env_file"

    # Append Docker-specific database configuration
    cat >> "$env_file" <<ENVBLOCK

# Docker database configuration (generated by skeleton)
DB_CONNECTION=${DB_CONNECTION}
DB_HOST=db
DB_PORT=${DB_INTERNAL_PORT}
DB_DATABASE=${project_name}
DB_USERNAME=${project_name}
DB_PASSWORD=${db_password}
SESSION_DRIVER=file
ENVBLOCK

    # Wait for the database to be ready before migrating
    echo ""
    echo -e "${CYAN}Waiting for ${DB_LABEL} to be ready...${NC}"
    local retries=30
    while ! db_is_ready "$target_dir" "$project_name" "$db_password" 2>/dev/null; do
        retries=$((retries - 1))
        if [[ "$retries" -le 0 ]]; then
            echo -e "${RED}${DB_LABEL} did not become ready in time. You may need to run migrations manually.${NC}"
            return 1
        fi
        sleep 2
    done

    # Run migrations
    echo ""
    echo -e "${CYAN}Running database migrations...${NC}"
    (cd "$target_dir" && docker compose exec app php artisan migrate)

    echo ""
    echo -e "${GREEN}Laravel installed and configured successfully.${NC}"
}

generate_deferred_env() {
    local target_dir="$1"
    local project_name="$2"
    local db_password="$3"
    local nginx_port="$4"

    mkdir -p "$target_dir/laravel"

    cat > "$target_dir/laravel/.env" <<EOF
# =============================================================================
# Generated by skeleton
#
# WARNING: This file contains Docker-specific configuration only.
# After installing Laravel, merge these values into the .env file that
# Laravel generates. Do not replace Laravel's .env entirely — it contains
# additional settings (APP_KEY, etc.) that are required.
# =============================================================================

APP_URL=http://localhost:${nginx_port}

DB_CONNECTION=${DB_CONNECTION}
DB_HOST=db
DB_PORT=${DB_INTERNAL_PORT}
DB_DATABASE=${project_name}
DB_USERNAME=${project_name}
DB_PASSWORD=${db_password}

SESSION_DRIVER=file
EOF
}

# =============================================================================
# Summary
# =============================================================================

print_summary() {
    local project_name="$1"
    local target_dir="$2"
    local nginx_port="$3"
    local db_port="$4"
    local db_password="$5"
    local laravel_installed="$6"
    local readme_status="$7"
    local license_status="$8"

    echo ""
    echo -e "${GREEN}${BOLD}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║          Setup Complete!               ║${NC}"
    echo -e "${GREEN}${BOLD}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}Project:${NC}    $project_name"
    echo -e "${BOLD}Directory:${NC}  $target_dir"
    echo -e "${BOLD}Nginx:${NC}      http://localhost:${nginx_port}"
    echo -e "${BOLD}Database:${NC}   ${DB_LABEL} at 127.0.0.1:${db_port}"
    echo -e "${BOLD}DB User:${NC}    $project_name"
    echo -e "${BOLD}DB Password:${NC} $db_password"
    echo -e "${BOLD}README:${NC}     $readme_status"
    echo -e "${BOLD}License:${NC}    $license_status"
    echo -e "${BOLD}Laravel:${NC}    $( [[ "$laravel_installed" == "true" ]] && echo "Installed" || echo "Not installed" )"

    echo ""
    echo -e "${BOLD}Next steps:${NC}"
    echo ""

    if [[ "$laravel_installed" == "true" ]]; then
        echo "  Build frontend assets (from host machine):"
        echo ""
        echo -e "    ${CYAN}cd ${target_dir}/laravel && npm install && npm run build && cd ..${NC}"
        echo ""
        echo "  Then visit http://localhost:${nginx_port}"
    else
        echo "  1. Start the Docker environment:"
        echo ""
        echo -e "    ${CYAN}cd ${target_dir} && docker compose up -d${NC}"
        echo ""
        echo "  2. Install Laravel:"
        echo ""
        echo -e "    ${CYAN}docker compose exec app composer create-project laravel/laravel .${NC}"
        echo ""
        echo "  3. Generate an app key:"
        echo ""
        echo -e "    ${CYAN}docker compose exec app php artisan key:generate${NC}"
        echo ""
        echo "  4. Merge the generated laravel/.env into Laravel's .env, then migrate:"
        echo ""
        echo -e "    ${CYAN}docker compose exec app php artisan migrate${NC}"
        echo ""
        echo "  5. Build frontend assets (from host machine):"
        echo ""
        echo -e "    ${CYAN}cd ${target_dir}/laravel && npm install && npm run build && cd ..${NC}"
        echo ""
        echo "  Then visit http://localhost:${nginx_port}"
    fi

    echo ""
}

# =============================================================================
# Main
# =============================================================================

main() {
    # Parse arguments
    case "${1:-}" in
        --help|-h)
            show_help
            ;;
        --version|-v)
            show_version
            ;;
    esac

    # Verify templates directory exists
    if [[ ! -d "$TEMPLATES_DIR" ]]; then
        echo -e "${RED}Error: Templates directory not found at $TEMPLATES_DIR${NC}"
        echo "Make sure you're running skeleton from a valid installation."
        exit 1
    fi

    print_header

    # -------------------------------------------------------------------------
    # Step 1 — Project directory
    # -------------------------------------------------------------------------
    echo -e "${BOLD}Step 1: Project Directory${NC}"
    echo ""
    read -rp "Set up project in current directory? (y/n): " use_current

    if is_yes "$use_current"; then
        TARGET_DIR="$(pwd)"
    else
        read -rp "Enter the full directory path: " TARGET_DIR
        # Expand ~ to home directory
        TARGET_DIR="${TARGET_DIR/#\~/$HOME}"

        if [[ ! -d "$TARGET_DIR" ]]; then
            echo -e "${CYAN}Directory does not exist. Creating: $TARGET_DIR${NC}"
            mkdir -p "$TARGET_DIR"
        fi
    fi

    TARGET_DIR="$(readlink -f "$TARGET_DIR")"

    # Self-detection guard
    if is_skeleton_repo "$TARGET_DIR"; then
        echo ""
        echo -e "${RED}${BOLD}Error:${NC}${RED} This appears to be the skeleton repo itself.${NC}"
        echo "Please run skeleton from a different directory for your new project."
        echo ""
        echo "Example:"
        echo "  mkdir ~/projects/my-new-app && cd ~/projects/my-new-app"
        echo "  skeleton"
        exit 1
    fi

    echo -e "Target directory: ${GREEN}$TARGET_DIR${NC}"

    # -------------------------------------------------------------------------
    # Step 2 — Conflict check
    # -------------------------------------------------------------------------
    check_conflicts "$TARGET_DIR"

    # -------------------------------------------------------------------------
    # Step 3 — Project name
    # -------------------------------------------------------------------------
    echo ""
    echo -e "${BOLD}Step 2: Project Name${NC}"
    echo "Used for Docker container names, database, and network."
    echo "Must be lowercase alphanumeric with optional hyphens."
    echo ""

    while true; do
        read -rp "Project name: " PROJECT_NAME
        error_msg="$(validate_project_name "$PROJECT_NAME" 2>&1)" && break
        echo -e "${RED}$error_msg${NC}"
    done

    echo -e "Project name: ${GREEN}$PROJECT_NAME${NC}"

    # -------------------------------------------------------------------------
    # Step 4 — Database engine
    # -------------------------------------------------------------------------
    select_database

    # -------------------------------------------------------------------------
    # Step 5 — Nginx port
    # -------------------------------------------------------------------------
    NGINX_PORT="$(prompt_port "Nginx" "$NGINX_PORT_DEFAULT" "$NGINX_PORT_MIN" "$NGINX_PORT_MAX")"

    # -------------------------------------------------------------------------
    # Step 6 — Database port
    # -------------------------------------------------------------------------
    DB_HOST_PORT="$(prompt_port "Database" "$DB_PORT_DEFAULT" "$DB_PORT_MIN" "$DB_PORT_MAX")"

    # -------------------------------------------------------------------------
    # Generate database password
    # -------------------------------------------------------------------------
    DB_PASSWORD="$(generate_password 32)"
    echo ""
    echo -e "${BOLD}Generated database password:${NC} ${YELLOW}$DB_PASSWORD${NC}"
    echo "(This will be saved to .env — never committed to the repo)"

    # -------------------------------------------------------------------------
    # Step 7 — README
    # -------------------------------------------------------------------------
    echo ""
    echo -e "${BOLD}Step 4: README${NC}"

    if [[ -f "$TARGET_DIR/README.md" ]]; then
        echo -e "Existing README.md found — ${GREEN}preserving${NC}."
        README_STATUS="preserved (existing)"
    else
        echo "No README.md found. Let's create one."
        echo ""
        read -rp "Enter a short description for your project: " PROJECT_DESCRIPTION

        if [[ -z "$PROJECT_DESCRIPTION" ]]; then
            PROJECT_DESCRIPTION="A Laravel application."
        fi

        README_STATUS="generated"
    fi

    # -------------------------------------------------------------------------
    # Step 8 — License
    # -------------------------------------------------------------------------
    echo ""
    echo -e "${BOLD}Step 5: License${NC}"

    if [[ -f "$TARGET_DIR/LICENSE" ]]; then
        echo -e "Existing LICENSE found — ${GREEN}preserving${NC}."
        LICENSE_STATUS="preserved (existing)"
        LICENSE_TYPE="existing"
    else
        echo "No LICENSE file found. Would you like to add one?"
        echo ""

        # Build menu dynamically from available license templates
        local license_options=()
        local menu_index=1

        while IFS= read -r license_name; do
            license_options+=("$license_name")
            echo "  ${menu_index}) ${license_name}"
            ((menu_index++))
        done < <(get_available_licenses)

        local custom_index="$menu_index"
        echo "  ${custom_index}) Custom (provide your own)"
        ((menu_index++))

        local none_index="$menu_index"
        echo "  ${none_index}) No license"
        echo ""

        while true; do
            read -rp "Choose [1-${none_index}]: " license_choice
            if [[ "$license_choice" =~ ^[0-9]+$ && "$license_choice" -ge 1 && "$license_choice" -le "$none_index" ]]; then
                if [[ "$license_choice" -eq "$none_index" ]]; then
                    LICENSE_TYPE="none"
                elif [[ "$license_choice" -eq "$custom_index" ]]; then
                    LICENSE_TYPE="custom"
                else
                    LICENSE_TYPE="${license_options[$((license_choice - 1))]}"
                fi
                break
            else
                echo -e "${RED}Please enter a number between 1 and ${none_index}.${NC}"
            fi
        done

        if [[ "$LICENSE_TYPE" != "none" ]]; then
            if [[ "$LICENSE_TYPE" != "custom" ]]; then
                read -rp "Copyright holder name: " COPYRIGHT_HOLDER
                if [[ -z "$COPYRIGHT_HOLDER" ]]; then
                    COPYRIGHT_HOLDER="$(whoami)"
                fi
            fi
            LICENSE_STATUS="generated (${LICENSE_TYPE})"
        else
            LICENSE_STATUS="none"
        fi
    fi

    # -------------------------------------------------------------------------
    # Confirm and execute
    # -------------------------------------------------------------------------
    echo ""
    echo -e "${BOLD}╔════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║          Ready to scaffold             ║${NC}"
    echo -e "${BOLD}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  Project:    ${CYAN}$PROJECT_NAME${NC}"
    echo -e "  Directory:  ${CYAN}$TARGET_DIR${NC}"
    echo -e "  Nginx port: ${CYAN}$NGINX_PORT${NC}"
    echo -e "  Database:   ${CYAN}$DB_LABEL${NC}"
    echo -e "  DB port:    ${CYAN}$DB_HOST_PORT${NC}"
    echo -e "  README:     ${CYAN}$README_STATUS${NC}"
    echo -e "  License:    ${CYAN}$LICENSE_STATUS${NC}"
    echo ""
    read -rp "Proceed? (y/n): " confirm_proceed

    if ! is_yes "$confirm_proceed"; then
        echo "Setup cancelled."
        exit 0
    fi

    # -------------------------------------------------------------------------
    # Execute — copy templates and apply configuration
    # -------------------------------------------------------------------------
    copy_templates "$TARGET_DIR" "$PROJECT_NAME"
    generate_env "$TARGET_DIR" "$PROJECT_NAME" "$NGINX_PORT" "$DB_HOST_PORT" "$DB_PASSWORD"
    generate_env_example "$TARGET_DIR"

    # Generate README if needed
    if [[ "$README_STATUS" == "generated" ]]; then
        generate_readme "$TARGET_DIR" "$PROJECT_NAME" "$PROJECT_DESCRIPTION" "$NGINX_PORT" "$DB_HOST_PORT"
    fi

    # Generate license if needed
    if [[ "$LICENSE_TYPE" != "none" && "$LICENSE_TYPE" != "existing" ]]; then
        generate_license "$TARGET_DIR" "$LICENSE_TYPE" "${COPYRIGHT_HOLDER:-}"
    fi

    # -------------------------------------------------------------------------
    # Step 9 — Laravel installation
    # -------------------------------------------------------------------------
    echo ""
    echo -e "${BOLD}Step 6: Laravel Installation${NC}"
    echo ""
    read -rp "Install Laravel now? This will start Docker and run composer. (y/n): " install_now

    if is_yes "$install_now"; then
        install_laravel "$TARGET_DIR" "$PROJECT_NAME" "$DB_PASSWORD" "$NGINX_PORT"
        LARAVEL_INSTALLED="true"
    else
        generate_deferred_env "$TARGET_DIR" "$PROJECT_NAME" "$DB_PASSWORD" "$NGINX_PORT"
        echo -e "${YELLOW}Deferred .env written to ${TARGET_DIR}/laravel/.env${NC}"
        echo "Merge these values after installing Laravel."
        LARAVEL_INSTALLED="false"
    fi

    # -------------------------------------------------------------------------
    # Summary
    # -------------------------------------------------------------------------
    print_summary "$PROJECT_NAME" "$TARGET_DIR" "$NGINX_PORT" "$DB_HOST_PORT" "$DB_PASSWORD" "$LARAVEL_INSTALLED" "$README_STATUS" "$LICENSE_STATUS"
}

main "$@"