# WorkBench Development Instructions

## Working principles

- Treat this repository as a production-quality application.
- Prefer simple, maintainable designs over clever abstractions.
- Do not add dependencies without explaining why they are necessary.
- Never commit credentials, signing certificates, API keys, tokens, or secrets.
- Do not modify files outside this repository.
- Do not reuse legacy code unless explicitly instructed.
- Make small, reviewable changes.
- Run relevant tests after every functional change.
- Report warnings and test failures rather than hiding them.

## Before implementing a feature

1. Restate the requested behavior.
2. Inspect the relevant existing code and documentation.
3. Propose a concise implementation plan.
4. Identify risks, assumptions, and affected files.
5. Wait for approval when the change alters architecture, dependencies,
   persistence, security, privacy, or public interfaces.

## Definition of done

A change is complete only when:

- The requested behavior works.
- Relevant automated tests exist and pass.
- Existing tests continue to pass.
- Build warnings have been reviewed.
- User-facing or architectural behavior is documented.
- The resulting diff contains no unrelated changes.

## Git practices

- Work on one logical change at a time.
- Use descriptive branch and commit names.
- Do not rewrite published history.
- Do not commit generated build artifacts.
- Keep commits small enough to review.
