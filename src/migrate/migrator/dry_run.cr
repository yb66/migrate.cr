module Migrate
  class Migrator
    module DryRun
      # Represents the result of a dry run operation
      struct DryRunResult
        property target_version : String
        property current_version : String
        property direction : Direction
        property migrations : Array(DryRunMigration)

        def initialize(
          @target_version : String,
          @current_version : String,
          @direction : Direction,
          @migrations : Array(DryRunMigration)
        )
        end

        def to_s(io : IO)
          io << "Dry Run Result:\n"
          io << "  Current version: #{current_version}\n"
          io << "  Target version: #{target_version}\n"
          io << "  Direction: #{direction}\n"
          io << "  Migrations to apply: #{migrations.size}\n\n"

          migrations.each do |migration|
            io << "Migration #{migration.version}:\n"
            io << "  Statements: #{migration.statements.size}\n"
            migration.statements.each_with_index do |stmt, idx|
              preview = stmt.size > 80 ? stmt[0..77] + "..." : stmt
              io << "    #{idx + 1}. #{preview}\n"
            end
            io << "\n"
          end
        end
      end

      # Represents a migration that would be executed in a dry run
      struct DryRunMigration
        property version : String
        property name : String?
        property statements : Array(String)
        property destructive_operations : Array(String)

        def initialize(
          @version : String,
          @name : String?,
          @statements : Array(String),
          @destructive_operations : Array(String) = [] of String
        )
        end

        def has_destructive_operations?
          !destructive_operations.empty?
        end
      end

      # Perform a dry run of a migration to a target version
      # Returns a DryRunResult showing what would be executed
      def dry_run(target_version : String | Int32 | Int64) : DryRunResult
        # Convert integer versions to strings for backward compatibility
        target_version = target_version.to_s if target_version.is_a?(Int32 | Int64)

        current = current_version

        if target_version == current
          return DryRunResult.new(
            target_version: target_version,
            current_version: current,
            direction: Direction::Up,
            migrations: [] of DryRunMigration
          )
        end

        # Version "0" is special - it means no migrations applied
        unless target_version == "0" || all_versions.includes?(target_version)
          raise("There is no version #{target_version} in migrations dir!")
        end

        # Determine direction by comparing position in sorted versions array
        current_idx = all_versions.index(current)
        raise("Version #{current} not found in migrations!") unless current_idx

        # target_idx is nil when target_version is "0" (initial state)
        target_idx = all_versions.index(target_version)

        direction = if target_version == "0" || (target_idx && target_idx < current_idx)
                      Direction::Down
                    else
                      Direction::Up
                    end

        # Select versions to apply based on direction
        applied_versions = if direction == Direction::Up
                             raise("Target index not found!") unless target_idx
                             all_versions[current_idx + 1..target_idx]
                           else
                             # When migrating down to "0", apply all migrations from current down to first
                             if target_version == "0"
                               all_versions[0..current_idx]
                             else
                               raise("Target index not found!") unless target_idx
                               all_versions[target_idx + 1..current_idx]
                             end
                           end

        # Get migration objects for the versions to apply
        migrations_to_apply = applied_versions.map do |version|
          @migrations[version]
        end.compact

        migrations_to_apply.reverse! if direction == Direction::Down

        # Build dry run migration list
        dry_run_migrations = migrations_to_apply.map do |migration|
          queries = case direction
                    when Direction::Up
                      migration.queries_up
                    when Direction::Down
                      migration.queries_down
                    end

          # Detect destructive operations
          destructive_ops = detect_destructive_operations(queries)

          DryRunMigration.new(
            version: migration.version.not_nil!,
            name: migration.name,
            statements: queries,
            destructive_operations: destructive_ops
          )
        end

        DryRunResult.new(
          target_version: target_version,
          current_version: current,
          direction: direction,
          migrations: dry_run_migrations
        )
      end

      # Detect potentially destructive SQL operations
      private def detect_destructive_operations(queries : Array(String)) : Array(String)
        destructive = [] of String
        destructive_patterns = [
          /DROP\s+TABLE/i,
          /DROP\s+DATABASE/i,
          /DROP\s+SCHEMA/i,
          /TRUNCATE/i,
          /DELETE\s+FROM/i,
          /DROP\s+COLUMN/i,
          /DROP\s+INDEX/i,
        ]

        queries.each do |query|
          destructive_patterns.each do |pattern|
            if query =~ pattern
              destructive << query
              break
            end
          end
        end

        destructive
      end
    end
  end
end
