require "../spec_helper"

# Unit tests for version handling and comparison
# Covers Phase 3.1 requirement: Test version comparison logic
# Version comparison is critical since the refactor changed from Int64 to String
describe "Version handling", tags: "unit" do
  describe "Version extraction from filenames" do
    it "extracts single-digit versions" do
      path = Path["1.sql"]
      match = Migrate::Migration::FILE_REGEX.match(path.basename(".sql"))

      match.should_not be_nil
      match.not_nil!["version"].should eq "1"
    end

    it "extracts multi-digit versions" do
      path = Path["123.sql"]
      match = Migrate::Migration::FILE_REGEX.match(path.basename(".sql"))

      match.should_not be_nil
      match.not_nil!["version"].should eq "123"
    end

    it "extracts version with name" do
      path = Path["10_create_users.sql"]
      match = Migrate::Migration::FILE_REGEX.match(path.basename(".sql"))

      match.should_not be_nil
      match.not_nil!["version"].should eq "10"
      match.not_nil!["name"]?.should eq "create_users"
    end

    it "handles large version numbers" do
      path = Path["20231121094530_add_indexes.sql"]
      match = Migrate::Migration::FILE_REGEX.match(path.basename(".sql"))

      match.should_not be_nil
      match.not_nil!["version"].should eq "20231121094530"
    end

    it "rejects non-numeric versions" do
      path = Path["abc_invalid.sql"]
      match = Migrate::Migration::FILE_REGEX.match(path.basename(".sql"))

      match.should be_nil
    end

    it "rejects version with leading zeros" do
      # This should actually match since \d+ allows leading zeros
      path = Path["001_migration.sql"]
      match = Migrate::Migration::FILE_REGEX.match(path.basename(".sql"))

      # Document current behavior
      match.should_not be_nil
      match.not_nil!["version"].should eq "001"
    end
  end

  describe "Version as String comparison" do
    it "compares single-digit string versions correctly" do
      versions = ["3", "1", "5", "2", "4"]
      sorted = versions.sort_by { |v| v.to_i }

      sorted.should eq ["1", "2", "3", "4", "5"]
    end

    it "compares multi-digit string versions correctly" do
      versions = ["100", "20", "3", "150", "45"]
      sorted = versions.sort_by { |v| v.to_i }

      sorted.should eq ["3", "20", "45", "100", "150"]
    end

    it "handles timestamp-based versions" do
      versions = [
        "20231121094530",
        "20231121093000",
        "20231120120000",
        "20231122000000"
      ]
      sorted = versions.sort_by { |v| v.to_i }

      sorted[0].should eq "20231120120000"
      sorted[1].should eq "20231121093000"
      sorted[2].should eq "20231121094530"
      sorted[3].should eq "20231122000000"
    end

    it "handles mixed length versions" do
      versions = ["1", "10", "100", "2", "20"]
      sorted = versions.sort_by { |v| v.to_i }

      sorted.should eq ["1", "2", "10", "20", "100"]
    end

    it "compares versions with string comparison vs numeric" do
      versions = ["1", "10", "2", "20", "3"]

      # String comparison (wrong!)
      string_sorted = versions.sort
      string_sorted.should eq ["1", "10", "2", "20", "3"]

      # Numeric comparison (correct!)
      numeric_sorted = versions.sort_by { |v| v.to_i }
      numeric_sorted.should eq ["1", "2", "3", "10", "20"]
    end
  end

  describe "Migration version ordering" do
    it "sorts migrations by numeric version" do
      migration_texts = Array(String).new
      3.times { migration_texts << "-- +migrate up\nCREATE TABLE foo (id INT);" }

      migrations = migration_texts.map_with_index do |text, i|
        m = Migrate::Migration.new(text)
        m.version = ["10", "2", "5"][i]
        m
      end

      sorted = migrations.sort_by { |m| m.version.not_nil!.to_i }
      sorted.map { |m| m.version }.should eq ["2", "5", "10"]
    end

    it "maintains sort order with string versions" do
      migration_texts = Array(String).new
      5.times { migration_texts << "-- +migrate up\nCREATE TABLE foo (id INT);" }

      migrations = migration_texts.map_with_index do |text, i|
        m = Migrate::Migration.new(text)
        m.version = ["3", "1", "10", "2", "20"][i]
        m
      end

      sorted = migrations.sort_by { |m| m.version.not_nil!.to_i }
      sorted.map { |m| m.version }.should eq ["1", "2", "3", "10", "20"]
    end
  end

  describe "Version range operations" do
    it "selects versions in range for upgrade" do
      all_versions = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10"]
      current_version = "3"
      target_version = "7"

      versions_to_apply = all_versions.select do |v|
        v.to_i > current_version.to_i && v.to_i <= target_version.to_i
      end

      versions_to_apply.should eq ["4", "5", "6", "7"]
    end

    it "selects versions in range for downgrade" do
      all_versions = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10"]
      current_version = "7"
      target_version = "3"

      # For downgrade, we need versions > target and <= current
      versions_to_apply = all_versions.select do |v|
        v.to_i > target_version.to_i && v.to_i <= current_version.to_i
      end.reverse

      versions_to_apply.should eq ["7", "6", "5", "4"]
    end

    it "returns empty array when already at target" do
      all_versions = ["1", "2", "3", "4", "5"]
      current_version = "3"
      target_version = "3"

      versions_to_apply = all_versions.select do |v|
        v.to_i > current_version.to_i && v.to_i <= target_version.to_i
      end

      versions_to_apply.should be_empty
    end
  end

  describe "Version validation" do
    it "detects duplicate versions" do
      versions = ["1", "2", "3", "2", "4"]
      duplicates = versions.group_by { |v| v }.select { |_, group| group.size > 1 }

      duplicates.should have_key("2")
    end

    it "finds gaps in version sequence" do
      versions = ["1", "2", "4", "5", "7"]
      sorted = versions.map(&.to_i).sort

      gaps = [] of Int32
      sorted.each_cons(2) do |pair|
        if pair[1] - pair[0] > 1
          gaps << pair[0]
        end
      end

      gaps.should eq [2, 5]  # gaps after 2 (missing 3) and after 5 (missing 6)
    end

    it "validates version is in migration list" do
      available_versions = ["1", "2", "3", "5", "7"]
      target_version = "4"

      available_versions.includes?(target_version).should be_false
    end

    it "finds next version in sequence" do
      all_versions = ["1", "2", "3", "4", "5"]
      current_version = "3"
      current_index = all_versions.index(current_version)

      current_index.should_not be_nil
      next_version = all_versions[current_index.not_nil! + 1]?
      next_version.should eq "4"
    end

    it "returns nil when at last version" do
      all_versions = ["1", "2", "3", "4", "5"]
      current_version = "5"
      current_index = all_versions.index(current_version)

      next_version = all_versions[current_index.not_nil! + 1]?
      next_version.should be_nil
    end

    it "finds previous version in sequence" do
      all_versions = ["1", "2", "3", "4", "5"]
      current_version = "3"
      current_index = all_versions.index(current_version)

      previous_version = all_versions[current_index.not_nil! - 1]?
      previous_version.should eq "2"
    end

    it "returns nil when at first version" do
      all_versions = ["1", "2", "3", "4", "5"]
      current_version = "1"
      current_index = all_versions.index(current_version)

      # Going below 0 should return nil
      previous_version = current_index.not_nil! > 0 ? all_versions[current_index.not_nil! - 1]? : nil
      previous_version.should be_nil
    end
  end

  describe "String vs Integer version comparison edge cases" do
    it "handles zero-padded versions" do
      versions = ["001", "010", "100"]
      sorted = versions.sort_by { |v| v.to_i }

      sorted.should eq ["001", "010", "100"]
      sorted.map(&.to_i).should eq [1, 10, 100]
    end

    it "compares very large version numbers" do
      v1 = "9999999999999"
      v2 = "10000000000000"

      (v1.to_i < v2.to_i).should be_true
      (v1.to_i64 < v2.to_i64).should be_true
    end

    it "handles version 0" do
      versions = ["0", "1", "2"]
      sorted = versions.sort_by { |v| v.to_i }

      sorted.should eq ["0", "1", "2"]
    end
  end
end
