
# TODO START HACK TODO
=begin
# Use of Module SqlServer2000ReplaceLimitOffset methode replace_limit_offset
# instat of Module SqlServerReplaceLimitOffset  methode replace_limit_offset
module ArJdbc
  module MSSQL
    module LimitHelpers

      # @private
      FIND_SELECT = /\b(SELECT(\s+DISTINCT)?)\b(.*)/mi

      module SqlServerReplaceLimitOffset

        module_function

        def replace_limit_offset!(sql, limit, offset, order)
          if limit
            offset ||= 0
            start_row = offset + 1
            end_row = offset + limit.to_i

            if match = FIND_SELECT.match(sql)
              select, distinct, rest_of_query = match[1], match[2], match[3]
            end
            #need the table name for avoiding amiguity
            table_name  = Utils.get_table_name(sql, true)
            primary_key = get_primary_key(order, table_name)

            #I am not sure this will cover all bases.  but all the tests pass
            if order[/ORDER/].nil?
              new_order = "ORDER BY #{order}, [#{table_name}].[#{primary_key}]" if order.index("#{table_name}.#{primary_key}").nil?
            else
              # FIX from soemo if a group is in he query
              if rest_of_query.downcase.include?("group")
                new_order = "ORDER BY MIN(#{table_name}.#{primary_key})"
              else
                new_order ||= order
              end
            end

            if (start_row == 1) && (end_row ==1)
              new_sql = "#{select} TOP 1 #{rest_of_query} #{new_order}"
              sql.replace(new_sql)
            else
              # We are in deep trouble here. SQL Server does not have any kind of OFFSET build in.
              # Only remaining solution is adding a where condition to be sure that the ID is not in SELECT TOP OFFSET FROM SAME_QUERY.
              # To do so we need to extract each part of the query to insert our additional condition in the right place.
              query_without_select = rest_of_query[/FROM/i=~ rest_of_query.. -1]
              additional_condition = "#{table_name}.#{primary_key} NOT IN (#{select} TOP #{offset} #{table_name}.#{primary_key} #{query_without_select} #{new_order})"

              # Extract the different parts of the query
              having, group_by, where, from, selection = split_sql(rest_of_query, /having/i, /group by/i, /where/i, /from/i)

              # Update the where part to add our additional condition
              if where.blank?
                where = "WHERE #{additional_condition}"
              else
                where = "#{where} AND #{additional_condition}"
              end

              # Replace the query to be our new customized query
              sql.replace("#{select} TOP #{limit} #{selection} #{from} #{where} #{group_by} #{having} #{new_order}")
            end
          end

          sql
        end

        # Split the rest_of_query into chunks based on regexs (applied from end of string to the beginning)
        # The result is an array of regexs.size+1 elements (the last one being the remaining once everything was chopped away)
        def split_sql(rest_of_query, *regexs)
          results = Array.new

          regexs.each do |regex|
            if position = (regex =~ rest_of_query)
              # Extract the matched string and chop the rest_of_query
              matched       = rest_of_query[position..-1]
              rest_of_query = rest_of_query[0...position]
            else
              matched = nil
            end

            results << matched
          end
          results << rest_of_query

          results
        end

        def get_primary_key(order, table_name) # table_name might be quoted
          if order =~ /(\w*id\w*)/i
            $1
          else
            unquoted_name = Utils.unquote_table_name(table_name)
            model = descendants.find { |m| m.table_name == table_name || m.table_name == unquoted_name }
            model ? model.primary_key : 'id'
          end
        end

        private

        if ActiveRecord::VERSION::MAJOR >= 3
          def descendants; ::ActiveRecord::Base.descendants; end
        else
          def descendants; ::ActiveRecord::Base.send(:subclasses) end
        end

      end

    end
  end
end

