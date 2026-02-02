# Testing Requirements

## CRITICAL: Test Execution Requirements

**YOU MUST RUN ALL ACCEPTANCE CRITERIA TESTS - NO EXCEPTIONS**

- **NEVER skip tests** because they "take too long" - this is NOT acceptable
- If tests take hours, that's expected - run them anyway
- Use `run_in_background: true` for long-running commands (builds, test suites)
- Use high timeout values: `timeout: 3600000` (1 hour) or `timeout: 7200000` (2 hours)
- Monitor background tasks with TaskOutput tool
- If ANY test fails, the story does NOT complete - DO NOT update status to "committed"
- DO NOT commit code unless ALL acceptance criteria tests pass
- DO NOT rationalize skipping tests for any reason

## Test Scope: Run ALL Tests in File

**CRITICAL: When running tests, run ALL tests within the entire test file, not just a single test fixture.**

- If you modify or work with a test file, identify ALL test fixtures in that file
- Use `--gtest_filter` with colon-separated patterns to run ALL fixtures
- A single test file often contains multiple test fixtures (e.g., `FooTest`, `FooTestWithFeature`, `FooTestDisabled`)
- Running all fixtures in the file catches test interactions, shared state issues, and side effects
- Examples:
  - ❌ WRONG: `--gtest_filter=AdBlockServiceTest.OneCase` (single test case)
  - ❌ WRONG: `--gtest_filter=AdBlockServiceTest.*` (only one fixture)
  - ✅ CORRECT: `--gtest_filter=AdBlockServiceTest.*:AdBlockServiceTestWithFeature.*` (all fixtures in file)

**Process:**
1. Identify which test file(s) you're working with
2. Examine the file to find ALL test fixture names (all `TEST_F(FixtureName, ...)` declarations)
3. Build a gtest_filter that includes all fixtures: `Fixture1.*:Fixture2.*:Fixture3.*`
4. Run all fixtures together to ensure comprehensive testing

## Build Failure Recovery

**If `npm run build` fails**, run these steps in order from `[workingDirectory from prd.json config]`:
```bash
cd [workingDirectory from prd.json config]
git fetch
git rebase origin/master
npm run sync -- --no-history
```
Then retry the build.

## ABSOLUTE RULE: No Test = No Pass

**IF YOU CANNOT RUN A TEST, THE STORY CANNOT BE MARKED AS PASSING. PERIOD.**

This means:
- ❌ "Test not runnable in local environment" → Story FAILS, keep status: "pending"
- ❌ "Feature not enabled in dev build" → Story FAILS, keep status: "pending"
- ❌ "Test environment not configured" → Story FAILS, keep status: "pending"
- ❌ "Test would take too long" → Story FAILS, keep status: "pending"
- ❌ "Fix addresses root cause but test can't verify" → Story FAILS, keep status: "pending"

**The ONLY acceptable outcome is:**
- ✅ Test runs AND passes → Update status to "committed"
- ❌ Test runs AND fails → Keep status: "pending", fix the issue
- ❌ Test cannot run for ANY reason → Keep status: "pending", document the blocker

**NO EXCEPTIONS. NO EXCUSES. NO RATIONALIZATIONS.**

If a test cannot be run, you must:
1. Document the exact blocker in progress.txt
2. Keep status: "pending"
3. Do NOT commit any changes
4. Move on to the next story

Only update status to "committed" when you have ACTUAL PROOF the test ran and passed.

## Example of Running Long Tests in Background

```javascript
// Start build in background
Bash({
  command: "cd brave && npm run build",
  run_in_background: true,
  timeout: 7200000,  // 2 hours
  description: "Build brave browser (may take 1-2 hours)"
})

// Later, check on the build with TaskOutput
TaskOutput({
  task_id: "task-xxx",  // Use the task ID returned from the background command
  block: true,
  timeout: 7200000
})

// Run tests in background
Bash({
  command: "cd brave && npm run test -- brave_browser_tests",
  run_in_background: true,
  timeout: 7200000,
  description: "Run brave_browser_tests (may take hours)"
})
```

## C++ Testing Best Practices (Chromium/Brave)

**CRITICAL: Follow these guidelines when writing C++ tests for Chromium/Brave codebase.**

