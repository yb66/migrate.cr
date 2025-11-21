# Claude.md - AI Agent Guide for migrate.cr

## Project Overview

**migrate.cr** is a database migration tool for Crystal applications, providing a clean and simple way to manage database schema changes with SQL migration files.

### Key Features
- SQL-based migrations with up/down directions
- Transaction-based migration execution (each migration runs in its own transaction)
- Support for complex SQL statements (functions, triggers, etc.)
- Version tracking via configurable database table
- Programmatic migration control (up, down, to, reset, redo, to_latest)
- Integration with task runners (Cakefile, Sam.cr)

### Technology Stack
- **Language**: Crystal 1.2.0
- **Primary Dependencies**:
  - `crystal-db` (~> 0.10.1) - Database abstraction layer
  - `time_format` (~> 0.1.0) - Time formatting utilities
- **Development Dependencies**:
  - `crystal-pg` (~> 0.24.0) - PostgreSQL driver for testing

## Project Structure

```
migrate.cr/
├── src/
│   ├── migrate.cr                    # Main entry point, defines Direction enum
│   └── migrate/
│       ├── version.cr                # Version constant
│       ├── migrator.cr               # Core Migrator class
│       ├── migration.cr              # Migration file parser
│       └── migration/
│           └── error.cr              # Custom error class
├── spec/
│   ├── spec_helper.cr
│   ├── migrations/                   # Test migration files
│   ├── migrations_with_errors/       # Test migrations with error handling
│   └── migrate/
│       ├── migration_spec.cr
│       ├── migrator_spec.cr
│       └── migrator_with_errors_spec.cr
└── db/migrations/                    # Default migrations directory (user-created)
```

## Core Components

### 1. Migrator (`src/migrate/migrator.cr`)

The main class that handles migration execution.

**Key Methods**:
- `current_version` - Returns current DB version
- `next_version` - Returns next available version
- `previous_version` - Returns previous version
- `up` - Migrate one step up
- `down` - Migrate one step down
- `to(version)` - Migrate to specific version
- `to_latest` - Migrate to the latest version
- `reset` - Revert all migrations to version 0
- `redo` - Reset and re-apply all migrations to current version
- `latest?` - Check if at latest version

**Configuration**:
```crystal
Migrate::Migrator.new(
  @db : DB::Database,        # Database connection
  @dir : String,             # Migration files directory (default: "db/migrations")
  @table : String,           # Version table name (default: "version")
  @column : String           # Version column name (default: "version")
)
```

### 2. Migration (`src/migrate/migration.cr`)

Parses SQL migration files and extracts queries for up/down directions.

**Migration File Format**:
```sql
-- +migrate up
CREATE TABLE users (id SERIAL PRIMARY KEY);

-- +migrate down
DROP TABLE users;
```

**Special Commands**:
- `-- +migrate up` - Marks beginning of up migration
- `-- +migrate down` - Marks beginning of down migration
- `-- +migrate start` - Start complex statement block (for functions, triggers with semicolons)
- `-- +migrate end` - End complex statement block
- `-- +migrate error <message>` - Define irreversible migration error

### 3. Migration Files

**Naming Convention**: `{version}[_{name}].sql`
- Version must be numeric (e.g., `1.sql`, `2_create_users.sql`, `10_add_indexes.sql`)
- Versions are applied in numeric order, not filename order
- Optional name is for documentation only

**Regex**: `/(?<version>\d+)(_(?<name>\w+))?\.sql/`

## Development Workflow

### Branch Strategy
- **develop**: Main development branch (if it exists)
- **master**: Production/release branch
- Development typically happens on feature branches

### Running Tests

Tests require a PostgreSQL database:

```bash
# Create test database
createdb migrate_test

# Run tests
env DATABASE_URL=postgres://postgres:postgres@localhost:5432/migrate_test crystal spec
```

### Building the Project

```bash
# Install dependencies
shards install

# Build
crystal build src/migrate.cr

# Run specs
crystal spec
```

## Migration Execution Flow

1. **Initialization**: Migrator ensures version table exists
2. **Version Detection**: Queries current version from database
3. **Direction Determination**: Compares current vs target version
4. **File Selection**: Selects migration files based on version range
5. **Parsing**: Each file is parsed to extract up/down queries
6. **Transaction Execution**: Each migration runs in its own transaction
   - Execute all queries in order
   - Update version table
   - Commit or rollback on error
7. **Logging**: Log migration progress and timing

## Important Implementation Details

### Version 0
- Version 0 represents "no migrations applied"
- Always included in `all_versions` array
- Starting point for fresh databases

### Transaction Behavior
- Each migration file runs in a separate transaction
- If a migration fails, only that migration is rolled back
- Previously applied migrations in the batch remain committed
- Partial migration state is possible on errors

### Migration Ordering
- Files are sorted by numeric version, not filename
- `1.sql`, `2.sql`, `10.sql` applies in order 1 → 2 → 10
- Not: `1.sql`, `10.sql`, `2.sql`

