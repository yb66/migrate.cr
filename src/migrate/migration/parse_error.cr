module Migrate
  class Migration
    # Error raised when migration file parsing fails
    class ParseError < Migrate::Error
      property file_path : String?
      property line_number : Int32?
      property context : String?

      def initialize(message : String, @file_path : String? = nil, @line_number : Int32? = nil, @context : String? = nil)
        full_message = build_message(message)
        super(full_message)
      end

      private def build_message(base_message : String) : String
        parts = [] of String

        if fp = @file_path
          parts << "In file: #{fp}"
        end

        if ln = @line_number
          parts << "Line: #{ln}"
        end

        parts << base_message

        if ctx = @context
          parts << "Context: #{ctx}"
        end

        parts.join("\n")
      end
    end
  end
end
