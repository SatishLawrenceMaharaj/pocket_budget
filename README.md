# Pocket Budget — private Flutter budgeting app

An **offline-first, personal Android/iOS app** in Flutter. Designed for private installation, without an account, server, cloud database, advertisements, analytics, or submission to an app store.

## Included features

- Dashboard for any month: recorded credits, debits, monthly net cash flow, category spending, planned budget and remaining budget.
- CSV bank-statement import with flexible column headers; handles signed `Amount` or separate `Debit` and `Credit` columns. Date formats include Trinidad and Tobago `DD/MM/YYYY` and ISO `YYYY-MM-DD`.
- Idempotent transaction import: deterministic IDs derived from account label, date, description, amount, reference and duplicate-row occurrence number. Re-importing the **same CSV with the same account label** will not duplicate its transactions.
- Manual credit/debit entries; re-categorize or delete transactions. No credentials are requested.
- Category-specific monthly spending limits, independent for each month.
- **One persisted report for each `YYYY-MM`** in the encrypted local vault. Importing new transactions or editing category budgets recomputes that same report; it doesn't append a duplicate.
- Saved month history and rule-based recommendations (overspending, savings gap, uncategorized spending, top spending category).
- Fingerprint / Face ID / device PIN authentication at launch; app also re-locks after >30 seconds in background; manual lock button.
- AES-256-GCM encrypted private file, with key stored via Android Keystore / iOS Keychain. Native setup script disables Android data backups and excludes iOS Application Support from device/iCloud backups.

## Easy Android install — no local Flutter installation

**An APK is not included in this source ZIP**, because an Android/Flutter SDK
was not available in the environment that created it, and the APK was not
compiled or tested here. The project now includes a GitHub Actions workflow
(`.github/workflows/android-apk.yml`) that builds the Android APK on a hosted
runner, without installing developer software on your phone or computer.

1. Create a **new PRIVATE repository** in your personal GitHub account. Do not
   place this personal finance app in a corporate repository.
2. Upload the **contents of the ZIP**, preserving the hidden `.github` folder,
   directly into the repository. GitHub's web interface can upload the unzipped
   files (including nested files when dragged as a folder using a compatible browser),
   or use Git to push the whole project.
3. Open the repository's **Actions** tab → **Build Pocket Budget Android APK**
   → **Run workflow**. The build runner downloads Flutter and compiles an APK.
4. If the workflow finishes successfully, open its run → **Artifacts** →
   **pocket-budget-android-apk**. Download and extract the artifact ZIP on
   your Android device, then tap `app-release.apk` to install it. Android might
   prompt you to allow installs from the browser/file manager. Grant that
   permission only when you trust the APK source.
5. Open **Pocket Budget**, authenticate with your phone's PIN/fingerprint,
   and start recording or importing transactions. No Republic Bank credentials
   are ever requested.

**Important signing limitation:** The starter workflow uses the standard
Flutter-generated Android debug signing configuration for a release-mode APK.
Hosted runners do **not** have a persistent signing key. Future builds may
use a different key, which Android will not accept as an update. Uninstalling
to replace the app would destroy the local encrypted history. For long-term
use, set up a **stable personal signing keystore**, stored securely and never
committed to a public repository, and update the workflow to sign all new
versions consistently **before installing and storing real financial data**.
This workflow has not been run here; resolve any build failures reported in
GitHub Actions before relying on the app for your actual finances.

## Requirements

- Flutter **3.38+ / Dart 3.10+**, Android Studio and/or Xcode (macOS required for iOS signing/builds).
- Android min API **24**; iOS **14+** (due to file picker).
- A physical device or configured emulator with a device passcode/biometric auth.

## Set up and run

Because this source bundle is platform-independent, the **generated Android and iOS platform folders are not included**. Create them using your locally installed Flutter SDK:

```bash
unzip pocket_budget_flutter.zip
cd pocket_budget_flutter
flutter create --platforms=android,ios --project-name=pocket_budget --org=app.privatebudget .
python3 scripts/configure_platforms.py
flutter pub get
flutter analyze
flutter test
flutter run
```

On **Windows**, if iOS template generation is unavailable, use `flutter create --platforms=android --project-name=pocket_budget --org=app.privatebudget .` and `py scripts\configure_platforms.py`, then create/build the iOS platform on a Mac later. Run the Python setup script again after generating iOS files.

Android personal installation (connect phone by USB + Android debugging):

```bash
flutter devices
flutter build apk --release
# Android APK location: build/app/outputs/flutter-apk/app-release.apk
# Transfer and install on your own device. Keep it private.
```

For iOS: open `ios/Runner.xcworkspace` with Xcode on a Mac, set the signing team and bundle identifier, connect your iPhone, and run `flutter run --release` or use Xcode's **Run**. Apple signing/provisioning rules apply even for personal installs; no App Store submission required. Keep a local copy of the source and signing setup.

