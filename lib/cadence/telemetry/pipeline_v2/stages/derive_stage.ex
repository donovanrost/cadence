defmodule Cadence.Telemetry.PipelineV2.Stages.DeriveStage do
  @moduledoc """
  Pipeline stage that computes derived telemetry items.

  Derived items are calculated from other telemetry values using
  expressions (e.g., TEMP_AVG = (TEMP1 + TEMP2) / 2).

  Also applies limit checking to produce final items_with_limits.

  ## Input

  PipelineEvent with:
  - `qualified_items` - Map of "PACKET.item" => converted_value

  ## Output

  PipelineEvent enriched with:
  - `all_items` - Map of all items (converted + derived)
  - `items_with_limits` - List of {name, value, limit_state} tuples

  ## Stateful Functions

  Derived items can use stateful functions that maintain state across
  evaluations:

  - `rolling_avg(x, window)` - Rolling average over last N samples
  - `rolling_min(x, window)` - Minimum over last N samples
  - `rolling_max(x, window)` - Maximum over last N samples
  - `stddev(x, window)` - Standard deviation over last N samples
  - `rate(x)` - Rate of change per second
  - `delta(x)` - Difference from previous value
  - `count()` - Packet counter
  - `elapsed()` - Seconds since first evaluation

  State is stored in the ProcessorState ETS table, scoped by mission_id
  and item name.

  ## Cross-Packet Dependencies

  Derived items may reference values from multiple packets. If required
  variables aren't available in the current packet, the derived item
  is skipped (handled gracefully by DerivedItems.compute/2).
  """

  use Cadence.Telemetry.PipelineV2.Stages.StageBehaviour

  alias Cadence.Telemetry.DerivedItems

  @impl true
  def stage_name, do: :derive

  @impl true
  def process(event, state) do
    %{qualified_items: qualified_items} = event
    mission_id = state.mission_id

    # Compute derived items using mission's runtime overlay
    all_items =
      case DerivedItems.compute(qualified_items, mission_id) do
        {:ok, items} ->
          items

        {:error, reason} ->
          Logger.warning("Derived items computation failed: #{inspect(reason)}")
          qualified_items
      end

    # Apply limit checking (TODO: implement actual limit checking)
    # For now, all items get :green status
    items_with_limits =
      Enum.map(all_items, fn {name, value} ->
        {name, value, :green}
      end)

    {:ok,
     %{
       event
       | all_items: all_items,
         items_with_limits: items_with_limits
     }}
  end
end
