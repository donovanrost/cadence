defmodule Cadence.Dashboards.DashboardActionTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.DashboardAction

  test "declares non-evidence dashboard action targets separately from data links" do
    assert DashboardAction.target?(:telemetry_explore)
    assert DashboardAction.target?(:source_inventory)
    assert DashboardAction.target?(:source_health)
    assert DashboardAction.target?(:dashboard_editor)
    assert DashboardAction.target?(:command)

    refute DashboardAction.target?(:telemetry_sample)
    refute DashboardAction.target?(:raw_evidence)
  end

  test "declares action execution and presentation vocabularies" do
    assert DashboardAction.kind?(:navigate)
    assert DashboardAction.kind?(:new_tab)
    assert DashboardAction.kind?(:invoke)

    assert DashboardAction.presentation?(:button)
    assert DashboardAction.source?(:evidence_panel)
    assert DashboardAction.source?(:data_link_panel)
    assert DashboardAction.source?(:frame)
    assert DashboardAction.source?(:field)
  end

  test "normalizes persisted or serialized action maps into typed actions" do
    assert %DashboardAction{
             action_id: "telemetry-explore:req-1",
             label: "Explore telemetry",
             message: "Open telemetry explorer",
             target: :telemetry_explore,
             kind: :invoke,
             route: nil,
             query: %{"point_id" => "HK.counter"},
             context: %{"source_request_id" => "req-1"},
             presentation: :button,
             source: :warning
           } =
             DashboardAction.normalize(%{
               "action_id" => "telemetry-explore:req-1",
               "label" => "Explore telemetry",
               "message" => "Open telemetry explorer",
               "target" => "telemetry-explore",
               "kind" => "invoke",
               "query" => %{"point_id" => "HK.counter"},
               "context" => %{"source_request_id" => "req-1"},
               "presentation" => "button",
               "source" => "warning"
             })
  end

  test "normalizes only valid action values from lists" do
    action = %DashboardAction{action_id: "source", target: :source_health, kind: :invoke}

    assert [
             ^action,
             %DashboardAction{
               action_id: "inventory",
               target: :source_inventory,
               kind: :navigate,
               presentation: :menu_item,
               source: :frame
             }
           ] =
             DashboardAction.normalize_many([
               action,
               %{
                 action_id: "inventory",
                 target: :source_inventory,
                 kind: "navigate",
                 presentation: "menu_item",
                 source: "frame"
               },
               "not an action"
             ])
  end
end
