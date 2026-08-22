defmodule CadenceWeb.OpsDashboardShowLive.OperationalResourceScopePolicyTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.OperationalResourceScopePolicy

  test "valid_resource? accepts setup-backed operational resource scopes" do
    assert OperationalResourceScopePolicy.valid_resource?(
             scope(),
             mission(),
             "ground_station",
             "ground-dss-14",
             fetch_ground_station: fn organization_id, mission_id, ground_station_id ->
               assert organization_id == "org-1"
               assert mission_id == "mission-1"
               assert ground_station_id == "ground-dss-14"
               {:ok, %{ground_station_id: ground_station_id}}
             end
           )

    assert OperationalResourceScopePolicy.valid_resource?(
             scope(),
             mission(),
             "source_endpoint",
             "endpoint-alpha",
             fetch_source_endpoint: fn organization_id, mission_id, source_endpoint_id ->
               assert organization_id == "org-1"
               assert mission_id == "mission-1"
               assert source_endpoint_id == "endpoint-alpha"
               {:ok, %{source_endpoint_id: source_endpoint_id}}
             end
           )

    assert OperationalResourceScopePolicy.valid_resource?(
             scope(),
             mission(),
             "transport",
             "transport-alpha",
             fetch_transport: fn organization_id, mission_id, transport_id ->
               assert organization_id == "org-1"
               assert mission_id == "mission-1"
               assert transport_id == "transport-alpha"
               {:ok, %{transport_id: transport_id}}
             end
           )

    assert OperationalResourceScopePolicy.valid_resource?(
             scope(),
             mission(),
             "link",
             "link-alpha",
             fetch_link_assignment: fn organization_id, mission_id, link_assignment_id ->
               assert organization_id == "org-1"
               assert mission_id == "mission-1"
               assert link_assignment_id == "link-alpha"
               {:ok, %{link_assignment_id: link_assignment_id}}
             end
           )
  end

  test "valid_resource? accepts link scopes backed by setup resource metadata" do
    assert OperationalResourceScopePolicy.valid_resource?(
             scope(),
             mission(),
             "link",
             "link-alpha",
             fetch_link_assignment: fn _organization_id, _mission_id, _link_assignment_id ->
               {:error, :link_assignment_not_found}
             end,
             list_transports: fn organization_id, mission_id ->
               assert organization_id == "org-1"
               assert mission_id == "mission-1"

               [
                 %{
                   transport_id: "transport-alpha",
                   metadata: %{"link_assignment_id" => "link-alpha"}
                 }
               ]
             end,
             list_source_endpoints: fn _organization_id, _mission_id -> [] end,
             list_ground_stations: fn _organization_id, _mission_id -> [] end
           )
  end

  test "valid_resource? rejects missing resources and lookup errors" do
    refute OperationalResourceScopePolicy.valid_resource?(
             scope(),
             mission(),
             "transport",
             "missing-transport",
             fetch_transport: fn _organization_id, _mission_id, _transport_id ->
               {:error, :transport_not_found}
             end
           )

    refute OperationalResourceScopePolicy.valid_resource?(
             scope(),
             mission(),
             "source_endpoint",
             "endpoint-alpha",
             fetch_source_endpoint: fn _organization_id, _mission_id, _source_endpoint_id ->
               {:error, :database_unavailable}
             end
           )

    refute OperationalResourceScopePolicy.valid_resource?(
             scope(),
             mission(),
             "link",
             "missing-link",
             fetch_link_assignment: fn _organization_id, _mission_id, _link_assignment_id ->
               {:error, :link_assignment_not_found}
             end,
             list_transports: fn _organization_id, _mission_id -> [] end,
             list_source_endpoints: fn _organization_id, _mission_id -> [] end,
             list_ground_stations: fn _organization_id, _mission_id -> [] end
           )
  end

  test "valid_resource? rejects unsupported or malformed scope inputs" do
    refute OperationalResourceScopePolicy.valid_resource?(scope(), mission(), "unknown", "id-1")
    refute OperationalResourceScopePolicy.valid_resource?(scope(), mission(), "transport", nil)

    refute OperationalResourceScopePolicy.valid_resource?(
             %{},
             mission(),
             "transport",
             "transport-1"
           )

    refute OperationalResourceScopePolicy.valid_resource?(
             scope(),
             %{},
             "transport",
             "transport-1"
           )
  end

  defp scope, do: %{organization_id: "org-1"}
  defp mission, do: %{mission_id: "mission-1"}
end
