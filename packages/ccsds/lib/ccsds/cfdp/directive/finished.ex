defmodule CCSDS.CFDP.Directive.Finished do
  @moduledoc """
  CFDP Finished directive payload.
  """

  alias CCSDS.CFDP
  alias CCSDS.CFDP.TLV.{EntityID, FilestoreResponse}

  @type delivery_code :: :complete | :incomplete
  @type file_status ::
          :discarded_deliberately
          | :discarded_by_filestore
          | :retained
          | :unreported

  @type t :: %__MODULE__{
          condition: CFDP.condition(),
          delivery_code: delivery_code(),
          file_status: file_status(),
          filestore_responses: [FilestoreResponse.t()],
          fault_location: EntityID.t() | nil
        }

  defstruct condition: :no_error,
            delivery_code: :complete,
            file_status: :unreported,
            filestore_responses: [],
            fault_location: nil

  @spec new(map() | keyword()) :: t()
  def new(attrs) when is_map(attrs) or is_list(attrs), do: struct(__MODULE__, Map.new(attrs))
end
