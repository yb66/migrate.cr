require "./base"

module Migrate
  module Adapters
    # PostgreSQL-specific adapter
    class PostgreSQL < Base
      def create_version_table_sql(table : String, column : String) : String
        "CREATE TABLE IF NOT EXISTS #{table} (#{column} VARCHAR(255) NOT NULL)"
      end

      def insert_initial_version_sql(table : String, column : String, value : String) : String
        "INSERT INTO #{table} (#{column}) VALUES ('#{value}')"
      end

      def update_version_sql(table : String, column : String, value : String) : String
        "UPDATE #{table} SET #{column} = '#{value}'"
      end

      def table_exists_sql(table : String) : String
        "SELECT COUNT(*) FROM information_schema.tables WHERE table_name = '#{table}'"
      end

      def create_checksums_table_sql(table : String) : String
        <<-SQL
        CREATE TABLE IF NOT EXISTS #{table} (
          version VARCHAR(255) NOT NULL PRIMARY KEY,
          checksum VARCHAR(64) NOT NULL,
          applied_at TIMESTAMP
        )
        SQL
      end

      def insert_checksum_sql(table : String) : String
        "INSERT INTO #{table} (version, checksum, applied_at) VALUES (?, ?, ?)"
      end

      def database_type : String
        "PostgreSQL"
      end
    end
  end
end
