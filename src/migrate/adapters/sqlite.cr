require "./base"

module Migrate
  module Adapters
    # SQLite-specific adapter
    class SQLite < Base
      def create_version_table_sql(table : String, column : String) : String
        "CREATE TABLE IF NOT EXISTS #{table} (#{column} TEXT NOT NULL)"
      end

      def insert_initial_version_sql(table : String, column : String, value : String) : String
        "INSERT INTO #{table} (#{column}) VALUES ('#{value}')"
      end

      def update_version_sql(table : String, column : String, value : String) : String
        "UPDATE #{table} SET #{column} = '#{value}'"
      end

      def table_exists_sql(table : String) : String
        "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='#{table}'"
      end

      def create_checksums_table_sql(table : String) : String
        <<-SQL
        CREATE TABLE IF NOT EXISTS #{table} (
          version TEXT NOT NULL PRIMARY KEY,
          checksum TEXT NOT NULL,
          applied_at TEXT
        )
        SQL
      end

      def insert_checksum_sql(table : String) : String
        "INSERT INTO #{table} (version, checksum, applied_at) VALUES (?, ?, ?)"
      end

      def database_type : String
        "SQLite"
      end
    end
  end
end
