module Migrate
  class Migrator
    module Reporting
      # Migration status information
      struct Status
        property current_version : String
        property latest_version : String?
        property pending_migrations : Array(String)
        property applied_migrations : Array(String)
        property total_migrations : Int32

        def initialize(
          @current_version : String,
          @latest_version : String?,
          @pending_migrations : Array(String),
          @applied_migrations : Array(String),
          @total_migrations : Int32
        )
        end

        def to_s(io : IO)
          io << "Current version: #{current_version}\n"
          io << "Latest version: #{latest_version || "none"}\n"
          io << "Total migrations: #{total_migrations}\n"
          io << "Applied: #{applied_migrations.size}, Pending: #{pending_migrations.size}\n"

          if pending_migrations.any?
            io << "\nPending migrations:\n"
            pending_migrations.each do |version|
              io << "  - #{version}\n"
            end
          end

          if applied_migrations.any?
            io << "\nApplied migrations:\n"
            applied_migrations.each do |version|
              io << "  - #{version}\n"
            end
          end
        end
      end

      # Get current migration status
      def status : Status
        current = current_version
        latest = all_versions.last?
        all_vers = all_versions

        current_idx = all_vers.index(current)

        if current_idx
          applied = all_vers[0..current_idx]
          pending = all_vers[current_idx + 1..-1]? || [] of String
        elsif current == "0"
          applied = [] of String
          pending = all_vers
        else
          # Current version not found in migrations - unusual state
          applied = [] of String
          pending = all_vers
        end

        Status.new(
          current_version: current,
          latest_version: latest,
          pending_migrations: pending,
          applied_migrations: applied,
          total_migrations: all_vers.size
        )
      end

      # Print status to logger
      def print_status
        s = status
        Log.info { "Migration Status:" }
        Log.info { "  Current version: #{s.current_version}" }
        Log.info { "  Latest version: #{s.latest_version || "none"}" }
        Log.info { "  Total migrations: #{s.total_migrations}" }
        Log.info { "  Applied: #{s.applied_migrations.size}, Pending: #{s.pending_migrations.size}" }

        if s.pending_migrations.any?
          Log.info { "  Pending migrations:" }
          s.pending_migrations.each do |version|
            migration = @migrations[version]
            name = migration.try(&.name) || version
            Log.info { "    - #{version}_#{name}" }
          end
        end
      end
    end
  end
end
