require "log"
require "time_format"
require "db"

require "./migration"
require "./migrator/actions"
require "./migrator/sql"
require "./migrator/validation"
require "./migrator/reporting"
require "./migrator/dry_run"
require "./migrator/checksums"
require "./migrator/safety"
require "./migrator/verbose_logging"
require "./migrator/enhanced_errors"
require "./adapters/factory"

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
    MIGRATION_FILE_REGEX = /
      (?<version>\d+)       # e.g. 1 or 19 etc
      (?: \_                # separator
        (?<name>\w[\w+\-])  # e.g. first_one or first-one
      )?                    # It's optional
      \.sql                 # Extension
    /x

    # The directory migrations were loaded from (nil if using array initialization)
    getter dir : Path | Nil

    # Hash of migrations keyed by version string, sorted by version
    getter migrations : Hash(String,Migration)
    getter adapter : Adapters::Base

    # Instance variables for modules
    @_verbose_config : VerboseLogging::VerboseConfig?

    # Return all migration versions sorted
    def all_versions : Array(String)
      @migrations.keys.sort
    end

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
      dir : String = "db/migrations",
      @table : String = "migrate_versions",
      @column : String = "version"
    )
      @dir = Path.new(dir).expand
      ensure_version_table_exist
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
      @column : String = "version",
      adapter : Adapters::Base? = nil
    )
      @adapter = adapter || Adapters::Factory.create(@db)
      dir_path = Path.new(dir).expand # does this raise?
      raise "Migrations dir does not exist" if dir_path.nil?
      raise "Migrations dir does not exist" unless Dir.exists? dir_path
      _dir = Dir.new(dir_path)
      @dir = dir_path
      @migrations = {} of String => Migration

      @db.scalar(query).as(Int32 | Int64)
    end

    # Return the next version as defined in migrations dir.
    def next_version
      current_index = all_versions.index(current_version) || raise("Current version #{current_version} is not found in migrations directory!")

      if current_index == all_versions.size - 1
        return nil # Means the current version is the last
      else
        return all_versions[current_index + 1]
      end
    end

    # Return previous version as defined in migrations dir.
    def previous_version
      current_index = all_versions.index(current_version) || raise("Current version #{current_version} is not found in migrations directory!")

      if current_index == 0
        return nil # Means the current version is the first
      else
        return all_versions[current_index - 1]
      end
    end

    # Return if current version is the latest one.
    def latest?
      next_version.nil?
    end

    # Apply all the migrations from current version to the last one.
    def to_latest
      to(all_versions.last)
    end

    # Migrate one step up.
    def up
      _next = next_version
      to(_next) if _next
    end

    # Migrate one step down.
    def down
      previous = previous_version
      to(previous) if previous
    end

    # Revert all migrations.
    def reset
      to(0)
    end

    # Revert all migrations and then migrate to current version.
    def redo
      current = current_version
      reset
      to(current)
    end

    # Migrate to specific version.
    # TODO split into a "down" and an "up" via a macro
    def to(target_version : Int32 | Int64)
      started_at = Time.utc
      current = current_version

      if target_version == current
        Log.info { "Already at version #{current}; aborting" }
        return nil
      end

      unless all_versions.includes?(target_version)
        raise("There is no version #{target_version} in migrations dir!")
      end

      direction = target_version > current ?
                    Direction::Up :
                    Direction::Down

      applied_versions = all_versions.to_a.select do |version|
        case direction
        when Direction::Up
          version > current && version <= target_version
        when Direction::Down
          version - 1 < current && version - 1 >= target_version
        end
      end

      case direction
        when Direction::Up
          version_number = applied_versions.dup
                                          .unshift(current.to_i64)
                                          .map(&.to_s)
                                          .join(" → ")
          Log.info { "Migrating up to version #{version_number}" }
        when Direction::Down
          # Add previous version to the list of applied versions,
          # turning "10 → 2" into "10 → 2 → 1"
          versions = applied_versions.dup.tap do |v|
            index = all_versions.index(v[0])
            if index && index > 0
              v.unshift(all_versions[index - 1])
            end
          end
          down_to = versions.reverse.map(&.to_s).join(" → ")
          Log.info { "Migrating down to version #{down_to}" }
      end

      applied_files = migrations.select do |filename|
        applied_versions.includes?(
          MIGRATION_FILE_REGEX.match(filename)
                              .not_nil!["version"]
                              .to_i64
        )
      end

      applied_files.reverse! if direction == Direction::Down

      migrations = applied_files.map { |path|
        Migration.new(File.join(@dir, path))
      }

      migrations.each do |migration|
        if error = migration.error
          raise error
        end

        case direction
        when Direction::Up
          if error = migration.error_up
            raise error
          end

          version = next_version
          queries = migration.queries_up
        when Direction::Down
          if error = migration.error_down
            raise error
          end

          version = previous_version
          queries = migration.queries_down
        end

        @db.transaction do |tx|
          if queries.not_nil!.empty?
            Log.warn { "No queries to run in migration file with version #{version}, applying anyway" }
          else
            queries.not_nil!.each do |query|
              Log.debug { query }
              tx.connection.exec(query)
            end
          end

          Log.debug { update_version_query(version) }
          tx.connection.exec(update_version_query(version))
        end
      end

      previous = current
      current = current_version

      Log.info { "Successfully migrated from version #{previous} to #{current} in #{TimeFormat.auto(Time.utc - started_at)}" }
      return current
    end

    private UPDATE_VERSION_SQL = <<-SQL
    UPDATE %{table} SET %{column} = %{value}
    SQL

    protected def update_version_query(version)
      UPDATE_VERSION_SQL % {
        table:  @table,
        column: @column,
        value:  version,
      }
    end

    # Return a sorted array of versions extracted from filenames in migrations dir. Contains 0 version which means no migrations.
    protected def all_versions
      migrations.map do |filename|
        MIGRATION_FILE_REGEX.match(filename).not_nil!["version"].to_i64
      end.unshift(0i64)
    end

    # Return sorted array of migration file names.
    protected def migrations
      Dir.new(@dir).entries.select { |filename|
        MIGRATION_FILE_REGEX.match(filename)
      }.sort_by {|filename|
        MIGRATION_FILE_REGEX.match(filename)
                            .not_nil!["version"]
                            .to_i64
      }
    end

    private CREATE_VERSION_TABLE_SQL = <<-SQL
    CREATE TABLE IF NOT EXISTS %{table} (%{column} BIGINT NOT NULL)
    SQL

    private COUNT_ROWS_SQL = <<-SQL
    SELECT COUNT(%{column}) FROM %{table}
    SQL

    private INSERT_SQL = <<-SQL
    INSERT INTO %{table} (%{column}) VALUES (%{value})
    SQL

    protected def ensure_version_table_exist
      table_query = CREATE_VERSION_TABLE_SQL % {
        table:  @table,
        column: @column,
      }

      count_query = COUNT_ROWS_SQL % {
        table:  @table,
        column: @column,
      }

      insert_query = INSERT_SQL % {
        table:  @table,
        column: @column,
        value:  0,
      }

      Log.debug { table_query }
      @db.exec(table_query)

      Log.debug { count_query }
      count = @db.scalar(count_query).as(Int64)

      if count == 0
        Log.debug { insert_query }
        @db.exec(insert_query)
      end
    end
  end
end
