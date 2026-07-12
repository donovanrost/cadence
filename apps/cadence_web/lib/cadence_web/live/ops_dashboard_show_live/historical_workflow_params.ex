defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowParams do
  @moduledoc false

  @type kind :: :stage | :group_stage | :request | :correction_request

  @type t :: %__MODULE__{
          kind: kind(),
          workflow: String.t() | nil,
          stage: String.t() | nil,
          run_id: String.t() | nil,
          realm: String.t() | nil,
          data_source_id: String.t() | nil,
          source_binding_id: String.t() | nil,
          observable_id: String.t() | nil,
          point_id: String.t() | nil,
          point_ids: String.t() | nil,
          source_from: String.t() | nil,
          source_to: String.t() | nil,
          dashboard_id: String.t() | nil,
          dashboard_version: String.t() | nil,
          dashboard_time_mode: String.t() | nil,
          dashboard_replay_run_id: String.t() | nil,
          dashboard_data_view: String.t() | nil,
          dashboard_limit_mode: String.t() | nil,
          comparison_review_request_event_id: String.t() | nil,
          comparison_review_request_kind: String.t() | nil,
          comparison_review_open_count: String.t() | nil,
          comparison_review_open_placement_ids: String.t() | nil,
          comparison_review_workflow_kind: String.t() | nil,
          comparison_review_workflow_action: String.t() | nil,
          comparison_review_workflow_selection_kind: String.t() | nil,
          comparison_review_workflow_selection_count: String.t() | nil,
          comparison_review_primary_data_view: String.t() | nil,
          comparison_review_compare_data_view: String.t() | nil,
          comparison_review_scope_kind: String.t() | nil,
          comparison_review_scope_ids: String.t() | nil,
          comparison_review_contact_ids: String.t() | nil,
          comparison_review_resource_ids: String.t() | nil,
          comparison_review_transport_ids: String.t() | nil,
          comparison_review_source_endpoint_ids: String.t() | nil,
          comparison_review_ground_station_ids: String.t() | nil,
          comparison_review_scope_link_ids: String.t() | nil,
          reason: String.t() | nil,
          confirmed: String.t() | nil,
          event_id: String.t() | nil,
          correction_source_event_id: String.t() | nil,
          request_group_id: String.t() | nil,
          request_mode: String.t() | nil,
          request_item_index: String.t() | nil,
          request_item_count: String.t() | nil,
          request_item_run_id: String.t() | nil,
          original_run_id: String.t() | nil,
          original_event_id: String.t() | nil,
          original_job_id: String.t() | nil,
          group_transition: map()
        }

  # This mirrors the flat historical workflow form contract while forms still submit string maps.
  # credo:disable-for-next-line Credo.Check.Warning.StructFieldAmount
  defstruct [
    :kind,
    :workflow,
    :stage,
    :run_id,
    :realm,
    :data_source_id,
    :source_binding_id,
    :observable_id,
    :point_id,
    :point_ids,
    :source_from,
    :source_to,
    :dashboard_id,
    :dashboard_version,
    :dashboard_time_mode,
    :dashboard_replay_run_id,
    :dashboard_data_view,
    :dashboard_limit_mode,
    :comparison_review_request_event_id,
    :comparison_review_request_kind,
    :comparison_review_open_count,
    :comparison_review_open_placement_ids,
    :comparison_review_workflow_kind,
    :comparison_review_workflow_action,
    :comparison_review_workflow_selection_kind,
    :comparison_review_workflow_selection_count,
    :comparison_review_primary_data_view,
    :comparison_review_compare_data_view,
    :comparison_review_scope_kind,
    :comparison_review_scope_ids,
    :comparison_review_contact_ids,
    :comparison_review_resource_ids,
    :comparison_review_transport_ids,
    :comparison_review_source_endpoint_ids,
    :comparison_review_ground_station_ids,
    :comparison_review_scope_link_ids,
    :reason,
    :confirmed,
    :event_id,
    :correction_source_event_id,
    :request_group_id,
    :request_mode,
    :request_item_index,
    :request_item_count,
    :request_item_run_id,
    :original_run_id,
    :original_event_id,
    :original_job_id,
    :group_transition
  ]

  @spec event_params(map()) :: t()
  def event_params(%{"historical_workflow" => params}) when is_map(params),
    do: new(:stage, params)

  def event_params(params) when is_map(params), do: new(:stage, params)

  @spec group_params(map()) :: t()
  def group_params(%{"historical_workflow_group" => params}) when is_map(params),
    do: new(:group_stage, params)

  def group_params(params) when is_map(params), do: new(:group_stage, params)

  @spec correction_params(map()) :: t()
  def correction_params(%{"historical_workflow_correction" => params}) when is_map(params),
    do: new(:correction_request, params)

  def correction_params(params) when is_map(params), do: new(:correction_request, params)

  @spec request_params(map()) :: t()
  def request_params(%{"historical_workflow_request" => params}) when is_map(params),
    do: new(:request, params)

  def request_params(params) when is_map(params), do: new(:request, params)

  @spec new(kind(), map()) :: t()
  def new(kind, params) when is_map(params) do
    %__MODULE__{
      kind: kind,
      workflow: param(params, "workflow", "workflow"),
      stage: param(params, "stage", "stage"),
      run_id: param(params, "run-id", "run_id"),
      realm: param(params, "realm", "realm"),
      data_source_id: param(params, "data-source-id", "data_source_id"),
      source_binding_id: param(params, "source-binding-id", "source_binding_id"),
      observable_id: param(params, "observable-id", "observable_id"),
      point_id: param(params, "point-id", "point_id"),
      point_ids: param(params, "point-ids", "point_ids"),
      source_from: param(params, "source-from", "source_from"),
      source_to: param(params, "source-to", "source_to"),
      dashboard_id: param(params, "dashboard-id", "dashboard_id"),
      dashboard_version: param(params, "dashboard-version", "dashboard_version"),
      dashboard_time_mode: param(params, "dashboard-time-mode", "dashboard_time_mode"),
      dashboard_replay_run_id:
        param(params, "dashboard-replay-run-id", "dashboard_replay_run_id"),
      dashboard_data_view: param(params, "dashboard-data-view", "dashboard_data_view"),
      dashboard_limit_mode: param(params, "dashboard-limit-mode", "dashboard_limit_mode"),
      comparison_review_request_event_id:
        param(
          params,
          "comparison-review-request-event-id",
          "comparison_review_request_event_id"
        ),
      comparison_review_request_kind:
        param(params, "comparison-review-request-kind", "comparison_review_request_kind"),
      comparison_review_open_count:
        param(params, "comparison-review-open-count", "comparison_review_open_count"),
      comparison_review_open_placement_ids:
        param(
          params,
          "comparison-review-open-placement-ids",
          "comparison_review_open_placement_ids"
        ),
      comparison_review_workflow_kind:
        param(params, "comparison-review-workflow-kind", "comparison_review_workflow_kind"),
      comparison_review_workflow_action:
        param(params, "comparison-review-workflow-action", "comparison_review_workflow_action"),
      comparison_review_workflow_selection_kind:
        param(
          params,
          "comparison-review-workflow-selection-kind",
          "comparison_review_workflow_selection_kind"
        ),
      comparison_review_workflow_selection_count:
        param(
          params,
          "comparison-review-workflow-selection-count",
          "comparison_review_workflow_selection_count"
        ),
      comparison_review_primary_data_view:
        param(
          params,
          "comparison-review-primary-data-view",
          "comparison_review_primary_data_view"
        ),
      comparison_review_compare_data_view:
        param(
          params,
          "comparison-review-compare-data-view",
          "comparison_review_compare_data_view"
        ),
      comparison_review_scope_kind:
        param(params, "comparison-review-scope-kind", "comparison_review_scope_kind"),
      comparison_review_scope_ids:
        param(params, "comparison-review-scope-ids", "comparison_review_scope_ids"),
      comparison_review_contact_ids:
        param(params, "comparison-review-contact-ids", "comparison_review_contact_ids"),
      comparison_review_resource_ids:
        param(params, "comparison-review-resource-ids", "comparison_review_resource_ids"),
      comparison_review_transport_ids:
        param(params, "comparison-review-transport-ids", "comparison_review_transport_ids"),
      comparison_review_source_endpoint_ids:
        param(
          params,
          "comparison-review-source-endpoint-ids",
          "comparison_review_source_endpoint_ids"
        ),
      comparison_review_ground_station_ids:
        param(
          params,
          "comparison-review-ground-station-ids",
          "comparison_review_ground_station_ids"
        ),
      comparison_review_scope_link_ids:
        param(params, "comparison-review-scope-link-ids", "comparison_review_scope_link_ids"),
      reason: param(params, "reason", "reason"),
      confirmed: param(params, "confirmed", "confirmed"),
      event_id: param(params, "event-id", "event_id"),
      correction_source_event_id:
        param(params, "correction-source-event-id", "correction_source_event_id"),
      request_group_id: param(params, "request-group-id", "request_group_id"),
      request_mode: param(params, "request-mode", "request_mode"),
      request_item_index: param(params, "request-item-index", "request_item_index"),
      request_item_count: param(params, "request-item-count", "request_item_count"),
      request_item_run_id: param(params, "request-item-run-id", "request_item_run_id"),
      original_run_id: param(params, "original-run-id", "original_run_id"),
      original_event_id: param(params, "original-event-id", "original_event_id"),
      original_job_id: param(params, "original-job-id", "original_job_id"),
      group_transition: group_transition_params(params)
    }
  end

  @spec put(t(), atom(), term()) :: t()
  def put(%__MODULE__{} = params, key, value) when is_atom(key) do
    Map.put(params, key, text_param(value))
  end

  @spec get(t() | map(), atom() | String.t()) :: term()
  def get(%__MODULE__{} = params, :group_transition_scope), do: group_transition_scope(params)

  def get(%__MODULE__{} = params, :group_correction_tasks), do: group_correction_tasks(params)

  def get(%__MODULE__{} = params, key) when is_atom(key), do: Map.get(params, key)

  def get(%__MODULE__{} = params, key) when is_binary(key),
    do: Map.get(to_event_params(params), key)

  def get(params, key) when is_map(params), do: Map.get(params, key)

  @spec to_event_params(t() | map()) :: map()
  def to_event_params(%__MODULE__{} = params) do
    %{
      "workflow" => params.workflow,
      "stage" => params.stage,
      "run_id" => params.run_id,
      "realm" => params.realm,
      "data_source_id" => params.data_source_id,
      "source_binding_id" => params.source_binding_id,
      "observable_id" => params.observable_id,
      "point_id" => params.point_id,
      "point_ids" => params.point_ids,
      "source_from" => params.source_from,
      "source_to" => params.source_to,
      "dashboard_id" => params.dashboard_id,
      "dashboard_version" => params.dashboard_version,
      "dashboard_time_mode" => params.dashboard_time_mode,
      "dashboard_replay_run_id" => params.dashboard_replay_run_id,
      "dashboard_data_view" => params.dashboard_data_view,
      "dashboard_limit_mode" => params.dashboard_limit_mode,
      "comparison_review_request_event_id" => params.comparison_review_request_event_id,
      "comparison_review_request_kind" => params.comparison_review_request_kind,
      "comparison_review_open_count" => params.comparison_review_open_count,
      "comparison_review_open_placement_ids" => params.comparison_review_open_placement_ids,
      "comparison_review_workflow_kind" => params.comparison_review_workflow_kind,
      "comparison_review_workflow_action" => params.comparison_review_workflow_action,
      "comparison_review_workflow_selection_kind" =>
        params.comparison_review_workflow_selection_kind,
      "comparison_review_workflow_selection_count" =>
        params.comparison_review_workflow_selection_count,
      "comparison_review_primary_data_view" => params.comparison_review_primary_data_view,
      "comparison_review_compare_data_view" => params.comparison_review_compare_data_view,
      "comparison_review_scope_kind" => params.comparison_review_scope_kind,
      "comparison_review_scope_ids" => params.comparison_review_scope_ids,
      "comparison_review_contact_ids" => params.comparison_review_contact_ids,
      "comparison_review_resource_ids" => params.comparison_review_resource_ids,
      "comparison_review_transport_ids" => params.comparison_review_transport_ids,
      "comparison_review_source_endpoint_ids" => params.comparison_review_source_endpoint_ids,
      "comparison_review_ground_station_ids" => params.comparison_review_ground_station_ids,
      "comparison_review_scope_link_ids" => params.comparison_review_scope_link_ids,
      "reason" => params.reason,
      "confirmed" => params.confirmed,
      "event_id" => params.event_id,
      "correction_source_event_id" => params.correction_source_event_id,
      "request_group_id" => params.request_group_id,
      "request_mode" => params.request_mode,
      "request_item_index" => params.request_item_index,
      "request_item_count" => params.request_item_count,
      "request_item_run_id" => params.request_item_run_id,
      "original_run_id" => params.original_run_id,
      "original_event_id" => params.original_event_id,
      "original_job_id" => params.original_job_id,
      "group_transition_scope" => group_transition_scope(params),
      "group_correction_tasks" => group_correction_tasks(params)
    }
    |> compact_payload()
  end

  def to_event_params(params) when is_map(params), do: params

  @spec attrs(t(), map(), map()) :: map()
  def attrs(%__MODULE__{} = params, scope, mission) do
    %{
      backfill_run_id: params.run_id,
      import_run_id: params.run_id,
      organization_id: scope.organization_id,
      mission_id: mission.mission_id,
      realm: params.realm,
      data_source_id: params.data_source_id,
      binding_id: params.source_binding_id,
      observable_id: params.observable_id,
      point_id: params.point_id,
      source_from: params.source_from,
      source_to: params.source_to,
      actor_id: current_scope_user_id(scope),
      actor_kind: "operator",
      authority: authority(params.stage),
      reason: reason(params),
      payload: payload(params)
    }
    |> compact()
  end

  def attrs(params, scope, mission) when is_map(params) do
    params
    |> then(&new(:stage, &1))
    |> attrs(scope, mission)
  end

  def actor_attrs(scope, mission) do
    %{
      organization_id: scope.organization_id,
      mission_id: mission.mission_id,
      actor_id: current_scope_user_id(scope),
      actor_kind: "operator"
    }
    |> compact()
  end

  @spec request_point_ids(t() | map()) :: [String.t()]
  def request_point_ids(%__MODULE__{} = params) do
    params.point_ids
    |> split_point_ids()
    |> case do
      [] ->
        [params.point_id, params.observable_id]
        |> Enum.map(&text_param/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      point_ids ->
        point_ids
    end
  end

  def request_point_ids(params) when is_map(params),
    do: params |> then(&new(:request, &1)) |> request_point_ids()

  @spec request_group_id(t() | map()) :: String.t() | nil
  def request_group_id(%__MODULE__{} = params), do: params.request_group_id

  def request_group_id(params) when is_map(params),
    do: params |> then(&new(:group_stage, &1)) |> request_group_id()

  def request_group_id(_params), do: nil

  @spec confirmed?(t() | map()) :: boolean()
  def confirmed?(%__MODULE__{} = params), do: params.confirmed in ["true", "confirmed", "on"]
  def confirmed?(params) when is_map(params), do: params |> then(&new(:stage, &1)) |> confirmed?()

  defp split_point_ids(nil), do: []

  defp split_point_ids(value) when is_binary(value) do
    value
    |> String.split([",", "\n", "\r", "\t", " "], trim: true)
    |> Enum.map(&text_param/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp split_point_ids(_value), do: []

  defp param(params, legacy_key, form_key) do
    params
    |> Map.get(legacy_key, Map.get(params, form_key))
    |> text_param()
  end

  defp group_transition_params(params) when is_map(params) do
    %{
      scope: param(params, "group-transition-scope", "group_transition_scope"),
      correction_tasks: param(params, "group-correction-tasks", "group_correction_tasks")
    }
    |> compact()
  end

  defp group_transition_scope(%__MODULE__{group_transition: group_transition})
       when is_map(group_transition),
       do: Map.get(group_transition, :scope)

  defp group_transition_scope(_params), do: nil

  defp group_correction_tasks(%__MODULE__{group_transition: group_transition})
       when is_map(group_transition),
       do: Map.get(group_transition, :correction_tasks)

  defp group_correction_tasks(_params), do: nil

  defp compact(attrs) when is_map(attrs) do
    attrs
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp authority(stage) when stage in ["approved", "completed", "retried"], do: :authoritative
  defp authority(stage) when stage in ["rejected", "failed"], do: :advisory
  defp authority(_stage), do: :unknown

  defp reason(%__MODULE__{} = params) do
    case text_param(params.reason) do
      nil -> default_reason(params.workflow, params.stage)
      reason -> reason
    end
  end

  defp payload(%__MODULE__{} = params) do
    dashboard_context =
      %{
        "dashboard_id" => params.dashboard_id,
        "dashboard_version" => params.dashboard_version,
        "dashboard_time_mode" => params.dashboard_time_mode,
        "dashboard_replay_run_id" => params.dashboard_replay_run_id,
        "dashboard_data_view" => params.dashboard_data_view,
        "dashboard_limit_mode" => params.dashboard_limit_mode
      }
      |> compact_payload()

    comparison_review_origin =
      %{
        "request_event_id" => params.comparison_review_request_event_id,
        "request_kind" => params.comparison_review_request_kind,
        "open_count" => params.comparison_review_open_count,
        "open_placement_ids" => params.comparison_review_open_placement_ids,
        "workflow_kind" => params.comparison_review_workflow_kind,
        "workflow_action" => params.comparison_review_workflow_action,
        "workflow_selection_kind" => params.comparison_review_workflow_selection_kind,
        "workflow_selection_count" => params.comparison_review_workflow_selection_count,
        "primary_data_view" => params.comparison_review_primary_data_view,
        "compare_data_view" => params.comparison_review_compare_data_view,
        "scope_kind" => params.comparison_review_scope_kind,
        "scope_ids" => params.comparison_review_scope_ids,
        "contact_ids" => params.comparison_review_contact_ids,
        "resource_ids" => params.comparison_review_resource_ids,
        "transport_ids" => params.comparison_review_transport_ids,
        "source_endpoint_ids" => params.comparison_review_source_endpoint_ids,
        "ground_station_ids" => params.comparison_review_ground_station_ids,
        "scope_link_ids" => params.comparison_review_scope_link_ids
      }
      |> compact_payload()

    %{
      "dashboard_context" => dashboard_context,
      "comparison_review_origin" => comparison_review_origin,
      "group_transition_scope" => group_transition_scope(params)
    }
    |> Enum.reject(fn {_key, value} -> value in [%{}, nil] end)
    |> Map.new()
    |> empty_payload_to_nil()
  end

  defp compact_payload(payload) when is_map(payload) do
    payload
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp empty_payload_to_nil(payload) when map_size(payload) == 0, do: nil
  defp empty_payload_to_nil(payload), do: payload

  defp default_reason(workflow, stage) do
    [workflow, stage]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> case do
      [] -> "dashboard_historical_workflow_event"
      parts -> Enum.join(["dashboard" | parts], "_")
    end
  end

  defp current_scope_user_id(%{user: %{id: id}}) when is_binary(id), do: id
  defp current_scope_user_id(%{user: %{user_id: id}}) when is_binary(id), do: id
  defp current_scope_user_id(_scope), do: nil

  defp text_param(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp text_param(_value), do: nil
end
