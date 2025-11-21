module Migrate
  class Migrator
    module VerboseLogging
      # Configuration for verbose logging
      class VerboseConfig
        property enabled : Bool = false
        property log_statements : Bool = true
        property log_timing : Bool = true
        property statement_preview_length : Int32 = 100

        def initialize(
          @enabled = false,
          @log_statements = true,
          @log_timing = true,
          @statement_preview_length = 100
        )
        end
      end

      # Statistics for a single migration execution
      struct MigrationStats
        property version : String
        property direction : Direction
        property statement_count : Int32
        property duration : Time::Span
        property success : Bool
        property error : Exception?

        def initialize(
          @version : String,
          @direction : Direction,
          @statement_count : Int32,
          @duration : Time::Span,
          @success : Bool = true,
          @error : Exception? = nil
        )
        end

        def to_s(io : IO)
          status = success ? "SUCCESS" : "FAILED"
          io << "Migration #{version} (#{direction}): #{status} - "
          io << "#{statement_count} statements in #{format_duration(duration)}"
          if error
            io << " - Error: #{error.message}"
          end
        end

        private def format_duration(duration : Time::Span) : String
          if duration.total_milliseconds < 1000
            "#{duration.total_milliseconds.round(2)}ms"
          else
            "#{duration.total_seconds.round(2)}s"
          end
        end
      end

      # Get or create verbose config
      def verbose_config : VerboseConfig
        @verbose_config ||= VerboseConfig.new
      end

      # Enable verbose logging
      def enable_verbose_logging(
        log_statements : Bool = true,
        log_timing : Bool = true,
        statement_preview_length : Int32 = 100
      )
        config = verbose_config
        config.enabled = true
        config.log_statements = log_statements
        config.log_timing = log_timing
        config.statement_preview_length = statement_preview_length
      end

      # Disable verbose logging
      def disable_verbose_logging
        verbose_config.enabled = false
      end

      # Log a statement execution (internal use)
      protected def log_statement_execution(statement : String, index : Int32, total : Int32)
        return unless verbose_config.enabled && verbose_config.log_statements

        preview_length = verbose_config.statement_preview_length
        preview = if statement.size > preview_length
                    statement[0...preview_length] + "..."
                  else
                    statement
                  end

        # Clean up the preview (remove extra whitespace/newlines)
        preview = preview.gsub(/\s+/, " ").strip

        Log.info { "  [#{index + 1}/#{total}] Executing: #{preview}" }
      end

      # Log migration start
      protected def log_migration_start(version : String, direction : Direction, statement_count : Int32)
        return unless verbose_config.enabled

        Log.info { "Starting migration #{version} (#{direction}) - #{statement_count} statements" }
      end

      # Log migration completion
      protected def log_migration_complete(stats : MigrationStats)
        return unless verbose_config.enabled

        if stats.success
          Log.info { stats.to_s }
        else
          Log.error { stats.to_s }
        end
      end

      # Log a migration batch summary
      protected def log_batch_summary(stats : Array(MigrationStats))
        return unless verbose_config.enabled

        total_duration = stats.sum(&.duration)
        total_statements = stats.sum(&.statement_count)
        successful = stats.count(&.success)
        failed = stats.count { |s| !s.success }

        Log.info { "" }
        Log.info { "=" * 60 }
        Log.info { "Migration Batch Summary:" }
        Log.info { "  Total migrations: #{stats.size}" }
        Log.info { "  Successful: #{successful}" }
        Log.info { "  Failed: #{failed}" } if failed > 0
        Log.info { "  Total statements: #{total_statements}" }

        if verbose_config.log_timing
          formatted_duration = if total_duration.total_milliseconds < 1000
                                "#{total_duration.total_milliseconds.round(2)}ms"
                              else
                                "#{total_duration.total_seconds.round(2)}s"
                              end
          Log.info { "  Total duration: #{formatted_duration}" }
        end
        Log.info { "=" * 60 }
      end
    end
  end
end
