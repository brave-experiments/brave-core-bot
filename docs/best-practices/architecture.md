# Architecture and Code Organization

## ❌ No Layering Violations - Components Cannot Depend on Browser

**Code in `components/` must never use `g_browser_process` or depend on `brave/browser/`.**

This is a Chromium layering violation. Components are lower-level and must not reference browser-layer code. Fix by passing dependencies via injection (constructor params, `Init()` methods, callbacks).

**BAD:**
```cpp
// ❌ WRONG - components/ code using g_browser_process
// In components/p3a/brave_p3a_service.cc
void BraveP3AService::Init() {
  uploader_.reset(new BraveP3AUploader(
      g_browser_process->shared_url_loader_factory(), ...));  // Layering violation!
}
```

**GOOD:**
```cpp
// ✅ CORRECT - dependency injected via Init()
// In components/p3a/brave_p3a_service.cc
void BraveP3AService::Init(
    scoped_refptr<network::SharedURLLoaderFactory> url_loader_factory) {
  uploader_.reset(new BraveP3AUploader(url_loader_factory, ...));
}
```

Similarly, code in `components/safe_browsing/` cannot have `brave/browser/` deps. Separate browser-dependent callbacks from component code.

**Specific rules:**
- Never use `Profile` in components - pass `PrefService` instead (use `user_prefs::UserPrefs::Get(browser_context)`)
- Never include `brave/browser/` or `chrome/browser/` from `components/`
- Use `BrowserContext` instead of `Profile` in components

---

## ✅ Prefer Internal Feature Guards Over External Ifdefs

**Code should handle disabled features internally rather than requiring external `#ifdef` guards.**

When a feature can be disabled, prefer making the factory/service return null or no-op when disabled, rather than requiring callers to wrap every usage in `#ifdef` guards. Scattered buildflags lead to missing deps and maintenance burden.

**BAD:**
```cpp
// ❌ WRONG - external ifdef guards everywhere
#if BUILDFLAG(BRAVE_REWARDS_ENABLED)
  auto* rewards_service = RewardsServiceFactory::GetForProfile(profile);
  rewards_service->DoSomething();
#endif
```

**GOOD:**
```cpp
// ✅ CORRECT - factory handles disabled state internally
auto* rewards_service = RewardsServiceFactory::GetForProfile(profile);
if (rewards_service) {  // Returns null when disabled
  rewards_service->DoSomething();
}
```

---

## ❌ Don't Misuse shared_ptr for Unowned Memory

**Don't use `shared_ptr` to take ownership of something you don't own.**

Using `shared_ptr` on memory owned by another class causes crashes when the `shared_ptr` frees memory that is still referenced elsewhere. Avoid shared pointers unless there is a strong reason for shared ownership.

**BAD:**
```cpp
// ❌ WRONG - taking ownership of an unowned resource
void Init(network::ResourceRequest& request) {
  auto shared_request = std::make_shared<network::ResourceRequest>(request);
  // shared_request will free memory that may still be in use!
}
```

**GOOD:**
```cpp
// ✅ CORRECT - pass by reference or raw pointer for unowned resources
void Init(const network::ResourceRequest& request) {
  // Use the request directly, don't take ownership
}
```

---

## Thread Safety - Service Method Calls

**Calling service methods from the wrong thread causes crashes.** Always verify which thread a method expects to be called on. This is especially important for ad-block and shields services.

---

## ❌ Never Access Internal/Vendor Headers Directly

**Never use `#include "brave/vendor/..."` to access internal headers.** Internal headers are not part of the public API and should not be accessed using full paths to bypass visibility.

```cpp
// ❌ WRONG - accessing internal headers via full vendor path
#include "brave/vendor/bat-native-ads/src/bat/ads/internal/locale_helper.h"

// ✅ CORRECT - use the public API header
#include "brave/components/brave_ads/browser/locale_helper.h"
```

---

