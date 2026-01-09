defmodule Cadence.Telemetry.Derive do
  @moduledoc """
  Pure entry point for derived telemetry computation (without limits).
  """

  require Logger

  alias Cadence.Telemetry.DerivedItems

  def run(%{qualified_items: qualified_items} = _event, _state)
      when map_size(qualified_items) == 0 do
    {:skip, :no_items}
  end

  def run(%{qualified_items: qualified_items} = event, state) do
    mission_id = state.mission_id

    all_items =
      case state[:config_bundle] do
        %{derived_defs: defs, derived_packet_index: packet_index} ->
          case DerivedItems.compute_stateless_with_defs(
                 qualified_items,
                 defs,
                 packet_index,
                 mission_id
               ) do
            {:ok, items} -> items
            _ -> fallback_items(qualified_items)
          end

        _ ->
          case DerivedItems.compute_stateless(qualified_items, mission_id) do
            {:ok, items} -> items
            _ -> fallback_items(qualified_items)
          end
      end

    {:ok,
     %{
       event
       | all_items: all_items,
         items_with_limits: nil
     }}
  end

  def run(_event, _state), do: {:error, :invalid_event}

  defp fallback_items(qualified_items) do
    Logger.warning("Derived items computation failed, using qualified items")
    qualified_items
  end
end
