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

  defp selected_datum_vue(html) do
    LiveVue.Test.get_vue(html, id: "dashboard-selected-datum-actions-component")
  end

  defp selected_datum_presentation(html) do
    html
    |> selected_datum_vue()
    |> Map.fetch!(:props)
    |> Map.fetch!("presentation")
  end

  defp selected_datum_action(html, id) do
    html
    |> selected_datum_presentation()
    |> find_selected_datum_node("id", id)
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
    vue = selected_datum_vue(unselected_live_html)

    assert document
           |> LazyHTML.query("#dashboard-selected-datum-actions-component")
           |> Enum.count() == 1

    assert document
           |> LazyHTML.query(
             "#dashboard-selected-datum-actions-component .cadence-dashboard-query-section"
           )
           |> Enum.empty?()

    assert vue.id == "dashboard-selected-datum-actions-component"
    assert vue.component == "DashboardSelectedDatumActions"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.slots == %{}
    assert Map.keys(vue.props) == ["presentation"]
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    presentation = vue.props["presentation"]
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
    document = LazyHTML.from_fragment(render_cluster([]))

    assert ["live"] =
             document
             |> LazyHTML.query("#dashboard-active-time-range")
             |> LazyHTML.attribute("data-dashboard-time-mode")

    assert document |> LazyHTML.query("#dashboard-active-time-range") |> LazyHTML.text() =~ "Live"

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-live-follow-indicator")
             |> LazyHTML.attribute("data-dashboard-live-follow")

    for id <- [
          "dashboard-time-shift-back",
          "dashboard-time-shift-forward",
          "dashboard-time-zoom-out"
        ] do
      assert [] = document |> LazyHTML.query("##{id}") |> LazyHTML.attribute("id")
    end

    assert [] =
             document
             |> LazyHTML.query("#dashboard-refresh-interval")
             |> LazyHTML.attribute("id")

    assert ["time"] =
             document
             |> LazyHTML.query("#dashboard-time-controls")
             |> LazyHTML.attribute("data-dashboard-primary-control")

    assert [""] =
             document
             |> LazyHTML.query("#dashboard-time-preset-live")
             |> LazyHTML.attribute("disabled")
  end

  test "sliding window labels the trigger and highlights the quick range" do
    document =
      LazyHTML.from_fragment(render_cluster(time_from: "now-6h", time_to: "now"))

    assert document |> LazyHTML.query("#dashboard-active-time-range") |> LazyHTML.text() =~
             "Last 6 hours"

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-time-preset-last-6h")
             |> LazyHTML.attribute("aria-current")

    assert ["false"] =
             document
             |> LazyHTML.query("#dashboard-time-preset-last-5m")
             |> LazyHTML.attribute("aria-current")

    for id <- [
          "dashboard-time-shift-back",
          "dashboard-time-shift-forward",
          "dashboard-time-zoom-out"
        ] do
      assert [] = document |> LazyHTML.query("##{id}") |> LazyHTML.attribute("disabled")
    end

    assert [] =
             document
             |> LazyHTML.query("#dashboard-time-preset-live")
             |> LazyHTML.attribute("disabled")
  end

  test "renders every quick range and filters by search query" do
    document = LazyHTML.from_fragment(render_cluster([]))

    assert document
           |> LazyHTML.query("#dashboard-time-presets button")
           |> LazyHTML.attribute("id")
           |> length() == 9

    filtered = LazyHTML.from_fragment(render_cluster(quick_query: "6 h"))

    assert ["dashboard-time-preset-last-6h"] =
             filtered
             |> LazyHTML.query("#dashboard-time-presets button")
             |> LazyHTML.attribute("id")
  end

  test "archive mode renders the time validation badge and range form values" do
    document =
      LazyHTML.from_fragment(
        render_cluster(
          time_mode: "archive",
          time_from: "2026-06-17T12:00:00Z",
          time_to: "2026-06-17T12:05:00Z",
          time_validation: "reset"
        )
      )

    assert ["reset"] =
             document
             |> LazyHTML.query("#dashboard-time-validation")
             |> LazyHTML.attribute("data-time-validation")

    assert ["false"] =
             document
             |> LazyHTML.query("#dashboard-live-follow-indicator")
             |> LazyHTML.attribute("data-dashboard-live-follow")

    assert ["2026-06-17T12:00:00Z"] =
             document |> LazyHTML.query("#dashboard-time-from") |> LazyHTML.attribute("value")

    assert ["2026-06-17T12:05:00Z"] =
             document |> LazyHTML.query("#dashboard-time-to") |> LazyHTML.attribute("value")
  end

  test "renders recently used ranges with an empty state fallback" do
    empty = LiveVue.Test.get_vue(render_cluster([]), id: "dashboard-time-recents")

    assert empty.component == "TimeRangeRecents"
    assert empty.id == "dashboard-time-recents"
    assert empty.ssr == false
    assert empty.class == "mt-3 border-t border-base-300/60 pt-2"
    assert empty.props["ranges"] == []
    assert empty.handlers["recents-loaded"] == JS.push("time_recents_loaded")
    assert empty.handlers["select-range"] == JS.push("set_chart_time_range")

    populated =
      LiveVue.Test.get_vue(
        render_cluster(
          recent_ranges: [
            %{from: "2026-06-17T12:00:00Z", to: "2026-06-17T12:05:00Z"}
          ]
        ),
        id: "dashboard-time-recents"
      )

    assert populated.props["ranges"] == [
             %{
               "from" => "2026-06-17T12:00:00Z",
               "to" => "2026-06-17T12:05:00Z",
               "label" => "2026-06-17 12:00:00 to 2026-06-17 12:05:00 UTC"
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

    assert ["replay-run-1"] =
             document
             |> LazyHTML.query("#dashboard-replay-run-selector option[selected]")
             |> LazyHTML.attribute("value")

    clock = LazyHTML.query(document, "#dashboard-replay-progress-clock")
    assert ["replay-run-1"] = LazyHTML.attribute(clock, "data-dashboard-replay-run-id")
    assert ["true"] = LazyHTML.attribute(clock, "data-dashboard-replay-run-known")
    assert ["completed"] = LazyHTML.attribute(clock, "data-dashboard-replay-run-status")

    assert ["2026-06-17T11:59:00Z"] =
             LazyHTML.attribute(clock, "data-dashboard-replay-run-started-at")

    assert ["42"] = LazyHTML.attribute(clock, "data-dashboard-replay-run-sample-count")

    assert ["2026-06-17T12:00:00Z"] =
             LazyHTML.attribute(clock, "data-dashboard-replay-window-from")

    assert ["true"] = LazyHTML.attribute(clock, "data-dashboard-replay-window-bounded")

    scrub = selected_datum_action(html, "dashboard-replay-scrub-to-selection")
    assert scrub["attrs"]["data-dashboard-replay-scrub-available"] == "true"
    refute Map.has_key?(scrub["attrs"], "disabled")

    assert [] =
             document
             |> LazyHTML.query("#dashboard-replay-metadata-warning")
             |> LazyHTML.attribute("id")

    assert document |> LazyHTML.query("#dashboard-active-time-range") |> LazyHTML.text() =~
             "Replay · replay-run-1"

    assert [] =
             document
             |> LazyHTML.query("#dashboard-time-shift-back")
             |> LazyHTML.attribute("id")
  end

  test "disables replay scrub when no timestamp is selected" do
    html =
      render_cluster(
        time_mode: "replay_run",
        replay_run_id: "replay-run-1",
        data_realm: "replay",
        data_view: "as_recorded"
      )

    document = LazyHTML.from_fragment(html)

    scrub = selected_datum_action(html, "dashboard-replay-scrub-to-selection")
    assert scrub["attrs"]["data-dashboard-replay-scrub-available"] == "false"
    assert scrub["attrs"]["disabled"] == ""

    assert ["false"] =
             document
             |> LazyHTML.query("#dashboard-replay-progress-clock")
             |> LazyHTML.attribute("data-dashboard-replay-window-bounded")
  end

  test "preserves unlisted replay deep links with metadata warning" do
    document =
      LazyHTML.from_fragment(
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
      )

    assert ["replay-run-unlisted"] =
             document
             |> LazyHTML.query("#dashboard-replay-run-selector option[selected]")
             |> LazyHTML.attribute("value")

    assert ["false"] =
             document
             |> LazyHTML.query("#dashboard-replay-progress-clock")
             |> LazyHTML.attribute("data-dashboard-replay-run-known")

    assert ["replay-run-unlisted"] =
             document
             |> LazyHTML.query("#dashboard-replay-metadata-warning")
             |> LazyHTML.attribute("data-dashboard-replay-run-id")
  end
end
