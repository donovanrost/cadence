defmodule CadenceWeb.OpsDataOperationsLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias CadenceWeb.OpsDataOperationsLive.{
    HistoricalWorkflowCommands,
    HistoricalWorkflowRequestDefaults
  }

  alias CadenceWeb.OpsDataOperationsLive.Presentation
  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.JS

  @request_context_keys ~w(
    workflow run_id realm data_source_id source_binding_id observable_id point_id point_ids
    source_from source_to dashboard_id dashboard_version dashboard_time_mode
    dashboard_replay_run_id dashboard_data_view dashboard_limit_mode
    comparison_review_request_event_id comparison_review_request_kind
    comparison_review_open_count comparison_review_open_placement_ids
    comparison_review_workflow_kind comparison_review_workflow_action
    comparison_review_workflow_selection_kind comparison_review_workflow_selection_count
    comparison_review_primary_data_view comparison_review_compare_data_view
    comparison_review_scope_kind comparison_review_scope_ids comparison_review_contact_ids
    comparison_review_resource_ids comparison_review_transport_ids
    comparison_review_source_endpoint_ids comparison_review_ground_station_ids
    comparison_review_scope_link_ids reason
  )

  @request_visible_fields ~w(
    workflow run_id realm data_source_id source_binding_id point_ids source_from source_to reason
    confirmed
  )a

  @request_hidden_fields [
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
    :observable_id,
    :point_id
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Data Operations")
     |> assign(:ops_nav_item, :data_operations)
     |> assign(:data_operations_admin?, socket.assigns.live_action == :manage)
     |> assign(:request_error, nil)
     |> assign(:selected_group, nil)
     |> assign(:selected_group_id, nil)
     |> assign(:operation_groups_empty?, true)
     |> assign(:request_form, to_form(request_defaults(%{}), as: :historical_workflow_request))
     |> stream(:data_operation_groups, [], dom_id: & &1["__dom_id"])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      socket
      |> assign(:selected_group_id, text(params["group"]))
      |> assign(
        :request_form,
        to_form(request_defaults(params), as: :historical_workflow_request)
      )
      |> refresh_groups()

    {:noreply, socket}
  end

  @impl true
  def handle_event("validate_request", %{"historical_workflow_request" => params}, socket)
      when is_map(params) do
    if string_form_values?(params) do
      {:noreply, assign(socket, :request_form, to_form(params, as: :historical_workflow_request))}
    else
      {:noreply, request_error(socket, :invalid_request)}
    end
  end

  def handle_event("validate_request", _params, socket) do
    {:noreply, request_error(socket, :invalid_request)}
  end

  def handle_event(
        "record_historical_workflow_request",
        %{"historical_workflow_request" => request_params} = params,
        socket
      )
      when is_map(request_params) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case confirmed_request(params) do
      {:ok, params} ->
        case HistoricalWorkflowCommands.record_request(params, scope, mission) do
          {:ok, [event | _events], _selection_params} ->
            group_id = Presentation.group_id(event)

            {:noreply,
             socket
             |> put_flash(
               :info,
               "Historical data request recorded. Data Operations now owns the workflow."
             )
             |> push_patch(
               to: ~p"/missions/#{mission.mission_id}/ops/data-operations?#{%{group: group_id}}"
             )}

          {:error, reason} ->
            {:noreply, request_error(socket, reason)}
        end

      {:error, reason} ->
        {:noreply, request_error(socket, reason)}
    end
  end

  def handle_event("record_historical_workflow_request", _params, socket) do
    {:noreply, request_error(socket, :invalid_request)}
  end

  def handle_event(
        "transition_group",
        _params,
        %{assigns: %{data_operations_admin?: false}} = socket
      ) do
    {:noreply,
     put_flash(socket, :error, "Workflow transitions require Data Operations administration.")}
  end

  def handle_event(
        "transition_group",
        %{"group-id" => group_id, "stage" => stage},
        socket
      )
      when is_binary(group_id) and stage in ~w(approved rejected started completed failed) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    group = Enum.find(operation_groups(socket), &(&1.id == group_id))

    params = %{
      "historical_workflow_group" => %{
        "workflow" => group && group.workflow,
        "stage" => stage,
        "request_group_id" => group_id,
        "confirmed" => "confirmed"
      }
    }

    case HistoricalWorkflowCommands.record_group_stage(params, scope, mission) do
      {:ok, _events, _jobs} ->
        {:noreply,
         socket
         |> put_flash(:info, "Workflow group #{stage} transition recorded.")
         |> refresh_groups()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_text(reason))}
    end
  end

  def handle_event("transition_group", _params, socket) do
    {:noreply, put_flash(socket, :error, "Historical request parameters are invalid.")}
  end

  def handle_event("retry_group", _params, %{assigns: %{data_operations_admin?: false}} = socket) do
    {:noreply,
     put_flash(socket, :error, "Workflow recovery requires Data Operations administration.")}
  end

  def handle_event("retry_group", %{"group-id" => group_id}, socket)
      when is_binary(group_id) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case HistoricalWorkflowCommands.retry_group_failed_jobs(group_id, scope, mission) do
      {:ok, _summary} ->
        {:noreply,
         socket
         |> put_flash(:info, "Eligible failed workflow jobs were queued for retry.")
         |> refresh_groups()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_text(reason))}
    end
  end

  def handle_event("retry_group", _params, socket) do
    {:noreply, put_flash(socket, :error, "Historical request parameters are invalid.")}
  end

  def handle_event(
        "request_correction",
        _params,
        %{assigns: %{data_operations_admin?: false}} = socket
      ) do
    {:noreply,
     put_flash(socket, :error, "Correction requests require Data Operations administration.")}
  end

  def handle_event(
        "request_correction",
        %{"event-id" => event_id, "group-id" => group_id},
        socket
      )
      when is_binary(event_id) and is_binary(group_id) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    with %{failed_events: failed_events, workflow: workflow} <-
           Enum.find(operation_groups(socket), &(&1.id == group_id)),
         %{run_id: run_id, job_id: job_id} <-
           Enum.find(failed_events, &(&1.event_id == event_id)),
         {:ok, _event} <-
           HistoricalWorkflowCommands.record_correction_request(
             %{
               "historical_workflow_correction" => %{
                 "workflow" => workflow,
                 "request_group_id" => group_id,
                 "original_event_id" => event_id,
                 "original_run_id" => run_id,
                 "original_job_id" => job_id,
                 "confirmed" => "confirmed"
               }
             },
             scope,
             mission
           ) do
      {:noreply,
       socket
       |> put_flash(:info, "Correction request recorded against the failed workflow item.")
       |> refresh_groups()}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "The failed workflow item is no longer available.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_text(reason))}
    end
  end

  def handle_event("request_correction", _params, socket) do
    {:noreply, put_flash(socket, :error, "Historical request parameters are invalid.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="ops-data-operations-component"
        v-component="FederatedFullPageSurface"
        application_key="ops_console"
        surface_id="data_operations"
        host_scope="mission"
        mission_id={@current_mission.mission_id}
        query_params={%{}}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end

  defp page_dto(mission, admin?, admin_eligible?, selected_group_id, groups_empty?) do
    navigation =
      %{}
      |> maybe_put_manage_navigation(mission, admin?, admin_eligible?, selected_group_id)
      |> maybe_put_reader_navigation(mission, admin?, selected_group_id)

    %{
      id: "ops-data-operations-page",
      selected_group_id: selected_group_id,
      groups_empty: groups_empty?,
      navigation: navigation
    }
  end

  defp maybe_put_manage_navigation(navigation, _mission, true, _eligible?, _selected_group_id),
    do: navigation

  defp maybe_put_manage_navigation(navigation, _mission, false, false, _selected_group_id),
    do: navigation

  defp maybe_put_manage_navigation(navigation, mission, false, true, selected_group_id) do
    Map.put(navigation, :manage, %{
      id: "data-operations-manage-link",
      label: "Manage recovery",
      href:
        ~p"/missions/#{mission.mission_id}/ops/data-operations/manage?#{%{group: selected_group_id}}"
    })
  end

  defp maybe_put_reader_navigation(navigation, _mission, false, _selected_group_id),
    do: navigation

  defp maybe_put_reader_navigation(navigation, mission, true, selected_group_id) do
    Map.put(navigation, :reader, %{
      id: "data-operations-reader-link",
      label: "Reader view",
      href: ~p"/missions/#{mission.mission_id}/ops/data-operations?#{%{group: selected_group_id}}"
    })
  end

  defp request_form_dto(form, request_error) do
    %{
      id: "data-operation-request-form",
      values: request_values(form),
      fields: %{
        workflow:
          request_field_dto(form, :workflow, "select", "Workflow",
            options: [
              %{label: "Backfill", value: "backfill"},
              %{label: "Import", value: "import"}
            ]
          ),
        run_id: request_field_dto(form, :run_id, "text", "Request group"),
        realm: request_field_dto(form, :realm, "text", "Realm"),
        data_source_id: request_field_dto(form, :data_source_id, "text", "Data source"),
        source_binding_id: request_field_dto(form, :source_binding_id, "text", "Source binding"),
        point_ids:
          request_field_dto(form, :point_ids, "text", "Point IDs",
            placeholder: "HK.counter, HK.voltage"
          ),
        source_from: request_field_dto(form, :source_from, "text", "Source from"),
        source_to: request_field_dto(form, :source_to, "text", "Source to"),
        reason: request_field_dto(form, :reason, "text", "Reason"),
        confirmed: request_field_dto(form, :confirmed, "checkbox", "Confirm request")
      },
      hidden_fields:
        Enum.map(@request_hidden_fields, fn field ->
          %{name: form[field].name, value_key: Atom.to_string(field)}
        end),
      error:
        if(request_error,
          do: %{id: "data-operation-request-error", message: request_error},
          else: nil
        ),
      submit: %{id: "data-operation-request-submit", label: "Record request"}
    }
  end

  defp request_field_dto(form, field, type, label, options \\ []) do
    form_field = form[field]

    %{
      id: form_field.id,
      name: form_field.name,
      type: type,
      label: label,
      placeholder: Keyword.get(options, :placeholder),
      options: Keyword.get(options, :options, [])
    }
  end

  defp request_values(form) do
    (@request_visible_fields ++ @request_hidden_fields)
    |> Map.new(fn field ->
      {Atom.to_string(field), form |> Form.input_value(field) |> form_value()}
    end)
  end

  defp form_value(nil), do: ""
  defp form_value(value) when is_binary(value), do: value
  defp form_value(value) when is_boolean(value), do: to_string(value)
  defp form_value(value) when is_atom(value), do: Atom.to_string(value)
  defp form_value(value) when is_integer(value), do: Integer.to_string(value)
  defp form_value(value) when is_float(value), do: Float.to_string(value)
  defp form_value(_value), do: ""

  defp selected_group_dto(nil, _mission, _admin?), do: nil

  defp selected_group_dto(group, mission, admin?) do
    %{
      id: group.id,
      workflow: group.workflow,
      state: group.state,
      context: %{
        realm: display_text(group.realm) || "realm unknown",
        data_source_id: display_text(group.data_source_id) || "source unknown",
        binding_id: display_text(group.binding_id) || "binding unknown"
      },
      progress: [
        %{label: "Requested", value: group.requested},
        %{label: "Approved", value: group.approved},
        %{label: "Started", value: group.started},
        %{label: "Completed", value: group.completed}
      ],
      affected_dashboards:
        Enum.map(group.affected_dashboards, &affected_dashboard_dto(&1, mission)),
      comparison_reviews: Enum.map(group.comparison_reviews, &comparison_review_dto/1),
      audit_events: Enum.map(group.audit_events, &audit_event_dto/1)
    }
    |> maybe_put_recovery(group, admin?)
  end

  defp affected_dashboard_dto(dashboard, mission) do
    %{
      id: "data-operation-dashboard-#{dashboard.dashboard_id}",
      label: dashboard.dashboard_id,
      href:
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{dashboard.query}"
    }
  end

  defp comparison_review_dto(review) do
    request_event_id = display_text(Map.get(review, "request_event_id"))

    %{
      id: "data-operation-comparison-#{request_event_id}",
      request_event_id: request_event_id,
      request_kind: display_text(Map.get(review, "request_kind")) || "comparison review",
      open_count: display_text(Map.get(review, "open_count")) || "?",
      open_placement_ids:
        display_text(Map.get(review, "open_placement_ids")) || "placements not recorded"
    }
  end

  defp audit_event_dto(event) do
    event_id = Map.get(event, :backfill_lifecycle_event_id)

    %{
      id: "data-operation-event-#{event_id}",
      event_type: display_text(Map.get(event, :event_type)),
      reason: display_text(Map.get(event, :reason)) || "no reason recorded",
      occurred_at: format_time(Map.get(event, :occurred_at))
    }
  end

  defp maybe_put_recovery(selected_group, _group, false), do: selected_group

  defp maybe_put_recovery(selected_group, group, true) do
    Map.put(selected_group, :recovery, %{
      transitions: transition_actions(group),
      retry: retry_action(group),
      failures: Enum.map(group.failed_events, &failure_dto(&1, group.id))
    })
  end

  defp transition_actions(group) do
    [
      {"approved", "Approve", group.eligibility.approve},
      {"rejected", "Reject", group.eligibility.reject},
      {"started", "Start", group.eligibility.start},
      {"completed", "Complete", group.eligibility.complete},
      {"failed", "Mark failed", group.eligibility.fail}
    ]
    |> Enum.filter(fn {_stage, _label, count} -> count > 0 end)
    |> Enum.map(fn {stage, label, count} ->
      %{
        id: "data-operation-transition-#{stage}",
        label: "#{label} (#{count})",
        confirm: "Record the #{stage} transition for this request group?",
        payload: %{"group-id" => group.id, "stage" => stage}
      }
    end)
  end

  defp retry_action(%{failed: failed}) when failed <= 0, do: nil

  defp retry_action(group) do
    %{
      id: "data-operation-retry-group",
      label: "Retry eligible failures",
      confirm: "Retry every eligible failed job in this request group?",
      payload: %{"group-id" => group.id}
    }
  end

  defp failure_dto(failed_event, group_id) do
    %{
      label: display_text(failed_event.point_id) || display_text(failed_event.run_id),
      recovery_action: display_text(failed_event.recovery_action) || "manual investigation"
    }
    |> maybe_put_correction_action(failed_event, group_id)
  end

  defp maybe_put_correction_action(failure, failed_event, _group_id)
       when failed_event.recovery_action != "correct_workflow_request",
       do: failure

  defp maybe_put_correction_action(failure, failed_event, group_id) do
    Map.put(failure, :correction, %{
      id: "data-operation-correct-#{failed_event.event_id}",
      label: "Request correction",
      confirm: "Create a corrected request that supersedes this failed item?",
      payload: %{"group-id" => group_id, "event-id" => failed_event.event_id}
    })
  end

  defp refresh_groups(socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    groups =
      mission.mission_id
      |> Cadence.list_telemetry_backfill_lifecycle_events(
        organization_id: scope.organization_id,
        limit: 1_000
      )
      |> Presentation.build()

    selected_group =
      case socket.assigns.selected_group_id do
        nil -> List.first(groups)
        group_id -> Enum.find(groups, &(&1.id == group_id))
      end

    selected_group_id = selected_group && selected_group.id
    group_rows = Enum.map(groups, &group_row_dto(&1, mission))

    socket
    |> assign(:operation_groups, groups)
    |> assign(:operation_groups_empty?, groups == [])
    |> assign(:selected_group, selected_group)
    |> assign(:selected_group_id, selected_group_id)
    |> stream(:data_operation_groups, group_rows, reset: true, dom_id: & &1["__dom_id"])
  end

  defp group_row_dto(group, mission) do
    %{
      "__dom_id" => group.dom_id,
      "id" => group.id,
      "href" => ~p"/missions/#{mission.mission_id}/ops/data-operations?#{%{group: group.id}}",
      "state" => group.state,
      "workflow" => group.workflow,
      "size" => group.size,
      "progress" => group.progress
    }
  end

  defp operation_groups(socket), do: socket.assigns[:operation_groups] || []

  defp confirmed_request(%{"historical_workflow_request" => params}) when is_map(params) do
    cond do
      not string_form_values?(params) ->
        {:error, :invalid_request}

      params["confirmed"] in ["true", "on", "confirmed"] ->
        {:ok, %{"historical_workflow_request" => params}}

      true ->
        {:error, :confirmation_required}
    end
  end

  defp confirmed_request(_params), do: {:error, :invalid_request}

  defp string_form_values?(params) do
    Enum.all?(params, fn {key, value} -> is_binary(key) and is_binary(value) end)
  end

  defp request_defaults(params) do
    aliases = %{
      "dashboard_time_mode" => params["dashboard_time_mode"] || params["time_mode"],
      "dashboard_replay_run_id" => params["dashboard_replay_run_id"] || params["replay_run_id"],
      "dashboard_data_view" =>
        params["dashboard_data_view"] || params["selected_data_view"] || params["data_view"],
      "dashboard_limit_mode" => params["dashboard_limit_mode"] || params["limit_mode"]
    }

    context =
      @request_context_keys
      |> Map.new(&{&1, params[&1]})
      |> Map.merge(aliases)

    context
    |> HistoricalWorkflowRequestDefaults.new()
    |> HistoricalWorkflowRequestDefaults.form_params()
    |> Map.merge(
      context
      |> Map.take(@request_context_keys)
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()
    )
    |> Map.put_new("confirmed", "")
  end

  defp admin_eligible?(%{capabilities: %MapSet{} = capabilities}) do
    MapSet.member?(capabilities, :organization_admin) or
      MapSet.member?(capabilities, :platform_admin)
  end

  defp admin_eligible?(_scope), do: false

  defp format_time(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%SZ")

  defp format_time(_datetime), do: "unknown"

  defp request_error(socket, reason) do
    socket
    |> assign(:request_error, error_text(reason))
    |> put_flash(:error, error_text(reason))
  end

  defp error_text(:confirmation_required), do: "Confirm the request before recording it."
  defp error_text(:invalid_request), do: "Historical request parameters are invalid."
  defp error_text({:missing_field, field}), do: "#{field} is required."
  defp error_text(_reason), do: "Data operation failed."

  defp display_text(nil), do: nil

  defp display_text(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp display_text(value) when is_atom(value), do: Atom.to_string(value)
  defp display_text(value) when is_integer(value), do: Integer.to_string(value)
  defp display_text(_value), do: nil

  defp text(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp text(_value), do: nil
end
