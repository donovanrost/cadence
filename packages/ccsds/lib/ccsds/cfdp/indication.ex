defmodule CCSDS.CFDP.Indication do
  @moduledoc """
  A protocol event emitted by a pure CFDP transaction machine.

  The `details` map carries protocol values only. Persisting, publishing, or
  presenting an indication is an integration concern.
  """

  alias CCSDS.CFDP.TransactionID

  @type kind ::
          :transaction_started
          | :metadata_received
          | :file_segment_received
          | :eof_received
          | :transaction_finished
          | :transaction_fault
          | :fault
          | :suspended
          | :resumed
          | :abandoned
          | :keep_alive_received

  @type t :: %__MODULE__{
          type: kind(),
          transaction_id: TransactionID.t(),
          details: map()
        }

  @enforce_keys [:type, :transaction_id]
  defstruct [:type, :transaction_id, details: %{}]

  @spec new(kind(), TransactionID.t(), map()) :: t()
  def new(type, %TransactionID{} = transaction_id, details \\ %{}) when is_map(details),
    do: %__MODULE__{type: type, transaction_id: transaction_id, details: details}
end
