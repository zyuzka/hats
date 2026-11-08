# The update feed Dev/package.sh publishes beside each disk image, and the changelog entry
# it carries. Sourced by package.sh, and by Dev/package-appcast.test.sh, which checks it
# against a made-up changelog without signing anything.

# The entry under "## <version>", up to the next "## " heading. The version is compared as a
# whole word: matched as a pattern, "0.4.1" also found "## 0.4.10", and its dots matched any
# character.
getChangelogEntry() {
    awk -v v="$1" '$1 == "##" && $2 == v { found = 1; next } found && /^## / { exit } found' "$2"
}

# Sparkle wants the minimum system as major.minor.patch, while the bundle says 13.0.
getThreePartVersion() {
    awk -F. '{ printf "%s.%s.%s\n", $1, ($2 == "" ? 0 : $2), ($3 == "" ? 0 : $3) }' <<< "$1"
}

# The update window shows the entry under "what's new". An empty one would show an empty
# window, and one containing ]]> would end the CDATA section it is embedded in.
checkReleaseEntry() {
    local version="$1" entry="$2"
    if [[ -z "${entry//[[:space:]]/}" ]]; then
        echo "the CHANGELOG.md entry for $version is empty, and the update window would show it empty." >&2
        return 1
    fi
    if [[ "$entry" == *"]]>"* ]]; then
        echo "the CHANGELOG.md entry for $version contains ]]>, which would end the CDATA section" >&2
        echo "it is embedded in." >&2
        return 1
    fi
}

# createAppcast <shown version> <bundle version> <minimum system> <image file name>
#               <EdDSA signature> <image length> <changelog entry> <publication date>
#
# sparkle:version is what Sparkle compares with the running copy's CFBundleVersion, so it is
# the bundle version, not the shown one. The image is downloaded from the release tagged
# v<shown version>, which is how the releases of this repository are tagged.
createAppcast() {
    local shown="$1" build="$2" minimum="$3" image="$4" signature="$5" length="$6" entry="$7" published="$8"
    checkReleaseEntry "$shown" "$entry" || return 1
    echo '<?xml version="1.0" encoding="utf-8"?>'
    echo '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
    echo '  <channel>'
    echo '    <title>Hats</title>'
    echo '    <link>https://github.com/zyuzka/hats</link>'
    echo '    <item>'
    echo "      <title>Hats $shown</title>"
    echo "      <pubDate>$published</pubDate>"
    echo "      <sparkle:version>$build</sparkle:version>"
    echo "      <sparkle:shortVersionString>$shown</sparkle:shortVersionString>"
    echo "      <sparkle:minimumSystemVersion>$minimum</sparkle:minimumSystemVersion>"
    echo '      <description sparkle:format="markdown"><![CDATA['
    printf '%s\n' "$entry"
    echo '      ]]></description>'
    echo "      <enclosure url=\"https://github.com/zyuzka/hats/releases/download/v$shown/$image\""
    echo "                 sparkle:edSignature=\"$signature\""
    echo "                 length=\"$length\""
    echo '                 type="application/octet-stream"/>'
    echo '    </item>'
    echo '  </channel>'
    echo '</rss>'
}
