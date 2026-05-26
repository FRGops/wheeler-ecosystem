# API Acceptance Rubric

## Score Ranges

| Score | Rating | Description |
|-------|--------|-------------|
| 90-100 | Production-Ready | Secure, documented, tested, performant |
| 75-89 | Good | Minor issues in docs or edge cases |
| 60-74 | Adequate | Functional but needs hardening |
| < 60 | Not Ready | Security or correctness issues |

## Dimensions

### Security (30 points)
- Authentication required (where appropriate)
- Authorization checks in place
- Input validation on all parameters
- Rate limiting considered
- No sensitive data in responses
- HTTPS enforced

### Correctness (25 points)
- Returns correct status codes (200, 201, 400, 401, 403, 404, 500)
- Error responses follow standard format
- Idempotency where needed (PUT, DELETE)
- Pagination on list endpoints

### Performance (20 points)
- Response time < 200ms (p50)
- Response time < 1000ms (p99)
- No N+1 queries
- Appropriate caching headers
- Payload size reasonable

### Documentation (15 points)
- Endpoint documented (method, path, params, response)
- Example request/response
- Error codes documented
- Authentication documented

### Testing (10 points)
- Unit tests for business logic
- Integration tests for endpoints
- Error cases tested
- Edge cases covered

## Automatic Checks
- OpenAPI/Swagger spec valid
- Response schema matches spec
- No 500 errors on valid input

## What Blocks 100/100
- Missing authentication on protected endpoint
- Missing input validation
- SQL injection vector
- Unhandled error returning stack trace
- Breaking change without version bump
