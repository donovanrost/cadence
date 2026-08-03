defmodule CadenceWeb.OpsCommandsLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.Reads.Commands
  alias CadenceWeb.OpsContextSnapshot

  @filter_keys ~w(status target query focus_command_id)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Commands")
     |> assign(:ops_nav_item, :commands)
     |> assign(:command_summary, empty_summary())
     |> assign(:command_targets, [])
     |> assign(:commands_empty?, true)
     |> assign(:focus_command_id, nil)
     |> assign(:filter_form, to_form(%{}, as: :filters))
     |> stream(:commands, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = Map.take(params, @filter_keys)
    focus_command_id = present_text(Map.get(filters, "focus_command_id"))
    %{current_scope: scope, current_mission: mission} = socket.assigns

    snapshot =
      Commands.snapshot(scope.organization_id, mission.mission_id, filters: filters)

    ops_context =
      OpsContextSnapshot.pin_command_focus(socket.assigns.ops_context, focus_command_id)

    {:noreply,
     socket
     |> assign(:ops_context, ops_context)
     |> assign(:command_summary, snapshot.summary)
     |> assign(:command_targets, snapshot.targets)
     |> assign(:commands_empty?, snapshot.rows == [])
     |> assign(:focus_command_id, focus_command_id)
     |> assign(:filter_form, to_form(filters, as: :filters))
     |> stream(:commands, snapshot.rows, reset: true)}
  end

  @impl true
  def handle_event("filter", %{"filters" => filters}, socket) do
    filters = Map.put(filters, "focus_command_id", socket.assigns.focus_command_id)
    {:noreply, push_patch(socket, to: commands_path(socket, filters))}
  end

  @impl true
  def handle_event("reset_filters", _params, socket) do
    {:noreply,
     push_patch(
       socket,
       to: commands_path(socket, %{"focus_command_id" => socket.assigns.focus_command_id})
     )}
  end

  @impl true
  def handle_event("follow_command", %{"command-request-id" => command_request_id}, socket) do
    {:noreply,
     push_patch(
       socket,
       to: commands_path(socket, current_filters(socket, command_request_id))
     )}
  end

  @impl true
  def handle_event("clear_command_focus", _params, socket) do
    {:noreply, push_patch(socket, to: commands_path(socket, current_filters(socket, nil)))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="ops-commands-page" class="h-full overflow-y-auto bg-base-100">
        <header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">
          <div class="mx-auto flex max-w-[100rem] flex-col gap-5 xl:flex-row xl:items-end xl:justify-between">
            <div>
              <p class="font-mono text-[0.65rem] uppercase tracking-[0.28em] text-primary/70">
                Mission operations / command posture
              </p>
              <h1 class="mt-1 text-2xl font-bold tracking-tight">Commands</h1>
              <p class="mt-2 max-w-3xl text-sm text-base-content/60">
                Read-only request, queue, release, transport, and verification state. Command
                creation, approval, and release remain outside this operator-readable surface.
              </p>
            </div>
            <div id="command-summary" class="grid grid-cols-2 gap-px border border-base-300 bg-base-300 sm:grid-cols-4" data-command-active-count={@command_summary.active_count}>
              <.summary_metric label="Queued" value={@command_summary.queued_count} tone={:info} />
              <.summary_metric label="Release pending" value={@command_summary.release_pending_count} tone={:warning} />
              <.summary_metric label="In flight" value={@command_summary.in_flight_count} tone={:info} />
              <.summary_metric label="Failed" value={@command_summary.failed_count + @command_summary.indeterminate_count} tone={:critical} />
            </div>
          </div>
        </header>

        <div class="mx-auto max-w-[100rem] space-y-4 p-5 lg:p-7">
          <div
            :if={@focus_command_id}
            id="followed-command-banner"
            data-followed-command={@focus_command_id}
            class="flex items-center gap-3 border-l-2 border-info bg-info/10 px-3 py-2"
          >
            <.icon name="hero-eye" class="h-4 w-4 text-info" />
            <p class="min-w-0 flex-1 truncate text-sm">
              Following <span class="font-mono font-semibold">{@focus_command_id}</span> across Ops pages
            </p>
            <button id="clear-command-focus" type="button" phx-click="clear_command_focus" class="btn btn-ghost btn-xs">
              Stop following
            </button>
          </div>

          <.form
            for={@filter_form}
            id="command-filter-form"
            phx-change="filter"
            class="grid gap-3 border border-base-300 bg-base-200/25 p-3 md:grid-cols-3"
          >
            <.input
              field={@filter_form[:status]}
              type="select"
              label="State"
              options={[{"All states", "all"}, {"Failed", "failed"}, {"Release pending", "release_pending"}, {"In flight", "in_flight"}, {"Queued", "queued"}, {"Released", "released"}, {"Approval pending", "approval_pending"}]}
            />
            <.input
              field={@filter_form[:target]}
              type="select"
              label="Target"
              options={[{"All targets", "all"} | Enum.map(@command_targets, &{&1, &1})]}
            />
            <.input
              field={@filter_form[:query]}
              type="search"
              label="Command or requester"
              placeholder="NOOP, request id, endpoint"
              phx-debounce="250"
            />
          </.form>

          <div class="flex items-center justify-between gap-3">
            <p class="font-mono text-[0.65rem] uppercase tracking-wider text-base-content/45">
              Projection observed {timestamp(@command_summary.observed_at)}
            </p>
            <button id="command-filter-reset" type="button" phx-click="reset_filters" class="btn btn-ghost btn-xs">
              Reset filters
            </button>
          </div>

          <section class="overflow-hidden border border-base-300 bg-base-100">
            <div id="command-rows" phx-update="stream">
              <div id="command-rows-empty" class="hidden only:flex min-h-48 flex-col items-center justify-center px-6 text-center">
                <.icon name="hero-command-line" class="h-8 w-8 text-base-content/30" />
                <p class="mt-3 font-semibold">No matching commands</p>
                <p class="mt-1 text-sm text-base-content/55">
                  Empty and unavailable projections are reported separately by the context rail.
                </p>
              </div>
              <article
                :for={{id, command} <- @streams.commands}
                id={id}
                data-command-request={command.command_request_id}
                data-command-state={command.status}
                class="grid gap-3 border-b border-base-300/60 px-4 py-3 last:border-b-0 xl:grid-cols-[9rem_minmax(0,1fr)_13rem_10rem_10rem_auto] xl:items-center"
              >
                <span class={status_class(command.status)}>{status_label(command.status)}</span>
                <div class="min-w-0">
                  <p class="truncate font-semibold">{command.command_name}</p>
                  <p class="truncate font-mono text-[0.68rem] text-base-content/50">
                    {command.command_request_id}
                  </p>
                </div>
                <div>
                  <p class="hud-label">Target</p>
                  <p class="mt-1 truncate font-mono text-[0.68rem]">{command.target}</p>
                </div>
                <div>
                  <p class="hud-label">Requested by</p>
                  <p class="mt-1 truncate text-xs">{command.requested_by}</p>
                </div>
                <div>
                  <p class="hud-label">Age</p>
                  <p class="mt-1 font-mono text-[0.68rem]">{age_label(command.requested_at)}</p>
                </div>
                <div class="flex justify-end">
                  <button
                    :if={@focus_command_id != command.command_request_id}
                    id={"follow-command-#{command.command_request_id}"}
                    type="button"
                    phx-click="follow_command"
                    phx-value-command-request-id={command.command_request_id}
                    class="btn btn-ghost btn-xs"
                  >
                    <.icon name="hero-eye" class="h-3.5 w-3.5" /> Follow
                  </button>
                  <span :if={@focus_command_id == command.command_request_id} class="badge badge-info badge-outline badge-sm">
                    Following
                  </span>
                </div>
                <details class="xl:col-span-6 border-t border-base-300/50 pt-2">
                  <summary class="cursor-pointer font-mono text-[0.65rem] uppercase tracking-wider text-base-content/50">
                    Queue, release, and verifier evidence
                  </summary>
                  <dl class="mt-2 grid gap-2 text-xs sm:grid-cols-2 lg:grid-cols-4">
                    <.detail label="Request state" value={command.request_state} />
                    <.detail label="Queue entry" value={record_id(command.queue_entry, :command_queue_entry_id)} />
                    <.detail label="Release attempt" value={record_id(command.release_attempt, :command_release_attempt_id)} />
                    <.detail label="Verification" value={command.verification_state || "not required"} />
                  </dl>
                </details>
              </article>
            </div>
          </section>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :tone, :atom, required: true

  defp summary_metric(assigns) do
    ~H"""
    <div class="min-w-24 bg-base-100/80 px-3 py-2">
      <p class="hud-label">{@label}</p>
      <p class={["mt-1 font-mono text-lg font-semibold", metric_class(@tone, @value)]}>{@value}</p>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp detail(assigns) do
    ~H"""
    <div><dt class="hud-label">{@label}</dt><dd class="mt-1 break-all font-mono text-[0.68rem]">{@value || "—"}</dd></div>
    """
  end

  defp commands_path(socket, filters) do
    query = filters |> Enum.reject(fn {_key, value} -> value in [nil, "", "all"] end) |> Map.new()
    ~p"/missions/#{socket.assigns.current_mission.mission_id}/ops/commands?#{query}"
  end

  defp current_filters(socket, focus_command_id) do
    socket.assigns.filter_form.params
    |> Map.take(~w(status target query))
    |> Map.put("focus_command_id", focus_command_id)
  end

  defp record_id(nil, _field), do: nil
  defp record_id(record, field), do: Map.get(record, field)

  defp status_label(status), do: status |> to_string() |> String.replace("_", " ")
  defp status_class(:failed), do: "badge badge-error badge-sm"
  defp status_class(:indeterminate), do: "badge badge-error badge-outline badge-sm"
  defp status_class(:release_pending), do: "badge badge-warning badge-sm"
  defp status_class(:in_flight), do: "badge badge-info badge-sm"
  defp status_class(:queued), do: "badge badge-info badge-outline badge-sm"
  defp status_class(:released), do: "badge badge-success badge-outline badge-sm"
  defp status_class(_state), do: "badge badge-ghost badge-sm"

  defp metric_class(_tone, 0), do: "text-base-content/35"
  defp metric_class(:critical, _value), do: "text-error"
  defp metric_class(:warning, _value), do: "text-warning"
  defp metric_class(:info, _value), do: "text-info"

  defp age_label(nil), do: "unknown"

  defp age_label(%DateTime{} = requested_at) do
    seconds = max(DateTime.diff(DateTime.utc_now(), requested_at, :second), 0)

    cond do
      seconds < 60 -> "#{seconds}s"
      seconds < 3_600 -> "#{div(seconds, 60)}m"
      seconds < 86_400 -> "#{div(seconds, 3_600)}h"
      true -> "#{div(seconds, 86_400)}d"
    end
  end

  defp timestamp(nil), do: "not observed"
  defp timestamp(%DateTime{} = value), do: Calendar.strftime(value, "%Y-%m-%d %H:%M:%S UTC")

  defp present_text(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp present_text(_value), do: nil

  defp empty_summary do
    %{
      observed_at: nil,
      active_count: 0,
      queued_count: 0,
      release_pending_count: 0,
      in_flight_count: 0,
      failed_count: 0,
      indeterminate_count: 0
    }
  end
end
