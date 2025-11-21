require "../spec_helper"
require "sqlite3"

# Transaction rollback tests
# Covers Phase 3.1 requirement: Transaction rollback tests
# All migrations run in separate transactions - if invalid, all statements are rolled back
describe "Transaction Rollback", tags: "sqlite3" do
  describe "Single migration transaction behavior" do
    it "commits all statements when migration succeeds" do
      db = DB.open("sqlite3:%3Amemory%3A")

      sql = <<-SQL
      -- +migrate up
      CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);
      INSERT INTO users (name) VALUES ('User 1');
      INSERT INTO users (name) VALUES ('User 2');
      CREATE TABLE posts (id INTEGER PRIMARY KEY, title TEXT);
      INSERT INTO posts (title) VALUES ('Post 1');
      SQL

      migration = Migrate::Migration.new(sql)
      up_statements = migration.statements.select { |s| s.is_a?(Migrate::Migration::Statement::Up) }

      # Run all statements in a transaction
      db.transaction do |tx|
        up_statements.each { |stmt| tx.connection.exec(stmt.text) }
      end

      # All changes should be committed
      db.scalar("SELECT COUNT(*) FROM users").as(Int64).should eq 2
      db.scalar("SELECT COUNT(*) FROM posts").as(Int64).should eq 1
    end

    it "rolls back all statements when migration fails" do
      db = DB.open("sqlite3:%3Amemory%3A")

      sql = <<-SQL
      -- +migrate up
      CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);
      INSERT INTO users (name) VALUES ('User 1');
      INSERT INTO users (id, name) VALUES (1, 'Duplicate');  -- This will fail
      SQL

      migration = Migrate::Migration.new(sql)
      up_statements = migration.statements.select { |s| s.is_a?(Migrate::Migration::Statement::Up) }

      # Run all statements in a transaction
      begin
        db.transaction do |tx|
          up_statements.each { |stmt| tx.connection.exec(stmt.text) }
        end
      rescue
        # Expected to fail
      end

      # All changes should be rolled back - table should not exist
      expect_raises(Exception) do
        db.scalar("SELECT COUNT(*) FROM users")
      end
    end

    it "rolls back on syntax error" do
      db = DB.open("sqlite3:%3Amemory%3A")

      sql = <<-SQL
      -- +migrate up
      CREATE TABLE users (id INTEGER PRIMARY KEY);
      INSERT INTO users VALUES (1);
      INVALID SQL SYNTAX HERE;
      INSERT INTO users VALUES (2);
      SQL

      migration = Migrate::Migration.new(sql)
      up_statements = migration.statements.select { |s| s.is_a?(Migrate::Migration::Statement::Up) }

      begin
        db.transaction do |tx|
          up_statements.each { |stmt| tx.connection.exec(stmt.text) }
        end
      rescue
        # Expected to fail
      end

      # Everything should be rolled back
      expect_raises(Exception) do
        db.scalar("SELECT COUNT(*) FROM users")
      end
    end

    it "rolls back on constraint violation" do
      db = DB.open("sqlite3:%3Amemory%3A")

      sql = <<-SQL
      -- +migrate up
      CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT UNIQUE);
      INSERT INTO users (id, email) VALUES (1, 'test@example.com');
      INSERT INTO users (id, email) VALUES (2, 'other@example.com');
      INSERT INTO users (id, email) VALUES (3, 'test@example.com');  -- Duplicate email
      SQL

      migration = Migrate::Migration.new(sql)
      up_statements = migration.statements.select { |s| s.is_a?(Migrate::Migration::Statement::Up) }

      begin
        db.transaction do |tx|
          up_statements.each { |stmt| tx.connection.exec(stmt.text) }
        end
      rescue
        # Expected to fail on unique constraint
      end

      # All inserts should be rolled back
      expect_raises(Exception) do
        db.scalar("SELECT COUNT(*) FROM users")
      end
    end

    it "rolls back on foreign key violation" do
      db = DB.open("sqlite3:%3Amemory%3A")
      db.exec("PRAGMA foreign_keys = ON")

      sql = <<-SQL
      -- +migrate up
      CREATE TABLE users (id INTEGER PRIMARY KEY);
      CREATE TABLE posts (id INTEGER PRIMARY KEY, user_id INTEGER REFERENCES users(id));
      INSERT INTO users VALUES (1);
      INSERT INTO posts VALUES (1, 1);  -- Valid
      INSERT INTO posts VALUES (2, 999);  -- Invalid user_id
      SQL

      migration = Migrate::Migration.new(sql)
      up_statements = migration.statements.select { |s| s.is_a?(Migrate::Migration::Statement::Up) }

      begin
        db.transaction do |tx|
          up_statements.each { |stmt| tx.connection.exec(stmt.text) }
        end
      rescue
        # Expected to fail on foreign key constraint
      end

      # All changes should be rolled back
      expect_raises(Exception) do
        db.scalar("SELECT COUNT(*) FROM users")
      end
    end
  end

  describe "Partial migration success scenarios" do
    it "previous migrations remain committed when later migration fails" do
      db = DB.open("sqlite3:%3Amemory%3A")

      # First migration - should succeed
      m1_sql = <<-SQL
      -- +migrate up
      CREATE TABLE users (id INTEGER PRIMARY KEY);
      INSERT INTO users VALUES (1);
      SQL

      # Second migration - should fail
      m2_sql = <<-SQL
      -- +migrate up
      CREATE TABLE posts (id INTEGER PRIMARY KEY);
      INVALID SQL SYNTAX;
      SQL

      m1 = Migrate::Migration.new(m1_sql)
      m2 = Migrate::Migration.new(m2_sql)

      # Run first migration successfully
      m1_statements = m1.statements.select { |s| s.is_a?(Migrate::Migration::Statement::Up) }
      db.transaction do |tx|
        m1_statements.each { |stmt| tx.connection.exec(stmt.text) }
      end

      # First migration should be committed
      db.scalar("SELECT COUNT(*) FROM users").as(Int64).should eq 1

      # Run second migration - it will fail
      m2_statements = m2.statements.select { |s| s.is_a?(Migrate::Migration::Statement::Up) }
      begin
        db.transaction do |tx|
          m2_statements.each { |stmt| tx.connection.exec(stmt.text) }
        end
      rescue
        # Expected to fail
      end

      # First migration should still be there
      db.scalar("SELECT COUNT(*) FROM users").as(Int64).should eq 1

      # Second migration should not exist
      expect_raises(Exception) do
        db.scalar("SELECT COUNT(*) FROM posts")
      end
    end
  end

  describe "Down migration rollback" do
    it "rolls back down migration on error" do
      db = DB.open("sqlite3:%3Amemory%3A")

      # Set up initial state
      db.exec("CREATE TABLE users (id INTEGER PRIMARY KEY)")
      db.exec("CREATE TABLE posts (id INTEGER PRIMARY KEY)")
      db.exec("INSERT INTO users VALUES (1)")

      sql = <<-SQL
      -- +migrate down
      DROP TABLE posts;
      DROP TABLE invalid_table_name;  -- This will fail
      DROP TABLE users;
      SQL

      migration = Migrate::Migration.new(sql)
      down_statements = migration.statements.select { |s| s.is_a?(Migrate::Migration::Statement::Down) }

      begin
        db.transaction do |tx|
          down_statements.each { |stmt| tx.connection.exec(stmt.text) }
        end
      rescue
        # Expected to fail
      end

      # Both tables should still exist because transaction rolled back
      db.scalar("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='users'").as(Int64).should eq 1
      db.scalar("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='posts'").as(Int64).should eq 1
    end

    it "commits down migration when successful" do
      db = DB.open("sqlite3:%3Amemory%3A")

      # Set up initial state
      db.exec("CREATE TABLE users (id INTEGER PRIMARY KEY)")
      db.exec("CREATE TABLE posts (id INTEGER PRIMARY KEY)")

      sql = <<-SQL
      -- +migrate down
      DROP TABLE posts;
      DROP TABLE users;
      SQL

      migration = Migrate::Migration.new(sql)
      down_statements = migration.statements.select { |s| s.is_a?(Migrate::Migration::Statement::Down) }

      db.transaction do |tx|
        down_statements.each { |stmt| tx.connection.exec(stmt.text) }
      end

      # Both tables should be dropped
      db.scalar("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='users'").as(Int64).should eq 0
      db.scalar("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='posts'").as(Int64).should eq 0
    end
  end

  describe "Transaction isolation" do
    it "changes are not visible outside transaction until commit" do
      db = DB.open("sqlite3:%3Amemory%3A")
      db.exec("CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT)")

      # Start transaction but don't commit
      tx = db.begin_transaction

      tx.connection.exec("INSERT INTO test VALUES (1, 'test')")

      # From outside the transaction, the insert is not visible
      count = db.scalar("SELECT COUNT(*) FROM test").as(Int64)
      count.should eq 0

      # Commit the transaction
      tx.commit

      # Now it should be visible
      count = db.scalar("SELECT COUNT(*) FROM test").as(Int64)
      count.should eq 1
    end

    it "rollback discards all changes" do
      db = DB.open("sqlite3:%3Amemory%3A")
      db.exec("CREATE TABLE test (id INTEGER PRIMARY KEY)")

      tx = db.begin_transaction
      tx.connection.exec("INSERT INTO test VALUES (1)")
      tx.connection.exec("INSERT INTO test VALUES (2)")
      tx.connection.exec("INSERT INTO test VALUES (3)")
      tx.rollback

      # No rows should exist
      count = db.scalar("SELECT COUNT(*) FROM test").as(Int64)
      count.should eq 0
    end
  end

  describe "Nested transaction behavior (savepoints)" do
    it "handles savepoints for partial rollback" do
      db = DB.open("sqlite3:%3Amemory%3A")
      db.exec("CREATE TABLE test (id INTEGER PRIMARY KEY)")

      db.transaction do |tx|
        tx.connection.exec("INSERT INTO test VALUES (1)")

        # SQLite uses SAVEPOINT for nested transactions
        tx.connection.exec("SAVEPOINT sp1")
        tx.connection.exec("INSERT INTO test VALUES (2)")
        tx.connection.exec("INSERT INTO test VALUES (3)")
        tx.connection.exec("ROLLBACK TO sp1")

        # Only first insert should remain
      end

      count = db.scalar("SELECT COUNT(*) FROM test").as(Int64)
      count.should eq 1

      value = db.scalar("SELECT id FROM test").as(Int64)
      value.should eq 1
    end
  end

  describe "Complex rollback scenarios" do
    it "rolls back DDL and DML together" do
      db = DB.open("sqlite3:%3Amemory%3A")

      sql = <<-SQL
      -- +migrate up
      CREATE TABLE users (id INTEGER PRIMARY KEY);
      INSERT INTO users VALUES (1);
      INSERT INTO users VALUES (2);
      CREATE TABLE posts (id INTEGER PRIMARY KEY);
      INSERT INTO posts VALUES (1);
      INSERT INTO users VALUES (1);  -- Duplicate primary key - will fail
      SQL

      migration = Migrate::Migration.new(sql)
      up_statements = migration.statements.select { |s| s.is_a?(Migrate::Migration::Statement::Up) }

      begin
        db.transaction do |tx|
          up_statements.each { |stmt| tx.connection.exec(stmt.text) }
        end
      rescue
        # Expected to fail
      end

      # Both tables and all data should be rolled back
      expect_raises(Exception) do
        db.scalar("SELECT COUNT(*) FROM users")
      end

      expect_raises(Exception) do
        db.scalar("SELECT COUNT(*) FROM posts")
      end
    end

    it "rolls back trigger creation on failure" do
      db = DB.open("sqlite3:%3Amemory%3A")

      sql = <<-SQL
      -- +migrate up
      CREATE TABLE test (id INTEGER PRIMARY KEY);

      -- +migrate start
      CREATE TRIGGER test_trigger AFTER INSERT ON test BEGIN
        SELECT RAISE(FAIL, 'Test error');
      END;
      -- +migrate end

      INSERT INTO test VALUES (1);  -- This will trigger the error
      SQL

      migration = Migrate::Migration.new(sql)
      up_statements = migration.statements.select { |s| s.is_a?(Migrate::Migration::Statement::Up) }

      begin
        db.transaction do |tx|
          up_statements.each { |stmt| tx.connection.exec(stmt.text) }
        end
      rescue
        # Expected to fail due to trigger
      end

      # Table and trigger should both be rolled back
      expect_raises(Exception) do
        db.scalar("SELECT COUNT(*) FROM test")
      end
    end

    it "handles rollback with complex SQL blocks" do
      db = DB.open("sqlite3:%3Amemory%3A")

      sql = <<-SQL
      -- +migrate up
      CREATE TABLE items (id INTEGER PRIMARY KEY);

      -- +migrate start
      CREATE TRIGGER items_check BEFORE INSERT ON items BEGIN
        SELECT CASE
          WHEN NEW.id < 0 THEN RAISE(FAIL, 'Invalid ID')
        END;
      END;
      -- +migrate end

      INSERT INTO items VALUES (1);
      INSERT INTO items VALUES (-1);  -- Will fail the trigger check
      SQL

      migration = Migrate::Migration.new(sql)
      up_statements = migration.statements.select { |s| s.is_a?(Migrate::Migration::Statement::Up) }

      begin
        db.transaction do |tx|
          up_statements.each { |stmt| tx.connection.exec(stmt.text) }
        end
      rescue
        # Expected to fail
      end

      # Everything should be rolled back
      expect_raises(Exception) do
        db.scalar("SELECT COUNT(*) FROM items")
      end
    end
  end

  describe "Rollback with version tracking" do
    it "does not update version on failed migration" do
      db = DB.open("sqlite3:%3Amemory%3A")

      # Create version table
      db.exec("CREATE TABLE migrate_versions (version TEXT NOT NULL)")
      db.exec("INSERT INTO migrate_versions (version) VALUES ('0')")

      sql = <<-SQL
      -- +migrate up
      CREATE TABLE test (id INTEGER PRIMARY KEY);
      INSERT INTO test VALUES (1);
      INVALID SQL;
      SQL

      migration = Migrate::Migration.new(sql)
      up_statements = migration.statements.select { |s| s.is_a?(Migrate::Migration::Statement::Up) }

      begin
        db.transaction do |tx|
          up_statements.each { |stmt| tx.connection.exec(stmt.text) }
          # Version update would happen here
          tx.connection.exec("UPDATE migrate_versions SET version = '1'")
        end
      rescue
        # Expected to fail
      end

      # Version should still be 0
      version = db.scalar("SELECT version FROM migrate_versions").as(String)
      version.should eq "0"

      # Test table should not exist
      expect_raises(Exception) do
        db.scalar("SELECT COUNT(*) FROM test")
      end
    end

    it "updates version only when migration succeeds" do
      db = DB.open("sqlite3:%3Amemory%3A")

      # Create version table
      db.exec("CREATE TABLE migrate_versions (version TEXT NOT NULL)")
      db.exec("INSERT INTO migrate_versions (version) VALUES ('0')")

      sql = <<-SQL
      -- +migrate up
      CREATE TABLE test (id INTEGER PRIMARY KEY);
      INSERT INTO test VALUES (1);
      SQL

      migration = Migrate::Migration.new(sql)
      up_statements = migration.statements.select { |s| s.is_a?(Migrate::Migration::Statement::Up) }

      db.transaction do |tx|
        up_statements.each { |stmt| tx.connection.exec(stmt.text) }
        tx.connection.exec("UPDATE migrate_versions SET version = '1'")
      end

      # Version should be updated
      version = db.scalar("SELECT version FROM migrate_versions").as(String)
      version.should eq "1"

      # Test table should exist
      count = db.scalar("SELECT COUNT(*) FROM test").as(Int64)
      count.should eq 1
    end
  end
end
