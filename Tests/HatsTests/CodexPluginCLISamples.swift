import Foundation
@testable import Hats

enum CodexPluginCLISamples {
    static let origin = "codex-cli 0.170.0 from Homebrew, CODEX_HOME set to an empty temporary folder, 2026-11-19; "
        + "home and temporary paths replaced with /Users/someone"
    static let codex = "/opt/homebrew/bin/codex"
    static let codexHome = "/Users/someone/.codex"
    static let worktree = "/Users/someone/projects/hats"
    static let pluginFolder = "/Users/someone/projects/hats/codex-plugin"
    static let cache = "/Users/someone/.codex/plugins/cache/hats/hats/0.1.0"

    static let listEmpty = PluginCLISample(
        origin: origin,
        command: "codex plugin list --json",
        stdout: #"""
        {
          "installed": [],
          "available": []
        }
        """# + "\n",
        stderr: "",
        exitCode: 0
    )

    static let listFromFolder = PluginCLISample(
        origin: origin + "; after codex plugin marketplace add <worktree> and codex plugin add hats@hats",
        command: "codex plugin list --json",
        stdout: #"""
        {
          "installed": [
            {
              "pluginId": "hats@hats",
              "name": "hats",
              "marketplaceName": "hats",
              "version": "0.1.0",
              "installed": true,
              "enabled": true,
              "source": {
                "source": "local",
                "path": "/Users/someone/projects/hats/codex-plugin"
              },
              "marketplaceSource": {
                "sourceType": "local",
                "source": "/Users/someone/projects/hats"
              },
              "installPolicy": "AVAILABLE",
              "authPolicy": "ON_INSTALL"
            }
          ],
          "available": []
        }
        """# + "\n",
        stderr: "",
        exitCode: 0
    )

    static func listFromGitHub(version: String) -> PluginCLISample {
        PluginCLISample(
            origin: "constructed: the shape of the warp@codex-warp entry codex-cli 0.170.0 listed on 2026-11-19 for "
                + "a Git marketplace, with the names and the source of hats",
            command: "codex plugin list --json",
            stdout: """
            {
              "installed": [
                {
                  "pluginId": "hats@hats",
                  "name": "hats",
                  "marketplaceName": "hats",
                  "version": "\(version)",
                  "installed": true,
                  "enabled": true,
                  "source": {
                    "source": "local",
                    "path": "/Users/someone/.codex/.tmp/marketplaces/hats/codex-plugin"
                  },
                  "marketplaceSource": {
                    "sourceType": "git",
                    "source": "https://github.com/zyuzka/hats.git"
                  },
                  "installPolicy": "AVAILABLE",
                  "authPolicy": "ON_INSTALL"
                }
              ],
              "available": []
            }

            """,
            stderr: "",
            exitCode: 0
        )
    }

    static let marketsEmpty = PluginCLISample(
        origin: origin + "; after codex plugin marketplace remove",
        command: "codex plugin marketplace list --json",
        stdout: #"""
        {
          "marketplaces": []
        }
        """# + "\n",
        stderr: "",
        exitCode: 0
    )

    static let marketsFolder = PluginCLISample(
        origin: "the user's own CODEX_HOME, codex-cli 0.170.0, 2026-11-19; the entry of hats, paths replaced",
        command: "codex plugin marketplace list --json",
        stdout: #"""
        {
          "marketplaces": [
            {
              "name": "openai-curated",
              "root": "/Users/someone/.codex/.tmp/plugins"
            },
            {
              "name": "hats",
              "root": "/Users/someone/projects/hats",
              "marketplaceSource": {
                "sourceType": "local",
                "source": "/Users/someone/projects/hats"
              }
            }
          ]
        }
        """# + "\n",
        stderr: "",
        exitCode: 0
    )

    static func markets(name: String, sourceType: String, source: String) -> PluginCLISample {
        PluginCLISample(
            origin: "constructed: the shape codex-cli 0.170.0 printed on 2026-11-19 after codex plugin marketplace "
                + "add warpdotdev/codex-warp, which it listed as sourceType git and https://github.com/<repo>.git",
            command: "codex plugin marketplace list --json",
            stdout: """
            {
              "marketplaces": [
                {
                  "name": "\(name)",
                  "root": "/Users/someone/.codex/.tmp/marketplaces/\(name)",
                  "marketplaceSource": {
                    "sourceType": "\(sourceType)",
                    "source": "\(source)"
                  }
                }
              ]
            }

            """,
            stderr: "",
            exitCode: 0
        )
    }

    static let marketsGitHub = markets(name: "hats", sourceType: "git", source: "https://github.com/zyuzka/hats.git")

    static let marketAddDone = PluginCLISample(
        origin: origin,
        command: "codex plugin marketplace add <worktree> --json",
        stdout: #"""
        {
          "marketplaceName": "hats",
          "installedRoot": "/Users/someone/projects/hats",
          "alreadyAdded": false
        }
        """# + "\n",
        stderr: "",
        exitCode: 0
    )

    static let marketAddNoManifest = PluginCLISample(
        origin: origin + "; zyuzka/hats has no Codex marketplace on main yet",
        command: "codex plugin marketplace add zyuzka/hats --json",
        stdout: "",
        stderr: "Error: invalid marketplace file `/Users/someone/.codex/.tmp/marketplaces/.staging/"
            + "marketplace-macos-Y0u432/checkout`: marketplace root does not contain a supported manifest\n",
        exitCode: 1
    )

    static let addDone = PluginCLISample(
        origin: origin,
        command: "codex plugin add hats@hats --json",
        stdout: #"""
        {
          "pluginId": "hats@hats",
          "name": "hats",
          "marketplaceName": "hats",
          "version": "0.1.0",
          "installedPath": "/Users/someone/.codex/plugins/cache/hats/hats/0.1.0",
          "authPolicy": "ON_INSTALL"
        }
        """# + "\n",
        stderr: "",
        exitCode: 0
    )

    static let addNotFound = PluginCLISample(
        origin: origin + "; after codex plugin marketplace remove hats",
        command: "codex plugin add hats@hats --json",
        stdout: "",
        stderr: "Error: plugin `hats` was not found in marketplace `hats`\n",
        exitCode: 1
    )

    static let removeDone = PluginCLISample(
        origin: origin,
        command: "codex plugin remove hats@hats --json",
        stdout: #"""
        {
          "pluginId": "hats@hats",
          "name": "hats",
          "marketplaceName": "hats"
        }
        """# + "\n",
        stderr: "",
        exitCode: 0
    )

    static let upgradeDone = PluginCLISample(
        origin: origin + "; the marketplace codex-warp, name replaced with hats",
        command: "codex plugin marketplace upgrade hats --json",
        stdout: #"""
        {
          "selectedMarketplaces": [
            "hats"
          ],
          "upgradedRoots": [
            "/Users/someone/.codex/.tmp/marketplaces/hats"
          ],
          "errors": []
        }
        """# + "\n",
        stderr: "",
        exitCode: 0
    )

    static let upgradeNotGit = PluginCLISample(
        origin: origin + "; the marketplace hats added from a folder",
        command: "codex plugin marketplace upgrade hats --json",
        stdout: "",
        stderr: "Error: marketplace `hats` is not configured as a Git marketplace\n",
        exitCode: 1
    )
}
