require "./base"
require "./postgresql"
require "./sqlite"

module Migrate
  module Adapters
    # Factory for creating database adapters
    class Factory
      # Auto-detect and return the appropriate adapter for the given database
      def self.create(db : DB::Database) : Base
        # Try to detect based on the connection URI or driver name
        uri = db.@uri || ""

        case uri
        when /^postgres/, /^postgresql/
          PostgreSQL.new
        when /^sqlite/
          SQLite.new
        else
          # Fallback: try to detect from driver class name if available
          # This is a best-effort approach
          if defined?(PG) && db.is_a?(PG::Database)
            PostgreSQL.new
          elsif defined?(SQLite3) && db.responds_to?(:filename)
            SQLite.new
          else
            # Default to PostgreSQL for backward compatibility
            PostgreSQL.new
          end
        end
      end

      # Create adapter by explicit database type
      def self.create(database_type : String) : Base
        case database_type.downcase
        when "postgresql", "postgres", "pg"
          PostgreSQL.new
        when "sqlite", "sqlite3"
          SQLite.new
        else
          raise "Unsupported database type: #{database_type}"
        end
      end
    end
  end
end
