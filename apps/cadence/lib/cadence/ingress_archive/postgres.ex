defmodule Cadence.IngressArchive.Postgres do
  @moduledoc """
  Compatibility ingress archive backend backed by the `ingress_raw_evidence`
  table.
  """

  import Ecto.Query

  alias Ecto.Multi

  alias Cadence.Ingress.RawEvidence
  alias Cadence.IngressArchive.Postgres.RawEvidenceRow
  alias Cadence.Replay.Scope
  alias Cadence.Repo

  @behaviour Cadence.IngressArchive

  @impl true
  def child_spec(_opts), do: nil

  @impl true
  def persist_raw_evidence_multi(%Multi{} = multi, %RawEvidence{} = raw_evidence) do
    Multi.insert(
      multi,
      {:raw_evidence, raw_evidence.evidence_id},
      RawEvidenceRow.changeset(raw_evidence)
    )
  end

  @impl true
  def persist_raw_evidence(_raw_evidence), do: :ok

  def persist_raw_evidences(raw_evidences) when is_list(raw_evidences) do
    case Enum.all?(raw_evidences, &match?(%RawEvidence{}, &1)) do
      true -> :ok
      false -> {:error, :invalid_raw_evidence_batch}
    end
  end

  @impl true
  def fetch_raw_evidences(mission_id, %Scope{} = scope) when is_binary(mission_id) do
    raw_evidences =
      RawEvidenceRow
      |> where([row], row.mission_id == ^mission_id)
      |> maybe_filter_scope(scope)
      |> order_by([row], asc: row.receipt_time, asc: row.evidence_id)
      |> maybe_limit_scope(scope.limit)
      |> Repo.all()
      |> Enum.map(&RawEvidenceRow.to_domain/1)

    case scope.evidence_ids do
      evidence_ids when is_list(evidence_ids) and evidence_ids != [] ->
        ordered = order_raw_evidences_by_ids(raw_evidences, evidence_ids)

        if length(ordered) == length(Enum.uniq(evidence_ids)) do
          {:ok, ordered}
        else
          found_ids = MapSet.new(Enum.map(ordered, & &1.evidence_id))

          missing_evidence_ids =
            evidence_ids
            |> Enum.uniq()
            |> Enum.reject(&MapSet.member?(found_ids, &1))

          {:error, {:evidence_not_found, missing_evidence_ids}}
        end

      _other ->
        case raw_evidences do
          [] -> {:error, :empty_replay_scope}
          _ -> {:ok, raw_evidences}
        end
    end
  end

  @impl true
  def flush(_mission_id), do: :ok

  @impl true
  def reset do
    _ = Repo.delete_all(RawEvidenceRow)
    :ok
  end

  @impl true
  def stats(_mission_id) do
    %{
      queue_depth: 0,
      oldest_buffered_age_ms: 0,
      flush_count: 0,
      flush_failure_count: 0,
      last_flush_error: nil,
      flushed_count: 0,
      segment_count: 0,
      flush_total_us: 0,
      avg_flush_us: 0.0,
      flushed_bytes_total: 0,
      avg_segment_bytes: 0.0
    }
  end

  @impl true
  def reset_stats(_mission_id), do: :ok

  defp maybe_filter_scope(query, %Scope{} = scope) do
    query
    |> maybe_filter_evidence_ids(scope.evidence_ids)
    |> maybe_filter_from_receipt_time(scope.from_receipt_time)
    |> maybe_filter_to_receipt_time(scope.to_receipt_time)
    |> maybe_filter_spacecraft(scope.spacecraft_id)
    |> maybe_filter_source_ref(scope.source_ref)
    |> maybe_filter_realized_contact_id(scope.realized_contact_id)
    |> maybe_filter_metadata_match(scope.metadata_match)
  end

  defp maybe_filter_evidence_ids(query, nil), do: query

  defp maybe_filter_evidence_ids(query, evidence_ids)
       when is_list(evidence_ids) and evidence_ids != [] do
    unique_evidence_ids = Enum.uniq(evidence_ids)
    where(query, [row], row.evidence_id in ^unique_evidence_ids)
  end

  defp maybe_filter_from_receipt_time(query, nil), do: query

  defp maybe_filter_from_receipt_time(query, %DateTime{} = from_receipt_time) do
    where(query, [row], row.receipt_time >= ^from_receipt_time)
  end

  defp maybe_filter_to_receipt_time(query, nil), do: query

  defp maybe_filter_to_receipt_time(query, %DateTime{} = to_receipt_time) do
    where(query, [row], row.receipt_time <= ^to_receipt_time)
  end

  defp maybe_filter_spacecraft(query, nil), do: query

  defp maybe_filter_spacecraft(query, spacecraft_id) when is_binary(spacecraft_id) do
    where(query, [row], row.spacecraft_id == ^spacecraft_id)
  end

  defp maybe_filter_source_ref(query, nil), do: query

  defp maybe_filter_source_ref(query, source_ref) when is_binary(source_ref) do
    where(query, [row], row.source_ref == ^source_ref)
  end

  defp maybe_filter_realized_contact_id(query, nil), do: query

  defp maybe_filter_realized_contact_id(query, realized_contact_id)
       when is_binary(realized_contact_id) do
    where(
      query,
      [row],
      fragment("? ->> 'realized_contact_id' = ?", row.metadata, ^realized_contact_id)
    )
  end

  defp maybe_filter_metadata_match(query, nil), do: query

  defp maybe_filter_metadata_match(query, metadata_match)
       when is_map(metadata_match) and map_size(metadata_match) > 0 do
    Enum.reduce(metadata_match, query, fn {key, value}, acc ->
      where(acc, [row], fragment("? ->> ? = ?", row.metadata, ^to_string(key), ^to_string(value)))
    end)
  end

  defp maybe_filter_metadata_match(query, _metadata_match), do: query

  defp maybe_limit_scope(query, nil), do: query
  defp maybe_limit_scope(query, limit), do: limit(query, ^limit)

  defp order_raw_evidences_by_ids(raw_evidences, evidence_ids) do
    evidence_order = Map.new(Enum.with_index(Enum.uniq(evidence_ids)))

    raw_evidences
    |> Enum.sort_by(fn %RawEvidence{} = raw_evidence ->
      Map.fetch!(evidence_order, raw_evidence.evidence_id)
    end)
  end
end
