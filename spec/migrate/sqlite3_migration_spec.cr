require "../spec_helper"
require "sqlite3"

describe Migrate::Migration, tags: "sqlite3" do
  migration_sql1 = <<-SQL
  -- Comments that will be skipped
  -- and ignored

  -- +migrate error Maybe I don't like this.

  -- This never gets run
  -- +migrate up
  CREATE TABLE bar (
    id      integer PRIMARY KEY,
    content TEXT NOT NULL
  );
SQL

  migration_sql2 = <<-SQL
    -- Comments that will be skipped
    -- and ignored

    -- +migrate up
    CREATE TABLE foo (
      id      integer PRIMARY KEY,
      content TEXT NOT NULL
    );

    -- Indexes
    CREATE UNIQUE INDEX foo_content_index ON foo (content);

    -- From https://www.sqlite.org/fts5.html
    CREATE TABLE tbl(a INTEGER PRIMARY KEY, b, c);

    CREATE VIRTUAL TABLE fts_idx USING fts5(b, c, content='tbl', content_rowid='a');

    -- Statements that might contain semicolons
    -- +migrate start
    CREATE TRIGGER tbl_ai AFTER INSERT ON tbl BEGIN
      INSERT INTO fts_idx(rowid, b, c) VALUES (new.a, new.b, new.c);
    END;
    -- +migrate end

    -- +migrate start
    CREATE TRIGGER tbl_ad AFTER DELETE ON tbl BEGIN
      INSERT INTO fts_idx(fts_idx, rowid, b, c) VALUES('delete', old.a, old.b, old.c);
    END;
    -- +migrate end

    -- +migrate start
    CREATE TRIGGER tbl_au AFTER UPDATE ON tbl BEGIN
      INSERT INTO fts_idx(fts_idx, rowid, b, c) VALUES('delete', old.a, old.b, old.c);
      INSERT INTO fts_idx(rowid, b, c) VALUES (new.a, new.b, new.c);
    END;
    -- +migrate end

    -- +migrate error I really don't like this table.
    CREATE TABLE bar (
      id      integer PRIMARY KEY,
      content TEXT NOT NULL
    );

    -- +migrate down
    DROP trigger tbl_au;
    DROP trigger tbl_ad;
    DROP trigger tbl_ai;
    DROP TABLE fts_idx;
    DROP TABLE tbl;
    DROP TABLE foo;
  SQL

  migration1 = Migrate::Migration.new(migration_sql1)
  migration2 = Migrate::Migration.new(migration_sql2)

  context "Just the migrations" do
    q0 = "Maybe I don't like this."

    q1 = <<-SQL
    CREATE TABLE foo (
      id      integer PRIMARY KEY,
      content TEXT NOT NULL
    );
    SQL

    q2 = <<-SQL
    CREATE UNIQUE INDEX foo_content_index ON foo (content);
    SQL

    q3 = <<-SQL
    CREATE TABLE tbl(a INTEGER PRIMARY KEY, b, c);
    SQL

    q4 = <<-SQL
    CREATE VIRTUAL TABLE fts_idx USING fts5(b, c, content='tbl', content_rowid='a');
    SQL

    q5 = <<-SQL
    CREATE TRIGGER tbl_ai AFTER INSERT ON tbl BEGIN
      INSERT INTO fts_idx(rowid, b, c) VALUES (new.a, new.b, new.c);
    END;
    SQL

    q6 = <<-SQL
    CREATE TRIGGER tbl_ad AFTER DELETE ON tbl BEGIN
      INSERT INTO fts_idx(fts_idx, rowid, b, c) VALUES('delete', old.a, old.b, old.c);
    END;
    SQL

    q7 = <<-SQL
    CREATE TRIGGER tbl_au AFTER UPDATE ON tbl BEGIN
      INSERT INTO fts_idx(fts_idx, rowid, b, c) VALUES('delete', old.a, old.b, old.c);
      INSERT INTO fts_idx(rowid, b, c) VALUES (new.a, new.b, new.c);
    END;
    SQL

    qe2 = "I really don't like this table."

    q8 = <<-SQL
    CREATE TABLE bar (
      id      integer PRIMARY KEY,
      content TEXT NOT NULL
    );
    SQL

    q9 = "DROP trigger tbl_au;"
    q10 = "DROP trigger tbl_ad;"
    q11 = "DROP trigger tbl_ai;"
    q12 = "DROP TABLE fts_idx;"
    q13 = "DROP TABLE tbl;"
    q14 = "DROP TABLE foo;"

    # Strip away dangling whitespace to account for
    # differences in spec strings that may differ for no
    # good reason that also have no relevance to efficacy
    # but will kill a test and my sanity dead.
    qs1 = [q0, q8].map{|q|
      q.lines.map{|x| x.strip }.join("\n")
    }
    qs2 = [q1, q2, q3, q4, q5, q6, q7, qe2, q8, q9, q10, q11, q12, q13, q14].map{|q|
      q.lines.map{|x| x.strip }.join("\n")
    }

    it do
      migration1.statements
              .map{|statement| statement.text }
              .should eq qs1
      migration2.statements
              .map{|statement| statement.text }
              .should eq qs2
    end
  end

  context "When applied" do
    break_on_errors = ->(db : DB::Database, migration : Migrate::Migration) {
      migration.statements.each_with_index do |statement, i|
        case statement
        when Migrate::Migration::Statement::Up
          db.exec statement.text
        when Migrate::Migration::Statement::Error
          break
        else
          # what?
        end
      end
    }
    context "Going up" do
      db = DB.open("sqlite3:%3Amemory%3A")
      [migration_sql1, migration_sql2].map{|m|
        Migrate::Migration.new m
      }.each do |migration|
        migration.statements.each_with_index do |statement, i|
          case statement
          when Migrate::Migration::Statement::Up
            db.exec statement.text
          when Migrate::Migration::Statement::Error
            break
          else
            # what?
          end
        end
      end
      it "should have the correct stuff" do
        db.scalar("SELECT count(*) FROM sqlite_master WHERE type='table' AND name='foo' COLLATE NOCASE;").as(Int64)
          .should eq 1
        db.scalar("SELECT count(*) FROM sqlite_master WHERE type='index' AND name='foo_content_index' COLLATE NOCASE;").as(Int64)
          .should eq 1
        db.scalar("SELECT count(*) FROM sqlite_master WHERE type='table' AND name='tbl' COLLATE NOCASE;").as(Int64)
          .should eq 1
        db.scalar("SELECT count(*) FROM sqlite_master WHERE type='table' AND name='fts_idx' COLLATE NOCASE;").as(Int64)
          .should eq 1
        db.scalar("SELECT count(*) FROM sqlite_master WHERE type='trigger' AND name='tbl_ai' COLLATE NOCASE;").as(Int64)
          .should eq 1
        db.scalar("SELECT count(*) FROM sqlite_master WHERE type='trigger' AND name='tbl_ad' COLLATE NOCASE;").as(Int64)
          .should eq 1
        db.scalar("SELECT count(*) FROM sqlite_master WHERE type='trigger' AND name='tbl_au' COLLATE NOCASE;").as(Int64)
          .should eq 1
        db.scalar("SELECT count(*) FROM sqlite_master WHERE type='table' AND name='bar' COLLATE NOCASE;").as(Int64)
          .should eq 0
      end
    end
    context "Going down" do
      it "should have the correct stuff" do
        db = DB.open("sqlite3:%3Amemory%3A")
        # This is here because I don't want to implement
        # the full migration logic, so this cancels out
        # ups that wouldn't have happened due to errors
        # that won't happen because it's a test.
        migration_sql3 = "-- +migrate down\ndrop table if exists bar;"
        [migration_sql2, migration_sql3].map{|m|
          Migrate::Migration.new m
        }.each do |migration|
          migration.statements.each_with_index do |statement, i|
            case statement
            when Migrate::Migration::Statement::Error
              # ignore
            else
              db.exec statement.text
            end
          end
        end
        db.scalar("SELECT count(*) FROM sqlite_master WHERE type='table' AND name='foo' COLLATE NOCASE;").as(Int64)
          .should eq 0
        db.scalar("SELECT count(*) FROM sqlite_master WHERE type='index' AND name='foo_content_index' COLLATE NOCASE;").as(Int64)
          .should eq 0
        db.scalar("SELECT count(*) FROM sqlite_master WHERE type='table' AND name='tbl' COLLATE NOCASE;").as(Int64)
          .should eq 0
        db.scalar("SELECT count(*) FROM sqlite_master WHERE type='table' AND name='fts_idx' COLLATE NOCASE;").as(Int64)
          .should eq 0
        db.scalar("SELECT count(*) FROM sqlite_master WHERE type='trigger' AND name='tbl_ai' COLLATE NOCASE;").as(Int64)
          .should eq 0
        db.scalar("SELECT count(*) FROM sqlite_master WHERE type='trigger' AND name='tbl_ad' COLLATE NOCASE;").as(Int64)
          .should eq 0
        db.scalar("SELECT count(*) FROM sqlite_master WHERE type='trigger' AND name='tbl_au' COLLATE NOCASE;").as(Int64)
          .should eq 0
        db.scalar("SELECT count(*) FROM sqlite_master WHERE type='table' AND name='bar' COLLATE NOCASE;").as(Int64)
          .should eq 0
      end
    end
    describe "Errors" do
      db = DB.open("sqlite3:%3Amemory%3A")
      it "shouldn't have done anything" do
        m1 = Migrate::Migration.new(migration_sql1)
        break_on_errors.call(db,m1)
        db.scalar("SELECT count(*) FROM sqlite_master;").as(Int64)
          .should eq 0
      end
      it "should not have a 'bar' table" do
        m2 = Migrate::Migration.new(migration_sql2)
        break_on_errors.call(db,m2)
        names = db.query_all "SELECT name FROM sqlite_master  where type='table';", &.read(String)
        names.should eq ["foo", "tbl", "fts_idx", "fts_idx_data", "fts_idx_idx", "fts_idx_docsize", "fts_idx_config"]
        db.scalar("SELECT count(*) FROM sqlite_master where type='index';").as(Int64)
          .should eq 1
        db.scalar("SELECT count(*) FROM sqlite_master where type='trigger';").as(Int64)
          .should eq 3
      end
    end
  end
end
