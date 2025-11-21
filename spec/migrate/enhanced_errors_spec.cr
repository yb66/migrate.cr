require "../spec_helper"

describe Migrate::Migrator::EnhancedErrors do
  describe "MigrationExecutionError" do
    it "creates error with basic info" do
      original = Exception.new("Original error message")
      error = Migrate::Migrator::EnhancedErrors::MigrationExecutionError.new(
        migration_version: "5",
        direction: Migrate::Direction::Up,
        original_error: original
      )

      error.migration_version.should eq("5")
      error.direction.should eq(Migrate::Direction::Up)
      error.original_error.should eq(original)
    end

    it "includes optional migration name and statement info" do
      original = Exception.new("SQL error")
      error = Migrate::Migrator::EnhancedErrors::MigrationExecutionError.new(
        migration_version: "10",
        direction: Migrate::Direction::Down,
        original_error: original,
        migration_name: "create_users",
        statement_index: 3,
        statement: "DROP TABLE users"
      )

      error.migration_name.should eq("create_users")
      error.statement_index.should eq(3)
      error.statement.should eq("DROP TABLE users")
    end

    it "builds comprehensive error message" do
      original = Exception.new("constraint violation")
      error = Migrate::Migrator::EnhancedErrors::MigrationExecutionError.new(
        migration_version: "7",
        direction: Migrate::Direction::Up,
        original_error: original,
        migration_name: "add_constraints",
        statement_index: 2,
        statement: "ALTER TABLE users ADD CONSTRAINT unique_email UNIQUE(email)"
      )

      message = error.message
      message.should contain("Migration execution failed")
      message.should contain("Version: 7")
      message.should contain("add_constraints")
      message.should contain("Direction: Up")
      message.should contain("Failed at statement 3") # index 2 + 1
      message.should contain("constraint violation")
    end

    it "truncates long statements in error message" do
      original = Exception.new("error")
      long_statement = "CREATE TABLE " + ("x" * 300)

      error = Migrate::Migrator::EnhancedErrors::MigrationExecutionError.new(
        migration_version: "1",
        direction: Migrate::Direction::Up,
        original_error: original,
        statement_index: 0,
        statement: long_statement
      )

      message = error.message
      # Statement should be truncated to ~200 chars
      message.should_not contain(long_statement)
      message.should contain("...")
    end

    it "formats error for display" do
      original = Exception.new("test error")
      error = Migrate::Migrator::EnhancedErrors::MigrationExecutionError.new(
        migration_version: "3",
        direction: Migrate::Direction::Down,
        original_error: original
      )

      output = error.to_s
      output.should contain("Migration execution failed")
      output.should contain("Version: 3")
      output.should contain("test error")
    end
  end

  describe "error handling during migration execution" do
    it "wraps database errors with enhanced context" do
      with_sqlite_migrator do |migrator|
        # Create a migration with an error
        bad_migration = Migrate::Migration.new("-- +migrate up\nINVALID SQL STATEMENT;")
        bad_migration.version = "999"

        bad_migrator = Migrate::Migrator.new(
          migrator.@db,
          [bad_migration],
          "migrate_versions_test"
        )

        expect_raises(Migrate::Migrator::EnhancedErrors::MigrationExecutionError) do
          bad_migrator.to("999", skip_safety_check: true)
        end
      end
    end

    it "provides statement index in error" do
      with_sqlite_migrator do |migrator|
        # Create migration with multiple statements, one invalid
        migration_content = <<-SQL
        -- +migrate up
        CREATE TABLE test1 (id INTEGER);
        CREATE TABLE test2 (id INTEGER);
        INVALID SQL HERE;
        CREATE TABLE test3 (id INTEGER);
        SQL

        bad_migration = Migrate::Migration.new(migration_content)
        bad_migration.version = "998"

        bad_migrator = Migrate::Migrator.new(
          migrator.@db,
          [bad_migration],
          "migrate_versions_test2"
        )

        begin
          bad_migrator.to("998", skip_safety_check: true)
          fail "Should have raised an error"
        rescue e : Migrate::Migrator::EnhancedErrors::MigrationExecutionError
          # Should indicate which statement failed
          e.statement_index.should_not be_nil
          e.statement.should_not be_nil
        end
      end
    end
  end
end
