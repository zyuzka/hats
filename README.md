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
- **It does not carry claude.ai connectors across hats.** A connector such as Slack or Atlassian is
  granted to one Claude account on Anthropic's side, so switching the hat changes which connectors
  work. A connector you connected while wearing one hat asks you to sign in again when you wear
  another.

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

The hat you wear has a small hat drawn left of its name, in the colour of its provider — terracotta
for Claude, lighter in dark mode. Under each hat Hats shows how much of the 5-hour and the weekly
limit is used. Settings › General › Usage as picks how: Percent shows the numbers, Bars shows two
bars, `5h` and `week`, with the reset time beside each. A bar turns orange from 70% and red from 90%;
a week Hats only remembers is pale, and a week that has already reset is a dashed outline.

## Codex hats

A hat can also be a Codex account. In Add hat, pick Codex, type the address and pick the hat's own
browser. Hats signs in to ChatGPT the way `codex login` does, but opens the sign-in page only in that
browser, so one browser stays one account. A small window waits for the answer; closing it, or 15
minutes without an answer, stops the sign-in and stores nothing. The sign-in listens on
`127.0.0.1:1455`, or on `1457` when 1455 is busy; those are the only two addresses the sign-in server
accepts. If Codex is already signed in as that address, the hat takes that login as it is.

Hats keeps each Codex login in the keychain, in an item of its own (`Hats Codex parked <id>`). Putting
a Codex hat on replaces `~/.codex/auth.json` the way Codex writes it: under both of Codex's locks, the
login in the file goes back to its own hat first, then the new one is written through a temporary file
and read back. Besides `auth.json`, Hats creates in `~/.codex` only Codex's own lock files
(`auth.lock`, `auth.json.lock`, kept as Codex keeps them) and its temporary file `.auth-hats-*`, which
the write renames into place or removes. Apart from the one gateway line in `config.toml` (below), it
changes nothing else there (it honours `CODEX_HOME`), and refuses when Codex keeps its login
elsewhere (`cli_auth_credentials_store` other than `file`) or the file is a link, read-only or not a
ChatGPT login. A login in the file that belongs to none of your hats is never overwritten: add it as a
hat first.

Hats renews the parked Codex hats — right after a hat comes off, and on the usage timer when its
access token has less than a day left. The hat you wear is renewed by Codex, and also by Hats while the
Codex gateway runs (below). Hats never signs a login out, because that revokes it on the server.

The menu has two tabs above the hats, "Claude" and "Codex"; each shows only its own hats, with the
average use of those hats on top, and the header names the hat worn for that tab. Each tab also names its
average 5-hour and weekly use, for example "Codex 42% · 61%", so both providers can be read without
switching tabs; hats on vacation do not count in it. The tab you chose last opens next time, also after a
restart of Hats. Settings → Hats lists the Claude hats and the Codex hats apart, each list with its own
Add… button.

### The Codex gateway

A Codex window keeps its login in memory, so putting another hat on reaches only windows started after
it — unless the window goes through the Codex gateway. The gateway is separate from Claude's: it
listens on `127.0.0.1:8788` (Settings → Gateway, under Codex; on by default once a Codex hat exists) and, while
it runs, Hats writes one line into the top of `~/.codex/config.toml`:

```toml
openai_base_url = "http://127.0.0.1:8788/<secret>/codex"
```

Every request Codex sends there goes on to ChatGPT with the login of the hat you wear right now, so a
thread started after the gateway came on changes hats between two requests without noticing. A request
already streaming finishes on the hat it started with. When the worn hat answers `usage_limit_reached`,
Hats puts on the next Codex hat that is not on vacation and does not need a sign-in, and sends the
request again; Codex sees the limit only when every hat refused it; you then get a notification, at most one every 10
minutes.
An expired login is renewed and the request repeated once; if the server refuses the login, Codex is told
that the hat needs a sign-in, and if the renewal could not reach the server, Codex gets a 502 and repeats
the turn itself. While the gateway runs, Hats also renews the hat you wear a day before its access token
expires, in `auth.json` itself, and leaves the file alone when Codex has renewed it first.

