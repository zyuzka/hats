# Hats — what changed

Newest first. Every version the app has ever reported has an entry here, and packaging refuses to build a
disk image when one is missing. A version that has gone out keeps the entry it shipped with, word for
word; later work gets its own entry rather than being added to that one.

The app was written in a private repository along a line that reached 0.9.0 and was never published.
Nothing from that line was released anywhere, so it is not a version history a reader can act on:
what it shipped is folded into the single entry below, and public numbering starts here.

## 0.2.1 — 2026-09-12

- **A hat keeps what it knows about when its login runs out.** Signing in used to erase that date,
  because the credential a fresh login writes does not carry one and the date was overwritten with
  nothing. A hat with no date cannot say its login has expired or is about to — both checks read
  that field and answer no when it is missing — so a login could quietly reach its end with nothing
  said. Renewing already kept the date; now signing in does too.

## 0.2.0 — 2026-09-12

Everything here came from two colleagues using 0.1.0 for a day and writing down what went wrong.

- **Signing in no longer opens Terminal.** The app runs the sign-in itself and shows it in a window
  of its own, with the browser link, a field for the code the page gives you, and a way to cancel.
  Before this it wrote a shell script and handed it to Terminal.app — not whichever terminal you
  use, and on a machine where Terminal already sat on another desktop the window never surfaced, so
  a second account could not be added at all. The permission to control Terminal is gone with it:
  the app no longer asks for it, because it no longer needs it.
- **A sign-in already running offers a way out.** Starting another one used to say so and give you a
  single OK. Now it offers to raise the window that is open, or to cancel that sign-in and go on
  with what you asked for.
- **A cancelled sign-in frees the next one at once.** There was a delay of about half a minute
  during which the app still refused, because the question "may another sign-in start" was put to
  the watch that reads the credential back rather than to the sign-in itself.
- **Chrome Beta, Dev and Canary are offered like any other browser.** Only ordinary Chrome was
  looked for, so a Claude living in Canary could not be given a hat. Each channel keeps its own
  wrapper, so the same profile name in two of them cannot collide.
- **The limits are read as soon as a sign-in settles** instead of leaving the last refusal on screen
  until the next poll came round, up to five minutes later.
- **The app tells you when a new version is out.** It asks GitHub every six hours, notifies once per
  version, and the button in Settings keeps saying which version is waiting until you act on it.
- **When Claude Code and its state file name different accounts, the app says so.** It used to show
  "needs one more login", which asks you to do the one thing that cannot help: the next login writes
  the same two disagreeing places again.
- **The app appears in the dock while one of its windows is open**, so a window that slipped behind
  something else can be raised, and disappears again when the last one closes.
- **The line about live sessions no longer names the hat a direct session keeps.** The app does not
  know it — the sessions window says as much two lines below — and naming the hat worn right now was
  the app contradicting itself.
- **Smaller things a person notices.** Dialogs are the app's own windows, without the slot macOS
  keeps for an icon; both session lists lost their scrollbars and their cut-off rows; release notes
  wrap to the window instead of to the file they are written in; Settings opens on General, Hats,
  Auto-switch, Gateway in that order; and the log button moved to General, beside the version, where
  people look for it.
- **A request the gateway cannot forward is written to the log.** The count lived only in memory and
  died with the app, so a report of the gateway swallowing something left nothing to read.

## 0.1.0 — 2026-09-08

The first version published anywhere.

- **A parked hat keeps its own login alive.** An account you are not wearing sits in a slot no Claude
  Code ever reads, so the renewal its row used to promise could never arrive there: hours after a
  switch the hat had no usable token and no number, and putting it on was the only cure. Hats now
  mints a fresh token for it by itself, from the login already stored, and the row keeps a live
  reading the whole time. A hat whose stored login genuinely cannot be renewed any more says that
  instead, in its own words.
- **Auto-switch chooses on a number it can see.** Because a parked hat now carries a live reading, the
  hat put on is one whose remaining limit was actually read, not guessed at. Handing over to an
  account that turned out to be spent — or refused — is what that used to cost.
