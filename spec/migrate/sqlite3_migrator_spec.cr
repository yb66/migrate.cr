require "../spec_helper"

describe Migrate::Migrator do
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
  db = DB.open("sqlite3:%3Amemory%3A")
  it "does not blow up on instantiation" do
    migrations = [migration_sql1,migration_sql2]
                    .zip(1..2)
                    .map{|sql,i|
      m = Migrate::Migration.new sql
      m.version = i.to_s
      m.name = "spec"
      m
    }
    migrator = Migrate::Migrator.new db, migrations
    migrator.should_not be_nil
  end
end
