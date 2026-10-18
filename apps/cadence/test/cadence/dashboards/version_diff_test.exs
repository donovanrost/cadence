defmodule Cadence.Dashboards.VersionDiffTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{Document, Placement, Section, VersionDiff, WidgetDef}

  defp widget(id, title, layout \\ %{x: 0, y: 0, w: 4, h: 2}) do
    %Placement{
      placement_id: id,
      layout: layout,
      widget_def: %WidgetDef{widget_type_id: :value_tile, title: title, options: %{precision: 2}}
    }
  end

  test "an unchanged document has no changes" do
    document = %Document{name: "Pass", placements: [widget("a", "Battery")]}
    assert VersionDiff.changes(document, document) == []
  end

  test "describes dashboard, section and widget changes in reading order" do
    before = %Document{
      name: "Pass",
      sections: [%Section{section_id: "s1", title: "Power"}],
      placements: [widget("a", "Battery"), widget("b", "Uptime"), widget("c", "Gone")]
    }

    after_ = %Document{
      name: "Pass review",
      sections: [
        %Section{section_id: "s1", title: "Power systems"},
        %Section{section_id: "s2", title: "Thermal"}
      ],
      placements: [
        widget("a", "Battery voltage"),
        widget("b", "Uptime", %{x: 4, y: 0, w: 4, h: 2}),
        widget("d", "Heater")
      ]
    }

    assert Enum.map(VersionDiff.changes(before, after_), &{&1.kind, &1.label, &1.detail}) == [
             {"changed", "Renamed dashboard", "Pass → Pass review"},
             {"added", "Added section “Thermal”", nil},
             {"changed", "Changed section “Power systems”", "Power → Power systems"},
             {"added", "Added widget “Heater”", "value tile"},
             {"removed", "Removed widget “Gone”", nil},
             {"changed", "Changed widget “Battery voltage”", "title Battery → Battery voltage"},
             {"changed", "Moved or resized 1 widget", nil}
           ]
  end
end
