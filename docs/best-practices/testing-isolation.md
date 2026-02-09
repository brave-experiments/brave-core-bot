# Test Isolation and Specific Patterns

## Test in Isolation with Fakes

**Prefer fakes over real dependencies:**
- Prevents cascading test failures
- Produces more maintainable, modular code
- Makes tests faster and more deterministic

**Example: Use MockTool instead of real navigation tool:**
```cpp
// ✅ GOOD - Control exact timing with MockTool
auto mock_tool = std::make_unique<MockTool>();
EXPECT_CALL(*mock_tool, Execute(_, _))
    .WillOnce([&](auto data, auto callback) {
      tool_callback = std::move(callback);
    });

// Now we can control exactly when the tool completes
ClickPauseButton();
std::move(tool_callback).Run(/* result */);
```

---

## Test the API, Not Implementation

**Focus on public interfaces:**
- Allows internal implementation changes without breaking tests
- Provides accurate usage examples for other developers
- Makes tests more maintainable

**BAD:**
```cpp
// ❌ Testing internal implementation details
EXPECT_EQ(object->private_state_, 42);
```

**GOOD:**
```cpp
// ✅ Testing public API behavior
EXPECT_TRUE(object->IsReady());
EXPECT_EQ(object->GetValue(), 42);
```

---

## HTTP Request Testing - Per-Domain Expected Values

When testing HTTP headers from pages with subresources, use per-domain maps:

**BAD:**
```cpp
// ❌ WRONG - Global expected value, race condition with subresources
std::string expected_header_;

void SetExpectedHeader(const std::string& value) {
  expected_header_ = value;
}

void OnRequest(const HttpRequest& request) {
  EXPECT_EQ(request.headers["Accept-Language"], expected_header_);
}
```

**GOOD:**
```cpp
// ✅ CORRECT - Per-domain expected values
std::map<std::string, std::string> expected_headers_;

void SetExpectedHeader(const std::string& domain, const std::string& value) {
  expected_headers_[domain] = value;
}

void OnRequest(const HttpRequest& request) {
  std::string domain = ExtractDomain(request.headers["Host"]);
  EXPECT_EQ(request.headers["Accept-Language"], expected_headers_[domain]);
}
```

Subresource requests can arrive out-of-order, so per-resource expected values prevent race conditions.

---

## Throttle Testing - Use Large Throttle Windows

**Problem:** Throttle timers start when a fetch happens, not when test timing checks begin.

**BAD:**
```cpp
// ❌ WRONG - 500ms throttle, but WaitForSelector might take 250ms!
const int kThrottleMs = 500;
WaitForSelectorBlocked();  // May take 200-300ms
NonBlockingDelay(base::Milliseconds(250));  // Checking too early!
```

**GOOD:**
```cpp
// ✅ CORRECT - Large throttle window accounts for polling time
const int kThrottleMs = 2000;
WaitForSelectorBlocked();  // Takes ~200-300ms
NonBlockingDelay(base::Milliseconds(1000));  // Still well within throttle
```

Polling-based waits consume time from the throttle window, so use throttle times much larger than expected polling durations.

---

## Chromium Pattern Research

### ✅ Search for Existing Chromium Patterns

**Before implementing a fix for async/timing issues, search the Chromium codebase for similar patterns.**

When you encounter a testing problem (flakiness, timing issues, async operations), ask:
1. Does Chromium have tests with similar requirements?
2. What patterns do they use to solve this?
3. Is there a more deterministic, event-driven approach?

**Research workflow:**
1. Generate an initial fix proposal
2. Search Chromium codebase for similar test scenarios
3. Compare your approach to existing Chromium patterns
4. Prefer established Chromium patterns over novel solutions

### ✅ Include Chromium Code References

**When following a Chromium pattern, include a reference in your code comments.**

**GOOD - Reference in code comment:**
```cpp
// NOTE: Replace() is an IPC to the renderer that updates the DOM
// asynchronously. We use a MutationObserver to wait for the DOM to update
// to the expected value before checking.
// Pattern from service_worker_internals_ui_browsertest.cc.
static constexpr char kWaitForTextScript[] = R"(
  // ...
)";
```

**GOOD - Reference in commit message:**
```
Fix flaky RewriteInPlace_ContentEditable test

The MutationObserver pattern follows the approach used in Chromium's
service_worker_internals_ui_browsertest.cc.
```

