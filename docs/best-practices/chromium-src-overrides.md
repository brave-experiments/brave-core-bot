# chromium_src Overrides

## ✅ Minimize Code Duplication in Overrides

**When overriding Chromium code via `chromium_src/`, prefer wrapping only the changed section and falling back to `ChromiumImpl` for everything else.**

Don't duplicate entire functions when only part of the logic needs to change.

**BAD:**
```cpp
// ❌ WRONG - duplicating the entire function
SkColor ChromeTypographyProvider::GetColor(...) {
  // 50 lines copied from upstream...
  // only 3 lines are actually different
}
```

**GOOD:**
```cpp
// ✅ CORRECT - wrap only the changed section
SkColor ChromeTypographyProvider::GetColor(...) {
  if (!ShouldIgnoreHarmonySpec(*native_theme)) {
    return ChromiumImpl::GetColor(...);  // Fallback to upstream
  }
  // Only our custom logic here
}
```

---

## ✅ Prefer chromium_src Overrides Over Patches

**Always prefer a chromium_src override over adding a patch.** Patches are harder to maintain, more likely to conflict, and harder to review. Required header files should be added through chromium_src overrides, not patches.

```cpp
// ❌ WRONG - adding a patch to include a header
// In patches/chromium/some_patch.patch
+#include "brave/components/my_feature/my_header.h"

// ✅ CORRECT - chromium_src override
// In chromium_src/chrome/browser/some_file.cc
#include "brave/components/my_feature/my_header.h"
```

When you need to add virtual to a method, add a class method, or intercept behavior, always use chromium_src overrides instead of patches.

---

## ❌ Never Copy Entire Files or Methods

**Never copy entire Chromium files or methods into chromium_src.** Only override the specific part that needs to change, and call the superclass for everything else.

```cpp
// ❌ WRONG - copying entire method (50+ lines) when only 3 lines differ
void SomeClass::LargeMethod() {
  // ... 50 lines copied from Chromium ...
  // Only 3 lines actually changed
}

// ✅ CORRECT - override just the changed part, call super for the rest
void SomeClass::LargeMethod() {
  // Call the original for most of the work
  auto* toast = [builder buildUserNotification];
  // Add only our custom logic
  [toast setCustomField:value];
}
```

---

## ❌ No Multiline Patches - Use Defines

**Never create multiline patches. Use `#define` macros or chromium_src overrides instead.**

---

## ✅ Prefer Subclassing Over Patching

**When possible, subclass Chromium classes using chromium_src overrides instead of patching.** This applies to both C++ and Java.

**C++ example - changing a class via chromium_src:**
```cpp
// ❌ WRONG - patching tab_strip.cc to change behavior
+  BraveNewTabButton* new_tab_button = new BraveNewTabButton(...);

// ✅ CORRECT - chromium_src override that changes the class name
// In chromium_src/chrome/browser/ui/views/tabs/tab_strip.cc
#define NewTabButton BraveNewTabButton
```

**Java example - subclassing instead of patching:**
```java
// ❌ WRONG - patching IncognitoNewTabPageView directly

// ✅ CORRECT - create BraveIncognitoNewTabPageView as subclass
// Patch only changes the superclass reference
```

Subclassing is better for long-term maintenance and makes changes easier to understand. One patch to change a superclass is better than multiple patches to modify individual methods.

---

## ❌ Never Add Comments in Patches

**Never add comments, empty lines, or any non-functional changes in patch files.** Patches should contain only the minimal functional changes needed.

---

## ✅ Use `include` for Extensible Patches

**When a patch adds to a list or block, use an `include` directive to make the patch extensible.** This way additional items can be added in brave-core without modifying the patch.

---

## ✅ Patches Should Use `define` for Extensibility

**Patches should use `#define` macros to be extensible.** This allows adding behavior in brave-core without changing the patch.

```cpp
// ❌ WRONG - patching inline code directly
+  if (permission == AUTOPLAY) return true;

// ✅ CORRECT - define macro that can be changed in brave-core
+#include "brave/chromium_src/path/to/override.h"
+BRAVE_PERMISSION_CONTROLLER_IMPL_METHOD
```