A thread counts as going through the gateway for 6 hours after its last request; an older one is only
written to the log. Turning the gateway off, changing its port, quitting Hats or removing the last Codex
hat asks first while such threads exist. Hats removes the line when the gateway stops, is turned off, or
Hats quits (and removes the file if Hats created it and nothing else is in it); the usage timer puts a
deleted line back while the gateway runs. Hats does not edit a `config.toml` that has a value over
several lines before its first table, and says so in the panel. It never touches a line someone else wrote: if
`openai_base_url` already points elsewhere, the panel says so and the gateway stays unused. A link
named `config.toml` stays a link; the file it points at is edited. The first time the gateway comes on,
Hats shows one notification asking you to restart the Codex windows that are already open — a thread keeps the address it
started with, so only threads started afterwards go through it.

The `<secret>` part of the address is random and kept in Hats' settings. A request without it gets 404
and never leaves the Mac. It keeps out web pages that call `127.0.0.1` and other users of the Mac, not
programs you run yourself — those can read `config.toml` anyway, and Codex shows the address in its own
window and logs.

What the gateway does not cover:

- Threads already open when the line was written stay on their old address.
- Voice mode (`realtime/calls`) is not supported through it and gets 404.
- The model catalog of a Codex service that was already running, and `model_catalog_url`, go around it.
- Requests to `chatgpt_base_url` (account limits, `wham/*`) keep the login the Codex service started
  with; once that login expires, the limits Codex shows can fail or disagree with the gateway.
- Codex and Hats share no lock on `config.toml`. Hats writes it through a temporary file, checks that
  nothing changed it in between, reads it back and redoes the edit when it differs, but a write from
  Codex at the very same moment cannot be ruled out.

The build script refuses to stop Hats while threads went through the Codex gateway in the last 6 hours,
as it does for Claude Code sessions on the Claude gateway, and names them as `codex-thread <id>`. It
decides whether the Codex gateway should be running by the app's own rule — a Codex hat exists and the
gateway is not switched off — from two values the app keeps in its settings.

### The Codex note before compaction

When a Codex session nears the end of its context window, Codex compacts the window into its own summary,
and the thread of the work can get lost. The Codex plugin `hats`, in this repository, keeps a resume note
for that moment.

Install it from Settings → General → Codex plugin, under the row of the Claude plugin. The row reads the
state with Codex's own commands and changes it only after you agree in a window that shows the exact
commands:

- **Install…** runs `codex plugin marketplace add zyuzka/hats` (only when no marketplace named `hats` is
  listed) and `codex plugin add hats@hats`.
- **Update…** appears when Codex lists an older version of the plugin than the one this Hats comes with. It
  runs `codex plugin marketplace upgrade hats` and `codex plugin add hats@hats`. Hats tells you about a new
  version once, with a notification.
- Install and Update take the plugin from the `main` branch of `zyuzka/hats` on GitHub, not from the Hats
  app: the app does not carry the plugin, so the version GitHub offers can lag behind the one this Hats
  names.
- **Remove…** runs `codex plugin remove hats@hats`. The marketplace stays.
- When the plugin is switched off in Codex, the row says so.
- A marketplace `hats` added from a folder is a developer's install: the row says "installed from a
  folder" and offers no update. Codex keeps its own copy of the plugin in
  `~/.codex/plugins/cache/hats/hats/<version>/` and does not refresh it when the folder changes; when the
  copy and the folder differ, the row offers **Refresh…**, which runs `codex plugin add hats@hats` again.
- A marketplace `hats` from another source, or another plugin named `hats`, is not ours: the row says so
  and offers nothing.

