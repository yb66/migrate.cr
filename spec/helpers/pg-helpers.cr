
require "pg"

def drop_db
  DB.open(ENV["DATABASE_URL"]) do |db|
    db.exec <<-SQL
      DROP SCHEMA public CASCADE;
    SQL

    db.exec <<-SQL
      CREATE SCHEMA public;
    SQL
  end
end
