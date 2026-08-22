defmodule CCSDS.CFDP.FileEffect do
  @moduledoc """
  Caller-owned file operation requested by a pure CFDP transaction machine.

  `reference` is opaque to the protocol library. It may identify a filesystem
  staging file, object-store upload, device, stream, or an application-owned
  process. The caller performs the operation and feeds its result back through
  the transaction procedure that emitted it.
  """

  alias CCSDS.CFDP.TransactionID

  @type operation :: :read | :write | :checksum | :finalize | :discard

  @type t :: %__MODULE__{
          operation: operation(),
          reference: term(),
          transaction_id: TransactionID.t(),
          offset: non_neg_integer() | nil,
          length: non_neg_integer() | nil,
          data: binary() | nil,
          details: map()
        }

  @enforce_keys [:operation, :reference, :transaction_id]
  defstruct [:operation, :reference, :transaction_id, :offset, :length, :data, details: %{}]

  @spec new(operation(), term(), TransactionID.t(), keyword()) :: t()
  def new(operation, reference, %TransactionID{} = transaction_id, opts \\ [])
      when operation in [:read, :write, :checksum, :finalize, :discard] do
    %__MODULE__{
      operation: operation,
      reference: reference,
      transaction_id: transaction_id,
      offset: Keyword.get(opts, :offset),
      length: Keyword.get(opts, :length),
      data: Keyword.get(opts, :data),
      details: Keyword.get(opts, :details, %{})
    }
  end
end
