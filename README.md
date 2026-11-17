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

## Session handoff

A Claude Code plugin that ships with Hats: the command «анкор» (`anchor`, or `/hats:anchor`) saves a
resume note, and the next session in the same folder is offered it. What it writes and where is under
[`plugin/`](#what-else-is-here) below.

When a session starts, and after `/clear`, Claude Code shows one line from the plugin under its logo:
`SessionStart:startup says: Hats handoff: …` (`SessionStart:clear says: …` after `/clear`). After
`/clear` it names the anchor the session continues and its note, or says that the anchor already went
to another session or that this Claude process has none; in a new session it lists the notes that
closed sessions left in this folder, or says there are none or that some could not be checked in
time. The line is for you only: what the model receives is unchanged (checked with Claude Code
2.1.323), except for the mark below.

The plugin also notices two sessions on one task. A session that reads a note with the Read tool is
recorded as reading it; when other live sessions read that note too, a line appears under that Read
call — `PostToolUse:Read says: Hats handoff: 1 other live session(s) reading this note: …` — and the
model is asked to continue the task only if you confirm. Only the first read warns. The list in a new
session and the note given back after `/clear` carry the same mark, for you and for the model, and
`/clear` takes the session off the notes it was reading. For this the plugin runs a hook after every
Read and writes, in `state/handoff/taken/` of Claude Code's settings folder (`~/.claude` unless
`CLAUDE_CONFIG_DIR` says otherwise), the Claude process id, start time and session id of each session
that read a note; a read made only to look at the note counts too, and the session stays recorded
until its `/clear` or until its Claude process exits.

Hats never installs it on its own. Open **Settings › General › Session handoff**: the row says whether
the plugin is installed, from where, and whether it is switched off in Claude Code. **Install…** first
checks what the plugin needs, then shows what it will install and into which Claude Code settings
folder, and runs nothing until you press Install there:

```sh
claude plugin install hats --marketplace zyuzka/hats --scope user --json
```

It refuses, with the reason and the cure, when Claude Code is missing or too old (no `--marketplace`),
when running sessions use different settings folders or `CLAUDE_CONFIG_DIR` is not a full path, when
the first `python3` on the PATH is the macOS placeholder that offers the Command Line Tools
(`xcode-select --install`), when `settings.json` cannot be read as JSON, and when `settings.json`
already starts the same handoff hook by itself — remove that entry by hand first: Hats shows it and
never edits the file. A marketplace named `hats` from another source, or another plugin named `hats`,
is reported and left alone. **Remove…** runs
`claude plugin uninstall hats@hats --scope user --keep-data --json`: the `hats` marketplace, your
notes and your settings stay, and an installation for a project is shown but not touched. Quitting
Hats removes nothing.

When Hats itself is updated and comes with a newer plugin than the one Claude Code lists, the row says
**Update available: 0.1.0 → 0.2.0** and offers **Update…**, and one notification says so for each new
version (a click opens Settings). Hats does not ask GitHub for this: it compares the installed version
with the one it was built with. **Update…** shows what it will run, and runs nothing until you press
Update there:

```sh
claude plugin marketplace update hats --json
claude plugin update hats@hats --scope user --json
```

The first refreshes Claude Code's copy of the `hats` marketplace; the second installs the version
GitHub offers now, so the window afterwards names the version Claude Code then lists, which may still
be older than the one this Hats comes with. A plugin switched off in Claude Code stays switched off —
the row offers the update, the notification stays silent, and the window afterwards says how to turn
it on. A plugin from a folder marketplace loads in place and is never offered an update. Running
sessions get the new version after `/reload-plugins`, new ones when they start.

Without Hats, the same commands work in a terminal.

