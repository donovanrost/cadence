defmodule CadenceWeb.OpsTimelineLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.MissionEvents.Entry
  alias Cadence.Reads.MissionTimeline
  alias Phoenix.LiveView.JS

  @query_keys ~w(
    event_id category kind severity spacecraft_id scope_kind scope_id from to source_dashboard_id
    return_to time_mode time_axis replay_run_id realm data_view data_source_id source_binding_id
    limit_mode selected_id
  )

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Mission Timeline")
     |> assign(:ops_nav_item, :timeline)
     |> assign(:timeline_context, timeline_context(%{}))
     |> assign(:timeline_presentation, %{})
     |> stream(:timeline_events, [], dom_id: &timeline_dom_id/1)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    context = timeline_context(params)

    events =
      MissionTimeline.list_for_mission(
        scope.organization_id,
        mission.mission_id,
        event_read_opts(context)
      )

    selected_event = selected_event(scope.organization_id, mission.mission_id, context.event_id)

    timeline_events =
      Enum.map(events, &timeline_event_presentation(&1, mission.mission_id, context))

    {:noreply,
     socket
     |> assign(:timeline_context, context)
     |> assign(
       :timeline_presentation,
       timeline_presentation(mission.mission_id, context, selected_event)
     )
     |> stream(:timeline_events, timeline_events, reset: true)}
  end

  @impl true
  def handle_event("apply_timeline_filters", %{"timeline" => params}, socket) do
    mission_id = socket.assigns.current_mission.mission_id

    query =
      socket.assigns.timeline_context
      |> context_query()
      |> Map.merge(Map.take(params, ~w(category kind severity spacecraft_id from to)))
      |> Map.delete("event_id")
      |> compact_query()

    {:noreply, push_patch(socket, to: ~p"/missions/#{mission_id}/ops/timeline?#{query}")}
  end

  def handle_event("clear_timeline_selection", _params, socket) do
    mission_id = socket.assigns.current_mission.mission_id
    query = socket.assigns.timeline_context |> context_query() |> Map.delete("event_id")

    {:noreply, push_patch(socket, to: ~p"/missions/#{mission_id}/ops/timeline?#{query}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="ops-timeline-page-component"
        v-component="FederatedFullPageSurface"
        application_key="ops_console"
        surface_id="timeline"
        host_scope="mission"
        mission_id={@current_mission.mission_id}
        query_params={%{}}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end

  @doc false
  def presentation_attrs(attrs) when is_map(attrs) do
    Enum.reduce(attrs, %{}, fn
      {_name, value}, rendered when value in [nil, false] ->
        rendered

      {name, true}, rendered ->
        Map.put(rendered, name, "")

      {name, value}, rendered ->
        Map.put(rendered, name, to_string(value))
    end)
  end

  defp timeline_presentation(mission_id, context, selected_event) do
    %{
      root: %{
        attrs:
          presentation_attrs(%{
            "id" => "ops-timeline-page",
            "class" => "min-h-0 flex-1 overflow-y-auto"
          })
      },
      container: %{
        attrs:
          presentation_attrs(%{
            "class" => "mx-auto max-w-[96rem] space-y-4 px-5 py-6"
          })
      },
      header: header_presentation(mission_id, context),
      filters: filter_presentation(context),
      body: %{
        attrs:
          presentation_attrs(%{
            "class" => "grid min-h-[40rem] gap-4 xl:grid-cols-[minmax(0,1fr)_28rem]"
          }),
        timeline: timeline_list_presentation(),
        detail: event_detail_presentation(mission_id, context, selected_event)
      }
    }
  end

  defp header_presentation(mission_id, context) do
    %{
      attrs:
        presentation_attrs(%{
          "class" =>
            "flex flex-col gap-3 border-b border-primary/20 pb-4 lg:flex-row lg:items-end lg:justify-between"
        }),
      content: %{attrs: %{}},
      eyebrow: %{
        attrs: presentation_attrs(%{"class" => "hud-label"}),
        text: "Observe / Canonical event projection"
      },
      title: %{
        attrs: presentation_attrs(%{"class" => "mt-1 text-xl font-semibold tracking-tight"}),
        text: "Mission Timeline"
      },
      description: %{
        attrs:
          presentation_attrs(%{
            "class" => "mt-1 max-w-3xl text-sm text-base-content/60"
          }),
        text:
          "Contacts, alarms, commands, source posture, catalog activation, historical repair, and runtime facts in one read-only sequence."
      },
      return_link: return_link_presentation(return_path(mission_id, context))
    }
  end

  defp return_link_presentation(nil), do: nil

  defp return_link_presentation(path) do
    %{
      attrs:
        navigate_attrs(path, %{
          "id" => "timeline-return-to-origin",
          "class" => "btn btn-sm btn-ghost"
        }),
      icon: %{
        attrs: presentation_attrs(%{"class" => "hero-arrow-uturn-left h-4 w-4"})
      },
      text: "Return to investigation"
    }
  end

  defp filter_presentation(context) do
    %{
      attrs:
        presentation_attrs(%{
          "id" => "timeline-filter-form",
          "class" =>
            "grid gap-3 border border-base-300 bg-base-200/35 p-3 md:grid-cols-3 xl:grid-cols-[10rem_12rem_10rem_minmax(12rem,1fr)_13rem_13rem_auto] xl:items-end"
        }),
      values: filter_params(context),
      fields: [
        filter_field_presentation("category", "select", "Category", nil, category_options()),
        filter_field_presentation(
          "kind",
          "text",
          "Kind",
          "telemetry_backfill_failed",
          []
        ),
        filter_field_presentation("severity", "select", "Severity", nil, severity_options()),
        filter_field_presentation("spacecraft_id", "text", "Spacecraft", nil, []),
        filter_field_presentation("from", "text", "From", nil, []),
        filter_field_presentation("to", "text", "To", nil, [])
      ],
      submit: %{
        attrs:
          presentation_attrs(%{
            "id" => "timeline-apply-filters",
            "type" => "submit",
            "class" => "btn btn-sm btn-primary"
          }),
        icon: %{attrs: presentation_attrs(%{"class" => "hero-funnel h-4 w-4"})},
        text: "Apply"
      }
    }
  end

  defp filter_field_presentation(key, type, label, placeholder, options) do
    control_attrs =
      %{
        "id" => "timeline_#{key}",
        "name" => "timeline[#{key}]",
        "type" => if(type == "select", do: nil, else: type),
        "placeholder" => placeholder,
        "class" => if(type == "select", do: "w-full select", else: "w-full input")
      }
      |> presentation_attrs()

    %{
      key: key,
      type: type,
      wrapper: %{attrs: presentation_attrs(%{"class" => "fieldset mb-3"})},
      label: %{attrs: %{}},
      label_text: %{
        attrs: presentation_attrs(%{"class" => "hud-label block mb-1.5"}),
        text: label
      },
      control: %{attrs: control_attrs},
      options:
        Enum.map(options, fn {option_label, value} ->
          %{label: option_label, value: value}
        end)
    }
  end

  defp timeline_list_presentation do
    %{
      section: %{
        attrs: presentation_attrs(%{"class" => "border border-base-300 bg-base-100"})
      },
      header: %{
        attrs:
          presentation_attrs(%{
            "class" =>
              "grid grid-cols-[10rem_7rem_minmax(10rem,1fr)_8rem] gap-3 border-b border-base-300 bg-base-200/50 px-3 py-2 text-[0.65rem] font-semibold uppercase tracking-wider text-base-content/45"
          }),
        columns: ["Occurred", "Category", "Event", "Subject"]
      },
      stream: %{
        attrs:
          presentation_attrs(%{
            "id" => "mission-timeline-events",
            "class" => "divide-y divide-base-300"
          }),
        empty: %{
          attrs:
            presentation_attrs(%{
              "id" => "mission-timeline-events-empty",
              "class" => "hidden only:block p-8 text-center text-sm text-base-content/50"
            }),
          text: "No canonical mission events match this context."
        }
      }
    }
  end

  defp event_detail_presentation(_mission_id, _context, nil) do
    %{
      attrs:
        presentation_attrs(%{
          "id" => "timeline-event-detail",
          "class" => "border border-base-300 bg-base-200/35 p-4"
        }),
      empty: %{
        attrs:
          presentation_attrs(%{
            "class" => "grid min-h-[20rem] place-items-center text-center"
          }),
        content: %{attrs: %{}},
        icon: %{
          attrs:
            presentation_attrs(%{
              "class" => "hero-clock mx-auto h-8 w-8 text-base-content/25"
            })
        },
        copy: %{
          attrs: presentation_attrs(%{"class" => "mt-3 text-sm text-base-content/55"}),
          text: "Select an event to inspect its canonical identity and evidence."
        }
      },
      selected: nil
    }
  end

  defp event_detail_presentation(mission_id, context, %Entry{} = event) do
    event_path = timeline_event_path(mission_id, context, event.mission_event_id)

    %{
      attrs:
        presentation_attrs(%{
          "id" => "timeline-event-detail",
          "class" => "border border-base-300 bg-base-200/35 p-4"
        }),
      empty: nil,
      selected: %{
        attrs: presentation_attrs(%{"class" => "space-y-4"}),
        header: %{
          attrs: presentation_attrs(%{"class" => "flex items-start justify-between gap-3"}),
          content: %{attrs: presentation_attrs(%{"class" => "min-w-0"})},
          kind: %{
            attrs: presentation_attrs(%{"class" => "hud-label"}),
            text: to_string(event.kind)
          },
          title: %{
            attrs:
              presentation_attrs(%{
                "id" => "timeline-selected-event-title",
                "class" => "mt-1 text-base font-semibold"
              }),
            text: event.title
          },
          clear: %{
            attrs:
              presentation_attrs(%{
                "id" => "timeline-clear-selection",
                "type" => "button",
                "class" => "btn btn-ghost btn-xs"
              }),
            icon: %{attrs: presentation_attrs(%{"class" => "hero-x-mark h-4 w-4"})}
          }
        },
        copy: %{
          host_attrs:
            presentation_attrs(%{
              "id" => "timeline-copy-event-link-component",
              "class" => "contents"
            }),
          button_id: "timeline-copy-event-link",
          clipboard_text: event_path,
          button_class: "btn btn-xs btn-outline w-full justify-start",
          icon: "hero-link",
          icon_class: "h-3.5 w-3.5",
          label: "Copy canonical event link"
        },
        rows: %{
          attrs:
            presentation_attrs(%{
              "class" => "grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-2 text-xs"
            }),
          items: Enum.map(event_rows(event), &event_detail_row_presentation/1)
        },
        investigation: %{
          attrs:
            presentation_attrs(%{
              "class" => "space-y-2 border-t border-base-300 pt-4"
            }),
          title: %{
            attrs: presentation_attrs(%{"class" => "hud-label"}),
            text: "Continue investigation"
          },
          links: %{
            attrs: presentation_attrs(%{"class" => "grid gap-2"}),
            owner: owner_link_presentation(event_owner_path(mission_id, event)),
            explore: explore_link_presentation(event_explore_path(mission_id, event, context))
          }
        }
      }
    }
  end

  defp event_detail_row_presentation(row) do
    %{
      label: %{
        attrs: presentation_attrs(%{"class" => "text-base-content/50"}),
        text: row.label
      },
      value: %{
        attrs:
          presentation_attrs(%{
            "class" => "break-all font-mono",
            "data-timeline-event-field" => row.label
          }),
        text: to_string(row.value)
      }
    }
  end

  defp owner_link_presentation(nil), do: nil

  defp owner_link_presentation(path) do
    %{
      attrs:
        navigate_attrs(path, %{
          "id" => "timeline-open-event-owner",
          "class" => "btn btn-xs btn-outline justify-start"
        }),
      icon: %{
        attrs: presentation_attrs(%{"class" => "hero-arrow-top-right-on-square h-3.5 w-3.5"})
      },
      text: "Open owning workflow"
    }
  end

  defp explore_link_presentation(nil), do: nil

  defp explore_link_presentation(path) do
    %{
      attrs:
        navigate_attrs(path, %{
          "id" => "timeline-explore-event",
          "class" => "btn btn-xs btn-outline justify-start"
        }),
      icon: %{
        attrs: presentation_attrs(%{"class" => "hero-magnifying-glass h-3.5 w-3.5"})
      },
      text: "Explore telemetry context"
    }
  end

  defp timeline_event_presentation(%Entry{} = event, mission_id, context) do
    row_class =
      "grid grid-cols-[10rem_7rem_minmax(10rem,1fr)_8rem] gap-3 px-3 py-3 text-xs hover:bg-primary/5"

    row_class =
      if context.event_id == event.mission_event_id do
        row_class <> " border-l-2 border-primary bg-primary/10"
      else
        row_class
      end

    %{
      mission_event_id: event.mission_event_id,
      attrs:
        patch_attrs(
          timeline_event_path(mission_id, context, event.mission_event_id),
          %{
            "class" => row_class,
            "data-mission-event-kind" => event.kind,
            "data-mission-event-category" => event.category,
            "data-mission-event-severity" => event.severity || "none"
          }
        ),
      occurred: %{
        attrs: presentation_attrs(%{"class" => "font-mono text-base-content/55"}),
        text: format_time(event.occurred_at)
      },
      category: %{
        attrs: presentation_attrs(%{"class" => "font-mono"}),
        text: to_string(event.category)
      },
      event: %{
        attrs: presentation_attrs(%{"class" => "min-w-0"}),
        title: %{
          attrs: presentation_attrs(%{"class" => "block truncate font-semibold"}),
          text: event.title
        },
        summary: %{
          attrs:
            presentation_attrs(%{
              "class" => "mt-0.5 block truncate text-base-content/50"
            }),
          text: event.summary || to_string(event.kind)
        }
      },
      subject: %{
        attrs:
          presentation_attrs(%{
            "class" => "truncate font-mono text-base-content/55"
          }),
        text: event.subject_id || event.source_record_id
      }
    }
  end

  defp navigate_attrs(path, attrs) do
    %{
      "data-phx-link" => "redirect",
      "data-phx-link-state" => "push",
      "href" => path
    }
    |> Map.merge(attrs)
    |> presentation_attrs()
  end

  defp patch_attrs(path, attrs) do
    %{
      "data-phx-link" => "patch",
      "data-phx-link-state" => "push",
      "href" => path
    }
    |> Map.merge(attrs)
    |> presentation_attrs()
  end

  defp timeline_context(params) do
    %{
      event_id: text(params["event_id"]),
      category: text(params["category"]),
      kind: text(params["kind"]),
      severity: text(params["severity"]),
      spacecraft_id: text(params["spacecraft_id"]),
      scope_kind: text(params["scope_kind"]),
      scope_id: text(params["scope_id"]),
      from: text(params["from"]),
      to: text(params["to"]),
      source_dashboard_id: text(params["source_dashboard_id"]),
      return_to: text(params["return_to"]),
      time_mode: text(params["time_mode"]),
      time_axis: text(params["time_axis"]),
      replay_run_id: text(params["replay_run_id"]),
      realm: text(params["realm"]),
      data_view: text(params["data_view"]),
      data_source_id: text(params["data_source_id"]),
      source_binding_id: text(params["source_binding_id"]),
      selected_id: text(params["selected_id"]),
      limit_mode: text(params["limit_mode"])
    }
  end

  defp event_read_opts(context) do
    [limit: 500]
    |> maybe_put(:category, context.category)
    |> maybe_put(:kind, context.kind)
    |> maybe_put(:severity, context.severity)
    |> maybe_put(:spacecraft_id, context.spacecraft_id)
    |> maybe_put(:from_occurred_at, parse_datetime(context.from))
    |> maybe_put(:to_occurred_at, parse_datetime(context.to))
  end

  defp selected_event(_organization_id, _mission_id, nil), do: nil

  defp selected_event(organization_id, mission_id, event_id) do
    case MissionTimeline.fetch_for_mission(organization_id, mission_id, event_id) do
      {:ok, event} -> event
      {:error, :mission_event_not_found} -> nil
    end
  end

  defp timeline_event_path(mission_id, context, event_id) do
    query = context |> context_query() |> Map.put("event_id", event_id)
    ~p"/missions/#{mission_id}/ops/timeline?#{query}"
  end

  defp timeline_dom_id(event) do
    safe_id = String.replace(event.mission_event_id, ~r/[^A-Za-z0-9_-]/, "-")
    "mission-event-#{safe_id}"
  end

  defp context_query(context) do
    context
    |> Enum.map(fn {key, value} -> {Atom.to_string(key), value} end)
    |> Map.new()
    |> Map.take(@query_keys)
    |> compact_query()
  end

  defp filter_params(context) do
    %{
      "category" => context.category || "",
      "kind" => context.kind || "",
      "severity" => context.severity || "",
      "spacecraft_id" => context.spacecraft_id || "",
      "from" => context.from || "",
      "to" => context.to || ""
    }
  end

  defp return_path(mission_id, %{source_dashboard_id: dashboard_id} = context)
       when is_binary(dashboard_id) and context.return_to != "explore" do
    query =
      %{
        "time_mode" => context.time_mode,
        "time_axis" => context.time_axis,
        "from" => context.from,
        "to" => context.to,
        "replay_run_id" => context.replay_run_id,
        "realm" => context.realm,
        "data_view" => context.data_view,
        "selected_data_view" => context.data_view,
        "data_source_id" => context.data_source_id,
        "source_binding_id" => context.source_binding_id,
        "scope_kind" => context.scope_kind,
        "scope_id" => context.scope_id,
        "limit_mode" => context.limit_mode,
        "selected_target" => if(context.selected_id, do: "mission_event"),
        "selected_id" => context.selected_id
      }
      |> compact_query()

    ~p"/missions/#{mission_id}/ops/dashboards/#{dashboard_id}?#{query}"
  end

  defp return_path(mission_id, %{return_to: "explore"} = context) do
    query =
      %{
        "spacecraft_id" => context.spacecraft_id,
        "scope_kind" => context.scope_kind,
        "scope_id" => context.scope_id,
        "time_mode" => context.time_mode,
        "time_axis" => context.time_axis,
        "from" => context.from,
        "to" => context.to,
        "replay_run_id" => context.replay_run_id,
        "realm" => context.realm,
        "selection_view" => context.data_view,
        "data_source_id" => context.data_source_id,
        "source_binding_id" => context.source_binding_id,
        "source_dashboard_id" => context.source_dashboard_id,
        "limit_mode" => context.limit_mode
      }
      |> compact_query()

    ~p"/missions/#{mission_id}/ops/explore?#{query}"
  end

  defp return_path(_mission_id, _context), do: nil

  defp event_owner_path(mission_id, %Entry{} = event) do
    event_owner_path(mission_id, event, historical_event?(event))
  end

  defp event_owner_path(mission_id, %Entry{} = event, true) do
    case historical_group_id(event) do
      group_id when is_binary(group_id) ->
        ~p"/missions/#{mission_id}/ops/data-operations?#{%{group: group_id}}"

      _missing_group ->
        ~p"/missions/#{mission_id}/ops/data-operations"
    end
  end

  defp event_owner_path(
         mission_id,
         %Entry{subject_kind: :data_source, subject_id: subject_id},
         false
       )
       when is_binary(subject_id),
       do: ~p"/missions/#{mission_id}/ops/data-sources/#{subject_id}"

  defp event_owner_path(
         mission_id,
         %Entry{kind: :limit_violation, subject_id: point_id, source_record_id: event_id},
         false
       ),
       do: ~p"/missions/#{mission_id}/ops/alarms?#{%{point_id: point_id, event_id: event_id}}"

  defp event_owner_path(mission_id, %Entry{subject_kind: :command, subject_id: command_id}, false)
       when is_binary(command_id),
       do: ~p"/missions/#{mission_id}/ops/commands?#{%{command_id: command_id}}"

  defp event_owner_path(mission_id, %Entry{realized_contact_id: contact_id}, false)
       when is_binary(contact_id),
       do: ~p"/missions/#{mission_id}/ops/contacts/records/#{contact_id}"

  defp event_owner_path(mission_id, %Entry{scheduled_contact_id: contact_id}, false)
       when is_binary(contact_id),
       do: ~p"/missions/#{mission_id}/ops/contacts/records/#{contact_id}"

  defp event_owner_path(
         mission_id,
         %Entry{subject_kind: subject_kind, subject_id: contact_id},
         false
       )
       when subject_kind in [:contact, :scheduled_contact, :realized_contact] and
              is_binary(contact_id),
       do: ~p"/missions/#{mission_id}/ops/contacts/records/#{contact_id}"

  defp event_owner_path(_mission_id, %Entry{}, false), do: nil

  defp event_explore_path(mission_id, %Entry{} = event, context) do
    point_id = if event.subject_kind == :telemetry_point, do: event.subject_id

    if is_binary(point_id) do
      query =
        %{
          "point_id" => point_id,
          "spacecraft_id" => event.spacecraft_id,
          "scope_kind" => context.scope_kind,
          "scope_id" => context.scope_id,
          "time_mode" => context.time_mode || "archive",
          "time_axis" => context.time_axis,
          "from" => context.from,
          "to" => context.to,
          "replay_run_id" => context.replay_run_id,
          "realm" => context.realm,
          "selection_view" => context.data_view,
          "data_source_id" => metadata_value(event, "data_source_id"),
          "source_binding_id" => metadata_value(event, "source_binding_id"),
          "limit_mode" => context.limit_mode,
          "selected_time" => DateTime.to_iso8601(event.occurred_at)
        }
        |> compact_query()

      ~p"/missions/#{mission_id}/ops/explore?#{query}"
    end
  end

  defp historical_event?(event) do
    event.kind
    |> Atom.to_string()
    |> String.starts_with?(["telemetry_backfill_", "telemetry_import_"])
  end

  defp historical_group_id(event) do
    metadata_value(event, "request_group_id") ||
      get_in(event.metadata, ["payload", "lifecycle_payload", "request_group_id"]) ||
      get_in(event.metadata, ["payload", "backfill_run_id"]) || event.correlation_key
  end

  defp metadata_value(%Entry{metadata: metadata}, key) when is_map(metadata) do
    Map.get(metadata, key) ||
      get_in(metadata, ["scope", key]) ||
      get_in(metadata, ["payload", key])
  end

  defp event_rows(event) do
    [
      row("Event", event.mission_event_id),
      row("Occurred", format_time(event.occurred_at)),
      row("Category", event.category),
      row("Kind", event.kind),
      row("Severity", event.severity),
      row("Status", event.status),
      row("Source kind", event.source_record_kind),
      row("Source record", event.source_record_id),
      row("Subject kind", event.subject_kind),
      row("Subject", event.subject_id),
      row("Correlation", event.correlation_key),
      row("Spacecraft", event.spacecraft_id),
      row("Source endpoint", event.source_endpoint_ref)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp row(_label, nil), do: nil
  defp row(label, value), do: %{label: label, value: value}

  defp category_options,
    do: [
      {"All", ""},
      {"Operations", "operations"},
      {"Health", "health"},
      {"Runtime", "runtime"},
      {"Transport", "transport"}
    ]

  defp severity_options,
    do: [
      {"All", ""},
      {"Info", "info"},
      {"Warning", "warning"},
      {"Error", "error"},
      {"Critical", "critical"}
    ]

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _error -> nil
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, ""), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp compact_query(query) do
    query
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp format_time(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%SZ")
  defp format_time(_datetime), do: "unknown"

  defp text(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp text(_value), do: nil
end
