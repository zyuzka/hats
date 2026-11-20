import Foundation
@testable import Hats

enum PluginCLISamples {
    static let version322 = PluginCLISample(
        origin: #"""
        Docker, image node:22.23.5-bookworm-slim, user node, claude 2.1.322 from npm, fresh settings, this repository read-only at /market, 2026-11-12, probe 1, run from /; Dev/plugin-cli-check.sh repeats it
        """#,
        command: #"""
        claude --version
        """#,
        stdout: #"""
        2.1.322 (Claude Code)
        """# + "\n",
        stderr: "",
        exitCode: 0
    )

    static let installHelp322 = PluginCLISample(
        origin: #"""
        Docker, image node:22.23.5-bookworm-slim, user node, claude 2.1.322 from npm, fresh settings, this repository read-only at /market, 2026-11-12, probe 1, run from /; Dev/plugin-cli-check.sh repeats it
        """#,
        command: #"""
        claude plugin install --help
        """#,
        stdout: #"""
        Usage: claude plugin install|i [options] <plugin>

        Install a plugin from available marketplaces (use plugin@marketplace for
        specific marketplace)

        Options:
          --accept-command <sha256>  Accept the marketplace-declared command (a
                                     command-source install, or the headersHelper that
                                     fetches the archive) whose sha256 a previous --json
                                     run reported as shownCommand.sha256; counts as -y
                                     for exactly that command, for that plugin and
                                     marketplace catalog, and nothing else. If either
                                     changed (a refresh that moved the catalog counts),
                                     the run refuses and reports the command again, to
                                     be shown to a person again
          --config <key=value>       Set a userConfig option declared in the plugin's
                                     manifest, or a bundled .mcpb server's own
                                     user_config field as <server>.<key>=<value> (a bare
                                     key works when only one bundled server declares
                                     it). Repeatable. Values are validated against the
                                     schema and stored via the same path as the
                                     interactive /plugin configure flow.
          -h, --help                 Display help for command
          --json                     Print one machine-readable result line on stdout
                                     instead of the human message (same exit codes; a
                                     marketplace-declared command is still shown and
                                     must be confirmed — pass -y when not interactive)
          --marketplace <source>     Install <plugin> (its bare name) from the
                                     marketplace at this source: owner/repo, a git or
                                     https URL, or a path. A marketplace not added yet
                                     is added first, in user settings, under the same
                                     checks as 'plugin marketplace add'
          --registry <url>           For a <package>@npm install: resolve and download
                                     from this npm registry instead of the one your npm
                                     configuration selects
          -s, --scope <scope>        Installation scope: user, project, or local
                                     (default: "user")
          -y, --yes                  Accept the displayed marketplace-declared command
                                     without the confirmation prompt — a plugin
                                     installed by running a command, or one whose
                                     archive is fetched through a headersHelper command
                                     (required when stdin or stdout is not a TTY)
        """# + "\n",
        stderr: "",
        exitCode: 0
    )

    static let listEmpty = PluginCLISample(
        origin: #"""
        Docker, image node:22.23.5-bookworm-slim, user node, claude 2.1.322 from npm, fresh settings, this repository read-only at /market, 2026-11-12, probe 1, run from /, before any install; Dev/plugin-cli-check.sh repeats it after the uninstall
        """#,
        command: #"""
        claude plugin list --json
        """#,
        stdout: #"""
        []
        """# + "\n",
        stderr: "",
        exitCode: 0
    )

    static let marketplacesEmpty = PluginCLISample(
        origin: #"""
        Docker, image node:22.23.5-bookworm-slim, user node, claude 2.1.322 from npm, fresh settings, this repository read-only at /market, 2026-11-12, probe 1, run from /, before any install
        """#,
        command: #"""
        claude plugin marketplace list --json
        """#,
        stdout: #"""
        []
        """# + "\n",
        stderr: "",
        exitCode: 0
    )

    static let installFromFolder = PluginCLISample(
        origin: #"""
        Docker, image node:22.23.5-bookworm-slim, user node, claude 2.1.322 from npm, fresh settings, this repository read-only at /market, 2026-11-12, probe 1, run from /; Dev/plugin-cli-check.sh repeats it
        """#,
        command: #"""
        claude plugin install hats --marketplace /market --scope user --json
        """#,
        stdout: #"""
        {"command":"install","outcome":"ok","plugin":"hats@hats","pluginId":"hats@hats","scope":"user","message":"Successfully installed plugin: hats@hats (scope: user)"}
        """# + "\n",
        stderr: "",
        exitCode: 0
    )

    static let listUserFromFolder = PluginCLISample(
        origin: #"""
        Docker, image node:22.23.5-bookworm-slim, user node, claude 2.1.322 from npm, fresh settings, this repository read-only at /market, 2026-11-12, probe 1, run from /, after the install; Dev/plugin-cli-check.sh repeats it
        """#,
        command: #"""
        claude plugin list --json
        """#,
        stdout: #"""
        [
          {
            "id": "hats@hats",
            "version": "0.1.0",
            "scope": "user",
            "enabled": true,
            "installPath": "/home/node/.claude/plugins/cache/hats/hats/0.1.0",
            "readFromFolder": "/market/plugin",
            "folderVersion": "0.1.0",
            "installedAt": "2026-11-12T18:21:16.714Z",
            "lastUpdated": "2026-11-12T18:21:16.714Z",
            "projectEnabled": false
          }
        ]
        """# + "\n",
        stderr: "",
        exitCode: 0
    )

    static let marketplacesFolder = PluginCLISample(
        origin: #"""
        Docker, image node:22.23.5-bookworm-slim, user node, claude 2.1.322 from npm, fresh settings, this repository read-only at /market, 2026-11-12, probe 1, run from /, after the install; Dev/plugin-cli-check.sh repeats it
        """#,
        command: #"""
        claude plugin marketplace list --json
        """#,
        stdout: #"""
        [
          {
            "name": "hats",
            "source": "directory",
            "path": "/market",
            "installLocation": "/market"
          }
        ]
        """# + "\n",
        stderr: "",
        exitCode: 0
    )

    static let installAlreadyThere = PluginCLISample(
        origin: #"""
        Docker, image node:22.23.5-bookworm-slim, user node, claude 2.1.322 from npm, fresh settings, this repository read-only at /market, 2026-11-12, probe 1, run from /, the same install a second time
        """#,
        command: #"""
        claude plugin install hats --marketplace /market --scope user --json
        """#,
        stdout: #"""
        {"command":"install","outcome":"ok","plugin":"hats@hats","pluginId":"hats@hats","scope":"user","message":"Plugin \"hats@hats\" is already installed (scope: user) — it loads in place from /market/plugin, so edits there take effect at the next session start or /reload-plugins","installedVersion":"0.1.0","availableVersion":"0.1.0"}
        """# + "\n",
        stderr: "",
        exitCode: 0
    )

    static let uninstallDone = PluginCLISample(
        origin: #"""
        Docker, image node:22.23.5-bookworm-slim, user node, claude 2.1.322 from npm, fresh settings, this repository read-only at /market, 2026-11-12, probe 1, run from /; Dev/plugin-cli-check.sh repeats it
        """#,
        command: #"""
        claude plugin uninstall hats@hats --scope user --keep-data --json
        """#,
        stdout: #"""
        {"command":"uninstall","outcome":"ok","plugin":"hats@hats","pluginId":"hats@hats","scope":"user","keptData":true,"message":"Successfully uninstalled plugin: hats (scope: user)"}
        """# + "\n",
        stderr: "",
        exitCode: 0
    )

    static let uninstallNotInstalled = PluginCLISample(
        origin: #"""
        Docker, image node:22.23.5-bookworm-slim, user node, claude 2.1.322 from npm, fresh settings, this repository read-only at /market, 2026-11-12, probe 1, run from /, the uninstall a second time
        """#,
        command: #"""
        claude plugin uninstall hats@hats --scope user --keep-data --json
        """#,
        stdout: #"""
        {"command":"uninstall","outcome":"failed","plugin":"hats@hats","scope":"user","message":"Plugin \"hats@hats\" not found in installed plugins","failureCode":"not_installed"}
        """# + "\n",
        stderr: #"""
        ✘ Failed to uninstall plugin "hats@hats": Plugin "hats@hats" not found in installed plugins
        """# + "\n",
        exitCode: 1
    )

    static let installManifestMissing = PluginCLISample(
        origin: #"""
        Docker, image node:22.23.5-bookworm-slim, user node, claude 2.1.322 from npm, fresh settings, this repository read-only at /market, 2026-11-12, probe 2 (git installed), run from /, after marketplace add /market; zyuzka/hats has no marketplace.json on its default branch yet
        """#,
        command: #"""
        claude plugin install hats --marketplace zyuzka/hats --scope user --json
        """#,
        stdout: #"""
        {"command":"install","outcome":"failed","plugin":"hats","scope":"user","message":"Marketplace file not found at /home/node/.claude/plugins/marketplaces/zyuzka-hats/.claude-plugin/marketplace.json","failureCode":"manifest_missing"}
        """# + "\n",
        stderr: #"""
        ✘ Failed to add marketplace: Marketplace file not found at /home/node/.claude/plugins/marketplaces/zyuzka-hats/.claude-plugin/marketplace.json
        """# + "\n",
        exitCode: 1
    )

    static let marketplacesGithubAndFolder = PluginCLISample(
        origin: #"""
        Docker, image node:22.23.5-bookworm-slim, user node, claude 2.1.322 from npm, fresh settings, this repository read-only at /market, 2026-11-12, probe 2 (git installed), run from /, after marketplace add anthropics/claude-plugins-official
        """#,
        command: #"""
        claude plugin marketplace list --json
        """#,
        stdout: #"""
        [
          {
            "name": "claude-plugins-official",
            "source": "github",
            "repo": "anthropics/claude-plugins-official",
            "installLocation": "/home/node/.claude/plugins/marketplaces/claude-plugins-official"
          },
          {
            "name": "hats",
            "source": "directory",
            "path": "/market",
            "installLocation": "/market"
          }
        ]
        """# + "\n",
        stderr: "",
        exitCode: 0
    )

    static let listProjectScope = PluginCLISample(
        origin: #"""
        Docker, image node:22.23.5-bookworm-slim, user node, claude 2.1.322 from npm, fresh settings, this repository read-only at /market, 2026-11-12, probe 2 (git installed), run from /tmp/proj, a git repository, after install hats@hats --scope project
        """#,
        command: #"""
        claude plugin list --json
        """#,
        stdout: #"""
        [
          {
            "id": "hats@hats",
            "version": "0.1.0",
            "scope": "project",
            "enabled": true,
            "installPath": "/home/node/.claude/plugins/cache/hats/hats/0.1.0",
            "readFromFolder": "/market/plugin",
            "folderVersion": "0.1.0",
            "installedAt": "2026-11-12T18:22:11.099Z",
            "lastUpdated": "2026-11-12T18:22:11.099Z",
            "projectPath": "/tmp/proj",
            "projectEnabled": true
          }
        ]
        """# + "\n",
        stderr: "",
        exitCode: 0
    )

    static let uninstallEnabledAtProjectScope = PluginCLISample(
        origin: #"""
        Docker, image node:22.23.5-bookworm-slim, user node, claude 2.1.322 from npm, fresh settings, this repository read-only at /market, 2026-11-12, probe 2 (git installed), run from /tmp/proj, with hats@hats only at project scope
        """#,
        command: #"""
        claude plugin uninstall hats@hats --scope user --keep-data --json
        """#,
        stdout: #"""
        {"command":"uninstall","outcome":"failed","plugin":"hats@hats","scope":"user","message":"Plugin \"hats@hats\" is enabled at project scope (.claude/settings.json, shared with your team). To disable just for you: claude plugin disable hats@hats --scope local","failureCode":"enabled_at_project_scope","installedScope":"project"}
        """# + "\n",
        stderr: #"""
        ✘ Failed to uninstall plugin "hats@hats": Plugin "hats@hats" is enabled at project scope (.claude/settings.json, shared with your team). To disable just for you: claude plugin disable hats@hats --scope local
        """# + "\n",
        exitCode: 1
    )

    static let installSettingsBroken = PluginCLISample(
        origin: #"""
        Docker, image node:22.23.5-bookworm-slim, user node, claude 2.1.322 from npm, fresh settings, this repository read-only at /market, 2026-11-12, probe 2 (git installed), run from /, with settings.json replaced by the text { broken
        """#,
        command: #"""
        claude plugin install hats --marketplace /market --scope user --json
        """#,
        stdout: #"""
        {"command":"install","outcome":"failed","plugin":"hats@hats","scope":"user","message":"Failed to update settings: Invalid JSON syntax in settings file at /home/node/.claude/settings.json","failureCode":"settings_write_failed"}
        """# + "\n",
        stderr: #"""
        ✘ Failed to install plugin "hats@hats": Failed to update settings: Invalid JSON syntax in settings file at /home/node/.claude/settings.json
        """# + "\n",
        exitCode: 1
    )

    static let listGithubPluginAndFolder = PluginCLISample(
        origin: #"""
        Docker, image node:22.23.5-bookworm-slim, user node, claude 2.1.322 from npm, fresh settings, this repository read-only at /market, 2026-11-12, probe 3 (git installed), run from /, after installing the first plugin of claude-plugins-official
        """#,
        command: #"""
        claude plugin list --json
        """#,
        stdout: #"""
        [
          {
            "id": "42crunch-api-security-testing@claude-plugins-official",
            "version": "1.5.5",
            "scope": "user",
            "enabled": true,
            "installPath": "/home/node/.claude/plugins/cache/claude-plugins-official/42crunch-api-security-testing/1.5.5",
            "installedAt": "2026-11-12T18:23:17.137Z",
            "lastUpdated": "2026-11-12T18:23:17.137Z",
            "projectEnabled": false
          },
          {
            "id": "hats@hats",
            "version": "0.1.0",
            "scope": "user",
            "enabled": true,
            "installPath": "/home/node/.claude/plugins/cache/hats/hats/0.1.0",
            "readFromFolder": "/market/plugin",
            "folderVersion": "0.1.0",
            "installedAt": "2026-11-12T18:23:09.437Z",
            "lastUpdated": "2026-11-12T18:23:09.437Z",
            "projectEnabled": false
          }
        ]
        """# + "\n",
        stderr: "",
        exitCode: 0
    )

    static let version153 = PluginCLISample(
        origin: #"""
        Docker, image node:22.23.5-bookworm-slim, user node, claude 2.1.322 from npm, fresh settings, this repository read-only at /market, 2026-11-12, probe 3 (git installed), run from /, claude 2.1.153 from npm in /tmp/old
        """#,
        command: #"""
        /tmp/old/node_modules/.bin/claude --version
        """#,
        stdout: #"""
        2.1.153 (Claude Code)
        """# + "\n",
        stderr: "",
        exitCode: 0
    )

    static let installHelp153 = PluginCLISample(
        origin: #"""
        Docker, image node:22.23.5-bookworm-slim, user node, claude 2.1.322 from npm, fresh settings, this repository read-only at /market, 2026-11-12, probe 3 (git installed), run from /, claude 2.1.153 from npm in /tmp/old
        """#,
        command: #"""
        /tmp/old/node_modules/.bin/claude plugin install --help
        """#,
        stdout: #"""
        Usage: claude plugin install|i [options] <plugin>

        Install a plugin from available marketplaces (use plugin@marketplace for
        specific marketplace)

        Options:
          --config <key=value>  Set a userConfig option declared in the plugin's
                                manifest (repeatable). Values are validated against the
                                schema and stored via the same path as the interactive
                                /plugin configure flow.
          -h, --help            Display help for command
          -s, --scope <scope>   Installation scope: user, project, or local (default:
                                "user")
        """# + "\n",
        stderr: "",
        exitCode: 0
    )

    static let marketplacesHatsFromGitHub = PluginCLISample(
        origin: #"""
        Composed, not recorded: written by the form of the claude-plugins-official entry recorded in probe 2 and 3, because hats cannot be installed from zyuzka/hats before the release; record it again after the release
        """#,
        command: #"""
        claude plugin marketplace list --json
        """#,
        stdout: #"""
        [
          {
            "name": "hats",
            "source": "github",
            "repo": "zyuzka/hats",
            "installLocation": "/home/node/.claude/plugins/marketplaces/zyuzka-hats"
          }
        ]
        """# + "\n",
        stderr: "",
        exitCode: 0
    )

    static let listUserFromGitHub = PluginCLISample(
        origin: #"""
        Composed, not recorded: written by the form of the claude-plugins-official entry recorded in probe 2 and 3, because hats cannot be installed from zyuzka/hats before the release; record it again after the release
        """#,
        command: #"""
        claude plugin list --json
        """#,
        stdout: #"""
        [
          {
            "id": "hats@hats",
            "version": "0.1.0",
            "scope": "user",
            "enabled": true,
            "installPath": "/home/node/.claude/plugins/cache/hats/hats/0.1.0",
            "installedAt": "2026-11-12T18:23:09.437Z",
            "lastUpdated": "2026-11-12T18:23:09.437Z",
            "projectEnabled": false
          }
        ]
        """# + "\n",
        stderr: "",
        exitCode: 0
    )

    static let marketplacesThroughGitHub = PluginCLISample(
        origin: #"""
        Docker, image node:22.23.5-bookworm-slim, user node, claude 2.1.322 from npm, git from root, a copy of this repository's marketplace committed as 0.1.0 (later 0.2.0) into a bare repository that stands in for https://github.com/zyuzka/hats.git through git insteadOf, 2026-11-12, run 3; CLAUDE_CONFIG_DIR=/home/node/cfg-a, run from /, after install hats --marketplace zyuzka/hats; Dev/plugin-cli-check.sh repeats it
        """#,
        command: #"""
        claude plugin marketplace list --json
        """#,
        stdout: #"""
        [
          {
            "name": "hats",
            "source": "github",
            "repo": "zyuzka/hats",
            "installLocation": "/home/node/cfg-a/plugins/marketplaces/hats"
          }
        ]
        """# + "\n",
        stderr: "",
        exitCode: 0
    )

    static let listUserThroughGitHub010 = PluginCLISample(
        origin: #"""
        Docker, image node:22.23.5-bookworm-slim, user node, claude 2.1.322 from npm, git from root, a copy of this repository's marketplace committed as 0.1.0 (later 0.2.0) into a bare repository that stands in for https://github.com/zyuzka/hats.git through git insteadOf, 2026-11-12, run 3; CLAUDE_CONFIG_DIR=/home/node/cfg-a, run from /, after install hats --marketplace zyuzka/hats; Dev/plugin-cli-check.sh repeats it
        """#,
        command: #"""
        claude plugin list --json
        """#,
        stdout: #"""
        [
          {
            "id": "hats@hats",
            "version": "0.1.0",
            "scope": "user",
            "enabled": true,
            "installPath": "/home/node/cfg-a/plugins/cache/hats/hats/0.1.0",
            "installedAt": "2026-11-12T22:51:07.115Z",
            "lastUpdated": "2026-11-12T22:51:07.115Z",
            "projectEnabled": false
          }
        ]
        """# + "\n",
        stderr: "",
        exitCode: 0
    )

    static let listUserAndProjectThroughGitHub010 = PluginCLISample(
        origin: #"""
        Docker, image node:22.23.5-bookworm-slim, user node, claude 2.1.322 from npm, git from root, a copy of this repository's marketplace committed as 0.1.0 (later 0.2.0) into a bare repository that stands in for https://github.com/zyuzka/hats.git through git insteadOf, 2026-11-12, run 3; CLAUDE_CONFIG_DIR=/home/node/cfg-b, run from /, after install hats@hats --scope project from /tmp/proj; Dev/plugin-cli-check.sh repeats it
        """#,
        command: #"""
        claude plugin list --json
        """#,
        stdout: #"""
        [
          {
            "id": "hats@hats",
            "version": "0.1.0",
            "scope": "user",
            "enabled": true,
            "installPath": "/home/node/cfg-b/plugins/cache/hats/hats/0.1.0",
            "installedAt": "2026-11-12T22:51:08.086Z",
            "lastUpdated": "2026-11-12T22:51:08.086Z",
            "projectEnabled": false
          },
          {
            "id": "hats@hats",
            "version": "0.1.0",
            "scope": "project",
            "enabled": true,
            "installPath": "/home/node/cfg-b/plugins/cache/hats/hats/0.1.0",
            "installedAt": "2026-11-12T22:51:11.878Z",
            "lastUpdated": "2026-11-12T22:51:11.878Z",
            "projectPath": "/tmp/proj",
            "projectEnabled": false
          }
        ]
        """# + "\n",
        stderr: "",
        exitCode: 0
    )

    static let listOffThroughGitHub010 = PluginCLISample(
        origin: #"""
        Docker, image node:22.23.5-bookworm-slim, user node, claude 2.1.322 from npm, git from root, a copy of this repository's marketplace committed as 0.1.0 (later 0.2.0) into a bare repository that stands in for https://github.com/zyuzka/hats.git through git insteadOf, 2026-11-12, run 3; CLAUDE_CONFIG_DIR=/home/node/cfg-c, run from /, after disable hats@hats --scope user; Dev/plugin-cli-check.sh repeats it
        """#,
        command: #"""
        claude plugin list --json
        """#,
        stdout: #"""
        [
          {
            "id": "hats@hats",
            "version": "0.1.0",
            "scope": "user",
            "enabled": false,
            "installPath": "/home/node/cfg-c/plugins/cache/hats/hats/0.1.0",
            "installedAt": "2026-11-12T22:51:09.183Z",
            "lastUpdated": "2026-11-12T22:51:09.183Z",
            "projectEnabled": false
          }
        ]
        """# + "\n",
        stderr: "",
        exitCode: 0
    )

    static let updateHelp322 = PluginCLISample(
        origin: #"""
        Docker, image node:22.23.5-bookworm-slim, user node, claude 2.1.322 from npm, git from root, a copy of this repository's marketplace committed as 0.1.0 (later 0.2.0) into a bare repository that stands in for https://github.com/zyuzka/hats.git through git insteadOf, 2026-11-12, run 3; CLAUDE_CONFIG_DIR=/home/node/cfg-a, run from /; Dev/plugin-cli-check.sh repeats it
        """#,
        command: #"""
        claude plugin update --help
        """#,
        stdout: #"""
        Usage: claude plugin update [options] <plugin>

        Update a plugin to the latest version (restart required to apply)

        Options:
          --accept-command <sha256>  Accept the marketplace-declared command (a
                                     command-source install, or the headersHelper that
                                     fetches the archive) whose sha256 a previous --json
                                     run reported as shownCommand.sha256; counts as -y
                                     for exactly that command, for that plugin and
                                     marketplace catalog, and nothing else. If either
                                     changed (a refresh that moved the catalog counts),
                                     the run refuses and reports the command again, to
                                     be shown to a person again
          -h, --help                 Display help for command
          --json                     Print one machine-readable result line on stdout
                                     instead of the human message (same exit codes; a
                                     marketplace-declared command is still shown and
                                     must be confirmed — pass -y when not interactive)
          -s, --scope <scope>        Installation scope: user, project, local, managed
                                     (default: auto-detect)
          -y, --yes                  Accept the displayed marketplace-declared command
                                     without the confirmation prompt — a changed install
                                     command, or the headersHelper command that fetches
                                     its archive (required when stdin or stdout is not a
                                     TTY)
        """# + "\n",
        stderr: "",
        exitCode: 0
    )

    static let marketplaceUpdateHelp322 = PluginCLISample(
        origin: #"""
        Docker, image node:22.23.5-bookworm-slim, user node, claude 2.1.322 from npm, git from root, a copy of this repository's marketplace committed as 0.1.0 (later 0.2.0) into a bare repository that stands in for https://github.com/zyuzka/hats.git through git insteadOf, 2026-11-12, run 3; CLAUDE_CONFIG_DIR=/home/node/cfg-a, run from /; Dev/plugin-cli-check.sh repeats it
        """#,
        command: #"""
        claude plugin marketplace update --help
        """#,
        stdout: #"""
        Usage: claude plugin marketplace update [options] [name]

        Update marketplace(s) from their source - updates all if no name specified

        Options:
          -h, --help  Display help for command
          --json      With a marketplace name: print one machine-readable result line as
                      the last line on stdout (same exit codes)
        """# + "\n",
        stderr: "",
        exitCode: 0
    )

    static let updateUpToDate010 = PluginCLISample(
        origin: #"""
        Docker, image node:22.23.5-bookworm-slim, user node, claude 2.1.322 from npm, git from root, a copy of this repository's marketplace committed as 0.1.0 (later 0.2.0) into a bare repository that stands in for https://github.com/zyuzka/hats.git through git insteadOf, 2026-11-12, run 3; CLAUDE_CONFIG_DIR=/home/node/cfg-a, run from /, after 0.2.0 was pushed, without marketplace update first: the catalog was seconds old and was not refreshed; Dev/plugin-cli-check.sh repeats it
        """#,
        command: #"""
        claude plugin update hats@hats --scope user --json
        """#,
        stdout: #"""
        {"command":"update","outcome":"ok","plugin":"hats@hats","pluginId":"hats@hats","scope":"user","message":"hats is already at the latest version (0.1.0).","updateOutcome":"up_to_date","oldVersion":"0.1.0","newVersion":"0.1.0"}
        """# + "\n",
        stderr: "",
        exitCode: 0
    )

    static let marketplaceUpdateDone = PluginCLISample(
        origin: #"""
        Docker, image node:22.23.5-bookworm-slim, user node, claude 2.1.322 from npm, git from root, a copy of this repository's marketplace committed as 0.1.0 (later 0.2.0) into a bare repository that stands in for https://github.com/zyuzka/hats.git through git insteadOf, 2026-11-12, run 3; CLAUDE_CONFIG_DIR=/home/node/cfg-b, run from /, after 0.2.0 was pushed; Dev/plugin-cli-check.sh repeats it
        """#,
        command: #"""
        claude plugin marketplace update hats --json
        """#,
        stdout: #"""
        {"command":"marketplace-update","outcome":"ok","marketplace":"hats","message":"Refreshing marketplace cache (timeout: 120s)…\nCloning repository (timeout: 120s): https://github.com/zyuzka/hats.git\nReplacing the existing marketplace clone…\nClone complete, validating marketplace…\nSuccessfully updated marketplace: hats"}
        """# + "\n",
        stderr: "",
        exitCode: 0
    )

    static let updateDone010To020 = PluginCLISample(
        origin: #"""
        Docker, image node:22.23.5-bookworm-slim, user node, claude 2.1.322 from npm, git from root, a copy of this repository's marketplace committed as 0.1.0 (later 0.2.0) into a bare repository that stands in for https://github.com/zyuzka/hats.git through git insteadOf, 2026-11-12, run 3; CLAUDE_CONFIG_DIR=/home/node/cfg-b, run from /, right after marketplace update hats; Dev/plugin-cli-check.sh repeats it
        """#,
        command: #"""
        claude plugin update hats@hats --scope user --json
        """#,
        stdout: #"""
        {"command":"update","outcome":"ok","plugin":"hats@hats","pluginId":"hats@hats","scope":"user","message":"Plugin \"hats\" updated from 0.1.0 to 0.2.0 for scope user. Restart to apply changes.","updateOutcome":"updated","oldVersion":"0.1.0","newVersion":"0.2.0"}
        """# + "\n",
        stderr: "",
        exitCode: 0
    )

    static let listUserAndProjectThroughGitHub020 = PluginCLISample(
        origin: #"""
        Docker, image node:22.23.5-bookworm-slim, user node, claude 2.1.322 from npm, git from root, a copy of this repository's marketplace committed as 0.1.0 (later 0.2.0) into a bare repository that stands in for https://github.com/zyuzka/hats.git through git insteadOf, 2026-11-12, run 3; CLAUDE_CONFIG_DIR=/home/node/cfg-b, run from /, after the update of the user installation; Dev/plugin-cli-check.sh repeats it
        """#,
        command: #"""
        claude plugin list --json
        """#,
        stdout: #"""
        [
          {
            "id": "hats@hats",
            "version": "0.2.0",
            "scope": "user",
            "enabled": true,
            "installPath": "/home/node/cfg-b/plugins/cache/hats/hats/0.2.0",
            "installedAt": "2026-11-12T22:51:08.086Z",
            "lastUpdated": "2026-11-12T22:51:15.833Z",
            "projectEnabled": false
          },
          {
            "id": "hats@hats",
            "version": "0.1.0",
            "scope": "project",
            "enabled": true,
            "installPath": "/home/node/cfg-b/plugins/cache/hats/hats/0.1.0",
            "installedAt": "2026-11-12T22:51:11.878Z",
            "lastUpdated": "2026-11-12T22:51:11.878Z",
            "projectPath": "/tmp/proj",
            "projectEnabled": false
          }
        ]
        """# + "\n",
        stderr: "",
        exitCode: 0
    )

    static let listOffThroughGitHub020 = PluginCLISample(
        origin: #"""
        Docker, image node:22.23.5-bookworm-slim, user node, claude 2.1.322 from npm, git from root, a copy of this repository's marketplace committed as 0.1.0 (later 0.2.0) into a bare repository that stands in for https://github.com/zyuzka/hats.git through git insteadOf, 2026-11-12, run 3; CLAUDE_CONFIG_DIR=/home/node/cfg-c, run from /, after marketplace update and update of the switched-off plugin; Dev/plugin-cli-check.sh repeats it
        """#,
        command: #"""
        claude plugin list --json
        """#,
        stdout: #"""
        [
          {
            "id": "hats@hats",
            "version": "0.2.0",
            "scope": "user",
            "enabled": false,
            "installPath": "/home/node/cfg-c/plugins/cache/hats/hats/0.2.0",
            "installedAt": "2026-11-12T22:51:09.183Z",
            "lastUpdated": "2026-11-12T22:51:18.873Z",
            "projectEnabled": false
          }
        ]
        """# + "\n",
        stderr: "",
        exitCode: 0
    )

    static let marketplaceUpdateRepositoryGone = PluginCLISample(
        origin: #"""
        Docker, image node:22.23.5-bookworm-slim, user node, claude 2.1.322 from npm, git from root, a copy of this repository's marketplace committed as 0.1.0 (later 0.2.0) into a bare repository that stands in for https://github.com/zyuzka/hats.git through git insteadOf, 2026-11-12, run 3; CLAUDE_CONFIG_DIR=/home/node/cfg-d, run from /, with the bare repository moved away; Dev/plugin-cli-check.sh repeats it
        """#,
        command: #"""
        claude plugin marketplace update hats --json
        """#,
        stdout: #"""
        {"command":"marketplace-update","marketplace":"hats","outcome":"failed","message":"Failed to refresh marketplace 'hats': Fetching the marketplace from GitHub failed on both attempts. HTTPS (https://github.com/zyuzka/hats.git): Failed to clone marketplace repository: SSH authentication failed. Please ensure your SSH keys are configured for GitHub, or use an HTTPS URL instead.\n\nOriginal error: Cloning into '/home/node/cfg-d/plugins/marketplaces/hats..clone'...\nfatal: '/tmp/hats.git' does not appear to be a git repository\nfatal: Could not read from remote repository.\n\nPlease make sure you have the correct access rights\nand the repository exists.\n\nSSH (git@github.com:zyuzka/hats.git): Failed to clone marketplace repository: SSH host key is not in your known_hosts file. To add it, connect once manually (this will show the fingerprint for you to verify):\n  ssh -T git@github.com\n\nOr use an HTTPS URL instead (recommended for public repos).\n\nOriginal error: Cloning into '/home/node/cfg-d/plugins/marketplaces/hats..clone'...\nNo ED25519 host key is known for github.com and you have requested strict checking. \nHost key verification failed. \nfatal: Could not read from remote repository.\n\nPlease make sure you have the correct access rights\nand the repository exists.","failureCode":"error_unknown"}
        """# + "\n",
        stderr: #"""
        ✘ Failed to update marketplace(s): Failed to refresh marketplace 'hats': Fetching the marketplace from GitHub failed on both attempts. HTTPS (https://github.com/zyuzka/hats.git): Failed to clone marketplace repository: SSH authentication failed. Please ensure your SSH keys are configured for GitHub, or use an HTTPS URL instead.

        Original error: Cloning into '/home/node/cfg-d/plugins/marketplaces/hats..clone'...
        fatal: '/tmp/hats.git' does not appear to be a git repository
        fatal: Could not read from remote repository.

        Please make sure you have the correct access rights
        and the repository exists.

        SSH (git@github.com:zyuzka/hats.git): Failed to clone marketplace repository: SSH host key is not in your known_hosts file. To add it, connect once manually (this will show the fingerprint for you to verify):
          ssh -T git@github.com

        Or use an HTTPS URL instead (recommended for public repos).

        Original error: Cloning into '/home/node/cfg-d/plugins/marketplaces/hats..clone'...
        No ED25519 host key is known for github.com and you have requested strict checking. 
        Host key verification failed. 
        fatal: Could not read from remote repository.

        Please make sure you have the correct access rights
        and the repository exists.
        """# + "\n",
        exitCode: 1
    )

    static let updateRefreshFailed = PluginCLISample(
        origin: #"""
        Docker, the same setup as run 3 by hand before Dev/plugin-cli-check.sh took it over, 2026-11-12; CLAUDE_CONFIG_DIR=/home/node/cfg-d, run from /, the bare repository moved away, the catalog about 45 seconds old; the script does not repeat it: there the catalog is seconds old and plugin update skips the refresh
        """#,
        command: #"""
        claude plugin update hats@hats --scope user --json
        """#,
        stdout: #"""
        {"command":"update","outcome":"ok","plugin":"hats@hats","pluginId":"hats@hats","scope":"user","message":"hats is already at the latest version (0.1.0). Warning: marketplace not refreshed (Failed to refresh marketplace 'hats': Failed to clone marketplace repository: SSH authentication failed. Please ensure your SSH keys are configured for GitHub, or use an HTTPS URL instead.) — version shown may be stale.","updateOutcome":"up_to_date","oldVersion":"0.1.0","newVersion":"0.1.0","refreshFailed":true}
        """# + "\n",
        stderr: "",
        exitCode: 0
    )
}

struct PluginCLISample {
    let origin: String
    let command: String
    let stdout: String
    let stderr: String
    let exitCode: Int32

    var outcome: PluginCommandOutcome {
        PluginCommandOutcome(
            end: .exited(exitCode),
            stdout: Data(stdout.utf8),
            stderr: Data(stderr.utf8)
        )
    }
}