Hats finds `codex` in `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin` or on the `PATH` of a new login
shell, and runs it with `CODEX_HOME` set the way Hats reads the Codex folder. Without `codex` the row says
"Codex not found".

Without Hats, the same install is two commands:

```sh
codex plugin marketplace add zyuzka/hats
codex plugin add hats@hats
```

When an install, update or refresh brings hooks that are new or changed, the next Codex window says so;
choose to trust them there. Hooks trusted before and unchanged are not asked about again: Remove keeps
Codex's trust, so Install of the same plugin opens the next window without a question. Hats never trusts
them for you and never edits `~/.codex/hooks.json`.

The plugin uses the same window thresholds as the Claude plugin (Settings → Context; 60% and 70% when Hats
has never run):

- At the start of a turn past the warning threshold, the hook asks the model to write a resume note to
  `$TMPDIR/hats-codex-notes/<session id>.md` and tell you so in one line.
- At the start of every later turn, until the compaction, it asks the model to update the note, silently.
- Codex compacts the window by itself at the save threshold. Right after that, the hook hands the note back
  to the session, and the turn goes on by itself.
- After the compaction the warning comes again the next time the window passes the warning threshold.

The fill the hook sees is the input of the last answer over the model's window, from Codex's own session
file, so it lags one answer behind. One long turn can jump past both thresholds at once; Codex then compacts
before any request reached the model, and there is no note. If the model cannot write the note, it is told
to tell you only once; later turns ask it to write the note again, and the hook journal says `note-missing`.

The save threshold reaches Codex through one line Hats writes at the top of `~/.codex/config.toml`, like
the gateway line:

```toml
model_auto_compact_token_limit = 332500 # set by Hats
```

The number is the save threshold of the model's window, which the hook writes for Hats into
`codex-windows/<session id>.json` in the Hats folder. With several such files from the last 7 days, the
smallest window counts, so no thread gets a limit above its own window; older files count for nothing. The
first Codex session after the install teaches Hats the window: until then there is no line, and threads
started before the line exists compact at Codex's own limit. Codex reads the line when a thread starts, so
open threads keep the limit they started with.

Hats writes no line when the number would be 40 000 or less (a compacted window alone takes about 20 000).
It removes its line when the save threshold is turned off or no window is known any more, and puts it back
the next time it looks (at most once in 10 seconds) when someone else deletes it. The line stays in `config.toml` after Hats quits. A line
without the `# set by Hats` mark belongs to someone else and stays as it is; Hats writes that to its log.
With either threshold off, the hook asks for no note. The hooks never stop a turn: on any error they stay
silent and write a line to `codex-hooks.log` in the Hats folder.

