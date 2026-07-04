defmodule CadenceWeb.OpsDashboardShowLive.RuntimeAdminDecisionLink do
  @moduledoc false

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  @spec from_runtime_invalidation(map()) :: String.t() | nil
  def from_runtime_invalidation(event) when is_map(event) do
    admin_decision_link(event, context_reason_key: :context_reason)
  end

  def from_runtime_invalidation(_event), do: nil

  @spec from_no_refresh_summary(map()) :: String.t() | nil
  def from_no_refresh_summary(%{blocker: blocker}) when is_map(blocker) do
    admin_decision_link(blocker, context_reason_key: :context_reason_filter)
  end

  def from_no_refresh_summary(%{"blocker" => blocker}) when is_map(blocker) do
    admin_decision_link(blocker, context_reason_key: :context_reason_filter)
  end

  def from_no_refresh_summary(_summary), do: nil

  defp admin_decision_link(attrs, opts) do
    decision_event_id = attr(attrs, :decision_event_id)

    if present?(decision_event_id) do
      ~p"/admin/runtime?#{admin_decision_query(attrs, decision_event_id, opts)}"
    end
  end

  defp admin_decision_query(attrs, decision_event_id, opts) do
    context_reason_key = Keyword.fetch!(opts, :context_reason_key)

    %{
      "dashboard_id" => attr(attrs, :dashboard_id),
      "mission_id" => attr(attrs, :mission_id),
      "boundary" => attr(attrs, :boundary),
      "context_reason" => attr(attrs, context_reason_key),
      "replay_run_id" => attr(attrs, :replay_run_id),
      "affected_placement_id" => first_csv_value(attr(attrs, :affected_placement_ids)),
      "decision" => decision_event_id
    }
    |> compact_query()
  end

  defp attr(attrs, key) when is_map(attrs) and is_atom(key) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
  end

  defp compact_query(params) do
    Map.reject(params, fn {_key, value} -> not present?(value) end)
  end

  defp first_csv_value(value) when is_binary(value) do
    value
    |> String.split(",", parts: 2)
    |> List.first()
    |> case do
      nil -> nil
      value -> String.trim(value)
    end
  end

  defp first_csv_value(_value), do: nil

  defp present?(value) when value in [nil, "", "-"], do: false
  defp present?(_value), do: true
end
