module Migrate
  class Migrator
    module Safety
      # Safety check result
      struct SafetyCheckResult
        property safe : Bool
        property warnings : Array(String)
        property errors : Array(String)
        property destructive_operations : Array(DestructiveOperation)

        def initialize
          @safe = true
          @warnings = [] of String
          @errors = [] of String
          @destructive_operations = [] of DestructiveOperation
        end

        def safe?
          @safe && @errors.empty?
        end

        def has_warnings?
          !@warnings.empty?
        end

        def has_destructive_operations?
          !@destructive_operations.empty?
        end
      end

      # Represents a destructive operation found in a migration
      struct DestructiveOperation
        property version : String
        property statement : String
        property operation_type : String
        property severity : Severity

        enum Severity
          Low
          Medium
          High
          Critical
        end

        def initialize(
          @version : String,
          @statement : String,
          @operation_type : String,
          @severity : Severity
        )
        end

        def to_s(io : IO)
          io << "[#{severity}] #{operation_type} in migration #{version}"
        end
      end

      # Perform safety checks before migrating
      def safety_check(target_version : String | Int32 | Int64, direction : Direction? = nil) : SafetyCheckResult
        result = SafetyCheckResult.new

        # Convert integer versions to strings
        target_version = target_version.to_s if target_version.is_a?(Int32 | Int64)

        current = current_version

        # Determine direction if not provided
        if direction.nil?
          current_idx = all_versions.index(current)
          target_idx = all_versions.index(target_version)

          direction = if target_version == "0" || (target_idx && current_idx && target_idx < current_idx)
                        Direction::Down
                      else
                        Direction::Up
                      end
        end

        # Get migrations that would be applied
        current_idx = all_versions.index(current)
        target_idx = all_versions.index(target_version)

        applied_versions = if direction == Direction::Up
                             return result unless target_idx && current_idx
                             all_versions[current_idx + 1..target_idx]
                           else
                             if target_version == "0"
                               return result unless current_idx
                               all_versions[0..current_idx]
                             else
                               return result unless target_idx && current_idx
                               all_versions[target_idx + 1..current_idx]
                             end
                           end

        # Check each migration for safety issues
        applied_versions.each do |version|
          migration = @migrations[version]
          next unless migration

          # Check for missing down migrations when going down
          if direction == Direction::Down
            if migration.queries_down.empty?
              result.errors << "Migration #{version} has no down migration - cannot rollback!"
              result.safe = false
            else
              # Check for destructive operations in down migration
              destructive_ops = check_destructive_operations(
                migration.queries_down,
                version,
                DestructiveOperation::Severity::High
              )
              result.destructive_operations.concat(destructive_ops)

              if destructive_ops.any?
                result.warnings << "Migration #{version} contains destructive operations in down migration"
              end
            end
          else
            # Check for destructive operations in up migration
            destructive_ops = check_destructive_operations(
              migration.queries_up,
              version,
              DestructiveOperation::Severity::Medium
            )
            result.destructive_operations.concat(destructive_ops)
          end
        end

        result
      end

      # Check a list of queries for destructive operations
      private def check_destructive_operations(
        queries : Array(String),
        version : String,
        default_severity : DestructiveOperation::Severity
      ) : Array(DestructiveOperation)
        operations = [] of DestructiveOperation

        # Define destructive patterns with their severity
        patterns = {
          /DROP\s+DATABASE/i         => {type: "DROP DATABASE", severity: DestructiveOperation::Severity::Critical},
          /DROP\s+SCHEMA/i           => {type: "DROP SCHEMA", severity: DestructiveOperation::Severity::Critical},
          /DROP\s+TABLE/i            => {type: "DROP TABLE", severity: DestructiveOperation::Severity::High},
          /TRUNCATE/i                => {type: "TRUNCATE", severity: DestructiveOperation::Severity::High},
          /DELETE\s+FROM/i           => {type: "DELETE", severity: DestructiveOperation::Severity::Medium},
          /DROP\s+COLUMN/i           => {type: "DROP COLUMN", severity: DestructiveOperation::Severity::Medium},
          /DROP\s+INDEX/i            => {type: "DROP INDEX", severity: DestructiveOperation::Severity::Low},
          /DROP\s+CONSTRAINT/i       => {type: "DROP CONSTRAINT", severity: DestructiveOperation::Severity::Low},
          /ALTER\s+TABLE.*DROP/i     => {type: "ALTER TABLE DROP", severity: DestructiveOperation::Severity::Medium},
        }

        queries.each do |query|
          patterns.each do |pattern, info|
            if query =~ pattern
              operations << DestructiveOperation.new(
                version: version,
                statement: query,
                operation_type: info[:type],
                severity: info[:severity]
              )
              break # Only count each statement once
            end
          end
        end

        operations
      end

      # Perform safety check and raise if unsafe
      def safety_check!(target_version : String | Int32 | Int64, direction : Direction? = nil)
        result = safety_check(target_version, direction)

        unless result.safe?
          error_msg = "Safety check failed:\n"
          result.errors.each do |error|
            error_msg += "  ERROR: #{error}\n"
          end
          raise Error.new(error_msg)
        end

        if result.has_warnings?
          result.warnings.each do |warning|
            Log.warn { warning }
          end
        end

        if result.has_destructive_operations?
          Log.warn { "Found #{result.destructive_operations.size} destructive operation(s):" }
          result.destructive_operations.each do |op|
            Log.warn { "  #{op}" }
          end
        end
      end
    end
  end
end
