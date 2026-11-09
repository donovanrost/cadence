defmodule Cadence.Comms.UplinkResolutionTest do
  use ExUnit.Case, async: true

  alias Cadence.Comms.{RoutingRule, UplinkResolution}

  defp route(id, opts \\ []) do
    %RoutingRule{
      routing_rule_id: id,
      mission_id: "m1",
      spacecraft_id: "sc-1",
      lifecycle_state: Keyword.get(opts, :state, :active),
      display_name: "Route #{id}",
      purpose_label: "ops",
      direction: Keyword.get(opts, :direction, :outbound),
      transport_id: "tr-#{id}",
      transport_version: 1,
      role: Keyword.get(opts, :role, :primary),
      enabled?: Keyword.get(opts, :enabled, true),
      origin: :profile,
      profile_rule_id: Keyword.get(opts, :rule, "rule-#{id}"),
      spacecraft_type_id: "profile-1",
      ground_station_id: Keyword.get(opts, :station)
    }
  end

  defp target, do: %{spacecraft_id: "sc-1", source_endpoint_id: nil}

  test "one primary uplink rule resolves to the managed endpoint, even across stations" do
    routes = [
      route("a", rule: "uplink", station: "svl"),
      route("b", rule: "uplink", station: "awa"),
      route("c", direction: :inbound)
    ]

    assert {:ok, %{source_endpoint_id: "spacecraft_runtime:sc-1", via: :route, routes: [_, _]}} =
             UplinkResolution.resolve(target(), routes)
  end

  test "bidirectional primary counts; candidate, disabled and archived routes don't" do
    routes = [
      route("bi", direction: :bidirectional),
      route("cand", role: :candidate),
      route("off", enabled: false),
      route("old", state: :archived)
    ]

    assert {:ok, %{routes: [%{id: "bi"}]}} = UplinkResolution.resolve(target(), routes)
  end

  test "no primary uplink route is a NO-GO that still lists the routes it has" do
    assert {:error, :no_uplink_route, [%{id: "in", direction: :inbound}]} =
             UplinkResolution.resolve(target(), [route("in", direction: :inbound)])
  end

  test "several primary uplink rules are a NO-GO naming the competing routes" do
    assert {:error, :multiple_primary_uplink_routes, competing} =
             UplinkResolution.resolve(target(), [route("x"), route("y")])

    assert Enum.map(competing, & &1.id) == ["x", "y"]
    assert Enum.all?(competing, &(&1.profile_id == "profile-1"))
  end

  test "an explicit endpoint is an override, recorded with the primary routes" do
    assert {:ok, %{source_endpoint_id: "ep-9", via: :override, routes: [%{id: "x"}, %{id: "y"}]}} =
             UplinkResolution.resolve(%{spacecraft_id: "sc-1", source_endpoint_id: "ep-9"}, [
               route("x"),
               route("y")
             ])
  end
end
