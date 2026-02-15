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

---

## ❌ Avoid Unnecessary `useMemo` for Simple Property Access

**Don't wrap simple property lookups in `useMemo`.** Accessing `array.length`, `obj.property`, or other trivial derivations is cheaper than React's memoization overhead.

```tsx
// ❌ WRONG - useMemo for trivial access
const count = useMemo(() => items.length, [items])

// ✅ CORRECT - direct access
const count = items.length
```

---

## ✅ Return Null from Components When No Data

**React components should return `null` early when there's no data to render,** rather than rendering empty containers or placeholder markup that adds unnecessary DOM nodes.

```tsx
// ❌ WRONG - renders empty container
function UserInfo({ user }: Props) {
  return <div className="user-info">{user ? user.name : ''}</div>
}

// ✅ CORRECT - return null when no data
function UserInfo({ user }: Props) {
  if (!user) return null
  return <div className="user-info">{user.name}</div>
}
```

---

## ✅ Use `generateReactContextForAPI` for Mojo API Contexts

**Use the `generateReactContextForAPI` helper from `components/common/react_api.tsx`** for creating React context + provider pairs for Mojo API bindings. Don't write custom context boilerplate for each API.

---

## ✅ Use Partial Value Updates Instead of Spread-Then-Modify

**When updating state objects, prefer partial update functions over spreading the entire object and overriding one field.** This is more efficient and less error-prone.

```tsx
// ❌ WRONG - spread then override
setState({ ...state, isLoading: true })

// ✅ CORRECT - partial update
setPartialState({ isLoading: true })
```

---

## ❌ Don't Provide Defaults for Leo CSS Variables

**Never provide fallback/default values for Leo design system CSS custom properties.** Leo variables are guaranteed to be set by the design system; providing defaults can mask theming bugs and produce inconsistent styling.

```css
/* ❌ WRONG - default masks theming bugs */
color: var(--leo-color-text-primary, #000);

/* ✅ CORRECT - trust the design system */
color: var(--leo-color-text-primary);
```

---

## ✅ Use `I18nMixinLit` for Localization in Lit Components

**In Lit-based WebUI components, use `I18nMixinLit` instead of calling `loadTimeData.getString()` directly.** The mixin provides consistent i18n patterns and is the standard approach.

---

## ✅ New UI Components Must Have Storybook Stories

**All new UI components must have Storybook stories covering their primary states** (default, loading, error, empty, populated). Stories serve as both documentation and visual regression baselines.

---

## ❌ TS Mojom Bindings Generate Interfaces, Not Classes

**TypeScript WebUI mojom bindings generate interfaces, not classes.** This means `instanceof` checks won't work on mojom types. Use type guards or discriminated unions instead.

```tsx
// ❌ WRONG - instanceof on mojom-generated type
if (value instanceof mojom.ConversationTurn) { ... }

// ✅ CORRECT - type guard or property check
if ('text' in value && 'role' in value) { ... }
```

---

## ✅ WebUI Resource Files Must Be in Correct Top-Level Directory

**WebUI resource files must be placed in the correct top-level directory under `resources/` matching the WebUI host name.** Misplaced resources won't be found at runtime.
