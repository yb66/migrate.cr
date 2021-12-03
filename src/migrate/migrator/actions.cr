module Migrate
  class Migrator
    module Actions
      # Return actual DB version.
      def current_version
        query = "SELECT %{column} FROM %{table}" % {
          column: @column,
          table:  @table,
        }
        # TODO does it really need the casting?
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
    def to(target_version : Int32 | Int64)
      started_at = Time.utc
      current = current_version

      if target_version == current
        Log.info { "Already at version #{current}; aborting" }
        return nil
      end

      unless all_versions.includes?(target_version)
        raise("There is no version #{target_version} in migrations dir!")
      end

      direction = target_version > current ?
                    Direction::Up :
                    Direction::Down

      applied_versions = all_versions.to_a.select do |version|
        case direction
        when Direction::Up
          version > current && version <= target_version
        when Direction::Down
          version - 1 < current && version - 1 >= target_version
        end
      end

      case direction
        when Direction::Up
          version_number = applied_versions.dup
                                          .unshift(current.to_i64)
                                          .map(&.to_s)
                                          .join(" → ")
          Log.info { "Migrating up to version #{version_number}" }
        when Direction::Down
          # Add previous version to the list of applied versions,
          # turning "10 → 2" into "10 → 2 → 1"
          versions = applied_versions.dup.tap do |v|
            index = all_versions.index(v[0])
            if index && index > 0
              v.unshift(all_versions[index - 1])
            end
          end
          down_to = versions.reverse.map(&.to_s).join(" → ")
          Log.info { "Migrating down to version #{down_to}" }
      end

      applied_files = migrations.select do |filename|
        applied_versions.includes?(
          MIGRATION_FILE_REGEX.match(filename)
                              .not_nil!["version"]
                              .to_i64
        )
      end

      applied_files.reverse! if direction == Direction::Down

      migrations = applied_files.map { |path|
        Migration.new(File.join(@dir, path))
      }

      migrations.each do |migration|
        if error = migration.error
          raise error
        end

        case direction
        when Direction::Up
          if error = migration.error_up
            raise error
          end

          version = next_version
          queries = migration.queries_up
        when Direction::Down
          if error = migration.error_down
            raise error
          end

          version = previous_version
          queries = migration.queries_down
        end

        @db.transaction do |tx|
          if queries.not_nil!.empty?
            Log.warn { "No queries to run in migration file with version #{version}, applying anyway" }
          else
            queries.not_nil!.each do |query|
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