## ✅ Use Pref Change Registrar Instead of Custom Observers

**Use the existing `pref_change_registrar_` pattern for observing pref changes.** Don't create custom observer interfaces when the pref change registrar already handles this.

```cpp
// ❌ WRONG - custom observer for pref changes
class MyObserver : public PrefObserver {
  void OnPrefChanged(const std::string& pref_name) override;
};

// ✅ CORRECT - use pref change registrar
pref_change_registrar_.Add(
    prefs::kMyPref,
    base::BindRepeating(&MyClass::OnPrefChanged, base::Unretained(this)));
```

Also: check if the superclass already has a `pref_change_registrar_` before adding a new one.

---

## ❌ Don't Duplicate Pref Storage

**Don't cache pref values in member variables when you can just read the pref at call time.**

```cpp
// ❌ WRONG - duplicating pref storage
bool is_opted_in_ = false;
void OnPrefChanged() { is_opted_in_ = prefs->GetBoolean(kOptedIn); }
bool IsOptedIn() { return is_opted_in_; }

// ✅ CORRECT - read pref when needed
bool IsOptedIn() { return prefs_->GetBoolean(kOptedIn); }
```

---

## Factory Patterns

### ✅ Use DependsOn for Factory Dependencies

**If your KeyedServiceFactory depends on other services, declare it with `DependsOn`.** This ensures proper initialization order.

```cpp
MyServiceFactory::MyServiceFactory()
    : BrowserContextKeyedServiceFactory(...) {
  DependsOn(RewardsServiceFactory::GetInstance());
  DependsOn(AdsServiceFactory::GetInstance());
}
```

### ✅ Return Null for Incognito Profiles

**If a service shouldn't be active in incognito, return null from `GetForProfile` rather than overriding `GetBrowserContextToUse`.**

### ❌ Components Don't Need Their Own Component Manager

**Each component does not need its own component manager.** Use a component installer policy instead.

---

## ✅ Use Abstract Base Classes to Avoid Layering Violations

**When browser-layer code needs to be accessed from components, create an abstract base class in components and implement it in browser.**

```cpp
// ✅ In components/ - abstract interface
class BraveOmniboxClient {
 public:
  virtual bool IsAutocompleteEnabled() = 0;
};

// ✅ In browser/ - concrete implementation
class BraveOmniboxClientImpl : public BraveOmniboxClient {
  bool IsAutocompleteEnabled() override { ... }
};
```

Then cast to the abstract type in components without a layering violation.

---

## ❌ Don't Initialize Services for Wrong Profile Types

**Never initialize services for profile types they shouldn't support.** For example, never initialize Rewards service for incognito profiles. The `GetBrowserContextToUse` method in factories must correctly return null for unsupported profile types.

```cpp
// ❌ WRONG - returns the profile even for incognito
content::BrowserContext* GetBrowserContextToUse(
    content::BrowserContext* context) const override {
  return context;  // This creates services for incognito!
}

// ✅ CORRECT - return null for unsupported profiles
content::BrowserContext* GetBrowserContextToUse(
    content::BrowserContext* context) const override {
  if (context->IsOffTheRecord())
    return nullptr;
  return context;
}
```

---

## ✅ Reuse Existing Services and Singletons

**Check for existing services and singletons before creating new ones.** Don't create duplicate singletons for the same purpose (e.g., don't create a new locale helper when `brave_ads::LocaleHelper` already exists).

**Use observers for decoupled notifications instead of adding direct cross-service calls.**

---

## ✅ Encapsulate Cleanup in the Owning Class

**Cleanup logic (like deleting files) should be encapsulated in the class that owns the resource.** Don't spread cleanup code across multiple callers.

```cpp
// ❌ WRONG - caller handles cleanup details
tor_client_updater()->GetExecutablePath();
base::DeleteFile(path);

// ✅ CORRECT - owning class encapsulates cleanup
tor_client_updater()->Cleanup();
```

