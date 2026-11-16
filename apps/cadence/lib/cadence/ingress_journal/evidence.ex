defmodule Cadence.IngressJournal.Evidence do
  @moduledoc """
  Reconstructs canonical raw evidence from an immutable journal entry.

  Processing and raw archival share this conversion so replay preserves the
  same evidence identity and absolute byte provenance at both boundaries.
  """

  alias Cadence.Ingress.RawEvidence
  alias Cadence.IngressJournal.{Entry, Identity}

  @spec from_entry(Entry.t()) :: {:ok, RawEvidence.t()} | {:error, term()}
  def from_entry(%Entry{} = entry) do
    with {:ok, payload} <- Entry.read(entry) do
      from_payload([entry], payload)
    end
  end

  @doc """
  Reconstructs one semantic work item from adjacent journal records.

  The work item's identity and provenance cover the complete absolute byte
  range; the physical record boundaries remain available as a sequence range.
  """
  @spec from_contiguous_entries([Entry.t()]) :: {:ok, RawEvidence.t()} | {:error, term()}
  def from_contiguous_entries([%Entry{} | _rest] = entries) do
    with :ok <- validate_contiguous_entries(entries),
         {:ok, payloads} <- read_payloads(entries) do
      from_payload(entries, IO.iodata_to_binary(payloads))
    end
  end

  def from_contiguous_entries(_entries),
    do: {:error, :empty_ingress_journal_evidence_batch}

  @spec from_entries([Entry.t()]) :: {:ok, [RawEvidence.t()]} | {:error, term()}
  def from_entries(entries) when is_list(entries) and entries != [] do
    Enum.reduce_while(entries, {:ok, []}, fn %Entry{} = entry, {:ok, acc} ->
      case from_entry(entry) do
        {:ok, %RawEvidence{} = raw_evidence} -> {:cont, {:ok, [raw_evidence | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, raw_evidences} -> {:ok, Enum.reverse(raw_evidences)}
      {:error, reason} -> {:error, reason}
    end
  end

  def from_entries(_entries), do: {:error, :empty_ingress_journal_evidence_batch}

  @doc """
  Returns whether two adjacent records may share one semantic work item.

  Capture-batch identifiers and boundaries describe physical socket admission,
  not semantic interpretation, so they may differ. Source and protocol
  metadata must remain identical.
  """
  @spec compatible_entries?(Entry.t(), Entry.t()) :: boolean()
  def compatible_entries?(%Entry{} = first, %Entry{} = second) do
    first.stream_id == second.stream_id and first.end_offset == second.start_offset and
      first.sequence + 1 == second.sequence and
      stable_metadata(first.metadata) == stable_metadata(second.metadata)
  end

  defp from_payload([%Entry{} = first | _rest] = entries, payload) do
    last = List.last(entries)
    metadata = first.metadata
    protocol_family = metadata_value(metadata, :protocol_family)

    if protocol_family in [:tm, :tm_transfer_frame] do
      ingress_metadata = metadata_value(metadata, :ingress_metadata) || %{}
      capture_batches = capture_batches(entries)

      journal_metadata = %{
        "journal_stream_id" => first.stream_id,
        "journal_sequence" => first.sequence,
        "journal_end_sequence" => last.sequence,
        "journal_record_count" => last.sequence - first.sequence + 1,
        "journal_capture_batch_id" => single_capture_batch_id(capture_batches),
        "journal_capture_batch_ids" => Enum.map(capture_batches, & &1["id"]),
        "journal_capture_batch_count" => length(capture_batches),
        "journal_capture_batches" => capture_batches,
        "journal_start_offset" => first.start_offset,
        "journal_end_offset" => last.end_offset,
        "journal_first_receipt_time" => DateTime.to_iso8601(first.receipt_time),
        "journal_last_receipt_time" => DateTime.to_iso8601(last.receipt_time),
        # Survives the ingress archive (which keeps metadata), so re-decoding archived evidence
        # still gives each frame its own record's receipt time.
        RawEvidence.receipt_times_key() =>
          RawEvidence.encode_receipt_times(receipt_times(entries))
      }

      {:ok,
       RawEvidence.new(%{
         evidence_id: Identity.evidence_id(first.stream_id, first.start_offset, last.end_offset),
         mission_id: metadata_value(metadata, :mission_id),
         source_endpoint_ref: metadata_value(metadata, :source_endpoint_ref),
         spacecraft_id: metadata_value(metadata, :spacecraft_id),
         protocol_family: protocol_family,
         direction: :downlink,
         raw: payload,
         receipt_time: first.receipt_time,
         # Each record keeps its own socket receipt time: a merged batch must not stamp every
         # frame with the first record's time (11-14 00:38–00:40Z, 8 frames per stamp).
         receipt_times: receipt_times(entries),
         source_ref: metadata_value(metadata, :source_ref),
         metadata:
           ingress_metadata |> Map.merge(contact_context(metadata)) |> Map.merge(journal_metadata)
       })}
    else
      {:error, {:unsupported_journal_protocol_family, protocol_family}}
    end
  end

  @doc """
  `raw_evidence` without its leading bytes before the absolute stream offset `offset`: after a
  restart, the bytes of the resume entry the processing consumer had already decoded (the journal's
  durable resume point, domain's partial-frame fix 11-15). Unchanged when `offset` isn't inside it.
  """
  @spec drop_before(RawEvidence.t(), non_neg_integer()) :: RawEvidence.t()
  def drop_before(%RawEvidence{metadata: metadata} = raw_evidence, offset)
      when is_integer(offset) do
    start = metadata["journal_start_offset"]
    finish = metadata["journal_end_offset"]

    if is_integer(start) and is_integer(finish) and offset > start and offset < finish do
      skip = offset - start
      <<_done::binary-size(^skip), rest::binary>> = raw_evidence.raw

      %{
        raw_evidence
        | evidence_id: Identity.evidence_id(metadata["journal_stream_id"], offset, finish),
          raw: rest,
          receipt_times: receipt_times_from(raw_evidence.receipt_times, offset),
          metadata:
            metadata
            |> Map.put("journal_start_offset", offset)
            |> Map.put("journal_resumed_from", start)
            |> Map.put(
              RawEvidence.receipt_times_key(),
              RawEvidence.encode_receipt_times(
                receipt_times_from(raw_evidence.receipt_times, offset)
              )
            )
      }
    else
      raw_evidence
    end
  end

  # The record covering `offset` keeps its time, starting at `offset`; later records unchanged.
  defp receipt_times_from(times, offset) when is_list(times) do
    {before, rest} = Enum.split_while(times, fn {start, _time} -> start < offset end)

    case {List.last(before), rest} do
      {nil, rest} -> rest
      {{_start, time}, [{^offset, _} | _] = rest} when is_struct(time) -> rest
      {{_start, time}, rest} -> [{offset, time} | rest]
    end
  end

  defp receipt_times_from(times, _offset), do: times

  defp receipt_times(entries), do: Enum.map(entries, &{&1.start_offset, &1.receipt_time})

  # The contact, path and binding the TCP receiver journals at the entry's top level, as the
  # same string keys the journal-less path sets (tcp_socket.ex), so archive rows name their
  # contact (qa issue 61: every archive row read NULL, and #88 quarantine items group by it).
  defp contact_context(metadata) do
    for key <- [:realized_contact_id, :path_id, :provider_binding_id],
        value = metadata_value(metadata, key),
        is_binary(value),
        into: %{},
        do: {Atom.to_string(key), value}
  end

  defp validate_contiguous_entries([%Entry{}]), do: :ok

  defp validate_contiguous_entries([%Entry{} = first, %Entry{} = second | rest]) do
    if compatible_entries?(first, second) do
      validate_contiguous_entries([second | rest])
    else
      {:error, :non_contiguous_ingress_journal_evidence_batch}
    end
  end

  defp read_payloads(entries) do
    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, payloads} ->
      case Entry.read(entry) do
        {:ok, payload} -> {:cont, {:ok, [payload | payloads]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, payloads} -> {:ok, Enum.reverse(payloads)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp metadata_value(metadata, key) do
    Map.get(metadata, key, Map.get(metadata, Atom.to_string(key)))
  end

  defp stable_metadata(metadata) do
    Map.drop(metadata, [
      :journal_capture_batch_id,
      :journal_capture_batch_start_offset,
      :journal_capture_batch_end_offset,
      "journal_capture_batch_id",
      "journal_capture_batch_start_offset",
      "journal_capture_batch_end_offset"
    ])
  end

  defp capture_batches(entries) do
    entries
    |> Enum.reduce([], fn entry, batches ->
      batch = %{
        "id" => metadata_value(entry.metadata, :journal_capture_batch_id),
        "start_offset" => metadata_value(entry.metadata, :journal_capture_batch_start_offset),
        "end_offset" => metadata_value(entry.metadata, :journal_capture_batch_end_offset)
      }

      if batch["id"] && List.first(batches) != batch, do: [batch | batches], else: batches
    end)
    |> Enum.reverse()
  end

  defp single_capture_batch_id([%{"id" => id}]), do: id
  defp single_capture_batch_id(_capture_batches), do: nil
end
