defmodule CadenceWeb.OpsDashboardShowLive.WidgetInspectModelTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.WidgetInspectModel

  @t0 1_700_000_000_000

  defp series(id, points, attrs \\ %{}) do
    Map.merge(%{id: id, label: id, unit: nil, points: points}, attrs)
  end

  describe "from_series/3" do
    test "merges misaligned series on the union of timestamps with blanks" do
      model =
        WidgetInspectModel.from_series("placement-1", "Trend", [
          series("volts", [[@t0, 1.0], [@t0 + 1_000, 2.0]], %{unit: "V"}),
          series("amps", [[@t0 + 1_000, 0.5], [@t0 + 2_000, 0.75]])
        ])

      assert model.row_count_total == 3
      refute model.capped?

      assert [
               %{timestamp_ms: t2, values: [nil, 0.75]},
               %{timestamp_ms: t1, values: [2.0, 0.5]},
               %{timestamp_ms: t0, values: [1.0, nil]}
             ] = model.rows

      assert {^t0, ^t2} = model.time_range
      assert t1 == @t0 + 1_000
      assert model.series == [%{label: "volts", unit: "V"}, %{label: "amps", unit: nil}]
    end

    test "skips non-numeric values and keeps point metadata out of the table" do
      model =
        WidgetInspectModel.from_series("placement-1", "Trend", [
          series("volts", [
            [@t0, 1.0, %{sample_id: "s-1"}],
            [@t0 + 1_000, nil],
            [@t0 + 2_000, "bad"]
          ])
        ])

      assert model.row_count_total == 1
      assert [%{timestamp_ms: @t0, values: [1.0]}] = model.rows
      assert [%{count: 1, min: 1.0, max: 1.0, mean: 1.0, last: 1.0}] = model.stats
    end

    test "caps displayed rows but reports the total" do
      points = for offset <- 0..599, do: [@t0 + offset * 1_000, offset * 1.0]

      model = WidgetInspectModel.from_series("placement-1", "Trend", [series("volts", points)])

      assert model.capped?
      assert model.row_count_total == 600
      assert length(model.rows) == WidgetInspectModel.max_table_rows()
      assert hd(model.rows).timestamp_ms == @t0 + 599 * 1_000
    end

    test "computes stats per series" do
      model =
        WidgetInspectModel.from_series("placement-1", "Trend", [
          series("volts", [[@t0, 1.0], [@t0 + 1_000, 3.0], [@t0 + 2_000, 2.0]], %{unit: "V"})
        ])

      assert [%{label: "volts", unit: "V", count: 3, min: 1.0, max: 3.0, mean: 2.0, last: 2.0}] =
               model.stats
    end

    test "empty series produce an empty model, not a crash" do
      model = WidgetInspectModel.from_series("placement-1", "Trend", [])

      assert model.rows == []
      assert model.row_count_total == 0
      assert model.time_range == nil
      assert model.csv == "time_utc"
    end
  end

  describe "csv" do
    test "renders the full dataset ascending with ISO times and unit-suffixed headers" do
      points = for offset <- 0..549, do: [@t0 + offset * 1_000, offset * 1.0]

      model =
        WidgetInspectModel.from_series("placement-1", "Trend", [
          series("volts", points, %{unit: "V"})
        ])

      lines = String.split(model.csv, "\r\n")
      assert hd(lines) == "time_utc,volts (V)"
      # full dataset, not the 500-row display cap
      assert length(lines) == 551
      assert Enum.at(lines, 1) == "2023-11-14T22:13:20.000Z,0.0"
    end

    test "quotes fields containing commas or quotes per RFC 4180" do
      model =
        WidgetInspectModel.from_series("placement-1", "Trend", [
          series("volts", [[@t0, 1.0]], %{label: ~s(bus "A", primary)})
        ])

      assert String.starts_with?(model.csv, ~s(time_utc,"bus ""A"", primary"))
    end

    test "blank cells for missing values" do
      model =
        WidgetInspectModel.from_series("placement-1", "Trend", [
          series("volts", [[@t0, 1.0]]),
          series("amps", [[@t0 + 1_000, 2.0]])
        ])

      [_header, row1, row2] = String.split(model.csv, "\r\n")
      assert row1 =~ ",1.0,"
      assert String.ends_with?(row1, "1.0,")
      assert String.ends_with?(row2, ",2.0")
    end
  end

  describe "build/3" do
    test "returns nil for other panels or missing placements" do
      assert WidgetInspectModel.build(:diagnostics, [], %{}) == nil
      assert WidgetInspectModel.build(nil, [], %{}) == nil

      assert WidgetInspectModel.build(
               {:widget_inspect, %{placement_id: "gone"}},
               [],
               %{}
             ) == nil
    end
  end
end