The plugin also tells Hats how full each session's context window is. After every prompt, every tool
call, the end of every turn and a compaction it reads the end of the session's transcript and writes
the number Claude Code's status line shows into
`~/Library/Application Support/Hats/session-windows/<session>.json`; when the session ends (`/exit`,
`/clear`, logout) its file is removed. It writes only where Hats has run — the plugin never creates
`~/Library/Application Support/Hats` — and subagents and sessions without a person (`claude -p`, the
SDK) write nothing; files older than 30 days are removed. The menu then shows, under **Context**, up
to five sessions measured in the last hour, the fullest first: the percent, the token count when the
model's window size is not known, or `compacted` right after a compaction. A session is named by the
title you gave it with `/rename`, else by its folder; two rows with the same name get the first four
characters of their session id. Hats writes back `hat-usage.json` beside that folder — the usage of
the hat you wear and whether another hat could take over — for the plugin's later window and limit
thresholds; nothing reads it yet.

The plugin also acts on the window, through a part that runs inside Claude Code (a mod; Claude Code
2.1.323 or newer). When a session's window passes 45%, the model is asked to tell you so in one line.
When a turn ends past 55%, the plugin shows `● hats: context 56% (anchor threshold 55%) — anchoring
this session.` and runs `/hats:anchor` itself, your own steps included. It says `anchored at …` and
offers `/clear` (the note comes back after it) only once it has checked the save: a marker written in
that turn, and the note rewritten in it and not changed by anyone since. Otherwise it says why the
session was not anchored, and nothing else happens. A threshold fires once, and again only after the
window has been below it; a session never seen below 45% — on a model with a 200 thousand token
window that can be one already fuller at its first answer — gets neither. «анкор» said by you in a
turn that ends past 55% counts as that save. If the session wrote to another repository, Claude Code
may ask your permission to check it, and the save waits for your answer. Subagents and sessions
without a person (`claude -p`, the SDK) are left alone; a teammate of an agent team that runs in its
own tmux pane is a session of its own to the plugin, and is warned and anchored like any other. The thresholds and the action are set in Hats, under **Settings › Context**: **Warn at** and
**Anchor at**, each with a switch that turns it off, and **After anchoring** — only tell you, offer
`/clear`, offer `/exit` and a new session, or clear and go on from the note. Until you change them they
are 45%, 55% and the `/clear` offer, and the choice survives a restart of Hats. Hats writes them to `window-thresholds.json` in
`~/Library/Application Support/Hats` and puts the file back if it is removed; the plugin reads it at
every decision, also while Hats is not running, and without it takes 45%, 55% and the `/clear` offer.
Each session's stage goes to `session-thresholds/<session>.json` beside it, but only into a folder
Hats made. A running Hats reads those files and shows one notification for each threshold a session
crosses, titled with the session's name — the title you gave it, else its folder, else the start of
its id — and its percent: `hats — context 47%` with «Past the warning threshold of 45%. The session
anchors at 55%.», or «Past 55%: the session anchors at the end of its turn.» (with the clear action:
«… at the end of its turn and, if nothing stands in the way, clears its context and goes on from its
note.») — also while Settings is open in front. It says nothing about stages written before it
started, nothing when mods are off in Claude Code, and removes stage files older than 30 days.

