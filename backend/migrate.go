package main

import (
	"context"
	"log"
	"os"
	"path/filepath"
	"sort"
)

// migrate applies migrations/*.sql in name order, once each (tracked in schema_migrations).
// Runs on every start, so a deploy (git push) updates the database schema automatically.
// An advisory lock makes it safe when two instances start at the same time.
func (s *Server) migrate() {
	dir := ""
	for _, d := range []string{os.Getenv("MIGRATIONS_DIR"), "/migrations", "./migrations"} {
		if d == "" {
			continue
		}
		if st, err := os.Stat(d); err == nil && st.IsDir() {
			dir = d
			break
		}
	}
	if dir == "" {
		log.Println("migrate: no migrations directory found, skipping")
		return
	}
	files, _ := filepath.Glob(filepath.Join(dir, "*.sql"))
	sort.Strings(files)

	ctx := context.Background()
	conn, err := s.db.Conn(ctx)
	if err != nil {
		log.Fatal("migrate: ", err)
	}
	defer conn.Close()
	if _, err := conn.ExecContext(ctx, `SELECT pg_advisory_lock(727274)`); err != nil {
		log.Fatal("migrate lock: ", err)
	}
	defer conn.ExecContext(ctx, `SELECT pg_advisory_unlock(727274)`)

	if _, err := conn.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS schema_migrations (name TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())`); err != nil {
		log.Fatal("migrate: ", err)
	}
	// Existing database created before this runner (e.g. docker initdb): treat 001 as already applied.
	var n int
	var usersTable *string
	_ = conn.QueryRowContext(ctx, `SELECT count(*) FROM schema_migrations`).Scan(&n)
	_ = conn.QueryRowContext(ctx, `SELECT to_regclass('public.users')::text`).Scan(&usersTable)
	if n == 0 && usersTable != nil {
		_, _ = conn.ExecContext(ctx, `INSERT INTO schema_migrations(name) VALUES ('001_init.sql') ON CONFLICT DO NOTHING`)
		log.Println("migrate: existing database detected, 001_init.sql marked as applied")
	}

	for _, f := range files {
		name := filepath.Base(f)
		var done bool
		_ = conn.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM schema_migrations WHERE name=$1)`, name).Scan(&done)
		if done {
			continue
		}
		sqlText, err := os.ReadFile(f)
		if err != nil {
			log.Fatal("migrate: ", err)
		}
		tx, err := conn.BeginTx(ctx, nil)
		if err != nil {
			log.Fatal("migrate: ", err)
		}
		if _, err := tx.ExecContext(ctx, string(sqlText)); err != nil {
			_ = tx.Rollback()
			log.Fatalf("migrate %s failed: %v", name, err)
		}
		if _, err := tx.ExecContext(ctx, `INSERT INTO schema_migrations(name) VALUES ($1)`, name); err != nil {
			_ = tx.Rollback()
			log.Fatal("migrate: ", err)
		}
		if err := tx.Commit(); err != nil {
			log.Fatal("migrate: ", err)
		}
		log.Println("migrate: applied", name)
	}
}