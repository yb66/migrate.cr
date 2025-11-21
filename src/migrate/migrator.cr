require "log"
require "time_format"
require "db"
require "sqlite3"

require "./migration"
require "./migrator/actions"
require "./migrator/sql"

module Migrate
  # Manages database migrations by running SQL statements in transactions.
  #
  # The `Migrator` class is responsible for:
  # - Loading migration files from a directory or array
  # - Tracking which migrations have been applied
  # - Running migrations in the correct order
  # - Managing the version table in the database
  # - Ensuring all migrations run within transactions
  #
  # ## Version Storage
  #
  # Migrations are tracked in a database table (default: `migrate_versions`)
  # with a column storing the current version as a string (default: `version`).
  #
  # ## Transaction Safety
  #
  # Each migration runs in its own transaction. If any statement in a migration
  # fails, the entire migration is rolled back, including the version update.
  # Previously applied migrations remain committed.
  #
  # ## Usage Examples
  #
  # ### File-based migrations:
  # ```crystal
  # require "db"
  # require "pg"
  # require "migrate"
  #
  # db = DB.open(ENV["DATABASE_URL"])
  # migrator = Migrate::Migrator.new(db, "db/migrations")
  #
  # migrator.current_version  # => "0"
  # migrator.next_version     # => "1"
  #
  # migrator.up               # Run next migration
  # migrator.to_latest        # Run all pending migrations
  # migrator.down             # Rollback one migration
  # migrator.to("5")          # Migrate to specific version
  # ```
  #
  # ### Array-based migrations:
  # ```crystal
  # migrations = [m1, m2, m3]  # Array of Migration objects
  # migrator = Migrate::Migrator.new(db, migrations)
  # migrator.to_latest
  # ```
  class Migrator
    include Migrate::Migrator::Actions
    include Migrate::Migrator::SQL

    # The directory migrations were loaded from (nil if using array initialization)
    getter dir : Path | Nil

    # Hash of migrations keyed by version string, sorted by version
    getter migrations : Hash(String,Migration)

    # Creates a Migrator with an array of Migration objects.
    #
    # Useful for testing or when migrations are generated programmatically.
    #
    # Example:
    # ```crystal
    # migration = Migrate::Migration.new("-- +migrate up\nCREATE TABLE foo (id INT);")
    # migration.version = "1"
    #
    # migrator = Migrate::Migrator.new(db, [migration])
    # ```
    #
    # @param db [DB::Database] The database connection
    # @param migrations [Array(Migration)] Array of migration objects
    # @param table [String] Name of the version tracking table (default: "migrate_versions")
    # @param column [String] Name of the version column (default: "version")
    def initialize(
      @db : DB::Database,
      migrations : Array(Migration),
      @table : String = "migrate_versions",
      @column : String = "version"
    )
      @migrations = {} of String => Migration
      # Get migrations in order
      migrations.sort_by {|migration|
        # Migration raises if no ver
        migration.version.not_nil!
      }.each do |migration|
        @migrations[migration.version.not_nil!] = migration
      end
    end

    # Creates a Migrator that loads migrations from a directory.
    #
    # Scans the directory for .sql files matching the VERSION[_NAME].sql pattern,
    # loads and parses them, and creates the version tracking table if needed.
    #
    # Example:
    # ```crystal
    # migrator = Migrate::Migrator.new(
    #   db,
    #   "db/migrations",
    #   table: "schema_versions",
    #   column: "ver"
    # )
    # ```
    #
    # @param db [DB::Database] The database connection
    # @param dir [String | Path] Directory containing migration files (default: "db/migrations")
    # @param table [String] Name of the version tracking table (default: "migrate_versions")
    # @param column [String] Name of the version column (default: "version")
    # @raise [Exception] If directory does not exist
    def initialize(
      @db : DB::Database,
      dir : String | Path = "db/migrations",
      @table : String = "migrate_versions",
      @column : String = "version"
    )
      dir_path = Path.new(dir).expand # does this raise?
      raise "Migrations dir does not exist" if dir_path.nil?
      raise "Migrations dir does not exist" unless Dir.exists? dir_path
      _dir = Dir.new(dir_path)
      @dir = dir_path
      @migrations = {} of String => Migration

      # Get migrations in order
      _dir.children.map {|child|
        path = Path.new(child)
        Migration.new(path)
      }.sort_by {|migration|
        migration.version.not_nil! # Migration raises if no ver
      }.each do |migration|
        @migrations[migration.version.not_nil!] = migration
      end

      ensure_version_table_exist
    end

  end
end
