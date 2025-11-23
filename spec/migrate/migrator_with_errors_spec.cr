require "../spec_helper"

{% for table in %w(foo bar baz) %}
  def {{table.id}}_exists?(db)
    db.scalar("SELECT COUNT(*) FROM {{table.id}}").as(Int64)
  rescue
    false
  end
{% end %}
# %}

describe "Migrate::Migrator with errors", tags: "pg" do
  describe "direction-specific errors" do
    it do
      drop_db

      migrator = Migrate::Migrator.new(
        db,
        Path["spec/fixtures", "migrations_with_errors"]
      )
      migrator.up

      expect_raises Migrate::Migration::Error do
        migrator.down
      end

      migrator.current_version.should eq 1
    end
  end

  describe "top-level errors" do
    it do
      drop_db

      migrator = Migrate::Migrator.new(
        db,
        Path["spec/fixtures", "migrations_with_errors"]
      )

      migrator.up

      expect_raises Migrate::Migration::Error do
        migrator.up
      end

      migrator.current_version.should eq 1
    end
  end
end