**📖 READ FIRST:** Before implementing any test fixes, read [BEST-PRACTICES.md](../BEST-PRACTICES.md) for comprehensive async testing patterns, including:
- Avoiding nested run loops (EvalJs inside RunUntil)
- JavaScript evaluation patterns
- Navigation and timing issues
- Test isolation principles

### ❌ NEVER Use RunUntilIdle() - YOU MUST REPLACE IT

**DO NOT use `RunLoop::RunUntilIdle()` for asynchronous testing.**

This is explicitly forbidden by Chromium style guide because it causes flaky tests:
- May run too long and timeout
- May return too early if events depend on different task queues
- Creates unreliable, non-deterministic tests

**CRITICAL: If you find RunUntilIdle() in a test, DO NOT just delete it. You MUST replace it with one of the proper patterns below. Simply removing it will break the test because async operations won't complete.**

### ✅ REQUIRED: Replace RunUntilIdle() with These Patterns

When you encounter `RunLoop::RunUntilIdle()`, replace it with one of these approved patterns:

#### Option 1: TestFuture (PREFERRED for callbacks)

**BEFORE (WRONG):**
```cpp
object_under_test.DoSomethingAsync(callback);
task_environment_.RunUntilIdle();  // WRONG - causes flaky tests
```

**AFTER (CORRECT):**
```cpp
TestFuture<ResultType> future;
object_under_test.DoSomethingAsync(future.GetCallback());
const ResultType& actual_result = future.Get();  // Waits for callback
// Now you can assert on actual_result
```

#### Option 2: QuitClosure() + Run() (for manual control)

**BEFORE (WRONG):**
```cpp
object_under_test.DoSomethingAsync();
task_environment_.RunUntilIdle();  // WRONG
```

**AFTER (CORRECT):**
```cpp
base::RunLoop run_loop;
object_under_test.DoSomethingAsync(run_loop.QuitClosure());
run_loop.Run();  // Waits specifically for this closure
```

#### Option 3: RunLoop with explicit quit in observer/callback

**BEFORE (WRONG):**
```cpp
TriggerAsyncOperation();
task_environment_.RunUntilIdle();  // WRONG
```

**AFTER (CORRECT):**
```cpp
base::RunLoop run_loop;
auto quit_closure = run_loop.QuitClosure();
// Pass quit_closure to your observer or callback
// OR call std::move(quit_closure).Run() when operation completes
run_loop.Run();  // Waits for explicit quit
```

#### Option 4: base::test::RunUntil() (for condition-based waiting)

**BEFORE (WRONG):**
```cpp
TriggerAsyncOperation();
task_environment_.RunUntilIdle();  // WRONG - waits for all tasks
```

**AFTER (CORRECT):**
```cpp
int destroy_count = 0;
TriggerAsyncOperation();
EXPECT_TRUE(base::test::RunUntil([&]() { return destroy_count == 1; }));
// Waits for SPECIFIC condition to become true
```

**Use this when:** You need to wait for a specific state change that you can check with a boolean condition (e.g., counter reaches value, object becomes ready, child count changes).

**KEY POINT: Always wait for a SPECIFIC completion signal or condition, not just "all idle tasks".**

## Test Quality Standards

**Test in Isolation:**
- Use fakes rather than real dependencies
- Prevents cascading test failures
- Produces more maintainable, modular code

**Test the API, Not Implementation:**
- Focus on public interfaces
- Allows internal implementation changes without breaking tests
- Provides accurate usage examples for other developers

## Test Types & Purpose

**Unit Tests:** Test individual components in isolation. Should be fast and pinpoint exact failures.

**Integration Tests:** Test component interactions. Slower and more complex than unit tests.

**Browser Tests:** Run inside a browser process instance for UI testing.

**E2E Tests:** Run on actual hardware. Slowest but detect real-world issues.

## Common Patterns

**Friending Tests:** Use the `friend` keyword sparingly to access private members, but prefer testing public APIs first.

**Mojo Testing:** Reference "Stubbing Mojo Pipes" documentation for unit testing Mojo calls.

## Quality Requirements

- **ALL** acceptance criteria tests must pass - this is non-negotiable
- Do NOT commit broken code
- Do NOT skip tests for any reason
- Keep changes focused and minimal
- Follow existing code patterns
- Report ALL test results in progress.txt
