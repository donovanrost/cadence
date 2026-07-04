defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflow do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3, to_form: 2]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Cadence.Dashboards.{ComparisonReviewQueue, DataLink, Document}
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowCommands
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowParams
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowPresenter
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowRequestDefaults
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowSelection
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowSelectionResult
  alias CadenceWeb.OpsDashboardShowLive.SelectionPanel

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
            HistoricalWorkflowPresenter.action_outcome(:stage_transition, {:ok, job_result}, %{
              stage: stage,
              target_event_id: event_id(event),
              target_run_id: run_id(event)
            })
          )
          |> put_event_selection(event, params, opts)

        {:error, reason} ->
          put_action_flash(
            socket,
            HistoricalWorkflowPresenter.action_outcome(
              :stage_transition,
              {:error, reason},
              %{stage: stage, target_event_id: HistoricalWorkflowParams.get(params, :event_id)}
            )
          )
      end
    else
      put_action_flash(
        socket,
        HistoricalWorkflowPresenter.action_outcome(:stage_transition, :unconfirmed, %{
          stage: stage,
          target_event_id: HistoricalWorkflowParams.get(params, :event_id)
        })
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
                target_run_id: run_id(selection.event)
              }
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
              %{stage: stage, target_event_id: HistoricalWorkflowParams.get(params, :event_id)}
            )
          )
      end
    else
      put_action_flash(
        socket,
        HistoricalWorkflowPresenter.action_outcome(:group_stage_transition, :unconfirmed, %{
          stage: stage,
          target_event_id: HistoricalWorkflowParams.get(params, :event_id)
        })
      )
    end
  end

  def record_request(socket, params, opts \\ []) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    params = HistoricalWorkflowParams.request_params(params)

    if HistoricalWorkflowParams.confirmed?(params) do
      case record_request_command(opts).(params, scope, mission) do
        {:ok, [event | _events] = events, params} ->
          socket
          |> put_action_flash(
            HistoricalWorkflowPresenter.action_outcome(:request, {:ok, events}, %{
              target_event_id: event_id(event),
              target_run_id: run_id(event)
            })
          )
          |> assign(
            :historical_workflow_request_form,
            to_form(request_form_params(socket), as: :historical_workflow_request)
          )
          |> put_event_selection(event, params, opts)

        {:error, reason} ->
          put_action_flash(
            socket,
            HistoricalWorkflowPresenter.action_outcome(:request, {:error, reason})
          )
      end
    else
      put_action_flash(
        socket,
        HistoricalWorkflowPresenter.action_outcome(:request, :unconfirmed)
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
            HistoricalWorkflowPresenter.action_outcome(:correction_request, {:ok, event}, %{
              target_event_id: event_id(event),
              target_run_id: run_id(event)
            })
          )
          |> put_event_selection(event, params, opts)

        {:error, reason} ->
          put_action_flash(
            socket,
            HistoricalWorkflowPresenter.action_outcome(:correction_request, {:error, reason}, %{
              target_event_id: HistoricalWorkflowParams.get(params, :original_event_id),
              target_run_id: HistoricalWorkflowParams.get(params, :original_run_id)
            })
          )
      end
    else
      put_action_flash(
        socket,
        HistoricalWorkflowPresenter.action_outcome(:correction_request, :unconfirmed, %{
          target_event_id: HistoricalWorkflowParams.get(params, :original_event_id),
          target_run_id: HistoricalWorkflowParams.get(params, :original_run_id)
        })
      )
    end
  end

  def retry_job(socket, job_id, event_id, opts \\ []) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case retry_job_command(opts).(job_id, event_id, scope, mission) do
      {:ok, retried_job, retry_event} ->
        socket
        |> put_action_flash(
          HistoricalWorkflowPresenter.action_outcome(
            :retry_job,
            {:ok, retried_job, retry_event},
            %{target_event_id: event_id(retry_event), target_run_id: run_id(retry_event)}
          )
        )
        |> put_event_selection(retry_event, %{}, opts)

      {:error, reason} ->
        put_action_flash(
          socket,
          HistoricalWorkflowPresenter.action_outcome(:retry_job, {:error, reason}, %{
            target_event_id: event_id
          })
        )
    end
  end

  def inspect_stale_replacement_job(socket, job_id, event_id, opts \\ []) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case inspect_stale_replacement_job_command(opts).(job_id, event_id, scope, mission) do
      {:ok, inspection_event} ->
        socket
        |> put_action_flash(
          HistoricalWorkflowPresenter.action_outcome(
            :stale_replacement_job_inspection,
            {:ok, inspection_event},
            %{
              target_event_id: event_id(inspection_event),
              target_run_id: run_id(inspection_event)
            }
          )
        )
        |> put_event_selection(inspection_event, %{}, opts)

      {:error, reason} ->
        put_action_flash(
          socket,
          HistoricalWorkflowPresenter.action_outcome(
            :stale_replacement_job_inspection,
            {:error, reason},
            %{target_event_id: event_id}
          )
        )
    end
  end

  def inspect_missing_replacement_job(socket, request_group_id, replacement_run_id, opts \\ []) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

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
              target_run_id: run_id(inspection_event)
            }
          )
        )
        |> put_event_selection(inspection_event, %{}, opts)

      {:error, reason} ->
        put_action_flash(
          socket,
          HistoricalWorkflowPresenter.action_outcome(
            :missing_replacement_job_inspection,
            {:error, reason},
            %{target_run_id: replacement_run_id}
          )
        )
    end
  end

  def requeue_stale_replacement_job(socket, job_id, event_id, opts \\ []) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case requeue_stale_replacement_job_command(opts).(job_id, event_id, scope, mission) do
      {:ok, requeued_job, requeue_event} ->
        socket
        |> put_action_flash(
          HistoricalWorkflowPresenter.action_outcome(
            :stale_replacement_job_requeue,
            {:ok, requeued_job, requeue_event},
            %{
              target_event_id: event_id(requeue_event),
              target_run_id: run_id(requeue_event)
            }
          )
        )
        |> put_event_selection(requeue_event, %{}, opts)

      {:error, reason} ->
        put_action_flash(
          socket,
          HistoricalWorkflowPresenter.action_outcome(
            :stale_replacement_job_requeue,
            {:error, reason},
            %{target_event_id: event_id}
          )
        )
    end
  end

  def retry_group_failed_jobs(socket, request_group_id, event_id, opts \\ []) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case retry_group_failed_jobs_command(opts, request_group_id, scope, mission) do
      {:ok, summary} ->
        selection = HistoricalWorkflowSelection.retry_selection(summary, event_id)

        socket
        |> put_action_flash(
          HistoricalWorkflowPresenter.action_outcome(:retry_group_failed_jobs, {:ok, summary}, %{
            target_event_id: selection.link.target_id,
            retry_run_ids: Keyword.get(opts, :retry_run_ids)
          })
        )
        |> put_link_selection(selection, opts)

      {:error, reason} ->
        put_action_flash(
          socket,
          HistoricalWorkflowPresenter.action_outcome(
            :retry_group_failed_jobs,
            {:error, reason},
            %{
              target_event_id: event_id
            }
          )
        )
    end
  end

  def request_form_defaults(%{assigns: assigns} = socket) do
    HistoricalWorkflowPresenter.request_form_defaults(%{
      realm: assign_value(assigns, :dashboard_data_realm, "backfill"),
      data_source_id: assign_value(assigns, :dashboard_data_source_id),
      source_binding_id: assign_value(assigns, :dashboard_source_binding_id),
      point_id: request_point_id(socket),
      source_from: assign_value(assigns, :dashboard_time_from),
      source_to: assign_value(assigns, :dashboard_time_to),
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

  defp text_param(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp text_param(_value), do: nil
end
