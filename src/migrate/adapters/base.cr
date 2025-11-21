module Migrate
  module Adapters
    # Abstract base adapter for database-specific operations
    abstract class Base
      # Return the SQL to create the version tracking table
      abstract def create_version_table_sql(table : String, column : String) : String

      # Return the SQL to count rows in the version table
      def count_rows_sql(table : String, column : String) : String
        "SELECT COUNT(#{column}) FROM #{table}"
      end

      # Return the SQL to insert initial version
      abstract def insert_initial_version_sql(table : String, column : String, value : String) : String

      # Return the SQL to update the version
      abstract def update_version_sql(table : String, column : String, value : String) : String

      # Return the SQL to get current version
      def current_version_sql(table : String, column : String) : String
        "SELECT #{column} FROM #{table}"
      end

      # Return the database type name
      abstract def database_type : String
    end
  end
end
