defmodule CadenceWeb.OpsDataOperationsLive.HistoricalWorkflowRequestDefaults do
  @moduledoc false

  @type t :: %__MODULE__{
          workflow: String.t(),
          run_id: String.t(),
          realm: String.t(),
          data_source_id: String.t(),
          source_binding_id: String.t(),
          observable_id: String.t(),
          point_id: String.t(),
          point_ids: String.t(),
          source_from: String.t(),
          source_to: String.t(),
          dashboard_id: String.t(),
          dashboard_version: String.t(),
          dashboard_time_mode: String.t(),
          dashboard_replay_run_id: String.t(),
          dashboard_data_view: String.t(),
          dashboard_limit_mode: String.t(),
          comparison_review_scope_kind: String.t(),
          comparison_review_scope_ids: String.t(),
          comparison_review_contact_ids: String.t(),
          comparison_review_resource_ids: String.t(),
          comparison_review_transport_ids: String.t(),
          comparison_review_source_endpoint_ids: String.t(),
          comparison_review_ground_station_ids: String.t(),
          comparison_review_scope_link_ids: String.t(),
          reason: String.t(),
          confirmed: String.t()
        }

  defstruct workflow: "backfill",
            run_id: "",
            realm: "",
            data_source_id: "",
            source_binding_id: "",
            observable_id: "",
            point_id: "",
            point_ids: "",
            source_from: "",
            source_to: "",
            dashboard_id: "",
            dashboard_version: "",
            dashboard_time_mode: "",
            dashboard_replay_run_id: "",
            dashboard_data_view: "",
            dashboard_limit_mode: "",
            comparison_review_scope_kind: "",
            comparison_review_scope_ids: "",
            comparison_review_contact_ids: "",
            comparison_review_resource_ids: "",
            comparison_review_transport_ids: "",
            comparison_review_source_endpoint_ids: "",
            comparison_review_ground_station_ids: "",
            comparison_review_scope_link_ids: "",
            reason: "operator_requested_backfill",
            confirmed: ""

  @spec new(map() | nil) :: t()
  def new(context) when is_map(context) do
    point_id = text_value(value(context, :point_id))

    %__MODULE__{
      workflow: default_text(value(context, :workflow), "backfill"),
      run_id:
        default_text_lazy(value(context, :run_id), fn ->
          Cadence.Ids.new("telemetry_backfill_run")
        end),
      realm: text_value(value(context, :realm)),
      data_source_id: text_value(value(context, :data_source_id)),
      source_binding_id: text_value(value(context, :source_binding_id)),
      observable_id: default_text(value(context, :observable_id), point_id),
      point_id: point_id,
      point_ids: default_text(value(context, :point_ids), point_id),
      source_from: text_value(value(context, :source_from)),
      source_to: text_value(value(context, :source_to)),
      dashboard_id: text_value(value(context, :dashboard_id)),
      dashboard_version: text_value(value(context, :dashboard_version)),
      dashboard_time_mode: text_value(value(context, :dashboard_time_mode)),
      dashboard_replay_run_id: text_value(value(context, :dashboard_replay_run_id)),
      dashboard_data_view: text_value(value(context, :dashboard_data_view)),
      dashboard_limit_mode: text_value(value(context, :dashboard_limit_mode)),
      comparison_review_scope_kind: text_value(value(context, :comparison_review_scope_kind)),
      comparison_review_scope_ids: text_value(value(context, :comparison_review_scope_ids)),
      comparison_review_contact_ids: text_value(value(context, :comparison_review_contact_ids)),
      comparison_review_resource_ids: text_value(value(context, :comparison_review_resource_ids)),
      comparison_review_transport_ids:
        text_value(value(context, :comparison_review_transport_ids)),
      comparison_review_source_endpoint_ids:
        text_value(value(context, :comparison_review_source_endpoint_ids)),
      comparison_review_ground_station_ids:
        text_value(value(context, :comparison_review_ground_station_ids)),
      comparison_review_scope_link_ids:
        text_value(value(context, :comparison_review_scope_link_ids)),
      reason: default_text(value(context, :reason), "operator_requested_backfill"),
      confirmed: text_value(value(context, :confirmed))
    }
  end

  def new(_context), do: new(%{})

  @spec form_params(t()) :: %{String.t() => String.t()}
  def form_params(%__MODULE__{} = defaults) do
    %{
      "workflow" => defaults.workflow,
      "run_id" => defaults.run_id,
      "realm" => defaults.realm,
      "data_source_id" => defaults.data_source_id,
      "source_binding_id" => defaults.source_binding_id,
      "observable_id" => defaults.observable_id,
      "point_id" => defaults.point_id,
      "point_ids" => defaults.point_ids,
      "source_from" => defaults.source_from,
      "source_to" => defaults.source_to,
      "dashboard_id" => defaults.dashboard_id,
      "dashboard_version" => defaults.dashboard_version,
      "dashboard_time_mode" => defaults.dashboard_time_mode,
      "dashboard_replay_run_id" => defaults.dashboard_replay_run_id,
      "dashboard_data_view" => defaults.dashboard_data_view,
      "dashboard_limit_mode" => defaults.dashboard_limit_mode,
      "comparison_review_scope_kind" => defaults.comparison_review_scope_kind,
      "comparison_review_scope_ids" => defaults.comparison_review_scope_ids,
      "comparison_review_contact_ids" => defaults.comparison_review_contact_ids,
      "comparison_review_resource_ids" => defaults.comparison_review_resource_ids,
      "comparison_review_transport_ids" => defaults.comparison_review_transport_ids,
      "comparison_review_source_endpoint_ids" => defaults.comparison_review_source_endpoint_ids,
      "comparison_review_ground_station_ids" => defaults.comparison_review_ground_station_ids,
      "comparison_review_scope_link_ids" => defaults.comparison_review_scope_link_ids,
      "reason" => defaults.reason,
      "confirmed" => defaults.confirmed
    }
  end

  defp value(map, key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end

  defp default_text(value, default) do
    case text_value(value) do
      "" -> default
      value -> value
    end
  end

  defp default_text_lazy(value, default_fun) when is_function(default_fun, 0) do
    case text_value(value) do
      "" -> default_fun.()
      value -> value
    end
  end

  defp text_value(nil), do: ""
  defp text_value(value) when is_atom(value), do: Atom.to_string(value)
  defp text_value(value) when is_integer(value), do: Integer.to_string(value)

  defp text_value(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: "", else: value
  end

  defp text_value(_value), do: ""
end
