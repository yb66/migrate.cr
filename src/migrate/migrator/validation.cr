module Migrate
  class Migrator
    module Validation
      # Validation result for a migration check
      struct ValidationResult
        property errors : Array(String)
        property warnings : Array(String)

        def initialize
          @errors = [] of String
          @warnings = [] of String
        end

        def valid?
          @errors.empty?
        end

        def has_warnings?
          !@warnings.empty?
        end
      end

      # Validate all migrations before running
      # Returns a ValidationResult with any errors or warnings found
      def validate_migrations : ValidationResult
        result = ValidationResult.new

        # Check for duplicate version numbers
        version_counts = Hash(String, Int32).new(0)
        @migrations.each do |version, migration|
          version_counts[version] += 1
        end

        version_counts.each do |version, count|
          if count > 1
            result.errors << "Duplicate version number found: #{version} appears #{count} times"
          end
        end

        # Validate each migration can be parsed
        @migrations.each do |version, migration|
          begin
            # Migration is already parsed, but we can check for errors
            if migration.statements.empty?
              result.warnings << "Migration #{version} has no statements"
            end

            # Check for missing down migrations
            if migration.queries_down.empty? && !migration.queries_up.empty?
              result.warnings << "Migration #{version} has no down migration (irreversible)"
            end
          rescue e : Exception
            result.errors << "Migration #{version} failed to parse: #{e.message}"
          end
        end

        # Validate version ordering (versions should be sortable)
        begin
          sorted_versions = all_versions
          if sorted_versions.empty?
            result.warnings << "No migrations found"
          end
        rescue e : Exception
          result.errors << "Failed to sort migration versions: #{e.message}"
        end

        result
      end

      # Validate that we can migrate to a specific version
      # Checks that all migrations in the path are valid
      def validate_migration_path(target_version : String) : ValidationResult
        result = ValidationResult.new

        # First validate all migrations
        all_valid = validate_migrations
        result.errors.concat(all_valid.errors)
        result.warnings.concat(all_valid.warnings)

        # Check that target version exists (or is "0")
        unless target_version == "0" || all_versions.includes?(target_version)
          result.errors << "Target version #{target_version} not found in migrations"
          return result
        end

        # If already at target, nothing to validate
        current = current_version
        if current == target_version
          result.warnings << "Already at version #{target_version}"
          return result
        end

        # Determine direction
        current_idx = all_versions.index(current)
        unless current_idx
          result.errors << "Current version #{current} not found in migrations"
          return result
        end

        target_idx = all_versions.index(target_version)

        # Get migrations that would be applied
        migrations_to_check = if target_version == "0" || (target_idx && target_idx < current_idx)
                                # Migrating down
                                if target_version == "0"
                                  all_versions[0..current_idx]
                                else
                                  all_versions[target_idx + 1..current_idx]
                                end
                              else
                                # Migrating up
                                return result unless target_idx
                                all_versions[current_idx + 1..target_idx]
                              end

        # Check each migration in the path
        migrations_to_check.each do |version|
          migration = @migrations[version]
          next unless migration

          if target_version == "0" || (target_idx && target_idx < current_idx)
            # Check down migrations
            if migration.queries_down.empty?
              result.warnings << "Migration #{version} has no down migration"
            end
          else
            # Check up migrations
            if migration.queries_up.empty?
              result.warnings << "Migration #{version} has no up migration"
            end
          end
        end

        result
      end
    end
  end
end
