defmodule Cadence.Reads.SpacecraftWorkspaceCostTest do
  @moduledoc """
  The spacecraft workspace read costs the same however many spacecraft the mission has (the
  per-request rule, #1049), including its P5 `systems`: they come from the catalog's telemetry
  plan, one row, read once even when the saved and active documents name the same catalog.
  """
  use Cadence.RuntimeCase, async: false

  alias Cadence.Applications.SpacecraftConfiguration.Drafts
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Catalog.SpacecraftConfigurationInput
  alias Cadence.Reads.CatalogSystems
  alias Cadence.Reads.Spacecraft.Configuration

  test "the workspace read has the same statement count at 5 and 50 spacecraft" do
    small = measure(5)
    large = measure(50)
    assert small == large, "5 spacecraft: #{small} statements, 50 spacecraft: #{large}"
  end

  test "its systems are those of the saved APIDs; a nil selection is every system" do
    {mission, craft, scope, revision} = mission_with(3)
    saved(mission, craft, scope, revision, [])

    assert {:ok, %{systems: []}} =
             Configuration.load(scope, mission, craft.spacecraft_id, "overview")

    saved(mission, craft, scope, revision, [42])

    assert {:ok, %{systems: [%{path: "/", bound: :all, apids: [42]}]}} =
             Configuration.load(scope, mission, craft.spacecraft_id, "overview")

    plan =
      CatalogSystems.telemetry_plan(
        mission.organization_id,
        mission.mission_id,
        revision.catalog_revision_id
      )

    assert [%{path: "/", bound: :all, apids: [42]}] = CatalogSystems.effective(plan, nil)
    assert CatalogSystems.effective(nil, nil) == nil
  end

  defp measure(n) do
    {mission, craft, scope, revision} = mission_with(n)
    saved(mission, craft, scope, revision, [42])

    {result, queries} =
      count(fn -> Configuration.load(scope, mission, craft.spacecraft_id, "overview") end)

    assert {:ok, %{systems: [_ | _]}} = result
    queries
  end

  defp mission_with(n) do
    suffix = System.unique_integer([:positive])
    org = "org-ws-cost-#{suffix}"
    mid = "mission-ws-cost-#{suffix}"
    {craft, revision, _endpoint} = Fixtures.setup_imported_mission!(org, mid)
    for i <- 2..n//1, do: Fixtures.persist_spacecraft!(org, mid, display_name: "Craft #{i}")
    {:ok, mission} = Cadence.Missions.fetch_mission(org, mid)
    {mission, craft, Fixtures.user_scope(org, "operator"), revision}
  end

  defp saved(mission, craft, scope, revision, apids) do
    current = Drafts.snapshot(mission, craft)

    document =
      Map.merge(SpacecraftConfigurationInput.empty(), %{
        "catalog_revision_id" => revision.catalog_revision_id,
        "handled_apids" => apids
      })

    {:ok, _} =
      Drafts.save(scope, mission.mission_id, craft.spacecraft_id, current.token, document)
  end

  defp count(fun) do
    test_pid = self()
    handler = "ws-cost-#{System.unique_integer([:positive])}"
    counter = :counters.new(1, [])

    :telemetry.attach(
      handler,
      [:cadence, :repo, :query],
      fn _event, _measurements, _metadata, _config ->
        if self() == test_pid, do: :counters.add(counter, 1, 1)
      end,
      nil
    )

    try do
      {fun.(), :counters.get(counter, 1)}
    after
      :telemetry.detach(handler)
    end
  end
end
