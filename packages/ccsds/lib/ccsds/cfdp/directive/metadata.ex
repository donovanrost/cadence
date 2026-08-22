defmodule CCSDS.CFDP.Directive.Metadata do
  @moduledoc """
  CFDP Metadata directive payload.
  """

  alias CCSDS.CFDP.TLV

  @type t :: %__MODULE__{
          closure_requested?: boolean(),
          checksum_type: 0..15,
          file_size: non_neg_integer(),
          source_file_name: binary(),
          destination_file_name: binary(),
          options: [TLV.t()]
        }

  defstruct closure_requested?: false,
            checksum_type: 0,
            file_size: 0,
            source_file_name: <<>>,
            destination_file_name: <<>>,
            options: []

  @spec new(map() | keyword()) :: t()
  def new(attrs) when is_map(attrs) or is_list(attrs), do: struct(__MODULE__, Map.new(attrs))
end
