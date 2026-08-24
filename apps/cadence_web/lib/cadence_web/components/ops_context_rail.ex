defmodule CadenceWeb.Components.OpsContextRail do
  @moduledoc """
  Phoenix-owned presentation boundary for the right-side operational context
  rail. The server preserves module ordering, status/count derivation,
  freshness labels, and navigation destinations; LiveVue owns only rendering
  and client-side rail interaction.
  """

  use Phoenix.Component
  use LiveVue
  use LiveVue.Components, vue_root: ["./assets/vue", "./lib/cadence_web"]

  import Phoenix.Component, except: [sigil_H: 2]
  import LiveVue.SharedPropsView, only: [sigil_H: 2]

  attr :id, :string, default: "ops-context-rail"
  attr :sections, :list, required: true

  def ops_context_rail(assigns) do
    assigns =
      assigns
      |> assign(:rail, rail_dto(assigns.id))
      |> assign(
        :section_dtos,
        assigns.sections
        |> Enum.filter(&section_visible?/1)
        |> Enum.map(&section_dto/1)
      )

    ~H"""
    <.vue
      id={"#{@id}-component"}
      v-component="OpsContextRail"
      rail={@rail}
      sections={@section_dtos}
      v-ssr={false}
      class="contents"
    />
    """
  end

  @doc """
  The shell-owned rail for every Ops page. Its ordered modules come from the
  mission-scoped `ops_context` snapshot assembled by `OpsShellHook`.
  """
  attr :ops_context, :map, required: true

  def mission_context_rail(assigns) do
    assigns =
      assign(
        assigns,
        :sections,
        assigns.ops_context
        |> Map.get(:modules, [])
        |> Enum.map(&context_module_section/1)
      )

    ~H"""
    <.ops_context_rail sections={@sections} />
    """
  end

  defp rail_dto(id) do
    %{
      "id" => id,
      "aria_label" => "Operational context",
      "storage_key" => "cadence-ops-context-rail",
      "role" => "context",
      "default_expanded" => false,
      "resize_title" => "Drag to resize",
      "toggle_label" => "Toggle context panel"
    }
  end

  defp context_module_section(context_module) do
    %{
      key: context_module.key,
      title: context_module.title,
      icon: context_module.icon,
      status: context_module.status,
      count: context_module.count,
      freshness: context_module.freshness,
      freshness_label: freshness_label(context_module.freshness),
      observed_at_label: observed_at_label(context_module.observed_at),
      destination: context_module.destination,
      content: context_content(context_module.key, context_module.data)
    }
  end

  defp section_dto(section) do
    status = section_value(section, :status)

    %{
      "key" => section_value(section, :key) || section_value(section, :title),
      "title" => section_value(section, :title),
      "icon" => section_value(section, :icon),
      "status" => enum_value(status),
      "status_dot_class" => status_dot_class(status),
      "count" => section_count(section),
      "freshness" => enum_value(section_value(section, :freshness)),
      "freshness_label" => section_value(section, :freshness_label),
      "observed_at_label" => section_value(section, :observed_at_label),
      "destination" => section_value(section, :destination),
      "content" => section_value(section, :content) || %{"kind" => "empty"}
    }
  end

  defp context_content("alarms", summary) do
    active_count = count_value(summary, :active_count)

    %{
      "kind" => "alarms",
      "active" => active_count > 0,
      "badges" => [
        severity_badge_dto(:critical, count_value(summary, :critical_count), "Critical"),
        severity_badge_dto(:warning, count_value(summary, :warning_count), "Warning"),
        severity_badge_dto(:info, count_value(summary, :info_count), "Info")
      ],
      "empty_label" => "No active limit conditions",
      "latest_transition_label" => latest_transition_label(summary)
    }
  end

  defp context_content("commands", summary) do
    %{
      "kind" => "commands",
      "counts" => [
        context_count_dto("Queued", count_value(summary, :queued_count), :info),
        context_count_dto(
          "Release pending",
          count_value(summary, :release_pending_count),
          :warning
        ),
        context_count_dto("In flight", count_value(summary, :in_flight_count), :info),
        context_count_dto(
          "Failed",
          count_value(summary, :failed_count) + count_value(summary, :indeterminate_count),
          :critical
        )
      ],
      "followed_command" => followed_command_dto(Map.get(summary, :followed_command))
    }
  end

  defp context_content("fleet_health", nil) do
    %{
      "kind" => "fleet_health",
      "available" => false,
      "badges" => [],
      "violating_points_label" => nil,
      "unavailable_label" => "Fleet health unavailable."
    }
  end

  defp context_content("fleet_health", fleet_health) do
    state_counts = Map.fetch!(fleet_health, :normalized_state_counts)

    %{
      "kind" => "fleet_health",
      "available" => true,
      "badges" => [
        severity_badge_dto(:critical, Map.fetch!(state_counts, :red), "Red"),
        severity_badge_dto(:warning, Map.fetch!(state_counts, :yellow), "Yellow"),
        severity_badge_dto(:info, Map.fetch!(state_counts, :blue), "Blue"),
        severity_badge_dto(:nominal, Map.fetch!(state_counts, :green), "Green")
      ],
      "violating_points_label" => "#{fleet_health.violating_points} violating points",
      "unavailable_label" => nil
    }
  end

  defp context_content(_key, _data), do: %{"kind" => "empty"}

  defp severity_badge_dto(severity, count, label) do
    %{
      "class" => severity_badge_class(severity),
      "count" => count,
      "label" => label
    }
  end

  defp context_count_dto(label, count, tone) do
    %{
      "label" => label,
      "value" => count,
      "class" => context_count_class(tone, count)
    }
  end

  defp followed_command_dto(nil), do: nil

  defp followed_command_dto(followed_command) do
    %{
      "command_request_id" => followed_command.command_request_id,
      "command_name" => followed_command.command_name,
      "detail" => "#{followed_command.status} · #{followed_command.target}"
    }
  end

  defp latest_transition_label(summary) do
    case Map.get(summary, :latest_transition_at) do
      nil -> nil
      latest_transition_at -> "Latest transition #{observed_at_label(latest_transition_at)}"
    end
  end

  defp section_visible?(section), do: section_value(section, :visible, true) != false

  defp section_count(section) do
    case section_value(section, :count) do
      count when is_integer(count) -> count
      _count -> nil
    end
  end

  defp section_value(section, key, default \\ nil) do
    case Map.fetch(section, key) do
      {:ok, value} -> value
      :error -> Map.get(section, Atom.to_string(key), default)
    end
  end

  defp count_value(summary, key) do
    case Map.get(summary, key, 0) do
      count when is_integer(count) -> count
      _count -> 0
    end
  end

  defp enum_value(nil), do: nil
  defp enum_value(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_value(value) when is_binary(value), do: value
  defp enum_value(_value), do: nil

  defp freshness_label(:current), do: "Live"
  defp freshness_label(:stale), do: "Stale"
  defp freshness_label(:unavailable), do: "Unavailable"
  defp freshness_label(_freshness), do: "Unknown"

  defp observed_at_label(%DateTime{} = observed_at),
    do: Calendar.strftime(observed_at, "%H:%M:%S UTC")

  defp observed_at_label(_observed_at), do: "not observed"

  defp status_dot_class(:critical), do: "bg-error"
  defp status_dot_class("critical"), do: "bg-error"
  defp status_dot_class(:warning), do: "bg-warning"
  defp status_dot_class("warning"), do: "bg-warning"
  defp status_dot_class(:info), do: "bg-info"
  defp status_dot_class("info"), do: "bg-info"
  defp status_dot_class(:nominal), do: "bg-success"
  defp status_dot_class("nominal"), do: "bg-success"
  defp status_dot_class(_status), do: "bg-base-content/30"

  defp severity_badge_class(:critical), do: "bg-error/20 text-error"
  defp severity_badge_class(:warning), do: "bg-warning/20 text-warning"
  defp severity_badge_class(:info), do: "bg-info/20 text-info"
  defp severity_badge_class(:nominal), do: "bg-success/20 text-success"

  defp context_count_class(_tone, 0), do: "text-base-content/35"
  defp context_count_class(:critical, _count), do: "text-error"
  defp context_count_class(:warning, _count), do: "text-warning"
  defp context_count_class(:info, _count), do: "text-info"
end
