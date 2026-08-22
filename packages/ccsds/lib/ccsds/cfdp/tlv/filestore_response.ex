defmodule CCSDS.CFDP.TLV.FilestoreResponse do
  @moduledoc """
  CFDP Filestore Response TLV.
  """

  alias CCSDS.CFDP.TLV.FilestoreRequest

  @type t :: %__MODULE__{
          action: FilestoreRequest.action(),
          status: 0..15,
          first_file_name: binary(),
          second_file_name: binary() | nil,
          filestore_message: binary()
        }

  defstruct action: nil,
            status: 0,
            first_file_name: <<>>,
            second_file_name: nil,
            filestore_message: <<>>

  @spec new(map() | keyword()) :: t()
  def new(attrs) when is_map(attrs) or is_list(attrs), do: struct(__MODULE__, Map.new(attrs))
end
