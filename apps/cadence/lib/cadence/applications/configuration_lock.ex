defmodule Cadence.Applications.ConfigurationLock do
  @moduledoc "Serializes mission application configuration reads and writes in one transaction."

  alias Cadence.Repo
  alias Ecto.Adapters.SQL

  @spec run(binary(), binary(), (-> result)) :: result | {:error, term()} when result: term()
  def run(organization_id, mission_id, operation, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_function(operation, 0) do
    identity = :erlang.term_to_binary({__MODULE__, organization_id, mission_id})
    <<key::signed-64, _rest::binary>> = :crypto.hash(:sha256, identity)

    case Repo.transaction(
           fn ->
             SQL.query!(Repo, "SELECT pg_advisory_xact_lock($1::bigint)", [key])

             complete_operation(operation.())
           end,
           opts
         ) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp complete_operation({:error, reason}), do: Repo.rollback(reason)
  defp complete_operation(result), do: result
end
