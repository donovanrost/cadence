import Config

# #50: test values that change between runs (the partition, the OS pid) are runtime config, so the
# compile-time config stays stable and switching MIX_TEST_PARTITION doesn't recompile everything.
# The same block is in each project's runtime.exs (root, cadence, cadence_web, cadence_simulator),
# because each project reads only its own.
if config_env() == :test do
  partition = System.get_env("MIX_TEST_PARTITION", "")

  config :cadence, Cadence.Repo, database: "cadence_test#{partition}"

  config :cadence, :ingress_journal,
    base_path:
      Path.join(
        System.tmp_dir!(),
        "cadence-ingress-journal-test-#{System.pid()}-#{System.get_env("MIX_TEST_PARTITION", "0")}"
      )
end