Convention for define names: `BRAVE_ALL_CAPS_ORIGINAL_METHOD_NAME`.

---

## Patch Style Guidelines

- **Keep patches to one line** even if it violates lint character line limits (lint doesn't run on patched files)
- **In XML patches, use HTML comments** (`<!-- -->`) instead of deleting lines to reduce the diff
- **Minimize line modifications** - put additions on separate lines to avoid modifying existing lines
- **Match existing code exactly** when possible so patches auto-resolve during updates

```xml
<!-- ❌ WRONG - deleting XML elements -->
-<LinearLayout ...>
-  ...
-</LinearLayout>

<!-- ✅ CORRECT - commenting out -->
+<!--
 <LinearLayout ...>
   ...
 </LinearLayout>
+-->
```

---

## ✅ Always Use Original Header Paths

**In chromium_src overrides, always `#include` the original header path, not the chromium_src version.**

```cpp
// ❌ WRONG
#include "brave/chromium_src/net/proxy_resolution/proxy_resolution_service.h"

// ✅ CORRECT
#include "net/proxy_resolution/proxy_resolution_service.h"
```

---

## ✅ Use `-=` for List Removal in Patches

**When removing items from GN lists, use `-=` instead of modifying the original line.** This makes the patch an addition rather than a modification.

```gn
# ❌ WRONG - modifying the original deps line
-  public_deps += [ ":chrome_framework_widevine_signature" ]

# ✅ CORRECT - separate removal line (addition-only patch)
+  public_deps -= [ ":chrome_framework_widevine_signature" ]
```

---

## ✅ Replace Entire Classes with Dummy chromium_src Files

**When you need to disable or replace a Chromium class entirely, create a minimal no-op dummy replacement in chromium_src for the `.h` and `.cc` files.** This avoids needing a patch and makes maintenance easier.

```cpp
// ❌ WRONG - two patches to disable a class
patches/components-translate-core-browser-translate_url_fetcher.cc.patch
patches/components-translate-core-browser-translate_url_fetcher.h.patch

// ✅ CORRECT - chromium_src replacement with no-op implementation
// chromium_src/components/translate/core/browser/translate_url_fetcher.h
class TranslateURLFetcher {
 public:
  TranslateURLFetcher() = default;
  bool Request(const GURL& url, Callback callback) { return false; }
};
```

---

## ✅ Use `#define` to Add `virtual` Without Patches

**When a Chromium method needs to be made virtual for override, use a `#define` in a chromium_src override of the header instead of a patch.**

```cpp
// ❌ WRONG - patch to add virtual keyword
-  void StartAutocomplete(...);
+  virtual void StartAutocomplete(...);

// ✅ CORRECT - chromium_src define
#define StartAutocomplete virtual StartAutocomplete
#include "src/components/omnibox/browser/omnibox_controller.h"
#undef StartAutocomplete
```

Note: This technique does not work when the return type is a pointer or reference (e.g., `T* Method()`).

---

## ❌ Never Use `#define final` to Remove the `final` Keyword

**Redefining `final` via `#define` is undefined behavior per the C++ standard and is highly viral.** It can cause build failures in unrelated code that uses `final` in different contexts. Use a patch to remove `final` when subclassing is required, or find alternative approaches.

```cpp
// ❌ WRONG - undefined behavior, viral side effects
#define final
#include "src/chrome/browser/ui/views/side_panel/side_panel_coordinator.h"
#undef final

// ✅ CORRECT - use a minimal patch if no alternative exists
// Or use #define only for specific method names that won't collide
```

---

## ✅ Add Explanation Comments in chromium_src Override Files

**When creating a chromium_src override, include a comment explaining why the override is needed.** The override's purpose is not always self-evident from the code alone.

```cpp
// chromium_src/chrome/browser/ui/views/tabs/tab_view.cc

// Override to add Brave-specific tab context menu items.
// The upstream class doesn't support extensibility here,
// so we replace the menu construction logic.
```
