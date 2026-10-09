defmodule Cadence.Dashboards.CurrentVersionsTest do
  use Cadence.DataCase, async: false

  import Cadence.Dashboards.DocumentStoreFixtures

  alias Cadence.Dashboards
  alias Cadence.Dashboards.{CurrentVersions, Document, RuntimeCache, RuntimeInvalidation}

  @org "org-current-versions"
  @mission "mission-current-versions"
  @dashboard "dashboard-current-versions"

  setup do
    RuntimeCache.reset()
    on_exit(fn -> RuntimeCache.reset() end)
    persist_mission_scope(@org, @mission)

    document =
      "value_tile_latest.v1.json"
      |> load_fixture!()
      |> scope_document(@org, @mission, @dashboard)

    %{document: document}
  end

  test "created, saved and restored versions are each current immediately", %{document: document} do
    :ok =
      RuntimeInvalidation.subscribe(%{
        organization_id: @org,
        mission_id: @mission,
        dashboard_id: @dashboard
      })

    assert {:ok, created} = CurrentVersions.create(@org, document, created_by: "user-1")
    assert summary().published_version == 1
    assert_receive {:dashboard_runtime_invalidated, _}

    assert {:ok, saved} =
             CurrentVersions.save(@org, @mission, @dashboard, %{created | name: "Second"},
               expected_version: 1,
               created_by: "user-1",
               change_summary: "Rename"
             )

    assert Document.version(saved) == 2
    assert %{published_version: 2, latest_version: 2, draft_version: nil} = summary()

    assert {:ok, %Document{name: "Second"}} =
             Dashboards.fetch_published_document(@org, @mission, @dashboard)

    assert {:ok, restored} =
             CurrentVersions.restore(@org, @mission, @dashboard, 1,
               expected_version: 2,
               created_by: "user-2"
             )

    assert restored.version == 3
    assert restored.based_on_version == 1
    assert restored.change_summary == "Restored from version 1"
    assert %{published_version: 3, latest_version: 3} = summary()

    assert {:ok, %Document{name: name}} =
             Dashboards.fetch_published_document(@org, @mission, @dashboard)

    assert name == document.name
  end

  test "a stale save writes nothing", %{document: document} do
    {:ok, created} = CurrentVersions.create(@org, document)

    assert {:error, {:dashboard_version_conflict, 1}} =
             CurrentVersions.save(@org, @mission, @dashboard, %{created | name: "Stale"},
               expected_version: 7
             )

    assert %{published_version: 1, latest_version: 1} = summary()
    assert length(Dashboards.list_versions(@org, @mission, @dashboard)) == 1
  end

  defp summary do
    @org
    |> Dashboards.list_dashboard_summaries(@mission)
    |> Enum.find(&(&1.dashboard_id == @dashboard))
  end
end
