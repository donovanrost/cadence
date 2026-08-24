defmodule CadenceWeb.OpsCommandsLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.Reads.Commands
  alias CadenceWeb.OpsContextSnapshot
  alias Phoenix.LiveView.JS

  @filter_keys ~w(status target query focus_command_id)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> stream_configure(:commands, dom_id: &"command-row-#{&1.id}")
     |> assign(:page_title, "Commands")
     |> assign(:ops_nav_item, :commands)
     |> assign(:command_summary, empty_summary())
     |> assign(:command_targets, [])
     |> assign(:commands_empty?, true)
     |> assign(:focus_command_id, nil)
     |> assign(:filter_form, to_form(%{}, as: :filters))
     |> assign(:commands_page, page_dto())
     |> assign(:command_summary_dto, summary_dto(empty_summary()))
     |> assign(:command_filters_dto, filters_dto(%{}, []))
     |> assign(:command_reset, reset_dto())
     |> assign(:command_focus_banner, nil)
     |> assign(:command_empty, empty_dto())
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
     |> assign(:command_summary_dto, summary_dto(snapshot.summary))
     |> assign(:command_filters_dto, filters_dto(filters, snapshot.targets))
     |> assign(:command_focus_banner, focus_banner_dto(focus_command_id))
     |> stream(
       :commands,
       Enum.map(snapshot.rows, &command_dto(&1, focus_command_id)),
       reset: true
     )}
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
      <.vue
        id="ops-commands-component"
        v-component="OpsCommands"
        page={@commands_page}
        summary={@command_summary_dto}
        filters={@command_filters_dto}
        reset={@command_reset}
        focus_banner={@command_focus_banner}
        empty={@command_empty}
        commands={@streams.commands}
        v-on:filter={JS.push("filter")}
        v-on:reset_filters={JS.push("reset_filters")}
        v-on:follow_command={JS.push("follow_command")}
        v-on:clear_command_focus={JS.push("clear_command_focus")}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end

  defp page_dto do
    %{
      id: "ops-commands-page",
      header: %{
        eyebrow: "Mission operations / command posture",
        heading: "Commands",
        copy:
          "Read-only request, queue, release, transport, and verification state. Command creation, approval, and release remain outside this operator-readable surface."
      },
      rows_id: "command-rows"
    }
  end

  defp summary_dto(summary) do
    %{
      id: "command-summary",
      active_count: summary.active_count,
      observed: "Projection observed #{timestamp(summary.observed_at)}",
      metrics: [
        summary_metric_dto("Queued", summary.queued_count, :info),
        summary_metric_dto("Release pending", summary.release_pending_count, :warning),
        summary_metric_dto("In flight", summary.in_flight_count, :info),
        summary_metric_dto(
          "Failed",
          summary.failed_count + summary.indeterminate_count,
          :critical
        )
      ]
    }
  end

  defp summary_metric_dto(label, value, tone) do
    %{
      label: label,
      value: value,
      value_class: metric_class(tone, value)
    }
  end

  defp filters_dto(filters, targets) do
    %{
      id: "command-filter-form",
      values: %{
        status: Map.get(filters, "status", "all"),
        target: Map.get(filters, "target", "all"),
        query: Map.get(filters, "query", "")
      },
      fields: %{
        status:
          select_field_dto(
            "filters_status",
            "filters[status]",
            "State",
            [
              {"All states", "all"},
              {"Failed", "failed"},
              {"Release pending", "release_pending"},
              {"In flight", "in_flight"},
              {"Queued", "queued"},
              {"Released", "released"},
              {"Approval pending", "approval_pending"}
            ]
          ),
        target:
          select_field_dto(
            "filters_target",
            "filters[target]",
            "Target",
            [{"All targets", "all"} | Enum.map(targets, &{&1, &1})]
          ),
        query: %{
          id: "filters_query",
          name: "filters[query]",
          type: "search",
          label: "Command or requester",
          placeholder: "NOOP, request id, endpoint",
          debounce_ms: 250
        }
      }
    }
  end

  defp select_field_dto(id, name, label, options) do
    %{
      id: id,
      name: name,
      type: "select",
      label: label,
      options:
        Enum.map(options, fn {option_label, value} ->
          %{label: option_label, value: value}
        end)
    }
  end

  defp reset_dto do
    %{id: "command-filter-reset", label: "Reset filters", payload: %{}}
  end

  defp focus_banner_dto(nil), do: nil

  defp focus_banner_dto(command_request_id) do
    %{
      id: "followed-command-banner",
      command_request_id: command_request_id,
      icon: "hero-eye",
      prefix: "Following",
      suffix: "across Ops pages",
      clear: %{
        id: "clear-command-focus",
        label: "Stop following",
        payload: %{}
      }
    }
  end

  defp empty_dto do
    %{
      id: "command-rows-empty",
      icon: "hero-command-line",
      heading: "No matching commands",
      copy: "Empty and unavailable projections are reported separately by the context rail."
    }
  end

  defp command_dto(command, focus_command_id) do
    command_request_id = command.command_request_id
    verification_state = optional_state(command.verification_state)

    %{
      id: command_request_id,
      command_request_id: command_request_id,
      command_name: command.command_name,
      status: %{
        value: Atom.to_string(command.status),
        label: status_label(command.status),
        class: status_class(command.status)
      },
      target: %{label: "Target", display: command.target},
      requester: %{label: "Requested by", display: command.requested_by},
      age: %{label: "Age", display: age_label(command.requested_at)},
      focus: %{
        following: focus_command_id == command_request_id,
        label: "Following",
        class: "badge badge-info badge-outline badge-sm",
        action: %{
          id: "follow-command-#{command_request_id}",
          label: "Follow",
          icon: "hero-eye",
          payload: %{"command-request-id" => command_request_id}
        }
      },
      evidence: %{
        summary: "Queue, release, and verifier evidence",
        request_state: detail_dto("Request state", Atom.to_string(command.request_state)),
        queue_entry:
          record_detail_dto(
            "Queue entry",
            record_id(command.queue_entry, :command_queue_entry_id)
          ),
        release_attempt:
          record_detail_dto(
            "Release attempt",
            record_id(command.release_attempt, :command_release_attempt_id)
          ),
        verification: %{
          label: "Verification",
          state: verification_state,
          display: verification_state || "not required"
        }
      }
    }
  end

  defp detail_dto(label, display), do: %{label: label, display: display}

  defp record_detail_dto(label, record_id) do
    %{label: label, record_id: record_id, display: record_id || "—"}
  end

  defp optional_state(nil), do: nil
  defp optional_state(state), do: Atom.to_string(state)

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
