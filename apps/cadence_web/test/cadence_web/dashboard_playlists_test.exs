defmodule CadenceWeb.DashboardPlaylistsTest do
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

  test "real empty, populated, published and unavailable models render in Vue", c do
    {:ok, empty} = Playlists.directory(c.scope, c.mission.mission_id, %{})
    {:ok, receipt} = create(c)
    {:ok, directory} = Playlists.directory(c.scope, c.mission.mission_id, %{})
    {:ok, unavailable} = present(c, receipt.id, %{})

    {:ok, _} =
      Documents.publish(c.org.organization_id, c.mission.mission_id, c.first.dashboard_id, 1, [])

    {:ok, published} = present(c, receipt.id, %{})

    renderer =
      Path.expand(
        "../../../../frontend/modules/dashboards-and-exploration/src/features/playlists/producer-render-check.mjs",
        __DIR__
      )

    node =
      System.find_executable("node") || flunk("Node is required for playlist producer contracts")

    {output, status} =
      System.cmd(
        node,
        ["--no-warnings", renderer, Jason.encode!([empty, directory, unavailable, published])],
        stderr_to_stdout: true
      )

    assert status == 0, output
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

  test "directory and lookup are bounded and use literal scoped searches", c do
    for n <- 1..28 do
      assert {:ok, _} = create(c, %{"name" => "Playlist #{n}"})

      assert {:ok, _} =
               Documents.persist(c.org.organization_id, %{
                 c.first
                 | dashboard_id: "lookup-" <> String.pad_leading(to_string(n), 2, "0"),
                   name: "Lookup #{n}"
               })
    end

    assert {:ok, first} = Playlists.directory(c.scope, c.mission.mission_id, %{})
    assert length(first.playlists.rows) == 25

    assert {:ok, next} =
             Playlists.directory(c.scope, c.mission.mission_id, %{"after" => first.playlists.next})

    assert length(next.playlists.rows) == 3
    assert next.playlists.next == nil
    assert {:ok, search} = Playlists.search(c.scope, c.mission.mission_id, %{"q" => "LOOKUP"})
    assert length(search.choices.rows) == 25

    assert {:ok, tail} =
             Playlists.search(c.scope, c.mission.mission_id, %{
               "q" => "LOOKUP",
               "after" => search.choices.next
             })

    assert length(tail.choices.rows) == 3
    assert {:ok, literal} = Playlists.search(c.scope, c.mission.mission_id, %{"q" => "%"})
    assert literal.choices.rows == []
  end

  test "presentation retains unavailable positions and never substitutes drafts", c do
    assert {:ok, receipt} =
             create(c, %{
               "dashboard_ids" => [c.first.dashboard_id, c.second.dashboard_id],
               "wallboard_mode" => true
             })

    assert {:ok, initial} = present(c, receipt.id, %{})
    assert initial.index == 0
    assert initial.playing
    assert initial.current.snapshot == nil

    assert {:ok, _} =
             Documents.publish(
               c.org.organization_id,
               c.mission.mission_id,
               c.first.dashboard_id,
               1,
               []
             )

    assert {:ok, published} = present(c, receipt.id, %{})
    assert published.current.snapshot.document_mode == "published"
    assert published.current.snapshot.document_version == 1

    assert {:ok, _} =
             Documents.update(
               c.org.organization_id,
               c.mission.mission_id,
               c.first.dashboard_id,
               %{c.first | name: "Unpublished draft"},
               expected_version: 1
             )

    assert {:ok, old_publication} = present(c, receipt.id, %{})
    assert old_publication.current.snapshot.document_version == 1
    assert old_publication.current.name == c.first.name
    assert {:ok, next} = present(c, receipt.id, %{"index" => "1", "playing" => "0"})
    assert next.current.id == c.second.dashboard_id
    refute next.playing
    :ok = Documents.archive(c.org.organization_id, c.mission.mission_id, c.first.dashboard_id, [])
    assert {:ok, archived} = present(c, receipt.id, %{})
    assert archived.current.name == nil
    assert archived.current.snapshot == nil
    assert archived.total == 2
  end

  test "presentation rejects invalid positions, foreign scope and extra context", c do
    assert {:ok, receipt} = create(c)

    for query <- [
          %{"index" => "-1"},
          %{"index" => "01"},
          %{"index" => "1"},
          %{"playing" => "true"},
          %{"mode" => "edit"}
        ] do
      assert {:error, :unavailable} = present(c, receipt.id, query)
    end

    foreign = TestFixtures.persist_mission!(c.org)

    assert {:error, :unavailable} =
             Playlists.present(c.scope, foreign.mission_id, receipt.id, %{})

    assert {:error, :unavailable} =
             Playlists.present(
               %{c.scope | mission_id: foreign.mission_id},
               c.mission.mission_id,
               receipt.id,
               %{}
             )

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

  defp present(c, id, query), do: Playlists.present(c.scope, c.mission.mission_id, id, query)
end
