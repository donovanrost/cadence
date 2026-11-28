defmodule Cadence.Commanding.QueueLaneLock do
  @moduledoc "Serializes queue ordering and release admission within one database transaction."
  alias Cadence.Repo
  alias Ecto.Adapters.SQL

  @spec acquire(binary(), binary(), binary()) :: :ok
  def acquire(organization_id, mission_id, lane) do
    true = Repo.in_transaction?()

    SQL.query!(Repo, "SELECT pg_advisory_xact_lock($1::bigint)", [
      key(organization_id, mission_id, lane)
    ])

    :ok
  end

  @doc """
  `acquire/3` for many lanes in one statement (#1041): the same keys, taken in ascending key order
  by the statement that takes them (`ORDER BY key` on the very query that calls
  `pg_advisory_xact_lock`, not on a set it reads), so two transactions that lock overlapping lanes lock them in
  the same order and can't deadlock. (The single-lane `acquire/3` takes one lock, so it can't
  take part in a cycle.)
  """
  @spec acquire_all(binary(), binary(), [binary()]) :: :ok
  def acquire_all(_organization_id, _mission_id, []), do: :ok

  def acquire_all(organization_id, mission_id, lanes) do
    true = Repo.in_transaction?()
    keys = lanes |> Enum.uniq() |> Enum.map(&key(organization_id, mission_id, &1))

    SQL.query!(
      Repo,
      """
      WITH lane_keys AS MATERIALIZED (
        SELECT DISTINCT key FROM unnest($1::bigint[]) AS key
      )
      SELECT count(*)
      FROM (SELECT pg_advisory_xact_lock(key) FROM lane_keys ORDER BY key) AS locked
      """,
      [keys]
    )

    :ok
  end

  # The lock identity originally used by the sequence allocator.
  defp key(organization_id, mission_id, lane) do
    identity =
      :erlang.term_to_binary(
        {:"Elixir.Cadence.Commanding.QueueLaneSequence", organization_id, mission_id, lane}
      )

    <<key::signed-64, _rest::binary>> = :crypto.hash(:sha256, identity)
    key
  end
end
