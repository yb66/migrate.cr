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
    def to(target_version : String | Int32 | Int64)
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

      migrations_to_apply.each do |migration|
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

        @db.transaction do |tx|
          if queries.empty?
            Log.warn { "No queries to run in migration file with version #{version}, applying anyway" }
          else
            queries.each do |query|
              Log.debug { query }
              tx.connection.exec(query)
            end
          end

          Log.debug { update_version_query(version) }
          tx.connection.exec(update_version_query(version))
        end
      end

      previous = current
      current = current_version

      Log.info { "Successfully migrated from version #{previous} to #{current} in #{TimeFormat.auto(Time.utc - started_at)}" }
      return current
    end
  end
end
