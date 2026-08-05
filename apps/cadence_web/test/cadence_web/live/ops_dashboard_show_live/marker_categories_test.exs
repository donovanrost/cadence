defmodule CadenceWeb.OpsDashboardShowLive.MarkerCategoriesTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.MarkerCategories

  describe "normalize_param/1" do
    test "parses comma strings, dropping unknown keys and duplicates" do
      assert MarkerCategories.normalize_param("limits, contacts,limits,bogus") == ["limits"]
    end

    test "accepts lists and sorts them" do
      assert MarkerCategories.normalize_param(["watermarks", "contacts"]) == ["watermarks"]
    end

    test "accepts the checkbox map shape, treating false values as hidden" do
      assert MarkerCategories.normalize_param(%{
               "limits" => "false",
               "contacts" => "true",
               "mission_events" => "false",
               "bogus" => "false"
             }) == ["limits", "mission_events"]
    end

    test "unparseable input normalizes to no hidden categories" do
      assert MarkerCategories.normalize_param(nil) == []
      assert MarkerCategories.normalize_param(42) == []
      assert MarkerCategories.normalize_param("") == []
    end
  end

  describe "to_param/1" do
    test "empty list omits the param" do
      assert MarkerCategories.to_param([]) == nil
    end

    test "joins sorted valid keys" do
      assert MarkerCategories.to_param(["limits", "contacts"]) == "limits"
    end
  end

  describe "filter_limit_markers/2" do
    test "hides the whole stream when limits are hidden, even nil-typed markers" do
      markers = [%{marker_type: "limit_definition_interval"}, %{marker_type: nil}]

      assert MarkerCategories.filter_limit_markers(markers, ["limits"]) == []
      assert MarkerCategories.filter_limit_markers(markers, ["contacts"]) == markers
      assert MarkerCategories.filter_limit_markers(markers, []) == markers
    end
  end

  describe "filter_event_markers/2" do
    test "rejects markers whose type maps to a hidden category" do
      watermark = %{marker_type: "source_watermark_cursor"}
      mission = %{marker_type: "mission_event"}

      assert MarkerCategories.filter_event_markers([watermark, mission], ["watermarks"]) == [
               mission
             ]
    end

    test "keeps markers with unknown or missing types (fail open)" do
      unknown = %{marker_type: "future_marker"}
      untyped = %{marker_id: "x"}

      assert MarkerCategories.filter_event_markers([unknown, untyped], ["watermarks"]) ==
               [unknown, untyped]
    end

    test "no hidden categories is a passthrough" do
      markers = [%{marker_type: "mission_event"}]
      assert MarkerCategories.filter_event_markers(markers, []) == markers
    end
  end

  test "every emitted marker_type is covered by exactly one category" do
    emitted = [
      "limit_analysis",
      "limit_analysis_bucket",
      "limit_definition_interval",
      "source_binding_interval",
      "source_health_transition",
      "source_watermark_event",
      "source_watermark_cursor",
      "retention_gap",
      "mission_event",
      "telemetry_backfill_lifecycle",
      "telemetry_revision_range",
      "telemetry_revision_decision"
    ]

    for type <- emitted do
      hidden_by =
        Enum.filter(MarkerCategories.category_keys(), fn key ->
          MarkerCategories.filter_event_markers([%{marker_type: type}], [key]) == []
        end)

      assert length(hidden_by) == 1, "#{type} hidden by #{inspect(hidden_by)}"
    end
  end
end
