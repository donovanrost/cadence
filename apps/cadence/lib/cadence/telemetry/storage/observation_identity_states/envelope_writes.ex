defmodule Cadence.Telemetry.Storage.ObservationIdentityStates.EnvelopeWrites do
  @moduledoc """
  Identity-state writes for one batch of observation envelopes, run inside the caller's
  transaction.

  A row exists only for an identity something has been said about: a decision, or a
  non-canonical sighting (late data rejected as advisory, today). A canonical sighting of an
  identity with no row writes nothing (the first-seen rule, 11-17): selection reads such a sample
  by its own validity, and the dashboards revision dependency takes its identity from the sample.
  An identity that has a row tracks every later sighting as before: counts, canonical promotion,
  latest pointers, last seen.

  Lock order is identity order throughout, so two batches can't deadlock (dashboards' review,
  11-17): existing rows are locked once per batch; then the batch's new identities (each from its
  first non-canonical sighting) are inserted in one sorted ON CONFLICT DO NOTHING statement; then
  the rows a concurrent batch or decision created first are locked, sorted, and this batch's
  sightings update them. A conflicting row that vanished before the lock (the 96 h prune) is
  inserted once more; only a second conflict fails the batch. Within a batch, a canonical
  sighting before an identity's first non-canonical one still writes nothing.
  """

  import Ecto.Query

  alias Cadence.Telemetry.Storage.ObservationEnvelope

  alias Cadence.Telemetry.Storage.ObservationIdentityStates.TelemetryObservationIdentityStateRow,
    as: Row

  @spec record(module(), [ObservationEnvelope.t()]) :: :ok | {:error, term()}
  def record(repo, envelopes) when is_list(envelopes) do
    rows = lock_existing(repo, envelopes |> Enum.map(& &1.observation_identity_id) |> Enum.uniq())

    with {:ok, claimed, rows} <- claim_new(repo, envelopes, rows) do
      record_all(repo, envelopes, rows, claimed)
    end
  end

  defp record_all(repo, envelopes, rows, claimed) do
    envelopes
    |> Enum.reduce_while({:ok, rows}, fn envelope, {:ok, rows} ->
      id = envelope.observation_identity_id

      case record_envelope(repo, envelope, current_row(rows, claimed, envelope)) do
        {:ok, nil} -> {:cont, {:ok, rows}}
        {:ok, %Row{} = row} -> {:cont, {:ok, Map.put(rows, id, row)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, _rows} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Locks and returns the row for one identity, or nil."
  @spec lock_row(module(), binary()) :: struct() | nil
  def lock_row(repo, observation_identity_id) do
    Row
    |> where([row], row.observation_identity_id == ^observation_identity_id)
    |> lock("FOR UPDATE")
    |> repo.one()
  end

  # This batch's own new row counts from its first non-canonical sighting on, as if inserted there.
  defp current_row(rows, claimed, %ObservationEnvelope{observation_identity_id: id} = envelope) do
    case {Map.get(rows, id), Map.get(claimed, id)} do
      {%Row{} = row, _claimed} -> row
      {nil, %Row{latest_observation_id: obs} = row} when obs == envelope.observation_id -> row
      {nil, _not_yet} -> nil
    end
  end

  # One sorted insert-or-nothing of the identities this batch creates, then a sorted lock of those
  # another transaction created first; a vanished one is tried once more.
  defp claim_new(repo, envelopes, rows) do
    firsts = first_non_canonical(envelopes, rows)

    with {:ok, claimed, lost} <- insert_sorted(repo, firsts) do
      taken = lock_existing(repo, lost)
      vanished = Enum.reject(lost, &Map.has_key?(taken, &1))

      case insert_sorted(repo, Map.take(firsts, vanished)) do
        {:ok, again, []} -> {:ok, Map.merge(claimed, again), Map.merge(rows, taken)}
        {:ok, _again, [id | _rest]} -> {:error, {:observation_identity_state_conflict, id}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp first_non_canonical(envelopes, rows) do
    Enum.reduce(envelopes, %{}, fn
      %ObservationEnvelope{validity_state: :canonical}, firsts ->
        firsts

      %ObservationEnvelope{observation_identity_id: id} = envelope, firsts ->
        if Map.has_key?(rows, id), do: firsts, else: Map.put_new(firsts, id, envelope)
    end)
  end

  defp insert_sorted(_repo, firsts) when map_size(firsts) == 0, do: {:ok, %{}, []}

  defp insert_sorted(repo, firsts) do
    with {:ok, entries} <- insert_entries(firsts) do
      # Chunks stay in identity order; uncached, as before, so a large batch leaves no prepared
      # statement with thousands of parameters behind.
      claimed =
        entries
        |> Enum.chunk_every(1_000)
        |> Enum.flat_map(fn chunk ->
          {_count, inserted} =
            repo.insert_all(Row, chunk,
              cache_statement: false,
              on_conflict: :nothing,
              conflict_target: [:observation_identity_id],
              returning: true
            )

          inserted
        end)
        |> Map.new(&{&1.observation_identity_id, &1})

      {:ok, claimed,
       firsts |> Map.keys() |> Enum.reject(&Map.has_key?(claimed, &1)) |> Enum.sort()}
    end
  end

  defp insert_entries(firsts) do
    now = DateTime.utc_now()

    firsts
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce_while({:ok, []}, fn {_id, envelope}, {:ok, entries} ->
      changeset = Row.changeset(%Row{}, initial_attrs(envelope))

      case Ecto.Changeset.apply_action(changeset, :insert) do
        {:ok, row} ->
          attrs = row |> Map.take(Row.fields()) |> Map.merge(%{inserted_at: now, updated_at: now})
          {:cont, {:ok, [attrs | entries]}}

        {:error, changeset} ->
          {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp lock_existing(repo, ids) do
    case ids do
      [] ->
        %{}

      ids ->
        Row
        |> where([row], row.observation_identity_id in ^ids)
        |> order_by([row], asc: row.observation_identity_id)
        |> lock("FOR UPDATE")
        |> repo.all()
        |> Map.new(&{&1.observation_identity_id, &1})
    end
  end

  defp record_envelope(_repo, %ObservationEnvelope{validity_state: :canonical}, nil),
    do: {:ok, nil}

  # Every new identity's row was claimed or locked before the loop (claim_new/3).
  defp record_envelope(_repo, %ObservationEnvelope{} = envelope, nil),
    do: {:error, {:observation_identity_state_unclaimed, envelope.observation_identity_id}}

  defp record_envelope(_repo, envelope, %Row{} = row)
       when row.latest_observation_id == envelope.observation_id or
              row.canonical_observation_id == envelope.observation_id,
       do: {:ok, row}

  defp record_envelope(repo, envelope, %Row{} = row) do
    row
    |> Row.changeset(updated_attrs(row, envelope))
    |> repo.update()
  end

  defp initial_attrs(%ObservationEnvelope{} = envelope) do
    envelope
    |> base_attrs()
    |> Map.merge(count_attrs(envelope))
    |> maybe_put_canonical(envelope, envelope.validity_state == :canonical)
    |> Map.put(:validity_state, validity_state(nil, envelope))
  end

  # #369 (lead's ruling: a revision never clears an operator's decision; domain's scope): a row an
  # operator DECIDED (decision_event_id set) keeps every field the decision owns: the canonical
  # columns, validity_state, decision_reason, decided_at and the payload's "decision" that
  # EffectiveSelection reads. A later sighting (a duplicate, a conflict or a revision) updates only
  # the counts, latest_* and the seen times, so latest_revision > canonical_revision says a newer
  # revision arrived (U106) while selection still follows the decision.
  defp updated_attrs(%Row{decision_event_id: decided} = row, %ObservationEnvelope{} = envelope)
       when is_binary(decided) do
    row
    |> Map.take(Row.fields())
    |> merge_counts(envelope)
    |> Map.merge(%{
      latest_observation_id: envelope.observation_id,
      latest_sample_id: envelope.sample_id,
      latest_revision: envelope.revision
    })
    |> Map.put(:first_seen_at, earliest(row.first_seen_at, envelope.ingested_at))
    |> Map.put(:last_seen_at, latest(row.last_seen_at, envelope.ingested_at))
  end

  defp updated_attrs(%Row{} = row, %ObservationEnvelope{} = envelope) do
    row
    |> Map.take(Row.fields())
    |> Map.merge(base_attrs(envelope))
    |> merge_counts(envelope)
    |> maybe_put_canonical(envelope, promote_canonical?(row, envelope))
    |> Map.put(:validity_state, validity_state(row, envelope))
    |> Map.put(:first_seen_at, earliest(row.first_seen_at, envelope.ingested_at))
    |> Map.put(:last_seen_at, latest(row.last_seen_at, envelope.ingested_at))
  end

  defp base_attrs(%ObservationEnvelope{} = envelope) do
    %{
      observation_identity_id: envelope.observation_identity_id,
      organization_id: envelope.organization_id,
      mission_id: envelope.mission_id,
      realm: enum_string(envelope.realm),
      replay_run_id: envelope.replay_run_id,
      data_source_id: envelope.data_source_id,
      binding_id: envelope.binding_id,
      observable_id: envelope.observable_id,
      point_id: envelope.point_id,
      spacecraft_id: envelope.spacecraft_id,
      latest_observation_id: envelope.observation_id,
      latest_sample_id: envelope.sample_id,
      latest_revision: envelope.revision,
      first_seen_at: envelope.ingested_at,
      last_seen_at: envelope.ingested_at,
      payload: payload(envelope)
    }
  end

  @count_fields [
    canonical: :canonical_count,
    duplicate: :duplicate_count,
    conflict: :conflict_count,
    superseded: :superseded_count,
    advisory: :advisory_count
  ]

  defp count_attrs(%ObservationEnvelope{} = envelope) do
    Map.new(@count_fields, fn {state, field} -> {field, count(envelope, state)} end)
  end

  defp merge_counts(attrs, %ObservationEnvelope{} = envelope) do
    Enum.reduce(@count_fields, attrs, fn {state, field}, attrs ->
      Map.update!(attrs, field, &(&1 + count(envelope, state)))
    end)
  end

  defp count(%ObservationEnvelope{validity_state: state}, state), do: 1
  defp count(%ObservationEnvelope{}, _state), do: 0

  defp maybe_put_canonical(attrs, %ObservationEnvelope{} = envelope, true) do
    attrs
    |> Map.put(:canonical_observation_id, envelope.observation_id)
    |> Map.put(:canonical_sample_id, envelope.sample_id)
    |> Map.put(:canonical_revision, envelope.revision)
    |> Map.put(:decided_at, envelope.ingested_at)
    |> Map.put(:decision_reason, canonical_reason(envelope))
  end

  defp maybe_put_canonical(attrs, %ObservationEnvelope{}, false), do: attrs

  defp promote_canonical?(%Row{} = row, %ObservationEnvelope{validity_state: :canonical} = env),
    do: is_nil(row.canonical_revision) or env.revision >= row.canonical_revision

  defp promote_canonical?(%Row{}, %ObservationEnvelope{}), do: false

  defp validity_state(_row, %ObservationEnvelope{validity_state: :conflict}), do: "conflict"

  defp validity_state(%Row{conflict_count: count}, _envelope) when count > 0, do: "conflict"
  defp validity_state(_row, %ObservationEnvelope{validity_state: :canonical}), do: "canonical"
  defp validity_state(%Row{validity_state: state}, _envelope), do: state
  defp validity_state(nil, %ObservationEnvelope{validity_state: state}), do: enum_string(state)

  defp canonical_reason(%ObservationEnvelope{revision: 1}), do: "initial_canonical"
  defp canonical_reason(%ObservationEnvelope{}), do: "canonical_revision"

  # #359 (b): a recorded state's payload keeps only what no column holds: a correction's
  # supersession link (`supersedes_observation_id`, present only on a revision). It used to copy
  # six more fields on every row: three of this row's own columns (latest_observation_id,
  # latest_sample_id, the latest validity) and three of the observation's (source_endpoint_id,
  # evidence_id, packet_id). No reader takes those from the payload (re-delivery compares
  # columns; selection reads only the payload's "decision", which a decision adds), and they were
  # most of the payload's ~494 of the row's 1,083 bytes. Rows written before keep their copies
  # until a revision rewrites them; they read the same.
  defp payload(%ObservationEnvelope{supersedes_observation_id: nil}), do: %{}

  defp payload(%ObservationEnvelope{supersedes_observation_id: superseded}),
    do: %{supersedes_observation_id: superseded}

  defp enum_string(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_string(value), do: value

  defp earliest(nil, candidate), do: candidate
  defp earliest(current, nil), do: current

  defp earliest(current, candidate),
    do: if(DateTime.compare(candidate, current) == :lt, do: candidate, else: current)

  defp latest(nil, candidate), do: candidate
  defp latest(current, nil), do: current

  defp latest(current, candidate),
    do: if(DateTime.compare(candidate, current) == :gt, do: candidate, else: current)
end
