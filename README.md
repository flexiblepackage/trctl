# trctl

Command-line tool for managing TestRail test runs. Create a run from a chosen set of cases, update an
existing one, and report results back — built to run unattended in CI.

This repository distributes the released binaries. Releases are `linux/amd64` only.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/flexiblepackage/trctl/main/install.sh | sh
```

**In CI, pin a version.** A tool that silently changes behaviour between builds is worse than no tool:

```sh
curl -fsSL https://raw.githubusercontent.com/flexiblepackage/trctl/main/install.sh \
  | TRCTL_VERSION=v0.3.0 TRCTL_INSTALL_DIR=./bin sh
```

| variable | meaning |
|---|---|
| `TRCTL_VERSION` | tag to install, e.g. `v0.3.0`. Defaults to the latest release, and warns |
| `TRCTL_INSTALL_DIR` | where the binary goes. Defaults to `/usr/local/bin` |

The installer verifies the download against the release's `checksums.txt` and refuses to install if the
hash does not match or if no checksum tool is available. Or do it by hand:

```sh
curl -fsSLO https://github.com/flexiblepackage/trctl/releases/download/v0.3.0/trctl_linux_amd64
curl -fsSLO https://github.com/flexiblepackage/trctl/releases/download/v0.3.0/checksums.txt
sha256sum -c checksums.txt
chmod +x trctl_linux_amd64
```

## Use

```
trctl run create   -config runs.toml -run <key> (-ids-file <file> | -results <json>) [-dry-run] [-output json]
trctl run update   -id <run> [-name …] [-refs …] [-set-cases -ids-file <file> -confirm]
trctl results push -id <run> [-field <case field>] (-results <json> | -ids-file <file> -status <name>) [-output json]
```

### Naming the cases

Two ways, and they differ in what they can catch.

**By a join field** (`-ids-file`) matches each value against the case field named by the config's
`join_field`. Because the value identifies the test, a renamed or moved test has no matching case, and
the build fails naming it — the selection diff is the drift detector.

**By case id** (`-results`) takes a JSON file whose entries carry `case_id`, for when whatever produced
the results already knows which case each one belongs to. `-field` is then unnecessary. This path still
refuses an id that is not in the target suite, so a typo, a deleted case or an id from another suite is
caught; what it cannot catch is an id pointing at the wrong case in the same suite.

**The same results file drives both commands**, so a run's contents and the results pushed into it
cannot disagree:

```sh
run_id=$(trctl run create -config runs.toml -run nightly -results results.json -output json | jq -r .run.id)
trctl results push -id "$run_id" -results results.json -output json
```

```json
[
  {"case_id": 101, "status_id": 1, "elapsed": "2s"},
  {"case_id": 102, "status_id": 5, "elapsed": "3s", "comment": "AssertionError: expected 200, got 500"}
]
```

`status_id` may be given as `status` instead, naming the status as this instance spells it.

Credentials come from the environment, never from flags — flags land in CI logs:

```
TESTRAIL_BASE_URL   e.g. https://example.testrail.io
TESTRAIL_EMAIL
TESTRAIL_API_KEY
```

### Exit codes

| code | meaning |
|--:|---|
| 0 | success, or a dry run with a clean diff |
| 1 | usage error |
| 2 | **the CI gate** — the case selection had unmatched or ambiguous keys |
| 3 | a TestRail write failed |
| 4 | configuration or credentials invalid |

`-dry-run` is a first-class mode rather than a debug flag: it resolves and reports without writing, and
is how the gate is meant to be run.

### Machine-readable output

`run create` and `results push` accept `-output json`, which puts exactly one JSON document on stdout
and moves the human-readable report to stderr, so a pipeline can do:

```sh
run_id=$(trctl run create -config runs.toml -run nightly -ids-file ids.txt -output json | jq -r .run.id)
trctl results push -id "$run_id" -field custom_test_key -results results.json -output json \
  | jq -r '"\(.by_status.passed // 0)/\(.matched) passed"'
```

The document is emitted on exit 2 as well, so when the gate fires, `unmatched` and `duplicates` say
what did not match. Collection fields are always `[]` or `{}`, never `null`.

## Configuration

Everything site-specific lives in a TOML file supplied by the caller — no TestRail host, project,
suite, field name or status id is baked into the tool.

```toml
project_id = 1
join_field = "custom_test_key"

[[runs]]
key      = "nightly"
suite_id = 2
plan_id  = 3
name     = "Nightly #${BUILD_NUMBER}"
refs     = "ABC-123"
```

Environment variables in `name` are expanded, so each build can label its own run. Machine-side links
are always by id, never by name, so renaming is only a config edit.

## Licence

MIT. See [LICENSE](LICENSE).
