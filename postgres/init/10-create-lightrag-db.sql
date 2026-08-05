-- ============================================================================
-- Postgres init script — runs once on first database initialization
-- (when /var/lib/postgresql/data is empty).
-- ============================================================================
-- Creates a dedicated database for LightRAG so its tables are isolated from
-- the main application database. LightRAG itself will create its schema and
-- run `CREATE EXTENSION IF NOT EXISTS vector` on first connect, so we only
-- need the database to exist.
--
-- Connects as the POSTGRES_USER (superuser) set by the container env.
-- ============================================================================

SELECT 'CREATE DATABASE lightrag'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'lightrag')\gexec

GRANT ALL PRIVILEGES ON DATABASE lightrag TO :POSTGRES_USER;
