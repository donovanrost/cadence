defmodule CadenceWeb.OpsDashboardShowLive.EvidenceInspectorPanelComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.ActivityNavigation
  alias CadenceWeb.OpsDashboardShowLive.DashboardActionPresentation
  alias CadenceWeb.OpsDashboardShowLive.DataLinkAttrs
  alias CadenceWeb.OpsDashboardShowLive.DataLinkPresentation
  alias CadenceWeb.OpsDashboardShowLive.HealthEvidenceActivity

  alias Cadence.Dashboards.DashboardAction

  @evidence_data_link_targets %{
    raw_evidence: :raw_evidence,
    telemetry_sample: :telemetry_sample,
    limit_event: :limit_event,
    limit_definition: :limit_definition,
    limit_definition_interval: :limit_definition_interval,
    limit_definition_lifecycle_event: :limit_definition_lifecycle_event,
    mission_event: :mission_event,
    operational_event: :operational_event,
    command_queue_entry: :command_queue_entry,
    command_release_attempt: :command_release_attempt,
    command_verifier_instance: :command_verifier_instance,
    transport_action_request: :transport_action_request,
    transport_capability_record: :transport_capability_record,
    binding_set_interval: :binding_set_interval,
    application_binding_interval: :application_binding_interval,
    catalog_revision_interval: :catalog_revision_interval,
    source_binding_interval: :source_binding_interval,
    source_health_interval: :source_health_interval,
    transport_execution_interval: :transport_execution_interval,
    transport_connection_state_interval: :transport_connection_state_interval,
    ground_station_connection_state_interval: :ground_station_connection_state_interval,
    ground_station_antenna_pointing_state_interval:
      :ground_station_antenna_pointing_state_interval,
    link_rf_lock_state_interval: :link_rf_lock_state_interval,
    link_frame_sync_state_interval: :link_frame_sync_state_interval,
    source_health_event: :source_health_event,
    source_watermark_event: :source_watermark_event,
    source_binding_event: :source_binding_event,
    telemetry_revision_decision_event: :telemetry_revision_decision_event,
    telemetry_backfill_lifecycle_event: :telemetry_backfill_lifecycle_event,
    contact: :contact,
    scheduled_contact: :contact,
    realized_contact: :contact
  }

  attr :inspector, :map, required: true
  attr :mission_id, :string, required: true
  attr :dashboard_document, :any, required: true
  attr :dashboard_current_path, :string, required: true
  attr :dashboard_lifecycle_events, :list, required: true

  def evidence_panel(assigns) do
    assigns = assign(assigns, :presentation, presentation(assigns))

    ~H"""
    <.vue
      id={@presentation.component_id}
      v-component="EvidenceInspectorPanel"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  def presentation(assigns) do
    inspector = assigns.inspector
    health_activity = HealthEvidenceActivity.build(inspector, assigns.dashboard_lifecycle_events)

    presented_links =
      DataLinkPresentation.evidence(Map.get(inspector, :links, []), inspector)

    %{
      component_id: "dashboard-evidence-inspector-component",
      root: %{
        attrs:
          raw_attributes(%{
            "id" => "dashboard-evidence-inspector",
            "data-evidence-kind" => text_value(Map.get(inspector, :kind)),
            "data-evidence-subject" => text_value(Map.get(inspector, :subject) || ""),
            "data-evidence-status" => text_value(Map.get(inspector, :status_text) || ""),
            "class" => "space-y-4"
          })
      },
      header: header_presentation(inspector),
      actions: %{
        attrs: %{"class" => "grid gap-2"},
        copy: copy_presentation(assigns.dashboard_current_path),
        dashboard:
          assigns.mission_id
          |> evidence_actions(inspector, assigns.dashboard_document)
          |> dashboard_action_presentations(),
        health:
          health_activity_presentation(
            health_activity,
            assigns.dashboard_current_path
          )
      },
      subject: rows_presentation("Subject", Map.get(inspector, :subject_rows, [])),
      details: rows_presentation("Details", Map.get(inspector, :detail_rows, [])),
      evidence:
        evidence_presentation(
          Map.get(inspector, :evidence, []),
          inspector,
          assigns.dashboard_current_path
        ),
      data_links: data_links_presentation(presented_links)
    }
  end

  defp header_presentation(inspector) do
    %{
      attrs: %{"class" => "space-y-1"},
      badges: %{
        attrs: %{"class" => "flex items-center gap-2"},
        items: [
          %{
            key: "kind",
            attrs: %{"class" => "badge badge-xs badge-outline"},
            text: rendered_body(Map.get(inspector, :kind_text))
          },
          %{
            key: "status",
            attrs: %{"class" => "badge badge-xs"},
            text: rendered_body(Map.get(inspector, :status_text))
          }
        ]
      },
      message:
        if(Map.get(inspector, :message),
          do: %{
            attrs: %{"class" => "text-sm text-base-content/70"},
            text: rendered_body(Map.get(inspector, :message))
          }
        )
    }
  end

  defp copy_presentation(current_path) do
    %{
      host: %{
        attrs: %{
          "id" => "dashboard-evidence-copy-link-component",
          "class" => "contents",
          "data-name" => "ClipboardButton"
        }
      },
      props: %{
        button_id: "dashboard-evidence-copy-link",
        clipboard_text: current_path,
        button_class: "btn btn-sm btn-outline justify-start",
        icon: "hero-link",
        icon_class: "h-4 w-4",
        label: "Copy evidence link"
      }
    }
  end

  defp dashboard_action_presentations(actions) do
    actions
    |> DashboardActionPresentation.visible()
    |> Enum.with_index()
    |> Enum.map(fn {%DashboardAction{} = action, order} ->
      %{
        key: action.action_id,
        order: order,
        attrs:
          raw_attributes(%{
            "id" => action.action_id,
            "href" => action.route,
            "class" => "btn btn-sm btn-outline w-full justify-start",
            "data-dashboard-action" => action.action_id,
            "data-dashboard-action-kind" => Atom.to_string(action.kind),
            "data-dashboard-action-target" => Atom.to_string(action.target),
            "data-dashboard-action-source" => Atom.to_string(action.source),
            "data-dashboard-action-presentation" => Atom.to_string(action.presentation),
            "data-phx-link" => "redirect",
            "data-phx-link-state" => "push"
          }),
        icon: %{name: DashboardActionPresentation.icon(action), class: "h-4 w-4"},
        text: rendered_body(action.label)
      }
    end)
  end

  defp health_activity_presentation(%{render?: true} = activity, current_path) do
    %{
      attrs:
        raw_attributes(%{
          "id" => "dashboard-evidence-health-activity-link",
          "href" => ActivityNavigation.link(current_path, :health_snapshots, activity.event),
          "class" => "btn btn-sm btn-outline justify-start",
          "data-dashboard-health-activity-link" => activity.event_id,
          "data-dashboard-health-activity-snapshot-id" => activity.snapshot_id,
          "data-phx-link" => "redirect",
          "data-phx-link-state" => "push"
        }),
      icon: %{name: "hero-bookmark-square", class: "h-4 w-4"},
      text: "Open activity"
    }
  end

  defp health_activity_presentation(_activity, _current_path), do: nil

  defp rows_presentation(_title, []), do: nil

  defp rows_presentation(title, rows) do
    %{
      attrs: %{"class" => "space-y-2"},
      heading: %{attrs: %{"class" => "hud-label"}, text: title},
      list: %{
        attrs: %{
          "class" => "grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs"
        },
        rows:
          rows
          |> Enum.with_index()
          |> Enum.map(fn {row, order} -> row_presentation(row, order) end)
      }
    }
  end

  defp row_presentation(row, order) do
    label = evidence_value(row, :label)

    %{
      key: "#{order}:#{rendered_body(label)}",
      order: order,
      label: %{
        attrs: %{"class" => "text-base-content/60"},
        text: rendered_body(label)
      },
      value: %{
        attrs:
          raw_attributes(%{
            "class" => "font-mono text-base-content break-all",
            "data-evidence-subject-field" => label,
            "data-evidence-detail" => label
          }),
        text: rendered_body(evidence_value(row, :value))
      }
    }
  end

  defp evidence_presentation([], _inspector, _current_path) do
    %{
      items: [],
      empty: %{
        attrs: %{
          "class" =>
            "rounded border border-base-300/70 bg-base-100/40 px-2 py-2 text-xs text-base-content/60",
          "data-evidence-empty" => "refs"
        },
        text: "No evidence references were provided for this item."
      }
    }
  end

  defp evidence_presentation(evidence, inspector, current_path) do
    %{
      root: %{
        attrs: %{
          "class" => "space-y-2",
          "data-evidence-refs" => ""
        }
      },
      heading: %{attrs: %{"class" => "hud-label"}, text: "Evidence"},
      list: %{attrs: %{"class" => "space-y-1"}},
      items:
        evidence
        |> Enum.with_index()
        |> Enum.map(fn {item, order} ->
          evidence_ref_presentation(item, inspector, current_path, order)
        end),
      empty: nil
    }
  end

  defp evidence_ref_presentation(evidence, inspector, current_path, order) do
    data_link = evidence_data_link(evidence)
    kind_text = evidence_value(evidence, :kind_text)
    id = evidence_value(evidence, :id)

    attrs =
      %{
        "class" => evidence_ref_class(data_link),
        "data-evidence-ref-kind" => kind_text,
        "data-evidence-ref-id" => id || ""
      }
      |> Map.merge(evidence_ref_action_attrs(data_link, evidence, inspector, current_path))
      |> raw_attributes()

    %{
      key: "#{order}:#{rendered_body(kind_text)}:#{rendered_body(id)}",
      order: order,
      tag: if(data_link, do: "button", else: "div"),
      attrs: attrs,
      rows: [
        evidence_ref_row("kind", 0, "Kind", kind_text),
        evidence_ref_row("id", 1, "ID", id),
        evidence_ref_row("source", 2, "Source", evidence_value(evidence, :source_text)),
        evidence_ref_row(
          "confidence",
          3,
          "Confidence",
          evidence_value(evidence, :confidence_text)
        ),
        evidence_ref_row(
          "observed",
          4,
          "Observed",
          evidence_value(evidence, :observed_at_text)
        )
      ]
    }
  end

  defp evidence_ref_class(nil) do
    "grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 rounded border border-base-300/70 px-2 py-1 text-xs"
  end

  defp evidence_ref_class(_data_link) do
    "grid w-full grid-cols-[7rem_minmax(0,1fr)] gap-x-2 rounded border border-base-300/70 px-2 py-1 text-left text-xs hover:border-primary/60 hover:bg-base-100"
  end

  defp evidence_ref_action_attrs(nil, _evidence, _inspector, _current_path), do: %{}

  defp evidence_ref_action_attrs(data_link, evidence, inspector, current_path) do
    data_link
    |> DataLinkAttrs.open(
      context_fallback: evidence_ref_context(inspector, current_path),
      timestamp_ms: evidence_timestamp_ms(evidence)
    )
    |> Map.merge(%{
      "type" => "button",
      "phx-click" => "open_data_link",
      "data-evidence-ref-link-target" => Atom.to_string(data_link.target)
    })
  end

  defp evidence_ref_row(key, order, label, value) do
    %{
      key: key,
      order: order,
      label: %{attrs: %{"class" => "text-base-content/60"}, text: label},
      value: %{
        attrs: %{"class" => "font-mono text-base-content break-all"},
        text: rendered_body(value)
      }
    }
  end

  defp data_links_presentation([]) do
    %{
      items: [],
      empty: %{
        attrs: %{
          "class" =>
            "rounded border border-base-300/70 bg-base-100/40 px-2 py-2 text-xs text-base-content/60",
          "data-evidence-empty" => "links"
        },
        text: "No data links were provided for this item."
      }
    }
  end

  defp data_links_presentation(links) do
    %{
      root: %{
        attrs: %{
          "class" => "space-y-2",
          "data-evidence-links" => ""
        }
      },
      heading: %{attrs: %{"class" => "hud-label"}, text: "Data Links"},
      list: %{attrs: %{"class" => "space-y-1"}},
      items:
        links
        |> Enum.with_index()
        |> Enum.map(fn {link, order} -> data_link_presentation(link, order) end),
      empty: nil
    }
  end

  defp data_link_presentation(link, order) do
    %{
      key: "#{order}:#{rendered_body(link.link_id)}",
      order: order,
      attrs:
        link
        |> DataLinkAttrs.open()
        |> Map.merge(%{
          "type" => "button",
          "phx-click" => "open_data_link",
          "class" =>
            "grid w-full grid-cols-[7rem_minmax(0,1fr)] gap-x-2 rounded border border-base-300/70 px-2 py-1 text-left text-xs hover:border-primary/60 hover:bg-base-100",
          "data-evidence-link-target" => link.target_text,
          "data-evidence-link-id" => link.target_id || "",
          "data-evidence-link-ref" => link.link_id || ""
        })
        |> raw_attributes(),
      rows: [
        %{
          key: "target",
          label: %{
            attrs: %{"class" => "text-base-content/60"},
            text: rendered_body(link.target_text)
          },
          value: %{
            attrs: %{"class" => "font-mono text-base-content break-all"},
            text: rendered_body(link.target_id)
          }
        },
        %{
          key: "label",
          label: %{attrs: %{"class" => "text-base-content/60"}, text: "Label"},
          value: %{
            attrs: %{"class" => "text-base-content break-all"},
            text: rendered_body(link.label)
          }
        }
      ]
    }
  end

  defp evidence_actions(mission_id, inspector, dashboard_document) do
    DashboardActionPresentation.for_inspector(
      inspector,
      mission_id,
      :evidence_panel,
      dashboard_document
    )
  end

  defp text_value(nil), do: ""
  defp text_value(value) when is_atom(value), do: Atom.to_string(value)
  defp text_value(value) when is_binary(value), do: value
  defp text_value(value), do: to_string(value)

  defp raw_attributes(attributes) do
    Enum.reduce(attributes, %{}, fn
      {_key, value}, rendered when value in [nil, false] ->
        rendered

      {key, true}, rendered ->
        Map.put(rendered, to_string(key), "")

      {key, value}, rendered ->
        Map.put(rendered, to_string(key), rendered_body(value))
    end)
  end

  defp rendered_body(nil), do: ""
  defp rendered_body(value), do: text_value(value)

  defp evidence_timestamp_ms(evidence) do
    evidence
    |> evidence_observed_at()
    |> datetime_to_unix_ms()
  end

  defp evidence_observed_at(evidence) when is_map(evidence) do
    evidence_value(evidence, :observed_at) ||
      parse_observed_at_text(evidence_value(evidence, :observed_at_text))
  end

  defp evidence_observed_at(_evidence), do: nil

  defp parse_observed_at_text(value) when is_binary(value) and value != "" do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _invalid -> nil
    end
  end

  defp parse_observed_at_text(_value), do: nil

  defp datetime_to_unix_ms(%DateTime{} = datetime), do: DateTime.to_unix(datetime, :millisecond)
  defp datetime_to_unix_ms(_datetime), do: nil

  defp evidence_ref_context(inspector, current_path) when is_map(inspector) do
    rows = Map.get(inspector, :subject_rows, []) ++ Map.get(inspector, :detail_rows, [])
    query = path_query(current_path)

    %{
      realm: evidence_row_value(rows, "Realm") || evidence_row_value(rows, "Data realm"),
      data_view: evidence_row_value(rows, "Data view"),
      data_source_id: evidence_row_value(rows, "Data source"),
      source_binding_id: evidence_row_value(rows, "Source binding"),
      time_mode: evidence_row_value(rows, "Time mode"),
      time_axis: evidence_row_value(rows, "Time axis"),
      replay_run_id: evidence_row_value(rows, "Replay run"),
      scope_kind: Map.get(query, "scope_kind"),
      scope_id: Map.get(query, "scope_id") || Map.get(query, "spacecraft_id"),
      scope_ids: Map.get(query, "scope_ids")
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp evidence_ref_context(_inspector, _current_path), do: %{}

  defp path_query(current_path) when is_binary(current_path) do
    current_path
    |> URI.parse()
    |> Map.get(:query)
    |> case do
      nil -> %{}
      query -> URI.decode_query(query)
    end
  rescue
    URI.Error -> %{}
  end

  defp path_query(_current_path), do: %{}

  defp evidence_row_value(rows, label) do
    case Enum.find_value(rows, fn
           %{label: ^label, value: value} -> value
           %{"label" => ^label, "value" => value} -> value
           _row -> nil
         end) do
      nil -> nil
      value -> text_value(value)
    end
  end

  defp evidence_data_link(evidence) do
    with target when is_atom(target) <- evidence_target(evidence),
         id when is_binary(id) and id != "" <- evidence_value(evidence, :id) do
      %{
        link_id: "evidence-ref:#{Atom.to_string(target)}:#{id}",
        label: evidence_label(target),
        target: target,
        target_text: target |> Atom.to_string() |> String.replace("_", " "),
        target_id: id,
        context: %{}
      }
    else
      _missing -> nil
    end
  end

  defp evidence_target(evidence) do
    kind = evidence_kind(evidence)

    Map.get(@evidence_data_link_targets, kind) ||
      operational_interval_target(kind, evidence)
  end

  defp operational_interval_target(:operational_interval, evidence) do
    case evidence_kind(evidence, :interval_kind) do
      :source_health ->
        :source_health_interval

      _other ->
        if evidence_kind(evidence, :confidence) == :direct, do: :operational_event
    end
  end

  defp operational_interval_target(_kind, _evidence), do: nil

  defp evidence_kind(evidence, key \\ :kind) do
    evidence
    |> evidence_value(key)
    |> normalize_evidence_atom()
  end

  defp evidence_value(evidence, key) when is_map(evidence) and is_atom(key) do
    Map.get(evidence, key, Map.get(evidence, Atom.to_string(key)))
  end

  defp evidence_value(_evidence, _key), do: nil

  defp normalize_evidence_atom(value) when is_atom(value), do: value

  defp normalize_evidence_atom(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.replace(" ", "_")
    |> String.replace("-", "_")
    |> evidence_atom()
  end

  defp normalize_evidence_atom(_value), do: nil

  defp evidence_atom("raw_evidence"), do: :raw_evidence
  defp evidence_atom("telemetry_sample"), do: :telemetry_sample
  defp evidence_atom("limit_event"), do: :limit_event
  defp evidence_atom("limit_definition"), do: :limit_definition
  defp evidence_atom("limit_definition_interval"), do: :limit_definition_interval

  defp evidence_atom("limit_definition_lifecycle_event"),
    do: :limit_definition_lifecycle_event

  defp evidence_atom("mission_event"), do: :mission_event
  defp evidence_atom("operational_event"), do: :operational_event
  defp evidence_atom("command_queue_entry"), do: :command_queue_entry
  defp evidence_atom("operational_interval"), do: :operational_interval
  defp evidence_atom("binding_set_interval"), do: :binding_set_interval
  defp evidence_atom("application_binding_interval"), do: :application_binding_interval
  defp evidence_atom("catalog_revision_interval"), do: :catalog_revision_interval
  defp evidence_atom("source_binding_interval"), do: :source_binding_interval
  defp evidence_atom("transport_execution_interval"), do: :transport_execution_interval

  defp evidence_atom("transport_connection_state_interval"),
    do: :transport_connection_state_interval

  defp evidence_atom("ground_station_connection_state_interval"),
    do: :ground_station_connection_state_interval

  defp evidence_atom("ground_station_antenna_pointing_state_interval"),
    do: :ground_station_antenna_pointing_state_interval

  defp evidence_atom("link_rf_lock_state_interval"), do: :link_rf_lock_state_interval
  defp evidence_atom("link_frame_sync_state_interval"), do: :link_frame_sync_state_interval

  defp evidence_atom("source_health_event"), do: :source_health_event
  defp evidence_atom("source_watermark_event"), do: :source_watermark_event
  defp evidence_atom("source_binding_event"), do: :source_binding_event
  defp evidence_atom("telemetry_revision_decision_event"), do: :telemetry_revision_decision_event

  defp evidence_atom("telemetry_backfill_lifecycle_event"),
    do: :telemetry_backfill_lifecycle_event

  defp evidence_atom("contact"), do: :contact
  defp evidence_atom("scheduled_contact"), do: :scheduled_contact
  defp evidence_atom("realized_contact"), do: :realized_contact
  defp evidence_atom(_value), do: nil

  defp evidence_label(target) do
    target
    |> Atom.to_string()
    |> String.replace("_", " ")
  end
end
