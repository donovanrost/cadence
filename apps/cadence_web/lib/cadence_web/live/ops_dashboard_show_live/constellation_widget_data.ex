defmodule CadenceWeb.OpsDashboardShowLive.ConstellationWidgetData do
  @moduledoc """
  Presenter for constellation health widgets.
  """

  alias Cadence.Dashboards.{Frame, PlacementFrames}
  alias CadenceWeb.OpsDashboardShowLive.WidgetLifecyclePresentation

  @spec data(PlacementFrames.t()) :: map() | nil
  def data(
        %PlacementFrames{
          primary: [
            %Frame{source: :operational_observables, shape: :matrix, fields: fields} = frame | _
          ]
        } = placement_frames
      ) do
    with %{values: spacecraft_ids} <- field_by_name(fields, "spacecraft_id"),
         %{values: worst_states} <- field_by_name(fields, "worst_state") do
      spacecraft =
        spacecraft_ids
        |> Enum.zip(worst_states)
        |> Enum.map(fn {spacecraft_id, worst_state} ->
          %{spacecraft_id: spacecraft_id, worst_state: worst_state}
        end)

      %{
        kind: :constellation,
        counts: Map.get(frame.meta, :counts, count_worst_states(spacecraft)),
        spacecraft: spacecraft,
        unresolved?: false,
        engine_backed?: true
      }
      |> WidgetLifecyclePresentation.put(placement_frames, frame, :ready, false)
    else
      _missing -> empty_data(placement_frames)
    end
  end

  def data(%PlacementFrames{} = placement_frames), do: empty_data(placement_frames)

  defp empty_data(%PlacementFrames{} = placement_frames) do
    %{
      kind: :constellation,
      counts: %{},
      spacecraft: [],
      stale?: false,
      unresolved?: false,
      engine_backed?: true
    }
    |> WidgetLifecyclePresentation.put(
      placement_frames,
      placement_frames.primary,
      :no_data,
      false
    )
  end

  defp count_worst_states(spacecraft) do
    spacecraft
    |> Enum.group_by(&(&1.worst_state || :no_data))
    |> Map.new(fn {state, entries} -> {state, length(entries)} end)
  end

  defp field_by_name(fields, name), do: Enum.find(fields, &(&1.name == name))
end
