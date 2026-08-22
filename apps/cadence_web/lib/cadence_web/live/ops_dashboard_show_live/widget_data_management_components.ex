defmodule CadenceWeb.OpsDashboardShowLive.WidgetDataManagementComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.DataLinkAttrs

  attr :badge, :map, required: true
  attr :class, :string, default: nil

  def data_management_badge(assigns) do
    assigns =
      assigns
      |> assign(:actionable?, data_management_badge_actionable?(assigns.badge))
      |> assign(:data_link_target, data_management_badge_data_link_target(assigns.badge))
      |> assign(:data_link_id, data_management_badge_data_link_id(assigns.badge))
      |> assign(:data_link_key, data_management_badge_data_link_key(assigns.badge))
      |> assign(:summary, data_management_badge_summary(assigns.badge))
      |> assign(:title, data_management_badge_title(assigns.badge))

    ~H"""
    <button
      :if={@actionable?}
      type="button"
      phx-click="open_data_link"
      {DataLinkAttrs.open(@badge,
        link_id: @data_link_key,
        target: @data_link_target,
        target_id: @data_link_id
      )}
      class={["badge badge-xs cursor-pointer", data_management_badge_class(@badge), @class]}
      data-data-management-badge={@badge.value}
      data-data-management-kind={@badge.kind}
      data-data-management-code={@badge.code || ""}
      data-data-link-id={@data_link_key}
      data-data-link-target={@data_link_target}
      data-data-link-target-id={@data_link_id}
      data-data-link-realm={data_management_badge_context_attr(@badge, :realm) || ""}
      data-data-link-data-view={data_management_badge_context_attr(@badge, :data_view) || ""}
      data-data-link-data-source-id={
        data_management_badge_context_attr(@badge, :data_source_id) || ""
      }
      data-data-link-source-binding-id={
        data_management_badge_context_attr(@badge, :source_binding_id) || ""
      }
      data-data-link-time-mode={data_management_badge_context_attr(@badge, :time_mode) || ""}
      data-data-link-time-axis={data_management_badge_context_attr(@badge, :time_axis) || ""}
      data-data-link-replay-run-id={
        data_management_badge_context_attr(@badge, :replay_run_id) || ""
      }
      data-data-management-workflow-run-id={
        data_management_badge_context_attr(@badge, :workflow_run_id) || ""
      }
      data-data-management-workflow-job-id={
        data_management_badge_context_attr(@badge, :workflow_job_id) || ""
      }
      data-data-management-workflow-job-status={
        data_management_badge_context_attr(@badge, :workflow_job_status) || ""
      }
      data-data-management-workflow-job-failure={
        data_management_badge_context_attr(@badge, :workflow_job_failure) || ""
      }
      data-data-management-summary={@summary || ""}
      title={@title}
    >
      {@badge.label}
    </button>
    <span
      :if={not @actionable?}
      class={["badge badge-xs", data_management_badge_class(@badge), @class]}
      data-data-management-badge={@badge.value}
      data-data-management-kind={@badge.kind}
      data-data-management-code={@badge.code || ""}
      data-data-management-workflow-run-id={
        data_management_badge_context_attr(@badge, :workflow_run_id) || ""
      }
      data-data-management-workflow-job-id={
        data_management_badge_context_attr(@badge, :workflow_job_id) || ""
      }
      data-data-management-workflow-job-status={
        data_management_badge_context_attr(@badge, :workflow_job_status) || ""
      }
      data-data-management-workflow-job-failure={
        data_management_badge_context_attr(@badge, :workflow_job_failure) || ""
      }
      data-data-management-summary={@summary || ""}
      title={@title}
    >
      {@badge.label}
    </span>
    """
  end

  attr :data, :any, default: nil
  attr :backfill, :any, default: nil
  attr :compare_data, :any, default: nil
  attr :compare_backfill, :any, default: nil
  attr :data_view, :string, default: nil
  attr :compare_data_view, :string, default: nil

  def chart_data_management_strip(assigns) do
    assigns =
      assigns
      |> assign(:primary_badges, widget_data_management_badges([assigns.data, assigns.backfill]))
      |> assign(
        :compare_badges,
        widget_data_management_badges([assigns.compare_data, assigns.compare_backfill])
      )

    ~H"""
    <div
      :if={@primary_badges != [] or @compare_badges != [] or present_text?(@compare_data_view)}
      class="flex flex-wrap gap-1"
      data-chart-data-management-strip
      data-chart-data-view={@data_view || ""}
      data-chart-compare-data-view={@compare_data_view || ""}
    >
      <span
        :if={present_text?(@compare_data_view)}
        class="badge badge-xs badge-ghost border-base-300/80 font-mono"
        data-chart-data-view-comparison
        data-primary-data-view={@data_view || ""}
        data-compare-data-view={@compare_data_view || ""}
        title={"Primary #{data_view_label(@data_view)} compared with #{data_view_label(@compare_data_view)}"}
      >
        {data_view_label(@data_view)} vs {data_view_label(@compare_data_view)}
      </span>
      <.data_management_badge
        :for={badge <- @primary_badges}
        badge={badge}
        class="data-management-primary"
      />
      <.data_management_badge
        :for={badge <- @compare_badges}
        badge={badge}
        class="data-management-compare"
      />
    </div>
    """
  end

  def data_management_badges(%{data_management: %{badges: badges}}) when is_list(badges),
    do: badges

  def data_management_badges(_data), do: []

  def widget_data_management_badge_codes(sources) do
    sources
    |> widget_data_management_badges()
    |> Enum.map_join(",", & &1.value)
  end

  def data_management_badge_codes(data) do
    data
    |> data_management_badges()
    |> Enum.map_join(",", & &1.value)
  end

  def data_management_warning_codes(%{data_management: %{warning_codes: warning_codes}})
      when is_list(warning_codes) do
    warning_codes
    |> Enum.map(&data_management_value_text/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.join(",")
  end

  def data_management_warning_codes(_data), do: ""

  defp widget_data_management_badges(sources) when is_list(sources) do
    sources
    |> Enum.flat_map(&data_management_badges/1)
    |> Enum.uniq_by(&{&1.kind, &1.value, &1.code})
  end

  defp data_management_badge_actionable?(badge) do
    data_management_badge_data_link_target(badge) not in [nil, ""] and
      data_management_badge_data_link_id(badge) not in [nil, ""]
  end

  defp data_management_badge_data_link_target(%{data_link_target: target}),
    do: data_link_target_text(target)

  defp data_management_badge_data_link_target(%{"data_link_target" => target}),
    do: data_link_target_text(target)

  defp data_management_badge_data_link_target(_badge), do: nil

  defp data_link_target_text(target) when is_atom(target), do: Atom.to_string(target)
  defp data_link_target_text(target) when is_binary(target), do: target
  defp data_link_target_text(_target), do: nil

  defp data_management_badge_data_link_id(%{data_link_id: id}), do: data_link_target_id_text(id)

  defp data_management_badge_data_link_id(%{"data_link_id" => id}),
    do: data_link_target_id_text(id)

  defp data_management_badge_data_link_id(_badge), do: nil

  defp data_management_badge_data_link_key(badge) do
    case {data_management_badge_data_link_target(badge),
          data_management_badge_data_link_id(badge)} do
      {target, id} when target not in [nil, ""] and id not in [nil, ""] ->
        "direct:#{target}:#{id}"

      _missing ->
        nil
    end
  end

  defp data_link_target_id_text(id) when is_binary(id), do: id
  defp data_link_target_id_text(id) when is_atom(id), do: Atom.to_string(id)
  defp data_link_target_id_text(id) when is_integer(id), do: Integer.to_string(id)
  defp data_link_target_id_text(_id), do: nil

  defp data_management_badge_context_attr(badge, key) when is_map(badge) do
    badge
    |> Map.get(key, Map.get(badge, Atom.to_string(key)))
    |> data_management_value_text()
  end

  defp data_management_badge_context_attr(_badge, _key), do: nil

  defp data_management_badge_summary(%{summary: summary}), do: data_management_value_text(summary)

  defp data_management_badge_summary(%{"summary" => summary}),
    do: data_management_value_text(summary)

  defp data_management_badge_summary(_badge), do: nil

  defp data_management_badge_title(badge) do
    label = data_management_value_text(Map.get(badge, :label, Map.get(badge, "label")))

    case {label, data_management_badge_summary(badge)} do
      {nil, nil} -> nil
      {nil, summary} -> summary
      {label, nil} -> label
      {label, ""} -> label
      {label, summary} -> "#{label} - #{summary}"
    end
  end

  defp data_management_value_text(nil), do: nil
  defp data_management_value_text(value) when is_binary(value), do: value
  defp data_management_value_text(value) when is_atom(value), do: Atom.to_string(value)
  defp data_management_value_text(value), do: to_string(value)

  defp data_management_badge_class(%{status: :warning}), do: "badge-warning"
  defp data_management_badge_class(%{status: :attention}), do: "badge-warning badge-outline"
  defp data_management_badge_class(%{status: :info}), do: "badge-info badge-outline"
  defp data_management_badge_class(_badge), do: "badge-ghost"

  defp data_view_options do
    [
      {"Canonical", "canonical"},
      {"As recorded", "as_recorded"},
      {"All revisions", "all_revisions"},
      {"Recomputed", "recomputed"}
    ]
  end

  defp data_view_label(value) do
    value = present_text(value)

    data_view_options()
    |> Enum.find_value(value || "Canonical", fn {label, option_value} ->
      if option_value == value, do: label
    end)
  end

  defp present_text?(value), do: not is_nil(present_text(value))

  defp present_text(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp present_text(_value), do: nil
end
