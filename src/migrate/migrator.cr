require "log"
require "time_format"
require "db"

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

    getter dir : Path
    getter migrations : Hash(String,Migration)

    def initialize(
      @db : DB::Database,
      dir : String | Path = "db/migrations",
      @table : String = "migrate_versions",
      @column : String = "version"
    )
      @dir = Path.new(dir).expand
      @migrations = {} of String => Hash

      # Get migrations in order
      @dir.each_child.map {|child|
        path = Path.new(child)
        Migration.new(path)
      }.sort_by {|migration|
        migration.version
      }.each do |migration|
        @migrations[migration.version] = migration
      end

      ensure_version_table_exist
    end

  end
end
