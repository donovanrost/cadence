defmodule CadenceWeb.DashboardQ6Test do
  @moduledoc """
  Dashboards Q6 (DECISIONS #76): playlist update and delete, library update and retire (Q10),
  snapshot create with a frozen window and delete (tombstone), D14-D16 creators and windows,
  add_library_widget, and the audit lines for each.
  """
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Auth.Scope

  alias Cadence.Dashboards.{
    ConfigAudit,
    DocumentCodec,
    Documents,
    LibraryAuthoring,
    LibraryLifecycle,
    Management,
    PlaylistAuthoring,
    Snapshots,
    StatelessAuthoring,
    WidgetDef
  }

  alias Cadence.Reads.Dashboards.{Settings, SharedViews}
  alias CadenceWeb.TestFixtures

  @fixture Path.expand(
             "../../../cadence/test/fixtures/dashboards/value_tile_latest.v1.json",
             __DIR__
           )

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)

    scope =
      Scope.new(%{
        user: user,
        organization_id: org.organization_id,
        organization_membership: membership
      })

    base = DocumentCodec.load!(@fixture)

    document = %{
      base
      | organization_id: org.organization_id,
        mission_id: mission.mission_id,
        dashboard_id: "q6-" <> Ecto.UUID.generate()
    }

    {:ok, document} = Documents.persist(org.organization_id, document)
    widget = hd(document.placements).widget_def |> WidgetDef.to_map()

    %{
      org: org.organization_id,
      user: user,
      mission: mission.mission_id,
      scope: scope,
      document: document,
      json: Jason.encode!(widget)
    }
  end

  describe "library (Q10)" do
    test "a placed item can't retire; once unplaced it retires, leaves the listing and can't be placed",
         c do
      {:ok, %{item_id: item}} = library(c, "create_item", creation(c))

      # Placed by reference through the editor's command.
      assert {:ok, %{version: 2}} = save(c, 1, [place(item, 1, "dash_widget_power")])

      assert {:error,
              {:library_item_in_use,
               %{
                 consumer_count: 1,
                 used_by: %{dashboards: [%{id: id, placements: 1, pinned_versions: [1]}]}
               }}} = LibraryLifecycle.retire_item(c.scope, c.mission, item, 1)

      assert id == c.document.dashboard_id

      # A stale guard says what it is now.
      assert {:error, {:library_item_changed, 1}} =
               LibraryLifecycle.retire_item(c.scope, c.mission, item, 2)

      assert {:ok, %{version: 3}} =
               save(c, 2, [
                 %{
                   "event" => "remove_widget",
                   "input" => %{"placement_id" => "dash_widget_power"}
                 }
               ])

      assert :ok = LibraryLifecycle.retire_item(c.scope, c.mission, item, 1)

      refute Enum.any?(
               Management.list_library_items(c.org, c.mission),
               &(&1.dashboard_library_item_id == item)
             )

      # Its versions still resolve for old dashboard versions; new placements are refused.
      assert {:ok, _version} = Management.fetch_library_version(c.org, c.mission, item, 1)

      assert {:error, {:command, 0, :library_item_unavailable, "library_item_id"}} =
               save(c, 3, [place(item, 1, "dash_widget_again")])

      assert [%{action: "Retired library widget Power", target: %{kind: "library_item"}}] =
               ConfigAudit.list(c.org, c.mission)
    end

    test "rename guards on the latest version; an unknown version is the command's field error",
         c do
      {:ok, %{item_id: item}} = library(c, "create_item", creation(c))

      assert {:ok, %{name: "Battery"}} =
               LibraryLifecycle.update_item(c.scope, c.mission, item, %{"name" => " Battery "}, 1)

      assert {:error, {:library_item_changed, 1}} =
               LibraryLifecycle.update_item(c.scope, c.mission, item, %{"name" => "Late"}, 2)

      assert {:error, :invalid_input} =
               LibraryLifecycle.update_item(c.scope, c.mission, item, %{"name" => " "}, 1)

      assert {:error, {:command, 0, :library_version_unavailable, "version"}} =
               save(c, 1, [place(item, 9, "dash_widget_v9")])
    end
  end

  describe "playlists" do
    test "update guards on updated_at, checks dashboards, and delete is audited", c do
      {:ok, %{id: id}} =
        PlaylistAuthoring.create(c.scope, c.mission, %{
          "name" => "Ops wall",
          "description" => "",
          "dashboard_ids" => [c.document.dashboard_id],
          "dwell_seconds" => 30,
          "wallboard_mode" => false
        })

      {:ok, playlist} = Management.fetch_playlist(c.org, c.mission, id)
      stale = DateTime.add(playlist.updated_at, -1, :microsecond)

      assert {:error, {:stale, %{name: "Ops wall"}}} =
               PlaylistAuthoring.update(c.scope, c.mission, id, %{"name" => "Late"}, stale)

      assert {:error, {:invalid_dashboard, ["missing-dashboard"]}} =
               PlaylistAuthoring.update(
                 c.scope,
                 c.mission,
                 id,
                 %{"dashboard_ids" => ["missing-dashboard"]},
                 playlist.updated_at
               )

      assert {:ok, %{name: "Night wall", dwell_seconds: 60}} =
               PlaylistAuthoring.update(
                 c.scope,
                 c.mission,
                 id,
                 %{"name" => "Night wall", "dwell_seconds" => 60},
                 playlist.updated_at
               )

      assert :ok = PlaylistAuthoring.delete(c.scope, c.mission, id)
      assert {:error, :not_found} = PlaylistAuthoring.delete(c.scope, c.mission, id)

      assert [
               "Deleted playlist Night wall",
               "Updated playlist Night wall",
               "Created playlist Ops wall"
             ] =
               c.org |> ConfigAudit.list(c.mission) |> Enum.map(& &1.action)
    end
  end

  describe "snapshots (D14-D16, Q5/Q6)" do
    test "a console snapshot freezes its window; rows say who and when; delete leaves a tombstone",
         c do
      runtime = %{"from" => "2026-11-13T06:00:00Z", "to" => "2026-11-13T12:00:00Z"}

      assert {:error, {:invalid, %{"runtime.to" => _}}} =
               Snapshots.create(c.scope, c.mission, c.document.dashboard_id, %{
                 "data_visibility" => "definition_only",
                 "runtime" => %{runtime | "to" => runtime["from"]}
               })

      assert {:error, {:invalid, %{"runtime.from" => _}}} =
               Snapshots.create(c.scope, c.mission, c.document.dashboard_id, %{
                 "data_visibility" => "definition_only",
                 "runtime" => Map.delete(runtime, "from")
               })

      assert {:ok, snapshot} =
               Snapshots.create(c.scope, c.mission, c.document.dashboard_id, %{
                 "data_visibility" => "definition_only",
                 "runtime" => Map.put(runtime, "spacecraft_id", nil)
               })

      {:ok, model} = Settings.load(c.scope, c.mission, c.document.dashboard_id)

      assert [
               %{
                 window: %{from: "2026-11-13T06:00:00Z", to: "2026-11-13T12:00:00Z"},
                 created_by: %{id: user_id, kind: "user", name: name}
               }
             ] = model.snapshots.rows

      assert user_id == c.user.user_id and is_binary(name)

      assert :ok = Snapshots.delete(c.scope, c.mission, snapshot.dashboard_snapshot_id)

      assert {:error, :not_found} =
               Snapshots.delete(c.scope, c.mission, snapshot.dashboard_snapshot_id)

      assert {:error, :dashboard_snapshot_deleted} =
               Management.fetch_snapshot(c.org, c.mission, snapshot.dashboard_snapshot_id)

      assert {:error, :snapshot_deleted} =
               SharedViews.load(c.scope, c.mission, :snapshot, snapshot.dashboard_snapshot_id)

      {:ok, model} = Settings.load(c.scope, c.mission, c.document.dashboard_id)
      assert model.snapshots.rows == []

      assert [%{action: "Deleted snapshot of " <> _}] = ConfigAudit.list(c.org, c.mission)
    end
  end

  defp place(item, version, placement),
    do: %{
      "event" => "add_library_widget",
      "input" => %{
        "placement_id" => placement,
        "library_item_id" => item,
        "version" => version,
        "section_id" => ""
      }
    }

  defp save(c, base, commands),
    do: StatelessAuthoring.save(c.scope, c.mission, c.document.dashboard_id, base, commands, nil)

  defp creation(c),
    do: %{
      "name" => "Power",
      "description" => "Reusable power tile",
      "change_summary" => "Initial",
      "widget_json" => c.json
    }

  defp library(c, event, input), do: LibraryAuthoring.execute(c.scope, c.mission, event, input)
end
