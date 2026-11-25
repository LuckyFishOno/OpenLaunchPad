# Releasing OpenLaunchPad

Installed copies update through Sparkle. **Check for Updates** in the search
field's menu reads `appcast.xml` from the latest GitHub release and installs the
DMG only if its EdDSA signature matches the public key in the app.

## The update signing key

`OPENLAUNCHPAD_UPDATE_KEY` in `project.yml` is the public half. The private half
stays in the owner's login Keychain, under the account `OpenLaunchPad`
(`OPENLAUNCHPAD_KEY_ACCOUNT` selects another). Sparkle's tools live in this
project's `.build`, and `release.sh` uses the same copy. Fetch them once, then
export a backup to keep in a password manager, never in the repository:

```sh
xcodebuild -project OpenLaunchPad.xcodeproj -scheme OpenLaunchPad -clonedSourcePackagesDirPath "$PWD/.build" -resolvePackageDependencies
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account OpenLaunchPad -x BACKUP_FILE
```

On another Mac, import the backup with `-f BACKUP_FILE` and delete the file
afterwards. If the key is lost, installed copies can no longer update
themselves. Do not replace the key for any other reason. While the public key is
empty, the menu command is hidden and `release.sh` refuses to build.

## Steps

1. Raise `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` on both apps in
   `project.yml`, run `xcodegen generate`, and update `CHANGELOG.md` and both
   READMEs. The build number rises by one for every release and is never reused.
2. Commit on `main`, then run `scripts/release.sh build VERSION BUILD`.
3. Push `main`, and write the notes to `Builds/release/VERSION-BUILD/notes.md`.
4. Run `scripts/release.sh publish VERSION BUILD Builds/release/VERSION-BUILD/notes.md`.
5. On a Mac with the previous release, choose **Check for Updates** and confirm
   that it offers, installs, and reopens the new version.

Copies without the updater (1.1 and earlier) must be updated by hand once.

To test against another feed, pass `OPENLAUNCHPAD_FEED_URL` and
`OPENLAUNCHPAD_UPDATE_KEY` to `xcodebuild`.
