# CI/CD

`hanbin2007/jy-laundry` ships the app to TestFlight as **JY Laundry**
(`com.zhanghanbin.laundry`, team `NCLY9ZGRMZ`).

## What runs when

| Event | Workflow | What happens |
|---|---|---|
| Pull request, push to any branch except `main` | `CI` | iOS Debug build (simulator) and Release build (device, unsigned), unit tests if the scheme has any, server Python and shell checks |
| Push to `main` | `TestFlight` | Runs `CI`, then archives, signs and uploads a new build to TestFlight |
| Tag `v1.2.0` | `TestFlight` | Same, with the app version set to `1.2.0` |
| Manual (Actions → TestFlight → Run workflow) | `TestFlight` | Same, with optional "What to Test" text |

Each upload gets build number *highest build on App Store Connect + 1*, so
numbers never clash, even with builds uploaded by hand. The "What to Test" text
is the list of commit messages in the push. Every build goes to the internal
TestFlight group **Internal**, which receives all builds automatically.

Only this repo uploads builds; the TestFlight job is skipped in forks, and
pull requests from forks never see the secrets.

## Server settings

The server URL and access token are not in the source. The app and its widgets
read them from `Info.plist`, which gets them from the build settings
`LAUNDRY_SERVER_URL` and `LAUNDRY_SERVER_TOKEN`:

- **Local builds:** copy `Config/Secrets.example.xcconfig` to
  `Config/Secrets.xcconfig` (gitignored) and fill it in.
- **CI:** `scripts/ci/testflight.sh` writes that file from the
  `LAUNDRY_SERVER_URL` and `LAUNDRY_SERVER_TOKEN` secrets.
- Without them the app builds and runs, with no server set; it can be entered
  in the app's Settings.

## Signing

The archive is built unsigned. `xcodebuild -exportArchive` then signs it with a
cloud-managed Apple Distribution certificate and creates the App Store
provisioning profiles itself, using the App Store Connect API key. No
certificates or profiles are stored in the repo or in secrets.

## Settings

| Name | Kind | Value |
|---|---|---|
| `ASC_KEY_ID` | Actions variable | App Store Connect API key ID |
| `ASC_ISSUER_ID` | Actions variable | App Store Connect issuer ID |
| `ASC_PRIVATE_KEY` | Actions secret | Contents of `AuthKey_<KEY_ID>.p8` |
| `LAUNDRY_SERVER_URL` | Actions secret | Server base URL, e.g. `http://host/laundry` |
| `LAUNDRY_SERVER_TOKEN` | Actions secret | Server access token |

## Running it by hand

On a Mac with Xcode 27.2, the API key and `Config/Secrets.xcconfig`:

```sh
export ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
bash scripts/ci/testflight.sh                # archive, sign, upload, wait for processing
EXPORT_ONLY=1 bash scripts/ci/testflight.sh  # sign and export an .ipa only
```

Run it from a Terminal window on the Mac itself, not over SSH: over SSH the
login keychain is locked and codesign fails with `errSecInternalComponent`.

`scripts/ci/asc.py` is a small App Store Connect API client used by the script
(next build number, wait for processing, What to Test, beta groups).

## Notes

- Runners: `xcode-27` (GitHub's Xcode 27 image, Xcode 27.2). macOS minutes are
  free for public repos.
- `Info.plist` sets `ITSAppUsesNonExemptEncryption = NO` (the app only uses
  HTTPS), so builds don't wait on the export-compliance question.
- Submitting to App Store review is deliberately not automated.
