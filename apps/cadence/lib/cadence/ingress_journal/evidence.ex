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
        "journal_last_receipt_time" => DateTime.to_iso8601(last.receipt_time)
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
         source_ref: metadata_value(metadata, :source_ref),
         metadata: Map.merge(ingress_metadata, journal_metadata)
       })}
    else
      {:error, {:unsupported_journal_protocol_family, protocol_family}}
    end
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
