defmodule CadenceWeb.OpsDashboardShowLive.DashboardTimeReplayComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.SelectedDataRef

  attr(:time_mode, :string, required: true)
  attr(:time_axis, :string, default: "generation_time")
  attr(:time_from, :string, default: nil)
  attr(:time_to, :string, default: nil)
  attr(:replay_run_id, :string, default: nil)
  attr(:data_realm, :string, required: true)
  attr(:data_view, :string, required: true)
  attr(:compare_data_view, :string, default: nil)
  attr(:source_binding_id, :string, default: nil)
  attr(:limit_mode, :string, required: true)
  attr(:replay_runs, :list, default: [])
  attr(:selected_replay_run, :any, default: nil)

  def replay_section(assigns) do
    replay_form = to_form(replay_form_params(assigns))
    assigns = assign(assigns, :replay_presentation, replay_presentation(assigns, replay_form))

    ~H"""
    <.vue
      id="dashboard-time-replay-component"
      v-component="DashboardTimeReplay"
      presentation={@replay_presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  attr(:time_mode, :string, required: true)
  attr(:replay_run_id, :string, default: nil)
  attr(:selected_data_ref, :any, default: nil)

  def selected_datum_section(assigns) do
    assigns =
      assign(
        assigns,
        :selected_datum_presentation,
        selected_datum_presentation(
          assigns.time_mode,
          assigns.replay_run_id,
          assigns.selected_data_ref
        )
      )

    ~H"""
    <.vue
      id="dashboard-selected-datum-actions-component"
      v-component="DashboardSelectedDatumActions"
      presentation={@selected_datum_presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  defp selected_datum_presentation(time_mode, replay_run_id, selected_data_ref) do
    selected_datum_node(
      "selected-datum-root",
      "section",
      %{
        "class" => "cadence-dashboard-query-section",
        "aria-labelledby" => "dashboard-selection-time-heading"
      },
      [
        selected_datum_node(
          "selected-datum-heading",
          "p",
          %{
            "id" => "dashboard-selection-time-heading",
            "class" => "text-xs font-semibold text-base-content/85"
          },
          ["Selected datum"]
        ),
        selected_datum_node(
          "selected-datum-actions",
          "div",
          %{"class" => "mt-2 flex flex-wrap gap-1.5"},
          selected_datum_actions(time_mode, replay_run_id, selected_data_ref)
        )
      ]
    )
  end

  defp selected_datum_actions(time_mode, replay_run_id, selected_data_ref) do
    pause_action =
      selected_datum_action(
        "pause-at-selection",
        "dashboard-pause-at-selection",
        "pause_at_selected_time",
        not selected_timestamp?(selected_data_ref),
        "Pause dashboard time around the selected datum",
        "hero-pause",
        "Pause here"
      )

    replay_actions =
      if time_mode == "replay_run" do
        scrub_available? = replay_scrub_available?(replay_run_id, selected_data_ref)

        [
          selected_datum_action(
            "replay-scrub-to-selection",
            "dashboard-replay-scrub-to-selection",
            "scrub_replay_to_selection",
            not scrub_available?,
            "Move replay time around the selected datum",
            "hero-arrows-right-left",
            "Scrub here",
            %{
              "data-dashboard-replay-scrub-available" =>
                replay_scrub_available_text(replay_run_id, selected_data_ref)
            }
          )
        ]
      else
        []
      end

    clear_action =
      selected_datum_action(
        "clear-selection",
        "dashboard-clear-selection",
        "clear_data_selection",
        not SelectedDataRef.present?(selected_data_ref),
        "Clear the selected dashboard datum",
        "hero-x-mark",
        "Clear selection"
      )

    [pause_action] ++ replay_actions ++ [clear_action]
  end

  defp selected_datum_action(
         key,
         id,
         event,
         disabled?,
         title,
         icon,
         label,
         extra_attributes \\ %{}
       ) do
    attributes =
      Map.merge(
        %{
          "id" => id,
          "type" => "button",
          "class" => "btn btn-ghost btn-xs",
          "phx-click" => event,
          "disabled" => disabled?,
          "title" => title
        },
        extra_attributes
      )

    selected_datum_node(key, "button", attributes, [
      selected_datum_node("#{key}-icon", "span", %{"class" => "#{icon} h-3.5 w-3.5"}, []),
      " #{label}"
    ])
  end

  defp selected_datum_node(key, tag, attributes, children) do
    %{
      key: key,
      tag: tag,
      attrs: selected_datum_attributes(attributes),
      children: Enum.map(children, &selected_datum_child/1)
    }
  end

  defp selected_datum_child(%{tag: _tag} = node), do: node
  defp selected_datum_child(value), do: selected_datum_body(value)

  defp selected_datum_attributes(attributes) do
    Enum.reduce(attributes, %{}, fn
      {_key, value}, rendered when value in [nil, false] ->
        rendered

      {key, true}, rendered ->
        Map.put(rendered, to_string(key), "")

      {key, value}, rendered ->
        Map.put(rendered, to_string(key), selected_datum_body(value))
    end)
  end

  defp selected_datum_body(nil), do: ""
  defp selected_datum_body(value), do: to_string(value)

  defp replay_presentation(assigns, replay_form) do
    %{
      root: %{
        attrs: %{
          class: "cadence-dashboard-query-section",
          "aria-labelledby": "dashboard-replay-heading"
        }
      },
      heading: %{
        attrs: %{
          id: "dashboard-replay-heading",
          class: "text-xs font-semibold text-base-content/85"
        },
        text: "Replay"
      },
      body: %{
        class: "mt-2 grid gap-2 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-end",
        form: replay_form_dto(assigns, replay_form),
        clock: replay_clock_dto(assigns)
      },
      warning: replay_warning_dto(assigns)
    }
  end

  defp replay_form_dto(assigns, replay_form) do
    %{
      attrs: %{
        id: "runtime-replay-form",
        "phx-change": "set_runtime_context"
      },
      hidden_fields: [
        replay_hidden_field_dto(replay_form[:time_mode], "dashboard-replay-time-mode"),
        replay_hidden_field_dto(replay_form[:time_axis], "dashboard-replay-time-axis"),
        replay_hidden_field_dto(replay_form[:from], "dashboard-replay-from"),
        replay_hidden_field_dto(replay_form[:to], "dashboard-replay-to"),
        replay_hidden_field_dto(replay_form[:realm], "dashboard-replay-realm"),
        replay_hidden_field_dto(replay_form[:data_view], "dashboard-replay-data-view"),
        replay_hidden_field_dto(
          replay_form[:compare_data_view],
          "dashboard-replay-compare-data-view"
        ),
        replay_hidden_field_dto(replay_form[:limit_mode], "dashboard-replay-limit-mode"),
        replay_hidden_field_dto(
          replay_form[:source_binding_id],
          "dashboard-replay-source-binding"
        )
      ],
      replay_run:
        replay_select_field_dto(
          replay_form[:replay_run_id],
          replay_run_options(assigns.replay_runs, assigns.replay_run_id),
          assigns.replay_runs == [] and assigns.time_mode != "replay_run"
        )
    }
  end

  defp replay_hidden_field_dto(field, id) do
    %{
      wrapper_class: "fieldset",
      attrs: %{
        id: id,
        name: field.name,
        type: "hidden",
        value: field.value,
        required: false,
        disabled: false,
        class: "w-full input"
      }
    }
  end

  defp replay_select_field_dto(field, options, disabled?) do
    %{
      wrapper_class: "fieldset",
      label: %{
        class: "hud-label block mb-1.5",
        text: "Replay run"
      },
      attrs: %{
        id: "dashboard-replay-run-selector",
        name: field.name,
        required: false,
        multiple: false,
        disabled: disabled?,
        class: "w-full select select-xs font-mono"
      },
      options: Enum.map(options, &replay_select_option_dto(&1, field.value))
    }
  end

  defp replay_select_option_dto({label, value}, selected_value) do
    %{
      label: label,
      value: to_string(value),
      selected: to_string(selected_value) == to_string(value),
      disabled: false,
      title: nil
    }
  end

  defp replay_clock_dto(%{time_mode: "replay_run"} = assigns) do
    %{
      attrs: %{
        id: "dashboard-replay-progress-clock",
        "data-dashboard-replay-run-id": assigns.replay_run_id || "",
        "data-dashboard-replay-run-known": replay_run_known_text(assigns.selected_replay_run),
        "data-dashboard-replay-run-status": replay_run_attr(assigns.selected_replay_run, :status),
        "data-dashboard-replay-run-started-at":
          replay_run_datetime(assigns.selected_replay_run, :started_at),
        "data-dashboard-replay-run-completed-at":
          replay_run_datetime(assigns.selected_replay_run, :completed_at),
        "data-dashboard-replay-run-sample-count":
          replay_run_integer(assigns.selected_replay_run, :replayed_sample_count),
        "data-dashboard-replay-window-from": assigns.time_from || "",
        "data-dashboard-replay-window-to": assigns.time_to || "",
        "data-dashboard-replay-window-bounded":
          replay_window_bounded_text(assigns.time_from, assigns.time_to),
        class: "badge badge-info badge-outline badge-xs mb-1 max-w-64 truncate font-mono",
        title:
          replay_clock_title(
            assigns.selected_replay_run,
            assigns.replay_run_id,
            assigns.time_from,
            assigns.time_to
          )
      },
      text:
        replay_clock_label(
          assigns.selected_replay_run,
          assigns.replay_run_id,
          assigns.time_from,
          assigns.time_to
        )
    }
  end

  defp replay_clock_dto(_assigns), do: nil

  defp replay_warning_dto(%{
         time_mode: "replay_run",
         replay_run_id: replay_run_id,
         selected_replay_run: nil
       }) do
    if present_text?(replay_run_id) do
      %{
        attrs: %{
          id: "dashboard-replay-metadata-warning",
          "data-dashboard-replay-run-id": replay_run_id,
          class: "badge badge-warning badge-xs mt-2 max-w-64 truncate font-mono",
          title: "This replay run is not present in the persisted mission replay-run inventory."
        },
        icon_class: "hero-exclamation-triangle h-3 w-3",
        text: "Unlisted replay"
      }
    end
  end

  defp replay_warning_dto(_assigns), do: nil

  defp replay_form_params(assigns) do
    %{
      "time_mode" => "replay_run",
      "time_axis" => assigns.time_axis,
      "from" => assigns.time_from || "",
      "to" => assigns.time_to || "",
      "replay_run_id" => assigns.replay_run_id || "",
      "realm" => assigns.data_realm,
      "data_view" => assigns.data_view,
      "compare_data_view" => assigns.compare_data_view || "",
      "limit_mode" => assigns.limit_mode,
      "source_binding_id" => assigns.source_binding_id || ""
    }
  end

  defp selected_timestamp?(selected_data_ref),
    do: match?({:ok, _from_iso, _to_iso}, SelectedDataRef.archive_range(selected_data_ref))

  defp replay_clock_label(selected_replay_run, replay_run_id, from, to) do
    run_label = replay_run_label(selected_replay_run, replay_run_id)

    if replay_window_bounded?(from, to) do
      "#{run_label} / #{from} -> #{to}"
    else
      "#{run_label} / full run"
    end
  end

  defp replay_clock_title(selected_replay_run, replay_run_id, from, to) do
    run_label = replay_run_title(selected_replay_run, replay_run_id)

    if replay_window_bounded?(from, to) do
      "Replay #{run_label}, generation window #{from} to #{to}"
    else
      "Replay #{run_label}, full available run"
    end
  end

  defp replay_run_options(replay_runs, replay_run_id) do
    current_id = present_text(replay_run_id)

    options =
      replay_runs
      |> Enum.sort_by(&replay_run_sort_key/1)
      |> Enum.map(fn replay_run ->
        {replay_run_option_label(replay_run), replay_run_attr(replay_run, :replay_run_id)}
      end)

    options =
      if current_id && not Enum.any?(options, fn {_label, id} -> id == current_id end) do
        [{"Unlisted replay / #{current_id}", current_id} | options]
      else
        options
      end

    [{"Select replay run", ""} | options]
  end

  defp replay_run_option_label(replay_run) do
    replay_run
    |> replay_run_label(replay_run_attr(replay_run, :replay_run_id))
    |> then(fn label ->
      case replay_run_integer(replay_run, :replayed_sample_count) do
        "" -> label
        count -> "#{label} / #{count} samples"
      end
    end)
  end

  defp replay_run_label(nil, replay_run_id),
    do: present_text(replay_run_id) || "unselected replay"

  defp replay_run_label(replay_run, replay_run_id) do
    status = replay_run_attr(replay_run, :status)

    run_id =
      present_text(replay_run_attr(replay_run, :replay_run_id)) || present_text(replay_run_id)

    [status, run_id]
    |> Enum.filter(&present_text?/1)
    |> case do
      [] -> "unselected replay"
      parts -> Enum.join(parts, " ")
    end
  end

  defp replay_run_title(nil, replay_run_id) do
    present_text(replay_run_id) || "No replay run selected"
  end

  defp replay_run_title(replay_run, replay_run_id) do
    label = replay_run_label(replay_run, replay_run_id)
    started_at = replay_run_datetime(replay_run, :started_at)
    completed_at = replay_run_datetime(replay_run, :completed_at)

    cond do
      present_text?(started_at) and present_text?(completed_at) ->
        "#{label}, started #{started_at}, completed #{completed_at}"

      present_text?(started_at) ->
        "#{label}, started #{started_at}"

      true ->
        label
    end
  end

  defp replay_run_known_text(nil), do: "false"
  defp replay_run_known_text(_replay_run), do: "true"

  defp replay_run_attr(nil, _field), do: ""

  defp replay_run_attr(replay_run, field) when is_map(replay_run) do
    replay_run
    |> Map.get(field, Map.get(replay_run, Atom.to_string(field)))
    |> replay_run_value_text()
  end

  defp replay_run_datetime(replay_run, field) do
    case replay_run_value(replay_run, field) do
      %DateTime{} = datetime -> DateTime.to_iso8601(datetime)
      value -> replay_run_value_text(value)
    end
  end

  defp replay_run_integer(replay_run, field) do
    case replay_run_value(replay_run, field) do
      value when is_integer(value) -> Integer.to_string(value)
      value -> replay_run_value_text(value)
    end
  end

  defp replay_run_value(nil, _field), do: nil

  defp replay_run_value(replay_run, field) when is_map(replay_run) do
    Map.get(replay_run, field, Map.get(replay_run, Atom.to_string(field)))
  end

  defp replay_run_value_text(value) when is_atom(value), do: Atom.to_string(value)
  defp replay_run_value_text(value) when is_binary(value), do: value
  defp replay_run_value_text(value) when is_integer(value), do: Integer.to_string(value)
  defp replay_run_value_text(_value), do: ""

  defp replay_run_sort_key(replay_run) do
    started_at =
      case replay_run_value(replay_run, :started_at) do
        %DateTime{} = datetime -> DateTime.to_unix(datetime, :microsecond)
        _value -> 0
      end

    {-started_at, replay_run_attr(replay_run, :replay_run_id)}
  end

  defp replay_window_bounded?(from, to), do: present_text?(from) and present_text?(to)

  defp replay_window_bounded_text(from, to) do
    if replay_window_bounded?(from, to), do: "true", else: "false"
  end

  defp replay_scrub_available?(replay_run_id, selected_data_ref) do
    present_text?(replay_run_id) and selected_timestamp?(selected_data_ref)
  end

  defp replay_scrub_available_text(replay_run_id, selected_data_ref) do
    if replay_scrub_available?(replay_run_id, selected_data_ref), do: "true", else: "false"
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
