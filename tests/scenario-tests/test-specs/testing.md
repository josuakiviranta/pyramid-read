# Todo App — Testing

## Strategy

Three layers: server integration tests, client unit tests, and E2E tests.

- **TDD:** write failing test first, then implement
- **Isolation:** server tests use `:memory:` SQLite; client tests mock the API layer
- **E2E last:** Playwright tests run against the full running stack

## Server Tests (Vitest + Supertest)

Location: `server/src/__tests__/todos.test.ts`

Run: `npm test --workspace=server`

Covers:
- `GET /api/todos` — empty list, ordered list
- `POST /api/todos` — creates with defaults, with priority, 400 on bad input
- `PATCH /api/todos/:id` — updates text/completed/priority, 404 on missing id
- `DELETE /api/todos/:id` — deletes, 404 on missing id

## Client Tests (Vitest + React Testing Library)

Location: `client/src/**/*.test.tsx`

Run: `npm test --workspace=client`

Covers:
- `TodoInput` — renders, submits, resets, disables on empty
- `TodoItem` — checkbox toggle, inline edit (enter/escape/blur), delete
- `TodoList` — renders items, shows empty state
- `App` — fetches on mount, passes handlers, integrates components
- `api.ts` — mocks fetch, tests all 4 wrappers

## E2E Tests (Playwright)

Location: `e2e/`

Run: `npm run test:e2e` (requires `npm run dev` running)

Test files:
- `todo-crud.spec.ts` — create, edit, complete, delete flows
- `priority.spec.ts` — priority selection and badge display
- `scenarios/capture-and-complete.spec.ts`
- `scenarios/correct-a-mistake.spec.ts`
- `scenarios/prioritized-workday.spec.ts`
- `scenarios/clean-up-list.spec.ts`
