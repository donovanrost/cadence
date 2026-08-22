defmodule CadenceWeb.OpsDashboardShowLive.ContextScopePolicyTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{Frame, PlacementFrames}
  alias CadenceWeb.OpsDashboardShowLive.ContextScopePolicy

  test "resolves legacy primary ids without a primary kind" do
    assert ContextScopePolicy.resolved?(%{
             primary: %{ids: ["spacecraft-alpha"]}
           })
  end

  test "resolves non-spacecraft typed scopes" do
    assert ContextScopePolicy.resolved?(%{transport_id: "transport-alpha"})
    assert ContextScopePolicy.resolved?(%{"contact_id" => "contact-alpha"})

    assert ContextScopePolicy.resolved?(%{
             primary: %{kind: :source_endpoint, ids: ["endpoint-alpha"]}
           })
  end

  test "resolves all-mode selectors for supported scope kinds" do
    assert ContextScopePolicy.resolved?(%{
             primary: %{kind: :mission, mode: :all, ids: []}
           })
  end

  test "does not resolve empty or unsupported scopes" do
    refute ContextScopePolicy.resolved?(nil)
    refute ContextScopePolicy.resolved?(%{})
    refute ContextScopePolicy.resolved?(%{primary: %{kind: :unknown, ids: ["id-1"]}})
  end

  test "resolves placement frames from their first primary frame scope" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          source: :operational_observables,
          shape: :matrix,
          scope: %{primary: %{kind: :ground_station, ids: ["gs-alpha"]}}
        }
      ]
    }

    assert ContextScopePolicy.resolved?(placement_frames)
  end
end
