# Todo App — API

## Base URL

`/api/todos` — proxied to Express on `:3001` in dev, served directly in prod.

## Endpoints

### GET /api/todos

Returns all todos ordered by `created_at DESC`.

**Response 200:**
```json
[
  { "id": 2, "text": "Buy milk", "completed": 0, "priority": "high", "created_at": "2024-01-02T10:00:00" },
  { "id": 1, "text": "Walk dog", "completed": 1, "priority": "medium", "created_at": "2024-01-01T09:00:00" }
]
```

### POST /api/todos

Creates a new todo.

**Request body:**
```json
{ "text": "Buy milk", "priority": "high" }
```
`priority` defaults to `"medium"` if omitted.

**Response 201:** The created todo object.

**Response 400:** `{ "error": "text is required" }` or `{ "error": "invalid priority" }`

### PATCH /api/todos/:id

Updates `text`, `completed`, or `priority` (any subset).

**Request body:** `{ "text"?: string, "completed"?: 0|1, "priority"?: string }`

**Response 200:** The updated todo object.

**Response 404:** `{ "error": "not found" }` if id doesn't exist.

**Response 400:** `{ "error": "invalid priority" }` if priority value invalid.

### DELETE /api/todos/:id

Deletes the todo permanently.

**Response 200:** `{ "deleted": true }`

**Response 404:** `{ "error": "not found" }` if id doesn't exist.
