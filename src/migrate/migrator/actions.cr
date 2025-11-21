module Migrate
  class Migrator
    module Actions
      # Return actual DB version.
      def current_version
        query = @adapter.current_version_sql(@table, @column)
        # Cast to String since versions are now stored as strings
        @db.scalar(query).as(String)
      end

      # Return the next version as defined in migrations dir.
      def next_version
        current_index = all_versions.index(current_version) || raise("Current version #{current_version} is not found in migrations directory!")

        if current_index == all_versions.size - 1
          return nil # Means the current version is the last
        else
          return all_versions[current_index + 1]
        end
      end

      # Return previous version as defined in migrations dir.
      def previous_version
        current_index = all_versions.index(current_version) || raise("Current version #{current_version} is not found in migrations directory!")

        if current_index == 0
          return nil # Means the current version is the first
        else
          return all_versions[current_index - 1]
        end
      end

      # Return if current version is the latest one.
      def latest?
        next_version.nil?
      end

      # Apply all the migrations from current version to the last one.
      def to_latest
        to(all_versions.last)
      end

      # Migrate one step up.
      def up
        _next = next_version
        to(_next) if _next
      end

      # Migrate one step down.
      def down
        previous = previous_version
        to(previous) if previous
      end

      # Revert all migrations.
      def reset
        to(0)
      end

      # Revert all migrations and then migrate to current version.
      def redo
        current = current_version
        reset
        to(current)
      end
    end



    # Migrate to specific version.
    # TODO split into a "down" and an "up" via a macro
    def to(
      target_version : String | Int32 | Int64,
      skip_safety_check : Bool = false,
      enable_checksums : Bool = false
    )
      # Convert integer versions to strings for backward compatibility
      target_version = target_version.to_s if target_version.is_a?(Int32 | Int64)

      started_at = Time.utc
      current = current_version

      if target_version == current
        Log.info { "Already at version #{current}; aborting" }
        return nil
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

      # Perform safety check unless skipped
      unless skip_safety_check
        safety_check!(target_version, direction)
      end

      # Initialize checksums table if enabled
      if enable_checksums
        ensure_checksums_table_exist
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

      case direction
        when Direction::Up
          version_path = ([current] + applied_versions).join(" → ")
          Log.info { "Migrating up to version #{version_path}" }
        when Direction::Down
          version_path = ([current] + applied_versions.reverse + [target_version]).join(" → ")
          Log.info { "Migrating down to version #{version_path}" }
      end

      # Get migration objects for the versions to apply
      migrations_to_apply = applied_versions.map do |version|
        @migrations[version]
      end.compact

      migrations_to_apply.reverse! if direction == Direction::Down

      # Track stats for verbose logging
      migration_stats = [] of VerboseLogging::MigrationStats

      migrations_to_apply.each do |migration|
        migration_start_time = Time.utc

        # Check for top-level errors first
        if error = migration.error
          raise error
        end

        case direction
        when Direction::Up
          if error = migration.error_up
            raise error
          end

          version = migration.version.not_nil!
          queries = migration.queries_up
        when Direction::Down
          if error = migration.error_down
            raise error
          end

          # When migrating down, the target version is the one before this migration
          current_idx = all_versions.index(migration.version.not_nil!)
          raise("Migration version not found!") unless current_idx
          version = current_idx > 0 ? all_versions[current_idx - 1] : "0"
          queries = migration.queries_down
        end

        # Log migration start if verbose
        log_migration_start(migration.version.not_nil!, direction, queries.size)

        success = false
        error_occurred : Exception? = nil

        begin
          @db.transaction do |tx|
            if queries.empty?
              Log.warn { "No queries to run in migration file with version #{version}, applying anyway" }
            else
              queries.each_with_index do |query, idx|
                Log.debug { query }

                # Log statement execution if verbose
                log_statement_execution(query, idx, queries.size)

                # Execute with enhanced error handling
                begin
                  execute_statement_with_error_handling(
                    query,
                    idx,
                    queries.size,
                    migration.version.not_nil!,
                    migration.name,
                    direction,
                    tx.connection
                  )
                rescue e : EnhancedErrors::MigrationExecutionError
                  # Re-raise enhanced errors as-is
                  raise e
                rescue e : Exception
                  # Wrap other exceptions
                  raise EnhancedErrors::MigrationExecutionError.new(
                    migration_version: migration.version.not_nil!,
                    direction: direction,
                    original_error: e,
                    migration_name: migration.name,
                    statement_index: idx,
                    statement: query
                  )
                end
              end
            end

            Log.debug { update_version_query(version) }
            tx.connection.exec(update_version_query(version))

            # Store checksum if enabled and migrating up
            if enable_checksums && direction == Direction::Up
              checksum = calculate_migration_checksum(migration)
              store_checksum(migration.version.not_nil!, checksum)
            end
          end

          success = true
        rescue e : Exception
          error_occurred = e
          raise e
        ensure
          # Record stats for verbose logging
          duration = Time.utc - migration_start_time
          stats = VerboseLogging::MigrationStats.new(
            version: migration.version.not_nil!,
            direction: direction,
            statement_count: queries.size,
            duration: duration,
            success: success,
            error: error_occurred
          )
          migration_stats << stats
          log_migration_complete(stats)
        end
      end

      previous = current
      current = current_version

      total_duration = Time.utc - started_at
      Log.info { "Successfully migrated from version #{previous} to #{current} in #{TimeFormat.auto(total_duration)}" }

      # Log batch summary if verbose
      log_batch_summary(migration_stats) if migration_stats.any?

      return current
    end
  end
end
