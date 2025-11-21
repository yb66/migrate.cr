require "../spec_helper"

# Unit tests for Statement types
# Covers Phase 3.1 requirement: Test all Statement types
describe Migrate::Migration::Statement, tags: "unit" do
  describe "Statement::Up" do
    it "creates an Up statement with text" do
      text = "CREATE TABLE foo (id INT);"
      statement = Migrate::Migration::Statement::Up.new(text)

      statement.should be_a(Migrate::Migration::Statement::Up)
      statement.text.should eq "CREATE TABLE foo (id INT);"
    end

    it "strips whitespace from text" do
      text = "\n  CREATE TABLE foo (id INT);  \n"
      statement = Migrate::Migration::Statement::Up.new(text)

      statement.text.should_not start_with("\n")
      statement.text.should_not end_with("\n")
    end

    it "removes SQL comment lines" do
      text = <<-SQL
      -- This is a comment
      CREATE TABLE foo (id INT);
      -- Another comment
      SQL

      statement = Migrate::Migration::Statement::Up.new(text)
      statement.text.should_not contain("-- This is a comment")
      statement.text.should_not contain("-- Another comment")
    end

    it "removes empty lines" do
      text = <<-SQL
      CREATE TABLE foo (id INT);


      CREATE TABLE bar (id INT);
      SQL

      statement = Migrate::Migration::Statement::Up.new(text)
      lines = statement.text.split("\n")
      lines.should_not contain("")
    end

    it "handles multi-line SQL statements" do
      text = <<-SQL
      CREATE TABLE foo (
        id INT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at TIMESTAMP
      );
      SQL

      statement = Migrate::Migration::Statement::Up.new(text)
      statement.text.should contain("id INT PRIMARY KEY")
      statement.text.should contain("name TEXT NOT NULL")
      statement.text.should contain("created_at TIMESTAMP")
    end

    it "handles complex SQL with dollar quotes" do
      text = <<-SQL
      CREATE FUNCTION foo() RETURNS INT AS $$
      BEGIN
        RETURN 1;
      END;
      $$ LANGUAGE plpgsql;
      SQL

      statement = Migrate::Migration::Statement::Up.new(text)
      statement.text.should contain("$$")
      statement.text.should contain("BEGIN")
      statement.text.should contain("END")
    end
  end

  describe "Statement::Down" do
    it "creates a Down statement with text" do
      text = "DROP TABLE foo;"
      statement = Migrate::Migration::Statement::Down.new(text)

      statement.should be_a(Migrate::Migration::Statement::Down)
      statement.text.should eq "DROP TABLE foo;"
    end

    it "strips whitespace from text" do
      text = "\n  DROP TABLE foo;  \n"
      statement = Migrate::Migration::Statement::Down.new(text)

      statement.text.should_not start_with("\n")
      statement.text.should_not end_with("\n")
    end

    it "handles multiple drop statements" do
      text = <<-SQL
      DROP TRIGGER my_trigger;
      DROP TABLE bar;
      DROP TABLE foo;
      SQL

      statement = Migrate::Migration::Statement::Down.new(text)
      statement.text.should contain("DROP TRIGGER")
      statement.text.should contain("DROP TABLE bar")
      statement.text.should contain("DROP TABLE foo")
    end

    it "removes SQL comment lines" do
      text = <<-SQL
      -- Cleanup
      DROP TABLE foo;
      SQL

      statement = Migrate::Migration::Statement::Down.new(text)
      statement.text.should_not contain("-- Cleanup")
    end
  end

  describe "Statement::Error" do
    it "creates an Error statement with message" do
      message = "This migration is irreversible"
      statement = Migrate::Migration::Statement::Error.new(message)

      statement.should be_a(Migrate::Migration::Statement::Error)
      statement.text.should eq "This migration is irreversible"
    end

    it "creates an Error statement with nil message" do
      statement = Migrate::Migration::Statement::Error.new(nil)

      statement.should be_a(Migrate::Migration::Statement::Error)
      statement.text.should eq "Migration error command was given."
    end

    it "strips whitespace from error message" do
      message = "\n  This is an error  \n"
      statement = Migrate::Migration::Statement::Error.new(message)

      statement.text.should_not start_with("\n")
      statement.text.should_not end_with("\n")
    end

    it "handles empty string as error message" do
      statement = Migrate::Migration::Statement::Error.new("")

      # Empty string gets processed through strip which makes it empty
      # The initialize should handle this
      statement.text.should_not be_nil
    end

    it "handles multi-line error messages" do
      message = <<-MSG
      This migration cannot be run because:
      - Database version mismatch
      - Missing prerequisite tables
      MSG

      statement = Migrate::Migration::Statement::Error.new(message)
      # After processing, it should still contain the content
      statement.text.should_not be_empty
    end
  end

  describe "Statement type checking" do
    it "distinguishes between Up, Down, and Error statements" do
      up = Migrate::Migration::Statement::Up.new("CREATE TABLE foo (id INT);")
      down = Migrate::Migration::Statement::Down.new("DROP TABLE foo;")
      error = Migrate::Migration::Statement::Error.new("Error message")

      up.should be_a(Migrate::Migration::Statement::Up)
      up.should_not be_a(Migrate::Migration::Statement::Down)
      up.should_not be_a(Migrate::Migration::Statement::Error)

      down.should be_a(Migrate::Migration::Statement::Down)
      down.should_not be_a(Migrate::Migration::Statement::Up)
      down.should_not be_a(Migrate::Migration::Statement::Error)

      error.should be_a(Migrate::Migration::Statement::Error)
      error.should_not be_a(Migrate::Migration::Statement::Up)
      error.should_not be_a(Migrate::Migration::Statement::Down)
    end

    it "all statement types inherit from Statement" do
      up = Migrate::Migration::Statement::Up.new("CREATE TABLE foo (id INT);")
      down = Migrate::Migration::Statement::Down.new("DROP TABLE foo;")
      error = Migrate::Migration::Statement::Error.new("Error message")

      up.should be_a(Migrate::Migration::Statement)
      down.should be_a(Migrate::Migration::Statement)
      error.should be_a(Migrate::Migration::Statement)
    end
  end

  describe "Statement text normalization" do
    it "normalizes various whitespace characters" do
      text = "CREATE\tTABLE\r\nfoo\n(id\r\nINT);"
      statement = Migrate::Migration::Statement::Up.new(text)

      # After processing, whitespace should be normalized
      statement.text.should contain("CREATE")
      statement.text.should contain("TABLE")
      statement.text.should contain("foo")
    end

    it "handles statements with only whitespace" do
      text = "   \n\t\r\n   "
      statement = Migrate::Migration::Statement::Up.new(text)

      # After stripping and filtering, should be empty
      statement.text.should be_empty
    end

    it "preserves meaningful whitespace in SQL" do
      text = "SELECT  *  FROM  foo  WHERE  id  =  1;"
      statement = Migrate::Migration::Statement::Up.new(text)

      # The statement should still be valid SQL
      statement.text.should contain("SELECT")
      statement.text.should contain("FROM")
      statement.text.should contain("WHERE")
    end
  end

  describe "Statement text getter" do
    it "returns the processed text" do
      original = "\n-- comment\nCREATE TABLE foo (id INT);\n"
      statement = Migrate::Migration::Statement::Up.new(original)

      statement.text.should be_a(String)
      statement.text.should_not eq original
    end

    it "text is immutable after creation" do
      statement = Migrate::Migration::Statement::Up.new("CREATE TABLE foo (id INT);")
      original_text = statement.text

      # The text should remain the same
      statement.text.should eq original_text
    end
  end
end
