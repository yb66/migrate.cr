require "string_scanner"

module Migrate
  class Migration
    abstract struct Statement
      getter text : String
      def initialize(text)
        @text =
          text.strip
              .split("\n")
              .map{|str| str.strip }
              .reject{|line| line =~ /^[\s\n\r]*\-\-/ || line.empty?}
              .join("\n")
      end

      struct Up < Statement
      end

      struct Down < Statement
      end

      struct Error < Statement
        def initialize(text : String | Nil)
          text = "Migration error command was given." if text.nil?
          super(text)
        end
      end
    end

    FILE_REGEX = /
      (?<version>\d+)       # e.g. 1 or 19 etc
      (?: \_                # separator
        (?<name>\w[\w+\-])  # e.g. first_one or first-one
      )?                    # It's optional
      \.sql                 # Extension
    $/x

    SQL_COMMENT = /\s*+\-{2,}+\s++/
    MIGRATION_BRAND = /\+\b(?:mi[gc]rate|goose)\b\s++/

    # For consuming and tagging an up/down/error command.
    UPDOWN_PATTERN = /
      #{MIGRATION_BRAND}
      (?<cmd>
        \b
          (?: up | down)
        \b
      )
    /mix

    # For stopping at an up/down/error command.
    UPDOWN_STOPPER = /^
      #{SQL_COMMENT}
      (?=
        #{MIGRATION_BRAND}
        \b
          (?: up | down)
        \b
      )
    /mix

    # For finding and consuming a complex-start command.
    COMPLEX_START = /
      #{MIGRATION_BRAND}
      (?<cmd>
        \b
        (?:
          start
            |
          StatementBegin
        )
        \b
      )
    /mix

    # For stopping at a complex command.
    COMPLEX_STOPPER = /^
      #{SQL_COMMENT}
      (?=
        #{MIGRATION_BRAND}
        \b
        (?:
          (?:Statement)?End
            |
          start
            |
          StatementBegin
        )
        \b
      )
    /mix

    # For finding and consuming a complex-end statement.
    COMPLEX_END = /
      #{MIGRATION_BRAND}
      (?<cmd>
        \b
        (?:Statement)?End
        \b
      )
    /mix

    # For catching statements that are not complex.
    NOT_COMPLEX = /^
      #{SQL_COMMENT}
      #{MIGRATION_BRAND}
      (?!
        \b
        (?:Statement)?End
        \b
      )
    /mix

    ERROR_STOPPER = /^
      #{SQL_COMMENT}
      (?=
        #{MIGRATION_BRAND}
        \b error \b
      )
    /mix

    ERROR_PATTERN = /
      #{MIGRATION_BRAND}
      \b error \b
      \s++
      (?<message>
        [^\r\n]+
      )
    $/mix

    getter statements : Array(Statement)
    getter path : Path | Nil
    property version : String | Nil
    property name : String | Nil

    def initialize(@text : String)
      @statements = [] of Statement
      process!
    end


    def initialize(path : Path)
      @text = File.read(path)
      md = FILE_REGEX.match(path.basename(path.extension))
      raise "File name does not match `version_name.sql` pattern." if md.nil?
      @version = md["version"]?
      @name = md["name"]?
      @statements = [] of Statement
      @path = path
      process!
    end

    def process!
      s = StringScanner.new @text
      # `state` is whether it's currently going up or down.
      state = nil
      # This is checking for top-level up/down or error commands.
      while state.nil?
        s.skip_until(/#{ERROR_STOPPER}|#{UPDOWN_STOPPER}/)
        chunk = s.scan_until(/$/m)
        raise "No up/down/error command found" if chunk.nil?
        if md = ERROR_PATTERN.match(chunk)
          message = md.named_captures["message"]
          @statements << Migration::Statement::Error.new( message )
        elsif md = UPDOWN_PATTERN.match(chunk)
          cmd = md.named_captures["cmd"].not_nil!
          state = cmd == "up" ? Migration::Statement::Up : Migration::Statement::Down
        end
        return if s.eos?
      end
      state.not_nil!

      while !s.eos?
        # The idea here is to grab a chunk up to a semicolon
        # then check if that chunk contains other things.
        # If so, grab that instead. If not, it's fine, use it.
        if captured = s.check_until(/;/)
          case captured
          when ERROR_STOPPER
            #puts "ERROR_STOPPER2: #{s.check_until(/$/m)}"
            chunk = s.scan_until(ERROR_PATTERN).not_nil!
            @statements << Migration::Statement::Error.new(s["message"]? )
          when UPDOWN_STOPPER
            chunk = s.scan_until(UPDOWN_PATTERN).not_nil!
            state = s["cmd"]?.not_nil! == "up" ?
              Migration::Statement::Up :
              Migration::Statement::Down
          when COMPLEX_STOPPER
            # Can safely jump to start,
            # other statements would've been captured
            # if they existed.
            s.skip_until COMPLEX_START
            # Scan until an end statement or the end of the file.
            if complex_statement = s.scan_until /#{COMPLEX_END}|\z/
              if pos = complex_statement =~ NOT_COMPLEX
                # When another command is found before the end
                # of the complex statement then there
                # is something wrong with the migration.
                # TODO use proper Error class
                raise "The previous command was not finished (use `+migrate end`) before a new one was stated."
              end
              @statements << state.new( complex_statement)
            end
          else # just use it
            @statements << state.new( s.scan_until(/;/).not_nil!)
          end
        end
      end
    end

  end
end
