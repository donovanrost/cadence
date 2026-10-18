defmodule Cadence.Limits.DefinitionLock do
  @moduledoc false

  alias Cadence.Repo
  alias Ecto.Adapters.SQL

  # Include every activation realm in the same point/set lock. Definition
  # versions are shared across those realms, even when their active pointers differ.
  def run(organization_id, mission_id, point_id, limit_set_name, operation) do
    <<key::signed-64, _::binary>> =
      :crypto.hash(
        :sha256,
        :erlang.term_to_binary(
          {__MODULE__, organization_id, mission_id, point_id, limit_set_name}
        )
      )

    Repo.transaction(fn ->
      SQL.query!(Repo, "SELECT pg_advisory_xact_lock($1::bigint)", [key])
      operation.()
    end)
  end
end
