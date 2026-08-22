defmodule Cadence.IngressJournal.Identity do
  @moduledoc """
  Stable identities derived from immutable journal provenance.

  Replaying the same captured byte range therefore addresses the same
  persistence rows instead of creating duplicates.
  """

  alias Cadence.IngressJournal.Entry

  @spec evidence_id(Entry.t()) :: binary()
  def evidence_id(%Entry{} = entry) do
    evidence_id(entry.stream_id, entry.start_offset, entry.end_offset)
  end

  @spec evidence_id(binary(), non_neg_integer(), pos_integer()) :: binary()
  def evidence_id(stream_id, start_offset, end_offset)
      when is_binary(stream_id) and is_integer(start_offset) and start_offset >= 0 and
             is_integer(end_offset) and end_offset > start_offset do
    stable_id("evidence", [stream_id, start_offset, end_offset])
  end

  @spec archive_batch_id(binary(), non_neg_integer(), pos_integer()) :: binary()
  def archive_batch_id(stream_id, start_offset, end_offset)
      when is_binary(stream_id) and is_integer(start_offset) and start_offset >= 0 and
             is_integer(end_offset) and end_offset > start_offset do
    stable_id("archive_batch", [stream_id, start_offset, end_offset])
  end

  @spec capture_batch_id(binary(), non_neg_integer(), pos_integer()) :: binary()
  def capture_batch_id(stream_id, start_offset, end_offset)
      when is_binary(stream_id) and is_integer(start_offset) and start_offset >= 0 and
             is_integer(end_offset) and end_offset > start_offset do
    stable_id("capture_batch", [stream_id, start_offset, end_offset])
  end

  @spec frame_record_id(binary(), non_neg_integer(), pos_integer()) :: binary()
  def frame_record_id(evidence_id, absolute_offset, length)
      when is_binary(evidence_id) and is_integer(absolute_offset) and is_integer(length) do
    stable_id("frame", [evidence_id, absolute_offset, length])
  end

  @spec packet_id(binary(), non_neg_integer(), binary()) :: binary()
  def packet_id(evidence_id, ordinal, packet)
      when is_binary(evidence_id) and is_integer(ordinal) and is_binary(packet) do
    stable_id("packet", [evidence_id, ordinal, :crypto.hash(:sha256, packet)])
  end

  defp stable_id(prefix, parts) do
    digest =
      parts
      |> Enum.map(&:erlang.term_to_binary/1)
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    prefix <> "_" <> digest
  end
end
