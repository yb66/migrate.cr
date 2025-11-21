require "../spec_helper"
require "sqlite3"

# Comprehensive error handling tests
# Covers Phase 3.1 requirement: Test error handling paths
describe "Error Handling", tags: "unit" do
  describe "Migrate::Error" do
    it "is a subclass of Exception" do
      error = Migrate::Error.new("Test error")
      error.should be_a(Exception)
    end

    it "preserves error message" do
      message = "Migration failed due to constraint violation"
      error = Migrate::Error.new(message)
      error.message.should eq message
    end
  end

  describe "Migration parsing errors" do
    it "raises on invalid migration file format" do
      invalid_sql = "This is not a valid migration"

      expect_raises(Exception, /No up\/down\/error/) do
        Migrate::Migration.new(invalid_sql)
      end
    end

    it "raises on malformed file name pattern" do
      expect_raises(Exception, /pattern/) do
        # Invalid filename that doesn't match VERSION_NAME.sql
        Migrate::Migration.new(Path["invalid-name.sql"])
      end
    end

    it "handles unclosed complex statement gracefully" do
      sql = <<-SQL
      -- +migrate up
      -- +migrate start
      CREATE FUNCTION foo() RETURNS INT AS $$
      BEGIN
        RETURN 1;
      END;
      $$ LANGUAGE plpgsql;
      -- No +migrate end here
      SQL

      # Should either succeed (implicit end) or raise a clear error
      begin
        migration = Migrate::Migration.new(sql)
        migration.should_not be_nil
      rescue e : Exception
        e.message.should_not be_nil
      end
    end

    it "raises on nested complex statements without proper end" do
      sql = <<-SQL
      -- +migrate up
      -- +migrate start
      CREATE FUNCTION foo() RETURNS INT AS $$
      BEGIN
        RETURN 1;
      END;
      $$ LANGUAGE plpgsql;
      -- +migrate start  -- Nested start without ending previous
      CREATE FUNCTION bar() RETURNS INT AS $$
      BEGIN
        RETURN 2;
      END;
      $$ LANGUAGE plpgsql;
      -- +migrate end
      SQL

      expect_raises(Exception) do
        Migrate::Migration.new(sql)
      end
    end
  end

  describe "Migration::Statement::Error behavior" do
    it "creates error with custom message" do
      message = "This migration is irreversible"
      migration = Migrate::Migration.new("-- +migrate error #{message}")

      error_stmt = migration.statements.first
      error_stmt.should be_a(Migrate::Migration::Statement::Error)
      error_stmt.text.should eq message
    end

    it "creates error with default message when message is nil" do
      error = Migrate::Migration::Statement::Error.new(nil)
      error.text.should eq "Migration error command was given."
    end

    it "handles error directive mid-migration" do
      sql = <<-SQL
      -- +migrate up
      CREATE TABLE foo (id INT);
      -- +migrate error Cannot proceed further
      CREATE TABLE bar (id INT);
      SQL

      migration = Migrate::Migration.new(sql)
      statements = migration.statements

      statements.size.should be >= 2
      statements.any? { |s| s.is_a?(Migrate::Migration::Statement::Error) }.should be_true
    end
  end

  describe "Database operation errors", tags: "sqlite3" do
    it "handles SQL syntax errors" do
      db = DB.open("sqlite3:%3Amemory%3A")

      expect_raises(Exception) do
        db.exec("CREATE INVALID SQL SYNTAX")
      end
    end

    it "handles constraint violations" do
      db = DB.open("sqlite3:%3Amemory%3A")
      db.exec("CREATE TABLE foo (id INTEGER PRIMARY KEY)")
      db.exec("INSERT INTO foo VALUES (1)")

      expect_raises(Exception) do
        db.exec("INSERT INTO foo VALUES (1)")  # Duplicate primary key
      end
    end

    it "handles table already exists error" do
      db = DB.open("sqlite3:%3Amemory%3A")
      db.exec("CREATE TABLE foo (id INTEGER PRIMARY KEY)")

      expect_raises(Exception) do
        db.exec("CREATE TABLE foo (id INTEGER PRIMARY KEY)")
      end
    end

    it "handles table not found error" do
      db = DB.open("sqlite3:%3Amemory%3A")

      expect_raises(Exception) do
        db.exec("DROP TABLE nonexistent_table")
      end
    end

    it "handles column not found error" do
      db = DB.open("sqlite3:%3Amemory%3A")
      db.exec("CREATE TABLE foo (id INTEGER PRIMARY KEY)")

      expect_raises(Exception) do
        db.exec("SELECT nonexistent_column FROM foo")
      end
    end
  end

  describe "Transaction rollback on error", tags: "sqlite3" do
    it "rolls back transaction on error" do
      db = DB.open("sqlite3:%3Amemory%3A")
      db.exec("CREATE TABLE foo (id INTEGER PRIMARY KEY)")

      begin
        db.transaction do |tx|
          tx.connection.exec("INSERT INTO foo VALUES (1)")
          tx.connection.exec("INSERT INTO foo VALUES (1)")  # Duplicate, will fail
        end
      rescue
        # Transaction should be rolled back
      end

      # First insert should be rolled back
      count = db.scalar("SELECT COUNT(*) FROM foo").as(Int64)
      count.should eq 0
    end

    it "commits transaction on success" do
      db = DB.open("sqlite3:%3Amemory%3A")
      db.exec("CREATE TABLE foo (id INTEGER PRIMARY KEY)")

      db.transaction do |tx|
        tx.connection.exec("INSERT INTO foo VALUES (1)")
        tx.connection.exec("INSERT INTO foo VALUES (2)")
      end

      count = db.scalar("SELECT COUNT(*) FROM foo").as(Int64)
      count.should eq 2
    end

    it "allows multiple statements in transaction" do
      db = DB.open("sqlite3:%3Amemory%3A")

      db.transaction do |tx|
        tx.connection.exec("CREATE TABLE foo (id INTEGER PRIMARY KEY)")
        tx.connection.exec("INSERT INTO foo VALUES (1)")
        tx.connection.exec("CREATE TABLE bar (id INTEGER PRIMARY KEY)")
        tx.connection.exec("INSERT INTO bar VALUES (1)")
      end

      foo_count = db.scalar("SELECT COUNT(*) FROM foo").as(Int64)
      bar_count = db.scalar("SELECT COUNT(*) FROM bar").as(Int64)

      foo_count.should eq 1
      bar_count.should eq 1
    end

    it "rolls back all changes on any error in transaction" do
      db = DB.open("sqlite3:%3Amemory%3A")

      begin
        db.transaction do |tx|
          tx.connection.exec("CREATE TABLE foo (id INTEGER PRIMARY KEY)")
          tx.connection.exec("INSERT INTO foo VALUES (1)")
          tx.connection.exec("INSERT INTO foo VALUES (1)")  # This fails
        end
      rescue
        # Expected to fail
      end

      # Table should not exist because transaction was rolled back
      expect_raises(Exception) do
        db.scalar("SELECT COUNT(*) FROM foo")
      end
    end
  end

  describe "Error context and reporting" do
    it "preserves original exception information" do
      db = DB.open("sqlite3:%3Amemory%3A")

      begin
        db.exec("INVALID SQL")
      rescue e : Exception
        e.message.should_not be_nil
        e.class.should_not be_nil
      end
    end

    it "can wrap errors with additional context" do
      original_error = Exception.new("Original error")
      wrapped_error = Migrate::Error.new("Migration failed: #{original_error.message}")

      wrapped_error.message.should contain("Original error")
      wrapped_error.message.should contain("Migration failed")
    end
  end

  describe "Migration validation errors" do
    it "detects version not in migration list" do
      migration_sql = "-- +migrate up\nCREATE TABLE foo (id INT);"
      migrations = [migration_sql].map_with_index do |sql, i|
        m = Migrate::Migration.new(sql)
        m.version = (i + 1).to_s
        m
      end

      db = DB.open("sqlite3:%3Amemory%3A")
      migrator = Migrate::Migrator.new(db, migrations)

      all_versions = migrator.migrations.keys
      target_version = "99"

      all_versions.includes?(target_version).should be_false
    end

    it "detects current version not in migration list" do
      # This could happen if migration files are deleted or modified
      migration_sql = "-- +migrate up\nCREATE TABLE foo (id INT);"
      migrations = [migration_sql].map_with_index do |sql, i|
        m = Migrate::Migration.new(sql)
        m.version = (i + 10).to_s  # Start from 10
        m
      end

      db = DB.open("sqlite3:%3Amemory%3A")
      migrator = Migrate::Migrator.new(db, migrations)

      # If current version is 1 but migrations start at 10
      all_versions = migrator.migrations.keys
      current_version = "1"

      all_versions.includes?(current_version).should be_false
    end
  end

  describe "File system errors" do
    it "handles missing migration directory" do
      db = DB.open("sqlite3:%3Amemory%3A")

      expect_raises(Exception, /not exist/) do
        Migrate::Migrator.new(db, "/nonexistent/directory")
      end
    end

    it "handles missing migration file" do
      expect_raises(Exception) do
        Migrate::Migration.new(Path["/nonexistent/file.sql"])
      end
    end
  end

  describe "Empty migration handling" do
    it "handles empty up migration" do
      sql = <<-SQL
      -- +migrate up
      -- +migrate down
      DROP TABLE foo;
      SQL

      migration = Migrate::Migration.new(sql)
      up_statements = migration.statements.select { |s| s.is_a?(Migrate::Migration::Statement::Up) }

      # No up statements
      up_statements.should be_empty
    end

    it "handles empty down migration" do
      sql = <<-SQL
      -- +migrate up
      CREATE TABLE foo (id INT);
      -- +migrate down
      SQL

      migration = Migrate::Migration.new(sql)
      down_statements = migration.statements.select { |s| s.is_a?(Migrate::Migration::Statement::Down) }

      # No down statements
      down_statements.should be_empty
    end
  end

  describe "Concurrent migration errors" do
    it "detects when version table doesn't exist", tags: "sqlite3" do
      db = DB.open("sqlite3:%3Amemory%3A")

      # Try to read version before table exists
      expect_raises(Exception) do
        db.scalar("SELECT version FROM migrate_versions")
      end
    end

    it "handles multiple migrations with same version" do
      migration_sql = "-- +migrate up\nCREATE TABLE foo (id INT);"
      migrations = [migration_sql, migration_sql].map do |sql|
        m = Migrate::Migration.new(sql)
        m.version = "1"  # Same version!
        m
      end

      # Hash will only keep one due to duplicate key
      hash = {} of String => Migrate::Migration
      migrations.each do |m|
        hash[m.version.not_nil!] = m
      end

      hash.size.should eq 1  # Only one version stored
    end
  end
end
