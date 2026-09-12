defmodule CadenceWeb.MissionModulePage do
  @moduledoc "Host placement of mission contributions; Communications owns its page DTOs."
  alias Cadence.Auth.Scope
  alias Cadence.Reads.Comms.Pages

  @routes %{
    "/missions/:mission_id/comms" => {"overview", nil},
    "/missions/:mission_id/comms/validation" => {"validation", nil},
    "/missions/:mission_id/comms/transports" => {"transports", nil},
    "/missions/:mission_id/comms/transports/:transport_id" => {"transport", "transport_id"},
    "/missions/:mission_id/comms/routing" => {"routing", nil},
    "/missions/:mission_id/comms/routing/:routing_rule_id" =>
      {"routing_detail", "routing_rule_id"},
    "/missions/:mission_id/comms/ground-stations" => {"ground_stations", nil},
    "/missions/:mission_id/comms/ground-stations/:ground_station_id" =>
      {"ground_station", "ground_station_id"}
  }
  @collections ~w(transports routing ground_stations)
  @query_keys ~w(q page pageSize sort dir)

  def load(%Scope{} = scope, %{route: route, params: params}) do
    case Map.fetch(@routes, route) do
      {:ok, {page, resource_key}} -> snapshot(scope, page, resource_key, params)
      :error -> nil
    end
  end

  defp snapshot(scope, page, resource_key, params) do
    context = %{organizationId: scope.organization_id, missionId: params["mission_id"]}

    context =
      if resource_key, do: Map.put(context, :resourceId, params[resource_key]), else: context

    envelope = %{
      id: "comms." <> String.replace(page, "_", "-"),
      slot: "mission.page",
      version: 1,
      context: context
    }

    keys = if page in @collections, do: @query_keys, else: List.wrap(resource_key)

    case Pages.load(scope, params["mission_id"], page, Map.take(params, keys)) do
      {:ok, data} -> Map.merge(envelope, %{status: "ready", data: data})
      _error -> Map.put(envelope, :status, "unavailable")
    end
  end
end
