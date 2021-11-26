require "../spec_helper"
require "sqlite3"

describe Migrate::Migration, tags: "sqlite3" do
  db = DB.open("sqlite3:%3Amemory%3A")
  migration_sql = <<-SQL
    -- +migrate up
    CREATE TABLE foo (
      id      integer PRIMARY KEY,
      content TEXT NOT NULL
    );

    -- Indexes
    CREATE UNIQUE INDEX foo_content_index ON foo (content);

    -- Statements that might contain semicolons
    -- +migrate start
    -- From https://www.sqlite.org/fts5.html
    CREATE TABLE tbl(a INTEGER PRIMARY KEY, b, c);
    CREATE VIRTUAL TABLE fts_idx USING fts5(b, c, content='tbl', content_rowid='a');

    CREATE TRIGGER tbl_ai AFTER INSERT ON tbl BEGIN
      INSERT INTO fts_idx(rowid, b, c) VALUES (new.a, new.b, new.c);
    END;

    CREATE TRIGGER tbl_ad AFTER DELETE ON tbl BEGIN
      INSERT INTO fts_idx(fts_idx, rowid, b, c) VALUES('delete', old.a, old.b, old.c);
    END;

    CREATE TRIGGER tbl_au AFTER UPDATE ON tbl BEGIN
      INSERT INTO fts_idx(fts_idx, rowid, b, c) VALUES('delete', old.a, old.b, old.c);
      INSERT INTO fts_idx(rowid, b, c) VALUES (new.a, new.b, new.c);
    END;
    -- +migrate end

    -- +migrate down
    DROP trigger tbl_au;
    DROP trigger tbl_ad;
    DROP trigger tbl_ai;
    DROP TABLE fts_idx;
    DROP TABLE tbl;
    DROP TABLE foo;
  SQL
  migration = Migrate::Migration.new(migration_sql.lines.each)
  describe "#queries_up" do
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

    it do
      migration.queries_up.should eq [q1, q2, q3]
    end
  end
end
