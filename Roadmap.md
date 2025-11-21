# migrate.cr Roadmap - Complete the Refactoring

## Overview

This roadmap outlines the completion of the major refactoring started in the WIP commits on the `develop` branch (commits 8e8569b through 80c9d63). The refactoring represents a significant architectural improvement to support multiple databases, better SQL parsing, and improved testability.

**Status**: WIP commits indicate partial completion of a major rewrite
**Target Version**: 0.6.0
**Breaking Changes**: Yes - this is a major refactor with API changes

---

## Phase 1: Complete Core Refactoring

### 1.1 Migration Parser Rewrite ✓ (In Progress)

**Goal**: Replace simple line-by-line parser with robust StringScanner-based parser

**Current State**:
- ✓ StringScanner-based parser implemented
- ✓ Statement abstract struct with Up/Down/Error subtypes created
- ✓ Complex SQL support (triggers, procedures) added
- ✓ Multiple migration brands supported (+migrate, +goose)
- ✓ File version/name extraction from filenames

**Remaining Work**:
- [ ] Add comprehensive edge case tests for parser
- [ ] Handle malformed migration files gracefully
- [ ] Add parser error messages with line numbers
- [ ] Validate migration file structure before parsing
- [ ] Add support for transaction control directives
- [ ] Document all supported migration commands

**Implementation Details**:
```crystal
# Need to add:
- Statement::TransactionControl (for NO TRANSACTION directive)
- Better error context (line numbers, file paths)
- Migration validation method
- Parser state machine documentation
```

### 1.2 Migrator Class Modularization ✓ (In Progress)

**Goal**: Split monolithic Migrator into organized modules

**Current State**:
- ✓ Migrator::Actions module created (migration operations)
- ✓ Migrator::SQL module created (SQL generation)
- ✓ Two initialization modes (file-based and array-based)
- ✓ Version tracking changed to strings
- ✓ Default table renamed to `migrate_versions`

**Remaining Work**:
- [ ] Complete migration from old to new structure
- [ ] Add validation module for pre-flight checks
- [ ] Add reporting module for migration status
- [ ] Implement migration history tracking
- [ ] Add rollback safety checks
- [ ] Create comprehensive integration tests

**Breaking Changes**:
- `current_version` returns `String` instead of `Int32 | Int64`
- Default table name: `version` → `migrate_versions`
- Versions stored as strings in database
- Removed `MIGRATION_FILE_REGEX` constant exposure

### 1.3 Database-Agnostic Schema ✓ (In Progress)

**Goal**: Remove database-specific SQL from core

**Current State**:
- ✓ Column type changed from `BIGINT NOT NULL` to `NOT NULL`
- ✓ SQLite3 explicit dependency added

**Remaining Work**:
- [ ] Create database adapter pattern
- [ ] Implement PostgreSQL adapter
- [ ] Implement SQLite adapter
- [ ] Implement MySQL adapter (optional)
- [ ] Auto-detect database type from connection
- [ ] Add database-specific type mapping
- [ ] Test with all supported databases

**Implementation Structure**:
```
src/migrate/
  adapters/
    base.cr         # Abstract adapter interface
    postgresql.cr   # PostgreSQL-specific SQL
    sqlite.cr       # SQLite-specific SQL
    mysql.cr        # MySQL-specific SQL (future)
```

---

## Phase 2: Enhanced Features ✅ (Completed)

### 2.1 Migration Validation & Safety ✅

**New Capabilities Enabled by Statement Objects**:

- [x] **Pre-flight Validation** ✅ (Completed in Phase 1)
  - Check all migrations parse successfully before running any
  - Validate migration order/numbering
  - Detect duplicate version numbers
  - Warn about missing down migrations

- [x] **Dry Run Mode** ✅
  ```crystal
  result = migrator.dry_run(target_version)
  # Returns: DryRunResult with migrations and statements that would be executed
  ```

- [x] **Migration Checksums** ✅
  - Store checksum of executed migrations
  - Detect if applied migrations were modified
  - Prevent accidental changes to history

- [x] **Rollback Safety** ✅
  - Verify down migrations exist before allowing rollback
  - Detect destructive operations (DROP TABLE, etc.) with severity levels
  - Warn about destructive operations before execution

### 2.2 Better Error Handling & Reporting ✅

- [x] **Structured Error Information** ✅
  ```crystal
  MigrationExecutionError
    - migration_version : String
    - migration_name : String?
    - statement_index : Int32?
    - statement : String?
    - direction : Direction
    - original_error : Exception
  ```

- [x] **Migration Status Reporting** ✅ (Completed in Phase 1)
  ```crystal
  migrator.status
  # Returns:
  # Current version: 5
  # Latest version: 10
  # Pending migrations:
  #   6_add_users_table.sql
  #   7_add_indexes.sql
  #   ...
  ```

