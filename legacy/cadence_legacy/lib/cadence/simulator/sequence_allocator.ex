defmodule Cadence.Simulator.SequenceAllocator do
  @moduledoc """
  Lock-free sequence number allocator for CCSDS packets using Erlang :atomics.

  Provides atomic, contention-free sequence number allocation for parallel
  packet generators. Each APID gets its own slot in the atomics reference,
  allowing multiple workers to encode packets simultaneously without locking.

  ## CCSDS Sequence Numbers

  CCSDS packets use a 14-bit sequence counter (0-16383) that wraps around.
  Each APID maintains its own sequence, incrementing with each packet.

  ## Usage

      # Create allocator with known APIDs
      allocator = SequenceAllocator.new([100, 101, 102])

      # Atomically get next sequence (lock-free)
      seq = SequenceAllocator.next(allocator, 100)  # => 0
      seq = SequenceAllocator.next(allocator, 100)  # => 1

      # Works from multiple processes without coordination
      Task.async(fn -> SequenceAllocator.next(allocator, 100) end)
      Task.async(fn -> SequenceAllocator.next(allocator, 100) end)
  """

  @max_sequence 16_384
  @max_apids 256

  defstruct [:ref, :apid_to_slot]

  @type t :: %__MODULE__{
          ref: :atomics.atomics_ref(),
          apid_to_slot: %{non_neg_integer() => pos_integer()}
        }

  @doc """
  Creates a new sequence allocator.

  ## Options

  - `apids` - List of APIDs to pre-allocate slots for (optional).
    Unknown APIDs will be assigned slots dynamically based on their value.

  ## Examples

      # Pre-allocate for known APIDs
      allocator = SequenceAllocator.new([100, 101, 102])

      # Or create without pre-allocation
      allocator = SequenceAllocator.new()
  """
  @spec new(list(non_neg_integer())) :: t()
  def new(apids \\ []) do
    ref = :atomics.new(@max_apids, signed: false)
    apid_to_slot = build_apid_mapping(apids)

    %__MODULE__{
      ref: ref,
      apid_to_slot: apid_to_slot
    }
  end

  @doc """
  Atomically allocates and returns the next sequence number for an APID.

  This is lock-free and safe to call from multiple processes concurrently.
  Sequence numbers wrap at 16384 (14-bit CCSDS limit).

  ## Examples

      seq = SequenceAllocator.next(allocator, 100)  # => 0
      seq = SequenceAllocator.next(allocator, 100)  # => 1
      # ... after 16383 ...
      seq = SequenceAllocator.next(allocator, 100)  # => 0  (wrapped)
  """
  @spec next(t(), non_neg_integer()) :: non_neg_integer()
  def next(%__MODULE__{ref: ref, apid_to_slot: apid_to_slot}, apid) do
    slot = Map.get(apid_to_slot, apid, fallback_slot(apid))
    current = :atomics.add_get(ref, slot, 1)
    rem(current - 1, @max_sequence)
  end

  @doc """
  Gets the current sequence number for an APID without incrementing.

  Useful for debugging or stats. Note that this value may be stale
  immediately after reading due to concurrent updates.
  """
  @spec peek(t(), non_neg_integer()) :: non_neg_integer()
  def peek(%__MODULE__{ref: ref, apid_to_slot: apid_to_slot}, apid) do
    slot = Map.get(apid_to_slot, apid, fallback_slot(apid))
    value = :atomics.get(ref, slot)
    rem(value, @max_sequence)
  end

  @doc """
  Resets the sequence counter for an APID to zero.
  """
  @spec reset(t(), non_neg_integer()) :: :ok
  def reset(%__MODULE__{ref: ref, apid_to_slot: apid_to_slot}, apid) do
    slot = Map.get(apid_to_slot, apid, fallback_slot(apid))
    :atomics.put(ref, slot, 0)
    :ok
  end

  @doc """
  Resets all sequence counters to zero.
  """
  @spec reset_all(t()) :: :ok
  def reset_all(%__MODULE__{ref: ref}) do
    for slot <- 1..@max_apids do
      :atomics.put(ref, slot, 0)
    end

    :ok
  end

  # Build APID -> slot mapping for pre-allocated APIDs
  # Slots are 1-indexed (atomics requirement)
  defp build_apid_mapping(apids) do
    apids
    |> Enum.with_index(1)
    |> Map.new(fn {apid, slot} -> {apid, slot} end)
  end

  # Fallback slot for unknown APIDs: use APID + 1 as slot (1-indexed)
  # This works for APIDs 0-255
  defp fallback_slot(apid) when apid >= 0 and apid < @max_apids do
    apid + 1
  end

  defp fallback_slot(apid) do
    # For APIDs >= 256, hash to a slot
    rem(apid, @max_apids) + 1
  end
end
