defmodule CadenceWeb.OpsTelemetryExploreComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias Cadence.Telemetry.SelectionPolicy
  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.JS

  @filter_fields ~w(
    point_id spacecraft_id scope_kind scope_id time_mode time_axis from to replay_run_id
    order limit selection_view validity_state realm logical_source data_source_id
    source_binding_id source_dashboard_id sample_id selected_time question limit_mode
  )a

  def page(assigns) do
    assigns = assign(assigns, :telemetry_explore_props, presentation_props(assigns))

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="ops-telemetry-explore-component"
        v-component="FederatedFullPageSurface"
        {@telemetry_explore_props}
        v-on:apply_filters={JS.push("apply_filters")}
        v-on:apply_question={JS.push("apply_question")}
        v-on:add_to_dashboard={JS.push("add_to_dashboard")}
        v-on:clear_selected_sample={JS.push("clear_selected_sample")}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end

  @doc false
  def presentation_props(assigns) do
    mission_id = assigns.current_mission.mission_id
    context = assigns.explore_context

    %{
      page:
        page_dto(
          context,
          assigns.source_context,
          assigns.selected_sample_state,
          assigns.history_diagnostics,
          assigns.samples
        ),
      clipboard: clipboard_dto(assigns.investigation_path),
      investigation:
        investigation_dto(assigns.investigation_path, assigns.investigation_fingerprint),
      navigation: navigation_dto(mission_id, context),
      questions: questions_dto(context),
      question_briefing: question_briefing_dto(mission_id, context),
      filter_form:
        filter_form_dto(
          assigns.filter_form,
          assigns.points,
          assigns.spacecraft,
          assigns.data_sources,
          assigns.data_bindings,
          assigns.data_realms,
          context
        ),
      point: point_dto(assigns.point, context.point_id),
      selected_sample: selected_sample_dto(assigns.selected_sample, mission_id, context),
      source_context:
        source_context_dto(assigns.source_context, assigns.samples, mission_id, context),
      context_rows: context_rows(context),
      diagnostics: diagnostics_dto(assigns.history_diagnostics),
      samples: Enum.map(assigns.samples, &sample_dto(&1, mission_id, context))
    }
    |> maybe_put_authoring(assigns, context)
  end

  defp page_dto(context, source_context, selected_sample_state, diagnostics, samples) do
    %{
      id: "ops-telemetry-explore-page",
      heading: "Telemetry Explore",
      point_label: context.point_id || "No point selected",
      realm: context.realm,
      time_mode: context.time_mode,
      source_state: source_context.state,
      data_source_id: source_context.data_source_id || "",
      source_binding_id: source_context.source_binding_id || "",
      logical_source: source_context.logical_source || "",
      source_realm: source_context.realm || "",
      selected_sample_state: selected_sample_state,
      selected_sample_id: context.sample_id || "",
      selected_sample_status:
        selected_sample_status_dto(selected_sample_state, context.sample_id),
      samples_summary: "#{length(samples)} rows, #{order_label(context.order)}",
      empty_samples_message: empty_samples_message(diagnostics)
    }
  end

  defp selected_sample_status_dto("missing", sample_id) do
    %{
      id: "telemetry-explore-selected-sample-status",
      state: "missing",
      sample_id: sample_id || "",
      icon: "hero-exclamation-triangle",
      heading: "Selected sample is outside the current result set"
    }
  end

  defp selected_sample_status_dto(_state, _sample_id), do: nil

  defp clipboard_dto(investigation_path) do
    %{
      button_id: "telemetry-explore-copy-link",
      text: investigation_path,
      class: "btn btn-ghost btn-sm",
      icon: "hero-link",
      icon_class: "h-4 w-4",
      label: "Copy link",
      copied_message: "Copied to clipboard",
      failed_message: "Copy failed"
    }
  end

  defp investigation_dto(path, fingerprint) do
    %{
      id: "telemetry-explore-investigation-summary",
      label: "Investigation",
      path: path,
      fingerprint: fingerprint
    }
  end

  defp navigation_dto(mission_id, context) do
    %{
      back_to_dashboard:
        if(context.source_dashboard_id,
          do: %{
            id: "telemetry-explore-back-to-dashboard",
            href: dashboard_path(mission_id, context.source_dashboard_id, context),
            label: "Dashboard",
            icon: "hero-arrow-left",
            class: "btn btn-ghost btn-sm"
          },
          else: nil
        )
    }
  end

  defp questions_dto(context) do
    Enum.map(investigation_questions(), fn question ->
      %{
        id: question.id,
        dom_id: "telemetry-explore-question-#{question.id}",
        label: question.label,
        description: question.description,
        icon: question.icon,
        active: context.question == question.id
      }
    end)
  end

  defp question_briefing_dto(mission_id, context) do
    case question_briefing(context.question) do
      nil ->
        nil

      briefing ->
        %{
          id: "telemetry-explore-question-briefing",
          question: context.question,
          label: question_label(context.question),
          text: briefing,
          actions: question_actions_dto(mission_id, context)
        }
    end
  end

  defp question_actions_dto(mission_id, context) do
    [
      %{
        id: "telemetry-explore-question-timeline",
        href: timeline_path(mission_id, context),
        label: "Timeline",
        icon: "hero-clock"
      },
      question_contacts_action(mission_id, context.question),
      question_data_operations_action(mission_id, context)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp question_contacts_action(mission_id, "link_degradation") do
    %{
      id: "telemetry-explore-question-contacts",
      href: ~p"/missions/#{mission_id}/ops/contacts",
      label: "Contacts",
      icon: "hero-signal"
    }
  end

  defp question_contacts_action(_mission_id, _question), do: nil

  defp question_data_operations_action(mission_id, %{question: "missing_history"} = context) do
    %{
      id: "telemetry-explore-question-data-operations",
      href: data_operations_path(mission_id, context),
      label: "Data Operations",
      icon: "hero-circle-stack"
    }
  end

  defp question_data_operations_action(_mission_id, _context), do: nil

  defp filter_form_dto(
         form,
         points,
         spacecraft,
         data_sources,
         data_bindings,
         data_realms,
         context
       ) do
    %{
      id: "telemetry-explore-filter-form",
      values: filter_values_dto(form),
      fields: %{
        point_id:
          select_field_dto(
            "explore_point_id",
            "explore[point_id]",
            "Point",
            point_options(points, context.point_id)
          ),
        spacecraft_id:
          select_field_dto(
            "explore_spacecraft_id",
            "explore[spacecraft_id]",
            "Spacecraft",
            spacecraft_options(spacecraft)
          ),
        time_mode:
          select_field_dto(
            "explore_time_mode",
            "explore[time_mode]",
            "Window",
            time_mode_options()
          ),
        from: text_field_dto("explore_from", "explore[from]", "From"),
        to: text_field_dto("explore_to", "explore[to]", "To"),
        order:
          select_field_dto(
            "explore_order",
            "explore[order]",
            "Order",
            order_options()
          ),
        limit: %{
          id: "explore_limit",
          name: "explore[limit]",
          type: "number",
          label: "Limit",
          min: "1",
          max: "1000"
        },
        realm:
          select_field_dto(
            "explore_realm",
            "explore[realm]",
            "Realm",
            realm_options(data_realms, data_bindings, context.realm)
          ),
        logical_source:
          select_field_dto(
            "explore_logical_source",
            "explore[logical_source]",
            "Logical Source",
            logical_source_options()
          ),
        data_source_id:
          select_field_dto(
            "explore_data_source_id",
            "explore[data_source_id]",
            "Data Source",
            data_source_options(data_sources, data_bindings, context)
          ),
        source_binding_id:
          select_field_dto(
            "explore_source_binding_id",
            "explore[source_binding_id]",
            "Source Binding",
            source_binding_options(data_bindings, context)
          ),
        selection_view:
          select_field_dto(
            "explore_selection_view",
            "explore[selection_view]",
            "Selection View",
            selection_view_options()
          ),
        validity_state:
          select_field_dto(
            "explore_validity_state",
            "explore[validity_state]",
            "Validity",
            validity_state_options()
          )
      },
      submit: %{
        id: "telemetry-explore-apply-filters",
        label: "Load",
        icon: "hero-arrow-path"
      }
    }
  end

  defp filter_values_dto(form) do
    Map.new(@filter_fields, fn field ->
      {Atom.to_string(field), form_string_value(form, field)}
    end)
  end

  defp form_string_value(form, field) do
    form
    |> Form.input_value(field)
    |> string_value()
  end

  defp text_field_dto(id, name, label) do
    %{id: id, name: name, type: "text", label: label}
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

  defp point_dto(nil, requested_point_id) do
    %{
      id: "telemetry-explore-point-card",
      requested_point_id: requested_point_id || "",
      rows: [row("Point", requested_point_id || "none")],
      missing: not is_nil(requested_point_id)
    }
  end

  defp point_dto(point, requested_point_id) do
    %{
      id: "telemetry-explore-point-card",
      requested_point_id: requested_point_id || "",
      rows:
        [
          row("Point", requested_point_id || "none"),
          row("Packet", point.packet_name),
          row("Field", point.field_name),
          row("Unit", point.unit),
          row("Description", point.description)
        ]
        |> Enum.reject(&is_nil/1),
      missing: false
    }
  end

  defp maybe_put_authoring(props, assigns, context) do
    if Map.get(assigns, :dashboard_author?, false) and not is_nil(assigns.point) do
      Map.put(props, :authoring, %{
        form:
          add_to_dashboard_form_dto(
            assigns.add_to_dashboard_form,
            assigns.ops_dashboards,
            context
          )
      })
    else
      props
    end
  end

  defp add_to_dashboard_form_dto(form, dashboards, context) do
    %{
      id: "telemetry-explore-add-to-dashboard-form",
      note: "no direct write",
      values: %{
        "dashboard_id" => form_string_value(form, :dashboard_id),
        "widget_type" => form_string_value(form, :widget_type),
        "title" => form_string_value(form, :title)
      },
      fields: %{
        dashboard_id:
          select_field_dto(
            "add_to_dashboard_dashboard_id",
            "add_to_dashboard[dashboard_id]",
            "Dashboard",
            dashboard_options(dashboards, context.source_dashboard_id)
          ),
        widget_type:
          select_field_dto(
            "add_to_dashboard_widget_type",
            "add_to_dashboard[widget_type]",
            "Visualization",
            [{"Time series", "time_series"}, {"Value tile", "value_tile"}]
          ),
        title: %{
          id: "add_to_dashboard_title",
          name: "add_to_dashboard[title]",
          type: "text",
          label: "Title",
          placeholder: default_widget_title(context.point_id)
        }
      },
      submit: %{
        id: "telemetry-explore-add-to-dashboard",
        label: "Open staged candidate",
        icon: "hero-plus"
      }
    }
  end

  defp selected_sample_dto(nil, _mission_id, _context), do: nil

  defp selected_sample_dto(sample, mission_id, context) do
    %{
      id: "telemetry-explore-selected-sample-card",
      sample_id: sample.sample_id,
      validity_state: validity_state_label(sample),
      rows: sample_provenance_rows(sample),
      clear: %{
        id: "telemetry-explore-clear-selected-sample",
        icon: "hero-x-mark",
        label: "Clear selected sample"
      },
      dashboard_link:
        case dashboard_sample_href(mission_id, context, sample) do
          nil ->
            nil

          href ->
            %{
              id: "telemetry-explore-open-selected-in-dashboard",
              href: href,
              label: "Open in dashboard",
              icon: "hero-arrow-top-right-on-square"
            }
        end
    }
  end

  defp source_context_dto(source_context, samples, mission_id, context) do
    %{
      id: "telemetry-explore-source-card",
      state: source_context.state,
      data_source_id: source_context.data_source_id || "",
      source_binding_id: source_context.source_binding_id || "",
      logical_source: source_context.logical_source || "",
      realm: source_context.realm || "",
      matched_data_source_id: source_context.matched_data_source_id || "",
      matched_source_binding_id: source_context.matched_source_binding_id || "",
      rows: source_context_rows(source_context, samples),
      actions: source_actions_dto(source_context, mission_id, context)
    }
  end

  defp source_actions_dto(source_context, mission_id, context) do
    [
      case source_detail_path(mission_id, source_context) do
        nil ->
          nil

        href ->
          %{
            id: "telemetry-explore-open-source",
            href: href,
            label: "Open source posture",
            icon: "hero-circle-stack"
          }
      end,
      if(context.source_dashboard_id,
        do: %{
          id: "telemetry-explore-open-dashboard-diagnostics",
          href:
            ~p"/missions/#{mission_id}/ops/dashboards/#{context.source_dashboard_id}/diagnostics",
          label: "Dashboard diagnostics",
          icon: "hero-wrench-screwdriver"
        },
        else: nil
      )
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp diagnostics_dto(diagnostics) do
    %{
      id: "telemetry-explore-diagnostics-card",
      rows: diagnostics_rows(diagnostics)
    }
  end

  defp sample_dto(sample, mission_id, context) do
    %{
      id: "telemetry-explore-sample-#{sample.sample_id}",
      sample_id: sample.sample_id,
      selected: sample.sample_id == context.sample_id,
      receipt_time: format_datetime(sample.receipt_time),
      generation_time: format_datetime(sample.generation_time),
      spacecraft_id: sample.spacecraft_id || "mission",
      engineering_value: format_value(sample.engineering_value),
      raw_value: format_value(sample.raw_value),
      quality_state: string_value(sample.quality_state),
      validity_state: validity_state_label(sample),
      source_ref: sample_source_ref(sample),
      evidence_id: sample.evidence_id || "",
      evidence_display: sample.evidence_id || "none",
      packet_id: sample.packet_id || "",
      packet_display: sample.packet_id || "none",
      packet_definition_id: sample.packet_definition_id || "",
      packet_definition_ref: packet_definition_ref(sample),
      dashboard_href: dashboard_sample_href(mission_id, context, sample)
    }
  end

  defp context_rows(context) do
    [
      row("Spacecraft", context.spacecraft_id),
      row("Scope kind", context.scope_kind),
      row("Scope", context.scope_id),
      row("Sample", context.sample_id),
      row("Selected time", context.selected_time),
      row("Mode", context.time_mode),
      row("Time axis", context.time_axis),
      row("From", context.from_text),
      row("To", context.to_text),
      row("Replay", context.replay_run_id),
      row("Order", context.order_text),
      row("Limit", context.limit_text),
      row("Selection", context.selection_view_text),
      row("Validity", context.validity_state_text),
      row("Realm", context.realm),
      row("Logical source", context.logical_source_text),
      row("Data source", context.data_source_id),
      row("Source binding", context.source_binding_id),
      row("Limit semantics", context.limit_mode)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp source_context_rows(source_context, samples) do
    [
      row("State", source_context.state),
      row("Requested realm", source_context.realm),
      row("Requested source", source_context.data_source_id),
      row("Requested binding", source_context.source_binding_id),
      row("Matched source", source_context.matched_data_source_id),
      row("Matched binding", source_context.matched_source_binding_id),
      row("Logical source", source_context.logical_source),
      row("Returned sources", returned_source_summary(samples))
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp diagnostics_rows(diagnostics) do
    [
      row("Requested", diagnostics.requested_logical_limit),
      row("Returned", diagnostics.logical_selected_count),
      row("Physical", diagnostics.physical_candidate_count),
      row("Candidate cap", diagnostics.physical_candidate_limit),
      row("Effective", diagnostics.effective_selection?),
      row("Exhausted", diagnostics.candidate_window_exhausted?),
      row("Physical exists", diagnostics.physical_samples_exist?),
      row("Error", diagnostics.error)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp empty_samples_message(%{physical_samples_exist?: true}) do
    "Physical samples exist, but none matched the current selection view or validity filter."
  end

  defp empty_samples_message(_diagnostics), do: "No physical samples matched this context."

  defp sample_provenance_rows(sample) do
    [
      row("Sample", sample.sample_id),
      row("Point", sample.point_id),
      row("Spacecraft", sample.spacecraft_id),
      row("Receipt", format_datetime(sample.receipt_time)),
      row("Generation", format_datetime(sample.generation_time)),
      row("Evidence", sample.evidence_id),
      row("Packet", sample.packet_id),
      row("Definition", packet_definition_ref(sample)),
      row("Quality", sample.quality_state),
      row("Validity", validity_state_label(sample)),
      row("Realm", storage_provenance_value(sample, "realm")),
      row("Data source", storage_provenance_value(sample, "data_source_id")),
      row("Source binding", storage_provenance_value(sample, "binding_id")),
      row("Identity", storage_provenance_value(sample, "observation_identity_id")),
      row("Observation", storage_provenance_value(sample, "observation_id")),
      row("Revision", storage_provenance_value(sample, "revision")),
      row("Decision", storage_provenance_value(sample, "decision_reason"))
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp row(_label, nil), do: nil
  defp row(_label, ""), do: nil
  defp row(label, value), do: %{label: label, value: format_value(value)}

  defp dashboard_path(mission_id, dashboard_id, context) do
    query =
      %{
        "spacecraft_id" => context.spacecraft_id,
        "scope_kind" => context.scope_kind,
        "scope_id" => context.scope_id,
        "time_mode" => dashboard_time_mode(context.time_mode),
        "time_axis" => context.time_axis,
        "from" => context.from_text,
        "to" => context.to_text,
        "replay_run_id" => context.replay_run_id,
        "realm" => context.realm,
        "data_view" => context.selection_view_text,
        "data_source_id" => context.data_source_id,
        "source_binding_id" => context.source_binding_id,
        "limit_mode" => context.limit_mode,
        "selected_target" => selected_target(context),
        "selected_id" => context.sample_id || context.point_id
      }
      |> compact_query()

    ~p"/missions/#{mission_id}/ops/dashboards/#{dashboard_id}?#{query}"
  end

  defp dashboard_time_mode("latest"), do: "live"
  defp dashboard_time_mode(mode), do: mode

  defp selected_target(%{sample_id: sample_id}) when is_binary(sample_id),
    do: "telemetry_sample"

  defp selected_target(%{point_id: point_id}) when is_binary(point_id), do: "telemetry_point"
  defp selected_target(_context), do: nil

  defp format_datetime(nil), do: "none"
  defp format_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp format_value(nil), do: "none"
  defp format_value(value) when is_boolean(value), do: to_string(value)
  defp format_value(value) when is_atom(value), do: Atom.to_string(value)
  defp format_value(value) when is_binary(value), do: value
  defp format_value(value) when is_integer(value), do: Integer.to_string(value)
  defp format_value(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 3)
  defp format_value(value), do: inspect(value)

  defp string_value(nil), do: ""
  defp string_value(value) when is_binary(value), do: value
  defp string_value(value) when is_atom(value), do: Atom.to_string(value)
  defp string_value(value), do: to_string(value)

  defp packet_definition_ref(sample) do
    case {sample.packet_definition_id, sample.packet_definition_version} do
      {nil, _version} -> "none"
      {definition_id, nil} -> definition_id
      {definition_id, version} -> "#{definition_id}@#{version}"
    end
  end

  defp validity_state_label(sample) do
    case SelectionPolicy.sample_validity_state(sample) do
      nil -> "canonical"
      state -> Atom.to_string(state)
    end
  end

  defp storage_provenance_value(sample, key) do
    sample.provenance
    |> ensure_map()
    |> map_value("storage")
    |> ensure_map()
    |> map_value(key)
    |> format_storage_value()
  end

  defp dashboard_sample_href(_mission_id, %{source_dashboard_id: nil}, _sample), do: nil

  defp dashboard_sample_href(mission_id, context, sample) do
    query =
      %{
        "selected_target" => "telemetry_sample",
        "selected_id" => sample.sample_id,
        "spacecraft_id" => context.spacecraft_id,
        "time_mode" => dashboard_time_mode(context.time_mode),
        "time_axis" => context.time_axis,
        "from" => context.from_text,
        "to" => context.to_text,
        "replay_run_id" => context.replay_run_id,
        "realm" => context.realm,
        "data_view" => context.selection_view_text,
        "data_source_id" => context.data_source_id,
        "source_binding_id" => context.source_binding_id,
        "scope_kind" => context.scope_kind,
        "scope_id" => context.scope_id,
        "limit_mode" => context.limit_mode
      }
      |> compact_query()

    ~p"/missions/#{mission_id}/ops/dashboards/#{context.source_dashboard_id}?#{query}"
  end

  defp ensure_map(map) when is_map(map), do: map
  defp ensure_map(_value), do: %{}

  defp map_value(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp map_value(map, key) when is_map(map), do: Map.get(map, key)

  defp format_storage_value(nil), do: nil
  defp format_storage_value(value), do: format_value(value)

  defp sample_source_ref(sample) do
    realm = storage_provenance_value(sample, "realm")
    data_source_id = storage_provenance_value(sample, "data_source_id")
    binding_id = storage_provenance_value(sample, "binding_id")

    [realm, data_source_id, binding_id]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> "unattributed"
      parts -> Enum.join(parts, " / ")
    end
  end

  defp returned_source_summary([]), do: nil

  defp returned_source_summary(samples) do
    samples
    |> Enum.map(&sample_source_ref/1)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {source, _count} -> source end)
    |> Enum.map_join(", ", fn {source, count} -> "#{source} x#{count}" end)
  end

  defp point_options(points, selected_point_id) do
    options = [{"Select a point", ""}] ++ Enum.map(points, &{&1.point_id, &1.point_id})

    if selected_point_id &&
         !Enum.any?(options, fn {_label, value} -> value == selected_point_id end) do
      options ++ [{selected_point_id, selected_point_id}]
    else
      options
    end
  end

  defp spacecraft_options(spacecraft) do
    [{"All spacecraft", ""}] ++
      Enum.map(spacecraft, &{&1.display_name, &1.spacecraft_id})
  end

  defp time_mode_options do
    [
      {"Latest", "latest"},
      {"Last 5 minutes", "last_5m"},
      {"Last 15 minutes", "last_15m"},
      {"Last hour", "last_1h"},
      {"Explicit range", "archive"},
      {"Replay run", "replay_run"}
    ]
  end

  defp order_options do
    [
      {"Newest first", "desc"},
      {"Oldest first", "asc"}
    ]
  end

  defp order_label(:asc), do: "oldest first"
  defp order_label(_order), do: "newest first"

  defp realm_options(data_realms, data_bindings, current_realm) do
    realms =
      (data_realms ++ Enum.map(data_bindings, &to_string(&1.realm)) ++ List.wrap(current_realm))
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.map(&to_string/1)
      |> Enum.uniq()
      |> Enum.sort()

    [{"Any realm", ""}] ++ Enum.map(realms, &{&1, &1})
  end

  defp logical_source_options do
    [
      {"Telemetry", "telemetry"},
      {"Limits", "limits"},
      {"Events", "events"},
      {"Operational observables", "operational_observables"}
    ]
  end

  defp investigation_questions do
    [
      %{
        id: "recent_anomalies",
        label: "What is anomalous?",
        description:
          "Inspect recent values alongside duplicate, conflict, and supersession evidence.",
        icon: "hero-exclamation-triangle"
      },
      %{
        id: "what_changed",
        label: "What changed?",
        description:
          "Compare the last hour across revisions and correlate changes with mission events.",
        icon: "hero-arrows-right-left"
      },
      %{
        id: "missing_history",
        label: "Why is history missing?",
        description:
          "Inspect physical-versus-selected reads, then continue into repair and source posture.",
        icon: "hero-magnifying-glass"
      },
      %{
        id: "link_degradation",
        label: "Is the link degrading?",
        description:
          "Correlate operational observables with contacts, transport facts, and the timeline.",
        icon: "hero-signal"
      }
    ]
  end

  defp question_label(question) do
    investigation_questions()
    |> Enum.find(&(&1.id == question))
    |> case do
      nil -> question
      preset -> preset.label
    end
  end

  defp question_briefing("recent_anomalies"),
    do:
      "All revisions are visible so identity conflicts cannot disappear behind the canonical sample."

  defp question_briefing("what_changed"),
    do:
      "The one-hour window and mission Timeline share enough context to correlate telemetry changes with operations."

  defp question_briefing("missing_history"),
    do:
      "Read diagnostics distinguish no physical samples from samples excluded by selection policy."

  defp question_briefing("link_degradation"),
    do:
      "Follow the same time window through operational observables, Contacts, and the canonical Timeline."

  defp question_briefing(_question), do: nil

  defp timeline_path(mission_id, context) do
    query =
      %{
        "return_to" => "explore",
        "source_dashboard_id" => context.source_dashboard_id,
        "spacecraft_id" => context.spacecraft_id,
        "scope_kind" => context.scope_kind,
        "scope_id" => context.scope_id,
        "time_mode" => context.time_mode,
        "time_axis" => context.time_axis,
        "from" => context.from_text,
        "to" => context.to_text,
        "replay_run_id" => context.replay_run_id,
        "realm" => context.realm,
        "data_view" => context.selection_view_text,
        "data_source_id" => context.data_source_id,
        "source_binding_id" => context.source_binding_id,
        "limit_mode" => context.limit_mode
      }
      |> compact_query()

    ~p"/missions/#{mission_id}/ops/timeline?#{query}"
  end

  defp data_operations_path(mission_id, context) do
    query =
      %{
        "dashboard_id" => context.source_dashboard_id,
        "point_id" => context.point_id,
        "point_ids" => context.point_id,
        "dashboard_time_mode" => context.time_mode,
        "dashboard_data_view" => context.selection_view_text,
        "dashboard_replay_run_id" => context.replay_run_id,
        "scope_kind" => context.scope_kind,
        "scope_id" => context.scope_id,
        "time_axis" => context.time_axis,
        "limit_mode" => context.limit_mode,
        "realm" => context.realm,
        "data_source_id" => context.data_source_id,
        "source_binding_id" => context.source_binding_id
      }
      |> compact_query()

    ~p"/missions/#{mission_id}/ops/data-operations?#{query}"
  end

  defp dashboard_options(dashboards, selected_dashboard_id) do
    options =
      dashboards
      |> Enum.filter(&(&1.lifecycle_state == "active"))
      |> Enum.map(&{&1.name, &1.dashboard_id})

    [{"Choose a dashboard", ""}] ++ ensure_option(options, selected_dashboard_id)
  end

  defp default_widget_title(nil), do: "Telemetry trend"

  defp default_widget_title(point_id) do
    point_id
    |> String.replace(["_", "."], " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp source_detail_path(mission_id, source_context) do
    source_id = source_context.matched_data_source_id || source_context.data_source_id

    if is_binary(source_id) do
      ~p"/missions/#{mission_id}/ops/data-sources/#{source_id}"
    end
  end

  defp data_source_options(data_sources, data_bindings, context) do
    allowed_ids =
      data_bindings
      |> Enum.filter(&binding_matches_context?(&1, context))
      |> Enum.map(& &1.data_source_id)
      |> MapSet.new()

    options =
      data_sources
      |> Enum.filter(fn source ->
        MapSet.size(allowed_ids) == 0 or MapSet.member?(allowed_ids, source.data_source_id)
      end)
      |> Enum.map(&{&1.data_source_id, &1.data_source_id})
      |> Enum.sort_by(fn {label, _value} -> label end)

    [{"Any data source", ""}] ++ ensure_option(options, context.data_source_id)
  end

  defp source_binding_options(data_bindings, context) do
    options =
      data_bindings
      |> Enum.filter(&binding_matches_context?(&1, context))
      |> Enum.map(&{binding_option_label(&1), &1.binding_id})
      |> Enum.sort_by(fn {label, _value} -> label end)

    [{"Any binding", ""}] ++ ensure_option(options, context.source_binding_id)
  end

  defp binding_matches_context?(binding, context) do
    normalize_string(binding.logical_source) == context.logical_source_text and
      matches_optional?(normalize_string(binding.realm), context.realm) and
      matches_optional?(binding.data_source_id, context.data_source_id)
  end

  defp matches_optional?(_value, nil), do: true
  defp matches_optional?(_value, ""), do: true
  defp matches_optional?(value, value), do: true
  defp matches_optional?(_value, _expected), do: false

  defp binding_option_label(binding) do
    "#{binding.binding_id} (#{binding.realm} / #{binding.data_source_id})"
  end

  defp normalize_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_string(value), do: to_string(value)

  defp ensure_option(options, nil), do: options
  defp ensure_option(options, ""), do: options

  defp ensure_option(options, selected) do
    if Enum.any?(options, fn {_label, value} -> value == selected end) do
      options
    else
      options ++ [{selected, selected}]
    end
  end

  defp selection_view_options do
    [
      {"Canonical", "canonical"},
      {"All revisions", "all_revisions"},
      {"As recorded", "as_recorded"},
      {"Recomputed", "recomputed"}
    ]
  end

  defp validity_state_options do
    [
      {"Any validity", ""},
      {"Canonical", "canonical"},
      {"Duplicate", "duplicate"},
      {"Conflict", "conflict"},
      {"Superseded", "superseded"},
      {"Advisory", "advisory"}
    ]
  end

  defp compact_query(query) do
    query
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
  end
end