---

## ✅ File Organization by Component

**Group files by component, not by platform.** For example, `brave_rewards/android/` is preferred over `android/rewards/`.

```
# ❌ WRONG
brave/browser/android/rewards/brave_rewards_native_worker.cc

# ✅ CORRECT
brave/components/brave_rewards/android/brave_rewards_native_worker.cc
```

This keeps related code together and is consistent with Chromium patterns like `chrome/browser/history/android/`.

---

## ✅ Exclude Entire Feature API from GN When Disabled

**When a feature is disabled via buildflag, exclude the entire API from the build.** Don't leave API declarations with no implementation.

```gn
# ❌ WRONG - API always built, implementation conditionally empty
source_set("wallet_api") {
  sources = [ "wallet_api.cc" ]  # has empty stubs when disabled
}

# ✅ CORRECT - entire API excluded
if (brave_wallet_enabled) {
  source_set("wallet_api") {
    sources = [ "wallet_api.cc" ]
  }
}
```

---

## ✅ Use Friend Class for Test/Private Access

**When tests or subclasses need access to private members, use `friend` declarations instead of making methods public or protected.**

```cpp
// ❌ WRONG - making methods public just for testing
public:
  void InternalMethod();  // was private, made public for tests

// ✅ CORRECT - friend class
private:
  friend class BraveDownloadProtectionService;
  void InternalMethod();
```

For patches, use a `BRAVE_CLASS_NAME_H` define at the end of `public:` that adds friend declarations.

---

## ✅ Callbacks for Queries, Observers for State Changes

**Observer methods should only be triggered by state changes (Set/Create/Delete), never by query responses (Get/Fetch).** Use callbacks for query responses.

```cpp
// ❌ WRONG - observer triggered by a query
void RewardsService::GetRecurringDonations() {
  ledger->GetRecurringDonations([this](auto list) {
    for (auto& observer : observers_)
      observer.OnRecurringDonationsList(list);  // Wrong!
  });
}

// ✅ CORRECT - callback for query
void RewardsService::GetRecurringDonations(GetDonationsCallback callback) {
  ledger->GetRecurringDonations(std::move(callback));
}

// ✅ CORRECT - observer for state change
void RewardsService::SetRecurringDonation(amount) {
  SaveToDB(amount);
  for (auto& observer : observers_)
    observer.OnRecurringDonationUpdated();
}
```

---

## ❌ Don't Expose Internal Library Types in Public Headers

**Never expose internal library types (e.g., `ledger::*`, `bat/ledger/*`) in public component headers.** Use wrapper types defined in the component's public API.

```cpp
// ❌ WRONG - internal ledger types in public rewards header
#include "bat/ledger/ledger.h"
void DoSomething(ledger::PublisherInfo info);

// ✅ CORRECT - use component's own types
#include "brave/components/brave_rewards/browser/content_site.h"
void DoSomething(ContentSite site);
```

---

## ✅ source_set Name Should Match Directory

**GN source_set names should match their directory name.** This makes paths predictable and readable.

```gn
# ❌ WRONG
# In brave/components/brave_referrals/BUILD.gn
source_set("referrals") { ... }
# Referenced as //brave/components/brave_referrals:referrals

# ✅ CORRECT
source_set("browser") { ... }
# Referenced as //brave/components/brave_referrals/browser
```

---

## ✅ Use `CHECK_IS_TEST` for Null Checks That Should Only Occur in Tests

**When a pointer should never be null in production but may be null in certain test configurations, use `CHECK_IS_TEST()` before the null check.** This documents that the null case is test-only and prevents confusion about whether null is a valid production state.

```cpp
// ❌ WRONG - ambiguous null check
if (!g_brave_browser_process->speedreader_rewriter_service())
  return;

// ✅ CORRECT - explicit test-only guard
if (!service) {
  CHECK_IS_TEST();
  return;
}
```

