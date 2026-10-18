defmodule CadenceWeb.SpacecraftModulePage do
  @moduledoc "Host-selected spacecraft page contributions; domain DTOs remain module-owned."
  alias Cadence.Auth.Scope
  alias Cadence.Reads.Comms.SpacecraftRouting
  alias Cadence.Reads.SpacecraftCommanding

  @routes %{
    "/missions/:mission_id/spacecraft/:spacecraft_id/routing" =>
      {"comms.spacecraft-routing", SpacecraftRouting},
    "/missions/:mission_id/spacecraft/:spacecraft_id/commanding" =>
      {"commanding.spacecraft", SpacecraftCommanding}
  }

  def load(%Scope{} = scope, %{route: route, params: params}) do
    case Map.fetch(@routes, route) do
      {:ok, {id, provider}} -> snapshot(id, provider, scope, params)
      :error -> nil
    end
  end

  defp snapshot(id, provider, scope, params) do
    envelope = %{
      id: id,
      slot: "spacecraft.page",
      version: 1,
      context: %{
        organizationId: scope.organization_id,
        missionId: params["mission_id"],
        spacecraftId: params["spacecraft_id"]
      }
    }

    case read(provider, scope, params) do
      {:ok, data} -> Map.merge(envelope, %{status: "ready", data: data})
      _error -> Map.put(envelope, :status, "unavailable")
    end
  end

  defp read(SpacecraftCommanding, scope, params) do
    SpacecraftCommanding.load(
      scope,
      params["mission_id"],
      params["spacecraft_id"],
      Map.take(params, ~w(page query))
    )
  end

  defp read(provider, scope, params) do
    provider.load(scope, params["mission_id"], params["spacecraft_id"])
  rescue
    _exception -> {:error, :unavailable}
  end
end