- [x] **Verbose Logging** ✅
  - Log each statement being executed
  - Show execution time per migration
  - Configurable statement preview length
  - Batch summary with statistics

### 2.3 Advanced Migration Features

- [ ] **Reversible Migrations**
  - Automatic down migration generation for simple cases
  - Detect irreversible operations

- [ ] **Data Migrations**
  - Support for data transformation migrations
  - Separate schema vs data migration tracking

- [ ] **Conditional Migrations**
  ```sql
  -- +migrate up if table_exists('old_table')
  -- +migrate up if version < 5
  ```

- [ ] **Migration Dependencies**
  ```sql
  -- +migrate requires 4_create_users
  ```

---

## Phase 3: Testing & Quality

### 3.1 Test Suite Completion

**Current State**:
- ✓ SQLite migration specs created
- ✓ SQLite migrator specs created
- ✓ Test fixtures organized under spec/fixtures/

**Remaining Work**:

- [ ] **Unit Tests**
  - [ ] Complete Migration parser edge cases
  - [ ] Test all Statement types
  - [ ] Test version comparison logic
  - [ ] Test error handling paths

- [ ] **Integration Tests**
  - [ ] PostgreSQL integration tests
  - [ ] SQLite integration tests
  - [ ] Multi-database test suite
  - [ ] Transaction rollback tests
  - [ ] Concurrent migration tests

- [ ] **Property-Based Tests**
  - [ ] Random migration sequences
  - [ ] Fuzz testing for parser
  - [ ] Stress testing with large migration sets

### 3.2 Performance Testing

- [ ] Benchmark migration performance
- [ ] Test with 1000+ migrations
- [ ] Optimize file reading for large migration sets
- [ ] Add migration caching for repeated runs

### 3.3 Code Quality

- [ ] Run Crystal formatter on all files
- [ ] Add Ameba linter configuration
- [ ] Fix all compiler warnings
- [ ] Add type annotations where missing
- [ ] Document all public APIs
- [ ] Add code examples in documentation

---

## Phase 4: Migration Path & Documentation

### 4.1 Migration Guide for Users

- [ ] **Version 0.5.x → 0.6.0 Guide**
  - API changes documentation
  - Database schema migration script
  - Code update examples
  - Deprecation warnings

- [ ] **Schema Migration Script**
  ```sql
  -- Script to convert old version table to new format
  ALTER TABLE version RENAME TO migrate_versions;
  ALTER TABLE migrate_versions ALTER COLUMN version TYPE VARCHAR;
  ```

### 4.2 Updated Documentation

- [ ] **README Updates**
  - [ ] New API examples
  - [ ] Migration file format documentation
  - [ ] All supported commands reference
  - [ ] Database adapter documentation
  - [ ] Error handling guide

- [ ] **API Documentation**
  - [ ] Complete yard-style docs for all public methods
  - [ ] Add examples to each method
  - [ ] Document exceptions that can be raised
  - [ ] Add usage patterns documentation

- [ ] **Advanced Guides**
  - [ ] Complex SQL migrations guide
  - [ ] Testing migrations guide
  - [ ] Multiple database support guide
  - [ ] Custom adapter development guide

### 4.3 Examples & Recipes

- [ ] Create `examples/` directory with:
  - [ ] Basic migration example
  - [ ] Complex SQL (triggers, functions) example
  - [ ] Multi-database setup example
  - [ ] Testing migrations example
  - [ ] Custom adapter example
  - [ ] CLI tool example

---

## Phase 5: New Features & Enhancements

### 5.1 CLI Tool

- [ ] Create standalone CLI tool `migrate-cli`
  ```bash
  migrate up              # Run pending migrations
  migrate down            # Rollback one migration
  migrate status          # Show migration status
  migrate create NAME     # Generate new migration file
  migrate validate        # Validate all migrations
  migrate rollback N      # Rollback N migrations
  ```

### 5.2 Migration Generation

- [ ] **Migration File Generator**
  ```crystal
  Migrate::Generator.create("add_users_table")
  # Creates: db/migrations/001_add_users_table.sql
  ```

- [ ] **Smart Templates**
  - Detect migration type from name
  - Generate appropriate up/down stubs
  - Add helpful comments

### 5.3 Advanced Database Features

- [ ] **Connection Pooling Support**
- [ ] **Read Replica Support** (run migrations on primary only)
- [ ] **Distributed Migrations** (coordination across multiple instances)
- [ ] **Schema Dump/Load** for faster testing

### 5.4 Monitoring & Observability

