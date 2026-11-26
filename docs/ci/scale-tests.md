# Repeat scale tests on a hosted runner

Dispatch **Scale tests** only when the PR queue is short. It shares the account's
20 CI job slots. #217 budget measurements come from quiet laptop 2. The hosted
runner measures repeatability and includes its image, CPU model, and logical
core count in the results.

```sh
gh workflow run scale-tests.yml --ref develop -f ref=develop -f 'filter=--only scale' -f repeats=3
```

`ref` selects the commit, tag, or branch under test. `--ref` selects the workflow
revision. The default filter selects the core app's `:scale` tests. To focus on
one tag, pass `--only TAG` or `TAG`. To run a file, use its repo-relative path
such as `apps/cadence/test/cadence/reads/fleet_status_scale_test.exs`. Core paths
can also start with `test/`. File mode includes scale-tagged tests in the
selected file. Repeats range from 1 to 10 and default to 3.

All repetitions use one runner, a fixed seed, and one test at a time. The step
summary reports wall time and exit status for each run, then each test's median
and minimum–maximum duration across passing runs. Run wall time includes any
Mix startup and compilation. ExUnit durations include test setup. Download
`scale-test-results-<attempt>` for JSON timings and logs, including benchmark
output printed by the tests.
