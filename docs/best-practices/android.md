# Android Best Practices (Java/Kotlin)

<a id="AND-001"></a>

## ✅ Check `isActivityFinishingOrDestroyed()` Before UI Operations in Async Callbacks

**Always check `isActivityFinishingOrDestroyed()` before performing UI operations (showing dialogs, starting activities, manipulating views) in async callbacks, animation listeners, or lambdas.** Activities can be destroyed between when a callback is scheduled and when it executes.

```java
// ❌ WRONG - no lifecycle check in async callback
private void maybeRequestDefaultBrowser() {
    showDefaultBrowserDialog();
}

// ✅ CORRECT - guard against destroyed activity
private void maybeRequestDefaultBrowser() {
    if (isActivityFinishingOrDestroyed()) return;
    showDefaultBrowserDialog();
}

// ✅ CORRECT - guard in animation callbacks
animator.addListener(new AnimatorListenerAdapter() {
    @Override
    public void onAnimationEnd(Animator animation) {
        if (isActivityFinishingOrDestroyed()) return;
        mSplashContainer.setVisibility(View.GONE);
        showPager();
    }
});
```

---

<a id="AND-002"></a>

## ✅ Check Fragment Attachment Before Async UI Updates

**When async callbacks update UI through a Fragment, verify the fragment is still added and its host Activity is available.** Fragments can be detached or their Activity destroyed while async work is in progress.

```java
// ❌ WRONG - no fragment state checks
void onServiceResult(Result result) {
    updateUI(result);
}

// ✅ CORRECT - verify fragment is still attached
void onServiceResult(Result result) {
    if (!isAdded() || isDetached()) return;
    Activity activity = getActivity();
    if (activity == null || activity.isFinishing()) return;
    updateUI(result);
}
```

This applies to any asynchronous path: service callbacks, `PostTask.postTask()`, Mojo responses, etc.

---

<a id="AND-003"></a>

## ✅ Disable Interactive UI During Async Operations

**Disable buttons, preferences, and other interactive elements while an async operation is in progress to prevent double-clicks.** Re-enable when the callback completes.

```java
// ❌ WRONG - allows double-clicks during async operation
preference.setOnPreferenceClickListener(pref -> {
    accountService.resendConfirmationEmail(callback);
    return true;
});

// ✅ CORRECT - disable during async
preference.setOnPreferenceClickListener(pref -> {
    preference.setEnabled(false);
    accountService.resendConfirmationEmail(result -> {
        preference.setEnabled(true);
        // handle result
    });
    return true;
});
```

---

<a id="AND-004"></a>

## ✅ Apply Null Checks Consistently

**If a member field (e.g., a View reference) is checked for null in some code paths, check it in all code paths that use it.** Inconsistent null checking suggests some paths may crash.

```java
// ❌ WRONG - null check in some places but not others
private void showSplash() {
    if (mSplashContainer != null) {
        mSplashContainer.setVisibility(View.VISIBLE);
    }
}
private void hideSplash() {
    mSplashContainer.setVisibility(View.GONE);  // crash if null!
}

// ✅ CORRECT - consistent null checks
private void hideSplash() {
    if (mSplashContainer != null) {
        mSplashContainer.setVisibility(View.GONE);
    }
}
```

---

<a id="AND-005"></a>

## ✅ Add Null Checks for Services Unavailable in Incognito

**Services accessed through bridges or native code may be null in incognito profiles.** Always add explicit null checks at the point of use, even if upstream logic theoretically handles this.

```cpp
// ❌ WRONG - assumes service is always available
void NtpBackgroundImagesBridge::RegisterPageView() {
  view_counter_service_->RegisterPageView();
}

// ✅ CORRECT - explicit null check
void NtpBackgroundImagesBridge::RegisterPageView() {
  if (!view_counter_service_)
    return;
  view_counter_service_->RegisterPageView();
}
```

---

<a id="AND-006"></a>

## ✅ Use LazyHolder Pattern for Singleton Factories

**Use the LazyHolder idiom for singleton service factories instead of explicit `synchronized` blocks with a lock `Object`.** This is more compact and thread-safe by leveraging Java's class loading guarantees.

