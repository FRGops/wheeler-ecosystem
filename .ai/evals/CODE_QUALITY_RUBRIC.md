# Code Quality Rubric

## Score Ranges

| Score | Rating | Description |
|-------|--------|-------------|
| 90-100 | A | Production-grade, idiomatic, well-structured |
| 75-89 | B | Good quality, minor improvements possible |
| 60-74 | C | Functional but needs refactoring |
| < 60 | D | Technical debt — rewrite recommended |

## Dimensions

### Readability (25 points)
- Clear naming (variables, functions, types)
- Appropriate function length (< 50 lines typically)
- Consistent formatting
- No commented-out code

### Maintainability (25 points)
- Single responsibility principle
- Low coupling between modules
- Dependency injection where appropriate
- No magic numbers/strings

### Robustness (25 points)
- Error handling on external calls
- Null/undefined checks where needed
- Input validation at boundaries
- Timeouts on network operations

### Performance (15 points)
- No N+1 queries
- Appropriate data structures
- No obvious memory leaks
- Lazy loading where appropriate

### Convention Adherence (10 points)
- Follows project style guide
- Consistent file structure
- Proper use of TypeScript/types
- Follows existing patterns

## Automatic Checks
- ESLint/Prettier: clean
- TypeScript strict: no errors
- Tree-shaking: no unused exports
- Cyclomatic complexity: < 15 per function

## What Blocks 100/100
- Linter errors
- Type errors
- Any `any` type without justification
- Function > 100 lines without justification
- Commented-out code blocks