When the Claude plugin of [Session handoff](#session-handoff) is installed and switched on, a new Codex
session also shows the anchors that closed Claude Code sessions left in its folder, the same list Claude
Code shows: with your first message, as a line `↳ Hook · Hats handoff: …`, and the model is told about them.

### Continuing a Codex session after compaction

A Codex thread that ends a turn past the save threshold stops there: Codex compacts it and hands the note
back only with your next message. Hats can do that step for you, so the work goes on by itself. It is the
switch "Continue Codex sessions after compaction" in Settings → Context, on by default; with it off, Hats
does nothing and writes nothing about it.

When the plugin's `Stop` hook has written that a turn ended at or past the anchor (save) threshold, the
model has written its resume note, and the thread has stayed idle for 20 seconds since, Hats talks to the Codex service over its socket
(`~/.codex/app-server-control/app-server-control.sock`). Here the fill counts the turn's last answer too
(`end_percent` in the window file): Codex compacts by Hats' line before any request whose input would pass it,
so a turn can end past the save threshold only by its last answer, which the lagging fill above does not see yet.

1. It reads the thread and goes on only when the thread is idle, kept in a file and not a subagent's.
2. It reads the thread once more and compacts it ("Context compacted" shows in the window).
3. It waits up to 60 seconds for the thread to go busy and then idle again, then reads it once more.
4. It starts a turn with the text "Hats: this thread was compacted at the save threshold. Continue the task
   from your resume note. If the note says the task is done, say so in one line and stop." The window shows this turn as if you had typed it. The plugin hands the note
   back at the start of that turn, and the model goes on from it.

Hats does this once per crossing: the same thread gets it again only after its window was below the warning
threshold. A turn that ended more than 10 minutes ago is left alone. Both thresholds must be on. Without a
note file the thread is left alone (`skipped reason=noNote`). When the compaction does not end within 60
seconds (`compactTimeout`), no turn starts, and Hats does not try that thread again until its window falls
below the warning threshold. Hats keeps in memory which threads it continued; after a restart of Hats it
has forgotten them, so a thread whose turn ended past the threshold less than 10 minutes before may be
continued once more.

What to know:

- Only windows in the shared Codex service are reached. A window started with `--no-daemon`, with a `-c`
  flag or by `codex exec` has no socket; it compacts with your next message, as described above.
- Codex has no way to compact a thread only if it is idle. If you start a turn in the instant between Hats'
  last read and the compaction, the compaction cuts your turn off and your text comes back to the input
  line. The 20 seconds of quiet make this rare, not impossible; the read right before the compaction narrows
  the gap only a little.
- What happens when the turn Hats started asks for a permission has not been measured. Hats does not answer
  requests from the service; it writes `codexContinue.serviceRequest` with the method to its log.
- The log says `codexContinue.done`, or `codexContinue.skipped` and `codexContinue.failed` with a reason
  (`active`, `notLoaded`, `noNote`, `noService`, `compactTimeout` and others). A line is written when the
  name, reason or thread differs from the previous line; the same line in a row is written once, so two
  threads or two reasons taking turns each write again.

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
its log rather than holding in silence. A hat marked "On vacation" in Settings → Hats is never put on
by the switch until you clear the mark; you can still put it on yourself from the menu. Its name is
shown in pink in the menu and in Settings.

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
time. A new Codex session in the folder shows the same list when the Codex plugin is installed too
(see "The Codex note before compaction"). The line is for you only: what the model receives is unchanged (checked with Claude Code
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

To silence the handoff for one session without removing the plugin, start Claude Code with
`HANDOFF_OFF=1` in its environment: the hook at session start and the hook after Read then print
nothing. Each run of the session-start hook, silenced or not, adds one line to
`<config>/state/handoff/runs.log`, where `<config>` is `~/.claude` unless `CLAUDE_CONFIG_DIR` gives a
full path: the time, how long the hook took, why it ran (`startup`, `clear` and so on), the session
id, the session's folder, the Claude process id and what the hook decided, with the error when it
failed. The hook after Read adds a line, marked `took`, when the file read was a note — what it
recorded, or why it recorded nothing — and when its input was unusable (`bad-input`), its time ran
out before it went through the markers (`incomplete`), the Claude process was not found
(`no-process`) or the hook failed (`error`); a read of any other file leaves no line. Over 256 KB the log moves to `runs.log.1`, so it never holds more than two files.

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
the hat you wear, whether another hat could take over, the keychain item of the worn hat, whether
Hats would switch away from each limit by itself, and when it last read the worn hat's usage — which the plugin's
limit thresholds read (below).

The plugin also acts on the window, through a part that runs inside Claude Code (a mod; Claude Code
2.1.323 or newer). When a session's window passes 60%, the model is asked to tell you so in one line.
When a turn ends past 70%, the plugin shows `● hats: context 71% (anchor threshold 70%) — anchoring
this session.` and runs `/hats:anchor` itself, your own steps included. It says `anchored at …` and
offers `/clear` (the note comes back after it) only once it has checked the save: a marker written in
that turn, and the note rewritten in it and not changed by anyone since. Otherwise it says why the
session was not anchored, and nothing else happens. A threshold fires once, and again only after the
window has been below it; a session never seen below 60% — one already fuller at its first answer —
gets neither. «анкор» said by you in a
turn that ends past 70% counts as that save. If the session wrote to another repository, Claude Code
may ask your permission to check it, and the save waits for your answer. Subagents and sessions
without a person (`claude -p`, the SDK) are left alone; a teammate of an agent team that runs in its
own tmux pane is a session of its own to the plugin, and is warned and anchored like any other. The thresholds and the action are set in Hats, under **Settings › Context**: **Warn at** and
**Anchor at**, each with a switch that turns it off, and **After anchoring** — only tell you, offer
`/clear`, offer `/exit` and a new session, or clear and go on from the note. Until you change them they
are 60%, 70% and the `/clear` offer, and the choice survives a restart of Hats. Hats writes them to `window-thresholds.json` in
`~/Library/Application Support/Hats` and puts the file back if it is removed; the plugin reads it at
every decision, also while Hats is not running, and without it takes 60%, 70% and the `/clear` offer.
The Codex plugin reads the same two thresholds from the same file (see "The Codex note before compaction").
Each session's stage goes to `session-thresholds/<session>.json` beside it, but only into a folder
Hats made. A running Hats reads those files and shows one notification for each threshold a session
crosses, titled with the session's name — the title you gave it, else its folder, else the start of
its id — and its percent: `hats — context 62%` with «Past the warning threshold of 60%. The session
anchors at 70%.», or «Past 70%: the session anchors at the end of its turn.» (with the clear action:
«… at the end of its turn and, if nothing stands in the way, clears its context and goes on from its
note.») — also while Settings is open in front. It says nothing about stages written before it
started, nothing when mods are off in Claude Code, and removes stage files older than 30 days.

**Drain background work**, under **Warn at**, is off until you turn it on and works only with
**Anchor at** on — of the window or of the hat limit. From a context or hat-limit warning on, the plugin refuses every new subagent, workflow, monitor and
command started with `run_in_background` — in the session and in its subagents — and tells the model
to do the step in the foreground or leave it for the next session; work already running is never
stopped. Not refused: a command Claude Code moves to the background itself after its time limit, and a
skill that runs in the background — both are waited for; a command detached with `&` or `nohup` is
neither waited for nor listed. When a turn ends past the anchor threshold while background commands,
subagents or workflows still run, the plugin says `anchoring waits for 2 background jobs, up to 10 min
(drain).` and does not ask to anchor yet; it asks at the end of a later turn, once they have ended
or **Wait up to** (1 to 60 minutes, 10 until you change it) has passed. It never wakes an idle session:
the next turn comes with your message or with Claude Code's notice that a job ended. When it asks, it
gives the model the id, kind and description of everything still running, so the note names each —
they outlive `/clear`, and the next session is told when one ends but not what it was for. A monitor
that runs a command is a background command to Claude Code (2.1.327) and is waited for like one; a
monitor on a socket and a teammate are listed but not waited for. If the list cannot be read it asks at
once and says `background work could not be checked (drain).` The refusals end once it asks, after an
«анкор» you said past the threshold, or when the window falls below the lowest threshold; they also end
when the plugin reloads, when the session changes and during the pause after the plugin's own clear.
When they end while no anchor is asked — the window fell below its lowest threshold, **Drain background
work** was turned off, or, for a hat limit, Hats moves the session again, the limit resets, its
**Anchor at** is turned off, the hat changes or the session is no longer under Hats — and the model has
had a drain text, the plugin tells the model once that background work is allowed again and why — and, when the switch
was turned off, that the session still anchors at its thresholds. It
waits while anything else still refuses, and while a limit warning with the drain words goes out. With
**Warn at** off they start only when anchoring is put off for running work. Hats writes
the switch and the minutes to `window-thresholds.json` as `drain` and `drain_minutes`; a session that
waits has the stage `waiting`, and its notification reads «Past 70%: the session anchors at the end of
its turn, after its background work (up to 10 min).» Scheduled wake-ups (`/loop`, `CronCreate`) are
not refused; the list carries only their number — `Scheduled wake-ups: 1 — they are not listed here, and
they stop the automatic clear.`

**Drain by a hat limit.** The same switch acts on every session on the worn hat when Hats will not move
it off a limit (the rules of **Hat limit** below): from the limit warning on — or, with **Warn at** off,
from the first turn end whose anchor is put off — new background work is refused with `Hats drain: this
session's account is close to its 5-hour limit and …` (two limits with the same reason name it once:
`close to its 5-hour and weekly limits and …`), until that limit's anchor is asked, a save counts
for it, its episode ends or its reset passes, or Hats can move the session again. The anchor of the
limit waits for running work up to **Wait up to**, counted from the first warning of that limit on that
hat in that episode — one deadline for all its sessions. Hats finds that time in the stage files and
writes it to `hat-usage.json` as `first_warned`; until it does, a session counts from its own warning,
and with no warning from the turn end that put the anchor off. The deadline only ever comes nearer: a
session warned late may find it already passed and anchor at once, without waiting for its own work. At
the end of each turn the window and the limits are decided together: any cause that is ready — drain
off, nothing holding, its own deadline passed, the work could not be checked — asks once for all of
them, and the work still running is listed; otherwise the session waits, and the line names the
nearest deadline whenever it changes. A wait for a limit is written to the stage file as a `waiting`
event; a reload keeps it with its deadline. Hats tells it once per hat, limit and reset, on the first of
`waiting` and `asked`: «… Sessions anchor at the end of their turn, after their background work (up to
10 min from the first warning on this hat).»

**Hat limit**, the second section of **Settings › Context**, acts on the 5-hour and weekly limits when
Hats will not move you off a limit itself: no other hat is free, auto-switch is off, the switch
threshold of that limit is off, or Hats has not read the worn hat's usage for 15 minutes (it checks every 5
minutes and at once after the Mac wakes). Each session reads the usage of
its own account from Claude Code with every answer and compares it with **Warn at** and **Anchor at**
(70% and 80% until you change them, each with its own switch; one pair for both limits). Past the first,
the model is asked to tell you in one line — in the next tool result or with your next message; past
the second, at the end of the turn the plugin shows `● hats: hat limit: 5-hour 81% (anchor threshold
80%) — anchoring this session.`, runs `/hats:anchor`, and after the checked save says `anchored: this
session's account is at 81% of its 5-hour limit (threshold 80%), which resets at 17:00.` The action
after anchoring is not run for a limit — `/clear` does not give a limit back. When the window and a
limit are both due at one turn end there is one anchor, the limit line first and then the window's
action; a save that is due anyway — your «анкор», or one for the window — counts for a limit that is
past its anchor threshold. Each stage comes once per session for each limit and reset time: a reset
less than an hour from the first one seen is the same episode, and a new session (also after `/clear`)
is warned and anchored again. An anchor for a limit that did not save — the check failed, you pressed
Esc, the command did not start, a hook failed — is asked once more at the end of the next turn, and not
again in that episode if it fails a second time. The plugin acts only in a session whose keychain item is the one of the
worn hat (`credential_service` in `hat-usage.json`); Hats writes the thresholds to
`window-thresholds.json` as `limit_warn_percent` and `limit_save_percent`. The stage file of each
session carries the limit events, and a running Hats shows one notification for each hat, limit, reset
and stage, titled with the hat and the percent — `work — 5-hour 81%` with «No other hat to switch to. Sessions anchor at the end of their
turn.» — whatever **Notify me when it changes** says, and never for events from before it started.
**Early signal.** A limit can run from 70% to 80% in three minutes. So each session also keeps, in memory
only, the time it first saw each new top whole percent of each limit (a point keeps that first time and
is not moved by later readings of the same percent; a lower reading in the same episode means another
account and starts the points again from it), and works out the pace: the rise since the
newest point at least 5 points lower and at least a minute old, divided by the time from that point to
now. If at that pace the limit reaches **Anchor at** within the lead — the drain minutes plus 82 seconds
(the average cost of a save) with drain on, 10 minutes and 82 seconds with it off — the session gets
its warning early, below **Warn at**: «… at 58% of its 5-hour limit and spending fast: at the pace of
the last minutes it reaches 80% in about 11 minutes …». It is checked again when it is delivered; once
told, it is the warning of that episode, and the anchor at **Anchor at** stays as it was. The lead is
an aim, not a promise: a session that saw too few points, or reloaded the plugin, or has just started,
warns later or not early at all, and a pace that is fast for a minute and then stops can warn for
nothing. Hats tells it as `work — 5-hour 58%` with «Spending fast: 80% in about 11 min. No other hat
to switch to.» in place of the usual warning. Each `limit.alert` line in the journal carries `episode`
(the reset time of the episode), `early` (`1` or `0`), `target` (the anchor threshold) and
`lead_seconds`, and an early one `minutes_to_save`: with the lines of one episode you can count signals
that came true (the anchor line within twice the minutes), false ones (no anchor line, or later) and
misses (an anchor line with no early signal, less than the lead after its warning). Leave out an episode
whose lines carry different `target` values: the thresholds were changed inside it. The journal keeps
its last 500 lines, and episodes while Hats was not running are not in it.
Hats remembers what it told in `limit-notices.json` beside the stage files — the hat, limit, reset and
stage of each notification — for 8 days; deleting it does not bring old notifications back, since Hats
never tells events from before its start and keeps what it told in memory while it runs.
Not promised: a turn spends on until its end, so the warning may come late, a session at 100% cannot
anchor, and an idle session hears nothing. Not supported: Claude Code does not tell the plugin which
account a session spends, so "nowhere to go" is judged by the worn hat while the percent is the
session's own — a session without the gateway before its pass is renewed, or a gateway session before
it takes the new pass, may spend another account; a change of account whose reset is less than an hour
from the old one counts as the same episode; sessions with different settings, when Hats does not know
its keychain item, get nothing; and a session with `CLAUDE_SECURESTORAGE_CONFIG_DIR` set empty never
matches, because Hats counts its keychain item with a hash and Claude Code without one.

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
| Codex | hats: sign-in, wearing, renewing; the Codex gateway moves new threads between hats and past a usage limit; no usage display yet |

## Where things live

| What | Where |
| --- | --- |
| Hats, settings, operations log | `~/Library/Application Support/Hats/` |
| Stored logins | macOS Keychain, one item per hat |
| The Codex login in use | `~/.codex/auth.json`, Codex's own file |
| The Codex gateway address | one `openai_base_url` line in `~/.codex/config.toml`, only while the gateway runs |
| The Codex compaction limit | one `model_auto_compact_token_limit` line in `~/.codex/config.toml`, marked `# set by Hats` |
| Codex resume notes | `$TMPDIR/hats-codex-notes/<session id>.md`, written by the Codex session itself; beside it `<session id>.state.json`, whether you were told; both removed after 30 days |
| Codex model windows | `codex-windows/<session id>.json` in the Hats folder: session id, working folder, window and fill; removed after 30 days |
| Codex hook journal | `codex-hooks.log` in the Hats folder (`hooks.log` in the notes folder when there is no Hats folder) |
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
  them. With `HATS_STATE_HOME` set to an absolute path (`~` is not expanded), the notes folder is
  `$HATS_STATE_HOME/notes/` and the general steps file below sits in `$HATS_STATE_HOME`. A plugin
  hook lets the session read a note of that folder, and write one of its own project, without asking. Your own steps
  run with it, from two optional files:
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
