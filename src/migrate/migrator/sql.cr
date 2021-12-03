module Migrate
  class Migrator
    module SQL

      protected def ensure_version_table_exist
        table_query = CREATE_VERSION_TABLE_SQL % {
          table:  @table,
          column: @column,
        }

        count_query = COUNT_ROWS_SQL % {
          table:  @table,
          column: @column,
        }

        insert_query = INSERT_SQL % {
          table:  @table,
          column: @column,
          value:  0,
        }

        Log.debug { table_query }
        @db.exec(table_query)

        Log.debug { count_query }
        count = @db.scalar(count_query).as(Int64)

        if count == 0
          Log.debug { insert_query }
          @db.exec(insert_query)
        end
      end

      private CREATE_VERSION_TABLE_SQL = <<-SQL
      CREATE TABLE IF NOT EXISTS %{table} (%{column} NOT NULL)
      SQL

      private COUNT_ROWS_SQL = <<-SQL
      SELECT COUNT(%{column}) FROM %{table}
      SQL

      private INSERT_SQL = <<-SQL
      INSERT INTO %{table} (%{column}) VALUES (%{value})
      SQL

      private UPDATE_VERSION_SQL = <<-SQL
      UPDATE %{table} SET %{column} = %{value}
      SQL

      protected def update_version_query(version)
        UPDATE_VERSION_SQL % {
          table:  @table,
          column: @column,
          value:  version,
        }
      end
    end
  end
end
