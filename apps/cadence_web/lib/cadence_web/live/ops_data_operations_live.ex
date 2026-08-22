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
     |> stream(:data_operation_groups, [], dom_id: & &1.dom_id)}
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
  def handle_event("validate_request", %{"historical_workflow_request" => params}, socket) do
    {:noreply, assign(socket, :request_form, to_form(params, as: :historical_workflow_request))}
  end

  def handle_event("record_historical_workflow_request", params, socket) do
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
      when stage in ~w(approved rejected started completed failed) do
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

  def handle_event("retry_group", _params, %{assigns: %{data_operations_admin?: false}} = socket) do
    {:noreply,
     put_flash(socket, :error, "Workflow recovery requires Data Operations administration.")}
  end

  def handle_event("retry_group", %{"group-id" => group_id}, socket) do
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
      ) do
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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="ops-data-operations-page" class="min-h-0 flex-1 overflow-y-auto">
        <div class="mx-auto max-w-[96rem] space-y-5 px-5 py-6">
          <header class="flex flex-col gap-3 border-b border-primary/20 pb-4 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <p class="hud-label">System / Historical data plane</p>
              <h1 class="mt-1 text-xl font-semibold tracking-tight">Data Operations</h1>
              <p class="mt-1 max-w-3xl text-sm text-base-content/60">
                Request, follow, correct, and close historical telemetry repair without returning to the dashboard that exposed the gap.
              </p>
            </div>
            <div class="flex flex-wrap gap-2">
              <.link
                :if={admin_eligible?(@current_scope) and not @data_operations_admin?}
                id="data-operations-manage-link"
                navigate={~p"/missions/#{@current_mission.mission_id}/ops/data-operations/manage?#{%{group: @selected_group_id}}"}
                class="btn btn-sm btn-outline"
              >
                <.icon name="hero-wrench-screwdriver" class="h-4 w-4" /> Manage recovery
              </.link>
              <.link
                :if={@data_operations_admin?}
                id="data-operations-reader-link"
                navigate={~p"/missions/#{@current_mission.mission_id}/ops/data-operations?#{%{group: @selected_group_id}}"}
                class="btn btn-sm btn-ghost"
              >
                Reader view
              </.link>
            </div>
          </header>

          <section class="grid min-h-[42rem] gap-4 xl:grid-cols-[22rem_minmax(0,1fr)_24rem]">
            <aside class="border border-base-300 bg-base-200/45">
              <div class="border-b border-base-300 px-3 py-2">
                <h2 class="hud-label">Request groups</h2>
              </div>
              <div id="data-operation-groups" phx-update="stream" class="divide-y divide-base-300">
                <div id="data-operation-groups-empty" class="hidden only:block p-5 text-sm text-base-content/50">
                  No historical data operations have been recorded for this mission.
                </div>
                <.link
                  :for={{dom_id, group} <- @streams.data_operation_groups}
                  id={dom_id}
                  patch={~p"/missions/#{@current_mission.mission_id}/ops/data-operations?#{%{group: group.id}}"}
                  class={[
                    "block space-y-2 px-3 py-3 hover:bg-primary/5",
                    @selected_group_id == group.id && "border-l-2 border-primary bg-primary/10"
                  ]}
                  data-operation-state={group.state}
                  data-operation-workflow={group.workflow}
                >
                  <div class="flex items-center justify-between gap-2">
                    <span class="truncate font-mono text-xs font-semibold">{group.id}</span>
                    <span class={status_badge_class(group.state)}>{group.state}</span>
                  </div>
                  <div class="flex items-center justify-between text-[0.6875rem] text-base-content/55">
                    <span>{group.workflow} · {group.size} item(s)</span>
                    <span>{group.progress}</span>
                  </div>
                </.link>
              </div>
            </aside>

            <section id="data-operation-detail" class="min-w-0 border border-base-300 bg-base-100">
              <div :if={is_nil(@selected_group)} class="grid min-h-[34rem] place-items-center p-8 text-center">
                <div class="max-w-sm">
                  <.icon name="hero-circle-stack" class="mx-auto h-8 w-8 text-base-content/30" />
                  <h2 class="mt-3 text-sm font-semibold">Select an operation</h2>
                  <p class="mt-1 text-sm text-base-content/55">Choose a request group to follow progress, affected dashboards, recovery, and audit evidence.</p>
                </div>
              </div>

              <div :if={@selected_group} class="space-y-5 p-5">
                <div class="flex flex-col gap-3 border-b border-base-300 pb-4 md:flex-row md:items-start md:justify-between">
                  <div class="min-w-0">
                    <p class="hud-label">{@selected_group.workflow} request group</p>
                    <h2 id="data-operation-group-id" class="mt-1 break-all font-mono text-sm font-semibold">{@selected_group.id}</h2>
                    <p class="mt-2 text-xs text-base-content/55">
                      {@selected_group.realm || "realm unknown"} · {@selected_group.data_source_id || "source unknown"} · {@selected_group.binding_id || "binding unknown"}
                    </p>
                  </div>
                  <span class={status_badge_class(@selected_group.state)}>{@selected_group.state}</span>
                </div>

                <dl id="data-operation-progress" class="grid grid-cols-2 gap-px bg-base-300 sm:grid-cols-4">
                  <.progress_cell label="Requested" value={@selected_group.requested} />
                  <.progress_cell label="Approved" value={@selected_group.approved} />
                  <.progress_cell label="Started" value={@selected_group.started} />
                  <.progress_cell label="Completed" value={@selected_group.completed} />
                </dl>

                <section id="data-operation-affected-dashboards" class="space-y-2">
                  <h3 class="hud-label">Affected dashboards</h3>
                  <p :if={@selected_group.affected_dashboards == []} class="text-xs text-base-content/45">No dashboard origin was recorded.</p>
                  <div class="flex flex-wrap gap-2">
                    <.link
                      :for={dashboard <- @selected_group.affected_dashboards}
                      id={"data-operation-dashboard-#{dashboard.dashboard_id}"}
                      navigate={~p"/missions/#{@current_mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{dashboard.query}"}
                      class="btn btn-xs btn-outline"
                    >
                      <.icon name="hero-squares-2x2" class="h-3.5 w-3.5" /> {dashboard.dashboard_id}
                    </.link>
                  </div>
                </section>

                <section id="data-operation-comparison-reviews" class="space-y-2">
                  <h3 class="hud-label">Comparison & revision context</h3>
                  <p :if={@selected_group.comparison_reviews == []} class="text-xs text-base-content/45">No comparison-review origin is attached.</p>
                  <div
                    :for={review <- @selected_group.comparison_reviews}
                    id={"data-operation-comparison-#{review["request_event_id"]}"}
                    class="border border-base-300 bg-base-200/40 p-3 text-xs"
                  >
                    <p class="font-mono font-semibold">{review["request_event_id"]}</p>
                    <p class="mt-1 text-base-content/60">
                      {review["request_kind"] || "comparison review"} · {review["open_count"] || "?"} open finding(s)
                    </p>
                    <p class="mt-1 font-mono text-base-content/45">{review["open_placement_ids"] || "placements not recorded"}</p>
                  </div>
                </section>

                <section id="data-operation-audit" class="space-y-2">
                  <h3 class="hud-label">Audit history</h3>
                  <div class="divide-y divide-base-300 border border-base-300">
                    <div
                      :for={event <- @selected_group.audit_events}
                      id={"data-operation-event-#{event.backfill_lifecycle_event_id}"}
                      class="grid gap-1 px-3 py-2 text-xs sm:grid-cols-[10rem_minmax(0,1fr)_12rem]"
                    >
                      <span class="font-mono font-semibold">{event.event_type}</span>
                      <span class="truncate text-base-content/60">{event.reason || "no reason recorded"}</span>
                      <time class="font-mono text-base-content/45 sm:text-right">{format_time(event.occurred_at)}</time>
                    </div>
                  </div>
                </section>
              </div>
            </section>

            <aside class="space-y-4">
              <section id="data-operation-request-panel" class="border border-base-300 bg-base-200/45 p-4">
                <h2 class="hud-label">New historical request</h2>
                <p class="mt-1 text-xs text-base-content/55">Dashboard and Explore links prefill this same durable request.</p>
                <.form
                  for={@request_form}
                  id="data-operation-request-form"
                  phx-change="validate_request"
                  phx-submit="record_historical_workflow_request"
                  class="mt-4 space-y-3"
                >
                  <.input field={@request_form[:workflow]} type="select" label="Workflow" options={[{"Backfill", "backfill"}, {"Import", "import"}]} />
                  <.input field={@request_form[:run_id]} type="text" label="Request group" />
                  <.input field={@request_form[:realm]} type="text" label="Realm" />
                  <.input field={@request_form[:data_source_id]} type="text" label="Data source" />
                  <.input field={@request_form[:source_binding_id]} type="text" label="Source binding" />
                  <.input field={@request_form[:point_ids]} type="text" label="Point IDs" placeholder="HK.counter, HK.voltage" />
                  <div class="grid grid-cols-2 gap-2">
                    <.input field={@request_form[:source_from]} type="text" label="Source from" />
                    <.input field={@request_form[:source_to]} type="text" label="Source to" />
                  </div>
                  <.input field={@request_form[:reason]} type="text" label="Reason" />
                  <.input field={@request_form[:confirmed]} type="checkbox" label="Confirm request" />
                  <%= for field <- hidden_request_fields() do %>
                    <input type="hidden" name={@request_form[field].name} value={@request_form[field].value} />
                  <% end %>
                  <p :if={@request_error} id="data-operation-request-error" class="text-xs text-error">{@request_error}</p>
                  <button id="data-operation-request-submit" type="submit" class="btn btn-sm btn-primary w-full">
                    <.icon name="hero-document-plus" class="h-4 w-4" /> Record request
                  </button>
                </.form>
              </section>

              <section :if={@data_operations_admin? and @selected_group} id="data-operation-recovery-panel" class="border border-warning/35 bg-warning/5 p-4">
                <h2 class="hud-label">Privileged workflow controls</h2>
                <p class="mt-1 text-xs text-base-content/55">Transitions and recovery write audit events and may change canonical historical telemetry.</p>
                <div class="mt-3 grid grid-cols-2 gap-2">
                  <button
                    :for={{stage, label} <- transition_actions(@selected_group)}
                    id={"data-operation-transition-#{stage}"}
                    type="button"
                    phx-click="transition_group"
                    phx-value-group-id={@selected_group.id}
                    phx-value-stage={stage}
                    data-confirm={"Record the #{stage} transition for this request group?"}
                    class="btn btn-xs btn-outline"
                  >{label}</button>
                </div>
                <button
                  :if={@selected_group.failed > 0}
                  id="data-operation-retry-group"
                  type="button"
                  phx-click="retry_group"
                  phx-value-group-id={@selected_group.id}
                  data-confirm="Retry every eligible failed job in this request group?"
                  class="btn btn-xs btn-warning mt-3 w-full"
                >Retry eligible failures</button>
                <div :if={@selected_group.failed_events != []} class="mt-3 space-y-2">
                  <div :for={failure <- @selected_group.failed_events} class="border border-base-300 bg-base-100 p-2 text-xs">
                    <p class="font-mono">{failure.point_id || failure.run_id}</p>
                    <p class="mt-1 text-base-content/55">{failure.recovery_action || "manual investigation"}</p>
                    <button
                      :if={failure.recovery_action == "correct_workflow_request"}
                      id={"data-operation-correct-#{failure.event_id}"}
                      type="button"
                      phx-click="request_correction"
                      phx-value-group-id={@selected_group.id}
                      phx-value-event-id={failure.event_id}
                      data-confirm="Create a corrected request that supersedes this failed item?"
                      class="btn btn-xs btn-outline mt-2"
                    >Request correction</button>
                  </div>
                </div>
              </section>
            </aside>
          </section>
        </div>
      </main>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp progress_cell(assigns) do
    ~H"""
    <div class="bg-base-100 px-3 py-3">
      <dt class="hud-label">{@label}</dt>
      <dd class="mt-1 font-mono text-lg font-semibold">{@value}</dd>
    </div>
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

    socket
    |> assign(:operation_groups, groups)
    |> assign(:operation_groups_empty?, groups == [])
    |> assign(:selected_group, selected_group)
    |> assign(:selected_group_id, selected_group_id)
    |> stream(:data_operation_groups, groups, reset: true, dom_id: & &1.dom_id)
  end

  defp operation_groups(socket), do: socket.assigns[:operation_groups] || []

  defp confirmed_request(%{"historical_workflow_request" => params}) when is_map(params) do
    if params["confirmed"] in ["true", "on", "confirmed"] do
      {:ok, %{"historical_workflow_request" => params}}
    else
      {:error, :confirmation_required}
    end
  end

  defp confirmed_request(_params), do: {:error, :invalid_request}

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
    |> Map.merge(Map.take(context, @request_context_keys))
    |> Map.put_new("confirmed", "")
  end

  defp hidden_request_fields do
    [
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
    |> Enum.map(fn {stage, label, count} -> {stage, "#{label} (#{count})"} end)
  end

  defp admin_eligible?(%{capabilities: %MapSet{} = capabilities}) do
    MapSet.member?(capabilities, :organization_admin) or
      MapSet.member?(capabilities, :platform_admin)
  end

  defp admin_eligible?(_scope), do: false

  defp status_badge_class(state) do
    [
      "badge badge-xs font-mono",
      cond do
        state in ["completed", "closed"] -> "badge-success"
        state in ["failed", "blocked"] -> "badge-error"
        state in ["started", "in_progress"] -> "badge-info"
        true -> "badge-warning"
      end
    ]
  end

  defp format_time(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%SZ")
  defp format_time(_datetime), do: "unknown"

  defp request_error(socket, reason) do
    socket
    |> assign(:request_error, error_text(reason))
    |> put_flash(:error, error_text(reason))
  end

  defp error_text(:confirmation_required), do: "Confirm the request before recording it."
  defp error_text(:invalid_request), do: "Historical request parameters are invalid."
  defp error_text({:missing_field, field}), do: "#{field} is required."
  defp error_text(reason), do: "Data operation failed: #{inspect(reason)}"

  defp text(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp text(_value), do: nil
end