- [ ] Migration metrics (duration, success/failure)
- [ ] Integration with monitoring systems
- [ ] Structured logging (JSON output)
- [ ] Migration event hooks

---

## Phase 6: Release Preparation

### 6.1 Pre-Release Checklist

- [ ] All tests passing (100% coverage goal)
- [ ] Documentation complete
- [ ] Migration guide reviewed
- [ ] CHANGELOG.md updated
- [ ] Version bumped to 0.6.0
- [ ] Breaking changes documented
- [ ] Performance benchmarks run
- [ ] Security review completed

### 6.2 Release Process

- [ ] Create release branch `release/0.6.0`
- [ ] Tag version `v0.6.0`
- [ ] Publish to shards registry
- [ ] Announce on Crystal forum
- [ ] Update awesome-crystal listing
- [ ] Create GitHub release with notes

### 6.3 Post-Release

- [ ] Monitor for bug reports
- [ ] Prepare patch releases if needed
- [ ] Gather community feedback
- [ ] Plan 0.7.0 features based on feedback

---

## Implementation Priority

### High Priority (Core Functionality)
1. ✅ Complete Migration parser tests
2. ✅ Complete Migrator modularization tests
3. ✅ Database adapter pattern implementation
4. ✅ Migration validation & dry-run
5. ✅ Updated documentation

### Medium Priority (Enhanced Features)
6. ✅ Migration checksums
7. ✅ Better error reporting with context
8. CLI tool
9. Migration generation
10. Performance optimization

### Low Priority (Nice to Have)
11. Advanced features (conditional migrations, dependencies)
12. Monitoring/observability
13. Distributed migrations
14. Additional database adapters

---

## Technical Debt to Address

### Code Quality Issues Found in WIP

1. **TODO Comments in Code**
   - `src/migrate/migrator/actions.cr:10` - "does it really need the casting?"
   - `src/migrate/migrator/actions.cr:74` - "split into a 'down' and an 'up' via a macro"

2. **Error Handling**
   - Generic error messages without context
   - No line numbers in parse errors
   - Missing validation errors

3. **Type Safety**
   - Mixed use of String/Int64 for versions
   - Excessive use of `.not_nil!`
   - Missing null checks

4. **Performance**
   - Re-reading migration files on each run
   - No caching of parsed migrations
   - Inefficient regex matching

---

## Breaking Changes Summary

### API Changes
- `Migrator#current_version` returns `String` (was `Int32 | Int64`)
- `Migrator#next_version` returns `String | Nil` (was `Int64 | Nil`)
- `Migrator#previous_version` returns `String | Nil` (was `Int64 | Nil`)
- `Migrator#all_versions` returns `Array(String)` (was `Array(Int64)`)
- Default table name: `migrate_versions` (was `version`)

### Database Schema
- Version column type: `VARCHAR` or `TEXT` (was `BIGINT`)
- Version values stored as strings (was integers)

### Module Structure
- `Migration::Error` moved to `Migrate::Error`
- Removed `src/migrate/migration/error.cr`
- Added `src/migrate/migrator/actions.cr`
- Added `src/migrate/migrator/sql.cr`

### Behavior Changes
- Versions compared as strings, not integers
- Migration files must match `\d+(_\w+)?\.sql` pattern
- Error handling changed (Statement::Error objects)

---

## Success Criteria

### Definition of Done

- [ ] All phases 1-3 completed
- [ ] Test coverage > 90%
- [ ] All documentation updated
- [ ] Migration guide published
- [ ] Zero breaking bugs in beta testing
- [ ] Performance equal or better than 0.5.x
- [ ] Positive community feedback

### Quality Metrics

- Code coverage: 90%+
- Documentation coverage: 100% of public API
- Performance: ≤ 5% regression from 0.5.x
- Breaking changes: All documented with migration path

---

## Timeline Estimate

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| Phase 1 | 2-3 weeks | None |
| Phase 2 | 2-3 weeks | Phase 1 |
| Phase 3 | 1-2 weeks | Phase 1-2 |
| Phase 4 | 1 week | Phase 1-3 |
| Phase 5 | 2-3 weeks | Phase 1-4 |
| Phase 6 | 1 week | All phases |

**Total Estimate**: 9-13 weeks for complete implementation

**Minimum Viable Release (0.6.0-beta)**: Phase 1-3 only = 5-8 weeks

---

## Notes

- This roadmap assumes no backward compatibility requirements
- Breaking changes are acceptable for this major refactor
- Focus on correctness and features over backward compatibility
- Consider a beta release after Phase 3 for community testing
- Future versions (0.7.x) can add features without breaking changes

---

**Last Updated**: 2025-11-21
**Status**: Phase 2 Complete - Enhanced features implemented (dry run, checksums, safety checks, verbose logging, enhanced errors)
