require "../spec_helper"

describe Migrate::Migrator::Checksums do
  describe "#calculate_migration_checksum" do
    it "generates consistent checksums for same migration" do
      with_sqlite_migrator do |migrator|
        migration = migrator.migrations["1"]
        checksum1 = migrator.calculate_migration_checksum(migration)
        checksum2 = migrator.calculate_migration_checksum(migration)

        checksum1.should eq(checksum2)
        checksum1.should_not be_empty
      end
    end

    it "generates different checksums for different migrations" do
      with_sqlite_migrator do |migrator|
        migration1 = migrator.migrations["1"]
        migration2 = migrator.migrations["2"]

        checksum1 = migrator.calculate_migration_checksum(migration1)
        checksum2 = migrator.calculate_migration_checksum(migration2)

        checksum1.should_not eq(checksum2)
      end
    end
  end

  describe "#ensure_checksums_table_exist" do
    it "creates checksums table if it doesn't exist" do
      with_sqlite_migrator do |migrator|
        # Ensure table is created
        migrator.ensure_checksums_table_exist

        # Verify table exists by querying it
        count = migrator.@db.scalar("SELECT COUNT(*) FROM migrate_versions_checksums")
        count.should eq(0)
      end
    end

    it "doesn't fail if table already exists" do
      with_sqlite_migrator do |migrator|
        # Create table twice - should not fail
        migrator.ensure_checksums_table_exist
        migrator.ensure_checksums_table_exist

        # Should still work
        count = migrator.@db.scalar("SELECT COUNT(*) FROM migrate_versions_checksums")
        count.should eq(0)
      end
    end
  end

  describe "#store_checksum" do
    it "stores checksum for a migration" do
      with_sqlite_migrator do |migrator|
        migrator.ensure_checksums_table_exist

        checksum = "abc123"
        migrator.store_checksum("1", checksum)

        stored = migrator.get_stored_checksum("1")
        stored.should eq(checksum)
      end
    end

    it "updates checksum if already exists" do
      with_sqlite_migrator do |migrator|
        migrator.ensure_checksums_table_exist

        migrator.store_checksum("1", "checksum1")
        migrator.store_checksum("1", "checksum2")

        stored = migrator.get_stored_checksum("1")
        stored.should eq("checksum2")
      end
    end
  end

  describe "#get_stored_checksum" do
    it "returns nil for non-existent version" do
      with_sqlite_migrator do |migrator|
        migrator.ensure_checksums_table_exist

        stored = migrator.get_stored_checksum("999")
        stored.should be_nil
      end
    end

    it "retrieves stored checksum" do
      with_sqlite_migrator do |migrator|
        migrator.ensure_checksums_table_exist

        checksum = "test_checksum"
        migrator.store_checksum("5", checksum)

        stored = migrator.get_stored_checksum("5")
        stored.should eq(checksum)
      end
    end
  end

  describe "#validate_checksums" do
    it "passes when no migrations have been applied" do
      with_sqlite_migrator do |migrator|
        result = migrator.validate_checksums

        result.valid?.should be_true
        result.errors.should be_empty
      end
    end

    it "warns when applied migration has no stored checksum" do
      with_sqlite_migrator do |migrator|
        # Apply migration without checksums
        migrator.to("1", skip_safety_check: true)

        result = migrator.validate_checksums

        result.valid?.should be_true # Still valid, just a warning
        result.has_warnings?.should be_true
        result.warnings.should contain(/no stored checksum/)
      end
    end

    it "detects when applied migration has been modified" do
      with_sqlite_migrator do |migrator|
        migrator.ensure_checksums_table_exist

        # Store a fake checksum
        migrator.store_checksum("1", "wrong_checksum")

        # Apply the migration
        migrator.to("1", skip_safety_check: true)

        # Validate should detect mismatch
        result = migrator.validate_checksums

        result.valid?.should be_false
        result.errors.should_not be_empty
        result.modified_migrations.should contain("1")
      end
    end

    it "passes when checksums match" do
      with_sqlite_migrator do |migrator|
        # Apply migrations with checksums enabled
        migrator.to("1", skip_safety_check: true, enable_checksums: true)

        # Validation should pass
        result = migrator.validate_checksums

        result.valid?.should be_true
        result.errors.should be_empty
      end
    end
  end

  describe "#validate_checksums!" do
    it "raises error when checksums don't match" do
      with_sqlite_migrator do |migrator|
        migrator.ensure_checksums_table_exist
        migrator.store_checksum("1", "wrong_checksum")
        migrator.to("1", skip_safety_check: true)

        expect_raises(Migrate::Error, /checksum validation failed/) do
          migrator.validate_checksums!
        end
      end
    end

    it "doesn't raise when checksums are valid" do
      with_sqlite_migrator do |migrator|
        migrator.to("1", skip_safety_check: true, enable_checksums: true)

        # Should not raise
        migrator.validate_checksums!
      end
    end
  end

  describe "integration with migrations" do
    it "stores checksums when enable_checksums is true" do
      with_sqlite_migrator do |migrator|
        migrator.to("2", skip_safety_check: true, enable_checksums: true)

        # Both migration checksums should be stored
        migrator.get_stored_checksum("1").should_not be_nil
        migrator.get_stored_checksum("2").should_not be_nil
      end
    end

    it "doesn't store checksums when enable_checksums is false" do
      with_sqlite_migrator do |migrator|
        migrator.to("2", skip_safety_check: true, enable_checksums: false)

        # No checksums should be stored
        migrator.get_stored_checksum("1").should be_nil
        migrator.get_stored_checksum("2").should be_nil
      end
    end
  end
end
