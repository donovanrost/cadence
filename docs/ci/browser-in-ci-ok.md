# Proposal: the federation browser job in `ci-ok`, after a speed-up

Owner: devops. Status: **proposal, 2026-11-13**. Basis: the first fully green run, #62's PR
run 43378880714, where "Phoenix producer contracts and federation browser" took **11:18**.

## Where the 11:18 goes

| Step | Time | Notes |
| --- | ---: | --- |
| containers, checkout, setup-cadence, npm ci, Playwright install | 1:42 | caches warm |
| `pnpm test:producers` | **4:17** | core producers 62 s + web producers 190 s, all sync |
| federation browser step | **5:03** | node contract tests 0:15 · `assets.deploy` 1:28 (Vite 0:08, publication 1:12, digest) · cadence recompile 0:30 · 9 browser tests 2:56 (sync) |
| ops initial-state browser step | 0:07 | |

## 1. Producer contracts: remove the duplicate (−4:17)

`test:producers` runs the 30 producer test files from `frontend/tools/producer-contracts.json` a
second time. **The core and web shards already run those same files, and each one already
executes its real frontend consumer** (`System.cmd("node", [probe, ...])` → `vp test …`). The only
thing the separate step adds is the guarantee: with `CADENCE_REQUIRE_PRODUCER_FIXTURES=1`, a
consumer fails when its fixture is missing and appends itself to
`CADENCE_PRODUCER_FIXTURE_LEDGER`, and `producer-contracts.mjs` then checks that all 30 consumers
ran.

Move the guarantee into the shards:

- `test-core` ×4 and `test-web` ×2 set `CADENCE_REQUIRE_PRODUCER_FIXTURES=1` and
  `CADENCE_PRODUCER_FIXTURE_LEDGER=$RUNNER_TEMP/producer-ledger.txt`, and upload the ledger as
  an artifact.
- A small `producer-coverage` job (`needs: [test-core, test-web]`, about 0:30) downloads and
  concatenates the ledgers, then runs `assertProducerCoverage` (already exported by
  `producer-contracts.mjs`) against `producerContracts()`.
- Delete the `test:producers` step from the browser job.

Shard cost is roughly zero: the same tests, plus one env var and an append per consumer. Risk: a
producer test that's excluded or tagged out of the shards would now fail the coverage check
loudly instead of passing silently, which is what we want.

## 2. Build the assets once (−~1:15 per job using them)

Today the browser step rebuilds tailwind, Vite, the federation publication and the digests
(`assets.deploy`, 1:28). `test-web-publication` in CI builds the publication again (1:30).

- Fold the browser job from `frontend.yml` into `ci.yml` (plan step 3), so artifacts can flow
  between jobs.
- A `browser-assets` job runs `assets.deploy` once and uploads `apps/cadence_web/priv/static`.
- The browser jobs and `test-web-publication` download it instead of building. The browser step
  then runs the test part of `test.browser.federation` directly. I'd rather add a
  `CADENCE_SKIP_ASSET_BUILD`-style switch to that alias (a small mix.exs change) than copy the
  alias's file list into the workflow, so the list keeps a single source.
- Also worth checking: the 30 s full cadence recompile inside the browser step, the same family as
  the config-mtime recompile #51 fixed. It's probably the browser env var changing
  compile-time config.

## 3. Shard the browser tests (2:56 → ~1:30)

The 9 browser tests run serially in one VM, and each federation-fixture test builds and
activates releases. Split the files into two matrix jobs (federation smoke + scheduling | admin
mode + command workspace + spacecraft config + settings + ops initial state), balanced by
measured time.

## Resulting graph and expected wall clock (warm caches)

```
test-core ×4 ─┐
test-web ×2 ──┼─ producer-coverage ─┐
browser-assets ┬─ browser ×2 ───────┼─ ci-ok
               └─ test-web-publication ┘
quality, test-packages ─────────────┘
```

| Path | Estimate |
| --- | --- |
| browser-assets (setup 0:45 + `assets.deploy` 1:30) → browser shard (setup 1:00 + tests ~1:30) | **~5:00** |
| test-web shard → producer-coverage | ~4:30 |
| **PR wall clock with browser in `ci-ok`** | **~5–6 min** (today `ci-ok` is ~3–4 min without browser) |

That keeps required checks well under the 15-minute target, at roughly a 2-minute cost for
making the browser suite required.

## Order of work

1. Producer folding (§1): biggest win, CI-only.
2. Fold the browser job into `ci.yml` with `browser-assets` (§2), including the alias switch as
   its own small commit.
3. Browser sharding (§3).
4. Add the browser jobs and `producer-coverage` to `ci-ok` after ~a week without flakes. Its
   history so far: green only since #62.

Frontend quality (4:56, `pnpm verify`) stays in `frontend.yml` for now. It's independent and
already under 5 min, and it can join `ci-ok` as-is once #63 shows it steady.
