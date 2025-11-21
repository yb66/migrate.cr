require "digest/sha256"

module Migrate
  class Migrator
    module Checksums
      # Represents checksum information for a migration
      struct MigrationChecksum
        property version : String
        property checksum : String
        property applied_at : Time?

        def initialize(@version : String, @checksum : String, @applied_at : Time? = nil)
        end
      end

      # Result of a checksum validation
      struct ChecksumValidationResult
        property valid : Bool
        property errors : Array(String)
        property warnings : Array(String)
        property modified_migrations : Array(String)

        def initialize
          @valid = true
          @errors = [] of String
          @warnings = [] of String
          @modified_migrations = [] of String
        end

        def valid?
          @valid && @errors.empty?
        end

        def has_warnings?
          !@warnings.empty?
        end
      end

      # Calculate checksum for a migration's content
      def calculate_migration_checksum(migration : Migration) : String
        # Combine all statements (up and down) for checksum
        content = migration.queries_up.join("\n") + "\n" + migration.queries_down.join("\n")
        Digest::SHA256.hexdigest(content)
      end

      # Ensure the checksums table exists
      def ensure_checksums_table_exist
        table_name = "#{@table}_checksums"

        # Check if table exists
        table_exists_sql = @adapter.table_exists_sql(table_name)
        exists = @db.scalar(table_exists_sql).as(Int64 | Int32) > 0

        unless exists
          create_sql = @adapter.create_checksums_table_sql(table_name)
          @db.exec(create_sql)
          Log.debug { "Created checksums table: #{table_name}" }
        end
      end

      # Store checksum for a migration version
      def store_checksum(version : String, checksum : String)
        table_name = "#{@table}_checksums"

        # Delete existing checksum if any
        delete_sql = "DELETE FROM #{table_name} WHERE version = ?"
        @db.exec(delete_sql, version)

        # Insert new checksum
        insert_sql = @adapter.insert_checksum_sql(table_name)
        @db.exec(insert_sql, version, checksum, Time.utc)

        Log.debug { "Stored checksum for migration #{version}: #{checksum}" }
      end

      # Get stored checksum for a version
      def get_stored_checksum(version : String) : String?
        table_name = "#{@table}_checksums"

        query = "SELECT checksum FROM #{table_name} WHERE version = ? LIMIT 1"
        result = @db.query_one?(query, version, as: String)
        result
      rescue DB::NoResultsError
        nil
      end

      # Get all stored checksums
      def get_all_checksums : Hash(String, MigrationChecksum)
        table_name = "#{@table}_checksums"
        checksums = {} of String => MigrationChecksum

        query = "SELECT version, checksum, applied_at FROM #{table_name}"
        @db.query(query) do |rs|
          rs.each do
            version = rs.read(String)
            checksum = rs.read(String)
            applied_at = rs.read(Time?)
            checksums[version] = MigrationChecksum.new(version, checksum, applied_at)
          end
        end

        checksums
      rescue e : Exception
        Log.warn { "Failed to retrieve checksums: #{e.message}" }
        {} of String => MigrationChecksum
      end

      # Validate that applied migrations haven't been modified
      def validate_checksums : ChecksumValidationResult
        result = ChecksumValidationResult.new

        begin
          ensure_checksums_table_exist
        rescue e : Exception
          result.errors << "Failed to ensure checksums table exists: #{e.message}"
          result.valid = false
          return result
        end

        stored_checksums = get_all_checksums

        # Check each applied migration
        current = current_version
        current_idx = all_versions.index(current)

        if current_idx
          applied_versions = all_versions[0..current_idx]

          applied_versions.each do |version|
            migration = @migrations[version]
            next unless migration

            # Calculate current checksum
            current_checksum = calculate_migration_checksum(migration)

            # Get stored checksum
            stored = stored_checksums[version]?

            if stored.nil?
              # No checksum stored yet - this is a warning, not an error
              result.warnings << "Migration #{version} has no stored checksum"
            elsif stored.checksum != current_checksum
              # Checksum mismatch - migration was modified!
              result.errors << "Migration #{version} has been modified since it was applied!"
              result.errors << "  Stored checksum:  #{stored.checksum}"
              result.errors << "  Current checksum: #{current_checksum}"
              result.modified_migrations << version
              result.valid = false
            end
          end
        elsif current != "0"
          result.warnings << "Current version #{current} not found in migrations"
        end

        result
      end

      # Validate checksums and raise if invalid
      def validate_checksums!
        result = validate_checksums

        unless result.valid?
          error_msg = "Migration checksum validation failed:\n"
          result.errors.each do |error|
            error_msg += "  - #{error}\n"
          end
          raise Error.new(error_msg)
        end

        if result.has_warnings?
          result.warnings.each do |warning|
            Log.warn { warning }
          end
        end
      end
    end
  end
end
