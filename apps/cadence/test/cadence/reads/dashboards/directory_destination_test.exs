defmodule Cadence.Reads.Dashboards.DirectoryDestinationTest do
  use Cadence.DataCase, async: false
  alias Cadence.Applications.{HostContext, SurfaceQueryRequest}
  alias Cadence.Applications.OpsConsole, as: OpsDefinition
  alias Cadence.Auth.Scope
  alias Cadence.Reads.ApplicationSurfaces.OpsConsole
  alias Cadence.Reads.Dashboards.Directory

  @org "org-directory-destination"
  @mission "mission-directory-destination"
  @probe Path.expand(
           "../../../../../../frontend/modules/dashboards-and-exploration/src/features/directory/destination-producer-check.mjs",
           __DIR__
         )
  setup do
    persist_mission_scope(@org, @mission)

    %{
      scope: %Scope{
        actor_kind: :user,
        user: %{user_id: "directory-operator"},
        organization_id: @org,
        organization_membership: %{lifecycle_state: :active}
      }
    }
  end

  test "published queries preserve the canonical admitted filters through the actual consumer",
       c do
    models =
      for params <- [
            %{},
            %{
              "query" => "Flight /?&+",
              "lifecycle" => "archived",
              "sort" => "name",
              "tag" => "thermal & power",
              "page" => "2"
            },
            %{"lifecycle" => "all", "sort" => "widgets"}
          ] do
        assert {:ok, canonical} = Directory.load(c.scope, @mission, params)
        assert {:ok, response} = load(c.scope, params)

        assert %{"component" => "OpsDashboardDirectory", "props" => %{"model" => model}} =
                 response["data"]["presentation"]

        assert model["version"] == 1
        assert model["context"] == %{"organization_id" => @org, "mission_id" => @mission}
        assert model["filters"] == canonical.filters
        model
      end

    {output, status} = System.cmd("node", [@probe, Jason.encode!(models)], stderr_to_stdout: true)
    assert status == 0, output
    assert output =~ "DIRECTORY_DESTINATION_CONSUMER_OK"
  end

  test "durable surface and actions retain their identities with explicit filter admission" do
    spec = Enum.find(OpsDefinition.surface_specs(), &(&1.id == "dashboard_directory"))
    assert spec.path == "/missions/:mission_id/ops/dashboards"
    assert spec.query_params == ~w(query lifecycle tag sort page)
    assert spec.actions == ~w(filter_dashboards toggle_dashboard_star restore_dashboard)
  end

  test "invalid filters and extraneous params do not produce a destination", c do
    for params <- [
          %{"sort" => "other"},
          %{"lifecycle" => "other"},
          %{"page" => "0"},
          %{"page" => "1000001"},
          %{"page" => "1.2"},
          %{"query" => String.duplicate("x", 513)},
          %{"query" => []},
          %{"redirect" => "//foreign"},
          %{"mission_id" => "foreign"}
        ] do
      assert {:error, :unsupported_application_surface_query} = load(c.scope, params)
    end
  end

  test "missing actor, inactive membership and foreign scope cannot expose navigation", c do
    for scope <- [
          %Scope{},
          %{c.scope | user: nil},
          %{c.scope | mission_id: "foreign"},
          %{c.scope | organization_id: "foreign"},
          %{c.scope | organization_membership: %{lifecycle_state: :inactive}}
        ] do
      assert {:error, :unsupported_application_surface_query} = load(scope, %{})
    end
  end

  defp load(scope, params),
    do:
      OpsConsole.load(scope, HostContext.mission(@mission), %SurfaceQueryRequest{
        application_key: "ops_console",
        application_version: 1,
        surface_id: "dashboard_directory",
        surface_version: 1,
        query_id: "cadence.ops.dashboard_directory",
        query_version: 1,
        params: params
      })
end