If you re-run `flutter create`, also re-run `python3 scripts/configure_platforms.py`. Inspect platform files as native Flutter templates evolve.

## Importing your bank statement

1. Sign in **directly to the official bank app or official online banking site** (outside Pocket Budget).
2. Where available, export the account history to **CSV**. Republic Bank products/regions may have different export options; verify for your Republic Bank Limited personal account. If unavailable, use manual entry or create your own CSV from a downloaded statement.
3. Open Pocket Budget → **Import bank CSV statement**. Assign a consistent, distinct account label such as `Republic Chequing` or `Republic Savings` (avoid full account numbers).
4. Verify transaction dates, credit/debit direction and categorized expenses. Modify category by tapping any transaction.
5. Set limits under **Monthly budget → Edit**.

Example: [`samples/transactions.csv`](samples/transactions.csv)

```csv
Date,Description,Debit,Credit,Reference
01/10/2026,Salary October,,12000.00,PAY001
02/10/2026,Grocery Supermarket,350.40,,TX001
```

Supported headers:

- Date: `Date`, `Transaction Date`, `Posting Date`, `Value Date`, `Txn Date`
- Description: `Description`, `Details`, `Narrative`, `Transaction Details`, `Merchant`, `Memo`
- Money: `Amount`, `Transaction Amount`, `Net Amount`, `Signed Amount`, **or** a `Debit`/`Credit` pair (also `Withdrawals`/`Deposits`)
- Optional unique reference: `Reference`, `Transaction ID`, `Transaction Reference`, `Ref`, `ID`

If your actual statement has a different header layout, extend the aliases in `lib/services/transaction_importer.dart` or convert it into the sample schema. CSV exports from different providers are **not guaranteed** to work without adjustment.

**Important accounting notes**

- `Credits` means all positive bank movements and `Debits` means all negative movements, **not necessarily salary and consumption**. Transfers between your own accounts, loan proceeds, card repayments, refunds or reversals can distort calculated net cash flow. The app does not reconcile transfers between accounts or identify duplicates across different accounts. Treat the dashboard as a **cash-flow tracker** rather than a financial accounting ledger.
- Identical transactions without unique bank references on the same date can be ambiguous across overlapping partial exports. The same file can be imported repeatedly without duplication, but exports with different subsets of identical rows need manual review.
- CSV values use decimal `.` and optional comma thousands separators. `03/04/2026` is parsed as **3 April 2026**. CSV only: no PDF/OCR, XLSX or automatic bank refresh in this version.
- Recommendations are rule-based (no AI/API calls), and results depend on your imports and categorization.

## Security, privacy and recovery

- This app **never asks for your Republic Bank username, password, security answers, OTP or MFA code**. It is not affiliated with Republic Bank Limited.
- Banking app integration is **not implemented**; it must only be added later with verified bank-supported OAuth/consent APIs and terms. Never scrape or embed a login form to capture passwords.
- The saved vault is an encrypted file within private application storage. The encryption key is device-bound. **No cloud sync or automatic backup.** Uninstalling the app, losing access to the device Keychain/Keystore, or resetting the phone can **permanently lose all transaction history**.
- Imported CSVs **may remain unencrypted in Downloads, Files, or another export location** after import, and the OS picker may temporarily copy data. Delete imported plaintext files using your phone's file manager when no longer needed. Avoid sharing originals or screenshots of financial data.
- A rooted/jailbroken device, malicious keyboard, compromised OS or running app memory cannot be completely protected by app encryption. Keep the phone updated and protected by a device lock.
- For real financial use, test with non-sensitive sample data first and verify import semantics against your actual bank statement.
- The app stores values in **integer cents**, avoiding cumulative binary floating-point errors in reports. Imported decimal amounts are rounded to cents.

## Testing and project status

There are unit tests for CSV parsing, report uniqueness, re-import behavior, budget updates, JSON round-trip, and advice triggers. Run `flutter analyze && flutter test` locally after installing Flutter. The code was prepared without a Flutter SDK in the build environment; **no APK/IPA has been compiled or tested on a device here**.

Main files:

- `lib/main.dart`: app and device-authentication guard
- `lib/ui/home_screen.dart`: overview, activity, insights, month history, import/manual edits
- `lib/models.dart`: budget transactions, monthly reports, report upsert logic
- `lib/services/transaction_importer.dart`: CSV parsing and stable transaction identity
- `lib/services/secure_budget_store.dart`: encrypted local persistence
- `lib/services/recommendations.dart`: offline budget recommendations
- `scripts/configure_platforms.py`: post-generation Android/iOS privacy and biometric settings

## Extending it later

Potential next iteration: mapping UI for arbitrary bank CSV columns, PDF statements, account reconciliation, bill rules and saving goals, encrypted offline export/import with a user-supplied recovery password, and bank-approved OAuth if RBL publishes/authorizes the needed integration. Maintain offline-only as the default.
#   p o c k e t _ b u d g e t  
 