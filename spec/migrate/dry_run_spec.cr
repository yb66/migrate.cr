require "../spec_helper"

describe Migrate::Migrator::DryRun do
  describe "#dry_run" do
    it "returns a dry run result without applying migrations" do
      with_sqlite_migrator do |migrator|
        # Verify we're at version 0
        migrator.current_version.should eq("0")

        # Perform dry run to version 1
        result = migrator.dry_run("1")

        result.should be_a(Migrate::Migrator::DryRun::DryRunResult)
        result.current_version.should eq("0")
        result.target_version.should eq("1")
        result.direction.should eq(Migrate::Direction::Up)
        result.migrations.size.should eq(1)

        # Verify migrations were NOT actually applied
        migrator.current_version.should eq("0")
      end
    end

    it "shows all migrations that would be applied" do
      with_sqlite_migrator do |migrator|
        # Dry run to latest
        result = migrator.dry_run("10")

        result.migrations.size.should eq(3) # We have 3 test migrations
        result.migrations.map(&.version).should eq(["1", "2", "10"])
      end
    end

    it "detects destructive operations in down migrations" do
      with_sqlite_migrator do |migrator|
        # Apply all migrations first
        migrator.to_latest

        # Dry run down to 0
        result = migrator.dry_run("0")

        result.direction.should eq(Migrate::Direction::Down)

        # Check that destructive operations are detected
        result.migrations.any?(&.has_destructive_operations?).should be_true
      end
    end

    it "returns empty migrations for same version" do
      with_sqlite_migrator do |migrator|
        result = migrator.dry_run("0")

        result.migrations.should be_empty
        result.current_version.should eq("0")
        result.target_version.should eq("0")
      end
    end

    it "works for down migrations" do
      with_sqlite_migrator do |migrator|
        # Apply migrations first
        migrator.to("2")
        migrator.current_version.should eq("2")

        # Dry run back to version 1
        result = migrator.dry_run("1")

        result.direction.should eq(Migrate::Direction::Down)
        result.current_version.should eq("2")
        result.target_version.should eq("1")
        result.migrations.size.should eq(1)

        # Verify we're still at version 2
        migrator.current_version.should eq("2")
      end
    end

    it "provides statement counts" do
      with_sqlite_migrator do |migrator|
        result = migrator.dry_run("1")

        first_migration = result.migrations.first
        first_migration.statements.should_not be_empty
        first_migration.statements.size.should be > 0
      end
    end

    it "includes migration name if available" do
      with_sqlite_migrator do |migrator|
        result = migrator.dry_run("2")

        # Migration "2_create_bar" should have name "create_bar"
        bar_migration = result.migrations.find { |m| m.version == "2" }
        bar_migration.should_not be_nil
        bar_migration.try(&.name).should eq("create_bar")
      end
    end

    it "converts string result to readable format" do
      with_sqlite_migrator do |migrator|
        result = migrator.dry_run("1")
        output = result.to_s

        output.should contain("Dry Run Result")
        output.should contain("Current version: 0")
        output.should contain("Target version: 1")
        output.should contain("Direction: Up")
      end
    end
  end
end
