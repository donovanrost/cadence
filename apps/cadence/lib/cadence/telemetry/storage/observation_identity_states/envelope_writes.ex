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

  Existing rows are locked once per batch, in identity order. A new non-canonical row is inserted
  with ON CONFLICT DO NOTHING: a concurrent batch or decision that created it first wins, and this
  sighting then updates that row under its lock, so the unique key never raises.
  """

  import Ecto.Query

  alias Cadence.Telemetry.Storage.ObservationEnvelope

  alias Cadence.Telemetry.Storage.ObservationIdentityStates.TelemetryObservationIdentityStateRow,
    as: Row

  @spec record(module(), [ObservationEnvelope.t()]) :: :ok | {:error, term()}
  def record(repo, envelopes) when is_list(envelopes) do
    rows = lock_existing(repo, envelopes)

    envelopes
    |> Enum.reduce_while({:ok, rows}, fn envelope, {:ok, rows} ->
      id = envelope.observation_identity_id

      case record_envelope(repo, envelope, Map.get(rows, id)) do
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

  defp lock_existing(repo, envelopes) do
    case envelopes |> Enum.map(& &1.observation_identity_id) |> Enum.uniq() do
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

  defp record_envelope(repo, %ObservationEnvelope{} = envelope, nil),
    do: insert_new(repo, envelope)

  defp record_envelope(_repo, envelope, %Row{} = row)
       when row.latest_observation_id == envelope.observation_id or
              row.canonical_observation_id == envelope.observation_id,
       do: {:ok, row}

  defp record_envelope(repo, envelope, %Row{} = row) do
    row
    |> Row.changeset(updated_attrs(row, envelope))
    |> repo.update()
  end

  defp insert_new(repo, envelope) do
    changeset = Row.changeset(%Row{}, initial_attrs(envelope))

    with {:ok, %Row{} = row} <- Ecto.Changeset.apply_action(changeset, :insert) do
      now = DateTime.utc_now()
      attrs = row |> Map.take(Row.fields()) |> Map.merge(%{inserted_at: now, updated_at: now})

      case repo.insert_all(Row, [attrs],
             on_conflict: :nothing,
             conflict_target: [:observation_identity_id],
             returning: true
           ) do
        {1, [%Row{} = inserted]} -> {:ok, inserted}
        {0, []} -> record_after_conflict(repo, envelope)
      end
    end
  end

  # Another transaction committed this identity's row after our batch lock: update it under its
  # own lock. A row deleted again in between (the 96 h prune) is not this sighting's to recreate.
  defp record_after_conflict(repo, envelope) do
    case lock_row(repo, envelope.observation_identity_id) do
      %Row{} = row -> record_envelope(repo, envelope, row)
      nil -> {:error, {:observation_identity_state_conflict, envelope.observation_identity_id}}
    end
  end

  defp initial_attrs(%ObservationEnvelope{} = envelope) do
    envelope
    |> base_attrs()
    |> Map.merge(count_attrs(envelope))
    |> maybe_put_canonical(envelope, envelope.validity_state == :canonical)
    |> Map.put(:validity_state, validity_state(nil, envelope))
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
