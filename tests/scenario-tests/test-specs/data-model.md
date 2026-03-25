# Todo App — Data Model

## Database Schema

Single table `todos` in SQLite (`:memory:` in test, `todos.db` in dev/prod):

```sql
CREATE TABLE IF NOT EXISTS todos (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  text       TEXT    NOT NULL,
  completed  INTEGER NOT NULL DEFAULT 0,   -- 0 = false, 1 = true
  priority   TEXT    NOT NULL DEFAULT 'medium',
  created_at TEXT    NOT NULL DEFAULT (datetime('now'))
);
```

Valid priority values: `'low'` | `'medium'` | `'high'`

## TypeScript Types

Shared shape used across client and server:

```typescript
interface Todo {
  id: number
  text: string
  completed: 0 | 1        // SQLite integer boolean
  priority: 'low' | 'medium' | 'high'
  created_at: string       // ISO datetime string
}
```

## Notes

- `completed` is stored as SQLite integer (0/1), not JS boolean
- Todos are always returned ordered by `created_at DESC`
- No soft-delete — DELETE removes the row permanently
