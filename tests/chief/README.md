# Chief plugin tests

Functional/integration tests of Chief's own bash scripts.

The folder says what a test needs to run; the file name says what it tests.

| Folder | Needs | Holds |
|---|---|---|
| `unit/` | no backend, no agent | One library, CLI or template per file: `meta`, `lock`, `id`, `backlog`, `agent-*`, `hook-harness` (the Codex and Copilot adapters), `templates`, `static`... About 40 s in total |
| `workflow/` | a real herdr and the stand-in agent | Chief's scripts end to end: `spawn`, `spawn-agents`, `spawn-rollback`, `handoff`, `promote`, `send`, `control`, `teardown`, `review`, `review-all`, `crew-state`, `watch`, `hooks`, `lifecycle`, `spawn-sync` |
| `backends/` | a real herdr, or (`orca`) a real headless Orca | The adapter contract of `backends/herdr.sh` and `backends/orca.sh` |
| `harness/` | herdr (`standin`, the server guard) or nothing | The test doubles and the zero-cost guard |
| `manual/` | real herdr and agent CLIs, real tokens | Opt-in scripts (below), never run by `run-tests.sh` |

`lib/` holds the shared helpers, `fixtures/` the stand-in agent and the faulty
`herdr` wrapper, `ci/` the pinned installers.

## Real herdr with a stand-in agent

Tests run against a real, headless `herdr server` - one per test, with
its own `HOME`/`XDG_*` and socket, stopped in `teardown` (`lib/common.bash`).
The agent in its panes is `fixtures/standin/claude`, a Claude-Code-shaped TUI
that costs no tokens; the server's `PATH` holds only the stand-ins, and
`chief_zero_cost_guard` aborts if a real `claude`/`codex`/`copilot` could be
found. Panes inherit the server's environment, not the test's: configure the
stand-in through files under `$STANDIN_DIR` (`standin_mode`, `standin_hold`),
never exported variables (modes: `exit`, `never-ready`, `late`, `trust`,
`lose-enter`, `drop`, `slow-work`; see the header of `fixtures/standin/claude`).
Where a real herdr reply cannot be provoked, `chief_herdr_fault` swaps one named
call's reply (`fixtures/faulty/herdr`, a wrapper that otherwise runs the real
herdr). Use `eventually` for anything asynchronous, never a bare `sleep`.
`standin_never_ready` fails a spawn and shortens herdr's 30 s wait on the pane to 5 s
(`CHIEF_HERDR_AGENT_START_TIMEOUT_MS`).
Loading `lib/common` strips `HERDR_*`, `CHIEF_*` (except `CHIEF_TEST_*`) and
`CLAUDE_PROJECT_DIR` from the environment and fixes the git identity.

`tests/chief/ci/install-herdr.sh` installs the pinned herdr into
`tests/.cache/bin`, which the suite prefers over the herdr on `PATH`. Only tests
that start a server need herdr (`chief_herdr_require`); the `unit/` tier and the
Orca job do not.

## Real headless Orca (`backends/orca.bats`)

One `orca-ide serve` per file (`lib/orca.bash`: Xvfb, own `HOME`/`XDG_CONFIG_HOME`,
port 0, scrubbed env), so its tests run serially; `teardown_file` kills the
server, Xvfb, Orca's pty daemon and the stand-ins by working directory. Orca
adds the login shell's `PATH` to its panes, so the stand-ins go first through
the isolated `HOME`'s `.bashrc`, and a test checks in a pane that `claude`,
`codex` and `copilot` resolve to them. Orca cannot see a stand-in's hooks, so
each prompt it sends takes ~8 s; the file stays small (~5 min). It needs
`tests/chief/ci/install-orca.sh` (or `orca-ide` on `PATH`) and Xvfb plus the
Electron libraries listed in `.github/workflows/tests.yml`; without them the
file skips, unless `CHIEF_TEST_REQUIRE_BACKENDS=1` makes that a failure. CI
runs it as `chief-orca` (`run-tests.sh --only-orca`); the herdr job runs
`--no-orca`. A plain `run-tests.sh --jobs N` runs the Orca file alongside the
herdr files; on a small machine use `--no-orca`, then `--only-orca`.

## Running

```bash
./tests/chief/run-tests.sh                       # everything
./tests/chief/run-tests.sh tests/chief/unit      # the fast tier, no backend
./tests/chief/run-tests.sh tests/chief/workflow/send.bats
```

