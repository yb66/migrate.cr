require "log"
require "time_format"
require "db"

require "./migration"
require "./migrator/actions"
require "./migrator/sql"

module Migrate
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