---

## ✅ Always Check `EvalJs` Results

**When using `EvalJs` in tests, always check the result with `EXPECT_TRUE`/`EXPECT_EQ`.** An unchecked `EvalJs` call silently swallows errors - any gibberish expression would appear to "pass" the test.

```cpp
// ❌ WRONG - unchecked EvalJs, silently ignores exceptions
content::EvalJs(web_contents, "window.solana.isConnected");

// ✅ CORRECT - result checked
EXPECT_EQ(true, content::EvalJs(web_contents,
                                "window.solana.isConnected"));
```

---

## ❌ Don't Duplicate Test Constants - Expose via Header

**Don't duplicate constants between production code and test code.** If both need the same value, expose it via a shared header file.

```cpp
// ❌ WRONG - same constant duplicated in test
// production.cc
constexpr base::TimeDelta kCleanupDelay = base::Seconds(30);
// test.cc
constexpr base::TimeDelta kCleanupDelay = base::Seconds(30);  // duplicated!

// ✅ CORRECT - shared via header
// constants.h
inline constexpr base::TimeDelta kCleanupDelay = base::Seconds(30);
```

---

## ❌ Don't Depend on `//chrome` from Components Tests

**Component-level unit tests must not depend on `//chrome`.** If you need objects typically created by Chrome infrastructure, create them manually in the test.

```cpp
// ❌ WRONG - depending on //chrome from components test
#include "chrome/browser/content_settings/host_content_settings_map_factory.h"
auto* settings_map = HostContentSettingsMapFactory::GetForProfile(profile);

// ✅ CORRECT - create the instance directly
auto settings_map = base::MakeRefCounted<HostContentSettingsMap>(
    &pref_service_, false /* is_off_the_record */,
    false /* store_last_modified */, false /* restore_session*/,
    false /* should_record_metrics */);
```

---

## ✅ Prefer `*_for_testing()` Accessors Over `FRIEND_TEST`

**When tests need access to a single private member, provide a `*_for_testing()` accessor** returning a reference instead of adding multiple `FRIEND_TEST` macros.

```cpp
// ❌ WRONG - proliferating FRIEND_TEST macros
class BraveTab {
  FRIEND_TEST_ALL_PREFIXES(BraveTabTest, RenameBasic);
  FRIEND_TEST_ALL_PREFIXES(BraveTabTest, RenameCancel);
  FRIEND_TEST_ALL_PREFIXES(BraveTabTest, RenameSubmit);
  raw_ptr<views::Textfield> rename_textfield_;
};

// ✅ CORRECT - single accessor
class BraveTab {
  views::Textfield& rename_textfield_for_testing() { return *rename_textfield_; }
  raw_ptr<views::Textfield> rename_textfield_;
};
```

---

## ✅ Verify Tests Actually Test What They Claim

**When using test-only controls (globals, mocks, feature overrides), verify the test still exercises the code path it claims to test.** A test that disables the code under test proves nothing.

```cpp
// ❌ WRONG - test disables the code it claims to test
void SetUp() { g_disable_stats_for_testing = true; }
// "The stats updater should not reach the endpoint"
// But we disabled stats entirely - this test proves nothing!

// ✅ CORRECT - test the actual behavior with a mock server
```

---

## ✅ Re-enable Test-Only Globals in `TearDown`

**When a test disables functionality via a global in `SetUp()`, always re-enable it in `TearDown()`** to avoid leaking state to other tests.

```cpp
// ❌ WRONG - leaks state to other tests
void SetUp() { g_disable_auto_start = true; }

// ✅ CORRECT - restore state
void SetUp() { g_disable_auto_start = true; }
void TearDown() { g_disable_auto_start = false; }
```

---

## ✅ Use `base::test::ParseJsonDict` for Test Comparisons

**In tests comparing JSON values, use `base::test::ParseJsonDict()`** for simpler, more readable assertions.

```cpp
// ❌ WRONG - manually building expected dict
base::Value::Dict expected;
expected.Set("method", "chain_getBlockHash");
expected.Set("id", 1);
EXPECT_EQ(actual, expected);

// ✅ CORRECT - parse from string
EXPECT_EQ(actual, base::test::ParseJsonDict(
    R"({"method":"chain_getBlockHash","id":1})"));
```