`.bats` files run on [bats-core](https://github.com/bats-core/bats-core) pinned
in `tests/package.json` (bats 1.14.0, bats-assert, bats-support, bats-file;
`run-tests.sh` runs `npm ci` on first use, so Node and npm are needed). Options:
`run-tests.sh [--jobs N] [--junit DIR] [--no-orca | --only-orca] [bats args...] [path...]`.
A path (a folder or a `.bats` file) replaces the default of the whole suite. `--jobs`
needs GNU `parallel` (without it the run warns and goes serial, slowly);
`--junit` writes `DIR/report.xml`. Every test gets `BATS_TEST_TIMEOUT` (300 s).
To run bats yourself, pass `-r` and `--setup-suite-file tests/chief/setup_suite.bash`
(bats only looks for it beside the path it is given).

Requires `git`, `bash`, `jq`, `herdr` (v0.9.3) and `node`/`npm`; the Orca file
also needs Orca. A missing backend skips its tests, unless
`CHIEF_TEST_REQUIRE_BACKENDS=1` (set by both CI jobs) makes that a failure.

## Writing tests

- **File names** have no `test-` prefix: `workflow/send.bats`. The name is the
  subject (a script, a library or a feature), not a mood.
- **Test names** read `<area>: <observable outcome> [when <situation>]`: the area
  is a subcommand, function or phase, the outcome one behaviour (no `;`, `->` only
  for a role change), the whole at most 80 characters. A generated name must be
  unique and built from its input. A name promises only what the body asserts.
- **Status**: pin the exit code (`assert_failure 1`, `run -1`), not just "nonzero".
- **Helpers** (`lib/common.bash`) are named by what they drive: `chief_*` for
  Chief and herdr (`chief_project` then `chief_herdr_server` for a test that
  spawns, `chief_spawn <id> <role> [flags]`, `chief_spawn_quiet`,
  `chief_commit_file`, `chief_done_builder`, `chief_finish`, `chief_refused`,
  `chief_review`, `chief_watch_once` / `chief_watch_silent`), `standin_*` for the
  stand-in agent, `assert_contains_all` / `refute_contains_any` /
  `assert_agent_neutral` / `assert_no_placeholders` for text, and `eventually`
  for anything asynchronous. A helper used by two files lives there, not in the files.
  `eventually` takes a function or command, never `"$(...)"`, which expands once.
  Wait for background jobs by pid (`wait "$pid"`), never a bare `wait`: bats'
  timeout watchdog is a child of the test too.
- **Templates**: pin operative tokens only (paths, status syntax, commands, the
  "never" rules), not wording.

## The herdr and copilot backend tests that use real agents

`manual/herdr-real.sh` isn't free: it needs `herdr`, `claude`, `jq`,
`ss` and a claude login (`ANTHROPIC_API_KEY`, `CLAUDE_CODE_OAUTH_TOKEN` or
`.credentials.json`), and spends three trivial claude turns. It covers only what
the stand-in can merely imitate: the folder-trust dialog, the placeholder hint
in a never-prompted input box, and our text in the input line while a prompt is
in flight. `run-tests.sh` never runs it. Opt in:

```bash
CHIEF_TEST_HERDR=1 bash tests/chief/manual/herdr-real.sh
```

It never touches your herdr or `~/.claude.json`: like the copilot tests it runs
through `manual/lib/isolation.sh` (scrubbed environment, own `HOME`/`XDG_*`,
own herdr server and socket, own `CLAUDE_CONFIG_DIR`) and aborts unless that
isolation is proven. `CHIEF_TEST_HERDR_GUARD_ONLY=1` runs that guard alone (no
claude needed). The script has not been run against a real claude, so the seeded
`hasCompletedOnboarding` in its temp `.claude.json` is untested.

`backends/herdr.sh` is verified against a herdr 0.9.3 install -
see its header for the real CLI shape and two confirmed quirks: Claude
Code's first-run "trust this folder?" dialog, and `herdr agent prompt
--wait` reporting `agent_prompt_stalled` for distinct situations (text
delivered but Enter didn't register, text never delivered, TUI not yet
rendered) that `_chief_herdr_recover` tells apart from the screen.

### The copilot test

```bash
CHIEF_TEST_COPILOT=1 bash tests/chief/manual/copilot.sh
```

Needs `herdr`, `copilot`, `jq`, `ss` and a copilot login in `~/.copilot/config.json`
(or `$COPILOT_HOME`); skips cleanly without any of them. **Cost: one research
turn per run** (the spawned worker's brief); everything else, including the
paste check, is free local screen reading. It fails without retrying on a rate
or quota message.

It never touches your herdr: it runs in a scrubbed environment (no `HERDR_*`),
with its own `HOME`/`XDG_*` in a temp dir and its own herdr server and socket,
and aborts before any herdr call or copilot run unless it proves the socket
differs from the default and the caller's, its server pid differs from the
default server's, and its workspace list is empty.
`CHIEF_TEST_COPILOT_GUARD_ONLY=1` runs that guard alone. Only the login is
copied into the temp `HOME` (plus trust for the throwaway repo); it is deleted
on EXIT/INT/TERM/HUP along with the temp dir, and only the test's own server is
stopped. Copilot has no folder-trust handling, so the spawn repo is pre-trusted
in the temp config; an untrusted folder stalls at copilot's trust dialog.

### The copilot brief test

```bash
CHIEF_TEST_COPILOT_BRIEF=1 bash tests/chief/manual/copilot-brief.sh
```

Same prerequisites and isolation as the copilot test (shared in
`manual/lib/isolation.sh`). **Cost: one research turn per attempt**, with
`CHIEF_TEST_COPILOT_BRIEF_ATTEMPTS` attempts (default 3). The bug needs herdr to
report `agent_prompt_stalled` although copilot took the brief, which happens on
some runs only, so the test fails when no attempt stalled instead of passing
without having exercised the recovery.

## What's deliberately NOT here (needs the devcontainer instead)

- **Skill-behavior tests** (does Claude actually follow `using-chief`/`dispatch`/`setup` correctly when loaded) - that's `tests/claude-code/test-using-chief.sh`, `test-dispatch.sh`, and `test-chief-setup.sh`, which invoke the real `claude` CLI and cost real tokens.
