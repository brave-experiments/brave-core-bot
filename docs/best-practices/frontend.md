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