---

## ✅ Pass Dependencies via Constructors, Not Setter Callbacks

**When a service needs a dependency, pass it through the constructor rather than using a separate `Set*Callback` method.** Constructor injection makes dependencies explicit and avoids confusing initialization ordering.

```cpp
// ❌ WRONG - setting callback from an unrelated factory
void BraveVpnServiceFactory::BuildServiceInstanceFor(...) {
  auto* api = BraveVPNOSConnectionAPI::GetInstance();
  api->SetInstallSystemServiceCallback(base::BindRepeating(...));
}

// ✅ CORRECT - pass dependency via constructor
BraveVPNOSConnectionAPI::BraveVPNOSConnectionAPI(
    base::RepeatingCallback<void()> install_callback)
    : install_system_service_callback_(std::move(install_callback)) {}
```

---

## ✅ Use `ServiceIsNULLWhileTesting` for Optional Keyed Services

**When a `KeyedService` should not be created during unit tests that don't provide the required dependencies, override `ServiceIsNULLWhileTesting()` to return `true` in the factory.** This is cleaner than scattering null checks throughout the codebase.

```cpp
// ❌ WRONG - null checks scattered everywhere
void MyService::DoSomething() {
  if (!local_state_) return;  // might be null in tests
}

// ✅ CORRECT - factory controls creation
bool MyServiceFactory::ServiceIsNULLWhileTesting() const {
  return true;
}
```

---

## ❌ Never Call `GetOriginalProfile()` to Bypass Factory Checks

**Never call `GetOriginalProfile()` or similar methods to circumvent factory profile checks.** If a factory returns null for a given profile type, that profile is not supposed to use the service. Respect the factory's decision.

```cpp
// ❌ WRONG - circumventing factory profile checks
auto* profile = Profile::FromBrowserContext(context)->GetOriginalProfile();
auto* service = MyServiceFactory::GetForProfile(profile);

// ✅ CORRECT - respect what the factory returns
auto* service = MyServiceFactory::GetForProfile(
    Profile::FromBrowserContext(context));
if (!service)
  return;
```

---

## ✅ Use `MaybeCreateForWebContents` for Conditional Tab Helpers

**When a tab helper should not be attached to all web contents (e.g., skipped for incognito or when a feature is disabled), use a static `MaybeCreateForWebContents` method** with the appropriate guards instead of always creating and checking internally.

```cpp
// ❌ WRONG - always create, check internally
SerpMetricsTabHelper::CreateForWebContents(web_contents);

// ✅ CORRECT - conditionally create with proper guards
static void MaybeCreateForWebContents(content::WebContents* web_contents) {
  auto* profile = Profile::FromBrowserContext(
      web_contents->GetBrowserContext());
  if (!profile->IsRegularProfile())
    return;
  if (!base::FeatureList::IsEnabled(kSerpMetrics))
    return;
  SerpMetricsTabHelper::CreateForWebContents(web_contents);
}
```

---

## ✅ Use `ProfileKeyedServiceFactory` for New Desktop Factories

**New keyed service factories on desktop should inherit from `ProfileKeyedServiceFactory`** rather than the older `BrowserContextKeyedServiceFactory`. See the Brave keyed services documentation.

---

## ✅ Guard New Functionality Behind `base::Feature`

**New functionality should always be guarded behind a `base::Feature` flag.** Unguarded code that crashes can't be disabled remotely via Griffin/feature flags. Use `raw_ptr` checked before use for services that may not exist in all configurations (System profile, Guest profile, disabled feature).

```cpp
// ❌ WRONG - no feature guard, crash can't be remotely disabled
auto* service = MyNewServiceFactory::GetForProfile(profile);
service->DoSomething();  // Crashes if service unavailable

// ✅ CORRECT - guarded behind feature flag
if (!base::FeatureList::IsEnabled(features::kMyNewFeature))
  return;
auto* service = MyNewServiceFactory::GetForProfile(profile);
if (!service)
  return;
service->DoSomething();
```

