require "../spec_helper"

describe Migrate::Migrator::VerboseLogging do
  describe "#enable_verbose_logging" do
    it "enables verbose logging" do
      with_sqlite_migrator do |migrator|
        migrator.enable_verbose_logging

        config = migrator.verbose_config
        config.enabled.should be_true
        config.log_statements.should be_true
        config.log_timing.should be_true
      end
    end

    it "accepts custom configuration" do
      with_sqlite_migrator do |migrator|
        migrator.enable_verbose_logging(
          log_statements: false,
          log_timing: true,
          statement_preview_length: 50
        )

        config = migrator.verbose_config
        config.enabled.should be_true
        config.log_statements.should be_false
        config.log_timing.should be_true
        config.statement_preview_length.should eq(50)
      end
    end
  end

  describe "#disable_verbose_logging" do
    it "disables verbose logging" do
      with_sqlite_migrator do |migrator|
        migrator.enable_verbose_logging
        migrator.disable_verbose_logging

        config = migrator.verbose_config
        config.enabled.should be_false
      end
    end
  end

  describe "VerboseConfig" do
    it "has sensible defaults" do
      config = Migrate::Migrator::VerboseLogging::VerboseConfig.new

      config.enabled.should be_false
      config.log_statements.should be_true
      config.log_timing.should be_true
      config.statement_preview_length.should eq(100)
    end
  end

  describe "MigrationStats" do
    it "creates stats with all required info" do
      stats = Migrate::Migrator::VerboseLogging::MigrationStats.new(
        version: "5",
        direction: Migrate::Direction::Up,
        statement_count: 10,
        duration: Time::Span.new(seconds: 1, nanoseconds: 500_000_000),
        success: true
      )

      stats.version.should eq("5")
      stats.direction.should eq(Migrate::Direction::Up)
      stats.statement_count.should eq(10)
      stats.success.should be_true
      stats.error.should be_nil
    end

    it "formats to_s with duration in milliseconds for fast migrations" do
      stats = Migrate::Migrator::VerboseLogging::MigrationStats.new(
        version: "1",
        direction: Migrate::Direction::Up,
        statement_count: 5,
        duration: Time::Span.new(nanoseconds: 500_000_000), # 500ms
        success: true
      )

      output = stats.to_s
      output.should contain("SUCCESS")
      output.should contain("5 statements")
      output.should contain("ms")
    end

    it "formats to_s with duration in seconds for slow migrations" do
      stats = Migrate::Migrator::VerboseLogging::MigrationStats.new(
        version: "2",
        direction: Migrate::Direction::Down,
        statement_count: 3,
        duration: Time::Span.new(seconds: 2),
        success: true
      )

      output = stats.to_s
      output.should contain("SUCCESS")
      output.should contain("3 statements")
      output.should contain("s")
    end

    it "includes error info when migration failed" do
      error = Exception.new("Test error")
      stats = Migrate::Migrator::VerboseLogging::MigrationStats.new(
        version: "3",
        direction: Migrate::Direction::Up,
        statement_count: 2,
        duration: Time::Span.new(nanoseconds: 100_000_000),
        success: false,
        error: error
      )

      output = stats.to_s
      output.should contain("FAILED")
      output.should contain("Test error")
    end
  end

  describe "integration with migrations" do
    it "logs verbose output when enabled" do
      with_sqlite_migrator do |migrator|
        migrator.enable_verbose_logging

        # Run migration - should log verbose output
        migrator.to("1", skip_safety_check: true)

        migrator.current_version.should eq("1")
      end
    end

    it "doesn't log verbose output when disabled" do
      with_sqlite_migrator do |migrator|
        # Verbose logging disabled by default

        migrator.to("1", skip_safety_check: true)

        migrator.current_version.should eq("1")
      end
    end
  end
end
