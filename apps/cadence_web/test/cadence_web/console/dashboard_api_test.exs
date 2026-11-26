defmodule CadenceWeb.Console.DashboardAPITest do
  @moduledoc "D5: a dashboard resolved for the console viewer (docs/apogee/api/dashboards.md)."
  use CadenceWeb.ConnCase, async: false

  import CadenceWeb.OpsDashboardPageTestSupport

  alias Cadence.Dashboards.Documents
  alias CadenceWeb.TestFixtures

  setup do: dashboard_page_setup()

  defp show(c, query \\ "", user \\ nil) do
    (user || c.user)
    |> TestFixtures.member_conn()
    |> get(
      "/api/v1/missions/#{c.mission.mission_id}/dashboards/#{c.document.dashboard_id}" <>
        query
    )
  end

  test "resolves the current version with the snapshot unchanged and no private metadata", c do
    body = c |> show() |> response(200)
    data = Jason.decode!(body)["data"]

    assert %{
             "id" => id,
             "name" => name,
             "tags" => [],
             "current_version" => 1,
             "updated_at" => updated_at
           } = data["dashboard"]

    assert id == c.document.dashboard_id
    assert name == c.document.name
    assert is_binary(updated_at)
    assert Map.has_key?(data["dashboard"], "description")
    assert data["can_edit"] == true
    assert data["scope_options"] == []
    assert data["snapshot"]["name"] == c.document.name
    assert is_binary(data["resolved_at"])
    refute body =~ "private-authoring-metadata"

    save(c, %{c.document | name: "Next version"}, 1)
    data = c |> show() |> json_response(200) |> Map.fetch!("data")
    assert data["dashboard"]["current_version"] == 2
    assert data["snapshot"]["name"] == "Next version"
  end

  test "admits Grafana ranges and the mission's own spacecraft only", c do
    craft = TestFixtures.persist_spacecraft!(c.mission)

    data =
      c
      |> show("?from=now-6h&to=now&spacecraft_id=#{craft.spacecraft_id}")
      |> json_response(200)
      |> Map.fetch!("data")

    assert [%{"id" => id}] = data["scope_options"]
    assert id == craft.spacecraft_id

    assert %{"error" => %{"code" => "invalid_params", "details" => %{"field" => "spacecraft_id"}}} =
             c |> show("?spacecraft_id=someone-elses") |> json_response(422)

    assert %{"error" => %{"details" => %{"field" => "range"}}} =
             c |> show("?from=now-6h") |> json_response(422)

    assert %{"error" => %{"details" => %{"field" => "range"}}} =
             c |> show("?from=yesterday&to=now") |> json_response(422)
  end

  test "an unknown, archived or other mission's dashboard is not found", c do
    path = fn mission_id, dashboard_id ->
      "/api/v1/missions/#{mission_id}/dashboards/#{dashboard_id}"
    end

    conn = TestFixtures.member_conn(c.user)

    assert %{"error" => %{"code" => "not_found"}} =
             conn |> get(path.(c.mission.mission_id, "dashboard-nope")) |> json_response(404)

    other = TestFixtures.persist_mission!(c.org)

    assert %{"error" => %{"code" => "not_found"}} =
             conn
             |> get(path.(other.mission_id, c.document.dashboard_id))
             |> json_response(404)

    :ok =
      Documents.archive(
        c.org.organization_id,
        c.mission.mission_id,
        c.document.dashboard_id,
        []
      )

    assert %{"error" => %{"code" => "not_found"}} = c |> show() |> json_response(404)
  end

  test "another organization's member can't read it", c do
    stranger = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(stranger, TestFixtures.persist_org!())

    assert c |> show("", stranger) |> json_response(404)
  end
end
