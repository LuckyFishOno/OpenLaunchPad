#!/bin/sh
# Writes the Sparkle update feed (appcast.xml) for one release to standard output.
#
#   scripts/appcast.sh VERSION BUILD DMG DOWNLOAD_URL NOTES.html SPARKLE_BIN
#
# The DMG is signed with the EdDSA key in the login Keychain, whose public half is OPENLAUNCHPAD_UPDATE_KEY in
# project.yml. Sparkle installs the DMG only if the signature matches. release.sh publish calls this.
set -eu

account=${OPENLAUNCHPAD_KEY_ACCOUNT:-OpenLaunchPad}
fail() { printf 'appcast: %s\n' "$*" >&2; exit 1; }
[ $# -eq 6 ] || fail "usage: appcast.sh VERSION BUILD DMG DOWNLOAD_URL NOTES.html SPARKLE_BIN"
version=$1 build=$2 dmg=$3 url=$4 notes=$5 sign_update=$6/sign_update
[ -f "$dmg" ] || fail "no DMG at $dmg"
[ -f "$notes" ] || fail "no release notes at $notes"
[ -x "$sign_update" ] || fail "no sign_update at $sign_update"

# Prints: sparkle:edSignature="..." length="..."
enclosure=$("$sign_update" --account "$account" "$dmg") ||
    fail "could not sign $dmg; is the update key in the login Keychain?"
case $enclosure in *'sparkle:edSignature="'*'length="'*) ;; *) fail "unexpected sign_update output: $enclosure" ;; esac
signature=$(printf '%s' "$enclosure" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
"$sign_update" --account "$account" --verify "$dmg" "$signature" >/dev/null 2>&1 ||
    fail "the DMG signature does not verify"

grep -q ']]>' "$notes" && fail "the release notes may not contain ]]>"
date=$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')
cat <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
<channel>
<title>OpenLaunchPad</title>
<link>https://github.com/LuckyFishOno/OpenLaunchPad</link>
<language>en</language>
<item>
<title>OpenLaunchPad $version (build $build)</title>
<pubDate>$date</pubDate>
<sparkle:version>$build</sparkle:version>
<sparkle:shortVersionString>$version</sparkle:shortVersionString>
<sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
<sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
<sparkle:fullReleaseNotesLink>https://github.com/LuckyFishOno/OpenLaunchPad/releases</sparkle:fullReleaseNotesLink>
<description><![CDATA[
$(cat "$notes")
]]></description>
<enclosure url="$url" type="application/x-apple-diskimage" $enclosure/>
</item>
</channel>
</rss>
XML
