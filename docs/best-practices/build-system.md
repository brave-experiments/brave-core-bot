# Build System

## ✅ DEPS File - Use Commit Hashes

**In DEPS files, always use commit hashes rather than branch names or tags.** Commit hashes are immutable and ensure reproducible builds.

---

## ❌ Minimize Whitespace Changes in Patches

**Leave whitespace intact in patch files to minimize diff size.** Only change what's functionally necessary. Unnecessary whitespace changes make patches harder to review and more likely to conflict.

---

## ✅ Reuse Existing GN Config Args

**Check for existing GN args before creating new ones.** Duplicating config arguments (e.g., creating `brave_android_keystore_path` when `android_keystore_path` already exists) adds confusion and maintenance burden.

---

## ✅ Python Build Scripts

Python scripts used in the build system should follow these conventions:

- **Use `argparse`** for command-line arguments, not `sys.argv` directly
- **Use standard `Main()` pattern** to ensure proper error propagation to GN:
  ```python
  def Main():
      ...
      return 0

  if __name__ == '__main__':
      sys.exit(Main())
  ```

---

## ✅ Group Sources and Deps Together in BUILD.gn

**Always group `sources` and `deps` in the same block.** Don't dump everything in one place - move files to separate BUILD.gn files when needed so it's clear which deps belong to which sources.

```gn
# ❌ WRONG - all deps in root BUILD.gn, hard to track
source_set("browser") {
  sources = [ ... 200 files ... ]
  deps = [ ... 100 deps ... ]
}

# ✅ CORRECT - grouped by feature
source_set("branded_wallpaper") {
  sources = [ "branded_wallpaper.cc" ]
  deps = [ "//brave/components/ntp_background_images" ]
}
```

---

## ❌ Never More Than One Guard Per Target

**There should almost never be more than one of the same guard in any given BUILD.gn target.** If you find yourself repeating the same `if (enable_brave_foo)` block multiple times, consolidate.

---

## ✅ Use Buildflags Instead of OS Guards for Features

**Use buildflags (`BUILDFLAG(ENABLE_FOO)`) instead of OS platform guards (`is_linux`, `is_win`) for feature-specific code.** Platform guards without buildflags are deprecated.

```gn
# ❌ WRONG - deprecated OS guard
if (is_linux) {
  sources += [ "tor_launcher_linux.cc" ]
}

# ✅ CORRECT - use buildflag
if (enable_tor) {
  sources += [ "tor_launcher.cc" ]
}
```

Also: only feature-specific header files should go inside feature guards. Don't put unrelated headers inside a feature guard block even if they're only currently used by that feature.

---

## ✅ Buildflag Naming Convention

**Use `enable_brave_<feature>` as the naming convention for buildflags.**

```gn
# ❌ WRONG
brave_perf_predictor_enabled = true

# ✅ CORRECT
enable_brave_perf_predictor = true
```

---

## ❌ Never Add Empty Lines in Patches

**Never add empty lines in patch files.** Keep patches minimal - only change what's functionally necessary.

---

## ❌ Don't Duplicate License Files

**Never duplicate Chromium or other project license files.** Use special cases or references instead.

---

## ✅ JSON Resources Should Go in GRD Files

**JSON data files should be packaged as resources in `.grd` files, not loaded from disk.** This allows the same data to be used from both C++ and JS.

See `bat_ads_resources.grd` for an example.

---

## ✅ Always Double-Check Dependencies

**Always verify you have deps for all includes and used symbols.** Missing deps can work by accident through transitive dependencies but will break when those transitive deps change.

```gn
# Check for deps matching your includes:
# #include "url/gurl.h" -> needs dep "//url"
# #include "extensions/browser/..." -> needs dep "//extensions/browser/..."
```

---

## ✅ Use `//brave/` Deps Instead of Modifying Visibility Lists

**When adding deps from Chromium targets to Brave code, use high-level `//brave/` targets (e.g., `//brave/utility`) instead of modifying Chromium visibility lists.** Visibility lists exist to prevent exactly this kind of cross-boundary dependency.

```gn
# ❌ WRONG - modifying Chromium visibility list
visibility += [ "//brave/components/brave_rewards/browser" ]

# ✅ CORRECT - use a brave target that already has visibility
deps += [ "//brave/utility" ]
```

---

## ✅ Add `#endif` Comments for Nested Conditionals

**When you have nested `#if`/`#endif` blocks, add comments to clarify what each `#endif` is closing.**

```cpp
#if BUILDFLAG(ENABLE_SPELLCHECK)
#include "components/spellcheck/common/spellcheck_features.h"
#endif  // ENABLE_SPELLCHECK
```

---

## ✅ Scripts Go in brave/scripts

**Build and utility scripts should go in `brave/scripts/`, not in `build/` or other Chromium directories.**

---

