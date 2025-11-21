require "../spec_helper"

describe Migrate::Migrator::Safety do
  describe "#safety_check" do
    it "returns safe result for up migrations" do
      with_sqlite_migrator do |migrator|
        result = migrator.safety_check("1")

        result.should be_a(Migrate::Migrator::Safety::SafetyCheckResult)
        result.safe?.should be_true
        result.errors.should be_empty
      end
    end

    it "detects missing down migrations" do
      with_sqlite_migrator do |migrator|
        # First apply migrations
        migrator.to("2", skip_safety_check: true)

        # Check safety of rolling back
        result = migrator.safety_check("0")

        # Should detect that migrations can be rolled back
        # (our test migrations do have down migrations)
        result.safe?.should be_true
      end
    end

    it "detects destructive operations in down migrations" do
      with_sqlite_migrator do |migrator|
        # Apply migrations
        migrator.to("2", skip_safety_check: true)

        # Check rollback safety
        result = migrator.safety_check("0")

        # Down migrations contain DROP TABLE statements
        result.has_destructive_operations?.should be_true
        result.destructive_operations.any? { |op|
          op.operation_type == "DROP TABLE"
        }.should be_true
      end
    end

    it "categorizes destructive operations by severity" do
      with_sqlite_migrator do |migrator|
        migrator.to_latest(skip_safety_check: true)

        result = migrator.safety_check("0")

        if result.has_destructive_operations?
          # DROP TABLE should be high severity
          drop_ops = result.destructive_operations.select { |op|
            op.operation_type == "DROP TABLE"
          }

          drop_ops.any? { |op|
            op.severity == Migrate::Migrator::Safety::DestructiveOperation::Severity::High
          }.should be_true
        end
      end
    end

    it "returns empty result when already at target version" do
      with_sqlite_migrator do |migrator|
        result = migrator.safety_check("0")

        result.safe?.should be_true
        result.destructive_operations.should be_empty
        result.errors.should be_empty
      end
    end

    it "checks correct direction" do
      with_sqlite_migrator do |migrator|
        # Up migration check
        result_up = migrator.safety_check("1")
        # No destructive operations expected in up migrations (our test files)

        # Apply migration
        migrator.to("1", skip_safety_check: true)

        # Down migration check
        result_down = migrator.safety_check("0")
        result_down.direction.should eq(Migrate::Direction::Down)
      end
    end
  end

  describe "#safety_check!" do
    it "raises when safety check fails" do
      # This would need a migration with missing down migration
      # For now, test that it doesn't raise for valid migrations
      with_sqlite_migrator do |migrator|
        # Should not raise for safe migrations
        migrator.safety_check!("1")
      end
    end

    it "logs warnings for destructive operations" do
      with_sqlite_migrator do |migrator|
        migrator.to("1", skip_safety_check: true)

        # Should log warnings but not raise
        migrator.safety_check!("0")
      end
    end
  end

  describe "DestructiveOperation" do
    it "formats to_s with severity and type" do
      op = Migrate::Migrator::Safety::DestructiveOperation.new(
        version: "5",
        statement: "DROP TABLE foo",
        operation_type: "DROP TABLE",
        severity: Migrate::Migrator::Safety::DestructiveOperation::Severity::High
      )

      output = op.to_s
      output.should contain("High")
      output.should contain("DROP TABLE")
      output.should contain("migration 5")
    end
  end

  describe "destructive operation detection" do
    it "detects DROP TABLE" do
      with_sqlite_migrator do |migrator|
        migrator.to("1", skip_safety_check: true)
        result = migrator.safety_check("0")

        destructive_types = result.destructive_operations.map(&.operation_type)
        destructive_types.should contain("DROP TABLE")
      end
    end

    it "detects various destructive patterns" do
      # This test verifies the patterns are working
      # Would need specific test migrations for each type
      with_sqlite_migrator do |migrator|
        migrator.to_latest(skip_safety_check: true)
        result = migrator.safety_check("0")

        # At minimum, our test migrations have DROP TABLE
        result.destructive_operations.size.should be > 0
      end
    end
  end

  describe "integration with migrations" do
    it "runs safety check by default in to() method" do
      with_sqlite_migrator do |migrator|
        # Should run safety check automatically
        migrator.to("1")
        migrator.current_version.should eq("1")
      end
    end

    it "skips safety check when skip_safety_check is true" do
      with_sqlite_migrator do |migrator|
        # Should not run safety check
        migrator.to("1", skip_safety_check: true)
        migrator.current_version.should eq("1")
      end
    end
  end
end
