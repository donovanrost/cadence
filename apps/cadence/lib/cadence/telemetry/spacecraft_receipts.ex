defmodule Cadence.Telemetry.SpacecraftReceipts do
  @moduledoc """
  Durable "last heard" per spacecraft, read from the telemetry history store.

  The live current-value store is ephemeral by design (ETS by default), so it
  can't answer "has this spacecraft ever been heard?" after a restart. The
  history store is durable: QuestDB answers with `LATEST ON` per spacecraft
  symbol; the Postgres sample store with a grouped max. Other backends return
  `{:error, :unsupported}`, and callers fall back to live data.
  """

  alias Cadence.Telemetry.HistoryStore
  alias Cadence.Telemetry.SampleRecords
  alias Cadence.Telemetry.Storage.QuestDB.{RestClient, SQL}

  @spec latest_by_spacecraft(binary(), binary(), keyword()) ::
          {:ok, %{binary() => DateTime.t()}} | {:error, term()}
  def latest_by_spacecraft(organization_id, mission_id, opts \\ []) do
    policy = Keyword.get_lazy(opts, :policy, &HistoryStore.configured_policy/0)

    case policy.backend do
      HistoryStore.QuestDB -> questdb(organization_id, mission_id, policy.backend_opts)
      HistoryStore.Postgres -> postgres(organization_id, mission_id)
      _other -> {:error, :unsupported}
    end
  end

  defp questdb(organization_id, mission_id, backend_opts) do
    sql = """
    SELECT spacecraft_id, receipt_time
    FROM telemetry_observations
    WHERE mission_id = #{SQL.literal(mission_id)}
      AND organization_id = #{SQL.literal(organization_id)}
      AND realm = 'flight'
    LATEST ON observed_at PARTITION BY spacecraft_id
    """

    with {:ok, %{"columns" => columns, "dataset" => rows}} <- RestClient.exec(sql, backend_opts) do
      names = Enum.map(columns, & &1["name"])

      {:ok,
       rows
       |> Enum.map(&Map.new(Enum.zip(names, &1)))
       |> Enum.flat_map(fn
         %{"spacecraft_id" => id, "receipt_time" => at} when is_binary(id) and is_binary(at) ->
           case DateTime.from_iso8601(at) do
             {:ok, datetime, _offset} -> [{id, datetime}]
             _invalid -> []
           end

         _missing ->
           []
       end)
       |> Map.new()}
    end
  end

  defp postgres(organization_id, mission_id),
    do: {:ok, SampleRecords.latest_receipts_by_spacecraft(organization_id, mission_id)}
end
