defmodule Cadence.CCSDS.CFDP.Directive.Acknowledgement do
  @moduledoc """
  CFDP positive Acknowledgement directive payload.
  """

  alias Cadence.CCSDS.CFDP

  @type acknowledged_directive :: :end_of_file | :finished
  @type transaction_status :: :undefined | :active | :terminated | :unrecognized

  @type t :: %__MODULE__{
          directive: acknowledged_directive(),
          condition: CFDP.condition(),
          transaction_status: transaction_status()
        }

  defstruct directive: :end_of_file,
            condition: :no_error,
            transaction_status: :active

  @spec new(map() | keyword()) :: t()
  def new(attrs) when is_map(attrs) or is_list(attrs), do: struct(__MODULE__, Map.new(attrs))
end
