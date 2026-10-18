defmodule CadenceWeb.OpsTimelinePage do
  @moduledoc "Fixed host-owned timeline selection; reads remain scoped in Phoenix."
  alias Cadence.Auth.Scope
  alias Cadence.Reads.OpsWorkspace.Timeline
  @route "/missions/:mission_id/ops/timeline"
  @query_keys ~w(category kind severity spacecraft_id from to event_id source_dashboard_id before_at before_id)

  def load(%Scope{} = scope, %{route: @route, params: params}) do
    mission_id = params["mission_id"]

    envelope = %{
      version: 1,
      page: "timeline",
      context: %{organization_id: scope.organization_id, mission_id: mission_id}
    }

    case read(scope, mission_id, Map.take(params, @query_keys)) do
      {:ok, data} -> Map.merge(envelope, %{status: "ready", data: data})
      _ -> Map.put(envelope, :status, "unavailable")
    end
  end

  def load(_, _), do: nil

  defp read(scope, mission_id, query) do
    Timeline.load(scope, mission_id, query)
  rescue
    _ -> {:error, :unavailable}
  end
end
