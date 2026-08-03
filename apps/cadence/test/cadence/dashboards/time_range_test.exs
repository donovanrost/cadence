defmodule Cadence.Dashboards.TimeRangeTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.TimeRange

  @now ~U[2026-08-01 17:00:00Z]

  describe "parse_bound/1" do
    test "parses now" do
      assert {:ok, :now} = TimeRange.parse_bound("now")
      assert {:ok, :now} = TimeRange.parse_bound("  now  ")
    end

    test "parses relative offsets for every unit" do
      assert {:ok, {:relative, -90}} = TimeRange.parse_bound("now-90s")
      assert {:ok, {:relative, -300}} = TimeRange.parse_bound("now-5m")
      assert {:ok, {:relative, -21_600}} = TimeRange.parse_bound("now-6h")
      assert {:ok, {:relative, -172_800}} = TimeRange.parse_bound("now-2d")
      assert {:ok, {:relative, -604_800}} = TimeRange.parse_bound("now-1w")
    end

    test "parses ISO-8601 datetimes with and without offset suffix" do
      assert {:ok, {:absolute, ~U[2026-08-01 10:00:00Z]}} =
               TimeRange.parse_bound("2026-08-01T10:00:00Z")

      assert {:ok, {:absolute, ~U[2026-08-01 10:00:00Z]}} =
               TimeRange.parse_bound("2026-08-01T10:00:00")
    end

    test "rejects invalid bounds" do
      assert :error = TimeRange.parse_bound("")
      assert :error = TimeRange.parse_bound("now+6h")
      assert :error = TimeRange.parse_bound("now-6x")
      assert :error = TimeRange.parse_bound("yesterday")
      assert :error = TimeRange.parse_bound(nil)
      assert :error = TimeRange.parse_bound(21_600)
    end
  end

  describe "resolve/3" do
    test "now-N/now resolves to a sliding window" do
      assert {:ok, {:sliding, 21_600}} = TimeRange.resolve("now-6h", "now", @now)
      assert {:ok, {:sliding, 300}} = TimeRange.resolve("now-5m", "now", @now)
    end

    test "caps sliding windows at 24 hours" do
      assert {:ok, {:sliding, 86_400}} = TimeRange.resolve("now-24h", "now", @now)
      assert {:error, :window_too_large} = TimeRange.resolve("now-25h", "now", @now)
      assert {:error, :window_too_large} = TimeRange.resolve("now-7d", "now", @now)
    end

    test "absolute bounds resolve to a frozen range" do
      assert {:ok, {:absolute, ~U[2026-08-01 10:00:00Z], ~U[2026-08-01 12:00:00Z]}} =
               TimeRange.resolve("2026-08-01T10:00:00Z", "2026-08-01T12:00:00Z", @now)
    end

    test "relative-but-not-sliding pairs freeze against now" do
      assert {:ok, {:absolute, ~U[2026-08-01 11:00:00Z], ~U[2026-08-01 14:00:00Z]}} =
               TimeRange.resolve("now-6h", "now-3h", @now)

      assert {:ok, {:absolute, ~U[2026-08-01 16:00:00Z], ~U[2026-08-01 17:00:00Z]}} =
               TimeRange.resolve("now-1h", "2026-08-01T17:00:00Z", @now)
    end

    test "rejects reversed or empty ranges" do
      assert {:error, :time_range_reversed} =
               TimeRange.resolve("2026-08-01T12:00:00Z", "2026-08-01T10:00:00Z", @now)

      assert {:error, :time_range_reversed} = TimeRange.resolve("now", "now", @now)
      assert {:error, :time_range_reversed} = TimeRange.resolve("now", "now-1h", @now)
    end

    test "rejects invalid bounds" do
      assert {:error, :invalid_time_bound} = TimeRange.resolve("nope", "now", @now)
      assert {:error, :invalid_time_bound} = TimeRange.resolve("now-1h", nil, @now)
    end
  end

  describe "label/2" do
    test "labels sliding windows" do
      assert TimeRange.label("now-5m", "now") == "Last 5 minutes"
      assert TimeRange.label("now-1h", "now") == "Last 1 hour"
      assert TimeRange.label("now-6h", "now") == "Last 6 hours"
      assert TimeRange.label("now-24h", "now") == "Last 24 hours"
      assert TimeRange.label("now-90s", "now") == "Last 90 seconds"
    end

    test "labels absolute ranges" do
      assert TimeRange.label("2026-08-01T10:00:00Z", "2026-08-01T12:00:00Z") ==
               "2026-08-01 10:00:00 to 2026-08-01 12:00:00 UTC"
    end

    test "returns nil for unresolvable pairs" do
      assert TimeRange.label(nil, nil) == nil
      assert TimeRange.label("nope", "now") == nil
    end
  end

  describe "shift/2" do
    test "moves the range by half its span" do
      range = {~U[2026-08-01 15:00:00Z], ~U[2026-08-01 19:00:00Z]}

      assert TimeRange.shift(range, :back) ==
               {~U[2026-08-01 13:00:00Z], ~U[2026-08-01 17:00:00Z]}

      assert TimeRange.shift(range, :forward) ==
               {~U[2026-08-01 17:00:00Z], ~U[2026-08-01 21:00:00Z]}
    end
  end

  describe "zoom_out/1" do
    test "doubles the span around the center" do
      assert TimeRange.zoom_out({~U[2026-08-01 16:00:00Z], ~U[2026-08-01 18:00:00Z]}) ==
               {~U[2026-08-01 15:00:00Z], ~U[2026-08-01 19:00:00Z]}
    end
  end

  describe "quick_ranges/0" do
    test "every quick range resolves to its sliding window" do
      for range <- TimeRange.quick_ranges() do
        assert {:ok, {:sliding, seconds}} = TimeRange.resolve(range.from, range.to, @now)
        assert seconds == range.seconds
        assert TimeRange.label(range.from, range.to) =~ "Last "
      end
    end

    test "quick_range/1 fetches by key" do
      assert {:ok, %{label: "Last 6 hours"}} = TimeRange.quick_range("last_6h")
      assert :error = TimeRange.quick_range("last_5y")
    end
  end
end
