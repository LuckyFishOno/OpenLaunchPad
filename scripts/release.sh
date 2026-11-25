#!/bin/sh
# Builds and publishes an OpenLaunchPad release. See docs/RELEASING.md.
#
#   scripts/release.sh build VERSION BUILD [--skip-tests]
#   scripts/release.sh publish VERSION BUILD NOTES.md
#
# `build` tests, builds, signs, and checks Builds/release/VERSION-BUILD/OpenLaunchPad.dmg. `publish` writes the
# signed update feed, then creates the tag and the GitHub release with the DMG and the feed.
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
github_repo=LuckyFishOno/OpenLaunchPad
feed_url="https://github.com/$github_repo/releases/latest/download/appcast.xml"
account=${OPENLAUNCHPAD_KEY_ACCOUNT:-OpenLaunchPad}

fail() { printf 'release: %s\n' "$*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }

[ $# -ge 3 ] || fail "usage: release.sh build VERSION BUILD [--skip-tests] | release.sh publish VERSION BUILD NOTES.md"
command=$1 version=$2 build=$3
shift 3
printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+(\.[0-9]+)?$' || fail "VERSION must look like 1.2 or 1.2.1, not '$version'"
printf '%s' "$build" | grep -Eq '^[0-9]+$' || fail "BUILD must be a whole number, not '$build'"

tag="v$version"
title="OpenLaunchPad $version (build $build)"
out_dir="$repo_dir/Builds/release/$version-$build"
derived="$repo_dir/Builds/release/DerivedData"
packages="$repo_dir/.build"
sparkle_dir="$packages/artifacts/sparkle/Sparkle"
sparkle_bin="$sparkle_dir/bin"
dmg="$out_dir/OpenLaunchPad.dmg"
app="$out_dir/OpenLaunchPad.app"
agent="$app/Contents/Library/LoginItems/OpenLaunchPadAgent.app"
cd "$repo_dir"

check_tree() {
    [ "$(git rev-parse --abbrev-ref HEAD)" = main ] || fail "check out main first"
    [ "$(grep -c "MARKETING_VERSION: \"$version\"$" project.yml)" = 2 ] &&
        [ "$(grep -c "CURRENT_PROJECT_VERSION: $build$" project.yml)" = 2 ] ||
        fail "set MARKETING_VERSION $version and CURRENT_PROJECT_VERSION $build on both apps in project.yml, run xcodegen, and commit"
    [ -z "$(git status --porcelain)" ] || { git status --short >&2; fail "commit or stash the changes above first"; }
    if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then fail "tag $tag already exists"; fi
}

public_key() { sed -n 's/^ *OPENLAUNCHPAD_UPDATE_KEY: "\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' project.yml; }

# The EdDSA private key that signs updates must be in this Mac's login Keychain and match SUPublicEDKey.
check_update_key() {
    [ -n "$(public_key)" ] || fail "OPENLAUNCHPAD_UPDATE_KEY is empty in project.yml (docs/RELEASING.md)"
    if [ ! -x "$sparkle_bin/generate_keys" ]; then
        xcodebuild -project OpenLaunchPad.xcodeproj -scheme OpenLaunchPad \
            -clonedSourcePackagesDirPath "$packages" -resolvePackageDependencies >/dev/null
    fi
    actual=$("$sparkle_bin/generate_keys" --account "$account" -p 2>/dev/null) ||
        fail "the $account update signing key is not in the login Keychain; import the backup (docs/RELEASING.md)"
    [ "$actual" = "$(public_key)" ] || fail "the Keychain's update key does not match OPENLAUNCHPAD_UPDATE_KEY"
}

check_newer_build() {
    latest=$(gh release list -R "$github_repo" --limit 50 --json name -q '.[].name' 2>/dev/null |
        sed -n 's/.*(build \([0-9][0-9]*\)).*/\1/p' | sort -n | tail -1)
    if [ -n "$latest" ] && [ "$build" -le "$latest" ]; then fail "build $build is not above the published build $latest"; fi
}

case $command in
build)
    skip_tests=no
    [ "${1:-}" = --skip-tests ] && skip_tests=yes
    check_tree
    check_newer_build
    check_update_key
    [ ! -e "$out_dir" ] || fail "$out_dir exists; move it away and run again"

    if [ $skip_tests = no ]; then
        step "Swift tests"
        swift test
    fi

    step "Build OpenLaunchPad $version ($build)"
    mkdir -p "$out_dir/products"
    xcodebuild -project OpenLaunchPad.xcodeproj -scheme OpenLaunchPad -configuration Release \
        -derivedDataPath "$derived" -clonedSourcePackagesDirPath "$packages" CONFIGURATION_BUILD_DIR="$out_dir/products" CODE_SIGN_IDENTITY=- \
        ARCHS=arm64 -quiet build
    ditto "$out_dir/products/OpenLaunchPad.app" "$app"

    # Sparkle's nested helpers are signed before the framework, the agent, and the app.
    sparkle="$agent/Contents/Frameworks/Sparkle.framework"
    cp "$sparkle_dir/LICENSE" "$app/Contents/Resources/Sparkle-LICENSE.txt"
    for nested in "$sparkle"/Versions/B/XPCServices/*.xpc "$sparkle/Versions/B/Autoupdate" \
        "$sparkle/Versions/B/Updater.app" "$sparkle" "$agent" "$app"; do
        codesign --force --sign - "$nested"
    done

    step "Verify the app"
    for plist in "$app/Contents/Info.plist" "$agent/Contents/Info.plist"; do
        [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" = "$version" ] || fail "$plist is not $version"
        [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")" = "$build" ] || fail "$plist is not build $build"
    done
    plist="$app/Contents/Info.plist"
    [ "$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$plist")" = "$feed_url" ] || fail "the update feed is not $feed_url"
    [ "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$plist")" = "$(public_key)" ] || fail "the app's update key is wrong"
    [ -f "$sparkle/Versions/B/Sparkle" ] || fail "Sparkle.framework is missing"
    codesign --verify --deep --strict "$app"
    for binary in "$app/Contents/MacOS/OpenLaunchPad" "$agent/Contents/MacOS/OpenLaunchPadAgent"; do
        [ "$(lipo -archs "$binary")" = arm64 ] || fail "$binary is not arm64"
    done

    step "Make and verify OpenLaunchPad.dmg"
    mkdir -p "$out_dir/dmg"
    ditto "$app" "$out_dir/dmg/OpenLaunchPad.app"
    ln -s /Applications "$out_dir/dmg/Applications"
    hdiutil create -volname OpenLaunchPad -srcfolder "$out_dir/dmg" -fs HFS+ -format UDZO -imagekey zlib-level=9 "$dmg" >/dev/null
    hdiutil verify "$dmg" >/dev/null
    (cd "$out_dir" && shasum -a 256 OpenLaunchPad.dmg > OpenLaunchPad.dmg.sha256)
    printf 'DMG:     %s\nSHA-256: %s\nCommit:  %s\n' "$dmg" \
        "$(cut -d' ' -f1 "$out_dir/OpenLaunchPad.dmg.sha256")" "$(git rev-parse HEAD)"
    ;;

publish)
    [ $# -ge 1 ] || fail "publish needs the release notes file"
    notes=$1
    [ -s "$notes" ] || fail "release notes '$notes' are missing or empty"
    check_tree
    check_newer_build
    check_update_key
    [ -f "$dmg" ] || fail "no $dmg; run 'release.sh build $version $build' first"
    (cd "$out_dir" && shasum -a 256 -c OpenLaunchPad.dmg.sha256 >/dev/null) || fail "the DMG changed after it was built"

    step "Check that main is on GitHub"
    commit=$(git rev-parse HEAD)
    remote=$(git ls-remote "https://github.com/$github_repo.git" refs/heads/main | cut -f1)
    [ "$remote" = "$commit" ] || fail "GitHub main is ${remote:-unknown}, not $commit; push main first"

    step "Write the update feed"
    notes_html="$out_dir/notes.html"
    gh api markdown -f mode=gfm -f context="$github_repo" -F text=@"$notes" > "$notes_html" ||
        fail "GitHub could not render $notes as HTML"
    appcast="$out_dir/appcast.xml"
    ./scripts/appcast.sh "$version" "$build" "$dmg" \
        "https://github.com/$github_repo/releases/download/$tag/OpenLaunchPad.dmg" "$notes_html" "$sparkle_bin" > "$appcast"
    xmllint --noout "$appcast" || fail "appcast.xml is not well-formed XML"

    step "Create $tag"
    body="$out_dir/body.md"
    cat "$notes" > "$body"
    cat >> "$body" <<EOF

## Build information
- Tag: $tag
- App version: $version
- Build number: $build
- Architecture: arm64
- Minimum macOS: 15.0
- Commit: $commit
- OpenLaunchPad.dmg SHA-256: $(cut -d' ' -f1 "$out_dir/OpenLaunchPad.dmg.sha256")
EOF
    gh release create "$tag" "$dmg" "$appcast" -R "$github_repo" --target "$commit" --title "$title" --notes-file "$body" --latest

    step "Verify the release"
    curl -fsIL "https://github.com/$github_repo/releases/latest/download/OpenLaunchPad.dmg" >/dev/null ||
        fail "the latest-download link does not answer"
    curl -fsL "$feed_url" | grep -qF "<sparkle:version>$build</sparkle:version>" ||
        fail "the update feed at $feed_url does not offer build $build"
    printf 'Published %s: https://github.com/%s/releases/tag/%s\n' "$title" "$github_repo" "$tag"
    ;;

*) fail "unknown command '$command'; use build or publish" ;;
esac
