defmodule Cadence.IngressArchive.Batch do
  @moduledoc """
  A contiguous journal range offered to the canonical raw-evidence archive.

  The identity is derived from immutable journal provenance so replaying an
  effect after a crash addresses the same archive object and index entries.
  """

  alias Cadence.Ingress.RawEvidence
  alias Cadence.IngressJournal.Identity

  @enforce_keys [
    :batch_id,
    :stream_id,
    :start_offset,
    :end_offset,
    :raw_evidences,
    :item_count,
    :byte_count
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          batch_id: binary(),
          stream_id: binary(),
          start_offset: non_neg_integer(),
          end_offset: pos_integer(),
          raw_evidences: [RawEvidence.t()],
          item_count: pos_integer(),
          byte_count: pos_integer()
        }

  @spec new(binary(), non_neg_integer(), pos_integer(), [RawEvidence.t()]) :: t()
  def new(stream_id, start_offset, end_offset, raw_evidences)
      when is_binary(stream_id) and is_integer(start_offset) and start_offset >= 0 and
             is_integer(end_offset) and end_offset > start_offset and is_list(raw_evidences) and
             raw_evidences != [] do
    byte_count = Enum.reduce(raw_evidences, 0, &(&2 + byte_size(&1.raw)))

    if byte_count != end_offset - start_offset do
      raise ArgumentError,
            "archive batch byte count #{byte_count} does not match journal range " <>
              "#{end_offset - start_offset}"
    end

    %__MODULE__{
      batch_id: Identity.archive_batch_id(stream_id, start_offset, end_offset),
      stream_id: stream_id,
      start_offset: start_offset,
      end_offset: end_offset,
      raw_evidences: raw_evidences,
      item_count: length(raw_evidences),
      byte_count: byte_count
    }
  end
end
