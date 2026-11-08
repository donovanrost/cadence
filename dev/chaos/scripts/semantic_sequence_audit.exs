# Read-only check for stale writers appending an earlier semantic state.
# This detects sequence regressions; it is not a full deterministic replay audit.
import Ecto.Query

unless System.get_env("CADENCE_CHAOS_LAB") == "true" and
         System.get_env("POD_NAMESPACE") == "cadence-chaos",
       do: raise("Not the lab")

:cadence
|> Application.spec(:modules)
|> Enum.filter(&String.starts_with?(Atom.to_string(&1), "Elixir.Cadence.SemanticRuntime"))
|> Code.ensure_all_loaded()

query =
  Cadence.SemanticRuntime.CommitRow
  |> where([row], row.mission_id == "mission-earendil-demo")
  |> order_by([row],
    asc: row.partition_id,
    asc: row.runtime_basis_sha256,
    asc: row.commit_sequence
  )
  |> select([row], %{
    partition: row.partition_id,
    basis: row.runtime_basis_sha256,
    commit: row.commit_sequence,
    state: row.state_term
  })

{:ok, audit} =
  Cadence.Repo.transaction(
    fn ->
      query
      |> Cadence.Repo.stream(max_rows: 10)
      |> Enum.reduce(%{last: %{}, commits: 0, regressions: 0, examples: []}, fn row, acc ->
        state = :erlang.binary_to_term(row.state, [:safe])
        key = {row.partition, row.basis}
        prior = Map.get(acc.last, key, 0)
        regression? = state.sequence < prior

        examples =
          if regression? and length(acc.examples) < 10,
            do: [
              %{
                partition: row.partition,
                commit: row.commit,
                prior: prior,
                sequence: state.sequence
              }
              | acc.examples
            ],
            else: acc.examples

        %{
          last: Map.put(acc.last, key, state.sequence),
          commits: acc.commits + 1,
          regressions: acc.regressions + if(regression?, do: 1, else: 0),
          examples: examples
        }
      end)
    end,
    # Full-history audits grow with retained history. This is outside the timed
    # continuity window; keep the streaming audit instead of skipping old rows.
    timeout: 600_000
  )

IO.puts("LAB_SEMANTIC_AUDIT=" <> Jason.encode!(Map.delete(audit, :last)))