### Complex Statements
For SQL statements containing semicolons (like PL/pgSQL functions):
```sql
-- +migrate up
-- +migrate start
CREATE OR REPLACE FUNCTION my_function()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- +migrate end
```

### Error Handling
Mark irreversible migrations explicitly:
```sql
-- +migrate up
ALTER TABLE users DROP COLUMN sensitive_data;

-- +migrate down
-- +migrate error Cannot restore dropped sensitive_data column
```

## Common Tasks for AI Agents

### Adding a New Feature
1. Create feature branch from develop (or master if no develop)
2. Implement changes in `src/migrate/`
3. Add corresponding specs in `spec/`
4. Ensure all tests pass
5. Update version if needed

### Fixing a Bug
1. Add failing test case first
2. Implement fix
3. Verify all tests pass
4. Check edge cases (version 0, empty migrations, errors)

### Refactoring
1. Ensure test coverage exists
2. Make incremental changes
3. Run tests after each change
4. Maintain backward compatibility is NOT a concern (per user)

### Adding Tests
- Use PostgreSQL database for integration tests
- Test both up and down migrations
- Test error conditions
- Test edge cases (version 0, missing versions, etc.)

## Debugging Tips

### Enable Debug Logging
Crystal's Log module is used for logging:
- `Log.info` - Migration progress
- `Log.debug` - SQL queries executed
- `Log.warn` - Non-critical issues

### Common Issues
1. **Version not found**: Ensure migration files exist in directory
2. **Transaction errors**: Check SQL syntax in migration files
3. **Complex statement parsing**: Use `-- +migrate start/end` blocks
4. **Version table issues**: Check table/column configuration matches DB

## Testing Checklist

When modifying code, verify:
- [ ] All existing specs pass
- [ ] New specs added for new functionality
- [ ] Edge cases covered (version 0, empty migrations, etc.)
- [ ] Up and down migrations both work
- [ ] Transaction rollback works on errors
- [ ] Complex SQL statements parse correctly
- [ ] Version tracking updates correctly

## Dependencies and Compatibility

### Crystal Version
- Currently requires Crystal 1.2.0
- Check `shard.yml` for exact version

### Database Support
- Primary support: PostgreSQL
- Uses `crystal-db` abstraction layer
- Other databases may work but are not officially tested

### Key Dependencies
- `db`: Core database abstraction (github: crystal-lang/crystal-db)
- `time_format`: Human-readable time formatting (github: vladfaust/time_format.cr)

## Code Style and Conventions

### Crystal Conventions
- Use 2 spaces for indentation
- Follow Crystal style guide
- Use type annotations where helpful for clarity
- Prefer `not_nil!` over `as` for non-nil assertions when certain

### Project-Specific Patterns
- Use `protected` for methods used in testing
- SQL templates use `%{var}` interpolation style
- Regex patterns are defined as constants
- Direction enum for up/down clarity

## Resources

### Documentation
- Main README.md contains user-facing documentation
- API docs available at: https://github.vladfaust.com/migrate.cr
- Crystal docs: https://crystal-lang.org/docs/

### Related Projects
- crystal-db: https://github.com/crystal-lang/crystal-db
- crystal-pg: https://github.com/will/crystal-pg
- Cakefile: https://github.com/axvm/cake
- Sam.cr: https://github.com/imdrasil/sam.cr

## Quick Reference

### Migrator API
```crystal
require "migrate"

migrator = Migrate::Migrator.new(db, dir, table, column)

migrator.current_version  # Get current version
migrator.next_version     # Get next version
migrator.previous_version # Get previous version
migrator.latest?          # At latest version?

migrator.up               # Migrate up one version
migrator.down             # Migrate down one version
migrator.to(10)           # Migrate to version 10
migrator.to_latest        # Migrate to latest
migrator.reset            # Reset to version 0
migrator.redo             # Reset and re-apply to current
```

### Migration File Template
```sql
-- +migrate up
-- Your up migration SQL here
CREATE TABLE example (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL
);

CREATE INDEX example_name_idx ON example (name);

-- +migrate down
-- Your down migration SQL here
DROP TABLE example;
```

### Complex Statement Example
```sql
-- +migrate up
-- +migrate start
CREATE OR REPLACE FUNCTION auto_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- +migrate end

CREATE TRIGGER set_timestamp
  BEFORE UPDATE ON my_table
  FOR EACH ROW
  EXECUTE FUNCTION auto_timestamp();

-- +migrate down
DROP TRIGGER IF EXISTS set_timestamp ON my_table;
DROP FUNCTION IF EXISTS auto_timestamp();
```

## Notes for AI Agents

- **Backward Compatibility**: Not a concern for this project (per user specification)
- **Primary Database**: PostgreSQL is the primary target
- **Testing Required**: Always ensure tests pass before committing
- **Migration Files**: Example migration files in `spec/migrations/` directory
- **Logging**: Use existing Log statements as examples for new code
- **Error Messages**: Should be clear and actionable for users
