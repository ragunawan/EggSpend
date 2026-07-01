# App Store Privacy Details

Use these answers for App Store Connect based on the current app behavior.

## Privacy Policy

- Privacy policy URL: https://github.com/ragunawan/EggSpend/blob/main/docs/app-store-privacy.md

## Data Collection

- Data collected by developer: no.
- App Store Connect selection: Data Not Collected.

EggSpend stores user data locally with SwiftData and can sync through the user's private iCloud/CloudKit account. The developer does not operate an account system, backend, analytics service, crash-reporting service, support-log collection flow, or other mechanism that gives the developer access to this data.

## Data Processed Only For App Functionality

The app processes the following user-provided data on device/private iCloud only:

- Financial Info: transaction amounts, dates, budgets, account balances, recurring transactions, savings goals, and imported CSV financial records.
- User Content: imported CSV contents and optional notes attached to transactions, accounts, recurring transactions, and savings goals.

These are used only for app functionality and are not collected by the developer.

## App Permissions

EggSpend does not request any sensitive system permissions:

- Camera: not requested.
- Photo library: not requested.
- Location: not requested.
- Contacts: not requested.
- Face ID / biometric authentication: not requested.
- Push notifications: not requested.
- Microphone: not requested.

CSV import uses the system file picker (SwiftUI `.fileImporter`) to read a user-selected local file; it does not access the photo library or camera.

## Network Access

- No direct network requests are made by the app (no `URLSession` usage).
- The only network activity is Apple's own CloudKit sync, used by SwiftData to sync records to the user's private iCloud account (container `iCloud.dev.gnwn.EggSpend`). This is optional and automatically falls back to local-only storage if iCloud is unavailable or the user isn't signed in.
- No third-party SDKs, dependencies, analytics, or crash-reporting services are included in the app.

## Tracking And Analytics

- Tracking across apps/websites: no.
- Advertising: no.
- Third-party analytics: no.
- Third-party crash reporting: no.
- Developer account/sign-in requirement: no.

## Data Deletion

- All data lives on-device or in the user's private iCloud account; the developer holds no copy and cannot access or delete it on the user's behalf.
- Users can delete data by removing records in-app, or by deleting the app, which removes local data and syncs any deletions to the user's private CloudKit database if iCloud sync was enabled.

## Children's Privacy

- EggSpend collects no personal data from any user, including children, and has no account system or age gating.

## Privacy Manifest

`EggSpend/PrivacyInfo.xcprivacy` declares:

- No collected data types.
- No tracking.
- No tracking domains.
- No required-reason API usage.