- **A refused hat stays refused until you sign in again.** Storing a hat's credential as it came off
  used to clear the mark that says the API turned it down, so a hat known to be dead could be picked
  by auto-switch minutes later and cost a sign-in. Only claiming a live login clears it now.
- **Settings is a window.** The gear opens one window with tabs — General, Gateway, Auto-switch and
  Hats — instead of replacing the popover's contents or opening a menu. A right click on the menu-bar
  mark opens the same window. Typing a port and clicking elsewhere no longer loses what you typed,
  which is what a popover that closes on focus loss did. Quit stays where it is: the power button at
  the foot of the popover, with `Cmd-Q` beside it.
- **The app stopped freezing after a long run.** Reading the list of running sessions waited for a
  process that had already been killed, with no deadline, and gave up a thread each time it happened.
  Enough of those and nothing was left to answer a click: the menu bar stayed up and the app stopped
  responding, while its own log filled with the same line. Every wait on that path now carries the
  deadline the operation already had.
- **A failed renewal is not retried on the next tick.** It waits, and the wait doubles, so an endpoint
  answering `429` is left alone instead of being asked every five minutes for as long as the app runs.
- **The credential paths refuse to be redirected elsewhere.** A request carrying a login now declines
  any redirect leaving the host, scheme and port it started at, rather than following it with the
  credential attached.
- **An answer the server could not have meant is refused rather than stored.** A login lifetime of
  zero, of a negative number, or large enough to overflow the stored date is turned away — one of
  those crashed the app outright, and another would have marked a hat expired the instant it was
  renewed.

- **The app is called Hats everywhere now.** The code carried the old `acc-switch` name long after the
  app stopped using it; the Swift module, the bundle identifier, the keychain slots and the markers
  written into the shell profile all say Hats. An installation made under the old name is adopted on
  first run and nothing has to be moved by hand. macOS ties the permission to control Terminal to the
  bundle identifier, so that one permission is asked for once more.
- **State moved out of `~/.claude`.** It used to sit in `~/.claude/state`, which belongs to Claude Code
  and is not a place for another program's files. Hats keeps its own state in
  `~/Library/Application Support/Hats` and moves what it finds in either older location on first run,
  leaving nothing behind.
- **The app has an icon**, and the release is a disk image you open and drag to Applications.
- **A hat whose token the API has refused stops counting as usable.** Health used to be read off the
  expiry date the stored credential claims, so a hat could look switchable while every new session
  under it failed to refresh. An observed 401 now outranks that date, and auto-switch will not put
  such a hat on.
- **Check for Updates** on the General tab of Settings asks GitHub for the newest release and offers
  the download.

- **A hat comes off only when its own limit is reached.** The app used to put the previous hat back the
  moment that hat's window reset, whatever the hat in use still had left — measured twice in one day,
  leaving hats with 93% and 78% of their five hours unspent. That rule is gone, along with the **Put the
  hat back on when the limit resets** switch, and the hat put on is now the first one whose own reading
  shows room, in the order you set. Coming back to a preferred account happens by itself: when the hat in
  use runs out, a window that has reset is simply a hat with room. When every hat is spent the app says
  so in its log instead of holding in silence.
- **Turning the gateway off asks first** when sessions are running through it. Quitting already asked and
  building already refused; the toggle in the panel closed the same listener without a word.
- **An automatic switch reaches the person it happened to.** Permission for notifications is asked
  whenever the switching policy would notify, not only in the moment the setting is switched on — where
  the policy was already on, it was never asked at all, so no notification could ever arrive. A banner
  drawn into a popover that is closing no longer counts as one somebody read. The switch log names the
  incoming hat's meters beside the worn hat's, which is why two true figures used to look contradictory.
- The operations log is written only by the app itself. Running the test suite used to append to it, and
  those lines read exactly like the app's own.
- **Only the real Claude Code decides which account file is live.** The app finds that out by reading
  the environment of the sessions running now, and it used to accept any process whose executable was
  named `claude` — so anything running as you could name the keychain slot and the account file a switch
  writes to, or stop every switch by disagreeing. It now requires the process to be Anthropic's signed
  binary; anything else is still listed as a session but gets no say in where a credential goes.