With **Clear and go on from the note** the plugin clears the session itself, after a save on the
threshold that it checked — never after an «анкор» you said. It shows `anchored at 56% — clearing the
context; the session goes on from its note.`, runs `/clear`, waits up to 5 seconds for its start hook
to give the note back to the new session, and then sends `Hats: this session reached 56% of its
context window, was anchored and cleared. Continue the task from the resume note …` as your prompt;
Claude Code marks it as a prompt from the plugin, and the model names the note it picked up and goes
on with its next step. It clears only when nothing stands in the way: nobody but the plugin sent input
since it asked to anchor — you, a notice of a background task, a `/loop`, another session or a channel;
the prompt holds no draft; your own steps had nothing to run after the anchor; the note is still what
the session wrote; every background task still running is named in the note by its id; and nothing is
scheduled to wake the session. When `/clear` starts to run, three of these are checked once more: no
input arrived, the prompt holds no draft, and the session is still the same one. Otherwise it says `anchored at 56%, not cleared: <why>. Type /clear when ready: the plugin
gives the note back.` When the note does not come back, or something was typed after `/clear`, it
sends no prompt and says so. For 10 minutes after its own clear it does not ask to anchor again; it
says so, and «анкор» still works. To see the background work it reads
`stop-snapshots/<session>.json` beside the stage files, which a hook on Claude Code's `Stop` writes at
the end of every turn — the id, kind, state and description of each background task still running and
the number of scheduled wake-ups. That hook runs before the turn ends, only where Hats has run, and
removes its files older than 7 days. Background commands and subagents survive `/clear`, and the new
session is told when one ends.

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
- [`plugin/`](plugin/) — a Claude Code plugin that hands a saved resume note to the next session: the
  command «анкор» (`anchor`, or `/hats:anchor`) saves it. The note goes into Claude Code's memory
  folder of the project, beside a `resume-index.md` that lists the saved sessions, and one line at the
  top of `MEMORY.md` points to that index — so a session finds the note even after the plugin is
  removed. The plugin alone writes the index; do not edit it. So the plugin writes into Claude Code's
  memory folder: it creates `MEMORY.md` with that line when there is none, and asks the session to add
  the line at the top of an existing one. It also keeps one small file per session in
  `~/Library/Application Support/Hats/session-windows/` (see [Session handoff](#session-handoff)).
  With Claude Code's memory switched off
  the notes live in
  `~/Library/Application Support/Hats/notes/`, one folder per project; deleting that folder deletes
  them. Your own steps run with it, from two optional files:
  `~/Library/Application Support/Hats/anchor-steps.json` for every project, and
  `<project>/.claude/anchor-steps.json`, which counts only when the session runs in a folder listed in
  `projects` of the first one — that folder itself, not a subfolder. Each holds the lists `before` and
  `after`; a step is `skill:<name>` or a plain instruction, and the general steps come first:

  ```json
  {"before": ["skill:daily-journal", "Commit the vault files you wrote, by explicit path."], "projects": ["~/projects/hats"]}
  ```

  If a skill of yours writes the resume note itself, say so with `"note": "steps"` in either file
  (the project's value wins when that file counts; the default is `"anchor"`). Keep the step that
  writes the note in the same file as `"note": "steps"`: the general and the project steps add up, so
  a writer in the general file still runs under a project's `"anchor"`, and the task gets two notes.
  That step, in `before`, writes the note and prints exactly one line `resume note: <path>` during
  this anchor command — in a command's output or in its reply — with a path from the root and without
  `"`, `$`, a backquote, a backslash or a line break; anchor hands that path to the handoff without
  writing a note of its own or touching that one. Otherwise there is no handoff, and the summary says
  "Not saved" with the reason. The path must lie in a Claude Code memory folder — of any project: the
  plugin does not check which, and a path into another project's memory rewrites that project's
  index — or in this project's notes folder above; otherwise the handoff refuses it. If the command
  that reads your steps fails, anchor writes its own note and warns that the task may now have two
  notes.

  Steps that change a repository belong in `before`: the save then sees the state they leave. Keep a
  project file out of git, for example in `.git/info/exclude`: committed, it runs for everyone who
  lists that folder. A file over 16 KB, a list over 20 steps, a step over 500 characters or any
  malformed entry skips the whole file, and a skipped general file marks no project; the reason shows
  on the `own steps` line of the anchor summary. The plugin's tests sit beside it, and
  [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json) lists it.

The source carries no comments — a SwiftLint rule enforces it, and what a name cannot say goes into a
development journal that is kept out of this repository. A few comments, and that rule's own message,
still point at a `NOTES.md` you will not find here.

## License

[MIT](LICENSE). The two dependencies are fetched at build time rather than vendored here:
[swift-nio](https://github.com/apple/swift-nio), Apache-2.0, and
[Sparkle](https://github.com/sparkle-project/Sparkle), MIT, which installs updates.