---

## ✅ Unify Platform-Specific Delegates

**When implementing functionality for both Android and desktop, unify the code in a single delegate** rather than duplicating it across platforms. Extract only the platform-specific parts (like tab handling) into the delegate interface.

```cpp
// ❌ WRONG - duplicated logic
class DesktopDelegate { /* same logic with BrowserList */ };
class AndroidDelegate { /* same logic with TabModel */ };

// ✅ CORRECT - unified logic, platform-specific tab access
class UnifiedDelegate {
  virtual std::vector<TabInfo> GetOpenTabs() = 0;  // platform-specific
  void DoSharedLogic() { /* uses GetOpenTabs() */ }  // shared
};
```

---

## ❌ Don't Silently Fall Back on Unknown Types

**When handling unknown/unsupported types, prefer an explicit error rather than silently falling back to a default.** Silent fallbacks mask bugs and make debugging harder.

```cpp
// ❌ WRONG - silently treats unknown files as images
FileType GetFileType(const std::string& mime) {
  if (mime == "application/pdf") return FileType::kPDF;
  return FileType::kImage;  // Silent fallback!
}

// ✅ CORRECT - explicit error on unknown
std::optional<FileType> GetFileType(const std::string& mime) {
  if (mime == "application/pdf") return FileType::kPDF;
  if (mime.starts_with("image/")) return FileType::kImage;
  return std::nullopt;  // Caller handles unknown types
}
```

---

## ✅ Separate Lifecycle Events from Data Change Events in Mojo

**A Mojo `Changed` event should only fire when actual data changes occur.** Don't conflate lifecycle events (model loading, listener registration) with data mutation events. Provide separate events.

```cpp
// ❌ WRONG - Changed fires on initialization, not actual change
interface BookmarksListener {
  Changed(BookmarksChange change);  // Fires on model load AND data change
};

// ✅ CORRECT - separate lifecycle and data events
interface BookmarksListener {
  OnBookmarksReady();                // Fires once when model is loaded
  OnBookmarksChanged(BookmarksChange change);  // Only fires on actual changes
};
```

---

## ✅ Use `base::BarrierCallback` for Parallel Async Aggregation

**Use `base::BarrierCallback` to aggregate results from multiple parallel async operations** rather than manually tracking completion counts. This simplifies multi-callback aggregation.

```cpp
// ❌ WRONG - manual tracking
int pending_count_ = 3;
std::vector<Result> results_;
void OnResult(Result r) {
  results_.push_back(std::move(r));
  if (--pending_count_ == 0) OnAllComplete();
}

// ✅ CORRECT - barrier callback
auto barrier = base::BarrierCallback<Result>(
    3, base::BindOnce(&MyClass::OnAllComplete, weak_factory_.GetWeakPtr()));
service1->Fetch(barrier);
service2->Fetch(barrier);
service3->Fetch(barrier);
```

---

## ❌ Mojom Enums Must Be Top-Level When Targeting iOS

**Mojom enums cannot be nested inside mojom structs when the target includes iOS.** The Objective-C++ code generator produces invalid code for nested enums (`common.mojom.objc.mm` build failure). Always define mojom enums at the top level of the `.mojom` file.

```mojom
// ❌ WRONG - nested enum breaks iOS build
struct ModelConfig {
  enum Category {
    kChat = 0,
    kCompletion = 1,
  };
  Category category;
};

// ✅ CORRECT - top-level enum
enum ModelCategory {
  kChat = 0,
  kCompletion = 1,
};

struct ModelConfig {
  ModelCategory category;
};
```

---

## ❌ No Content-Layer Dependencies for iOS-Targeted Components

