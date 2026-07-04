defmodule CadenceWeb.OpsDashboardShowLive.VersionHistoryPresentation do
  @moduledoc false

  alias Cadence.Dashboards
  alias Cadence.Dashboards.{DashboardSummary, Document, Version}
  alias CadenceWeb.OpsDashboardShowLive.DocumentLifecycle
  alias CadenceWeb.OpsDashboardShowLive.RuntimeQuery

  def build(summary, versions) when is_list(versions) do
    ordered_versions = Enum.sort_by(versions, & &1.version, :desc)

    %{
      pointers: pointer_metrics(summary),
      runtime_defaults: runtime_defaults(summary, versions),
      count: length(versions),
      empty: versions == [],
      versions: Enum.map(ordered_versions, &version_row(&1, summary))
    }
  end

  def build(summary, _versions), do: build(summary, [])

  defp pointer_metrics(summary) do
    [
      %{label: "latest", value: pointer_value(summary, :latest_version)},
      %{label: "draft", value: pointer_value(summary, :draft_version)},
      %{label: "published", value: pointer_value(summary, :published_version)}
    ]
  end

  defp pointer_value(nil, _field), do: "-"

  defp pointer_value(%DashboardSummary{} = summary, field) do
    case Map.get(summary, field) do
      nil -> "-"
      version -> "v#{version}"
    end
  end

  defp pointer_value(_summary, _field), do: "-"

  defp runtime_defaults(%DashboardSummary{} = summary, versions) when is_list(versions) do
    published = version_context(versions, summary.published_version)
    draft = version_context(versions, summary.draft_version)
    differ? = DocumentLifecycle.draft_runtime_defaults_differ?(summary, versions)

    %{
      present?: published.present? or draft.present?,
      differ?: differ?,
      differ_text: boolean_text(differ?),
      status_label: runtime_defaults_status_label(differ?),
      publish_impact: publish_impact(published, draft, differ?),
      published: published,
      draft: draft
    }
  end

  defp runtime_defaults(_summary, _versions) do
    %{
      present?: false,
      differ?: false,
      differ_text: "false",
      status_label: "not available",
      publish_impact: publish_impact(empty_version_context(), empty_version_context(), false),
      published: empty_version_context(),
      draft: empty_version_context()
    }
  end

  defp version_context(versions, version) when is_integer(version) and version > 0 do
    case Enum.find(versions, &(&1.version == version)) do
      %Version{document: %Document{} = document} ->
        document
        |> RuntimeQuery.document_data_defaults()
        |> data_context(version)

      _missing ->
        empty_version_context(version)
    end
  end

  defp version_context(_versions, _version), do: empty_version_context()

  defp data_context(defaults, version) when is_map(defaults) do
    telemetry_context =
      defaults
      |> Map.get("source_contexts", %{})
      |> Map.get("telemetry", %{})

    source_binding_id = text_value(Map.get(telemetry_context, "source_binding_id"))
    data_source_id = text_value(Map.get(telemetry_context, "data_source_id"))

    %{
      present?: true,
      version: version,
      version_text: version_text(version),
      realm: text_value(Map.get(defaults, "realm")) || "-",
      source_binding_id: source_binding_id,
      source_binding_text: source_binding_id || "primary",
      source_binding_attr: source_binding_id || "primary",
      data_source_id: data_source_id,
      data_source_text: data_source_id || "-",
      data_source_attr: data_source_id || "",
      data_view:
        text_value(Map.get(defaults, "view") || Map.get(defaults, "data_view")) || "canonical"
    }
  end

  defp empty_version_context(version \\ nil) do
    %{
      present?: false,
      version: version,
      version_text: version_text(version),
      realm: "-",
      source_binding_id: nil,
      source_binding_text: "-",
      source_binding_attr: "",
      data_source_id: nil,
      data_source_text: "-",
      data_source_attr: "",
      data_view: "-"
    }
  end

  defp runtime_defaults_status_label(true), do: "draft differs"
  defp runtime_defaults_status_label(false), do: "aligned"

  defp publish_impact(%{present?: true} = published, %{present?: true} = draft, true) do
    %{
      present?: true,
      state: "runtime_context_change",
      severity: "warning",
      label: "runtime defaults change",
      message:
        "Publishing will move operators from #{context_label(published)} to #{context_label(draft)}.",
      from: published,
      to: draft
    }
  end

  defp publish_impact(%{present?: true} = published, %{present?: true} = draft, false) do
    %{
      present?: true,
      state: "no_runtime_context_change",
      severity: "success",
      label: "runtime defaults unchanged",
      message: "Publishing keeps operators on #{context_label(published)}.",
      from: published,
      to: draft
    }
  end

  defp publish_impact(_published, %{present?: true} = draft, _differ?) do
    %{
      present?: true,
      state: "initial_publish",
      severity: "info",
      label: "initial publish",
      message: "Publishing will make #{context_label(draft)} operator-facing.",
      from: empty_version_context(),
      to: draft
    }
  end

  defp publish_impact(published, draft, _differ?) do
    %{
      present?: false,
      state: "not_available",
      severity: "neutral",
      label: "not available",
      message: nil,
      from: published,
      to: draft
    }
  end

  defp context_label(context) do
    [
      context.realm,
      context.source_binding_text,
      context.data_view
    ]
    |> Enum.reject(&(&1 in [nil, "", "-"]))
    |> Enum.join(" / ")
  end

  defp version_row(%Version{} = version, summary) do
    %{
      version: version.version,
      dom_id: "dashboard-version-#{version.version}",
      publish_button_id: "publish-version-#{version.version}",
      restore_button_id: "restore-version-#{version.version}",
      publish_confirm: "Publish version #{version.version} for operators?",
      restore_confirm: "Restore version #{version.version} as the latest draft?",
      snapshot_label: snapshot_label(version.snapshot_kind),
      pointer_labels: pointer_labels(version, summary),
      lineage: lineage(version),
      saved_at: format_time(version.inserted_at),
      created_by: version.created_by || "unknown",
      parent_version: version.parent_version || "-",
      based_on_version: version.based_on_version || "-",
      change_summary: version.change_summary,
      publish_action: version_action(version, summary, :publish),
      restore_action: version_action(version, summary, :restore)
    }
  end

  defp pointer_labels(%Version{} = version, %DashboardSummary{} = summary) do
    [
      pointer_label(version.version == summary.latest_version, "latest"),
      pointer_label(version.version == summary.draft_version, "draft"),
      pointer_label(version.version == summary.published_version, "published")
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp pointer_labels(%Version{}, _summary), do: []

  defp pointer_label(false, _label), do: nil

  defp pointer_label(true, label) do
    %{label: label, badge_class: pointer_badge_class(label)}
  end

  defp pointer_badge_class("published"), do: "badge-primary"
  defp pointer_badge_class("draft"), do: "badge-warning"
  defp pointer_badge_class(_label), do: "badge-ghost"

  defp snapshot_label(:draft_save), do: "draft save"
  defp snapshot_label(:publish), do: "publish"
  defp snapshot_label(:revert), do: "revert"
  defp snapshot_label(:migration), do: "migration"
  defp snapshot_label(kind), do: to_string(kind)

  defp lineage(%Version{snapshot_kind: :publish}) do
    %{
      kind: "publish",
      label: "Published for operators",
      source_version: nil,
      source_version_text: nil
    }
  end

  defp lineage(%Version{snapshot_kind: :revert, based_on_version: version})
       when is_integer(version) and version > 0 do
    %{
      kind: "revert",
      label: "Restored from v#{version}",
      source_version: version,
      source_version_text: Integer.to_string(version)
    }
  end

  defp lineage(%Version{snapshot_kind: :migration, based_on_version: version})
       when is_integer(version) and version > 0 do
    %{
      kind: "migration",
      label: "Migrated from v#{version}",
      source_version: version,
      source_version_text: Integer.to_string(version)
    }
  end

  defp lineage(%Version{snapshot_kind: :draft_save, based_on_version: version})
       when is_integer(version) and version > 0 do
    %{
      kind: "draft_save",
      label: "Draft saved from v#{version}",
      source_version: version,
      source_version_text: Integer.to_string(version)
    }
  end

  defp lineage(%Version{snapshot_kind: kind}) do
    %{
      kind: snapshot_kind_value(kind),
      label: "Version snapshot",
      source_version: nil,
      source_version_text: nil
    }
  end

  defp snapshot_kind_value(kind) when is_atom(kind), do: Atom.to_string(kind)
  defp snapshot_kind_value(kind), do: to_string(kind)

  defp version_action(%Version{} = version, summary, action) do
    action_state = Dashboards.dashboard_version_action(summary, version)
    available = Map.get(action_state, action_available_field(action), false)

    %{
      available: available,
      available_text: if(available, do: "true", else: "false"),
      reason_text:
        action_state
        |> Map.get(action_reason_field(action), :unknown)
        |> Atom.to_string()
    }
  end

  defp action_available_field(:publish), do: :publish_available?
  defp action_available_field(:restore), do: :restore_available?

  defp action_reason_field(:publish), do: :publish_reason
  defp action_reason_field(:restore), do: :restore_reason

  defp format_time(nil), do: "-"

  defp format_time(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
  end

  defp version_text(nil), do: "-"
  defp version_text(version) when is_integer(version), do: "v#{version}"

  defp boolean_text(true), do: "true"
  defp boolean_text(false), do: "false"

  defp text_value(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp text_value(value) when is_atom(value), do: Atom.to_string(value)
  defp text_value(value) when is_integer(value), do: Integer.to_string(value)
  defp text_value(_value), do: nil
end
