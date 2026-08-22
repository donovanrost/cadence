defmodule Cadence.IngressJournal.Entry do
  @moduledoc """
  Immutable location and provenance for one captured ingress byte range.

  Entries deliberately contain a file location rather than the payload. This
  lets journal consumers read bytes directly from the filesystem without
  serializing reads through the journal writer.
  """

  @enforce_keys [
    :stream_id,
    :sequence,
    :start_offset,
    :end_offset,
    :payload_length,
    :receipt_time,
    :metadata,
    :segment_path,
    :payload_file_offset,
    :checksum
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          stream_id: binary(),
          sequence: non_neg_integer(),
          start_offset: non_neg_integer(),
          end_offset: pos_integer(),
          payload_length: pos_integer(),
          receipt_time: DateTime.t(),
          metadata: map(),
          segment_path: binary(),
          payload_file_offset: non_neg_integer(),
          checksum: binary()
        }

  @spec read(t()) :: {:ok, binary()} | {:error, term()}
  def read(%__MODULE__{} = entry) do
    with {:ok, file} <- :file.open(entry.segment_path, [:read, :binary, :raw]),
         result <- :file.pread(file, entry.payload_file_offset, entry.payload_length),
         :ok <- :file.close(file) do
      validate_payload(result, entry)
    end
  end

  defp validate_payload({:ok, payload}, %__MODULE__{} = entry)
       when byte_size(payload) == entry.payload_length do
    if :crypto.hash(:sha256, payload) == entry.checksum do
      {:ok, payload}
    else
      {:error, {:journal_checksum_mismatch, entry.sequence}}
    end
  end

  defp validate_payload(:eof, %__MODULE__{} = entry),
    do: {:error, {:journal_payload_missing, entry.sequence}}

  defp validate_payload({:ok, payload}, %__MODULE__{} = entry),
    do: {:error, {:journal_payload_truncated, entry.sequence, byte_size(payload)}}

  defp validate_payload({:error, reason}, %__MODULE__{} = entry),
    do: {:error, {:journal_read_failed, entry.sequence, reason}}
end
