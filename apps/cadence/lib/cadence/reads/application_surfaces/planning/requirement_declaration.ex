defmodule Cadence.Reads.ApplicationSurfaces.Planning.RequirementDeclaration do
  @moduledoc "Authorized declaration defaults and bounded spacecraft choices."
  alias Cadence.Auth.Policy
  alias Cadence.Missions
  alias Cadence.SpacecraftStore

  def initial_horizon do
    starts = DateTime.utc_now() |> DateTime.add(900, :second) |> DateTime.truncate(:second)

    %{
      earliest_start: DateTime.to_iso8601(starts),
      latest_end: starts |> DateTime.add(86_400, :second) |> DateTime.to_iso8601()
    }
  end

  def load(scope, mission, horizon, page) do
    with {:ok, spacecraft} <- choices(scope, mission, page) do
      {:ok,
       %{
         contract_version: 1,
         context: %{
           organization_id: scope.organization_id,
           mission_id: mission,
           actor_id: scope.user.user_id
         },
         horizon: horizon,
         spacecraft: spacecraft,
         can_declare: spacecraft.total > 0
       }}
    end
  end

  def choices(scope, mission, page) when is_integer(page) and page in 1..1_000_000 do
    with true <- is_nil(scope.mission_id) or scope.mission_id == mission,
         :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission
           }),
         {:ok, _} <- Missions.fetch_mission(scope.organization_id, mission) do
      result =
        SpacecraftStore.list_spacecraft_page(scope.organization_id, mission,
          page: page,
          page_size: 25
        )

      {:ok,
       %{
         page: result.page,
         total: result.total_count,
         entries: Enum.map(result.items, &%{id: &1.spacecraft_id, name: &1.display_name})
       }}
    else
      false -> {:error, :scope_mismatch}
      error -> error
    end
  end

  def choices(_, _, _), do: {:error, :invalid_page}
end
