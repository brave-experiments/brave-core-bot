# Front-End Best Practices

## ❌ Don't Spread Args in Render Helpers or Components

**Avoid spreading `...args` into `render()`, component props, or other React APIs.** Spreading arbitrary arguments can allow unexpected attributes to be injected, potentially leading to XSS. Pass explicit props instead.

```tsx
// ❌ WRONG - spreading arbitrary args
async function renderMyComponent(
  ...args: Parameters<typeof render>
): Promise<ReturnType<typeof render>> {
  let result: ReturnType<typeof render>
  await act(async () => {
    result = render(...args)
  })
  return result!
}

// ✅ CORRECT - explicit props
async function renderMyComponent(
  ui: React.ReactElement,
  options?: RenderOptions
): Promise<RenderResult> {
  let result: RenderResult
  await act(async () => {
    result = render(ui, options)
  })
  return result!
}
```

---

## ❌ Avoid Redundant React Keys

**When a parent component already assigns a `key` prop to a child in a list, the child should not redundantly set its own key on inner elements for list-keying purposes.** Redundant keys suggest a misunderstanding of React's reconciliation boundary.

```tsx
// ❌ WRONG - parent already provides key
{items.map((item) => (
  <AttachmentItem key={item.id}>
    <div key={item.id}>{item.name}</div>  {/* Redundant! */}
  </AttachmentItem>
))}

// ✅ CORRECT - key only on the list element
{items.map((item) => (
  <AttachmentItem key={item.id}>
    <div>{item.name}</div>
  </AttachmentItem>
))}
```

---

## ✅ Move Utility Functions to Dedicated Modules

**Pure utility functions should live in dedicated utility modules (e.g., `utils/conversation_history_utils.ts`), not in React context/state files.** Context files should focus on state management, not data transformation logic.

---

## ✅ Merge Similar UI Components

**When adding support for a new file type to an upload/attachment UI, merge similar components into a single generic one** rather than creating parallel components.

```tsx
// ❌ WRONG - separate components for each type
<AttachmentImageItem />
<AttachmentDocumentItem />

// ✅ CORRECT - single generic component
<AttachmentUploadItem type={file.type} />
```

---

## ❌ Don't Redefine Types from Generated Bindings

**In TypeScript tests, import enum types from generated Mojo bindings or source files.** Do not redefine or duplicate them in test files.

```tsx
// ❌ WRONG - redefining enum from mojom
enum FileType {
  kImage = 0,
  kDocument = 1,
}

// ✅ CORRECT - import from generated bindings
import { FileType } from 'gen/brave/components/ai_chat/core/common/mojom/ai_chat.mojom-webui.js'
```
