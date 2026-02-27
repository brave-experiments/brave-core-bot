# NullAway Best Practices (Java)

Chromium uses [NullAway](https://github.com/uber/NullAway) to enforce [JSpecify](https://jspecify.dev/docs/user-guide/)-style `@Nullable` annotations. NullAway is an [Error Prone](https://errorprone.info/) plugin that runs as a static analysis step for targets without `chromium_code = false`. Null checking is enabled only for classes annotated with `@NullMarked`. Migration progress: [crbug.com/389129271](https://crbug.com/389129271).

Key configuration facts:
- JSpecify mode is enabled — `@Nullable` is `TYPE_USE`.
- Non-annotated types default to non-null (no `@NonNull` needed).
- Nullness of local variables is inferred automatically.
- Annotations live under `org.chromium.build.annotations` (part of `//build/android:build_java`, a default dep).
- Java collections and Guava's `Preconditions` are modeled directly in NullAway.
- Android's `onCreate()` (and similar) methods are implicitly `@Initializer`.

---

<a id="NA-001"></a>

## ✅ Place `@Nullable` Immediately Before the Type

**`@Nullable` is `TYPE_USE` in JSpecify mode — it must appear immediately before the type it annotates.** Placing it on a separate line or before modifiers does not compile. For nested types, the annotation goes before the inner type name.

```java
// ❌ WRONG - annotation on separate line
@Nullable
private String mValue;

// ✅ CORRECT - immediately before the type
private @Nullable String mValue;
private Outer.@Nullable Inner mNestedType;
```

For arrays and generics, position matters for what is nullable:

```java
// Nullable array of non-null strings
private String @Nullable[] mNullableArrayOfNonNullString;

// Non-null array of nullable strings
private @Nullable String[] mNonNullArrayOfNullableString;

// Non-null list of nullable strings
private List<@Nullable String> mNonNullListOfNullableString;

// Nullable callback of nullable strings
private @Nullable Callback<@Nullable String> mNullableCallbackOfNullableString;
```

---

<a id="NA-002"></a>

## ✅ Use Method Annotations for Pre/Post Conditions

**NullAway analyzes code per-method. Use `@RequiresNonNull`, `@EnsuresNonNull`, `@EnsuresNonNullIf`, and `@Contract` to communicate nullability conditions across method boundaries.**

```java
// @RequiresNonNull — only makes sense on private methods
@RequiresNonNull("mNullableString")
private void usesNullableString() {
    if (mNullableString.isEmpty()) { ... }  // No warning
}

// @EnsuresNonNull — guarantees field is non-null after call
@EnsuresNonNull("mNullableString")
private void initializeString() {
    assert mNullableString != null;  // Warns if nullable at any exit
}

// @EnsuresNonNullIf — ties nullness to boolean return
@EnsuresNonNullIf("mThing")
private boolean isThingEnabled() {
    return mThing != null;
}

// With multiple fields and negated result
@EnsuresNonNullIf(value={"sThing1", "sThing2"}, result=false)
private static boolean isDestroyed() {
    return sThing1 == null || sThing2 == null;
}

// @Contract — limited forms supported
@Contract("null -> false")
private boolean isParamNonNull(@Nullable String foo) {
    return foo != null;
}

@Contract("_, !null -> !null")
@Nullable String getOrDefault(String key, @Nullable String defaultValue) {
    return defaultValue;
}
```

**Note:** NullAway's validation of `@Contract` correctness is buggy and disabled, but contracts still apply to callers (they are assumed to be true). See [NullAway#1104](https://github.com/uber/NullAway/issues/1104).

---

<a id="NA-003"></a>

## ✅ Use `@MonotonicNonNull` for Late-Initialized Fields

**When a field starts as null but must never be set back to null after initialization, use `@MonotonicNonNull` instead of `@Nullable`.** This allows NullAway to trust the field is non-null after its first assignment, even in lambdas.

```java
private @MonotonicNonNull String mSomeValue;

public void doThing(String value) {
    // Emits a warning — mSomeValue is still nullable here:
    helper(mSomeValue);

    mSomeValue = value;
    // No warning — even in a lambda, NullAway trusts it stays non-null:
    PostTask.postTask(TaskTraits.USER_BLOCKING, () -> helper(mSomeValue));
}
```

---

<a id="NA-004"></a>

## ✅ Choose the Right Assert/Assume Pattern

**Use the correct null assertion mechanism depending on whether you need a statement or expression and what safety guarantees you want.** Always use `import static` for `assumeNonNull` / `assertNonNull`.

```java
import static org.chromium.build.NullUtil.assumeNonNull;
import static org.chromium.build.NullUtil.assertNonNull;

public String example() {
    // Prefer statements for preconditions — keeps them separate from usage
    assumeNonNull(mNullableThing);
    assert mOtherThing != null;

    // Works with nested fields and getters
    assumeNonNull(someObj.nullableField);
    assumeNonNull(someObj.getNullableThing());

    // Use expression form when it improves readability
    someHelper(assumeNonNull(Foo.maybeCreate(true)));

    // Use assertNonNull when you need an assert as an expression
    mNonNullField = assertNonNull(dict.get("key"));

    String ret = obj.getNullableString();
    if (willJustCrashLaterAnyways) {
        // Use "assert" when not locally dereferencing the object
        assert ret != null;
    } else {
        // Use requireNonNull for production safety
        // (asserts are only enabled on Canary as dump-without-crashing)
        Objects.requireNonNull(ret);
    }
    return ret;
}

// Use assertNonNull(null) for unreachable code paths
public String describe(@MyIntDef int validity) {
    return switch (validity) {
        case MyIntDef.VALID -> "okay";
        case MyIntDef.INVALID -> "not okay";
        default -> assertNonNull(null);
    };
}
```

| Mechanism | Form | Crashes in prod? | Use when |
|-----------|------|------------------|----------|
| `assumeNonNull()` | Statement or expression | No | You're confident the value is non-null |
| `assertNonNull()` | Expression | No (Canary only) | You need a non-null expression |
| `assert x != null` | Statement | No (Canary only) | You're not dereferencing locally |
| `Objects.requireNonNull()` | Expression | Yes | Null would cause worse problems later |

---

<a id="NA-005"></a>

## ✅ Handle Object Destruction Correctly

**For classes with `destroy()` methods that null out otherwise non-null fields, choose one of two strategies:**

### Strategy 1: `@Nullable` fields with `@EnsuresNonNullIf` guards (preferred for complex cases)

```java
private @Nullable SomeService mService;

@EnsuresNonNullIf(value = {"mService"}, result = false)
private boolean isDestroyed() {
    return mService == null;
}

public void doWork() {
    if (isDestroyed()) return;
    mService.execute();  // No warning — NullAway trusts @EnsuresNonNullIf
}

public void destroy() {
    mService = null;
}
```

### Strategy 2: Suppress warnings on `destroy()` (simpler cases)

```java
private SomeService mService;  // stays non-null

@SuppressWarnings("NullAway")
public void destroy() {
    mService = null;
}
```

---

<a id="NA-006"></a>

## ✅ Use `assertBound()` for View Binders, Not `@Initializer`

**Do not mark `onBindViewHolder()` with `@Initializer` — it is not called immediately after construction.** Instead, add an `assertBound()` helper that uses `@EnsuresNonNull` to verify fields are initialized.

```java
// ❌ WRONG - onBindViewHolder is not a real initializer
@Initializer
@Override
public void onBindViewHolder(ViewHolder holder, int position) {
    mField1 = holder.field1;
    mField2 = holder.field2;
}

// ✅ CORRECT - use assertBound() in methods that need the fields
@EnsuresNonNull({"mField1", "mField2"})
private void assertBound() {
    assert mField1 != null;
    assert mField2 != null;
}

private void updateView() {
    assertBound();
    mField1.setText("hello");  // No warning
}
```

---

<a id="NA-007"></a>

## ✅ Initialize Struct-Like Class Fields via Constructor

**NullAway has no special handling for classes with public fields — it warns on non-primitive, non-`@Nullable` public fields not set by a constructor.** Create a constructor that sets all fields. Use `/* paramName= */` comments if readability suffers.

```java
// ❌ WRONG - NullAway warns about uninitialized public fields
public class TabInfo {
    public String title;
    public String url;
}

// ✅ CORRECT - constructor sets all non-null fields
public class TabInfo {
    public final String title;
    public final String url;

    public TabInfo(String title, String url) {
        this.title = title;
        this.url = url;
    }
}

// At call sites, add comments for clarity:
new TabInfo(/* title= */ "Home", /* url= */ "https://brave.com");
```

---

<a id="NA-008"></a>

## ✅ Use "Checked" Companion Methods for Effectively Non-Null Returns

**Some methods are technically `@Nullable` but practically always non-null (e.g., `Activity.findViewById()`, `Context.getSystemService()`).** For Chromium-authored code, create a "Checked" companion instead of mis-annotating the return type.

```java
// When you're not sure if the tab exists:
public @Nullable Tab getTabById(String tabId) {
    ...
}

// When you know the tab exists:
public Tab getTabByIdChecked(String tabId) {
    return assertNonNull(getTabById(tabId));
}
```

Do not annotate `@Nullable` methods as `@NonNull` just because callers expect non-null — this hides real nullability and defeats the purpose of static analysis.

---

<a id="NA-009"></a>

## ✅ Handle Supplier Nullability Variance

**`Supplier<T>` and `Supplier<@Nullable T>` are not assignment-compatible due to Java generics invariance.** Explicit casts or utilities are required.

```java
// Passing Supplier<T> to Supplier<@Nullable T> — explicit cast required
Supplier<String> nonNullSupplier = () -> "hello";
acceptsNullableSupplier((Supplier<@Nullable String>) nonNullSupplier);

// Passing Supplier<@Nullable T> to Supplier<T> — use SupplierUtils
Supplier<@Nullable String> nullableSupplier = () -> maybeNull();
acceptsNonNullSupplier(SupplierUtils.asNonNull(nullableSupplier));

// If the value might actually be null, change the parameter type instead:
void betterApproach(Supplier<@Nullable String> supplier) {
    String value = assumeNonNull(supplier.get());
}
```

See [NullAway#1356](https://github.com/uber/NullAway/issues/1356) for background on why casts are necessary.

---

<a id="NA-010"></a>

## ✅ Match Upstream `@NullUnmarked` on Overridden Methods

**When overriding upstream methods, match the upstream nullability annotations exactly.** Mismatched annotations cause NullAway build failures. See also [AND-036](./android.md#AND-036).

```java
// ❌ WRONG - upstream method has @NullUnmarked but override doesn't
@Override
public void onResult(Profile profile) { ... }

// ✅ CORRECT - match upstream annotations
@NullUnmarked
@Override
public void onResult(Profile profile) { ... }
```

---

<a id="NA-011"></a>

## ✅ Use `@Initializer` for Two-Phase Initialization

**When a class uses two-phase initialization (e.g., `onCreate()`, `initialize()`), annotate the second-phase method with `@Initializer`.** NullAway will then validate non-null fields as if the initializer runs right after the constructor. Android's `onCreate()` is implicitly `@Initializer`.

```java
public class MyComponent {
    private SomeService mService;

    public MyComponent() {
        // mService not set here — that's OK because initialize() is @Initializer
    }

    @Initializer
    public void initialize(SomeService service) {
        mService = service;
    }
}
```

**Caveat:** NullAway does not verify that `@Initializer` methods are actually called. When multiple setters are always called together, prefer a single `initialize()` method.

---

<a id="NA-012"></a>

## ✅ Understand `@SuppressWarnings("NullAway")` vs `@NullUnmarked`

**Both suppress NullAway warnings, but they differ in how callers see the method's signature.**

| Annotation | Method body | Callers see |
|-----------|-------------|-------------|
| `@SuppressWarnings("NullAway")` | Warnings suppressed | Method remains `@NullMarked` — callers get full null checking |
| `@NullUnmarked` | Warnings suppressed | Parameters and return types have **unknown** nullability — callers also lose null checking |

**Prefer `@SuppressWarnings("NullAway")`** when you want to silence a false positive inside a method without degrading the caller experience. Use `@NullUnmarked` only for classes/methods not yet migrated to null safety.

---

<a id="NA-013"></a>

## ❌ Don't Use Intermediate Booleans for Null Checks

**NullAway cannot track nullness through intermediate boolean variables.** Always use the null check directly in the `if` condition.

```java
// ❌ WRONG - NullAway loses track of nullness
boolean isNull = thing == null;
if (!isNull) {
    thing.doWork();  // NullAway still warns!
}

// ✅ CORRECT - direct null check
if (thing != null) {
    thing.doWork();  // No warning
}
```

This is a known NullAway limitation: [NullAway#98](https://github.com/uber/NullAway/issues/98).

---

<a id="NA-014"></a>

## ✅ JNI: `@CalledByNative` Skips Checks, Java-to-Native Is Checked

**Nullness is not checked for `@CalledByNative` methods** ([crbug/389192501](https://crbug.com/389192501)). However, Java-to-Native method calls **are checked** via `assert` statements when `@NullMarked` is present.

Ensure native-bound parameters have correct nullability annotations so that callers on the Java side are properly checked.

---

<a id="NA-015"></a>

## ✅ Use JSpecify Annotations for Mirrored Code

**For code that will be mirrored and built in other environments, use JSpecify annotations directly** instead of Chromium's copies under `org.chromium.build.annotations`. Configure the build target accordingly:

```gn
deps += [ "//third_party/android_deps:org_jspecify_jspecify_java" ]

# Prevent automatic dep on build_java.
chromium_code = false

# Do not let chromium_code = false disable Error Prone.
enable_errorprone = true
```