module ArJdbc
  module MSSQL
    module LockMethods

      # @private
      SELECT_FROM_WHERE_RE = /\A(\s*SELECT\s.*?)(\sFROM\s)(.*?)(\sWHERE\s.*|)\Z/mi

      # Microsoft SQL Server uses its own syntax for SELECT .. FOR UPDATE:
      # SELECT .. FROM table1 WITH(ROWLOCK,UPDLOCK), table2 WITH(ROWLOCK,UPDLOCK) WHERE ..
      #
      # This does in-place modification of the passed-in string.
      def add_lock!(sql, options)
        if (lock = options[:lock]) && sql =~ /\A\s*SELECT/mi
          # Check for and extract the :limit/:offset sub-query
          if sql =~ /\A(\s*SELECT t\.\* FROM \()(.*)(\) AS t WHERE t._row_num BETWEEN \d+ AND \d+\s*)\Z/m
            prefix, subselect, suffix = [$1, $2, $3]
            add_lock!(subselect, options)
            return sql.replace(prefix + subselect + suffix)
          end
          unless sql =~ SELECT_FROM_WHERE_RE
            # If you get this error, this driver probably needs to be fixed.
            raise NotImplementedError, "Don't know how to add_lock! to SQL statement: #{sql.inspect}"
          end
          select_clause, from_word, from_tables, where_clause = $1, $2, $3, $4
          # FIXME soemo 29.07.13 HACK  WITH(ROWLOCK,UPDLOCK) commented out
          #with_clause = lock.is_a?(String) ? " #{lock} " : " WITH(ROWLOCK,UPDLOCK) "
          with_clause = ''

          # Split the FROM clause into its constituent tables, and add the with clause after each one.
          new_from_tables = []
          scanner = StringScanner.new(from_tables)
          until scanner.eos?
            prev_pos = scanner.pos
            if scanner.scan_until(/,|(INNER\s+JOIN|CROSS\s+JOIN|(LEFT|RIGHT|FULL)(\s+OUTER)?\s+JOIN)\s+/mi)
              join_operand = scanner.pre_match[prev_pos..-1]
              join_operator = scanner.matched
            else
              join_operand = scanner.rest
              join_operator = ""
              scanner.terminate
            end

            # At this point, we have something like:
            #   join_operand == "appointments "
            #   join_operator == "INNER JOIN "
            # or:
            #   join_operand == "appointment_details AS d1 ON appointments.[id] = d1.[appointment_id]"
            #   join_operator == ""
            if join_operand =~ /\A(.*)(\s+ON\s+.*)\Z/mi
              table_spec, on_clause = $1, $2
            else
              table_spec = join_operand
              on_clause = ""
            end

            # Add the "WITH(ROWLOCK,UPDLOCK)" option to the table specification
            table_spec << with_clause unless table_spec =~ /\A\(\s*SELECT\s+/mi # HACK - this parser isn't so great
            join_operand = table_spec + on_clause

            # So now we have something like:
            #   join_operand == "appointments  WITH(ROWLOCK,UPDLOCK) "
            #   join_operator == "INNER JOIN "
            # or:
            #   join_operand == "appointment_details AS d1 WITH(ROWLOCK,UPDLOCK)  ON appointments.[id] = d1.[appointment_id]"
            #   join_operator == ""

            new_from_tables << join_operand
            new_from_tables << join_operator
          end
          sql.replace( select_clause.to_s << from_word.to_s << new_from_tables.join << where_clause.to_s )
        end
        sql
      end

    end
  end
end
=end
# TODO END HACK TODO







# Rails3 Fix
module ActiveRecord
  module Locking
    module Optimistic

      private
      def update(attribute_names = @attributes.keys) #:nodoc:
        return super unless locking_enabled?
        return 0 if attribute_names.empty?

        lock_col = self.class.locking_column
        previous_lock_value = send(lock_col).to_i
        increment_lock

        attribute_names += [lock_col]
        attribute_names.uniq!

        begin
          relation = self.class.unscoped

          # FIX should be fixed in Rails4
          # TODO quote_value(previous_lock_value) to quote_value(previous_lock_value, column_for_attribute(lock_col)
          # https://github.com/rails/rails/commit/39b5bfe2394d0a4d479b41ee8d170e0f6c65fd59#activerecord/lib/active_record/locking/optimistic.rb
          stmt = relation.where(
              relation.table[self.class.primary_key].eq(id).and(
                  relation.table[lock_col].eq(quote_value(previous_lock_value, column_for_attribute(lock_col)))
              )
          ).arel.compile_update(arel_attributes_values(false, false, attribute_names))

          affected_rows = connection.update stmt

          unless affected_rows == 1
            raise ActiveRecord::StaleObjectError.new(self, "update")
          end

          affected_rows

            # If something went wrong, revert the version.
        rescue Exception
          send(lock_col + '=', previous_lock_value)
          raise
        end
      end

    end
  end
end
