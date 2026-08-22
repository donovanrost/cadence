defmodule CCSDS.CFDP.FileData do
  @moduledoc """
  CFDP File Data PDU payload.
  """

  @type record_continuation_state ::
          :no_start_no_end | :start_no_end | :no_start_end | :start_and_end

  @type t :: %__MODULE__{
          offset: non_neg_integer(),
          data: binary(),
          record_continuation_state: record_continuation_state(),
          segment_metadata: binary() | nil
        }

  defstruct offset: 0,
            data: <<>>,
            record_continuation_state: :no_start_no_end,
            segment_metadata: nil

  @spec new(map() | keyword()) :: t()
  def new(attrs) when is_map(attrs) or is_list(attrs), do: struct(__MODULE__, Map.new(attrs))
end
