defmodule Cadence.Dashboards.DataContextTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.DataContext

  test "normalizes data-management view aliases into the dashboard data context" do
    assert %DataContext{view: :all_revisions} =
             DataContext.from_map(%{data_management_view: :all_revisions})

    assert %DataContext{view: "as_recorded"} =
             DataContext.from_map(%{"selection_view" => "as_recorded"})

    assert %DataContext{view: "recomputed"} =
             DataContext.from_map(%{"data_view" => "recomputed"})
  end

  test "validates supported data-management views" do
    assert DataContext.validate(%DataContext{view: :canonical}) == []
    assert DataContext.validate(%DataContext{view: "all_revisions"}) == []

    assert DataContext.validate(%DataContext{view: :unknown_view}) == [:unsupported_data_view]
  end

  test "source-specific context can override the selected data-management view" do
    context =
      DataContext.from_map(%{
        view: :canonical,
        source_contexts: %{
          telemetry: %{view: :all_revisions},
          limits: %{selection_view: :as_recorded}
        }
      })

    assert DataContext.source_value(context, :telemetry, :view) == :all_revisions
    assert DataContext.source_value(context, :limits, :view) == :as_recorded
    assert DataContext.source_value(context, :events, :view) == :canonical
  end
end
