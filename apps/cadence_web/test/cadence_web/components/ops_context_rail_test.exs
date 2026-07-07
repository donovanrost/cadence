defmodule CadenceWeb.Components.OpsContextRailTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.Components.OpsContextRail

  test "ops context rail renders stable section metadata and filters hidden sections" do
    html =
      render_component(&OpsContextRail.ops_context_rail/1,
        id: "test-context-rail",
        section: [
          section_slot("dashboard_health", "Dashboard health", :critical, 2, "Health body"),
          section_slot("source_status", "Source status", :warning, 1, "Source body"),
          section_slot("hidden", "Hidden", :info, 4, "Hidden body", visible: false)
        ]
      )

    document = LazyHTML.from_fragment(html)

    assert ["NavRail"] =
             document
             |> LazyHTML.query("#test-context-rail")
             |> LazyHTML.attribute("phx-hook")

    assert ["cadence-ops-context-rail"] =
             document
             |> LazyHTML.query("#test-context-rail")
             |> LazyHTML.attribute("data-storage-key")

    assert ["Toggle context panel"] =
             document
             |> LazyHTML.query("#test-context-rail-toggle")
             |> LazyHTML.attribute("aria-label")

    assert ["dashboard_health", "source_status"] =
             document
             |> LazyHTML.query("[data-ops-context-collapsed-section]")
             |> LazyHTML.attribute("data-ops-context-collapsed-section")

    assert ["critical"] =
             document
             |> LazyHTML.query(~s([data-ops-context-section="dashboard_health"]))
             |> LazyHTML.attribute("data-ops-context-section-status")

    assert ["2"] =
             document
             |> LazyHTML.query(~s([data-ops-context-section="dashboard_health"]))
             |> LazyHTML.attribute("data-ops-context-section-count")

    assert [] =
             document
             |> LazyHTML.query(~s([data-ops-context-section="hidden"]))
             |> LazyHTML.attribute("data-ops-context-section")
  end

  test "mission context rail derives fleet-health badge status and count" do
    html =
      render_component(&OpsContextRail.mission_context_rail/1,
        fleet_health: %{
          normalized_state_counts: %{red: 0, yellow: 2, blue: 1, green: 8},
          violating_points: 3
        }
      )

    document = LazyHTML.from_fragment(html)

    assert ["fleet_health"] =
             document
             |> LazyHTML.query("[data-ops-context-collapsed-section]")
             |> LazyHTML.attribute("data-ops-context-collapsed-section")

    assert ["warning"] =
             document
             |> LazyHTML.query(~s([data-ops-context-section="fleet_health"]))
             |> LazyHTML.attribute("data-ops-context-section-status")

    assert ["3"] =
             document
             |> LazyHTML.query(~s([data-ops-context-section="fleet_health"]))
             |> LazyHTML.attribute("data-ops-context-section-count")
  end

  defp section_slot(key, title, status, count, body, opts \\ []) do
    %{
      __slot__: :section,
      key: key,
      title: title,
      icon: "hero-squares-2x2",
      status: status,
      count: count,
      visible: Keyword.get(opts, :visible, true),
      inner_block: fn _changed, _arg -> slot_text(body) end
    }
  end

  defp slot_text(text) do
    assigns = %{text: text}

    ~H"{@text}"
  end
end
