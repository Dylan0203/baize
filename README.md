# baize (白澤)

> 白澤知曉天下所有災異鬼怪,將每一種災禍列給黃帝聽,讓他能預先防備。

A host-level disk monitor that reports to GlitchTip before the disk fills up.
Pure bash + curl. No runtime dependencies. Does not depend on anything it monitors.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/Dylan0203/baize/main/install.sh \
  | bash -s -- --dsn https://<key>@glitchtip.example.com/<project_id>
```

This downloads the latest tagged release, verifies it against `SHA256SUMS`,
installs it to `~/.local/bin/baize`, writes `~/.config/baize/config`, and
wires a cron entry — no sudo, ever.

Then verify it works end to end:

```sh
baize test     # sends a synthetic event — check GlitchTip
baize status   # config, cron state, current disk
```

## Why

On a past date a production host silently filled to 87% disk usage. A
zombie, unmonitored native Redis had been failing `bgsave` for a year,
leaking orphaned temp files. Once the disk got tight enough, the app's own
Dockerized Redis hit `stop-writes-on-bgsave-error` and refused all writes —
nine shipment notifications failed before it self-recovered. Nobody knew
the disk was tight until the application started throwing exceptions. See
[BRIEF.md](BRIEF.md) for the full incident writeup.

## How it works

```
cron, every INTERVAL
  -> baize run
       -> disk_used_pct per MOUNTS            (df -P)
       -> decide_action vs THRESHOLD + state   (breach / restate / recovery / none)
       -> on breach/restate/recovery: send an event to GlitchTip
       -> always: heartbeat check-in, if HEARTBEAT_URL is set
```

## Commands

| Command | What it does | When you'd reach for it |
|---|---|---|
| `baize install [--dsn URL] [--threshold N] [--interval Nm\|Nh] [--heartbeat URL] [--dry-run]` | Writes `~/.config/baize/config` and wires the cron entry. Idempotent — flags override the existing config, unset flags keep it. `--dry-run` prints without writing. | First-time setup, or changing a setting later |
| `baize check` | Runs once, prints per-mount usage, sends nothing | Debugging at the terminal without risking an alert |
| `baize run` | The cron verb: check, alert only on transitions, always heartbeat | What cron calls; not something you normally run by hand |
| `baize test` | Sends one synthetic `baize-test` event | Proving the DSN and network path work end to end |
| `baize status` | Config (redacted), cron state, last alert, current disk, whether a newer release exists | "What is this host doing?" at 3am |
| `baize update [--force]` | Downloads, verifies, and atomically swaps in the latest release, with rollback on any failure | Explicitly, by a human, when you've decided to update |
| `baize remove [--force] [--keep-config]` | Announces departure to GlitchTip, unwires cron, deletes files | Decommissioning a host |
| `baize version` | Prints the installed version | — |

## Configuration

`~/.config/baize/config` is shell `KEY=VALUE`, sourced with `.`. It is
written by `baize install` and never touched by `baize update`. See
[config.example](config.example) for the fully annotated version.

| Key | Default | Meaning |
|---|---|---|
| `DSN` | *(required)* | GlitchTip DSN — `https://<public_key>@glitchtip.example.com/<project_id>` |
| `MOUNTS` | `/` | Space-separated mount points to watch |
| `THRESHOLD` | `85` | Alert when used% reaches this (inclusive), 1–99 |
| `RESTATE_HOURS` | `24` | While still breached, re-send an event this often |
| `HEARTBEAT_URL` | *(empty)* | GlitchTip heartbeat check-in URL — optional, strongly recommended |
| `INTERVAL` | `15m` | How often cron invokes `baize run` — install-time only |

## Alerting behavior

Alert on **crossing**, restate on a timer, recover once:

- **Crossing** — usage goes from below to at/above `THRESHOLD`: one `warning` event.
- **Still breached** — usage stays at/above `THRESHOLD`: nothing fires again until
  `RESTATE_HOURS` has passed, then one more `warning` event.
- **Recovered** — usage drops back below `THRESHOLD`: one `info` event, once.

