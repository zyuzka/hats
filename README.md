<h1 align="center">
  <img src="docs/mark.svg" width="72" alt=""><br>
  Hats
</h1>

<p align="center">
  Put on the account Claude Code uses.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13%2B-0969da" alt="macOS 13+">
  <img src="https://img.shields.io/badge/version-0.4.1-1a7f37" alt="version 0.4.1">
  <img src="https://img.shields.io/badge/license-MIT-59636e" alt="MIT">
</p>

A macOS menu-bar app for developers holding more than one Claude subscription. It switches the
logged-in Claude Code account without a relogin, so work continues when one account runs out of
limits. Each account is a hat; you put one on.

The app was called `acc-switch` before it was published anywhere. The code carried that name for a
while longer; it no longer does — the Swift module is `Hats` and the bundle identifier `dev.tmk.hats`.

Not affiliated with Anthropic.

## What it asks for

- **Keychain access**, once, to read the credential slot Claude Code uses.
- **Permission to show notifications**, when it first starts — for a new release and for switching by
  itself. Refusing turns off only the notifications.
- It writes a marked block into your login shell's profile while the gateway serves, and takes it
  back out when it quits. The first write keeps a backup of the profile beside it.
- **Whether to restart for an update**, when you press Install and Relaunch and a Claude Code session
  is running through the gateway. The restart cuts off a request going through it at that moment.

## What it does not do

