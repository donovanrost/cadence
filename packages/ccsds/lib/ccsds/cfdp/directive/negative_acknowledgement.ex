defmodule CCSDS.CFDP.Directive.NegativeAcknowledgement do
  @moduledoc """
  CFDP Negative Acknowledgement directive payload.

  A `{0, 0}` segment request identifies missing Metadata. Other ranges use an
  exclusive end offset.
  """

  @type segment_request :: {non_neg_integer(), non_neg_integer()}

  @type t :: %__MODULE__{
          start_of_scope: non_neg_integer(),
          end_of_scope: non_neg_integer(),
          segment_requests: [segment_request()]
        }

  defstruct start_of_scope: 0,
            end_of_scope: 0,
            segment_requests: []

  @spec new(map() | keyword()) :: t()
  def new(attrs) when is_map(attrs) or is_list(attrs), do: struct(__MODULE__, Map.new(attrs))
end
