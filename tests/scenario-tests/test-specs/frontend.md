# Todo App — Frontend

## Component Tree

```
App
├── TodoInput           # text field + priority select + submit button
└── TodoList
    └── TodoItem[]      # checkbox + text (inline edit) + priority badge + delete
```

## App

`client/src/App.tsx` — root component, owns the `todos` state array.

- Fetches all todos on mount via `api.getTodos()`
- Passes todos and CRUD handlers down to children
- Handlers: `handleCreate`, `handleUpdate`, `handleDelete`

## TodoInput

`client/src/components/TodoInput.tsx`

- Controlled text input + priority `<select>` (low/medium/high, default medium)
- Submit: calls `onSubmit(text, priority)`, resets form on success
- Disables submit when text is empty

## TodoList

`client/src/components/TodoList.tsx`

- Renders `<TodoItem>` for each todo in the array
- Empty state: shows "No todos yet" message

## TodoItem

`client/src/components/TodoItem.tsx`

- **Checkbox:** toggles `completed`, calls `onUpdate(id, { completed: 0|1 })`
- **Text:** double-click to enter inline edit mode; blur or Enter saves; Escape cancels
- **Priority badge:** color-coded pill (low=gray, medium=blue, high=red)
- **Delete button:** calls `onDelete(id)`

## API Layer

`client/src/lib/api.ts` — typed fetch wrappers, base URL `/api/todos`.

```typescript
getTodos(): Promise<Todo[]>
createTodo(text: string, priority: string): Promise<Todo>
updateTodo(id: number, patch: Partial<Todo>): Promise<Todo>
deleteTodo(id: number): Promise<void>
```

All functions throw on non-2xx responses.
