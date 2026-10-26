# HARIVAS iOS – Multi-Target WebView App

Five separate App Store apps sharing a single Swift codebase, each pointing to a different portal on **https://gkgos.in**.

| Target | Bundle ID | Portal | Accent Colour |
|--------|-----------|--------|---------------|
| HARIVASStore  | `com.harivas.store`  | `/harivas/`         | Green  `#388E3C` |
| HARIVASRider  | `com.harivas.rider`  | `/harivas-rider/`   | Yellow `#F8CB46` |
| HARIVASVendor | `com.harivas.vendor` | `/harivas-vendor/`  | Blue   `#1565C0` |
| HARIVASStaff  | `com.harivas.staff`  | `/harivas-staff/`   | Purple `#6A1B9A` |
| HARIVASAdmin  | `com.harivas.admin`  | `/harivas-admin/`   | Red    `#B71C1C` |

---

## Prerequisites

| Tool | Install |
|------|---------|
| Xcode 15+ | Mac App Store |
| XcodeGen | `brew install xcodegen` |
| CocoaPods | `sudo gem install cocoapods` |
| Fastlane (optional) | `brew install fastlane` |

---

## Local Setup

```bash
# 1. Clone the repo
git clone <repo-url>
cd harivas-ios

# 2. Generate the Xcode project
xcodegen generate

# 3. Install CocoaPods dependencies
pod install

# 4. Open the workspace (NOT the .xcodeproj)
open HARIVASApp.xcworkspace
```

In Xcode:
- Select the desired **scheme** from the toolbar (e.g. `HARIVASStore`)
- Pick a simulator or physical device
- Press **⌘R** to build and run

---

## Adding App Icons

Place a **1024×1024 PNG** named `AppIcon.png` in each asset folder:

```
Assets/Store/AppIcon.appiconset/AppIcon.png
Assets/Rider/AppIcon.appiconset/AppIcon.png
Assets/Vendor/AppIcon.appiconset/AppIcon.png
Assets/Staff/AppIcon.appiconset/AppIcon.png
Assets/Admin/AppIcon.appiconset/AppIcon.png
```

Xcode will generate all required sizes automatically.

---

## Firebase / Push Notifications

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Create **5 separate iOS apps** (one per bundle ID)
3. Download each `GoogleService-Info.plist`
4. Place them in the corresponding target folder:
   ```
   Targets/Store/GoogleService-Info.plist
   Targets/Rider/GoogleService-Info.plist
   ...
   ```
5. Add each plist to its target in Xcode (**Target Membership** checkbox)
6. In Firebase → Project Settings → Cloud Messaging: upload your **APNs Auth Key** (`.p8`)

---

## Apple Developer Setup

1. Log in to [developer.apple.com](https://developer.apple.com)
2. Create **5 App IDs** matching the bundle IDs above
3. Enable capabilities for each:
   - All: **Push Notifications**, **Background Modes** (remote-notification, background fetch)
   - Rider only: also enable **Background Modes → Location updates**
4. Create **Distribution Certificates** and **Provisioning Profiles** for each app
5. Download and double-click to install the `.mobileprovision` files

---

## Codemagic CI/CD Setup

1. Push the repo to GitHub / Bitbucket / GitLab
2. Connect it to [Codemagic](https://codemagic.io)
3. For **each** of the 5 workflows, create a variable group in Codemagic:

   | Variable | Description |
   |----------|-------------|
   | `APPLE_TEAM_ID` | Your 10-char Team ID |
   | `CM_CERTIFICATE` | Base64-encoded `.p12` distribution cert |
   | `CERTIFICATE_PRIVATE_KEY` | The cert private key |
   | `CM_PROVISIONING_PROFILE` | Base64-encoded `.mobileprovision` |
   | `CM_CERTIFICATE_PASSWORD` | p12 password |

   Use these group names: `harivas_store_signing`, `harivas_rider_signing`, `harivas_vendor_signing`, `harivas_staff_signing`, `harivas_admin_signing`

4. Trigger a build per workflow or set up auto-triggers on branch pushes

---

## Fastlane

```bash
# Build Store IPA
bundle exec fastlane build_store

# Build Rider IPA
bundle exec fastlane build_rider

# Build all at once (from CI)
bundle exec fastlane build_all
```

---

## Project Structure

```
harivas-ios/
├── project.yml                 ← XcodeGen spec
├── Podfile                     ← CocoaPods
├── codemagic.yaml              ← CI/CD
├── fastlane/
│   └── Fastfile
├── Sources/                    ← Shared Swift code (all targets)
│   ├── AppDelegate.swift
│   ├── SceneDelegate.swift
│   ├── WebViewController.swift
│   ├── LocationManager.swift
│   └── PushNotificationManager.swift
├── Targets/
│   ├── Store/Info.plist
│   ├── Rider/Info.plist
│   ├── Vendor/Info.plist
│   ├── Staff/Info.plist
│   └── Admin/Info.plist
└── Assets/
    ├── Store/AppIcon.appiconset/
    ├── Rider/AppIcon.appiconset/
    ├── Vendor/AppIcon.appiconset/
    ├── Staff/AppIcon.appiconset/
    ├── Admin/AppIcon.appiconset/
    └── AccentColor/
        ├── Store.colorset/
        ├── Rider.colorset/
        ├── Vendor.colorset/
        ├── Staff.colorset/
        └── Admin.colorset/
```

---

## Native JS Bridge

The app injects `window.HvNative` into every page:

```javascript
// Check if running inside the native app
if (window.HvNative && window.HvNative.isIOSApp) {
    console.log('Version:', window.HvNative.getAppVersion());
}

// Start GPS tracking for a rider order
window.HvNative.startLocationTracking('ORDER-12345');

// Stop GPS tracking
window.HvNative.stopLocationTracking();

// Request push notification permission
window.HvNative.requestNotificationPermission();
```

---

## Scheme Interception

The native app intercepts and opens these URL schemes in the system app:
`tel:`, `mailto:`, `maps:`, `upi:`, `razorpay:`, `phonepe:`

External `https://` links open in an in-app `SFSafariViewController`.
Same-host links stay in the WKWebView.