## ❌ Avoid Separate Repositories

**Avoid creating separate repositories for Brave features.** Separate repos are harder to manage, code review, and maintain. Prefer keeping code within brave-core.

---

## ✅ Add New URLs to the Network Audit Whitelist

**When adding any new network endpoint URL, it must be added to the network audit whitelist** at `lib/whitelistedUrlPrefixes.js` in brave-browser. Without this, the network audit check will fail.

---

## ✅ Keep Lists Sorted Alphabetically

**When adding items to lists (includes, deps, sources, histograms, features), maintain alphabetical ordering.** Sorted lists reduce merge conflicts and make items easier to find.

```gn
# ❌ WRONG - unsorted
deps = [
  "//brave/components/brave_shields",
  "//brave/components/brave_ads",
  "//brave/components/brave_wallet",
]

# ✅ CORRECT - alphabetically sorted
deps = [
  "//brave/components/brave_ads",
  "//brave/components/brave_shields",
  "//brave/components/brave_wallet",
]
```

---

## ❌ Don't Use OS Guards as Proxy for Feature Guards

**Use the correct feature guard (`brave_wallet_enabled`, `enable_extensions`) instead of approximating with OS guards (`!is_android && !is_ios`).** OS guards can get out of sync with the actual feature flag logic.

```gn
# ❌ WRONG - OS guard as proxy for feature
if (!is_android && !is_ios) {
  sources += [ "brave_wallet_utils.cc" ]
}

# ✅ CORRECT - actual feature guard
if (brave_wallet_enabled) {
  sources += [ "brave_wallet_utils.cc" ]
}
```

---

## ❌ Don't Have Both `BUILD.gn` and `sources.gni` in the Same Directory

**A directory should contain either a `BUILD.gn` file (preferred) or a `sources.gni` file, but not both.** Having both creates confusion about which is authoritative and makes dependency tracking harder.

---

## ✅ Create Test Targets in Component BUILD.gn

**Unit test files should have a test target in the component's `BUILD.gn`, not be individually listed in the top-level `test/BUILD.gn`.** The top-level test target should depend on the component's test target.

```gn
# ❌ WRONG - individual test files in top-level test/BUILD.gn
sources += [ "//brave/components/ai_chat/core/credential_manager_unittest.cc" ]

# ✅ CORRECT - test target in component BUILD.gn
# components/ai_chat/core/BUILD.gn
source_set("unit_tests") {
  sources = [ "credential_manager_unittest.cc" ]
  deps = [ ... ]
}
# test/BUILD.gn
deps += [ "//brave/components/ai_chat/core:unit_tests" ]
```

---

## ✅ Use `PlatformBrowserTest` for Cross-Platform Browser Tests

**Browser tests that should run on both desktop and Android should use `PlatformBrowserTest` as the base class instead of `InProcessBrowserTest`.**

```cpp
#if BUILDFLAG(IS_ANDROID)
#include "chrome/test/base/android/android_browser_test.h"
#else
#include "chrome/test/base/in_process_browser_test.h"
#endif

// ❌ WRONG
class MyBrowserTest : public InProcessBrowserTest {};

// ✅ CORRECT
class MyBrowserTest : public PlatformBrowserTest {};
```

---

## ✅ Use `public_deps` for Header-File Includes in BUILD.gn

**When a dependency's headers are included in your target's header files (not just .cc files), that dependency must be listed in `public_deps`, not `deps`.** This ensures consumers of your target also get the transitive include paths they need.

```gn
# ❌ WRONG - header-visible dependency in regular deps
source_set("my_service") {
  sources = [ "my_service.h", "my_service.cc" ]
  deps = [ "//components/prefs" ]  # prefs is used in my_service.h!
}

# ✅ CORRECT - header dependency in public_deps
source_set("my_service") {
  sources = [ "my_service.h", "my_service.cc" ]
  public_deps = [ "//components/prefs" ]  # used in header
  deps = [ "//base" ]  # only used in .cc
}
```

---

## ✅ Use `deps +=` with a Variable for Extensible GN Patches

**When a patch adds dependencies to a Chromium BUILD.gn target, define a variable in Brave code and patch only the variable reference.** This allows adding/removing deps without modifying the patch.

```gn
# ❌ WRONG - patching inline deps
+  deps += [ "//brave/browser/ui/views/location_bar" ]

# ✅ CORRECT - patch references a variable
+  deps += brave_browser_window_deps
# In brave code:
brave_browser_window_deps = [
  "//brave/browser/ui/views/location_bar",
]
```

---

## ✅ Utility Scripts Should Be Python, Not Node.js or Shell

**Build and utility scripts in brave-core should be written in Python (using `vpython` from depot tools), not Node.js or shell scripts.** This follows Chromium conventions, avoids additional runtime dependencies, and works on all platforms including Windows.
