defmodule Cadence.Dashboards.DashboardSectionTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.{Document, Placement, Section}

  test "sections round-trip in document order and validate placement membership" do
    document = %Document{
      dashboard_id: "dashboard-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      name: "Flight",
      sections: [
        %Section{
          section_id: "power",
          title: "Power",
          description: "Electrical health",
          collapsed_by_default?: true
        }
      ],
      placements: [%Placement{placement_id: "widget-1", section_id: "power"}]
    }

    round_tripped = document |> Document.to_map() |> Document.from_map()

    assert [%Section{section_id: "power", collapsed_by_default?: true}] = round_tripped.sections
    assert [%Placement{section_id: "power"}] = round_tripped.placements

    invalid = %Document{
      round_tripped
      | placements: [%Placement{placement_id: "widget-1", section_id: "missing"}]
    }

    assert Enum.any?(Document.validate(invalid).errors, &(&1.code == :unknown_dashboard_section))
  end

  test "removing a section preserves its widgets on the unsectioned canvas" do
    document = %Document{
      sections: [%Section{section_id: "power", title: "Power"}],
      placements: [%Placement{placement_id: "widget-1", section_id: "power"}]
    }

    assert %Document{sections: [], placements: [%Placement{section_id: nil}]} =
             Document.remove_section(document, "power")
  end

  test "sections can be reordered without changing their identity" do
    document = %Document{
      sections: [
        %Section{section_id: "power", title: "Power"},
        %Section{section_id: "comms", title: "Comms"}
      ]
    }

    assert [%Section{section_id: "comms"}, %Section{section_id: "power"}] =
             Document.move_section(document, "comms", :up).sections
  end
end
