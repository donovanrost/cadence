defmodule CadenceWeb.OpsDashboardShowLive.DashboardTimePickerComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.DashboardTimePickerComponents
  alias Phoenix.LiveView.JS

  defp render_cluster(overrides) do
    attrs =
      Keyword.merge(
        [
          time_mode: "live",
          time_axis: "generation_time",
          time_from: nil,
          time_to: nil,
          replay_run_id: nil,
          time_validation: "ok",
          data_realm: "flight",
          data_view: "canonical",
          compare_data_view: nil,
          source_binding_id: nil,
          limit_mode: "observed",
          replay_runs: [],
          selected_replay_run: nil,
          selected_data_ref: nil,
          quick_query: "",
          recent_ranges: []
        ],
        overrides
      )

    render_component(&DashboardTimePickerComponents.time_toolbar_cluster/1, attrs)
  end

  defp time_picker_vue(html) do
    LiveVue.Test.get_vue(html, id: "dashboard-time-picker-component")
  end

  defp time_picker_presentation(html) do
    html
    |> time_picker_vue()
    |> Map.fetch!(:props)
    |> Map.fetch!("presentation")
  end

  defp replay_presentation(html) do
    html
    |> time_picker_presentation()
    |> Map.fetch!("replay")
  end

  defp replay_control(presentation, id) do
    form = presentation["body"]["form"]

    Enum.find(
      form["hidden_fields"] ++ [form["replay_run"]],
      &(&1["attrs"]["id"] == id)
    )
  end

  defp replay_option(presentation, value) do
    presentation
    |> replay_control("dashboard-replay-run-selector")
    |> Map.fetch!("options")
    |> Enum.find(&(&1["value"] == value))
  end

  defp selected_datum_presentation(html) do
    html
    |> time_picker_presentation()
    |> Map.fetch!("selected_datum")
  end

  defp selected_datum_action(html, id) do
    html
    |> selected_datum_presentation()
    |> find_selected_datum_node("id", id)
  end

  defp quick_ranges_presentation(html) do
    html
    |> time_picker_presentation()
    |> get_in(["time_picker", "quick_ranges"])
  end

  defp quick_range_item(html, id) do
    html
    |> quick_ranges_presentation()
    |> get_in(["presets", "items"])
    |> Enum.find(&(&1["attrs"]["id"] == id))
  end

  defp absolute_range_props(html) do
    html
    |> time_picker_presentation()
    |> get_in(["time_picker", "absolute_range"])
  end

  defp find_selected_datum_node(%{"attrs" => attrs} = node, attribute, value) do
    if attrs[attribute] == value do
      node
    else
      Enum.find_value(node["children"], fn
        child when is_map(child) -> find_selected_datum_node(child, attribute, value)
        _text -> nil
      end)
    end
  end

  defp normalized_selected_datum_node?(%{
         "key" => key,
         "tag" => tag,
         "attrs" => attrs,
         "children" => children
       }) do
    is_binary(key) and
      is_binary(tag) and
      Enum.all?(attrs, fn {attribute, value} ->
        is_binary(attribute) and is_binary(value)
      end) and
      Enum.all?(children, fn
        child when is_binary(child) -> true
        child when is_map(child) -> normalized_selected_datum_node?(child)
        _child -> false
      end)
  end

  defp normalized_selected_datum_node?(_node), do: false

  test "selected datum action island preserves server-owned action presentation" do
    unselected_live_html = render_cluster([])
    document = LazyHTML.from_fragment(unselected_live_html)
    vue = time_picker_vue(unselected_live_html)

    assert document
           |> LazyHTML.query("#dashboard-time-picker-component")
           |> Enum.count() == 1

    assert document
           |> LazyHTML.query("#dashboard-time-picker-component .cadence-dashboard-query-section")
           |> Enum.empty?()

    assert vue.id == "dashboard-time-picker-component"
    assert vue.component == "DashboardTimePicker"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers["recents-loaded"] == JS.push("time_recents_loaded")
    assert vue.handlers["select-range"] == JS.push("set_chart_time_range")
    assert vue.slots == %{}
    assert Map.keys(vue.props) == ["presentation"]
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    presentation = vue.props["presentation"]["selected_datum"]
    assert normalized_selected_datum_node?(presentation)
    assert presentation["key"] == "selected-datum-root"
    assert presentation["tag"] == "section"

    assert presentation["attrs"] == %{
             "class" => "cadence-dashboard-query-section",
             "aria-labelledby" => "dashboard-selection-time-heading"
           }

    [heading, live_actions] = presentation["children"]

    assert heading == %{
             "key" => "selected-datum-heading",
             "tag" => "p",
             "attrs" => %{
               "id" => "dashboard-selection-time-heading",
               "class" => "text-xs font-semibold text-base-content/85"
             },
             "children" => ["Selected datum"]
           }

    assert live_actions["key"] == "selected-datum-actions"
    assert live_actions["tag"] == "div"
    assert live_actions["attrs"] == %{"class" => "mt-2 flex flex-wrap gap-1.5"}

    assert Enum.map(live_actions["children"], & &1["attrs"]["id"]) == [
             "dashboard-pause-at-selection",
             "dashboard-clear-selection"
           ]

    [pause, clear] = live_actions["children"]

    assert pause == %{
             "key" => "pause-at-selection",
             "tag" => "button",
             "attrs" => %{
               "id" => "dashboard-pause-at-selection",
               "type" => "button",
               "class" => "btn btn-ghost btn-xs",
               "phx-click" => "pause_at_selected_time",
               "disabled" => "",
               "title" => "Pause dashboard time around the selected datum"
             },
             "children" => [
               %{
                 "key" => "pause-at-selection-icon",
                 "tag" => "span",
                 "attrs" => %{"class" => "hero-pause h-3.5 w-3.5"},
                 "children" => []
               },
               " Pause here"
             ]
           }

    assert clear == %{
             "key" => "clear-selection",
             "tag" => "button",
             "attrs" => %{
               "id" => "dashboard-clear-selection",
               "type" => "button",
               "class" => "btn btn-ghost btn-xs",
               "phx-click" => "clear_data_selection",
               "disabled" => "",
               "title" => "Clear the selected dashboard datum"
             },
             "children" => [
               %{
                 "key" => "clear-selection-icon",
                 "tag" => "span",
                 "attrs" => %{"class" => "hero-x-mark h-3.5 w-3.5"},
                 "children" => []
               },
               " Clear selection"
             ]
           }

    selected_timestamp_ms = DateTime.to_unix(~U[2026-06-17 12:02:00Z], :millisecond)

    selected_live_html =
      render_cluster(selected_data_ref: %{"timestamp_ms" => selected_timestamp_ms})

    selected_pause = selected_datum_action(selected_live_html, "dashboard-pause-at-selection")
    selected_clear = selected_datum_action(selected_live_html, "dashboard-clear-selection")
    refute Map.has_key?(selected_pause["attrs"], "disabled")
    refute Map.has_key?(selected_clear["attrs"], "disabled")
    assert selected_pause["attrs"] == Map.delete(pause["attrs"], "disabled")
    assert selected_clear["attrs"] == Map.delete(clear["attrs"], "disabled")
    assert selected_pause["children"] == pause["children"]
    assert selected_clear["children"] == clear["children"]

    replay_unselected_html =
      render_cluster(time_mode: "replay_run", replay_run_id: "replay-run-1")

    replay_unselected = selected_datum_presentation(replay_unselected_html)
    [_heading, replay_unselected_actions] = replay_unselected["children"]

    assert Enum.map(replay_unselected_actions["children"], & &1["attrs"]["id"]) == [
             "dashboard-pause-at-selection",
             "dashboard-replay-scrub-to-selection",
             "dashboard-clear-selection"
           ]

    replay_unselected_scrub =
      selected_datum_action(replay_unselected_html, "dashboard-replay-scrub-to-selection")

    assert replay_unselected_scrub == %{
             "key" => "replay-scrub-to-selection",
             "tag" => "button",
             "attrs" => %{
               "id" => "dashboard-replay-scrub-to-selection",
               "type" => "button",
               "class" => "btn btn-ghost btn-xs",
               "phx-click" => "scrub_replay_to_selection",
               "disabled" => "",
               "data-dashboard-replay-scrub-available" => "false",
               "title" => "Move replay time around the selected datum"
             },
             "children" => [
               %{
                 "key" => "replay-scrub-to-selection-icon",
                 "tag" => "span",
                 "attrs" => %{"class" => "hero-arrows-right-left h-3.5 w-3.5"},
                 "children" => []
               },
               " Scrub here"
             ]
           }

    replay_selected_html =
      render_cluster(
        time_mode: "replay_run",
        replay_run_id: "replay-run-1",
        selected_data_ref: %{"timestamp_ms" => selected_timestamp_ms}
      )

    for id <- [
          "dashboard-pause-at-selection",
          "dashboard-replay-scrub-to-selection",
          "dashboard-clear-selection"
        ] do
      refute Map.has_key?(selected_datum_action(replay_selected_html, id)["attrs"], "disabled")
    end

    replay_selected_scrub =
      selected_datum_action(replay_selected_html, "dashboard-replay-scrub-to-selection")

    assert replay_selected_scrub["attrs"] == %{
             "id" => "dashboard-replay-scrub-to-selection",
             "type" => "button",
             "class" => "btn btn-ghost btn-xs",
             "phx-click" => "scrub_replay_to_selection",
             "data-dashboard-replay-scrub-available" => "true",
             "title" => "Move replay time around the selected datum"
           }

    present_without_timestamp_html =
      render_cluster(selected_data_ref: %{"target_id" => 7})

    assert selected_datum_action(present_without_timestamp_html, "dashboard-pause-at-selection")[
             "attrs"
           ]["disabled"] == ""

    refute Map.has_key?(
             selected_datum_action(present_without_timestamp_html, "dashboard-clear-selection")[
               "attrs"
             ],
             "disabled"
           )

    blank_replay_id_html =
      render_cluster(
        time_mode: "replay_run",
        replay_run_id: "  ",
        selected_data_ref: %{"timestamp_ms" => selected_timestamp_ms}
      )

    blank_replay_scrub =
      selected_datum_action(blank_replay_id_html, "dashboard-replay-scrub-to-selection")

    assert blank_replay_scrub["attrs"]["disabled"] == ""
    assert blank_replay_scrub["attrs"]["data-dashboard-replay-scrub-available"] == "false"
  end

  test "plain live mode renders Live without inactive time navigation" do
    html = render_cluster([])
    presentation = time_picker_presentation(html)
    overlay = presentation["overlay"]

    assert overlay["root"]["attrs"] == %{
             "id" => "dashboard-time-controls",
             "data-overlay-kind" => "popover",
             "data-overlay-placement" => "bottom-end",
             "class" => "cadence-overlay",
             "data-query-state" => "live",
             "data-dashboard-primary-control" => "time"
           }

    assert overlay["trigger"]["attrs"] == %{
             "id" => "dashboard-time-controls-toggle",
             "type" => "button",
             "data-overlay-trigger" => "",
             "aria-haspopup" => "dialog",
             "aria-expanded" => "false",
             "aria-controls" => "dashboard-time-controls-panel",
             "aria-label" => "Dashboard time range",
             "class" => "cadence-overlay-trigger cadence-dashboard-query-trigger"
           }

    assert overlay["trigger"]["live_indicator"]["attrs"] == %{
             "id" => "dashboard-live-follow-indicator",
             "class" => "cadence-dashboard-query-dot",
             "data-dashboard-live-follow" => "true",
             "aria-hidden" => "true"
           }

    assert overlay["trigger"]["active_range"]["attrs"] == %{
             "id" => "dashboard-active-time-range",
             "class" => "cadence-dashboard-query-trigger-value max-w-48",
             "data-dashboard-time-mode" => "live",
             "data-dashboard-time-summary" => "live"
           }

    assert overlay["trigger"]["active_range"]["text"] == "Live"

    assert overlay["trigger"]["icon_class"] ==
             "hero-chevron-down h-3 w-3 shrink-0 text-base-content/40"

    assert overlay["panel"]["attrs"] == %{
             "id" => "dashboard-time-controls-panel",
             "data-overlay-panel" => "",
             "data-overlay-width" => "lg",
             "aria-label" => "Dashboard time range",
             "class" => "cadence-overlay-panel cadence-popover-panel",
             "hidden" => true
           }

    assert overlay["panel"]["header"] == %{
             "class" => "cadence-dashboard-query-panel-header",
             "icon_class" => "hero-clock mt-0.5 h-4 w-4 text-primary",
             "title" => %{
               "class" => "text-xs font-semibold text-base-content/85",
               "text" => "Dashboard time"
             },
             "description" => %{
               "class" => "mt-0.5 text-[0.68rem] text-base-content/50",
               "text" => "Follow live telemetry, inspect history, or select a replay run."
             }
           }

    assert overlay["panel"]["body"] == %{
             "class" => "cadence-dashboard-query-panel-body",
             "controls" => %{
               "attrs" => %{
                 "id" => "dashboard-time-query-controls",
                 "data-dashboard-query-control-section" => "time",
                 "class" => "min-w-0"
               }
             }
           }

    assert presentation["shift_back"] == false
    assert presentation["shift_forward"] == false
    assert presentation["zoom_out"] == false

    assert presentation["time_picker"]["absolute_range_host"] == %{
             "attrs" => %{
               "id" => "dashboard-time-absolute-range-component",
               "class" => "contents"
             }
           }

    assert presentation["time_picker"]["quick_ranges_host"] == %{
             "attrs" => %{
               "id" => "dashboard-time-quick-ranges-component",
               "class" => "contents"
             }
           }

    assert presentation["replay_host"] == %{
             "attrs" => %{"id" => "dashboard-time-replay-component", "class" => "contents"}
           }

    assert presentation["selected_datum_host"] == %{
             "attrs" => %{
               "id" => "dashboard-selected-datum-actions-component",
               "class" => "contents"
             }
           }

    refute Map.has_key?(presentation, "refresh_interval")

    refute Map.has_key?(overlay["root"]["attrs"], "phx-hook")

    assert quick_range_item(html, "dashboard-time-preset-live")["attrs"]["disabled"]
  end

  test "sliding window labels the trigger and highlights the quick range" do
    html = render_cluster(time_from: "now-6h", time_to: "now")
    presentation = time_picker_presentation(html)

    assert presentation["overlay"]["trigger"]["active_range"]["text"] == "Last 6 hours"

    last_6h = quick_range_item(html, "dashboard-time-preset-last-6h")
    last_5m = quick_range_item(html, "dashboard-time-preset-last-5m")

    assert last_6h["attrs"]["aria-current"] == "true"

    assert last_6h["attrs"]["class"] ==
             "flex w-full items-center gap-1.5 px-2 py-1 text-left text-xs bg-primary/10 font-semibold text-primary"

    assert last_5m["attrs"]["aria-current"] == "false"

    assert last_5m["attrs"]["class"] ==
             "flex w-full items-center gap-1.5 px-2 py-1 text-left text-xs text-base-content/80 hover:bg-base-300/40 hover:text-base-content"

    assert presentation["shift_back"]["attrs"]["id"] == "dashboard-time-shift-back"
    assert presentation["shift_back"]["attrs"]["phx-click"] == "shift_time_range"
    assert presentation["shift_back"]["attrs"]["phx-value-direction"] == "back"
    assert presentation["shift_back"]["attrs"]["class"] == "btn btn-ghost btn-xs"

    assert presentation["shift_back"]["attrs"]["aria-label"] ==
             "Move time range backwards"

    assert presentation["shift_back"]["icon_class"] == "hero-chevron-left h-3.5 w-3.5"
    assert presentation["shift_forward"]["attrs"]["id"] == "dashboard-time-shift-forward"
    assert presentation["shift_forward"]["attrs"]["phx-value-direction"] == "forward"

    assert presentation["shift_forward"]["attrs"]["aria-label"] ==
             "Move time range forwards"

    assert presentation["shift_forward"]["icon_class"] == "hero-chevron-right h-3.5 w-3.5"
    assert presentation["zoom_out"]["attrs"]["id"] == "dashboard-time-zoom-out"
    assert presentation["zoom_out"]["attrs"]["phx-click"] == "zoom_out_time_range"
    assert presentation["zoom_out"]["attrs"]["aria-label"] == "Zoom out time range"

    assert presentation["zoom_out"]["icon_class"] ==
             "hero-magnifying-glass-minus h-3.5 w-3.5"

    refute quick_range_item(html, "dashboard-time-preset-live")["attrs"]["disabled"]
  end

  test "renders every quick range and filters by search query" do
    html = render_cluster([])
    document = LazyHTML.from_fragment(html)
    vue = time_picker_vue(html)

    assert document
           |> LazyHTML.query("#dashboard-time-picker-component")
           |> Enum.count() == 1

    assert document
           |> LazyHTML.query("#dashboard-time-picker-component #dashboard-time-presets")
           |> Enum.empty?()

    assert vue.id == "dashboard-time-picker-component"
    assert vue.component == "DashboardTimePicker"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers["recents-loaded"] == JS.push("time_recents_loaded")
    assert vue.handlers["select-range"] == JS.push("set_chart_time_range")
    assert vue.slots == %{}
    assert Map.keys(vue.props) == ["presentation"]
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    presentation = vue.props["presentation"]["time_picker"]["quick_ranges"]
    assert Map.keys(presentation) |> Enum.sort() == ["presets", "root", "search"]

    assert presentation["root"] == %{
             "attrs" => %{
               "class" => "w-44 shrink-0 border-l border-base-300/60 pl-3"
             }
           }

    assert presentation["search"] == %{
             "form" => %{
               "attrs" => %{
                 "id" => "dashboard-time-quick-search-form",
                 "phx-change" => "time_quick_search",
                 "onsubmit" => "return false"
               }
             },
             "field" => %{
               "wrapper_class" => "fieldset",
               "attrs" => %{
                 "id" => "dashboard-time-quick-search",
                 "name" => "query",
                 "type" => "search",
                 "value" => "",
                 "placeholder" => "Search quick ranges",
                 "required" => false,
                 "autocomplete" => nil,
                 "class" => "w-full input",
                 "phx-debounce" => "150"
               }
             }
           }

    presets = presentation["presets"]
    assert Map.keys(presets) |> Enum.sort() == ["attrs", "items"]

    assert presets["attrs"] == %{
             "id" => "dashboard-time-presets",
             "role" => "presentation",
             "aria-label" => "Quick time ranges",
             "class" => "mt-2 max-h-56 overflow-y-auto"
           }

    assert Enum.map(presets["items"], & &1["attrs"]["id"]) == [
             "dashboard-time-preset-live",
             "dashboard-time-preset-last-5m",
             "dashboard-time-preset-last-15m",
             "dashboard-time-preset-last-30m",
             "dashboard-time-preset-last-1h",
             "dashboard-time-preset-last-3h",
             "dashboard-time-preset-last-6h",
             "dashboard-time-preset-last-12h",
             "dashboard-time-preset-last-24h"
           ]

    assert Enum.all?(presets["items"], fn item ->
             Map.keys(item) |> Enum.sort() == ["attrs", "indicator_class", "key", "label"]
           end)

    assert Enum.all?(presets["items"], fn item ->
             Map.keys(item["attrs"]) |> Enum.sort() == [
               "aria-current",
               "class",
               "disabled",
               "id",
               "phx-click",
               "phx-value-preset",
               "title",
               "type"
             ]
           end)

    assert Enum.map(presets["items"], & &1["attrs"]["phx-click"])
           |> Enum.uniq() == ["set_time_preset"]

    assert Enum.map(presets["items"], & &1["attrs"]["phx-value-preset"]) == [
             "live",
             "last_5m",
             "last_15m",
             "last_30m",
             "last_1h",
             "last_3h",
             "last_6h",
             "last_12h",
             "last_24h"
           ]

    assert Enum.map(presets["items"], & &1["label"]) == [
             "Live",
             "Last 5 minutes",
             "Last 15 minutes",
             "Last 30 minutes",
             "Last 1 hour",
             "Last 3 hours",
             "Last 6 hours",
             "Last 12 hours",
             "Last 24 hours"
           ]

    assert Enum.map(presets["items"], & &1["attrs"]["title"]) == [
             "Return to live dashboard time",
             "Follow the last 5 minutes as a sliding window",
             "Follow the last 15 minutes as a sliding window",
             "Follow the last 30 minutes as a sliding window",
             "Follow the last 1 hour as a sliding window",
             "Follow the last 3 hours as a sliding window",
             "Follow the last 6 hours as a sliding window",
             "Follow the last 12 hours as a sliding window",
             "Follow the last 24 hours as a sliding window"
           ]

    assert Enum.all?(presets["items"], &(&1["attrs"]["type"] == "button"))

    assert Enum.map(presets["items"], & &1["attrs"]["disabled"]) ==
             [true, false, false, false, false, false, false, false, false]

    assert Enum.map(presets["items"], & &1["attrs"]["aria-current"]) ==
             ["true", "false", "false", "false", "false", "false", "false", "false", "false"]

    assert Enum.map(presets["items"], & &1["indicator_class"]) == [
             "h-1.5 w-1.5 rounded-full bg-success",
             nil,
             nil,
             nil,
             nil,
             nil,
             nil,
             nil,
             nil
           ]

    live = List.first(presets["items"])
    assert live["key"] == "dashboard-time-preset-live"
    assert live["label"] == "Live"
    assert live["indicator_class"] == "h-1.5 w-1.5 rounded-full bg-success"
    assert live["attrs"]["aria-current"] == "true"
    assert live["attrs"]["title"] == "Return to live dashboard time"

    filtered_html = render_cluster(quick_query: "6 h")
    filtered = quick_ranges_presentation(filtered_html)

    assert filtered["search"]["field"]["attrs"]["value"] == "6 h"

    assert Enum.map(filtered["presets"]["items"], & &1["attrs"]["id"]) == [
             "dashboard-time-preset-last-6h"
           ]

    assert quick_ranges_presentation(render_cluster(quick_query: "no matching range"))[
             "presets"
           ]["items"] == []
  end

  test "archive mode renders the time validation badge and range form values" do
    html =
      render_cluster(
        time_mode: "archive",
        time_from: "2026-06-17T12:00:00Z",
        time_to: "2026-06-17T12:05:00Z",
        time_validation: "reset"
      )

    document = LazyHTML.from_fragment(html)
    vue = time_picker_vue(html)
    presentation = vue.props["presentation"]
    props = presentation["time_picker"]["absolute_range"]

    assert document
           |> LazyHTML.query("#dashboard-time-picker-component")
           |> Enum.count() == 1

    assert document
           |> LazyHTML.query("#dashboard-time-picker-component #dashboard-custom-range-form")
           |> Enum.empty?()

    assert vue.id == "dashboard-time-picker-component"
    assert vue.component == "DashboardTimePicker"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers["recents-loaded"] == JS.push("time_recents_loaded")
    assert vue.handlers["select-range"] == JS.push("set_chart_time_range")
    assert vue.slots == %{}
    assert Map.keys(props) |> Enum.sort() == ["form", "heading", "recents", "root", "validation"]
    assert props == Jason.decode!(Jason.encode!(props))

    assert props["root"] == %{
             "attrs" => %{"class" => "min-w-0 flex-1"}
           }

    assert props["heading"] == %{
             "attrs" => %{
               "id" => "dashboard-range-heading",
               "class" => "text-xs font-semibold text-base-content/85"
             },
             "text" => "Absolute time range"
           }

    assert props["form"] == %{
             "attrs" => %{
               "id" => "dashboard-custom-range-form",
               "phx-submit" => "set_chart_time_range",
               "class" => "mt-2"
             },
             "from" => %{
               "wrapper_class" => "fieldset",
               "label" => %{
                 "class" => "hud-label block mb-1.5",
                 "text" => "From"
               },
               "attrs" => %{
                 "id" => "dashboard-time-from",
                 "name" => "from",
                 "type" => "text",
                 "value" => "2026-06-17T12:00:00Z",
                 "placeholder" => "now-6h or 2026-08-01T16:30:00Z",
                 "required" => false,
                 "autocomplete" => nil,
                 "class" => "w-full input input-xs font-mono"
               }
             },
             "to" => %{
               "margin_class" => "mt-2",
               "field" => %{
                 "wrapper_class" => "fieldset",
                 "label" => %{
                   "class" => "hud-label block mb-1.5",
                   "text" => "To"
                 },
                 "attrs" => %{
                   "id" => "dashboard-time-to",
                   "name" => "to",
                   "type" => "text",
                   "value" => "2026-06-17T12:05:00Z",
                   "placeholder" => "now",
                   "required" => false,
                   "autocomplete" => nil,
                   "class" => "w-full input input-xs font-mono"
                 }
               }
             },
             "submit" => %{
               "attrs" => %{
                 "id" => "dashboard-apply-time-range",
                 "type" => "submit",
                 "class" => "btn btn-primary btn-xs mt-2"
               },
               "text" => "Apply time range"
             }
           }

    assert props["validation"] == %{
             "attrs" => %{
               "id" => "dashboard-time-validation",
               "data-time-validation" => "reset",
               "class" => "badge badge-warning badge-xs mt-2"
             },
             "text" => "Time reset"
           }

    assert presentation["overlay"]["trigger"]["live_indicator"]["attrs"][
             "data-dashboard-live-follow"
           ] == "false"
  end

  test "renders recently used ranges with an empty state fallback" do
    html = render_cluster([])
    vue = time_picker_vue(html)
    empty = absolute_range_props(html)

    assert vue.component == "DashboardTimePicker"
    assert vue.id == "dashboard-time-picker-component"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert empty["validation"] == nil

    assert empty["recents"] == %{
             "attrs" => %{
               "id" => "dashboard-time-recents",
               "class" => "mt-3 border-t border-base-300/60 pt-2"
             },
             "ranges" => []
           }

    assert vue.handlers["recents-loaded"] == JS.push("time_recents_loaded")
    assert vue.handlers["select-range"] == JS.push("set_chart_time_range")

    populated =
      absolute_range_props(
        render_cluster(
          recent_ranges: [
            %{from: "2026-06-17T12:00:00Z", to: "2026-06-17T12:05:00Z"},
            %{from: "2026-06-17T13:00:00Z", to: "2026-06-17T14:00:00Z"}
          ]
        )
      )

    assert populated["recents"]["ranges"] == [
             %{
               "from" => "2026-06-17T12:00:00Z",
               "to" => "2026-06-17T12:05:00Z",
               "label" => "2026-06-17 12:00:00 to 2026-06-17 12:05:00 UTC"
             },
             %{
               "from" => "2026-06-17T13:00:00Z",
               "to" => "2026-06-17T14:00:00Z",
               "label" => "2026-06-17 13:00:00 to 2026-06-17 14:00:00 UTC"
             }
           ]
  end

  test "renders replay selector, progress clock, and scrub command" do
    selected_timestamp_ms = DateTime.to_unix(~U[2026-06-17 12:02:00Z], :millisecond)

    replay_run = %{
      replay_run_id: "replay-run-1",
      status: :completed,
      replayed_sample_count: 42,
      started_at: ~U[2026-06-17 11:59:00Z],
      completed_at: ~U[2026-06-17 12:06:00Z]
    }

    html =
      render_cluster(
        time_mode: "replay_run",
        time_from: "2026-06-17T12:00:00Z",
        time_to: "2026-06-17T12:05:00Z",
        replay_run_id: "replay-run-1",
        data_realm: "replay",
        data_view: "as_recorded",
        source_binding_id: "replay-binding",
        limit_mode: "current",
        replay_runs: [
          replay_run,
          %{
            replay_run_id: "replay-run-2",
            status: :running,
            replayed_sample_count: 7,
            started_at: ~U[2026-06-17 12:10:00Z],
            completed_at: nil
          }
        ],
        selected_replay_run: replay_run,
        selected_data_ref: %{"timestamp_ms" => selected_timestamp_ms}
      )

    document = LazyHTML.from_fragment(html)
    vue = time_picker_vue(html)

    assert document
           |> LazyHTML.query("#dashboard-time-picker-component")
           |> Enum.count() == 1

    assert document
           |> LazyHTML.query("#dashboard-time-picker-component .cadence-dashboard-query-section")
           |> Enum.empty?()

    assert vue.id == "dashboard-time-picker-component"
    assert vue.component == "DashboardTimePicker"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers["recents-loaded"] == JS.push("time_recents_loaded")
    assert vue.handlers["select-range"] == JS.push("set_chart_time_range")
    assert vue.slots == %{}
    assert Map.keys(vue.props) == ["presentation"]
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    time_picker_presentation = vue.props["presentation"]
    presentation = time_picker_presentation["replay"]

    assert presentation["root"] == %{
             "attrs" => %{
               "class" => "cadence-dashboard-query-section",
               "aria-labelledby" => "dashboard-replay-heading"
             }
           }

    assert presentation["heading"] == %{
             "attrs" => %{
               "id" => "dashboard-replay-heading",
               "class" => "text-xs font-semibold text-base-content/85"
             },
             "text" => "Replay"
           }

    assert presentation["body"]["class"] ==
             "mt-2 grid gap-2 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-end"

    form = presentation["body"]["form"]

    assert form["attrs"] == %{
             "id" => "runtime-replay-form",
             "phx-change" => "set_runtime_context"
           }

    assert form["hidden_fields"] == [
             %{
               "wrapper_class" => "fieldset",
               "attrs" => %{
                 "id" => "dashboard-replay-time-mode",
                 "name" => "time_mode",
                 "type" => "hidden",
                 "value" => "replay_run",
                 "required" => false,
                 "disabled" => false,
                 "class" => "w-full input"
               }
             },
             %{
               "wrapper_class" => "fieldset",
               "attrs" => %{
                 "id" => "dashboard-replay-time-axis",
                 "name" => "time_axis",
                 "type" => "hidden",
                 "value" => "generation_time",
                 "required" => false,
                 "disabled" => false,
                 "class" => "w-full input"
               }
             },
             %{
               "wrapper_class" => "fieldset",
               "attrs" => %{
                 "id" => "dashboard-replay-from",
                 "name" => "from",
                 "type" => "hidden",
                 "value" => "2026-06-17T12:00:00Z",
                 "required" => false,
                 "disabled" => false,
                 "class" => "w-full input"
               }
             },
             %{
               "wrapper_class" => "fieldset",
               "attrs" => %{
                 "id" => "dashboard-replay-to",
                 "name" => "to",
                 "type" => "hidden",
                 "value" => "2026-06-17T12:05:00Z",
                 "required" => false,
                 "disabled" => false,
                 "class" => "w-full input"
               }
             },
             %{
               "wrapper_class" => "fieldset",
               "attrs" => %{
                 "id" => "dashboard-replay-realm",
                 "name" => "realm",
                 "type" => "hidden",
                 "value" => "replay",
                 "required" => false,
                 "disabled" => false,
                 "class" => "w-full input"
               }
             },
             %{
               "wrapper_class" => "fieldset",
               "attrs" => %{
                 "id" => "dashboard-replay-data-view",
                 "name" => "data_view",
                 "type" => "hidden",
                 "value" => "as_recorded",
                 "required" => false,
                 "disabled" => false,
                 "class" => "w-full input"
               }
             },
             %{
               "wrapper_class" => "fieldset",
               "attrs" => %{
                 "id" => "dashboard-replay-compare-data-view",
                 "name" => "compare_data_view",
                 "type" => "hidden",
                 "value" => "",
                 "required" => false,
                 "disabled" => false,
                 "class" => "w-full input"
               }
             },
             %{
               "wrapper_class" => "fieldset",
               "attrs" => %{
                 "id" => "dashboard-replay-limit-mode",
                 "name" => "limit_mode",
                 "type" => "hidden",
                 "value" => "current",
                 "required" => false,
                 "disabled" => false,
                 "class" => "w-full input"
               }
             },
             %{
               "wrapper_class" => "fieldset",
               "attrs" => %{
                 "id" => "dashboard-replay-source-binding",
                 "name" => "source_binding_id",
                 "type" => "hidden",
                 "value" => "replay-binding",
                 "required" => false,
                 "disabled" => false,
                 "class" => "w-full input"
               }
             }
           ]

    assert form["replay_run"] == %{
             "wrapper_class" => "fieldset",
             "label" => %{
               "class" => "hud-label block mb-1.5",
               "text" => "Replay run"
             },
             "attrs" => %{
               "id" => "dashboard-replay-run-selector",
               "name" => "replay_run_id",
               "required" => false,
               "multiple" => false,
               "disabled" => false,
               "class" => "w-full select select-xs font-mono"
             },
             "options" => [
               %{
                 "label" => "Select replay run",
                 "value" => "",
                 "selected" => false,
                 "disabled" => false,
                 "title" => nil
               },
               %{
                 "label" => "running replay-run-2 / 7 samples",
                 "value" => "replay-run-2",
                 "selected" => false,
                 "disabled" => false,
                 "title" => nil
               },
               %{
                 "label" => "completed replay-run-1 / 42 samples",
                 "value" => "replay-run-1",
                 "selected" => true,
                 "disabled" => false,
                 "title" => nil
               }
             ]
           }

    assert replay_option(presentation, "replay-run-1")["selected"]

    clock = presentation["body"]["clock"]

    assert clock == %{
             "attrs" => %{
               "id" => "dashboard-replay-progress-clock",
               "data-dashboard-replay-run-id" => "replay-run-1",
               "data-dashboard-replay-run-known" => "true",
               "data-dashboard-replay-run-status" => "completed",
               "data-dashboard-replay-run-started-at" => "2026-06-17T11:59:00Z",
               "data-dashboard-replay-run-completed-at" => "2026-06-17T12:06:00Z",
               "data-dashboard-replay-run-sample-count" => "42",
               "data-dashboard-replay-window-from" => "2026-06-17T12:00:00Z",
               "data-dashboard-replay-window-to" => "2026-06-17T12:05:00Z",
               "data-dashboard-replay-window-bounded" => "true",
               "class" =>
                 "badge badge-info badge-outline badge-xs mb-1 max-w-64 truncate font-mono",
               "title" =>
                 "Replay completed replay-run-1, started 2026-06-17T11:59:00Z, completed 2026-06-17T12:06:00Z, generation window 2026-06-17T12:00:00Z to 2026-06-17T12:05:00Z"
             },
             "text" => "completed replay-run-1 / 2026-06-17T12:00:00Z -> 2026-06-17T12:05:00Z"
           }

    scrub = selected_datum_action(html, "dashboard-replay-scrub-to-selection")
    assert scrub["attrs"]["data-dashboard-replay-scrub-available"] == "true"
    refute Map.has_key?(scrub["attrs"], "disabled")

    assert presentation["warning"] == nil

    assert time_picker_presentation["overlay"]["trigger"]["active_range"]["text"] ==
             "Replay · replay-run-1"

    assert time_picker_presentation["shift_back"] == false
  end

  test "keeps inactive replay presentation disabled without runtime-only badges" do
    presentation = render_cluster([]) |> replay_presentation()
    replay_run = replay_control(presentation, "dashboard-replay-run-selector")

    assert replay_run["attrs"]["disabled"]

    assert replay_run["options"] == [
             %{
               "label" => "Select replay run",
               "value" => "",
               "selected" => true,
               "disabled" => false,
               "title" => nil
             }
           ]

    assert presentation["body"]["clock"] == nil
    assert presentation["warning"] == nil
  end

  test "disables replay scrub when no timestamp is selected" do
    html =
      render_cluster(
        time_mode: "replay_run",
        replay_run_id: "replay-run-1",
        data_realm: "replay",
        data_view: "as_recorded"
      )

    scrub = selected_datum_action(html, "dashboard-replay-scrub-to-selection")
    assert scrub["attrs"]["data-dashboard-replay-scrub-available"] == "false"
    assert scrub["attrs"]["disabled"] == ""

    clock_attrs = replay_presentation(html)["body"]["clock"]["attrs"]
    assert clock_attrs["data-dashboard-replay-window-bounded"] == "false"
  end

  test "preserves unlisted replay deep links with metadata warning" do
    html =
      render_cluster(
        time_mode: "replay_run",
        time_from: "2026-06-17T12:00:00Z",
        time_to: "2026-06-17T12:05:00Z",
        replay_run_id: "replay-run-unlisted",
        data_realm: "replay",
        data_view: "as_recorded",
        selected_data_ref: %{
          "timestamp_ms" => DateTime.to_unix(~U[2026-06-17 12:02:00Z], :millisecond)
        }
      )

    presentation = replay_presentation(html)

    assert replay_option(presentation, "replay-run-unlisted")["selected"]

    assert presentation["body"]["clock"]["attrs"]["data-dashboard-replay-run-known"] ==
             "false"

    assert presentation["warning"] == %{
             "attrs" => %{
               "id" => "dashboard-replay-metadata-warning",
               "data-dashboard-replay-run-id" => "replay-run-unlisted",
               "class" => "badge badge-warning badge-xs mt-2 max-w-64 truncate font-mono",
               "title" =>
                 "This replay run is not present in the persisted mission replay-run inventory."
             },
             "icon_class" => "hero-exclamation-triangle h-3 w-3",
             "text" => "Unlisted replay"
           }
  end
end
