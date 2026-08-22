defmodule CadenceSimulator.SequenceAllocator do
  @moduledoc """
  Lock-free CCSDS sequence allocator backed by Erlang `:atomics`.
  """

  @max_sequence 16_384
  @max_apids 256

  defstruct [:ref, :apid_to_slot]

  @type t :: %__MODULE__{
          ref: :atomics.atomics_ref(),
          apid_to_slot: %{non_neg_integer() => pos_integer()}
        }

  @spec new(list(non_neg_integer())) :: t()
  def new(apids \\ []) do
    %__MODULE__{
      ref: :atomics.new(@max_apids, signed: false),
      apid_to_slot: build_apid_mapping(apids)
    }
  end

  @spec next(t(), non_neg_integer()) :: non_neg_integer()
  def next(%__MODULE__{ref: ref, apid_to_slot: apid_to_slot}, apid) do
    slot = Map.get(apid_to_slot, apid, fallback_slot(apid))
    current = :atomics.add_get(ref, slot, 1)
    rem(current - 1, @max_sequence)
  end

  @spec peek(t(), non_neg_integer()) :: non_neg_integer()
  def peek(%__MODULE__{ref: ref, apid_to_slot: apid_to_slot}, apid) do
    slot = Map.get(apid_to_slot, apid, fallback_slot(apid))
    value = :atomics.get(ref, slot)
    rem(value, @max_sequence)
  end

  @spec reset(t(), non_neg_integer()) :: :ok
  def reset(%__MODULE__{ref: ref, apid_to_slot: apid_to_slot}, apid) do
    :atomics.put(ref, Map.get(apid_to_slot, apid, fallback_slot(apid)), 0)
    :ok
  end

  @spec reset_all(t()) :: :ok
  def reset_all(%__MODULE__{ref: ref}) do
    for slot <- 1..@max_apids do
      :atomics.put(ref, slot, 0)
    end

    :ok
  end

  defp build_apid_mapping(apids) do
    apids
    |> Enum.with_index(1)
    |> Map.new(fn {apid, slot} -> {apid, slot} end)
  end

  defp fallback_slot(apid) when apid >= 0 and apid < @max_apids, do: apid + 1
  defp fallback_slot(apid), do: rem(apid, @max_apids) + 1
end
