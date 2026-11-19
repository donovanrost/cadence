defmodule Cadence.Reads.Administration.ConsoleRuntime do
  @moduledoc """
  Every mission's runtime for the console admin area (L7 AD4), platform administrators in admin
  mode only: the recorded runtime status (the same as `/counts` `runtime`, U38) and when the
  mission last received telemetry. Both are what this node knows: `nil` means not known here,
  never zero. Telemetry reads run at most 4 at a time and give up after 5 s per mission.
  """

  alias Cadence.Administration.{Access, ConsoleOrganizations}
  alias Cadence.Reads.{FleetStatus, MissionRuntimeStatus}

  @cap 500
  @timeout_ms 5_000

  @spec load(term()) :: {:ok, map()} | {:error, term()}
  def load(scope) do
    with {:ok, _admin} <- Access.authorize(scope) do
      missions = ConsoleOrganizations.missions(@cap)

      received = last_received(missions)

      {:ok,
       %{
         observed_at: DateTime.utc_now(),
         missions:
           Enum.map(missions, fn row ->
             Map.merge(row, %{
               runtime: MissionRuntimeStatus.status(row.organization.id, row.mission.id),
               telemetry_last_received_at: Map.get(received, row.mission.id),
               technical: []
             })
           end)
       }}
    end
  end

  defp last_received(missions) do
    missions
    |> Task.async_stream(
      fn %{organization: org, mission: mission} ->
        latest =
          org.id
          |> FleetStatus.last_received_by_spacecraft(mission.id)
          |> Map.values()
          |> Enum.max(DateTime, fn -> nil end)

        {mission.id, latest}
      end,
      max_concurrency: 4,
      timeout: @timeout_ms,
      on_timeout: :kill_task
    )
    |> Enum.flat_map(fn
      {:ok, {id, %DateTime{} = at}} -> [{id, at}]
      _unknown -> []
    end)
    |> Map.new()
  end
end
