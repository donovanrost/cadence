defmodule Cadence.Commanding.QueueLaneLock do
  @moduledoc "Serializes queue ordering and release admission within one database transaction."
  alias Cadence.Repo
  alias Ecto.Adapters.SQL

  @spec acquire(binary(), binary(), binary()) :: :ok
  def acquire(organization_id, mission_id, lane) do
    true = Repo.in_transaction?()
    # Preserve the lock identity originally used by the sequence allocator.
    identity =
      :erlang.term_to_binary(
        {:"Elixir.Cadence.Commanding.QueueLaneSequence", organization_id, mission_id, lane}
      )

    <<key::signed-64, _rest::binary>> = :crypto.hash(:sha256, identity)
    SQL.query!(Repo, "SELECT pg_advisory_xact_lock($1::bigint)", [key])
    :ok
  end
end
