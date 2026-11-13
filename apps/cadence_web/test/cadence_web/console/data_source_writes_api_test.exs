defmodule CadenceWeb.Console.DataSourceWritesAPITest do
  @moduledoc "L11 data-source writes and reads (docs/apogee/api/setup.md §Data sources (L11))."
  use CadenceWeb.ConnCase, async: false

  @moduletag :capture_log

  alias Cadence.DataSources.{DataBinding, DataSource}
  alias Cadence.Management.DataSources
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)
    %{org: org, user: user, mission: mission, conn: TestFixtures.member_conn(user)}
  end

  defp api(c, path), do: "/api/console/v1/missions/#{c.mission.mission_id}" <> path

  defp register!(c, name) do
    c.conn
    |> post(api(c, "/data-sources"), %{
      "display_name" => name,
      "logical_source" => "telemetry",
      "kind" => "managed_tsdb",
      "isolation_level" => "mission_isolated",
      "storage" => "questdb"
    })
    |> json_response(201)
    |> get_in(["data", "source"])
  end

  test "R1 options are words, with what each kind needs", c do
    data =
      c.conn |> get(api(c, "/data-sources/options")) |> json_response(200) |> Map.fetch!("data")

    assert [_ | _] = data["logical_sources"]
    assert Enum.any?(data["logical_sources"], &(&1["key"] == "telemetry"))

    assert %{"key" => "byo_tsdb", "requires_credentials" => true} =
             Enum.find(data["kinds"], &(&1["key"] == "byo_tsdb"))

    assert Enum.all?(data["isolation_levels"]["managed_tsdb"], &is_binary(&1["label"]))
  end

  test "W1 registers from a name; W2 disable/enable with 409 on the same state; D1 permissions",
       c do
    source = register!(c, "Bus history")

    assert %{
             "id" => "bus_history",
             "display_name" => "Bus history",
             "state" => "enabled",
             "shared" => false,
             "kind" => "managed_tsdb",
             "isolation_level" => "mission_isolated",
             "storage" => "questdb",
             "logical_source" => %{"key" => "telemetry"}
           } = source

    assert register!(c, "Bus history")["id"] == "bus_history_2"

    assert %{"data" => %{"source" => %{"state" => "disabled"}}} =
             c.conn |> post(api(c, "/data-sources/bus_history/disable")) |> json_response(200)

    assert %{"error" => %{"code" => "data_source_state", "details" => %{"state" => "disabled"}}} =
             c.conn |> post(api(c, "/data-sources/bus_history/disable")) |> json_response(409)

    assert %{"data" => %{"source" => %{"state" => "enabled"}}} =
             c.conn |> post(api(c, "/data-sources/bus_history/enable")) |> json_response(200)

    assert %{"data" => %{"permissions" => ["data_sources.manage"]}} =
             c.conn |> get(api(c, "/data-sources")) |> json_response(200)

    assert %{"error" => %{"details" => %{"field" => "display_name"}}} =
             c.conn
             |> post(api(c, "/data-sources"), %{"display_name" => " ", "kind" => "managed_tsdb"})
             |> json_response(422)
  end

  test "R2 shows the source with its bindings and runs; unknown is 404", c do
    register!(c, "Bus history")

    assert %{"data" => %{"source" => %{"id" => "bus_history"}, "bindings" => [], "runs" => []}} =
             c.conn |> get(api(c, "/data-sources/bus_history")) |> json_response(200)

    assert %{"error" => %{"code" => "data_source_not_found"}} =
             c.conn |> get(api(c, "/data-sources/nope")) |> json_response(404)
  end

  test "a platform-shared source is read-only for a mission operator (403 platform_source)", c do
    {:ok, _shared} =
      DataSources.persist_data_source(%DataSource{
        data_source_id: "shared_store_#{System.unique_integer([:positive])}",
        owner: :cadence,
        kind: :managed_tsdb,
        adapter: Cadence.Dashboards.Sources.Telemetry,
        isolation_level: :shared,
        capabilities: %{latest?: true},
        metadata: %{storage: :questdb}
      })

    [shared | _] =
      c.conn
      |> get(api(c, "/data-sources"))
      |> json_response(200)
      |> get_in(["data", "sources"])
      |> Enum.filter(& &1["shared"])

    assert %{"error" => %{"code" => "platform_source"}} =
             c.conn |> post(api(c, "/data-sources/#{shared["id"]}/disable")) |> json_response(403)
  end

  test "W3 switches a binding, refusing a stale expectation (409 binding_changed)", c do
    register!(c, "Primary")
    register!(c, "Secondary")

    {:ok, _binding} =
      DataSources.persist_data_binding(%DataBinding{
        binding_id: "binding-#{System.unique_integer([:positive])}",
        organization_id: c.org.organization_id,
        mission_id: c.mission.mission_id,
        realm: "flight",
        logical_source: :telemetry,
        data_source_id: "primary"
      })

    [binding] =
      c.conn
      |> get(api(c, "/data-sources/primary"))
      |> json_response(200)
      |> get_in(["data", "bindings"])

    path = api(c, "/data-source-bindings/#{binding["id"]}")

    assert %{
             "error" => %{
               "code" => "binding_changed",
               "details" => %{"current_data_source_id" => "primary"}
             }
           } =
             c.conn
             |> put(path, %{"data_source_id" => "secondary", "expected_data_source_id" => "other"})
             |> json_response(409)

    assert %{"data" => %{"binding" => %{"data_source_id" => "secondary", "status" => "active"}}} =
             c.conn
             |> put(path, %{
               "data_source_id" => "secondary",
               "expected_data_source_id" => "primary"
             })
             |> json_response(200)
  end
end
