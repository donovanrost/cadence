defmodule Cadence.Reads.SpacecraftMetadata do
  @moduledoc """
  Typed accessors for spacecraft metadata fields that operator surfaces show
  before they become first-class (`plane`, `slot`, `norad_id`,
  `operational_phase`, `orbit.mean_anomaly_deg`).
  """

  @spec integer(map() | nil, binary()) :: integer() | nil
  def integer(metadata, key) do
    case Map.get(metadata || %{}, key) do
      value when is_integer(value) ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {integer, ""} -> integer
          _other -> nil
        end

      _other ->
        nil
    end
  end

  @spec string(map() | nil, binary()) :: binary() | nil
  def string(metadata, key) do
    case Map.get(metadata || %{}, key) do
      value when is_binary(value) -> value
      _other -> nil
    end
  end

  @spec phase_deg(map() | nil) :: number() | nil
  def phase_deg(%{"orbit" => %{"mean_anomaly_deg" => value}}) when is_number(value), do: value
  def phase_deg(_metadata), do: nil
end
