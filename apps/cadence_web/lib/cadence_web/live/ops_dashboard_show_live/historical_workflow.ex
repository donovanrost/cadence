defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflow do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3, to_form: 2]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Cadence.Dashboards.{ComparisonReviewQueue, DataLink, Document, TimeRange}
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowCommands
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowContext
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowParams
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowPresenter
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowRequestDefaults
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowSelection
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowSelectionResult
  alias CadenceWeb.OpsDashboardShowLive.SelectionPanel
  alias CadenceWeb.OpsDashboardShowLive.SelectionQuery

  @dashboard_context_keys [
    :dashboard_id,
    :dashboard_version,
    :dashboard_time_mode,
    :dashboard_replay_run_id,
    :dashboard_data_view,
    :dashboard_limit_mode
  ]

  def open_request(socket) do
    socket
    |> assign(:panel, :historical_workflow_request)
    |> assign(
      :historical_workflow_request_form,
      to_form(request_form_params(socket), as: :historical_workflow_request)
    )
  end

  def open_comparison_review_request(socket, params) when is_map(params) do
    request_event_id =
      text_param(Map.get(params, "request-event-id") || Map.get(params, "request_event_id"))

    case comparison_review_request_event(socket, request_event_id) do
      nil ->
        put_flash(socket, :error, "Comparison review request is no longer available.")

      event ->
        socket
        |> assign(:panel, :historical_workflow_request)
        |> assign(
          :historical_workflow_request_form,
          to_form(request_form_params(socket, comparison_review_request_overrides(event)),
            as: :historical_workflow_request
          )
        )
    end
  end

  def record_stage(socket, params, opts \\ []) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    params = HistoricalWorkflowParams.event_params(params)
    stage = HistoricalWorkflowParams.get(params, :stage)

    if HistoricalWorkflowParams.confirmed?(params) do
      case record_stage_command(opts).(params, scope, mission) do
        {:ok, event, job_result} ->
          socket
          |> put_action_flash(
            HistoricalWorkflowPresenter.action_outcome(
              :stage_transition,
              {:ok, job_result},
              %{
                stage: stage,
                target_event_id: event_id(event),
                target_run_id: run_id(event)
              }
              |> with_dashboard_context(params)
            )
          )
          |> put_event_selection(event, params, opts)

        {:error, reason} ->
          put_action_flash(
            socket,
            HistoricalWorkflowPresenter.action_outcome(
              :stage_transition,
              {:error, reason},
              %{
                stage: stage,
                target_event_id: HistoricalWorkflowParams.get(params, :event_id)
              }
              |> with_dashboard_context(params)
            )
          )
      end
    else
      put_action_flash(
        socket,
        HistoricalWorkflowPresenter.action_outcome(
          :stage_transition,
          :unconfirmed,
          %{
            stage: stage,
            target_event_id: HistoricalWorkflowParams.get(params, :event_id)
          }
          |> with_dashboard_context(params)
        )
      )
    end
  end

  def record_group_stage(socket, params, opts \\ []) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    params = HistoricalWorkflowParams.group_params(params)
    stage = HistoricalWorkflowParams.get(params, :stage)

    if HistoricalWorkflowParams.confirmed?(params) do
      case record_group_stage_command(opts).(params, scope, mission) do
        {:ok, [_event | _events] = events, job_results} ->
          selection =
            HistoricalWorkflowSelection.group_transition_selection(events, job_results, params)

          socket
          |> put_action_flash(
            HistoricalWorkflowPresenter.action_outcome(
              :group_stage_transition,
              {:ok, events, job_results},
              %{
                stage: stage,
                target_event_id: event_id(selection.event),
                target_run_id: run_id(selection.event),
                request_group_id: HistoricalWorkflowParams.get(params, :request_group_id)
              }
              |> with_dashboard_context(params)
            )
          )
          |> put_link_selection(selection, opts)

        {:error, {:no_eligible_request_group_items, request_group_id, failed_stage}} ->
          refresh_no_eligible_group(socket, request_group_id, failed_stage)

        {:error, reason} ->
          put_action_flash(
            socket,
            HistoricalWorkflowPresenter.action_outcome(
              :group_stage_transition,
              {:error, reason},
              %{
                stage: stage,
                target_event_id: HistoricalWorkflowParams.get(params, :event_id),
                request_group_id: HistoricalWorkflowParams.get(params, :request_group_id)
              }
              |> with_dashboard_context(params)
            )
          )
      end
    else
      put_action_flash(
        socket,
        HistoricalWorkflowPresenter.action_outcome(
          :group_stage_transition,
          :unconfirmed,
          %{
            stage: stage,
            target_event_id: HistoricalWorkflowParams.get(params, :event_id),
            request_group_id: HistoricalWorkflowParams.get(params, :request_group_id)
          }
          |> with_dashboard_context(params)
        )
      )
    end
  end

  def record_request(socket, params, opts \\ []) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    params = HistoricalWorkflowParams.request_params(params)

    if HistoricalWorkflowParams.confirmed?(params) do
      case record_request_command(opts).(params, scope, mission) do
        {:ok, [event | _events] = events, selection_params} ->
          socket
          |> put_action_flash(
            HistoricalWorkflowPresenter.action_outcome(
              :request,
              {:ok, events},
              request_context(event, events, selection_params)
              |> with_dashboard_context(params)
            )
          )
          |> assign(
            :historical_workflow_request_form,
            to_form(request_form_params(socket), as: :historical_workflow_request)
          )
          |> put_event_selection(event, selection_params, opts)

        {:error, reason} ->
          put_action_flash(
            socket,
            HistoricalWorkflowPresenter.action_outcome(
              :request,
              {:error, reason},
              request_context(params)
              |> with_dashboard_context(params)
            )
          )
      end
    else
      put_action_flash(
        socket,
        HistoricalWorkflowPresenter.action_outcome(
          :request,
          :unconfirmed,
          request_context(params)
          |> with_dashboard_context(params)
        )
      )
    end
  end

  def record_correction_request(socket, params, opts \\ []) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    params = HistoricalWorkflowParams.correction_params(params)

    if HistoricalWorkflowParams.confirmed?(params) do
      case record_correction_request_command(opts).(params, scope, mission) do
        {:ok, event} ->
          socket
          |> put_action_flash(
            HistoricalWorkflowPresenter.action_outcome(
              :correction_request,
              {:ok, event},
              %{
                target_event_id: event_id(event),
                target_run_id: run_id(event),
                request_group_id: HistoricalWorkflowParams.get(params, :request_group_id)
              }
              |> with_dashboard_context(params)
            )
          )
          |> put_event_selection(event, params, opts)

        {:error, reason} ->
          put_action_flash(
            socket,
            HistoricalWorkflowPresenter.action_outcome(
              :correction_request,
              {:error, reason},
              %{
                target_event_id: HistoricalWorkflowParams.get(params, :original_event_id),
                target_run_id: HistoricalWorkflowParams.get(params, :original_run_id),
                request_group_id: HistoricalWorkflowParams.get(params, :request_group_id)
              }
              |> with_dashboard_context(params)
            )
          )
      end
    else
      put_action_flash(
        socket,
        HistoricalWorkflowPresenter.action_outcome(
          :correction_request,
          :unconfirmed,
          %{
            target_event_id: HistoricalWorkflowParams.get(params, :original_event_id),
            target_run_id: HistoricalWorkflowParams.get(params, :original_run_id),
            request_group_id: HistoricalWorkflowParams.get(params, :request_group_id)
          }
          |> with_dashboard_context(params)
        )
      )
    end
  end

  def retry_job(socket, job_id, event_id, opts \\ []) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    dashboard_context = selected_dashboard_context(socket)

    case retry_job_command(opts).(job_id, event_id, scope, mission) do
      {:ok, retried_job, retry_event} ->
        socket
        |> put_action_flash(
          HistoricalWorkflowPresenter.action_outcome(
            :retry_job,
            {:ok, retried_job, retry_event},
            retry_job_context(retry_event, opts)
            |> with_dashboard_context(dashboard_context)
          )
        )
        |> put_event_selection(retry_event, dashboard_context, opts)

      {:error, reason} ->
        put_action_flash(
          socket,
          HistoricalWorkflowPresenter.action_outcome(
            :retry_job,
            {:error, reason},
            %{
              target_event_id: event_id
            }
            |> with_dashboard_context(dashboard_context)
          )
        )
    end
  end

  def inspect_stale_replacement_job(socket, job_id, event_id, opts \\ []) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    dashboard_context = selected_dashboard_context(socket)

    case inspect_stale_replacement_job_command(opts).(job_id, event_id, scope, mission) do
      {:ok, inspection_event} ->
        socket
        |> put_action_flash(
          HistoricalWorkflowPresenter.action_outcome(
            :stale_replacement_job_inspection,
            {:ok, inspection_event},
            %{
              target_event_id: event_id(inspection_event),
              target_run_id: replacement_target_run_id(inspection_event, opts)
            }
            |> with_dashboard_context(dashboard_context)
          )
        )
        |> put_event_selection(inspection_event, dashboard_context, opts)

      {:error, reason} ->
        put_action_flash(
          socket,
          HistoricalWorkflowPresenter.action_outcome(
            :stale_replacement_job_inspection,
            {:error, reason},
            %{target_event_id: event_id, target_run_id: replacement_target_run_id(nil, opts)}
            |> with_dashboard_context(dashboard_context)
          )
        )
    end
  end

  def inspect_missing_replacement_job(socket, request_group_id, replacement_run_id, opts \\ []) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    dashboard_context = selected_dashboard_context(socket)

    case inspect_missing_replacement_job_command(opts).(
           request_group_id,
           replacement_run_id,
           scope,
           mission
         ) do
      {:ok, inspection_event} ->
        socket
        |> put_action_flash(
          HistoricalWorkflowPresenter.action_outcome(
            :missing_replacement_job_inspection,
            {:ok, inspection_event},
            %{
              target_event_id: event_id(inspection_event),
              target_run_id: run_id(inspection_event),
              request_group_id: request_group_id
            }
            |> with_dashboard_context(dashboard_context)
          )
        )
        |> put_event_selection(inspection_event, dashboard_context, opts)

      {:error, reason} ->
        put_action_flash(
          socket,
          HistoricalWorkflowPresenter.action_outcome(
            :missing_replacement_job_inspection,
            {:error, reason},
            %{target_run_id: replacement_run_id, request_group_id: request_group_id}
            |> with_dashboard_context(dashboard_context)
          )
        )
    end
  end

  def requeue_stale_replacement_job(socket, job_id, event_id, opts \\ []) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    dashboard_context = selected_dashboard_context(socket)

    case requeue_stale_replacement_job_command(opts).(job_id, event_id, scope, mission) do
      {:ok, requeued_job, requeue_event} ->
        socket
        |> put_action_flash(
          HistoricalWorkflowPresenter.action_outcome(
            :stale_replacement_job_requeue,
            {:ok, requeued_job, requeue_event},
            %{
              target_event_id: event_id(requeue_event),
              target_run_id: replacement_target_run_id(requeue_event, opts)
            }
            |> with_dashboard_context(dashboard_context)
          )
        )
        |> put_event_selection(requeue_event, dashboard_context, opts)

      {:error, reason} ->
        put_action_flash(
          socket,
          HistoricalWorkflowPresenter.action_outcome(
            :stale_replacement_job_requeue,
            {:error, reason},
            %{target_event_id: event_id, target_run_id: replacement_target_run_id(nil, opts)}
            |> with_dashboard_context(dashboard_context)
          )
        )
    end
  end

  def retry_group_failed_jobs(socket, request_group_id, event_id, opts \\ []) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    dashboard_context = selected_dashboard_context(socket)

    case retry_group_failed_jobs_command(opts, request_group_id, scope, mission) do
      {:ok, summary} ->
        selection =
          HistoricalWorkflowSelection.retry_selection(summary, event_id, dashboard_context)

        socket
        |> put_action_flash(
          HistoricalWorkflowPresenter.action_outcome(
            :retry_group_failed_jobs,
            {:ok, summary},
            %{
              target_event_id: selection.link.target_id,
              request_group_id: request_group_id,
              retry_run_ids: Keyword.get(opts, :retry_run_ids)
            }
            |> with_dashboard_context(dashboard_context)
          )
        )
        |> put_link_selection(selection, opts)

      {:error, reason} ->
        put_action_flash(
          socket,
          HistoricalWorkflowPresenter.action_outcome(
            :retry_group_failed_jobs,
            {:error, reason},
            %{
              target_event_id: event_id,
              request_group_id: request_group_id
            }
            |> with_dashboard_context(dashboard_context)
          )
        )
    end
  end

  def request_form_defaults(%{assigns: assigns} = socket) do
    {source_from, source_to} =
      TimeRange.frozen_bounds(
        assign_value(assigns, :dashboard_time_from),
        assign_value(assigns, :dashboard_time_to),
        DateTime.utc_now()
      )

    HistoricalWorkflowPresenter.request_form_defaults(%{
      realm: assign_value(assigns, :dashboard_data_realm, "backfill"),
      data_source_id: assign_value(assigns, :dashboard_data_source_id),
      source_binding_id: assign_value(assigns, :dashboard_source_binding_id),
      point_id: request_point_id(socket),
      source_from: source_from,
      source_to: source_to,
      dashboard_id: dashboard_id(assigns[:dashboard_document]),
      dashboard_version: dashboard_version(assigns[:dashboard_document]),
      dashboard_time_mode: assign_value(assigns, :dashboard_time_mode),
      dashboard_replay_run_id: assign_value(assigns, :dashboard_replay_run_id),
      dashboard_data_view: assign_value(assigns, :dashboard_data_view),
      dashboard_limit_mode: assign_value(assigns, :dashboard_limit_mode)
    })
  end

  defp request_form_params(socket, overrides \\ %{}) do
    socket
    |> request_form_defaults()
    |> HistoricalWorkflowRequestDefaults.form_params()
    |> Map.merge(overrides)
  end

  defp assign_value(assigns, key, default \\ "")

  defp assign_value(assigns, key, default) when is_map(assigns),
    do: Map.get(assigns, key) || default

  defp assign_value(_assigns, _key, default), do: default

  defp request_point_id(socket) do
    socket.assigns[:selected_point_id] ||
      SelectionPanel.selected_data_ref_observable_id(socket) ||
      ""
  end

  defp dashboard_id(%Document{} = document), do: document.dashboard_id
  defp dashboard_id(_document), do: ""

  defp dashboard_version(%Document{} = document) do
    case Document.version(document) do
      version when is_integer(version) -> Integer.to_string(version)
      _version -> ""
    end
  end

  defp dashboard_version(_document), do: ""

  defp comparison_review_request_event(%{assigns: assigns}, request_event_id)
       when is_binary(request_event_id) and request_event_id != "" do
    assigns
    |> Map.get(:dashboard_lifecycle_events, [])
    |> Enum.find(fn event ->
      ComparisonReviewQueue.event_value(event, :dashboard_lifecycle_event_id) == request_event_id and
        ComparisonReviewQueue.event_value(event, :event_type) in [
          :comparison_review_requested,
          "comparison_review_requested"
        ]
    end)
  end

  defp comparison_review_request_event(_socket, _request_event_id), do: nil

  defp comparison_review_request_overrides(event) do
    payload = ComparisonReviewQueue.event_value(event, :payload)
    workflow_intent = ComparisonReviewQueue.payload_value(payload, "workflow_intent")
    open_findings = ComparisonReviewQueue.payload_value(payload, "open_findings")
    comparison = ComparisonReviewQueue.payload_value(open_findings, "comparison")

    point_ids =
      event
      |> ComparisonReviewQueue.request_findings()
      |> Enum.flat_map(&comparison_finding_point_ids/1)
      |> Enum.uniq()

    first_point_id = List.first(point_ids) || ""
    operational_context = ComparisonReviewQueue.request_operational_context(event)

    %{
      "workflow" => "backfill",
      "observable_id" => first_point_id,
      "point_id" => first_point_id,
      "point_ids" => Enum.join(point_ids, ", "),
      "comparison_review_request_event_id" =>
        ComparisonReviewQueue.event_value(event, :dashboard_lifecycle_event_id),
      "comparison_review_request_kind" =>
        ComparisonReviewQueue.payload_value(payload, "request_kind"),
      "comparison_review_open_count" =>
        payload
        |> ComparisonReviewQueue.payload_value("open_count")
        |> count_param(),
      "comparison_review_open_placement_ids" =>
        payload
        |> ComparisonReviewQueue.payload_value("open_placement_ids")
        |> placement_ids_param(),
      "comparison_review_workflow_kind" =>
        ComparisonReviewQueue.payload_value(workflow_intent, "kind"),
      "comparison_review_workflow_action" =>
        ComparisonReviewQueue.payload_value(workflow_intent, "action"),
      "comparison_review_workflow_selection_kind" =>
        ComparisonReviewQueue.payload_value(workflow_intent, "selection_kind"),
      "comparison_review_workflow_selection_count" =>
        workflow_intent
        |> ComparisonReviewQueue.payload_value("selection_count")
        |> count_param(),
      "comparison_review_primary_data_view" =>
        ComparisonReviewQueue.payload_value(workflow_intent, "primary_data_view") ||
          ComparisonReviewQueue.payload_value(comparison, "primary_data_view"),
      "comparison_review_compare_data_view" =>
        ComparisonReviewQueue.payload_value(workflow_intent, "compare_data_view") ||
          ComparisonReviewQueue.payload_value(comparison, "compare_data_view"),
      "comparison_review_scope_kind" => Map.get(operational_context, :scope_kind),
      "comparison_review_scope_ids" => Map.get(operational_context, :scope_ids_attr),
      "comparison_review_contact_ids" => Map.get(operational_context, :contact_ids_attr),
      "comparison_review_resource_ids" => Map.get(operational_context, :resource_ids_attr),
      "comparison_review_transport_ids" => Map.get(operational_context, :transport_ids_attr),
      "comparison_review_source_endpoint_ids" =>
        Map.get(operational_context, :source_endpoint_ids_attr),
      "comparison_review_ground_station_ids" =>
        Map.get(operational_context, :ground_station_ids_attr),
      "comparison_review_scope_link_ids" => Map.get(operational_context, :scope_link_ids_attr),
      "reason" => "operator_requested_bulk_correction_authority_review"
    }
  end

  defp comparison_finding_point_ids(finding) when is_map(finding) do
    [
      ComparisonReviewQueue.payload_value(finding, "point_id"),
      ComparisonReviewQueue.payload_value(finding, "observable_id"),
      ComparisonReviewQueue.payload_value(finding, "primary_observable_ids"),
      ComparisonReviewQueue.payload_value(finding, "compare_observable_ids")
    ]
    |> Enum.flat_map(&point_id_values/1)
    |> Enum.uniq()
  end

  defp comparison_finding_point_ids(_finding), do: []

  defp point_id_values(values) when is_list(values) do
    values
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp point_id_values(value) when is_binary(value) do
    value
    |> String.split([",", "\n", "\r", "\t", " "], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp point_id_values(_value), do: []

  defp placement_ids_param(values) when is_list(values) do
    values
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(",")
  end

  defp placement_ids_param(value) when is_binary(value), do: text_param(value)
  defp placement_ids_param(_value), do: nil

  defp count_param(value) when is_integer(value), do: Integer.to_string(value)
  defp count_param(value) when is_binary(value), do: text_param(value)
  defp count_param(_value), do: nil

  defp put_event_selection(socket, event, params, opts) do
    selection = HistoricalWorkflowSelection.event_selection(event, params)

    put_link_selection(socket, selection, opts)
  end

  defp event_id(%{backfill_lifecycle_event_id: event_id}) when is_binary(event_id), do: event_id
  defp event_id(_event), do: nil

  defp run_id(%{backfill_run_id: run_id}) when is_binary(run_id), do: run_id
  defp run_id(_event), do: nil

  defp request_context(event, events, params) do
    %{
      target_event_id: event_id(event),
      target_run_id: run_id(event),
      request_group_id: request_group_id(events, params)
    }
  end

  defp request_context(params) do
    %{request_group_id: request_group_id(params)}
  end

  defp request_group_id(events, params) when is_list(events) do
    events
    |> Enum.find_value(&event_request_group_id/1)
    |> case do
      nil -> request_group_id(params)
      request_group_id -> request_group_id
    end
  end

  defp request_group_id(%HistoricalWorkflowParams{} = params) do
    params
    |> HistoricalWorkflowParams.get(:run_id)
    |> text_param()
  end

  defp request_group_id(params) when is_map(params) do
    ["request_group_id", :request_group_id, "run_id", :run_id]
    |> Enum.find_value(fn key ->
      params
      |> Map.get(key)
      |> text_param()
    end)
  end

  defp request_group_id(_params), do: nil

  defp with_dashboard_context(context, %HistoricalWorkflowParams{} = params)
       when is_map(context) do
    Enum.reduce(@dashboard_context_keys, context, &put_context_param(&2, &1, params))
  end

  defp with_dashboard_context(context, source) when is_map(context) and is_map(source) do
    Enum.reduce(@dashboard_context_keys, context, &put_context_value(&2, &1, source))
  end

  defp with_dashboard_context(context, _params), do: context

  defp put_context_param(context, key, %HistoricalWorkflowParams{} = params) do
    case HistoricalWorkflowParams.get(params, key) do
      value when is_binary(value) and value != "" -> Map.put(context, key, value)
      _value -> context
    end
  end

  defp put_context_value(context, key, source) when is_map(source) do
    value =
      source
      |> Map.get(key, Map.get(source, Atom.to_string(key)))
      |> text_param()

    case value do
      nil -> context
      value -> Map.put(context, key, value)
    end
  end

  defp selected_dashboard_context(%{assigns: assigns}) do
    assigns
    |> Map.get(:panel)
    |> selected_panel_inspector()
    |> HistoricalWorkflowContext.build()
    |> dashboard_context()
    |> with_selection_dashboard_context(Map.get(assigns, :dashboard_selection_query))
  end

  defp selected_panel_inspector({:data_link, inspector}), do: inspector
  defp selected_panel_inspector(_panel), do: %{}

  defp dashboard_context(%HistoricalWorkflowContext{} = context) do
    Enum.reduce(@dashboard_context_keys, %{}, &put_context_value(&2, &1, context))
  end

  defp with_selection_dashboard_context(context, query) when is_map(context) do
    query = SelectionQuery.to_params(query)

    context
    |> put_context_value(:dashboard_time_mode, %{"dashboard_time_mode" => query["time_mode"]})
    |> put_context_value(:dashboard_replay_run_id, %{
      "dashboard_replay_run_id" => query["replay_run_id"]
    })
    |> put_context_value(:dashboard_data_view, %{
      "dashboard_data_view" => query["selected_data_view"] || query["data_view"]
    })
    |> put_context_value(:dashboard_limit_mode, %{"dashboard_limit_mode" => query["limit_mode"]})
  end

  defp event_request_group_id(%{payload: payload}) when is_map(payload) do
    payload
    |> Map.get("request_group_id")
    |> text_param()
  end

  defp event_request_group_id(_event), do: nil

  defp put_link_selection(
         socket,
         %HistoricalWorkflowSelectionResult{query: query, link: %DataLink{} = link},
         opts
       ) do
    case Keyword.get(opts, :put_link_selection) do
      callback when is_function(callback, 3) ->
        callback.(socket, query, link)

      _missing ->
        SelectionPanel.put_historical_workflow_link_selection(
          socket,
          query,
          link,
          Keyword.put(opts, :preserve_data_link_action_outcome?, true)
        )
    end
  end

  defp refresh_no_eligible_group(socket, request_group_id, stage) do
    socket
    |> SelectionPanel.refresh_current_historical_workflow_group_selection()
    |> put_action_flash(
      HistoricalWorkflowPresenter.action_outcome(
        :group_stage_transition,
        {:no_eligible, request_group_id, stage}
      )
    )
  end

  defp put_action_flash(socket, %{kind: kind, message: message} = outcome) do
    socket
    |> assign(:data_link_action_outcome, outcome)
    |> put_flash(kind, message)
  end

  defp record_stage_command(opts),
    do: Keyword.get(opts, :record_stage, &HistoricalWorkflowCommands.record_stage/3)

  defp record_group_stage_command(opts),
    do: Keyword.get(opts, :record_group_stage, &HistoricalWorkflowCommands.record_group_stage/3)

  defp record_request_command(opts),
    do: Keyword.get(opts, :record_request, &HistoricalWorkflowCommands.record_request/3)

  defp record_correction_request_command(opts) do
    Keyword.get(
      opts,
      :record_correction_request,
      &HistoricalWorkflowCommands.record_correction_request/3
    )
  end

  defp retry_job_command(opts),
    do: Keyword.get(opts, :retry_job, &HistoricalWorkflowCommands.retry_job/4)

  defp inspect_stale_replacement_job_command(opts) do
    Keyword.get(
      opts,
      :inspect_stale_replacement_job,
      &HistoricalWorkflowCommands.inspect_stale_replacement_job/4
    )
  end

  defp inspect_missing_replacement_job_command(opts) do
    Keyword.get(
      opts,
      :inspect_missing_replacement_job,
      &HistoricalWorkflowCommands.inspect_missing_replacement_job/4
    )
  end

  defp requeue_stale_replacement_job_command(opts) do
    Keyword.get(
      opts,
      :requeue_stale_replacement_job,
      &HistoricalWorkflowCommands.requeue_stale_replacement_job/4
    )
  end

  defp retry_group_failed_jobs_command(opts) do
    Keyword.get(
      opts,
      :retry_group_failed_jobs,
      &HistoricalWorkflowCommands.retry_group_failed_jobs/4
    )
  end

  defp retry_group_failed_jobs_command(opts, request_group_id, scope, mission) do
    command = retry_group_failed_jobs_command(opts)

    case Function.info(command, :arity) do
      {:arity, 4} -> command.(request_group_id, scope, mission, opts)
      {:arity, 3} -> command.(request_group_id, scope, mission)
    end
  end

  defp retry_job_context(retry_event, opts) do
    %{
      target_event_id: event_id(retry_event),
      target_run_id: retry_job_target_run_id(retry_event, opts)
    }
  end

  defp retry_job_target_run_id(retry_event, opts) do
    case text_param(Keyword.get(opts, :replacement_run_id)) do
      nil -> run_id(retry_event)
      replacement_run_id -> replacement_run_id
    end
  end

  defp replacement_target_run_id(event, opts) do
    case text_param(Keyword.get(opts, :replacement_run_id)) do
      nil -> run_id(event)
      replacement_run_id -> replacement_run_id
    end
  end

  defp text_param(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp text_param(_value), do: nil
end