```java
// ❌ WRONG - explicit lock-based singleton
public class BraveAccountServiceFactory {
    private static final Object sLock = new Object();
    private static BraveAccountServiceFactory sInstance;

    public static BraveAccountServiceFactory getInstance() {
        synchronized (sLock) {
            if (sInstance == null) {
                sInstance = new BraveAccountServiceFactory();
            }
            return sInstance;
        }
    }
}

// ✅ CORRECT - LazyHolder pattern
public class BraveAccountServiceFactory {
    private static class LazyHolder {
        static final BraveAccountServiceFactory INSTANCE =
                new BraveAccountServiceFactory();
    }

    public static BraveAccountServiceFactory getInstance() {
        return LazyHolder.INSTANCE;
    }
}
```

---

<a id="AND-007"></a>

## ✅ Resolve Theme Colors at Bind Time

**When a custom Preference or view resolves colors from theme attributes, do so at `onBindViewHolder` time (or equivalent), not during construction.** This ensures colors update correctly when the user switches between light and dark themes without the view being recreated.

```java
// ❌ WRONG - resolve color during construction
public class MyPreference extends Preference {
    private final int mTextColor;

    public MyPreference(Context context) {
        super(context);
        mTextColor = resolveThemeColor(context, R.attr.textColor);  // stale if theme changes
    }
}

// ✅ CORRECT - resolve at bind time
public class MyPreference extends Preference {
    @Override
    public void onBindViewHolder(PreferenceViewHolder holder) {
        super.onBindViewHolder(holder);
        int textColor = resolveThemeColor(getContext(), R.attr.textColor);
        ((TextView) holder.findViewById(R.id.title)).setTextColor(textColor);
    }
}
```

---

<a id="AND-008"></a>

## ✅ Use `app:isPreferenceVisible="false"` for Conditionally Shown Preferences

**When a preference in XML will be programmatically removed or hidden based on a feature flag, set `app:isPreferenceVisible="false"` in XML to avoid a brief visual flash before the code hides it.**

```xml
<!-- ✅ Prevents flash of preference before programmatic removal -->
<org.chromium.chrome.browser.settings.BraveAccountPreference
    android:key="brave_account"
    app:isPreferenceVisible="false"
    android:title="@string/brave_account_title" />
```

---

<a id="AND-009"></a>

## ✅ Use `assert` Alongside `Log` for Validation

**Pair defensive null/validation checks with `assert` statements.** Assertions crash in debug builds making problems immediately visible, while graceful handling still protects release builds. Log-only guards are easily missed in logcat output.

```java
// ❌ WRONG - log-only guard, easily missed
if (contractAddress == null || contractAddress.length() < MIN_LENGTH) {
    Log.e(TAG, "Invalid contract address");
    return "";
}

// ✅ CORRECT - assert for debug + graceful fallback for release
assert contractAddress != null && contractAddress.length() >= MIN_LENGTH
        : "Invalid contract address";
if (contractAddress == null || contractAddress.length() < MIN_LENGTH) {
    Log.e(TAG, "Invalid contract address");
    return "";
}
```

---

<a id="AND-010"></a>

## ✅ Cache Expensive System Service Lookups

**When a method internally fetches system services (e.g., `PackageManager`, `AppOpsManager`), avoid calling it repeatedly in a hot path.** Compute the value once and store it in a member variable.

**Exception:** Don't cache values that can change without notification in multi-window or configuration-change scenarios (e.g., PiP availability can change when a second app starts).

```java
// ❌ WRONG - repeated expensive service lookup
@Override
public void onResume() {
    if (hasPipPermission()) { /* fetches PackageManager + AppOpsManager */ }
}

// ✅ CORRECT - cache on creation
private boolean mHasPipPermission;

@Override
public void onCreate() {
    mHasPipPermission = hasPipPermission();
}
```

---

<a id="AND-011"></a>

## ✅ Prefer Core/Native-Side Validation

**Before implementing validation logic in Android/Java code, check whether unified validation exists on the core/native side.** Prefer core-side validation to avoid cross-platform inconsistencies between Android, iOS, and desktop.

---

<a id="AND-012"></a>

