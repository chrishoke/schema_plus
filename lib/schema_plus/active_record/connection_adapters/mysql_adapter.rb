module SchemaPlus
  module ActiveRecord
    module ConnectionAdapters
      # SchemaPlus includes a MySQL implementation of the AbstractAdapter
      # extensions.
      module MysqlAdapter

        #:enddoc:
        
        def self.included(base)
          base.class_eval do
            alias_method_chain :remove_column, :schema_plus
            alias_method_chain :rename_table, :schema_plus
          end
          ::ActiveRecord::ConnectionAdapters::AbstractMysqlAdapter::SchemaCreation.send(:include, SchemaPlus::ActiveRecord::ConnectionAdapters::AbstractAdapter::VisitTableDefinition)
        end

        def remove_column_with_schema_plus(table_name, column_name, type=nil, options={})
          foreign_keys(table_name).select { |foreign_key| Array.wrap(foreign_key.column).include?(column_name.to_s) }.each do |foreign_key|
            remove_foreign_key(table_name, name: foreign_key.name)
          end
          remove_column_without_schema_plus(table_name, column_name, type, options)
        end

        def rename_table_with_schema_plus(oldname, newname)
          rename_table_without_schema_plus(oldname, newname)
          rename_foreign_keys(oldname, newname)
        end

        # implement cascade by removing foreign keys
        def drop_table(name, options={})
          if options[:cascade]
            reverse_foreign_keys(name).each do |foreign_key|
              remove_foreign_key(foreign_key.from_table, name: foreign_key.name)
            end
          end

          sql = 'DROP'
          sql += ' TEMPORARY' if options[:temporary]
          sql += ' TABLE'
          sql += ' IF EXISTS' if options[:if_exists]
          sql += " #{quote_table_name(name)}"

          execute sql
        end

        def remove_foreign_key(*args)
          from_table, to_table, options = normalize_remove_foreign_key_args(*args)
          if options[:if_exists]
            foreign_key_name = get_foreign_key_name(from_table, to_table, options)
            return if !foreign_key_name or not foreign_keys(from_table).detect{|fk| fk.name == foreign_key_name}
          end
          options.delete(:if_exists)
          super from_table, to_table, options
        end

        def remove_foreign_key_sql(*args)
          super.tap { |ret|
            ret.sub!(/DROP CONSTRAINT/, 'DROP FOREIGN KEY') if ret
          }
        end

        def foreign_keys(table_name, name = nil)
          results = select_all("SHOW CREATE TABLE #{quote_table_name(table_name)}", name)

          table_name = table_name.to_s
          namespace_prefix = table_namespace_prefix(table_name)

          foreign_keys = []

          results.each do |result|
            create_table_sql = result["Create Table"]
            create_table_sql.lines.each do |line|
              if line =~ /^  CONSTRAINT [`"](.+?)[`"] FOREIGN KEY \([`"](.+?)[`"]\) REFERENCES [`"](.+?)[`"] \((.+?)\)( ON DELETE (.+?))?( ON UPDATE (.+?))?,?$/
                name = $1
                columns = $2
                to_table = $3
                to_table = namespace_prefix + to_table if table_namespace_prefix(to_table).blank?
                primary_keys = $4
                on_update = $8
                on_delete = $6
                on_update = on_update ? on_update.downcase.gsub(' ', '_').to_sym : :restrict
                on_delete = on_delete ? on_delete.downcase.gsub(' ', '_').to_sym : :restrict

                options = { :name => name,
                            :on_delete => on_delete,
                            :on_update => on_update,
                            :column => columns.gsub('`', '').split(', '),
                            :primary_key => primary_keys.gsub('`', '').split(', ')
                }

                foreign_keys << ::ActiveRecord::ConnectionAdapters::ForeignKeyDefinition.new(
                  namespace_prefix + table_name,
                  to_table,
                  options)
              end
            end
          end

          foreign_keys
        end

        def reverse_foreign_keys(table_name, name = nil)
          results = select_all(<<-SQL, name)
        SELECT constraint_name, table_name, column_name, referenced_table_name, referenced_column_name
          FROM information_schema.key_column_usage
         WHERE table_schema = #{table_schema_sql(table_name)}
           AND referenced_table_schema = table_schema
         ORDER BY constraint_name, ordinal_position;
          SQL

          constraints = results.to_a.group_by do |r|
            r.values_at('constraint_name', 'table_name', 'referenced_table_name')
          end

          from_table_constraints = constraints.select do |(_, _, to_table), _|
            table_name_without_namespace(table_name).casecmp(to_table) == 0
          end

          from_table_constraints.map do |(constraint_name, from_table, to_table), columns|
            from_table = table_namespace_prefix(from_table) + from_table
            to_table = table_namespace_prefix(to_table) + to_table

            options = {
              :name => constraint_name,
              :column => columns.map { |row| row['column_name'] },
              :primary_key => columns.map { |row| row['referenced_column_name'] }
            }

            ::ActiveRecord::ConnectionAdapters::ForeignKeyDefinition.new(from_table, to_table, options)
          end
        end

        private

        def table_namespace_prefix(table_name)
          table_name.to_s =~ /(.*[.])/ ? $1 : ""
        end

        def table_schema_sql(table_name)
          table_name.to_s =~ /(.*)[.]/ ? "'#{$1}'" : "SCHEMA()"
        end

        def table_name_without_namespace(table_name)
          table_name.to_s.sub /.*[.]/, ''
        end

      end
    end
  end
end
