defmodule CadenceWeb.OpsDashboardDiagnosticsLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Dashboards.Document
  alias Cadence.Projections.DashboardRuntimeInvalidations
  alias Cadence.Projections.DataSources.Health, as: SourceHealth

  @collections ~w(plan requests frames cache source refresh invalidations)
  @runtime_query_keys ~w(spacecraft_id scope_kind scope_id time_mode time_axis from to replay_run_id realm data_view data_source_id source_binding_id limit_mode selected_id)

  @impl true
  def mount(%{"dashboard_id" => dashboard_id}, _session, socket) do
    socket =
      socket
      |> stream_configure(:diagnostic_rows, dom_id: &"dashboard-diagnostic-row-#{&1.id}")
      |> assign(:ops_nav_item, :dashboards)
      |> assign(:active_dashboard_id, dashboard_id)
      |> assign(:dashboard_id, dashboard_id)
      |> assign(:diagnostic_collection, "plan")
      |> assign(:runtime_query, %{})
      |> assign(:diagnostic_rows_list, [])
      |> assign(:selected_diagnostic, nil)
      |> assign(:diagnostic_count, 0)

    {:ok, load_diagnostics(socket)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    collection = normalize_collection(params["collection"])
    rows = Map.get(socket.assigns.diagnostic_collections, collection, [])
    selected = select_row(rows, params["selected"])
    runtime_query = runtime_query(params)

    socket =
      socket
      |> assign(:diagnostic_collection, collection)
      |> assign(:runtime_query, runtime_query)
      |> assign(:diagnostic_rows_list, rows)
      |> assign(:selected_diagnostic, selected)
      |> assign(:diagnostic_count, length(rows))
      |> assign_diagnostics_presentation()

    stream_rows =
      Enum.map(rows, fn row ->
        diagnostic_row_presentation(
          row,
          selected,
          socket.assigns.current_mission.mission_id,
          socket.assigns.dashboard_id,
          collection,
          runtime_query
        )
      end)

    {:noreply, stream(socket, :diagnostic_rows, stream_rows, reset: true)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="ops-dashboard-diagnostics-page-component"
        v-component="FederatedFullPageSurface"
        presentation={@presentation}
        diagnostic_rows={@streams.diagnostic_rows}
        v-diff={false}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end

  defp load_diagnostics(socket) do
    %{current_scope: scope, current_mission: mission, dashboard_id: dashboard_id} = socket.assigns

    case Cadence.Dashboards.fetch_document(
           scope.organization_id,
           mission.mission_id,
           dashboard_id
         ) do
      {:ok, %Document{} = document} ->
        collections = diagnostic_collections(scope, mission, document)
        rows = Map.get(collections, "plan", [])
        selected = select_row(rows, nil)

        socket
        |> assign(:page_title, "#{document.name} Diagnostics")
        |> assign(:dashboard_document, document)
        |> assign(:collections, @collections)
        |> assign(:diagnostic_collections, collections)
        |> assign(:diagnostic_collection, "plan")
        |> assign(:runtime_query, %{})
        |> assign(:diagnostic_rows_list, rows)
        |> assign(:selected_diagnostic, selected)
        |> assign(:diagnostic_count, length(rows))
        |> assign_diagnostics_presentation()

      {:error, _reason} ->
        socket
        |> put_flash(:error, "Dashboard diagnostics are unavailable.")
        |> push_navigate(to: ~p"/missions/#{mission.mission_id}/ops/dashboards")
    end
  end

  @doc false
  def presentation_attrs(attrs) when is_map(attrs) do
    Enum.reduce(attrs, %{}, fn
      {_name, value}, rendered when value in [nil, false] ->
        rendered

      {name, true}, rendered ->
        Map.put(rendered, to_string(name), "")

      {name, value}, rendered ->
        Map.put(rendered, to_string(name), to_string(value))
    end)
  end

  defp assign_diagnostics_presentation(socket) do
    assign(socket, :presentation, diagnostics_presentation(socket.assigns))
  end

  defp diagnostics_presentation(assigns) do
    mission_id = assigns.current_mission.mission_id
    dashboard_id = assigns.dashboard_id
    runtime_query = assigns.runtime_query

    %{
      "root" => %{
        "attrs" =>
          presentation_attrs(%{
            "id" => "dashboard-diagnostics-page",
            "class" => "h-full overflow-y-auto bg-base-100"
          })
      },
      "header" => %{
        "attrs" =>
          presentation_attrs(%{
            "class" => "border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7"
          }),
        "inner" => %{
          "attrs" =>
            presentation_attrs(%{
              "class" => "mx-auto flex max-w-[110rem] items-end justify-between gap-4"
            })
        },
        "content" => %{"attrs" => %{}},
        "eyebrow" => %{
          "attrs" =>
            presentation_attrs(%{
              "class" => "font-mono text-[0.65rem] uppercase tracking-[0.2em] text-primary/70"
            }),
          "text" => "Dashboard / Diagnostics"
        },
        "heading" => %{
          "attrs" => presentation_attrs(%{"class" => "mt-1 text-2xl font-bold tracking-tight"}),
          "text" => assigns.dashboard_document.name
        },
        "copy" => %{
          "attrs" => presentation_attrs(%{"class" => "mt-2 text-sm text-base-content/60"}),
          "text" => "Explainable plan, execution, source, refresh, and invalidation evidence."
        },
        "viewer" => %{
          "attrs" =>
            navigate_attrs(
              ~p"/missions/#{mission_id}/ops/dashboards/#{dashboard_id}?#{runtime_query}",
              %{
                "id" => "dashboard-diagnostics-viewer",
                "class" => "btn btn-ghost btn-sm"
              }
            ),
          "text" => "Back to Viewer"
        }
      },
      "content" => %{
        "attrs" => presentation_attrs(%{"class" => "mx-auto max-w-[110rem] p-5 lg:p-7"})
      },
      "collections" =>
        collections_presentation(
          assigns.collections,
          assigns.diagnostic_collections,
          assigns.diagnostic_collection,
          mission_id,
          dashboard_id,
          runtime_query
        ),
      "workspace" => %{
        "attrs" =>
          presentation_attrs(%{
            "class" =>
              "grid min-h-[34rem] border-x border-b border-base-300 lg:grid-cols-[24rem_minmax(0,1fr)]"
          })
      },
      "master" => master_presentation(assigns.diagnostic_collection, assigns.diagnostic_count),
      "detail" =>
        detail_presentation(
          assigns.selected_diagnostic,
          assigns.current_scope,
          mission_id,
          dashboard_id,
          runtime_query
        )
    }
  end

  defp collections_presentation(
         collections,
         diagnostic_collections,
         selected_collection,
         mission_id,
         dashboard_id,
         runtime_query
       ) do
    %{
      "attrs" =>
        presentation_attrs(%{
          "id" => "dashboard-diagnostic-collections",
          "class" => "flex flex-wrap gap-1 border-b border-base-300",
          "aria-label" => "Diagnostic collections"
        }),
      "items" =>
        Enum.map(collections, fn collection ->
          %{
            "key" => collection,
            "attrs" =>
              patch_attrs(
                diagnostic_path(
                  mission_id,
                  dashboard_id,
                  collection,
                  nil,
                  runtime_query
                ),
                %{
                  "id" => "dashboard-diagnostic-collection-#{collection}",
                  "data-diagnostic-collection" => collection,
                  "class" => collection_class(collection, selected_collection)
                }
              ),
            "label" => collection_label(collection),
            "count" => %{
              "attrs" => presentation_attrs(%{"class" => "ml-1 opacity-60"}),
              "text" => to_string(length(Map.get(diagnostic_collections, collection, [])))
            }
          }
        end)
    }
  end

  defp master_presentation(collection, count) do
    %{
      "attrs" =>
        presentation_attrs(%{
          "class" => "border-b border-base-300 lg:border-b-0 lg:border-r"
        }),
      "header" => %{
        "attrs" =>
          presentation_attrs(%{
            "class" => "flex items-center justify-between bg-base-200/45 px-3 py-2"
          }),
        "label" => %{
          "attrs" => presentation_attrs(%{"class" => "hud-label"}),
          "text" => collection_label(collection)
        },
        "count" => %{
          "attrs" =>
            presentation_attrs(%{
              "id" => "dashboard-diagnostic-count",
              "class" => "font-mono text-xs text-base-content/45"
            }),
          "text" => to_string(count)
        }
      },
      "stream" => %{
        "attrs" =>
          presentation_attrs(%{
            "id" => "dashboard-diagnostic-rows",
            "class" => "divide-y divide-base-300/70"
          }),
        "empty" => %{
          "attrs" =>
            presentation_attrs(%{
              "id" => "dashboard-diagnostic-rows-empty",
              "class" => "hidden only:block p-5 text-sm text-base-content/55"
            }),
          "text" => "No records exist for this diagnostic collection yet."
        }
      }
    }
  end

  defp diagnostic_row_presentation(
         row,
         selected,
         mission_id,
         dashboard_id,
         collection,
         runtime_query
       ) do
    %{
      :id => row.id,
      "attrs" =>
        patch_attrs(
          diagnostic_path(mission_id, dashboard_id, collection, row.id, runtime_query),
          %{
            "data-diagnostic-id" => row.id,
            "class" => diagnostic_row_class(row, selected)
          }
        ),
      "header" => %{
        "attrs" => presentation_attrs(%{"class" => "flex items-start justify-between gap-2"})
      },
      "title" => %{
        "attrs" => presentation_attrs(%{"class" => "min-w-0 truncate text-sm font-medium"}),
        "text" => row.title
      },
      "status" => %{
        "attrs" => presentation_attrs(%{"class" => Enum.join(status_class(row.status), " ")}),
        "text" => row.status
      },
      "identity" => %{
        "attrs" =>
          presentation_attrs(%{
            "class" => "mt-1 truncate font-mono text-[0.63rem] text-base-content/45"
          }),
        "text" => row.identity
      }
    }
  end

  defp detail_presentation(nil, _scope, _mission_id, _dashboard_id, _runtime_query) do
    %{
      "attrs" =>
        presentation_attrs(%{
          "id" => "dashboard-diagnostic-detail",
          "class" => "min-w-0 p-5 lg:p-6"
        }),
      "selected" => nil,
      "empty" => %{
        "attrs" =>
          presentation_attrs(%{
            "class" => "flex min-h-64 items-center justify-center text-sm text-base-content/55"
          }),
        "text" => "Select a diagnostic record to inspect its evidence."
      }
    }
  end

  defp detail_presentation(selected, scope, mission_id, dashboard_id, runtime_query) do
    %{
      "attrs" =>
        presentation_attrs(%{
          "id" => "dashboard-diagnostic-detail",
          "class" => "min-w-0 p-5 lg:p-6"
        }),
      "selected" => %{
        "header" => %{
          "attrs" =>
            presentation_attrs(%{
              "class" => "flex flex-wrap items-start justify-between gap-3"
            }),
          "content" => %{"attrs" => %{}},
          "label" => %{
            "attrs" => presentation_attrs(%{"class" => "hud-label"}),
            "text" => "Diagnostic identity"
          },
          "title" => %{
            "attrs" => presentation_attrs(%{"class" => "mt-1 text-lg font-semibold"}),
            "text" => selected.title
          },
          "identity" => %{
            "attrs" =>
              presentation_attrs(%{
                "class" => "mt-1 break-all font-mono text-xs text-base-content/55"
              }),
            "text" => selected.identity
          },
          "copy" => %{
            "component" => "ClipboardButton",
            "host" => %{
              "attrs" =>
                presentation_attrs(%{
                  "id" => "dashboard-diagnostic-copy-identity-component",
                  "class" => "contents",
                  "data-name" => "ClipboardButton"
                })
            },
            "props" => %{
              "button_id" => "dashboard-diagnostic-copy-identity",
              "clipboard_text" => selected.identity,
              "button_class" => "btn btn-outline btn-xs",
              "icon" => "hero-clipboard",
              "icon_class" => "h-3.5 w-3.5",
              "label" => "Copy identity"
            }
          }
        },
        "details" => %{
          "attrs" =>
            presentation_attrs(%{
              "class" => "mt-5 grid gap-x-6 gap-y-3 border-t border-base-300 pt-5 sm:grid-cols-2"
            }),
          "items" => detail_items(selected.details)
        },
        "drilldowns" => drilldowns_presentation(scope, mission_id, dashboard_id, runtime_query)
      },
      "empty" => nil
    }
  end

  defp detail_items(details) do
    details
    |> Enum.with_index()
    |> Enum.map(fn {{key, value}, index} ->
      %{
        "key" => "#{index}-#{key}",
        "attrs" => presentation_attrs(%{"class" => "min-w-0"}),
        "label" => %{
          "attrs" =>
            presentation_attrs(%{
              "class" => "font-mono text-[0.62rem] uppercase tracking-wider text-base-content/45"
            }),
          "text" => detail_label(key)
        },
        "value" => %{
          "attrs" => presentation_attrs(%{"class" => "mt-1 break-words font-mono text-xs"}),
          "text" => detail_value(value)
        }
      }
    end)
  end

  defp drilldowns_presentation(scope, mission_id, dashboard_id, runtime_query) do
    dashboard_runtime_query = Map.put(runtime_query, "source_dashboard_id", dashboard_id)

    links = [
      drilldown_link(
        "diagnostics-open-explore",
        ~p"/missions/#{mission_id}/ops/explore?#{dashboard_runtime_query}",
        "Explore"
      ),
      drilldown_link(
        "diagnostics-open-sources",
        ~p"/missions/#{mission_id}/ops/data-sources?#{dashboard_runtime_query}",
        "Sources"
      ),
      drilldown_link(
        "diagnostics-open-catalog",
        ~p"/missions/#{mission_id}/catalog",
        "Catalog"
      )
    ]

    links =
      if platform_admin?(scope) do
        links ++
          [drilldown_link("diagnostics-open-admin-runtime", ~p"/admin/runtime", "Admin Runtime")]
      else
        links
      end

    %{
      "attrs" =>
        presentation_attrs(%{
          "class" => "mt-6 flex flex-wrap gap-2 border-t border-base-300 pt-4",
          "aria-label" => "Diagnostic drilldowns"
        }),
      "links" => links
    }
  end

  defp drilldown_link(id, href, text) do
    %{
      "key" => id,
      "attrs" =>
        navigate_attrs(href, %{
          "id" => id,
          "class" => "btn btn-outline btn-xs"
        }),
      "text" => text
    }
  end

  defp collection_class(collection, selected_collection) do
    base = "border-b-2 px-3 py-2 font-mono text-[0.65rem] uppercase tracking-wider"

    if collection == selected_collection do
      base <> " border-primary text-primary"
    else
      base <> " border-transparent text-base-content/50 hover:text-base-content"
    end
  end

  defp diagnostic_row_class(row, selected) do
    base = "block p-3 transition-colors hover:bg-base-200/50"

    if selected && selected.id == row.id do
      base <> " border-l-2 border-primary bg-primary/5"
    else
      base
    end
  end

  defp navigate_attrs(href, attrs) do
    %{
      "href" => href,
      "data-phx-link" => "redirect",
      "data-phx-link-state" => "push"
    }
    |> Map.merge(attrs)
    |> presentation_attrs()
  end

  defp patch_attrs(href, attrs) do
    %{
      "href" => href,
      "data-phx-link" => "patch",
      "data-phx-link-state" => "push"
    }
    |> Map.merge(attrs)
    |> presentation_attrs()
  end

  defp diagnostic_collections(scope, mission, document) do
    invalidations =
      DashboardRuntimeInvalidations.list(
        organization_id: scope.organization_id,
        mission_id: mission.mission_id,
        dashboard_id: document.dashboard_id,
        limit: 100
      )

    source_events =
      SourceHealth.list_source_health_events(
        scope.organization_id,
        mission.mission_id,
        limit: 100
      )

    %{
      "plan" => plan_rows(document),
      "requests" => request_rows(document),
      "frames" => frame_rows(document),
      "cache" => cache_rows(document),
      "source" => source_rows(source_events),
      "refresh" => decision_rows(invalidations, "refresh"),
      "invalidations" => decision_rows(invalidations, "invalidation")
    }
  end

  defp plan_rows(document) do
    document.placements
    |> Enum.map(fn placement ->
      row(
        "plan-#{placement.placement_id}",
        placement.widget_def.title || placement.placement_id,
        "planned",
        "#{document.dashboard_id}:#{placement.placement_id}",
        %{
          placement_id: placement.placement_id,
          widget_type: placement.widget_def.widget_type_id,
          binding: inspect(placement.widget_def.binding),
          layout: inspect(placement.layout)
        }
      )
    end)
  end

  defp request_rows(document) do
    document.placements
    |> Enum.map(fn placement ->
      row(
        "request-#{placement.placement_id}",
        "Source request · #{placement.widget_def.title || placement.placement_id}",
        "derived",
        "#{document.dashboard_id}:request:#{placement.placement_id}",
        %{
          placement_id: placement.placement_id,
          binding_source: inspect(placement.widget_def.binding),
          semantics: "Resolved by the production dashboard engine in Viewer/Editor"
        }
      )
    end)
  end

  defp frame_rows(document) do
    document.placements
    |> Enum.map(fn placement ->
      row(
        "frame-#{placement.placement_id}",
        "Frame contract · #{placement.widget_def.title || placement.placement_id}",
        "runtime",
        "#{document.dashboard_id}:frame:#{placement.placement_id}",
        %{
          placement_id: placement.placement_id,
          widget_type: placement.widget_def.widget_type_id,
          posture:
            "Frame payload is runtime-scoped and intentionally not copied into the document"
        }
      )
    end)
  end

  defp cache_rows(document) do
    [
      row(
        "cache-contract",
        "Runtime cache contract",
        "ephemeral",
        "#{document.dashboard_id}:cache",
        %{
          dashboard_version: Document.version(document),
          posture: "Live cache entries are inspected in the active Viewer runtime",
          persistence: "No cache payload is persisted as dashboard state"
        }
      )
    ]
  end

  defp source_rows(events) do
    Enum.map(events, fn event ->
      event_id =
        value(event, :source_health_event_id) || value(event, :event_id) || inspect(event)

      row(
        "source-#{event_id}",
        value(event, :status) |> value_text("Source posture"),
        value(event, :status) |> value_text("observed"),
        to_string(event_id),
        diagnostic_details(event)
      )
    end)
  end

  defp decision_rows(decisions, prefix) do
    decisions
    |> Enum.with_index()
    |> Enum.map(fn {decision, index} ->
      event_id = decision.invalidation_event_id || "#{prefix}-#{index}"

      row(
        "#{prefix}-#{event_id}",
        "#{collection_label(prefix)} · #{value_text(decision.boundary, "unknown boundary")}",
        value_text(decision.decision_status, "observed"),
        "#{decision.dashboard_id}:#{event_id}",
        Map.take(decision, [
          :boundary,
          :domain_fact,
          :decision_status,
          :matches?,
          :context_reason,
          :refresh_allowed?,
          :refresh_reason,
          :affected_placement_count,
          :affected_placement_ids,
          :invalidation_occurred_at,
          :decision_observed_at
        ])
      )
    end)
  end

  defp row(id, title, status, identity, details) do
    %{
      id: safe_id(id),
      title: to_string(title),
      status: to_string(status),
      identity: identity,
      details: details
    }
  end

  defp safe_id(id), do: id |> to_string() |> String.replace(~r/[^a-zA-Z0-9_-]/u, "-")

  defp normalize_collection(collection) when collection in @collections, do: collection
  defp normalize_collection(_collection), do: "plan"

  defp select_row(rows, nil), do: List.first(rows)
  defp select_row(rows, id), do: Enum.find(rows, &(&1.id == id)) || List.first(rows)

  defp diagnostic_path(mission_id, dashboard_id, collection, selected, runtime_query) do
    query =
      runtime_query
      |> Map.merge(%{"collection" => collection, "selected" => selected})
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    ~p"/missions/#{mission_id}/ops/dashboards/#{dashboard_id}/diagnostics?#{query}"
  end

  defp runtime_query(params) do
    params
    |> Map.take(@runtime_query_keys)
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp collection_label("plan"), do: "Plan"
  defp collection_label("requests"), do: "Requests"
  defp collection_label("frames"), do: "Frames"
  defp collection_label("cache"), do: "Cache"
  defp collection_label("source"), do: "Source execution"
  defp collection_label("refresh"), do: "Refresh"
  defp collection_label("invalidations"), do: "Invalidations"
  defp collection_label(value), do: value |> to_string() |> String.capitalize()

  defp status_class(status) do
    status = String.downcase(to_string(status))

    [
      "border px-1.5 py-0.5 font-mono text-[0.58rem] uppercase tracking-wider",
      if(status in ["error", "failed", "degraded", "blocked"],
        do: "border-error/40 text-error",
        else: "border-base-300 text-base-content/50"
      )
    ]
  end

  defp detail_label(key), do: key |> to_string() |> String.replace("_", " ")
  defp detail_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp detail_value(value) when is_binary(value), do: value
  defp detail_value(value), do: inspect(value, pretty: true, limit: 20)

  defp value(struct, field) when is_struct(struct), do: Map.get(struct, field)

  defp value(map, field) when is_map(map),
    do: Map.get(map, field) || Map.get(map, to_string(field))

  defp value(_value, _field), do: nil

  defp value_text(nil, fallback), do: fallback
  defp value_text(value, _fallback), do: to_string(value)

  defp diagnostic_details(event) when is_struct(event),
    do: event |> Map.from_struct() |> Map.drop([:__meta__])

  defp diagnostic_details(event) when is_map(event), do: Map.drop(event, [:__meta__])
  defp diagnostic_details(event), do: %{value: inspect(event)}

  defp platform_admin?(scope), do: MapSet.member?(scope.capabilities, :platform_admin)
end
