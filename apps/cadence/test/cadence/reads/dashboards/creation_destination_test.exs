defmodule Cadence.Reads.Dashboards.CreationDestinationTest do
  use Cadence.DataCase, async: false

  alias Cadence.Applications.{HostContext, SurfaceQueryRequest}
  alias Cadence.Applications.OpsConsole, as: OpsDefinition
  alias Cadence.Auth.Scope
  alias Cadence.Dashboards.{Document, Documents}
  alias Cadence.Reads.ApplicationSurfaces.OpsConsole

  @org "org-creation-destination"
  @mission "mission-creation-destination"
  @probe Path.expand(
           "../../../../../../frontend/modules/dashboards-and-exploration/src/features/creation/destination-producer-check.mjs",
           __DIR__
         )

  setup do
    persist_mission_scope(@org, @mission)

    {:ok, source} =
      Documents.persist(@org, %Document{
        organization_id: @org,
        mission_id: @mission,
        dashboard_id: "source-creation-destination",
        name: "Flight"
      })

    scope = %Scope{
      actor_kind: :user,
      user: %{user_id: "creation-operator"},
      organization_id: @org,
      organization_membership: %{lifecycle_state: :active}
    }

    %{scope: scope, source: source}
  end

  test "published queries render each canonical creation mode through the actual owner", c do
    models =
      for params <- [
            %{},
            %{"mode" => "new"},
            %{"mode" => "import"},
            %{"mode" => "clone", "source_dashboard_id" => c.source.dashboard_id}
          ] do
        assert {:ok, response} = load(c.scope, params)

        assert %{"component" => "OpsDashboardNew", "props" => %{"model" => model}} =
                 response["data"]["presentation"]

        assert model["version"] == 1
        assert model["context"] == %{"organization_id" => @org, "mission_id" => @mission}
        assert model["mode"] == Map.get(params, "mode", "new")
        assert model["source_dashboard_id"] == params["source_dashboard_id"]
        model
      end

    {output, status} = System.cmd("node", [@probe, Jason.encode!(models)], stderr_to_stdout: true)
    assert status == 0, output
    assert output =~ "CREATION_DESTINATION_CONSUMER_OK"
    assert length(Documents.list(@org, @mission)) == 1
  end

  test "the durable surface and bounded query contract retain compatibility action identities" do
    spec = Enum.find(OpsDefinition.surface_specs(), &(&1.id == "dashboard_new"))
    assert spec.path == "/missions/:mission_id/ops/dashboards/new"
    assert spec.query_params == ~w(mode source_dashboard_id)
    assert spec.actions == ~w(validate save)
  end

  test "invalid modes, sources and extraneous query keys never produce a destination", c do
    for params <- [
          %{"mode" => "other"},
          %{"mode" => "clone"},
          %{"source_dashboard_id" => c.source.dashboard_id},
          %{"mode" => "import", "source_dashboard_id" => c.source.dashboard_id},
          %{"mode" => "clone", "source_dashboard_id" => "missing"},
          %{"mode" => "clone", "source_dashboard_id" => String.duplicate("x", 257)},
          %{"mode" => ["new"]},
          %{"mode" => "new", "query" => "ignored"},
          %{"mission_id" => "foreign"}
        ] do
      assert {:error, :unsupported_application_surface_query} = load(c.scope, params)
    end
  end

  test "missing authentication, inactive membership and foreign mission scopes fail closed", c do
    for scope <- [
          %Scope{},
          %{c.scope | user: nil},
          %{c.scope | mission_id: "foreign"},
          %{c.scope | organization_id: "foreign"},
          %{c.scope | organization_membership: %{lifecycle_state: :inactive}}
        ] do
      assert {:error, :unsupported_application_surface_query} = load(scope, %{})
    end

    persist_mission_scope(@org, "other-creation-mission")

    {:ok, foreign} =
      Documents.persist(@org, %Document{
        organization_id: @org,
        mission_id: "other-creation-mission",
        dashboard_id: "foreign-source",
        name: "Other mission"
      })

    assert {:error, :unsupported_application_surface_query} =
             load(c.scope, %{"mode" => "clone", "source_dashboard_id" => foreign.dashboard_id})

    assert length(Documents.list(@org, @mission)) == 1
  end

  defp load(scope, params) do
    OpsConsole.load(scope, HostContext.mission(@mission), %SurfaceQueryRequest{
      application_key: "ops_console",
      application_version: 1,
      surface_id: "dashboard_new",
      surface_version: 1,
      query_id: "cadence.ops.dashboard_new",
      query_version: 1,
      params: params
    })
  end
end
