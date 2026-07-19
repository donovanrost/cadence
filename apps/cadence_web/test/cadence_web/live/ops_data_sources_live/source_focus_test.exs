defmodule CadenceWeb.OpsDataSourcesLive.SourceFocusTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DataBinding, DataSource}
  alias CadenceWeb.OpsDataSourcesLive.SourceFocus

  describe "from_params/1" do
    test "returns the default focus when the URL has no focus criteria" do
      assert SourceFocus.from_params(%{}) == SourceFocus.default()
      assert SourceFocus.from_params(%{"data_source_id" => "  "}) == SourceFocus.default()
    end

    test "normalizes requested focus values" do
      focus =
        SourceFocus.from_params(%{
          "data_source_id" => " source-1 ",
          "source_binding_id" => " binding-1 ",
          "logical_source" => " telemetry ",
          "realm" => " rehearsal ",
          "source_dashboard_id" => " dashboard-1 "
        })

      assert focus.state == "pending"
      assert focus.data_source_id == "source-1"
      assert focus.source_binding_id == "binding-1"
      assert focus.logical_source == "telemetry"
      assert focus.realm == "rehearsal"
      assert focus.source_dashboard_id == "dashboard-1"
    end
  end

  describe "resolve/3" do
    test "matches an explicit source and binding" do
      source = data_source("source-1")
      binding = data_binding("binding-1", "source-1")

      focus =
        SourceFocus.from_params(%{
          "data_source_id" => source.data_source_id,
          "source_binding_id" => binding.binding_id,
          "logical_source" => "telemetry",
          "realm" => "rehearsal"
        })

      resolved = SourceFocus.resolve(focus, [source], [binding])

      assert resolved.state == "matched"
      assert resolved.matched_data_source_id == source.data_source_id
      assert resolved.matched_source_binding_id == binding.binding_id
      assert SourceFocus.source_focused?(resolved, %{data_source_id: source.data_source_id})
      assert SourceFocus.binding_focused?(resolved, %{binding: binding})
      assert SourceFocus.title(resolved) == "Source evidence matched"
      assert SourceFocus.icon(resolved) == "hero-arrow-top-right-on-square"
    end

    test "finds inventory by logical source and realm context" do
      source = data_source("source-1")
      binding = data_binding("binding-1", "source-1")

      focus =
        SourceFocus.from_params(%{
          "logical_source" => "telemetry",
          "realm" => "rehearsal"
        })

      assert %{
               state: "matched",
               matched_data_source_id: "source-1",
               matched_source_binding_id: "binding-1"
             } = SourceFocus.resolve(focus, [source], [binding])
    end

    test "marks stale inventory identifiers as missing" do
      focus =
        SourceFocus.from_params(%{
          "data_source_id" => "retired-source",
          "source_binding_id" => "retired-binding"
        })

      resolved = SourceFocus.resolve(focus, [data_source("source-1")], [])

      assert resolved.state == "missing"
      refute SourceFocus.source_focused?(resolved, data_source("source-1"))
      assert SourceFocus.title(resolved) == "Source evidence no longer matches current inventory"
      assert SourceFocus.icon(resolved) == "hero-exclamation-triangle"
    end
  end

  defp data_source(data_source_id) do
    %DataSource{data_source_id: data_source_id}
  end

  defp data_binding(binding_id, data_source_id) do
    %DataBinding{
      binding_id: binding_id,
      data_source_id: data_source_id,
      logical_source: :telemetry,
      realm: :rehearsal
    }
  end
end
