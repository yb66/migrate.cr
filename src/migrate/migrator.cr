require "log"
require "time_format"
require "db"
require "sqlite3"

require "./migration"
require "./migrator/actions"
require "./migrator/sql"

module Migrate
  class Migrator
    include Migrate::Migrator::Actions
    include Migrate::Migrator::SQL

    getter dir : Path | Nil
    getter migrations : Hash(String,Migration)


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
