defmodule CadenceWeb.OpsDashboardShowLive.ConstellationWidgetDataTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{Field, Frame, PlacementFrames}
  alias CadenceWeb.OpsDashboardShowLive.ConstellationWidgetData

  test "renders constellation health with supplied counts" do
    placement_frames =
      constellation_frames(
        counts: %{green: 1, yellow: 1, red: 1},
        worst_states: [:green, :yellow, :red]
      )

    assert %{
             kind: :constellation,
             engine_backed?: true,
             lifecycle_state: :ready,
             counts: %{green: 1, yellow: 1, red: 1},
             spacecraft: [
               %{spacecraft_id: "sc-alpha", worst_state: :green},
               %{spacecraft_id: "sc-beta", worst_state: :yellow},
               %{spacecraft_id: "sc-gamma", worst_state: :red}
             ]
           } = ConstellationWidgetData.data(placement_frames)
  end

  test "derives constellation counts when the frame does not provide them" do
    placement_frames = constellation_frames()

    assert %{
             counts: %{green: 1, red: 1, no_data: 1}
           } = ConstellationWidgetData.data(placement_frames)
  end

  test "returns no-data contract for unsupported constellation frames" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          source: :operational_observables,
          shape: :matrix,
          fields: [
            %Field{name: "spacecraft_id", kind: :string, values: ["sc-alpha"]}
          ],
          meta: %{}
        }
      ]
    }

    assert %{
             kind: :constellation,
             counts: %{},
             spacecraft: [],
             lifecycle_state: :no_data,
             engine_backed?: true,
             unresolved?: false
           } = ConstellationWidgetData.data(placement_frames)
  end

  defp constellation_frames(opts \\ []) do
    worst_states = Keyword.get(opts, :worst_states, [:green, :red, nil])

    meta =
      opts
      |> Keyword.get(:counts)
      |> case do
        nil -> %{supported_capability: :constellation_health}
        counts -> %{supported_capability: :constellation_health, counts: counts}
      end

    %PlacementFrames{
      primary: [
        %Frame{
          source: :operational_observables,
          shape: :matrix,
          fields: [
            %Field{
              name: "spacecraft_id",
              kind: :string,
              values: ["sc-alpha", "sc-beta", "sc-gamma"]
            },
            %Field{name: "worst_state", kind: :enum, values: worst_states}
          ],
          meta: meta
        }
      ]
    }
  end
end
