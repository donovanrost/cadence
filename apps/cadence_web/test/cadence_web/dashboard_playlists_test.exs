defmodule CadenceWeb.DashboardPlaylistsTest do
  @moduledoc """
  Playlist authoring and the directory read. L8b removed `Playlists.present/search` (only the
  legacy page called them) with their cases, and the playlists feature's producer check.
  """
  use CadenceWeb.ConnCase, async: false
  alias Cadence.Auth.Scope

  alias Cadence.Dashboards.{
    DocumentCodec,
    Documents,
    Management,
    PlaylistAuthoring,
    PlaylistInput
  }

  alias Cadence.Reads.Dashboards.Playlists
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

    {:ok, first} =
      Documents.persist(org.organization_id, %{
        base
        | organization_id: org.organization_id,
          mission_id: mission.mission_id,
          dashboard_id: "playlist-dashboard-a"
      })

    {:ok, second} =
      Documents.persist(org.organization_id, %{
        first
        | dashboard_id: "playlist-dashboard-b",
          name: "Second dashboard"
      })

    %{org: org, user: user, mission: mission, scope: scope, first: first, second: second}
  end

  test "creation preserves order and repeats with actor attribution", c do
    ids = [c.second.dashboard_id, c.first.dashboard_id, c.second.dashboard_id]
    assert {:ok, receipt} = create(c, %{"dashboard_ids" => ids})
    assert receipt.count == 3

    assert {:ok, playlist} =
             Management.fetch_playlist(c.org.organization_id, c.mission.mission_id, receipt.id)

    assert playlist.dashboard_ids == ids
    assert playlist.created_by == c.user.user_id
    assert playlist.wallboard_mode == false
    assert {:ok, directory} = Playlists.directory(c.scope, c.mission.mission_id, %{})
    assert [%{id: id, count: 3}] = directory.playlists.rows
    assert id == receipt.id
    refute Map.has_key?(hd(directory.playlists.rows), :dashboard_ids)
  end

  test "malformed fields and foreign or archived dashboard references cannot persist", c do
    for fields <- [
          %{"dashboard_ids" => []},
          %{"dashboard_ids" => List.duplicate(c.first.dashboard_id, 101)},
          %{"dashboard_ids" => [42]},
          %{"dwell_seconds" => 4},
          %{"dwell_seconds" => 901},
          %{"wallboard_mode" => "true"},
          %{"created_by" => "forged"}
        ] do
      assert {:error, :invalid_input} = create(c, fields)
    end

    mission = TestFixtures.persist_mission!(c.org)

    {:ok, foreign} =
      Documents.persist(c.org.organization_id, %{
        c.first
        | mission_id: mission.mission_id,
          dashboard_id: "foreign-dashboard"
      })

    assert {:error, :invalid_dashboard} = create(c, %{"dashboard_ids" => [foreign.dashboard_id]})
    :ok = Documents.archive(c.org.organization_id, c.mission.mission_id, c.first.dashboard_id, [])
    assert {:error, :invalid_dashboard} = create(c)
    assert Management.list_playlists(c.org.organization_id, c.mission.mission_id) == []

    assert {:error, :forbidden} =
             PlaylistAuthoring.create(
               %{c.scope | mission_id: mission.mission_id},
               c.mission.mission_id,
               fields(c)
             )
  end

  test "the directory is bounded and pages with a scoped cursor", c do
    for n <- 1..28 do
      assert {:ok, _} = create(c, %{"name" => "Playlist #{n}"})
    end

    assert {:ok, first} = Playlists.directory(c.scope, c.mission.mission_id, %{})
    assert length(first.playlists.rows) == 25

    assert {:ok, next} =
             Playlists.directory(c.scope, c.mission.mission_id, %{"after" => first.playlists.next})

    assert length(next.playlists.rows) == 3
    assert next.playlists.next == nil
    assert {:error, :invalid_input} = PlaylistInput.query(%{"after" => 1})
  end

  defp fields(c),
    do: %{
      "name" => "Flight rotation",
      "description" => "Operations",
      "dashboard_ids" => [c.first.dashboard_id],
      "dwell_seconds" => 30,
      "wallboard_mode" => false
    }

  defp create(c, patch \\ %{}),
    do: PlaylistAuthoring.create(c.scope, c.mission.mission_id, Map.merge(fields(c), patch))
end
