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

      def database_type : String
        "PostgreSQL"
      end
    end
  end
end
