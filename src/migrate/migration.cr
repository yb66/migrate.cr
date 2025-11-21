require "string_scanner"

module Migrate
  # Represents a database migration file containing SQL statements.
  #
  # A `Migration` parses SQL files containing special directives that indicate
  # whether statements should be run when migrating up or down, or if the migration
  # should raise an error.
  #
  # ## Migration File Format
  #
  # Migration files must follow the pattern: `VERSION[_NAME].sql`
  # - VERSION: Numeric version (e.g., 1, 10, 20231121094530)
  # - NAME: Optional descriptive name (e.g., create_users, add_indexes)
  #
  # ## Supported Directives
  #
  # - `-- +migrate up`: Marks statements to run when migrating up
  # - `-- +migrate down`: Marks statements to run when migrating down
  # - `-- +migrate error [message]`: Raises an error, preventing migration
  # - `-- +migrate start` / `-- +migrate end`: Wraps complex SQL (triggers, functions)
  # - `-- +goose up/down`: Alternative brand (compatible with goose)
  #
  # ## Examples
  #
  # ### Simple migration:
  # ```sql
  # -- +migrate up
  # CREATE TABLE users (
  #   id INTEGER PRIMARY KEY,
  #   name TEXT NOT NULL
  # );
  #
  # -- +migrate down
  # DROP TABLE users;
  # ```
  #
  # ### Complex SQL with triggers:
  # ```sql
  # -- +migrate up
  # CREATE TABLE items (id INTEGER PRIMARY KEY);
  #
  # -- +migrate start
  # CREATE TRIGGER items_audit AFTER INSERT ON items BEGIN
  #   INSERT INTO audit_log VALUES (NEW.id, 'created');
  # END;
  # -- +migrate end
  #
  # -- +migrate down
  # DROP TRIGGER items_audit;
  # DROP TABLE items;
  # ```
  #
  # ### Irreversible migration:
  # ```sql
  # -- +migrate up
  # DROP TABLE old_data;  -- Cannot be undone
  #
  # -- +migrate down
  # -- +migrate error Cannot recreate dropped data
  # ```
  #
  # ## Statement Types
  #
  # Parsed migrations contain `Statement` objects of three types:
  # - `Statement::Up`: SQL to run when migrating up
  # - `Statement::Down`: SQL to run when migrating down
  # - `Statement::Error`: Prevents migration and raises an error
  class Migration
    # Abstract base class for migration statements.
    #
    # All migration statements (Up, Down, Error) inherit from this struct.
    # Statements automatically normalize text by:
    # - Stripping leading/trailing whitespace
    # - Removing SQL comment lines (starting with --)
    # - Removing empty lines
    # - Preserving SQL content and structure
    abstract struct Statement
      # The normalized SQL text for this statement
      getter text : String

      # Creates a new Statement with normalized text.
      #
      # Text processing:
      # 1. Strips leading and trailing whitespace
      # 2. Splits into lines and strips each line
      # 3. Removes SQL comment lines (-- comments)
      # 4. Removes empty lines
      # 5. Joins remaining lines with newlines
      #
      # @param text [String] The raw SQL text to normalize
      def initialize(text)
        @text =
          text.strip
              .split("\n")
              .map{|str| str.strip }
              .reject{|line| line =~ /^[\s\n\r]*\-\-/ || line.empty?}
              .join("\n")
      end

      # Represents an UP migration statement (runs when migrating forward).
      #
      # Example:
      # ```crystal
      # up = Migration::Statement::Up.new("CREATE TABLE foo (id INT);")
      # up.text # => "CREATE TABLE foo (id INT);"
      # ```
      struct Up < Statement
      end

      # Represents a DOWN migration statement (runs when migrating backward).
      #
      # Example:
      # ```crystal
      # down = Migration::Statement::Down.new("DROP TABLE foo;")
      # down.text # => "DROP TABLE foo;"
      # ```
      struct Down < Statement
      end

      # Represents an ERROR directive that prevents migration.
      #
      # When encountered during migration, raises `Migrate::Error` with the message.
      #
      # Example:
      # ```crystal
      # error = Migration::Statement::Error.new("Cannot reverse this migration")
      # error.text # => "Cannot reverse this migration"
      #
      # # With nil message, uses default
      # error = Migration::Statement::Error.new(nil)
      # error.text # => "Migration error command was given."
      # ```
      struct Error < Statement
        # Creates an Error statement with optional message.
        #
        # @param text [String | Nil] The error message, or nil for default message
        def initialize(text : String | Nil)
          text = "Migration error command was given." if text.nil?
          super(text)
        end
      end
    end

    # Regular expression for valid migration file names.
    #
    # Matches: `VERSION[_NAME].sql`
    # - VERSION: One or more digits (e.g., 1, 10, 20231121094530)
    # - NAME: Optional alphanumeric name with underscores/hyphens
    #
    # Examples:
    # - `1.sql` → version: "1", name: nil
    # - `10_create_users.sql` → version: "10", name: "create_users"
    # - `20231121_add_indexes.sql` → version: "20231121", name: "add_indexes"
    FILE_REGEX = /
      (?<version>\d+)       # e.g. 1 or 19 etc
      (?: \_                # separator
        (?<name>\w[\w+\-])  # e.g. first_one or first-one
      )?                    # It's optional
      \.sql                 # Extension
    $/x

    # Pattern for SQL comment prefix
    SQL_COMMENT = /\s*+\-{2,}+\s++/

    # Pattern for migration brand directives
    # Supports: +migrate, +migcrate (typo variant), +goose
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

    # Array of parsed Statement objects (Up, Down, or Error)
    getter statements : Array(Statement)

    # The file path this migration was loaded from (nil if created from string)
    getter path : Path | Nil

    # The migration version (extracted from filename or set manually)
    property version : String | Nil

    # Optional descriptive name (extracted from filename or set manually)
    property name : String | Nil

    # Creates a new Migration from SQL text.
    #
    # Parses the SQL text and extracts all statements marked with migration directives.
    #
    # Example:
    # ```crystal
    # sql = <<-SQL
    #   -- +migrate up
    #   CREATE TABLE users (id INT);
    #   -- +migrate down
    #   DROP TABLE users;
    # SQL
    #
    # migration = Migration.new(sql)
    # migration.statements.size # => 2
    # ```
    #
    # @param text [String] The SQL text containing migration directives
    # @raise [Exception] If no up/down/error directive is found
    def initialize(@text : String)
      @statements = [] of Statement
      process!
    end

    # Creates a new Migration from a file path.
    #
    # Reads the file, extracts version and name from filename, and parses statements.
    #
    # Example:
    # ```crystal
    # migration = Migration.new(Path["db/migrations/1_create_users.sql"])
    # migration.version # => "1"
    # migration.name    # => "create_users"
    # ```
    #
    # @param path [Path] Path to the migration file
    # @raise [Exception] If filename doesn't match VERSION[_NAME].sql pattern
    # @raise [Exception] If file cannot be read
    # @raise [Exception] If no migration directives found in file
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

    # Internal method that parses the migration text and extracts statements.
    #
    # Uses StringScanner to parse migration directives and SQL statements.
    # The parser is a state machine that:
    # 1. Finds the first directive (up/down/error)
    # 2. Collects statements until the next directive or end of file
    # 3. Handles complex SQL blocks between +migrate start/end
    #
    # State transitions:
    # - nil → Up/Down: Initial directive determines first state
    # - Up/Down → Up/Down: Direction can change mid-file
    # - Any → Error: Error directive stops processing that direction
    #
    # @raise [Exception] If no up/down/error directive found
    # @raise [Exception] If complex statement block is not properly closed
    private def process!
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