- **The gateway's two status paths answer only the loopback name they listen on**, so a web page cannot
  reach them by pointing a name of its own at 127.0.0.1. They also no longer publish whole session
  identifiers — the identifier is what consumes a session's one-shot notice that its account changed —
  and the sessions-at-risk answer reuses the reading it already has instead of scanning the process
  table once per request.
- **A switch refuses rather than guesses when it cannot see the running sessions.** The app reads the
  process table to find which account file the sessions running now actually read. When that read failed
  — it is given five seconds — the answer arrived as "no session is running", so the switch went ahead
  against the app's own environment and could leave a running session on the previous account. It now
  says so and refuses, and the reason is in the operations log.

- A switch no longer refuses when two CLI account files exist. Hats resolves the one file the CLI itself
  reads, and asks the sessions that are running which configuration home they were started with — an app
  launched from Finder cannot see a shell variable, so its own environment is the wrong place to look.
  Where the running sessions disagree it still refuses, and now names the homes they disagree about.
- The hat you are wearing says why its limits are blank instead of showing nothing. Activating a hat moves
  its parked credential into the live slot, and a parked token is routinely expired by then, so the hat
  whose usage matters most was the one with no number. Each reason has its own sentence, and the one
  that promises Claude Code will renew the token on its next request is shown only for the hat you are
  wearing — it is the only hat that has one.
- **Gateway** counts sessions, not credentials. Two sessions on one token used to be one number.
- The **Live sessions** window lists the sessions the relay has served beside the process list, and says
  plainly that the two answer different questions and need not agree: one is every Claude Code process
  alive now, the other is the 32 most recently seen sessions the relay has handled, ended ones included.
- The version at the foot of the General tab opens a window of every release and what changed — this file, carried
  inside the bundle. Packaging now refuses when a version the bundle has ever reported has no entry here,
  including a version bumped in the working tree but not yet committed.
- The interface no longer freezes while a sign-in is being watched. A tick used to make three subprocesses
  on the main thread, about a quarter of every second.
- After a switch or a capture, Hats asks the server whose credential now sits in the slot and records the
  answer. It used to read back a note it had written itself, which could only ever agree with itself.
- Building the app refuses to stop it while Claude Code sessions are reaching Claude through the relay,
  and names them. Stopping the app takes the relay with it, and a session holding the address in its own
  environment cannot be told otherwise.

- The Live sessions window closes when you click away from it. It used to stay until you found its close
  button, and there was no keyboard way out: this app has no Window menu, so `Cmd-W` reached nothing.
- Its minimise button is gone with the same change. A window that leaves when you look elsewhere cannot be
  kept for later, so the button was promising something it could not do.

- A quit button at the foot of the popover, beside the gear, and `Cmd-Q` while the popover is open. Quit
  was previously reachable only through the menu.
- It asks before quitting when Claude Code sessions are running, and says how many. Quitting stops the
  relay, so a session going through it cannot reach Claude until Hats is back or its shell is cleared.
- Signing in no longer blames the app bundle when it cannot close the sign-in window. macOS is now asked
  for permission at the moment the window has to be closed, with Terminal already running, instead of a
  moment before Terminal is launched — which used to fail every time on a machine that keeps Terminal shut.

- A right click or control-click on the menu-bar mark opens Settings directly.
- The install note tells you to quit Hats and delete the old app before putting the new one in. Replacing
  it in place does not launch, and the Gatekeeper step does not cure that.

- The delay before a running session follows a switch became the **Settle** field in the gateway panel. It
  was a fixed wait before, and the install note described it as fixed.

- The block Hats writes into your shell profile asks the relay first and only exports when it answers, so a
  shell opened while the app is off runs Claude directly.
- Changing the gateway port leaves running sessions alone. They stay on the old port until they end.
- The hat name in the menu bar and the blinking cursor became switches on the General tab of Settings.

- Renamed to Hats. The bundle identifier, the signing identity and the keychain service names stayed as
  they were, so this update kept every stored login and every permission already granted.

- First version handed to anyone: switch between paid Claude Code accounts from the menu bar, with each
  account's login kept ready to put on.