- **Its network traffic is to Anthropic, and to GitHub for updates.** The relay forwards your own
  Claude Code requests, and each hat's usage is read from Anthropic's usage endpoint with that hat's
  own token. About every six hours Hats reads the release feed of this repository on GitHub (with
  the automatic look turned off, only when you press Check for Updates…; see [Updating](#updating)),
  and it downloads a release only after you press Install. Nothing goes anywhere else.
- **It cannot sign you out.** Removing a hat forgets its stored copy; the account that is currently
  live keeps working.

## Install

Download the `.dmg` from [Releases](../../releases), open it and drag Hats to Applications.

Or with Homebrew: `brew install zyuzka/tap/hats`.

A Mac with Apple silicon and macOS 13 or later, and Claude Code already installed and logged in.

Hats is signed with an Apple Developer ID and notarized by Apple, so it opens on the first launch.

### Build it yourself

```sh
./Build/setup-signing.sh   # once per machine: create the signing certificate
./Build/build-app.sh       # build Hats.app
```

Run them from the repository root; each finds it on its own, so the working directory does not
matter. `build-app.sh` refuses to stop a running app while a Claude Code session is reaching Claude
through its gateway — `HATS_BUILD_MAY_STOP_SESSIONS=1` overrides that.

If your keychain holds an Apple Developer ID, the build signs with it instead, which needs the
network for Apple's timestamp; `HATS_SIGNING_IDENTITY="Hats Dev"` picks the self-signed one.

Needs a Swift 5.9 toolchain. Build output is git-ignored.

### Updating

From 0.4.0 on, Hats updates itself. It looks for a new release about every six hours, and Settings →
General has **Check for Updates…**. When there is one, a window shows what changed, and a notification
says so if Hats found it on its own. **Install Update** downloads the release and checks that it is
signed with the same key as the copy you run. A second window then says it is ready to install, and
**Install and Relaunch** there installs it and opens the new version.

From 0.4.1, Settings → General also has **Check for updates automatically**. Turned off, Hats looks
for a new release only when you press **Check for Updates…**, so no notification about one comes
either.

Installing restarts Hats, and the restart stops the gateway for a moment. If a Claude Code session is
running through the gateway, or Hats cannot read a session's settings to tell, it asks after Install
and Relaunch: a request going through the gateway at that moment is cut off. **Later** leaves the
update waiting, and it installs the next time Hats quits.

**From 0.3.x or earlier, update by hand one last time** — those versions cannot install an update themselves.
Quit Hats first — the power button at the foot of the popover, or `Cmd-Q` while it is open. It asks
before quitting if any Claude Code session is running, and says how many: quitting stops the relay,
so such a session stops working until Hats is back or its shell is cleared.

Then **delete `/Applications/Hats.app` before moving the new one in.** Copying over it in place can
leave macOS serving a stale record of where the bundle lives, and the app then refuses to launch.

Your hats and their stored logins live in `~/Library/Application Support/Hats` and the keychain, not
inside the app, so they survive an update untouched.

## Use it

Click the hat in the menu bar and pick one from the list — that account is the one `claude` signs in
with from then on. A hat is a named account: the name is what you read, the email address is the
detail underneath.

## The one thing to know before using it

A switch takes effect immediately for **new** sessions. A session already running follows only if it
was started through the app's gateway.

The gateway listens on `127.0.0.1:8787` by default, changeable in the gateway panel. The app writes
a block into the login shell's profile, between the markers `# >>> hats gateway >>>` and
`# <<< hats gateway <<<`, which asks the gateway whether it is there and exports three
variables only if it answers. A session started from a shell opened after that goes through the
gateway and moves to the new account at its first request after a 35-second settle — about 45
seconds after the switch in practice. The settle is adjustable in the gateway panel.

A session started without those variables keeps the hat it started on until its next token renewal —
a 401 or a token expiry, which is hours away, not a restart away. Restarting it is sufficient, not
necessary.

The other side of the same coin: a shell opened *before* the app started — a terminal restoring its
tabs at login, before the login item has run — has no gateway variables, and sessions started in it
do not follow a switch. Open a new shell once the app is up.

## Switching by itself

Off by default. Turn it on and the app puts the next hat on when the worn one crosses its limit —
90% of its 5-hour window or 95% of its weekly one, both adjustable in the panel. A hat comes off only
when its own limit is reached. The one put on is the first in the order you set that has room; if
none has room, the first whose usage could not be read. When every hat is spent the app says so in
its log rather than holding in silence.

<details>
<summary><strong>Troubleshooting:</strong> <code>claude</code> reports a connection error, and <code>echo $ANTHROPIC_BASE_URL</code> prints <code>http://127.0.0.1:8787</code></summary>

That shell is holding gateway variables from a time when the gateway was up, and nobody is listening
on that port now. Confirm with `curl -s http://127.0.0.1:8787/__gateway__/status` — a refused
connection means no gateway.

It can only happen to a shell that was **already open**. The block in the profile asks the gateway
first and exports nothing when it gets no answer, so a shell opened while the app is off runs Claude
directly. A shell that was open when the app quit or was killed keeps the variables in its own
environment, and a `claude` started there afterwards meets the dead port.

One of:

- open a new shell;
- start the app again — new sessions in that shell go through it again (whether a session that was
  already open recovers on its own has not been measured);
- in that shell, `unset ANTHROPIC_BASE_URL _CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL
  CLAUDE_GATEWAY_ALLOW_LOOPBACK` and start `claude` again — that session runs direct and does not
  follow a switch.

If the app is gone for good the block is already inert, since it exports nothing without an answer.
The app also takes it back out of the profile whenever it quits cleanly — the power button at the
foot of the popover, `Cmd-Q`, `kill <pid>`, `pkill -x Hats` — but not after a `kill -9` or a crash. A logout or a restart is not
on that list on purpose: it arrives through `applicationShouldTerminate`, which the app does not
implement, and macOS may kill it regardless. To remove it by hand, delete everything between the two
markers in whichever profile your login shell reads: `~/.zshrc` (or `$ZDOTDIR/.zshrc`), one of
`~/.bash_profile`, `~/.bash_login`, `~/.profile`, `~/.config/fish/config.fish`, or `~/.tcshrc` /
`~/.cshrc`. The profile as it was before the first write is beside it, in
`<profile>.bak-hats`.

</details>

## Supported CLIs

| Tool | Status |
| --- | --- |
| Claude Code | supported |

## Where things live

| What | Where |
| --- | --- |
| Hats, settings, operations log | `~/Library/Application Support/Hats/` |
| Stored logins | macOS Keychain, one item per hat |
| Updater state: last check, a skipped version, whether to check automatically | macOS defaults, domain `dev.tmk.hats`, shared by every build with that bundle id |

Credentials are never written to the state directory. Earlier versions kept state under
`~/.claude/state`, which is Claude Code's own directory and not a place for another program's files;
both older locations are adopted on first run, newest first, and an emptied one is removed. Parked
logins are re-filed in the keychain and the block in the shell profile is rewritten at the same
time.

## If something goes wrong

Every credential operation is logged, with fingerprints rather than tokens, in
`~/Library/Application Support/Hats/operations.log`. Send that along with the version, which is at
the foot of the General tab in Settings.

**`claude` reports a connection error, and `echo $ANTHROPIC_BASE_URL` prints a `127.0.0.1` address.**
That shell read the gateway variables while the app was serving, and nobody is on the port now — the
app was force-killed, crashed or deleted, since a normal quit cleans up after itself. Either start
Hats again, or in that shell:

```sh
unset ANTHROPIC_BASE_URL _CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL CLAUDE_GATEWAY_ALLOW_LOOPBACK
```

Only a shell opened *while* the relay was serving reaches that state; one opened after it stopped
sets nothing, because the block asks the relay first. So a leftover block is inert. To remove it by
hand, see [Switching by itself](#switching-by-itself) above, which names the markers and the profiles.

**You replaced the app in place and it will not launch.** That is the stale bundle record described
under [Updating](#updating), for an update by hand. Deleting `/Applications/Hats.app` and moving the
new one in is the cure; if the new app is already sitting there, this re-registers it where it is:

```sh
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Hats.app
```

## Tests and checks

```sh
HATS_STATE_HOME=$(mktemp -d) swift test
```

The variable is not optional if the app is installed on the same machine: the suite reaches the real
state directory otherwise, mixing test events into the log you would later read for diagnosis and
performing the first-run adoption ahead of the app. `HOME` does not help — `NSHomeDirectory()`
ignores it.

## What else is here

- [`CHANGELOG.md`](CHANGELOG.md) — what changed in each version, newest first.
- [`Build/`](Build/) — the build scripts, plus `gateway-session-probe.sh`: the predicate deciding which
  running sessions a build would break, shared by the build guard and the app so both read a gateway
  address the same way.

The source carries no comments — a SwiftLint rule enforces it, and what a name cannot say goes into a
development journal that is kept out of this repository. A few comments, and that rule's own message,
still point at a `NOTES.md` you will not find here.

## License

[MIT](LICENSE). The two dependencies are fetched at build time rather than vendored here:
[swift-nio](https://github.com/apple/swift-nio), Apache-2.0, and
[Sparkle](https://github.com/sparkle-project/Sparkle), MIT, which installs updates.
