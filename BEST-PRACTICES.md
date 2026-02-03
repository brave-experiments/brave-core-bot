# Brave Browser C++ Testing Best Practices

This document contains important patterns and anti-patterns discovered while fixing intermittent test failures in the Brave Browser codebase.

## Table of Contents
- [Root Cause Analysis](#root-cause-analysis)
- [Async Testing Patterns](#async-testing-patterns)
- [JavaScript Evaluation in Tests](#javascript-evaluation-in-tests)
- [Navigation and Timing](#navigation-and-timing)
- [Test Isolation](#test-isolation)

---

## Root Cause Analysis

### ❌ NEVER Make Timing-Based "Fixes"

**DO NOT make changes that "fix" the test by altering execution timing.**

These "fixes" may make the problem disappear locally, but the underlying race condition will inevitably return. This is the most common type of fake fix.

**BANNED - Any change that works by altering timing rather than providing proper synchronization:**

```cpp
// ❌ WRONG - Adding logging to "fix" a race condition
LOG(INFO) << "Debug output";  // Changes timing!
std::cout << "Checking state" << std::endl;  // Race condition hidden, not fixed
VLOG(1) << "Operation completed";  // Still just hiding the problem

// ❌ WRONG - Meaningless operations that change timing
volatile int dummy = 0;
for (int i = 0; i < 100; i++) { dummy++; }  // Delay tactic, not a fix
auto unused = SomeGetter();  // Adds execution time
std::this_thread::yield();  // Still a timing hack

// ❌ WRONG - Reordering unrelated code hoping it helps
SomeUnrelatedFunction();  // Accidentally changes timing
ActualTestCode();

// ❌ WRONG - Adding includes that change compilation/execution order
#include "some_header.h"  // If this "fixes" it, you haven't found the real problem

// ❌ WRONG - Refactoring that accidentally changes execution order
ExtractMethodThatChangesWhenThingsRun();  // Same code, different timing

// ❌ WRONG - ANY OTHER CHANGE where you can't explain the synchronization
// If removing it makes the test flaky again, but you don't know WHY it works,
// it's a fake fix that will eventually break
```

**This list is not exhaustive.** The key principle: if your change works by altering when things execute rather than by adding proper synchronization, it's unacceptable.

**Why these "fixes" are unacceptable:**
1. **They hide the problem, not solve it** - The race condition still exists
2. **They're compiler/optimization dependent** - May work in debug but fail in release builds
3. **They're platform dependent** - May work on your machine but fail in CI
4. **They'll break again** - As soon as something else changes timing (new code, different CPU, etc.)

### ✅ Proper Root Cause Analysis

**REQUIRED approach for all test fixes:**

1. **Identify the actual race condition:**
   - What two things are racing?
   - Which happens first? Which should happen first?
   - What's the synchronization mechanism (or lack thereof)?

2. **Find the real synchronization point:**
   - Use proper wait mechanisms (`base::test::RunUntil()`, `TestFuture`, observers)
   - Wait for the actual condition you care about, not arbitrary time
   - Use explicit synchronization primitives (callbacks, run loops with quit closures)

3. **Verify the fix addresses the root cause:**
   - Can you explain WHY the test was flaky?
   - Can you explain HOW your fix eliminates the race?
   - Would your fix work regardless of timing variations?

**GOOD - Actual fixes that address root causes:**

```cpp
// ✅ CORRECT - Wait for the actual condition
ASSERT_TRUE(base::test::RunUntil([&]() {
  return tab_helper()->PageDistillState() == DistillState::kDistilled;
}));

// ✅ CORRECT - Use TestFuture to synchronize on callback
TestFuture<Result> future;
DoAsyncOperation(future.GetCallback());
const Result& result = future.Get();  // Blocks until callback fires

// ✅ CORRECT - Use observer pattern for event notification
class MyObserver : public content::WebContentsObserver {
  void DidFinishNavigation(NavigationHandle* handle) override {
    if (handle->IsSameDocument()) {
      run_loop_.Quit();
    }
  }
  base::RunLoop run_loop_;
};
```

### Rule of Thumb

**If removing your "fix" would make the test flaky again, but you can't explain WHY it fixes the race condition, it's not a real fix.**

Real fixes are:
- Deterministic (work every time)
- Explainable (you can describe the synchronization mechanism)
- Robust (work across different timing conditions, platforms, and build types)

---

## Async Testing Patterns

### ❌ NEVER Use RunUntilIdle()

**DO NOT use `RunLoop::RunUntilIdle()` for asynchronous testing.**

This is explicitly forbidden by Chromium style guide because it causes flaky tests:
- May run too long and timeout
- May return too early if events depend on different task queues
- Creates unreliable, non-deterministic tests

**Reference:** [Chromium C++ Testing Best Practices](https://www.chromium.org/chromium-os/developer-library/guides/testing/cpp-writing-tests/)

### ✅ Use base::test::RunUntil() for C++ Conditions

**GOOD - When checking C++ state:**
```cpp
ASSERT_TRUE(base::test::RunUntil([th]() {
  return speedreader::DistillStates::IsDistilled(th->PageDistillState());
}));
```

**GOOD - When checking object properties:**
```cpp
ASSERT_TRUE(base::test::RunUntil([this]() {
  return tab_helper()->speedreader_bubble_view() != nullptr;
}));
```

### ❌ CRITICAL: Never Use EvalJs Inside RunUntil()

**DO NOT call `content::EvalJs()` or `content::ExecJs()` inside `base::test::RunUntil()` lambdas.**

This causes DCHECK failures on macOS arm64 due to nested run loop issues.

**BAD - Causes DCHECK failure:**
```cpp
// ❌ WRONG - Nested run loops!
ASSERT_TRUE(base::test::RunUntil([&]() {
  return content::EvalJs(web_contents, "!!document.getElementById('foo')")
      .ExtractBool();
}));
```

**Error you'll see on macOS arm64:**
```
FATAL:base/message_loop/message_pump_apple.mm:389]
DCHECK failed: stack_.size() < static_cast<size_t>(nesting_level_)
```

**Why it fails:**
1. `base::test::RunUntil()` starts a run loop to poll the condition
2. Inside that loop, `content::EvalJs()` starts **another** run loop to execute JavaScript
3. This creates **nested run loops**, which triggers a DCHECK on macOS

### ✅ Prefer Event-Driven JavaScript Over C++ Polling

**When waiting for DOM changes, prefer JavaScript event-driven patterns (like MutationObserver) over C++ polling loops.**

Event-driven patterns are:
- More deterministic (respond immediately when the event occurs)
- More efficient (no wasted CPU cycles polling)
- Consistent with Chromium patterns (see `service_worker_internals_ui_browsertest.cc`)

**BEST - MutationObserver for DOM changes:**
```cpp
// Pattern from Chromium's service_worker_internals_ui_browsertest.cc
static constexpr char kWaitForTextScript[] = R"(
  (function() {
    const element = document.getElementById($1);
    const expected = $2;

    function getText() {
      return element.tagName === 'INPUT' || element.tagName === 'TEXTAREA'
          ? element.value : element.innerText;
    }

    if (getText() === expected) {
      return getText();
    }

    return new Promise(function(resolve) {
      const observer = new MutationObserver(function() {
        if (getText() === expected) {
          observer.disconnect();
          resolve(getText());
        }
      });
      observer.observe(element,
          {childList: true, subtree: true, characterData: true});
    });
  })()
)";
std::string updated_text =
    content::EvalJs(web_contents,
                    content::JsReplace(kWaitForTextScript,
                                       element_id,
                                       expected_text))
        .ExtractString();
```

### ✅ Manual Polling Loop (Fallback)

**Use C++ polling only when JavaScript event-driven patterns aren't applicable** (e.g., checking for element existence, waiting for JS API readiness):

```cpp
const base::TimeTicks deadline = base::TimeTicks::Now() + base::Seconds(10);
for (;;) {
  NonBlockingDelay(base::Milliseconds(10));
  if (content::EvalJs(web_contents, "!!document.getElementById('foo')",
                      content::EXECUTE_SCRIPT_DEFAULT_OPTIONS,
                      ISOLATED_WORLD_ID_BRAVE_INTERNAL)
          .ExtractBool()) {
    break;
  }
  if (base::TimeTicks::Now() >= deadline) {
    FAIL() << "Timeout waiting for element";
  }
}
```

### General Rule: Avoid Nested Run Loops

**Any operation that creates its own run loop should NOT be called inside `base::test::RunUntil()`:**

- ❌ `content::EvalJs()` - creates run loop
- ❌ `content::ExecJs()` - creates run loop
- ❌ IPC operations that wait for responses - create run loops
- ✅ Direct C++ state checks - safe
- ✅ Simple getter methods - safe
- ✅ Checking object properties - safe

### Alternative: TestFuture for Callbacks

**PREFERRED for callback-based operations:**
```cpp
TestFuture<ResultType> future;
object_under_test.DoSomethingAsync(future.GetCallback());
const ResultType& actual_result = future.Get();  // Waits for callback
```

### Alternative: QuitClosure() + Run()

**For manual control:**
```cpp
base::RunLoop run_loop;
object_under_test.DoSomethingAsync(run_loop.QuitClosure());
run_loop.Run();  // Waits specifically for this closure
```

---

## JavaScript Evaluation in Tests

### Use Isolated Worlds for Test Code

When evaluating JavaScript in tests, use `ISOLATED_WORLD_ID_BRAVE_INTERNAL` to avoid interfering with page scripts:

```cpp
content::EvalJs(web_contents, "document.getElementById('foo')",
                content::EXECUTE_SCRIPT_DEFAULT_OPTIONS,
                ISOLATED_WORLD_ID_BRAVE_INTERNAL)
```

### Wait for Renderer-Side JS Setup

**Problem:** Mojo binding completes before JavaScript event emitter setup.

**Example (Solana provider):**
```cpp
// ❌ WRONG - WaitForSolanaProviderBinding only waits for mojo, not JS
WaitForSolanaProviderBinding();
// window.braveSolana.on might not be ready yet!

// ✅ CORRECT - Manual polling for JS API readiness
const base::TimeTicks deadline = base::TimeTicks::Now() + base::Seconds(5);
for (;;) {
  NonBlockingDelay(base::Milliseconds(10));
  if (content::EvalJs(web_contents,
                      "typeof window.braveSolana?.on === 'function'",
                      content::EXECUTE_SCRIPT_DEFAULT_OPTIONS,
                      ISOLATED_WORLD_ID_BRAVE_INTERNAL)
          .ExtractBool()) {
    break;
  }
  if (base::TimeTicks::Now() >= deadline) {
    FAIL() << "Timeout waiting for braveSolana.on";
  }
}
```

---

## Navigation and Timing

### Same-Document Navigation

**DO NOT use `base::test::RunUntil()` polling for same-document (hash/fragment) navigations.**

Standard `TestNavigationObserver` skips same-document navigations. Use a custom observer:

```cpp
class SameDocumentCommitObserver : public content::WebContentsObserver {
 public:
  explicit SameDocumentCommitObserver(content::WebContents* web_contents)
      : content::WebContentsObserver(web_contents) {}

  void Wait() { run_loop_.Run(); }

 private:
  void DidFinishNavigation(content::NavigationHandle* handle) override {
    if (handle->IsSameDocument() && !handle->IsErrorPage()) {
      run_loop_.Quit();
    }
  }

  base::RunLoop run_loop_;
};

// Usage:
SameDocumentCommitObserver observer(web_contents);
// Trigger navigation...
observer.Wait();
```

### Avoid Hardcoded JavaScript Timeouts

**BAD:**
```cpp
// ❌ WRONG - Unreliable hardcoded timeout
content::EvalJs(web_contents, R"(
  setTimeout(() => { /* wait for something */ }, 1200);
)");
```

**GOOD:**
```cpp
// ✅ CORRECT - Wait for actual condition in C++
ASSERT_TRUE(base::test::RunUntil([&]() {
  return template_url_service->GetTemplateURLForHost(host) != nullptr;
}));
```

### Wait for Page Distillation

When testing distilled content (Speedreader), always wait for distillation to complete:

```cpp
NavigateToPageSynchronously(url);
WaitDistilled();  // Wait for distillation before interacting with content
// Now safe to interact with distilled elements
```

`NavigateToPageSynchronously` only waits for load stop, not for distillation.

---

## Test Isolation

### Test in Isolation with Fakes

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

### Test the API, Not Implementation

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

## HTTP Request Testing

### Per-Domain Expected Values

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

## Throttle Testing

### Use Large Throttle Windows

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

**Example questions to ask:**
- "Does Chromium have a more deterministic way to test DOM updates?"
- "What pattern does Chromium use for waiting on IPC completion?"
- "How do Chromium tests handle async renderer updates?"

**Real example:** The `MutationObserver` pattern was found in Chromium's `service_worker_internals_ui_browsertest.cc` and is more deterministic than C++ polling loops.

### ✅ Include Chromium Code References

**When following a Chromium pattern, include a reference in your code comments.**

This helps reviewers:
- Understand the pattern's origin and purpose
- Verify the pattern is appropriate for your use case
- Find additional context if needed

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

## Summary Checklist

Before writing async tests, verify:

- [ ] No `RunLoop::RunUntilIdle()` usage
- [ ] No `EvalJs()` or `ExecJs()` inside `RunUntil()` lambdas
- [ ] Using manual polling loops for JavaScript conditions
- [ ] Using `base::test::RunUntil()` only for C++ conditions
- [ ] Waiting for specific completion signals, not arbitrary timeouts
- [ ] Using isolated worlds (`ISOLATED_WORLD_ID_BRAVE_INTERNAL`) for test JS
- [ ] Per-resource expected values for HTTP request testing
- [ ] Large throttle windows for throttle behavior tests
- [ ] Proper observers for same-document navigation
- [ ] Testing public APIs, not implementation details

---

## References

- [Chromium C++ Testing Best Practices](https://www.chromium.org/chromium-os/developer-library/guides/testing/cpp-writing-tests/)
- [Progress Log](./progress.txt) - Real examples from fixing intermittent tests
- [Agent Instructions](./CLAUDE.md) - Full workflow and testing requirements
