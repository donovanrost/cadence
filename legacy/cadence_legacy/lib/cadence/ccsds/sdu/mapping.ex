defmodule Cadence.CCSDS.SDU.Mapping do
  @moduledoc """
  Deterministic mapping from link context to SDU type.
  """

  alias Cadence.CCSDS.Core.Types

  @type key :: {
          Types.scid(),
          Types.vcid(),
          Types.map_id(),
          Types.direction()
        }

  @type sdu_type :: :space_packet | :encap | {:custom, String.t(), pos_integer()}

  @type t :: %__MODULE__{
          entries: %{key() => sdu_type()},
          default: sdu_type() | nil
        }

  defstruct entries: %{}, default: nil

  @spec new(map(), sdu_type() | nil) :: t()
  def new(entries \\ %{}, default \\ nil) when is_map(entries) do
    %__MODULE__{entries: entries, default: default}
  end

  @spec fetch(t(), Types.scid(), Types.vcid(), Types.map_id(), Types.direction()) ::
          {:ok, sdu_type()} | :error
  def fetch(%__MODULE__{} = mapping, scid, vcid, map_id, direction) do
    key = {scid, vcid, map_id, direction}

    case Map.fetch(mapping.entries, key) do
      {:ok, sdu_type} -> {:ok, sdu_type}
      :error -> fallback(mapping, scid, vcid, map_id, direction)
    end
  end

  defp fallback(mapping, scid, vcid, map_id, direction) do
    fallback_keys = [
      {scid, vcid, nil, direction},
      {scid, vcid, map_id, :downlink},
      {scid, vcid, nil, :downlink}
    ]

    case Enum.find_value(fallback_keys, fn key -> Map.get(mapping.entries, key) end) do
      nil -> if mapping.default, do: {:ok, mapping.default}, else: :error
      sdu_type -> {:ok, sdu_type}
    end
  end
end