## ✅ Skip Native/JNI Checks in Robolectric Tests

**Robolectric tests do not have native/JNI available.** When code paths hit JNI calls, use conditional checks (like `FeatureList.isNativeInitialized()`) to gracefully handle the test environment.

```java
// ✅ CORRECT - guard JNI calls for Robolectric compatibility
if (FeatureList.isNativeInitialized()) {
    BraveFeatureList.isEnabled(BraveFeatureList.SOME_FEATURE);
}
```

See `BraveTabbedAppMenuPropertiesDelegate.java` for an existing example of this pattern.

---

<a id="AND-013"></a>

## ✅ Use Direct Java Patches When Bytecode Patching Fails

**Bytecode (class adapter) patching fails when a class has two constructors.** In these cases, use direct `.java.patch` files instead. Also use direct `BUILD.gn` patches to add sources when circular dependencies prevent using `java_sources.gni`.

---

<a id="AND-014"></a>

## ✅ `ProfileManager.getLastUsedRegularProfile()` Is Acceptable in Widgets

**While the presubmit check flags `ProfileManager.getLastUsedRegularProfile()` as a banned pattern, it is acceptable in Android widget providers** (e.g., `QuickActionSearchAndBookmarkWidgetProvider`) where no Activity or WebContents context is available. This matches upstream Chromium's approach in their own widgets.

---

<a id="AND-015"></a>

## ✅ Remove Unused Interfaces and Dead Code

**Do not leave unused interfaces, listener patterns, or helper methods in the codebase.** If scaffolded during development but never actually called, remove before merging.

```java
// ❌ WRONG - interface defined but never used
public interface OnAnimationCompleteListener {
    void onAnimationComplete();
}

// ✅ CORRECT - remove if nothing implements or calls it
```

---

<a id="AND-016"></a>

## ❌ Don't Set `clickable`/`focusable` on Non-Interactive Views

**Avoid setting `android:clickable="true"` or `android:focusable="true"` on purely decorative or display-only views** (like animation containers). These attributes affect accessibility and touch event handling.

---

<a id="AND-017"></a>

## ✅ Share Identical Assets Across Platforms

**When Android and iOS use identical asset files (e.g., Lottie animation JSON), reference a single shared copy rather than maintaining duplicates.** This ensures future changes only need to be made once.

---

<a id="AND-018"></a>

## ✅ Java Field Naming Conventions

**Follow Chromium/Android field naming conventions:**
- Private non-static fields: `m` prefix (e.g., `mIgnorePullToRefresh`)
- Public fields: no `m` prefix (e.g., `ignorePullToRefresh`)
- Static fields: `s` prefix (e.g., `sInstance`)

The presubmit enforces the `m` prefix rule for private fields. Prefer setter/getter methods over public fields for encapsulation.

```java
// ❌ WRONG
private boolean ignorePullToRefresh;  // missing m prefix
public boolean mPublicField;  // m prefix on public field

// ✅ CORRECT
private boolean mIgnorePullToRefresh;
public boolean ignorePullToRefresh;
```

---

<a id="AND-019"></a>

## ✅ Group Feature-Specific Java Sources into Separate Build Targets

**When Java sources for a specific feature (e.g., `crypto_wallet`) accumulate in `brave_java_sources.gni`, consider creating a separate build target.** This improves build isolation and dependency tracking.

---

<a id="AND-020"></a>

## ✅ Provide Justification for Non-Translatable Strings

**When adding strings with `translatable="false"` in `.grd` or resource files, there should be a clear documented reason** (e.g., brand names, URLs, temporary placeholders). Reviewers will question unmarked non-translatable strings.

---

<a id="AND-021"></a>

## ✅ Prefer Early Returns Over Deep Nesting

**When a condition check determines whether the rest of a method should execute, return early rather than wrapping logic in nested `if` blocks.** This reduces nesting depth and improves readability.

```java
// ❌ WRONG - deep nesting
private void handleState() {
    if (!isFinished) {
        if (hasData) {
            // ... lots of code ...
        }
    }
}

// ✅ CORRECT - early return
private void handleState() {
    if (isFinished) return;
    if (!hasData) return;
    // ... lots of code at top level ...
}
```
