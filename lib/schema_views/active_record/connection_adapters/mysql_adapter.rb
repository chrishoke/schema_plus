module SchemaViews
  module ActiveRecord
    module ConnectionAdapters
      module MysqlAdapter
        def self.included(base)
          base.class_eval do
            alias_method_chain :tables, :schema_views
          end
        end

        def tables_with_schema_views(name=nil, *args)
          tables_without_schema_views(name, *args) - views(name)
        end

        def views(name = nil)
          views = []
          select_all("SELECT table_name FROM information_schema.views WHERE table_schema = SCHEMA()", name).each do |row|
            views << row["table_name"]
          end
          views
        end

        def view_definition(view_name, name = nil)
          results = select_all("SELECT view_definition, check_option FROM information_schema.views WHERE table_schema = SCHEMA() AND table_name = #{quote(view_name)}", name)
          return nil unless results.any?
          row = results.first
          sql = row["view_definition"]
          sql.gsub!(%r{#{quote_table_name(current_database)}[.]}, '')
          case row["check_option"]
          when "CASCADED" then sql += " WITH CASCADED CHECK OPTION"
          when "LOCAL" then sql += " WITH LOCAL CHECK OPTION"
          end
          sql
        end

      end
    end
  end
end
