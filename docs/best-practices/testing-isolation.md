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
