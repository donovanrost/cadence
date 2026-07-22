defmodule Cadence.CCSDS.CFDP.Directive.EndOfFile do
  @moduledoc """
  CFDP End-of-File directive payload.
  """

  alias Cadence.CCSDS.CFDP
  alias Cadence.CCSDS.CFDP.TLV.EntityID

  @type t :: %__MODULE__{
          condition: CFDP.condition(),
          file_checksum: 0..0xFFFFFFFF,
          file_size: non_neg_integer(),
          fault_location: EntityID.t() | nil
        }

  defstruct condition: :no_error,
            file_checksum: 0,
            file_size: 0,
            fault_location: nil

  @spec new(map() | keyword()) :: t()
  def new(attrs) when is_map(attrs) or is_list(attrs), do: struct(__MODULE__, Map.new(attrs))
end