Why it matters: a disk stuck at 88% for a week at a 15-minute cron interval
is 672 checks. With crossing/restate/recovery and `RESTATE_HOURS=24`, that
same week produces 7 events, not 672 — a state file, not sloppiness, is
what keeps it that way.

## The heartbeat

`HEARTBEAT_URL` points at a GlitchTip Heartbeat monitor's check-in URL.
`baize run` POSTs to it on every run, success or failure, last, after
whatever alerting happened.

Create the monitor: GlitchTip → Organization Settings → **Uptime Monitors**
→ *Create a New Uptime Monitor* → Monitor Type: **Heartbeat**. Save, then
copy the check-in URL from the monitor's detail page into `HEARTBEAT_URL`.
Set the monitor's expected interval comfortably longer than `INTERVAL` (a
15-minute cron wants roughly a 30–60 minute monitor interval) so one
transient network blip doesn't page anyone.

Skip it and you lose the one thing baize exists to guarantee: if baize
itself dies, or its cron entry is removed, or the box goes dark, silence
looks exactly like a healthy disk. The heartbeat is what turns that silence
into its own alert.

## Updating

```sh
baize update
```

Resolves the latest GitHub release, downloads `baize` and `SHA256SUMS`,
verifies the checksum, runs the candidate's self-test (`version` + `check`),
and only then atomically swaps it into `~/.local/bin/baize` — keeping the
previous binary at `~/.local/bin/baize.prev` for rollback. Any failure along
the way leaves the previously-working version running untouched.

This is explicitly manual, never automatic. `baize status` will tell you a
new version exists; it will never install one. An auto-updater would hand
this component the exact network dependency and remote-code-execution
surface it exists to not have.

## Uninstall

```sh
baize remove
```

Prompts for confirmation, sends a best-effort farewell event to GlitchTip
(so the removal is visible, not just silence), unwires the cron entry, and
deletes the binary, config, and state. Use `--force` to skip the prompt and
`--keep-config` to leave `~/.config/baize/config` behind.

One thing it cannot do: delete the GlitchTip Heartbeat monitor. Doing that
would need a write-scoped GlitchTip API token living on the host — exactly
the risk this tool avoids. If a heartbeat was configured, `remove` prints a
reminder to delete the monitor by hand; skip it and it pages in about 30
minutes because baize stopped checking in.

## Limitations

- **GlitchTip is an error tracker, not a metrics system.** baize gets you
  "tell me before the disk fills". It does not get you usage trends or
  graphs. If you need those: `node_exporter + Prometheus + Alertmanager`.
  That is a different tool and baize will not grow into it.
- **Checksums are integrity, not authenticity.** `SHA256SUMS` travels the
  same HTTPS channel as the artifact, so it catches corrupted downloads,
  not a MITM. The real trust anchor is GitHub's TLS plus the repo owner's
  account. This is not signing, and nothing in baize should be read as
  claiming it is.
- **Without a heartbeat, baize dying is undetectable.** Silence reads as
  health. `HEARTBEAT_URL` is optional in config but strongly recommended.
- **Config lives in `~/.config/baize/` under the installing user.** It is
  tied to that account's lifecycle, and it is invisible to anyone who does
  not know to look there. That is the price of a zero-sudo install.
- **Disk only.** Memory, load, inodes, and cert expiry are not checked and
  are not planned. The name is broad; the tool is not.
- **A resolved GlitchTip issue reopens** when the breach recurs. Expected
  behavior — worth knowing before wiring alert rules on top of it.

## Development

```sh
bin/check                       # shellcheck (no exclusions) + the full bats suite
```

There is no CI service — `bin/check` is the gate a change must pass, run it
yourself before shipping. It is exactly `shellcheck baize install.sh
test/helpers/stubs/* bin/*` followed by `bats test/`.

**Release procedure**: bump the `BAIZE_VERSION` constant near the top of
`baize`, commit, then cut the release locally:

```sh
bin/release v0.1.1
```

`bin/release` refuses a tag that doesn't match `BAIZE_VERSION`, runs
`bin/check`, computes `SHA256SUMS`, tags and pushes, and publishes a GitHub
release with `baize` and `SHA256SUMS` attached (release notes auto-generated
from commits). It needs the `gh` CLI authenticated.
