defmodule CadenceWeb.OpsDataOperationsLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias CadenceWeb.OpsDataOperationsLive.{
    HistoricalWorkflowCommands,
    HistoricalWorkflowRequestDefaults
  }

  alias CadenceWeb.OpsDataOperationsLive.Presentation
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
        surface_id={if(@data_operations_admin?, do: "data_operations_manage", else: "data_operations")}
        host_scope="mission"
        mission_id={@current_mission.mission_id}
        query_params={if(@selected_group_id, do: %{"group" => @selected_group_id}, else: %{})}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
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

  defp request_error(socket, reason) do
    socket
    |> assign(:request_error, error_text(reason))
    |> put_flash(:error, error_text(reason))
  end

  defp error_text(:confirmation_required), do: "Confirm the request before recording it."
  defp error_text(:invalid_request), do: "Historical request parameters are invalid."
  defp error_text({:missing_field, field}), do: "#{field} is required."
  defp error_text(_reason), do: "Data operation failed."

  defp text(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp text(_value), do: nil
end
