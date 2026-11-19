defmodule CadenceWeb.DashboardActivityReadTest do
  @moduledoc """
  `Reads.Dashboards.Activity`: history, restore and paging. Moved from the legacy activity page's
  test when L8b deleted the page; the console's D17 reads it (`console/dashboard_settings_api_test`).
  """
  use CadenceWeb.ConnCase, async: false
  alias Cadence.Auth.Scope
  alias Cadence.Dashboards.{CurrentVersions, DocumentCodec, Documents}
  alias Cadence.Reads.Dashboards.Activity
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
        dashboard_id: "activity-" <> Ecto.UUID.generate()
    }

    {:ok, document} = Documents.persist(org.organization_id, document)

    %{
      org: org,
      user: user,
      mission: mission,
      scope: scope,
      document: document
    }
  end

  test "history reads producer metadata without raw documents or event payloads", c do
    {:ok, first} = read(c)
    assert first.document_version == 1
    assert first.selected.widget_count == length(c.document.placements)

    assert {:ok, _} =
             Documents.publish(
               c.org.organization_id,
               c.mission.mission_id,
               c.document.dashboard_id,
               1,
               expected_version: 1,
               published_by: c.user.user_id
             )

    {:ok, published} = read(c)
    assert published.published_version == 1
    assert [%{event_type: "published", actor_id: actor}] = published.events
    assert actor == c.user.user_id
    refute Map.has_key?(published.selected, :document)
    refute Map.has_key?(hd(published.events), :payload)

    :ok =
      Documents.archive(c.org.organization_id, c.mission.mission_id, c.document.dashboard_id,
        actor_id: actor
      )

    {:ok, archived} = read(c)
    assert archived.archived
  end

  test "restore appends an attributed snapshot that becomes current and keeps old content", c do
    {:ok, _} =
      CurrentVersions.save(
        c.org.organization_id,
        c.mission.mission_id,
        c.document.dashboard_id,
        %{c.document | name: "Different"},
        expected_version: 1,
        created_by: c.user.user_id
      )

    assert {:ok, _} = restore(c, 1)
    {:ok, restored} = read(c)
    assert restored.document_version == 3
    assert restored.published_version == 3
    [third, second, first] = restored.versions
    assert third.kind == "publish"
    assert third.parent_version == 2
    assert third.based_on_version == 1
    assert third.actor_id == c.user.user_id
    assert second.version == 2
    assert first.version == 1

    {:ok, current} =
      Documents.fetch(c.org.organization_id, c.mission.mission_id, c.document.dashboard_id)

    assert current.name == c.document.name

    {:ok, old} =
      Documents.fetch_version(
        c.org.organization_id,
        c.mission.mission_id,
        c.document.dashboard_id,
        2
      )

    assert old.document.name == "Different"
  end

  test "bounded history pages have scoped cursors and no duplicates", c do
    for _ <- 1..27 do
      {:ok, current} = read(c)
      assert {:ok, _} = restore(c, 1, current.document_version)
    end

    {:ok, first} = read(c)
    assert length(first.versions) == 25
    assert length(first.events) == 25
    assert first.next_version == 4

    {:ok, second} =
      read(c, %{
        "version" => "1",
        "before_version" => to_string(first.next_version),
        "before_event" => first.next_event
      })

    assert Enum.map(second.versions, & &1.version) == [3, 2, 1]
    assert second.events != []
    assert second.next_version == nil
    assert MapSet.disjoint?(MapSet.new(first.events, & &1.id), MapSet.new(second.events, & &1.id))
    assert {:error, :unavailable} = read(c, %{"before_event" => "missing"})
    other = %{c.document | dashboard_id: "other-" <> Ecto.UUID.generate()}
    {:ok, _} = Documents.persist(c.org.organization_id, other)

    assert {:error, :unavailable} =
             Activity.load(c.scope, c.mission.mission_id, other.dashboard_id, %{
               "before_event" => first.next_event
             })
  end

  test "invalid queries and foreign or unauthenticated scopes cannot read history", c do
    for query <- [
          %{"version" => "01"},
          %{"version" => "2"},
          %{"version" => 1},
          %{"before_version" => "0"},
          %{"extra" => "x"},
          %{"before_event" => []}
        ] do
      assert {:error, :unavailable} = read(c, query)
    end

    for scope <- [
          %{c.scope | user: nil},
          %{c.scope | organization_membership: nil},
          %{c.scope | mission_id: "foreign"},
          %{c.scope | organization_id: "foreign"}
        ] do
      assert {:error, _} = Activity.load(scope, c.mission.mission_id, c.document.dashboard_id)
    end
  end

  defp read(c, params \\ %{"version" => "1"}),
    do: Activity.load(c.scope, c.mission.mission_id, c.document.dashboard_id, params)

  defp restore(c, version, expected \\ nil) do
    expected = expected || fetch_version!(c)

    CurrentVersions.restore(
      c.org.organization_id,
      c.mission.mission_id,
      c.document.dashboard_id,
      version,
      expected_version: expected,
      created_by: c.user.user_id
    )
  end

  defp fetch_version!(c) do
    {:ok, current} = read(c)
    current.document_version
  end
end
