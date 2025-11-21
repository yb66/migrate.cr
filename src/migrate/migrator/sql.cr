module Migrate
  class Migrator
    module SQL

      protected def ensure_version_table_exist
        table_query = @adapter.create_version_table_sql(@table, @column)
        count_query = @adapter.count_rows_sql(@table, @column)
        insert_query = @adapter.insert_initial_version_sql(@table, @column, "0")

        Log.debug { table_query }
        @db.exec(table_query)

        Log.debug { count_query }
        count = @db.scalar(count_query).as(Int64)

        if count == 0
          Log.debug { insert_query }
          @db.exec(insert_query)
        end
      end

      protected def update_version_query(version)
        @adapter.update_version_sql(@table, @column, version)
      end
    end
  end
end
