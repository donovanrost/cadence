defmodule Cadence.IngressArchive.Receipt do
  @moduledoc """
  Explicit completion receipt for one raw-archive batch.

  `:durable` means the source range is discoverable in the configured canonical
  archive. `:accepted` is reserved for explicitly non-durable benchmark or
  compatibility sinks and cannot satisfy the production durability policy.
  """

  alias Cadence.IngressArchive.Batch

  @enforce_keys [
    :batch_id,
    :stream_id,
    :start_offset,
    :end_offset,
    :item_count,
    :byte_count,
    :completion
  ]
  defstruct @enforce_keys

  @type completion :: :durable | :accepted
  @type t :: %__MODULE__{
          batch_id: binary(),
          stream_id: binary(),
          start_offset: non_neg_integer(),
          end_offset: pos_integer(),
          item_count: pos_integer(),
          byte_count: pos_integer(),
          completion: completion()
        }

  @spec for_batch(Batch.t(), completion()) :: t()
  def for_batch(%Batch{} = batch, completion) when completion in [:durable, :accepted] do
    %__MODULE__{
      batch_id: batch.batch_id,
      stream_id: batch.stream_id,
      start_offset: batch.start_offset,
      end_offset: batch.end_offset,
      item_count: batch.item_count,
      byte_count: batch.byte_count,
      completion: completion
    }
  end

  @spec valid_for_batch?(t(), Batch.t()) :: boolean()
  def valid_for_batch?(%__MODULE__{} = receipt, %Batch{} = batch) do
    receipt.batch_id == batch.batch_id and receipt.stream_id == batch.stream_id and
      receipt.start_offset == batch.start_offset and receipt.end_offset == batch.end_offset and
      receipt.item_count == batch.item_count and receipt.byte_count == batch.byte_count
  end

  @spec satisfies?(t(), completion()) :: boolean()
  def satisfies?(%__MODULE__{completion: :durable}, required)
      when required in [:durable, :accepted],
      do: true

  def satisfies?(%__MODULE__{completion: :accepted}, :accepted), do: true
  def satisfies?(%__MODULE__{}, _required), do: false
end
