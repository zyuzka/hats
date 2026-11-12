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
