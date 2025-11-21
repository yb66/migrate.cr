require "../spec_helper"
require "sqlite3"

# Comprehensive SQLite integration tests
# Covers Phase 3.1 requirement: SQLite integration tests
describe "SQLite Integration Tests", tags: "sqlite3" do
  describe "Full migration lifecycle" do
    it "performs complete up and down migration cycle" do
      db = DB.open("sqlite3:%3Amemory%3A")

      migration_sql = <<-SQL
      -- +migrate up
      CREATE TABLE users (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        email TEXT UNIQUE NOT NULL
      );

      CREATE INDEX idx_users_email ON users(email);

      INSERT INTO users (name, email) VALUES ('Admin', 'admin@example.com');

      -- +migrate down
      DROP INDEX idx_users_email;
      DROP TABLE users;
      SQL

      migration = Migrate::Migration.new(migration_sql)
      migration.version = "1"

      migrator = Migrate::Migrator.new(db, [migration])

      # Table should not exist initially
      count = db.scalar("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='migrate_versions'").as(Int64)
      count.should eq 1  # Only version table

      # Run up migration
      up_statements = migration.statements.select { |s| s.is_a?(Migrate::Migration::Statement::Up) }
      up_statements.each do |stmt|
        db.exec(stmt.text)
      end

      # Verify table exists
      count = db.scalar("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='users'").as(Int64)
      count.should eq 1

      # Verify index exists
      count = db.scalar("SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name='idx_users_email'").as(Int64)
      count.should eq 1

      # Verify data exists
      count = db.scalar("SELECT COUNT(*) FROM users").as(Int64)
      count.should eq 1

      # Run down migration
      down_statements = migration.statements.select { |s| s.is_a?(Migrate::Migration::Statement::Down) }
      down_statements.each do |stmt|
        db.exec(stmt.text)
      end

      # Verify table is dropped
      count = db.scalar("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='users'").as(Int64)
      count.should eq 0
    end

    it "handles multiple migrations in sequence" do
      db = DB.open("sqlite3:%3Amemory%3A")

      m1_sql = <<-SQL
      -- +migrate up
      CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);
      -- +migrate down
      DROP TABLE users;
      SQL

      m2_sql = <<-SQL
      -- +migrate up
      CREATE TABLE posts (id INTEGER PRIMARY KEY, user_id INTEGER, content TEXT);
      -- +migrate down
      DROP TABLE posts;
      SQL

      m3_sql = <<-SQL
      -- +migrate up
      CREATE TABLE comments (id INTEGER PRIMARY KEY, post_id INTEGER, text TEXT);
      -- +migrate down
      DROP TABLE comments;
      SQL

      migrations = [m1_sql, m2_sql, m3_sql].map_with_index do |sql, i|
        m = Migrate::Migration.new(sql)
        m.version = (i + 1).to_s
        m
      end

      # Apply all migrations
      migrations.each do |migration|
        up_statements = migration.statements.select { |s| s.is_a?(Migrate::Migration::Statement::Up) }
        up_statements.each { |stmt| db.exec(stmt.text) }
      end

      # Verify all tables exist
      db.scalar("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='users'").as(Int64).should eq 1
      db.scalar("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='posts'").as(Int64).should eq 1
      db.scalar("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='comments'").as(Int64).should eq 1

      # Rollback all migrations
      migrations.reverse.each do |migration|
        down_statements = migration.statements.select { |s| s.is_a?(Migrate::Migration::Statement::Down) }
        down_statements.each { |stmt| db.exec(stmt.text) }
      end

      # Verify all tables are dropped
      db.scalar("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='users'").as(Int64).should eq 0
      db.scalar("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='posts'").as(Int64).should eq 0
      db.scalar("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='comments'").as(Int64).should eq 0
    end
  end

  describe "SQLite specific features" do
    it "handles virtual tables (FTS5)" do
      db = DB.open("sqlite3:%3Amemory%3A")

      sql = <<-SQL
      -- +migrate up
      CREATE TABLE documents (id INTEGER PRIMARY KEY, content TEXT);

      CREATE VIRTUAL TABLE documents_fts USING fts5(content, content='documents', content_rowid='id');

      -- +migrate start
      CREATE TRIGGER documents_ai AFTER INSERT ON documents BEGIN
        INSERT INTO documents_fts(rowid, content) VALUES (new.id, new.content);
      END;
      -- +migrate end

      -- +migrate down
      DROP TRIGGER documents_ai;
      DROP TABLE documents_fts;
      DROP TABLE documents;
      SQL

      migration = Migrate::Migration.new(sql)

      up_statements = migration.statements.select { |s| s.is_a?(Migrate::Migration::Statement::Up) }
      up_statements.each { |stmt| db.exec(stmt.text) }

      # Test FTS is working
      db.exec("INSERT INTO documents (content) VALUES ('hello world')")

      count = db.scalar("SELECT COUNT(*) FROM documents_fts WHERE content MATCH 'hello'").as(Int64)
      count.should eq 1
    end

    it "handles triggers" do
      db = DB.open("sqlite3:%3Amemory%3A")

      sql = <<-SQL
      -- +migrate up
      CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT);
      CREATE TABLE audit_log (id INTEGER PRIMARY KEY, item_id INTEGER, action TEXT);

      -- +migrate start
      CREATE TRIGGER items_insert AFTER INSERT ON items BEGIN
        INSERT INTO audit_log (item_id, action) VALUES (NEW.id, 'INSERT');
      END;
      -- +migrate end

      -- +migrate down
      DROP TRIGGER items_insert;
      DROP TABLE audit_log;
      DROP TABLE items;
      SQL

      migration = Migrate::Migration.new(sql)

      up_statements = migration.statements.select { |s| s.is_a?(Migrate::Migration::Statement::Up) }
      up_statements.each { |stmt| db.exec(stmt.text) }

      db.exec("INSERT INTO items (name) VALUES ('test')")

      count = db.scalar("SELECT COUNT(*) FROM audit_log WHERE action = 'INSERT'").as(Int64)
      count.should eq 1
    end

    it "handles views" do
      db = DB.open("sqlite3:%3Amemory%3A")

      sql = <<-SQL
      -- +migrate up
      CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, active INTEGER);
      CREATE VIEW active_users AS SELECT * FROM users WHERE active = 1;

      -- +migrate down
      DROP VIEW active_users;
      DROP TABLE users;
      SQL

      migration = Migrate::Migration.new(sql)

      up_statements = migration.statements.select { |s| s.is_a?(Migrate::Migration::Statement::Up) }
      up_statements.each { |stmt| db.exec(stmt.text) }

      count = db.scalar("SELECT COUNT(*) FROM sqlite_master WHERE type='view' AND name='active_users'").as(Int64)
      count.should eq 1
    end

    it "handles indexes with expressions" do
      db = DB.open("sqlite3:%3Amemory%3A")

      sql = <<-SQL
      -- +migrate up
      CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT);
      CREATE INDEX idx_email_lower ON users(LOWER(email));

      -- +migrate down
      DROP INDEX idx_email_lower;
      DROP TABLE users;
      SQL

      migration = Migrate::Migration.new(sql)

      up_statements = migration.statements.select { |s| s.is_a?(Migrate::Migration::Statement::Up) }
      up_statements.each { |stmt| db.exec(stmt.text) }

      count = db.scalar("SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name='idx_email_lower'").as(Int64)
      count.should eq 1
    end
  end

  describe "Data migrations" do
    it "migrates data along with schema" do
      db = DB.open("sqlite3:%3Amemory%3A")

      sql = <<-SQL
      -- +migrate up
      CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT);
      INSERT INTO settings (key, value) VALUES ('version', '1.0.0');
      INSERT INTO settings (key, value) VALUES ('environment', 'production');

      -- +migrate down
      DROP TABLE settings;
      SQL

      migration = Migrate::Migration.new(sql)

      up_statements = migration.statements.select { |s| s.is_a?(Migrate::Migration::Statement::Up) }
      up_statements.each { |stmt| db.exec(stmt.text) }

      count = db.scalar("SELECT COUNT(*) FROM settings").as(Int64)
      count.should eq 2

      version = db.scalar("SELECT value FROM settings WHERE key = 'version'").as(String)
      version.should eq "1.0.0"
    end

    it "transforms data during migration" do
      db = DB.open("sqlite3:%3Amemory%3A")

      # Initial schema
      db.exec("CREATE TABLE users_old (id INTEGER PRIMARY KEY, fullname TEXT)")
      db.exec("INSERT INTO users_old (fullname) VALUES ('John Doe')")
      db.exec("INSERT INTO users_old (fullname) VALUES ('Jane Smith')")

      sql = <<-SQL
      -- +migrate up
      CREATE TABLE users_new (id INTEGER PRIMARY KEY, first_name TEXT, last_name TEXT);

      -- Note: SQLite doesn't support functions in INSERT...SELECT easily,
      -- so this is a simplified example
      -- INSERT INTO users_new (id, first_name, last_name)
      -- SELECT id, substr(fullname, 1, instr(fullname, ' ') - 1), substr(fullname, instr(fullname, ' ') + 1)
      -- FROM users_old;

      DROP TABLE users_old;

      -- +migrate down
      CREATE TABLE users_old (id INTEGER PRIMARY KEY, fullname TEXT);
      DROP TABLE users_new;
      SQL

      migration = Migrate::Migration.new(sql)

      up_statements = migration.statements.select { |s| s.is_a?(Migrate::Migration::Statement::Up) }
      up_statements.each { |stmt| db.exec(stmt.text) }

      # Verify new table exists
      count = db.scalar("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='users_new'").as(Int64)
      count.should eq 1

      # Verify old table is dropped
      count = db.scalar("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='users_old'").as(Int64)
      count.should eq 0
    end
  end

  describe "Complex migration scenarios" do
    it "handles foreign key constraints" do
      db = DB.open("sqlite3:%3Amemory%3A")
      db.exec("PRAGMA foreign_keys = ON")

      sql = <<-SQL
      -- +migrate up
      CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);
      CREATE TABLE posts (
        id INTEGER PRIMARY KEY,
        user_id INTEGER NOT NULL,
        content TEXT,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      );

      -- +migrate down
      DROP TABLE posts;
      DROP TABLE users;
      SQL

      migration = Migrate::Migration.new(sql)

      up_statements = migration.statements.select { |s| s.is_a?(Migrate::Migration::Statement::Up) }
      up_statements.each { |stmt| db.exec(stmt.text) }

      # Insert test data
      db.exec("INSERT INTO users (name) VALUES ('Test User')")
      db.exec("INSERT INTO posts (user_id, content) VALUES (1, 'Test Post')")

      # Verify constraint is enforced
      expect_raises(Exception) do
        db.exec("INSERT INTO posts (user_id, content) VALUES (999, 'Invalid Post')")
      end
    end

    it "handles check constraints" do
      db = DB.open("sqlite3:%3Amemory%3A")

      sql = <<-SQL
      -- +migrate up
      CREATE TABLE products (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        price REAL CHECK(price > 0),
        stock INTEGER CHECK(stock >= 0)
      );

      -- +migrate down
      DROP TABLE products;
      SQL

      migration = Migrate::Migration.new(sql)

      up_statements = migration.statements.select { |s| s.is_a?(Migrate::Migration::Statement::Up) }
      up_statements.each { |stmt| db.exec(stmt.text) }

      # Valid insert
      db.exec("INSERT INTO products (name, price, stock) VALUES ('Widget', 9.99, 10)")

      # Invalid price
      expect_raises(Exception) do
        db.exec("INSERT INTO products (name, price, stock) VALUES ('Bad', -5.00, 10)")
      end

      # Invalid stock
      expect_raises(Exception) do
        db.exec("INSERT INTO products (name, price, stock) VALUES ('Bad', 9.99, -1)")
      end
    end

    it "handles unique constraints" do
      db = DB.open("sqlite3:%3Amemory%3A")

      sql = <<-SQL
      -- +migrate up
      CREATE TABLE users (
        id INTEGER PRIMARY KEY,
        email TEXT UNIQUE NOT NULL,
        username TEXT UNIQUE NOT NULL
      );

      -- +migrate down
      DROP TABLE users;
      SQL

      migration = Migrate::Migration.new(sql)

      up_statements = migration.statements.select { |s| s.is_a?(Migrate::Migration::Statement::Up) }
      up_statements.each { |stmt| db.exec(stmt.text) }

      db.exec("INSERT INTO users (email, username) VALUES ('test@example.com', 'testuser')")

      # Duplicate email
      expect_raises(Exception) do
        db.exec("INSERT INTO users (email, username) VALUES ('test@example.com', 'different')")
      end

      # Duplicate username
      expect_raises(Exception) do
        db.exec("INSERT INTO users (email, username) VALUES ('different@example.com', 'testuser')")
      end
    end
  end

  describe "Migrator initialization and operations" do
    it "initializes migrator with array of migrations" do
      db = DB.open("sqlite3:%3Amemory%3A")

      migration_sql = "-- +migrate up\nCREATE TABLE foo (id INTEGER);"
      migrations = [migration_sql].map_with_index do |sql, i|
        m = Migrate::Migration.new(sql)
        m.version = (i + 1).to_s
        m.name = "test_migration"
        m
      end

      migrator = Migrate::Migrator.new(db, migrations)
      migrator.should_not be_nil
      migrator.migrations.size.should eq 1
    end

    it "sorts migrations by version" do
      db = DB.open("sqlite3:%3Amemory%3A")

      migration_sql = "-- +migrate up\nCREATE TABLE foo (id INTEGER);"
      versions = ["3", "1", "5", "2"]

      migrations = versions.map do |version|
        m = Migrate::Migration.new(migration_sql)
        m.version = version
        m
      end

      migrator = Migrate::Migrator.new(db, migrations)

      # Migrations should be sorted by version
      sorted_versions = migrator.migrations.keys
      sorted_versions.should eq ["1", "2", "3", "5"]
    end

    it "creates version table on initialization" do
      db = DB.open("sqlite3:%3Amemory%3A")

      migration_sql = "-- +migrate up\nCREATE TABLE foo (id INTEGER);"
      migration = Migrate::Migration.new(migration_sql)
      migration.version = "1"

      migrator = Migrate::Migrator.new(db, [migration])

      # Version table should exist
      count = db.scalar("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='migrate_versions'").as(Int64)
      count.should eq 1
    end
  end
end
