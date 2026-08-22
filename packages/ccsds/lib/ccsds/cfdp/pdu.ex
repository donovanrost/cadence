defmodule CCSDS.CFDP.PDU do
  @moduledoc """
  Semantic CFDP PDU with its common fixed-header fields.

  Identifier widths are retained on decode for exact re-encoding. When either
  width is `nil`, the encoder selects the smallest legal width.
  """

  alias CCSDS.CFDP
  alias CCSDS.CFDP.Directive
  alias CCSDS.CFDP.FileData

  @type payload ::
          Directive.Metadata.t()
          | Directive.EndOfFile.t()
          | Directive.Finished.t()
          | Directive.Acknowledgement.t()
          | Directive.NegativeAcknowledgement.t()
          | Directive.Prompt.t()
          | Directive.KeepAlive.t()
          | FileData.t()

  @type t :: %__MODULE__{
          version: 1,
          direction: CFDP.direction(),
          transmission_mode: CFDP.transmission_mode(),
          crc?: boolean(),
          large_file?: boolean(),
          record_boundaries_preserved?: boolean(),
          source_entity_id: non_neg_integer(),
          transaction_sequence_number: non_neg_integer(),
          destination_entity_id: non_neg_integer(),
          entity_id_octets: 1..8 | nil,
          sequence_number_octets: 1..8 | nil,
          payload: payload() | nil
        }

  defstruct version: 1,
            direction: :toward_file_receiver,
            transmission_mode: :unacknowledged,
            crc?: false,
            large_file?: false,
            record_boundaries_preserved?: false,
            source_entity_id: nil,
            transaction_sequence_number: nil,
            destination_entity_id: nil,
            entity_id_octets: nil,
            sequence_number_octets: nil,
            payload: nil

  @spec new(map() | keyword()) :: t()
  def new(attrs) when is_map(attrs) or is_list(attrs), do: struct(__MODULE__, Map.new(attrs))
end
