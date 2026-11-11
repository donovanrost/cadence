defmodule Cadence.Telemetry.PointLatest do
  @moduledoc """
  Durable latest sample per point for one spacecraft, read from the telemetry history store.

  The live current-value store is ephemeral (ETS by default) and starts empty after a restart,
  so it can't answer "what did this point last read?" until the spacecraft sends telemetry
  again. The history store is durable, so this answers it the way `SpacecraftReceipts`
  answers "last heard":
  - QuestDB: `LATEST ON observed_at PARTITION BY point_id`.
  - Postgres sample store: the newest receipt per point.
  - Other backends: `{:error, :unsupported}`, and callers keep live data only.
  """

  alias Cadence.Telemetry.{HistoryStore, Sample, SampleRecords}
  alias Cadence.Telemetry.Storage.QuestDB.{ObservationReader, RestClient, SQL}

  @spec for_spacecraft(binary(), binary(), binary(), [binary()], keyword()) ::
          {:ok, [Sample.t()]} | {:error, term()}
  def for_spacecraft(organization_id, mission_id, spacecraft_id, point_ids, opts \\ [])

  def for_spacecraft(_organization_id, _mission_id, _spacecraft_id, [], _opts), do: {:ok, []}

  def for_spacecraft(organization_id, mission_id, spacecraft_id, point_ids, opts) do
    policy = Keyword.get_lazy(opts, :policy, &HistoryStore.configured_policy/0)
    scope = {organization_id, mission_id, spacecraft_id, point_ids}

    case policy.backend do
      HistoryStore.QuestDB ->
        questdb(scope, policy.backend_opts)

      HistoryStore.Postgres ->
        {:ok,
         SampleRecords.latest_by_point(organization_id, mission_id, spacecraft_id, point_ids)}

      _other ->
        {:error, :unsupported}
    end
  end

  defp questdb({organization_id, mission_id, spacecraft_id, point_ids}, backend_opts) do
    sql = """
    SELECT #{Enum.join(ObservationReader.select_columns(), ", ")}
    FROM telemetry_observations
    WHERE mission_id = #{SQL.literal(mission_id)}
      AND organization_id = #{SQL.literal(organization_id)}
      AND spacecraft_id = #{SQL.literal(spacecraft_id)}
      AND realm = 'flight'
      AND point_id IN (#{Enum.map_join(point_ids, ", ", &SQL.literal/1)})
    LATEST ON observed_at PARTITION BY point_id
    """

    with {:ok, %{"columns" => columns, "dataset" => rows}} <- RestClient.exec(sql, backend_opts) do
      names = Enum.map(columns, & &1["name"])

      {:ok,
       Enum.map(
         rows,
         &(names |> Enum.zip(&1) |> Map.new() |> ObservationReader.sample_from_row())
       )}
    end
  end
end
