require "string_scanner"
require "./migration/parse_error"

module Migrate
  # Represents a database migration file containing SQL statements
  # and migration directives.
  #
  # ## Supported Migration Commands
  #
  # Migration files use special comment directives to organize SQL statements.
  # All directives must be in SQL comments starting with `--`.
  #
  # ### Basic Directives
  #
  # #### `+migrate up`
  # Marks the beginning of SQL statements to run when migrating up (applying migration).
  # All statements after this directive (until `+migrate down` or end of file) will be
  # executed when migrating forward.
  #
  # Example:
  # ```sql
  # -- +migrate up
  # CREATE TABLE users (
  #   id SERIAL PRIMARY KEY,
  #   name TEXT NOT NULL
  # );
  # ```
  #
  # #### `+migrate down`
  # Marks the beginning of SQL statements to run when migrating down (reverting migration).
  # All statements after this directive will be executed when rolling back this migration.
  #
  # Example:
  # ```sql
  # -- +migrate down
  # DROP TABLE users;
  # ```
  #
  # #### `+migrate error [message]`
  # Raises an error with the given message when the migration is executed.
  # Can be used at the top level (before up/down) to prevent the entire migration,
  # or within a specific direction to prevent that direction.
  #
  # Examples:
  # ```sql
  # -- Top-level error - prevents entire migration
  # -- +migrate error This migration is not ready
  #
  # -- Direction-specific error
  # -- +migrate up
  # CREATE TABLE foo;
  #
  # -- +migrate down
  # -- +migrate error This migration cannot be reversed
  # ```
  #
  # ### Complex Statement Directives
  #
  # For SQL statements containing semicolons (like triggers, functions, or procedures),
  # use the complex statement directives to prevent the parser from splitting on semicolons.
  #
  # #### `+migrate start` / `+migrate end`
  # Marks the beginning and end of a complex SQL statement.
  # All content between start and end is treated as a single statement.
  #
  # Example:
  # ```sql
  # -- +migrate start
  # CREATE TRIGGER update_timestamp
  # BEFORE UPDATE ON users
  # FOR EACH ROW
  # BEGIN
  #   NEW.updated_at = NOW();
  # END;
  # -- +migrate end
  # ```
  #
  # #### `+migrate StatementBegin` / `+migrate StatementEnd`
  # Alternative syntax for complex statements (goose compatibility).
  # Functions identically to `+migrate start` / `+migrate end`.
  #
  # ### Alternative Brands
  #
  # For compatibility with other migration tools, the following brands are supported
  # in addition to `+migrate`:
  # - `+goose` - Compatible with goose migration tool
  # - `+migcrate` - (legacy typo support)
  #
  # Example:
  # ```sql
  # -- +goose up
  # CREATE TABLE foo;
  #
  # -- +goose down
  # DROP TABLE foo;
  # ```
  #
  # ## File Naming Convention
  #
  # Migration files must follow the pattern: `{version}_{optional_name}.sql`
  # - `version`: Integer version number (e.g., `1`, `20231201`, `001`)
  # - `optional_name`: Optional descriptive name (alphanumeric, underscores, hyphens)
  #
  # Examples:
  # - `1.sql`
  # - `001_create_users.sql`
  # - `20231201_add_indexes.sql`
  # - `2_create-posts.sql`
  #
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

    # Return array of SQL queries for migrating up
    def queries_up : Array(String)
      @statements
        .select { |s| s.is_a?(Statement::Up) }
        .map(&.text)
    end

    # Return array of SQL queries for migrating down
    def queries_down : Array(String)
      @statements
        .select { |s| s.is_a?(Statement::Down) }
        .map(&.text)
    end

    # Return first error statement if any (top-level or direction-agnostic errors)
    # This would be an error that appears before any up/down directive
    def error : Migrate::Error?
      err = @statements.find { |s| s.is_a?(Statement::Error) && !is_direction_specific?(s) }
      err ? Migrate::Error.new(err.text) : nil
    end

    # Return first error statement in the up direction
    def error_up : Migrate::Error?
      in_up = false
      @statements.each do |s|
        in_up = true if s.is_a?(Statement::Up)
        return nil if s.is_a?(Statement::Down)
        if in_up && s.is_a?(Statement::Error)
          return Migrate::Error.new(s.text)
        end
      end
      nil
    end

    # Return first error statement in the down direction
    def error_down : Migrate::Error?
      in_down = false
      @statements.each do |s|
        in_down = true if s.is_a?(Statement::Down)
        if in_down && s.is_a?(Statement::Error)
          return Migrate::Error.new(s.text)
        end
      end
      nil
    end

    # Helper to determine if an error appears before any up/down directives
    private def is_direction_specific?(statement : Statement) : Bool
      idx = @statements.index(statement)
      return false unless idx

      # Check if there's an Up or Down statement before this error
      @statements[0...idx].any? { |s| s.is_a?(Statement::Up) || s.is_a?(Statement::Down) }
    end


    def initialize(path : Path)
      @text = File.read(path)
      @path = path
      md = FILE_REGEX.match(path.basename(path.extension))
      if md.nil?
        raise ParseError.new(
          "File name does not match `version_name.sql` pattern (expected: number_optional_name.sql)",
          file_path: path.to_s
        )
      end
      @version = md["version"]?
      @name = md["name"]?
      @statements = [] of Statement
      process!
    rescue ex : ParseError
      raise ex
    rescue ex : Exception
      raise ParseError.new("Failed to parse migration file: #{ex.message}", file_path: @path.try(&.to_s))
    end

    def process!
      s = StringScanner.new @text
      # `state` is whether it's currently going up or down.
      state = nil
      # This is checking for top-level up/down or error commands.
      while state.nil?
        s.skip_until(/#{ERROR_STOPPER}|#{UPDOWN_STOPPER}/)
        chunk = s.scan_until(/$/m)
        if chunk.nil?
          raise ParseError.new(
            "No up/down/error command found. Migration files must contain at least one directive: +migrate up, +migrate down, or +migrate error",
            file_path: @path.try(&.to_s),
            context: "Searched entire file for migration directives"
          )
        end
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
                raise ParseError.new(
                  "Complex statement was not properly closed. The previous `+migrate start` command must be closed with `+migrate end` before starting a new command.",
                  file_path: @path.try(&.to_s),
                  context: complex_statement[0...[pos + 50, complex_statement.size].min]
                )
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