**Components that must build for iOS (like `brave_wallet`) cannot depend on content-layer types** (`content::WebContents`, `content::BrowserContext`). iOS uses WebKit, not Chromium's content layer. Pass specific dependencies (`PrefService*`, `URLLoaderFactory`) instead.

---

## ✅ Service/Decoder Code Belongs in `services/` Not `components/.../browser/`

**Mojo service implementations and data decoders should live in a `services/` directory**, not inside `components/.../browser/`. This follows Chromium conventions and keeps service code at the correct architectural layer.

---

## ✅ Prefer Static Singleton Over KeyedService When No Profile Dependency

**When a service has no per-profile state and doesn't depend on profile-specific data, use a static singleton with `base::NoDestructor` instead of a `KeyedService`.** KeyedService adds unnecessary complexity when there's no profile dependency.

```cpp
// ❌ WRONG - KeyedService for profile-independent data
class ModelListServiceFactory : public BrowserContextKeyedServiceFactory { ... };

// ✅ CORRECT - static singleton
class ModelListService {
 public:
  static ModelListService& GetInstance() {
    static base::NoDestructor<ModelListService> instance;
    return *instance;
  }
};
```

---

## ✅ Flag Destructive Pref Operations for UX Review

**Operations that delete user data (clearing preferences, wiping storage) must be flagged for UX review before implementation.** Silent data deletion is a poor user experience and may violate user expectations.

---

## ✅ Use Pre-Allocated Vectors for Ordered Async Results

**When aggregating results from multiple parallel async calls that must maintain order, pre-allocate a vector and insert results by index** rather than using a map and sorting later.

```cpp
// ❌ WRONG - map loses original order
std::map<int, Result> results_by_index_;

// ✅ CORRECT - pre-allocated vector with indexed insertion
std::vector<Result> results_(num_requests);
// In each callback:
results_[request_index] = std::move(result);
```

---

## ✅ Use Existing Mojom Types Instead of Duplicating in C++

**When mojom types already describe the data shape, use them directly in C++ instead of creating redundant C++ struct types.** Duplicating types creates a synchronization burden and increases the risk of the two definitions drifting apart.

```cpp
// ❌ WRONG - redundant C++ struct
struct ToolConfig {
  std::string name;
  std::string description;
};

// ✅ CORRECT - use the mojom type directly
// mojom::ToolConfig already has name and description fields
void RegisterTool(mojom::ToolConfigPtr config);
```

---

## ❌ Don't Expose Cache Keys in API Interfaces

**Internal cache keys should not leak into public API interfaces.** Auto-generate unique cache keys internally rather than requiring callers to provide or manage them.

```cpp
// ❌ WRONG - caller must know about cache keys
void FetchData(const std::string& url, const std::string& cache_key,
               Callback cb);

// ✅ CORRECT - cache key generated internally
void FetchData(const std::string& url, Callback cb);
// Internally: cache_key = GenerateKey(url, params)
```

---

## ✅ Reorder Data for UI Presentation on Client Side

**Data reordering for UI presentation (sorting, grouping, prioritizing) belongs in the client/UI layer, not in the core data layer or API response.** The backend should return data in its canonical order; the frontend transforms it for display.

---

## ✅ Use Mojo Interfaces for Trusted/Untrusted WebUI Communication

**When communicating between trusted and untrusted WebUI frames, use a mojo interface rather than `postMessage`.** The Chromium documentation advises against `postMessage` across trust boundaries. Only avoid mojo when the frame intentionally executes untrusted code and reducing API surface is a deliberate security choice.

---

## ✅ Set Default Values in Mojom Struct Fields

**Mojom struct fields should have explicit default values for safety.** Uninitialized mojom fields can lead to unexpected behavior when the struct is partially constructed.

```mojom
// ❌ WRONG - no defaults
struct ModelConfig {
  string name;
  bool supports_tools;
};

// ✅ CORRECT - explicit defaults
struct ModelConfig {
  string name = "";
  bool supports_tools = false;
};
```
