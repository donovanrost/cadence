defmodule CadenceWeb.OpsDashboardShowLive.WidgetLifecyclePresentation do
  @moduledoc false

  alias Cadence.Dashboards.{Frame, FrameLifecycle, PlacementFrames}
  alias CadenceWeb.OpsDashboardShowLive.WidgetSourceStatus

  @spec put(map(), PlacementFrames.t(), Frame.t() | [Frame.t()] | nil, atom(), boolean()) :: map()
  def put(data, %PlacementFrames{} = placement_frames, frames, data_state, stale?)
      when is_map(data) do
    lifecycle =
      classify(%{
        warnings: placement_frames.warnings,
        warning_codes: frame_warning_codes(frames),
        data_state: data_state,
        stale?: stale?
      })

    data
    |> Map.put(:lifecycle, lifecycle)
    |> Map.put(:lifecycle_state, lifecycle.state)
    |> Map.put(:stale?, Map.get(data, :stale?, false) or lifecycle.state == :stale)
    |> Map.put(
      :source_status,
      WidgetSourceStatus.summarize(placement_frames, frames, data_state, stale?)
    )
  end

  @spec classify(map() | keyword()) :: FrameLifecycle.t()
  def classify(attrs), do: FrameLifecycle.classify(attrs)

  @spec state(FrameLifecycle.t() | map() | nil) :: atom() | nil
  def state(lifecycle), do: FrameLifecycle.state(lifecycle)

  @spec aggregate_row_data_state([map()]) :: :no_data | :ready
  def aggregate_row_data_state(rows) when is_list(rows) do
    if Enum.all?(rows, &(Map.get(&1, :normalized_state) == :no_data)), do: :no_data, else: :ready
  end

  @spec frame_warning_codes(Frame.t() | [Frame.t()] | nil) :: [atom()]
  def frame_warning_codes(frames) do
    frames
    |> List.wrap()
    |> Enum.flat_map(fn
      %Frame{meta: meta} when is_map(meta) ->
        meta
        |> context_value(:warning_codes)
        |> List.wrap()

      _frame ->
        []
    end)
    |> Enum.map(&normalize_warning_code/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp context_value(context, key) when is_map(context) and is_atom(key) do
    Map.get(context, key, Map.get(context, Atom.to_string(key)))
  end

  defp context_value(_context, _key), do: nil

  @spec normalize_warning_code(term()) :: atom() | nil
  def normalize_warning_code(code) when is_atom(code), do: code

  def normalize_warning_code(code) when is_binary(code) do
    code
    |> String.replace("-", "_")
    |> String.to_existing_atom()
  rescue
    ArgumentError -> nil
  end

  def normalize_warning_code(_code), do: nil
end
