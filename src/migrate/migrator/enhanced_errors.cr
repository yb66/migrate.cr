module Migrate
  class Migrator
    module EnhancedErrors
      # Enhanced migration error with detailed context
      class MigrationExecutionError < Error
        property migration_version : String
        property migration_name : String?
        property statement_index : Int32?
        property statement : String?
        property direction : Direction
        property original_error : Exception

        def initialize(
          @migration_version : String,
          @direction : Direction,
          @original_error : Exception,
          @migration_name : String? = nil,
          @statement_index : Int32? = nil,
          @statement : String? = nil
        )
          message = build_error_message
          super(message)
        end

        private def build_error_message : String
          msg = String.build do |io|
            io << "Migration execution failed\n"
            io << "  Version: #{migration_version}"
            io << " (#{migration_name})" if migration_name
            io << "\n"
            io << "  Direction: #{direction}\n"

            if statement_index && statement
              io << "  Failed at statement #{statement_index + 1}\n"
              preview = statement.size > 200 ? statement[0...200] + "..." : statement
              io << "  Statement: #{preview}\n"
            end

            io << "  Error: #{original_error.class.name}\n"
            io << "  Message: #{original_error.message}\n"

            if original_error.backtrace?
              io << "\nBacktrace:\n"
              original_error.backtrace?.try &.each do |line|
                io << "  #{line}\n"
              end
            end
          end
          msg
        end

        def to_s(io : IO)
          io << message
        end
      end

      # Wrapper to execute a statement with enhanced error handling
      protected def execute_statement_with_error_handling(
        statement : String,
        statement_index : Int32,
        total_statements : Int32,
        migration_version : String,
        migration_name : String?,
        direction : Direction,
        connection : DB::Connection
      )
        begin
          connection.exec(statement)
        rescue e : Exception
          raise MigrationExecutionError.new(
            migration_version: migration_version,
            direction: direction,
            original_error: e,
            migration_name: migration_name,
            statement_index: statement_index,
            statement: statement
          )
        end
      end
    end
  end
end
