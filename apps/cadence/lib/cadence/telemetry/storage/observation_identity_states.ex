defmodule Cadence.Telemetry.Storage.ObservationIdentityStates do
  @moduledoc """
  Current-state projection for telemetry observation identity revisions.

  Append-oriented observation stores keep immutable rows. This projection tracks
  the current canonical row and revision counters per logical observation
  identity so consumers can ask what Cadence currently considers canonical
  without mutating the physical TSDB row.
  """

  alias Ecto.Multi

  import Ecto.Query

  alias Cadence.Dashboards.RuntimeInvalidation
  alias Cadence.Dashboards.TelemetryRevisionSummary
  alias Cadence.Ids
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event, as: OperationalEvent
  alias Cadence.Projections.TelemetryLatestValues

  alias Cadence.Persistence.Schemas.TelemetryObservationIdentityStateRow
  alias Cadence.Repo
  alias Cadence.Telemetry.Storage.ObservationEnvelope
  alias Cadence.Telemetry.Storage.ObservationIdentityDecisionEvent
  alias Cadence.Telemetry.Storage.ObservationIdentityState

  alias Cadence.Telemetry.Storage.ObservationIdentityStates.DecisionEventRow,
    as: TelemetryObservationIdentityDecisionEventRow

  @decisions [:mark_canonical, :mark_conflict, :mark_superseded, :mark_advisory]

  @spec record_envelopes([ObservationEnvelope.t()], keyword()) :: :ok | {:error, term()}
  def record_envelopes(envelopes, opts \\ []) when is_list(envelopes) and is_list(opts) do
    envelopes
    |> Enum.reduce(Multi.new(), fn %ObservationEnvelope{} = envelope, multi ->
      Multi.run(multi, {:observation_identity_state, envelope.observation_id}, fn repo,
                                                                                  _changes ->
        upsert_state(repo, envelope)
      end)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _changes} ->
        invalidate_revision_state(envelopes, opts)
        :ok

      {:error, _operation, reason, _changes_so_far} ->
        {:error, reason}
    end
  end

  @spec fetch(binary()) :: {:ok, ObservationIdentityState.t()} | {:error, term()}
  def fetch(observation_identity_id) when is_binary(observation_identity_id) do
    case Repo.get(TelemetryObservationIdentityStateRow, observation_identity_id) do
      %TelemetryObservationIdentityStateRow{} = row ->
        {:ok, TelemetryObservationIdentityStateRow.to_domain(row)}

      nil ->
        {:error, :observation_identity_state_not_found}
    end
  end

  @spec apply_decision(binary(), atom(), keyword()) ::
          {:ok, ObservationIdentityState.t()} | {:error, term()}
  def apply_decision(observation_identity_id, decision, opts)
      when is_binary(observation_identity_id) and is_atom(decision) and is_list(opts) do
    with :ok <- require_decision(decision),
         :ok <- require_decision_context(opts),
         {:ok, row} <- fetch_row_for_decision(observation_identity_id, opts),
         {:ok, attrs} <- decision_attrs(row, decision, opts),
         {:ok, updated_row} <- persist_decision(row, attrs, decision, opts) do
      state = TelemetryObservationIdentityStateRow.to_domain(updated_row)

      with :ok <- refresh_latest_value(state, opts) do
        invalidate_revision_state_state(state, opts)
        {:ok, state}
      end
    end
  end

  @spec fetch_many([binary()], keyword()) :: [ObservationIdentityState.t()]
  def fetch_many(observation_identity_ids, opts)
      when is_list(observation_identity_ids) and is_list(opts) do
    observation_identity_ids
    |> normalize_identity_ids()
    |> case do
      [] ->
        []

      ids ->
        fetch_many_with_context(ids, opts)
    end
  end

  @spec list_decision_events(binary(), keyword()) :: [ObservationIdentityDecisionEvent.t()]
  def list_decision_events(observation_identity_id, opts)
      when is_binary(observation_identity_id) and is_list(opts) do
    if required_context?(opts) do
      TelemetryObservationIdentityDecisionEventRow
      |> where([row], row.observation_identity_id == ^observation_identity_id)
      |> filter(:organization_id, Keyword.get(opts, :organization_id))
      |> filter(:mission_id, Keyword.get(opts, :mission_id))
      |> filter(:realm, Keyword.get(opts, :realm))
      |> filter(:replay_run_id, Keyword.get(opts, :replay_run_id))
      |> filter(:data_source_id, Keyword.get(opts, :data_source_id))
      |> filter(:binding_id, Keyword.get(opts, :binding_id))
      |> order_by([row], asc: row.occurred_at, asc: row.decision_event_id)
      |> limit(^result_limit(opts))
      |> Repo.all()
      |> Enum.map(&TelemetryObservationIdentityDecisionEventRow.to_domain/1)
    else
      []
    end
  end

  @spec list_scoped_decision_events(binary(), keyword()) :: [ObservationIdentityDecisionEvent.t()]
  def list_scoped_decision_events(mission_id, opts)
      when is_binary(mission_id) and is_list(opts) do
    if required_context?(Keyword.put(opts, :mission_id, mission_id)) do
      TelemetryObservationIdentityDecisionEventRow
      |> where([row], row.mission_id == ^mission_id)
      |> filter(:organization_id, Keyword.get(opts, :organization_id))
      |> filter(:realm, Keyword.get(opts, :realm))
      |> filter(:replay_run_id, Keyword.get(opts, :replay_run_id))
      |> filter(:data_source_id, Keyword.get(opts, :data_source_id))
      |> filter(:binding_id, Keyword.get(opts, :binding_id))
      |> filter(:observation_identity_id, Keyword.get(opts, :observation_identity_id))
      |> filter(:observable_id, Keyword.get(opts, :observable_id))
      |> filter(:point_id, Keyword.get(opts, :point_id))
      |> filter(:spacecraft_id, Keyword.get(opts, :spacecraft_id))
      |> filter(:decision, Keyword.get(opts, :decision))
      |> maybe_from_occurred_at(Keyword.get(opts, :from_occurred_at))
      |> maybe_to_occurred_at(Keyword.get(opts, :to_occurred_at))
      |> order_by([row], asc: row.occurred_at, asc: row.decision_event_id)
      |> limit(^result_limit(opts))
      |> Repo.all()
      |> Enum.map(&TelemetryObservationIdentityDecisionEventRow.to_domain/1)
    else
      []
    end
  end

  @spec fetch_decision_event(binary(), keyword()) :: ObservationIdentityDecisionEvent.t() | nil
  def fetch_decision_event(decision_event_id, opts)
      when is_binary(decision_event_id) and is_list(opts) do
    organization_id = Keyword.get(opts, :organization_id)
    mission_id = Keyword.get(opts, :mission_id)

    if required_context?(opts) do
      TelemetryObservationIdentityDecisionEventRow
      |> where(
        [row],
        row.decision_event_id == ^decision_event_id and
          row.organization_id == ^organization_id and row.mission_id == ^mission_id
      )
      |> Repo.one()
      |> case do
        %TelemetryObservationIdentityDecisionEventRow{} = row ->
          TelemetryObservationIdentityDecisionEventRow.to_domain(row)

        nil ->
          nil
      end
    end
  end

  @spec list(binary(), keyword()) :: [ObservationIdentityState.t()]
  def list(mission_id, opts \\ []) when is_binary(mission_id) and is_list(opts) do
    TelemetryObservationIdentityStateRow
    |> where([row], row.mission_id == ^mission_id)
    |> filter(:organization_id, Keyword.get(opts, :organization_id))
    |> filter(:realm, Keyword.get(opts, :realm))
    |> filter(:replay_run_id, Keyword.get(opts, :replay_run_id))
    |> filter(:data_source_id, Keyword.get(opts, :data_source_id))
    |> filter(:binding_id, Keyword.get(opts, :binding_id))
    |> filter(:observable_id, Keyword.get(opts, :observable_id))
    |> filter(:point_id, Keyword.get(opts, :point_id))
    |> filter(:spacecraft_id, Keyword.get(opts, :spacecraft_id))
    |> filter(:validity_state, Keyword.get(opts, :validity_state))
    |> order_by([row],
      asc: row.point_id,
      asc: row.spacecraft_id,
      asc: row.observation_identity_id
    )
    |> limit(^result_limit(opts))
    |> Repo.all()
    |> Enum.map(&TelemetryObservationIdentityStateRow.to_domain/1)
  end

  defp upsert_state(repo, %ObservationEnvelope{} = envelope) do
    case repo.get(TelemetryObservationIdentityStateRow, envelope.observation_identity_id) do
      nil ->
        insert_state(repo, envelope)

      %TelemetryObservationIdentityStateRow{} = row
      when row.latest_observation_id == envelope.observation_id or
             row.canonical_observation_id == envelope.observation_id ->
        {:ok, row}

      %TelemetryObservationIdentityStateRow{} = row ->
        update_state(repo, row, envelope)
    end
  end

  defp insert_state(repo, %ObservationEnvelope{} = envelope) do
    %TelemetryObservationIdentityStateRow{}
    |> TelemetryObservationIdentityStateRow.changeset(initial_attrs(envelope))
    |> repo.insert()
  end

  defp update_state(
         repo,
         %TelemetryObservationIdentityStateRow{} = row,
         %ObservationEnvelope{} = envelope
       ) do
    row
    |> TelemetryObservationIdentityStateRow.changeset(updated_attrs(row, envelope))
    |> repo.update()
  end

  defp initial_attrs(%ObservationEnvelope{} = envelope) do
    base_attrs(envelope)
    |> Map.merge(count_attrs(envelope))
    |> maybe_put_canonical(envelope, canonical_envelope?(envelope))
    |> Map.put(:validity_state, validity_state(nil, envelope))
  end

  defp updated_attrs(
         %TelemetryObservationIdentityStateRow{} = row,
         %ObservationEnvelope{} = envelope
       ) do
    row
    |> Map.from_struct()
    |> Map.take(schema_fields())
    |> Map.merge(base_attrs(envelope))
    |> merge_counts(envelope)
    |> maybe_put_canonical(envelope, promote_canonical?(row, envelope))
    |> Map.put(:validity_state, validity_state(row, envelope))
    |> Map.put(:first_seen_at, earliest(row.first_seen_at, envelope.ingested_at))
    |> Map.put(:last_seen_at, latest(row.last_seen_at, envelope.ingested_at))
    |> Map.put(:payload, payload(envelope))
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

  defp count_attrs(%ObservationEnvelope{} = envelope) do
    %{
      canonical_count: count(envelope, :canonical),
      duplicate_count: count(envelope, :duplicate),
      conflict_count: count(envelope, :conflict),
      superseded_count: count(envelope, :superseded),
      advisory_count: count(envelope, :advisory)
    }
  end

  defp merge_counts(attrs, %ObservationEnvelope{} = envelope) do
    attrs
    |> Map.update!(:canonical_count, &(&1 + count(envelope, :canonical)))
    |> Map.update!(:duplicate_count, &(&1 + count(envelope, :duplicate)))
    |> Map.update!(:conflict_count, &(&1 + count(envelope, :conflict)))
    |> Map.update!(:superseded_count, &(&1 + count(envelope, :superseded)))
    |> Map.update!(:advisory_count, &(&1 + count(envelope, :advisory)))
  end

  defp count(%ObservationEnvelope{validity_state: state}, state), do: 1
  defp count(%ObservationEnvelope{}, _state), do: 0

  defp maybe_put_canonical(attrs, %ObservationEnvelope{} = envelope, true) do
    attrs
    |> Map.put(:canonical_observation_id, envelope.observation_id)
    |> Map.put(:canonical_sample_id, envelope.sample_id)
    |> Map.put(:canonical_revision, envelope.revision)
    |> Map.put(:decided_at, envelope.ingested_at)
    |> Map.put(:decision_reason, decision_reason(envelope))
  end

  defp maybe_put_canonical(attrs, %ObservationEnvelope{}, false), do: attrs

  defp canonical_envelope?(%ObservationEnvelope{validity_state: :canonical}), do: true
  defp canonical_envelope?(%ObservationEnvelope{}), do: false

  defp promote_canonical?(
         %TelemetryObservationIdentityStateRow{} = row,
         %ObservationEnvelope{validity_state: :canonical} = envelope
       ) do
    is_nil(row.canonical_revision) or envelope.revision >= row.canonical_revision
  end

  defp promote_canonical?(
         %TelemetryObservationIdentityStateRow{},
         %ObservationEnvelope{}
       ),
       do: false

  defp validity_state(_row, %ObservationEnvelope{validity_state: :conflict}), do: "conflict"

  defp validity_state(%TelemetryObservationIdentityStateRow{conflict_count: count}, _envelope)
       when count > 0,
       do: "conflict"

  defp validity_state(_row, %ObservationEnvelope{validity_state: :canonical}), do: "canonical"

  defp validity_state(%TelemetryObservationIdentityStateRow{validity_state: state}, _envelope),
    do: state

  defp validity_state(nil, %ObservationEnvelope{validity_state: state}), do: enum_string(state)

  defp decision_reason(%ObservationEnvelope{validity_state: :canonical, revision: 1}),
    do: "initial_canonical"

  defp decision_reason(%ObservationEnvelope{validity_state: :canonical}),
    do: "canonical_revision"

  defp payload(%ObservationEnvelope{} = envelope) do
    %{
      latest_observation_id: envelope.observation_id,
      latest_sample_id: envelope.sample_id,
      latest_validity_state: envelope.validity_state,
      supersedes_observation_id: envelope.supersedes_observation_id,
      source_endpoint_id: envelope.source_endpoint_id,
      evidence_id: envelope.evidence_id,
      packet_id: envelope.packet_id
    }
  end

  defp schema_fields do
    [
      :observation_identity_id,
      :organization_id,
      :mission_id,
      :realm,
      :replay_run_id,
      :data_source_id,
      :binding_id,
      :observable_id,
      :point_id,
      :spacecraft_id,
      :canonical_observation_id,
      :canonical_sample_id,
      :canonical_revision,
      :latest_observation_id,
      :latest_sample_id,
      :latest_revision,
      :validity_state,
      :canonical_count,
      :duplicate_count,
      :conflict_count,
      :superseded_count,
      :advisory_count,
      :first_seen_at,
      :last_seen_at,
      :decided_at,
      :decision_reason,
      :payload
    ]
  end

  defp enum_string(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_string(value), do: value

  defp require_decision(decision) when decision in @decisions, do: :ok
  defp require_decision(decision), do: {:error, {:unsupported_decision, decision}}

  defp require_decision_context(opts) do
    cond do
      not present?(Keyword.get(opts, :organization_id)) ->
        {:error, {:missing_field, :organization_id}}

      not present?(Keyword.get(opts, :mission_id)) ->
        {:error, {:missing_field, :mission_id}}

      true ->
        :ok
    end
  end

  defp fetch_row_for_decision(observation_identity_id, opts) do
    TelemetryObservationIdentityStateRow
    |> where([row], row.observation_identity_id == ^observation_identity_id)
    |> filter(:organization_id, Keyword.fetch!(opts, :organization_id))
    |> filter(:mission_id, Keyword.fetch!(opts, :mission_id))
    |> filter(:realm, Keyword.get(opts, :realm))
    |> filter(:replay_run_id, Keyword.get(opts, :replay_run_id))
    |> filter(:data_source_id, Keyword.get(opts, :data_source_id))
    |> filter(:binding_id, Keyword.get(opts, :binding_id))
    |> Repo.one()
    |> case do
      %TelemetryObservationIdentityStateRow{} = row -> {:ok, row}
      nil -> {:error, :observation_identity_state_not_found}
    end
  end

  defp decision_attrs(%TelemetryObservationIdentityStateRow{} = row, decision, opts) do
    decided_at = Keyword.get(opts, :decided_at, DateTime.utc_now())
    reason = decision_reason(decision, opts)
    decision_event_id = decision_event_id(opts)

    attrs =
      row
      |> Map.from_struct()
      |> Map.take(schema_fields())
      |> Map.merge(%{
        validity_state: decision_validity_state(decision),
        decided_at: decided_at,
        decision_event_id: decision_event_id,
        decision_reason: reason,
        payload: decision_payload(row, decision, reason, decided_at, opts)
      })
      |> maybe_merge_canonical_decision(decision, opts)

    with :ok <- validate_canonical_decision(attrs, decision) do
      {:ok, attrs}
    end
  end

  defp persist_decision(%TelemetryObservationIdentityStateRow{} = row, attrs, decision, opts) do
    Multi.new()
    |> Multi.update(
      :observation_identity_state,
      TelemetryObservationIdentityStateRow.changeset(row, attrs)
    )
    |> Multi.insert(:observation_identity_decision_event, fn %{
                                                               observation_identity_state:
                                                                 updated_row
                                                             } ->
      row
      |> decision_event(updated_row, decision, opts)
      |> TelemetryObservationIdentityDecisionEventRow.changeset()
    end)
    |> Multi.run(:operational_event, fn repo, %{observation_identity_decision_event: event_row} ->
      event_row
      |> TelemetryObservationIdentityDecisionEventRow.to_domain()
      |> OperationalEvent.from_observation_identity_decision_event()
      |> then(&OperationalEvents.persist_event(repo, &1))
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{observation_identity_state: updated_row}} ->
        {:ok, updated_row}

      {:error, _operation, reason, _changes_so_far} ->
        {:error, reason}
    end
  end

  defp decision_validity_state(:mark_canonical), do: "canonical"
  defp decision_validity_state(:mark_conflict), do: "conflict"
  defp decision_validity_state(:mark_superseded), do: "superseded"
  defp decision_validity_state(:mark_advisory), do: "advisory"

  defp decision_reason(decision, opts) do
    Keyword.get(opts, :decision_reason) ||
      Keyword.get(opts, :reason) ||
      Atom.to_string(decision)
  end

  defp decision_event_id(opts) do
    Keyword.get(opts, :decision_event_id) ||
      Keyword.get(opts, :telemetry_observation_identity_decision_event_id) ||
      Ids.new("telemetry_observation_identity_decision_event")
  end

  defp maybe_merge_canonical_decision(attrs, :mark_canonical, opts) do
    attrs
    |> maybe_put_opt(:canonical_observation_id, opts)
    |> maybe_put_opt(:canonical_sample_id, opts)
    |> maybe_put_opt(:canonical_revision, opts)
  end

  defp maybe_merge_canonical_decision(attrs, _decision, _opts), do: attrs

  defp maybe_put_opt(attrs, field, opts) do
    case Keyword.get(opts, field) do
      nil -> attrs
      value -> Map.put(attrs, field, value)
    end
  end

  defp validate_canonical_decision(attrs, :mark_canonical) do
    cond do
      not present?(Map.get(attrs, :canonical_observation_id)) ->
        {:error, {:missing_field, :canonical_observation_id}}

      not present?(Map.get(attrs, :canonical_sample_id)) ->
        {:error, {:missing_field, :canonical_sample_id}}

      not is_integer(Map.get(attrs, :canonical_revision)) ->
        {:error, {:missing_field, :canonical_revision}}

      Map.get(attrs, :canonical_revision) <= 0 ->
        {:error, {:invalid_field, :canonical_revision}}

      true ->
        :ok
    end
  end

  defp validate_canonical_decision(_attrs, _decision), do: :ok

  defp decision_payload(
         %TelemetryObservationIdentityStateRow{} = row,
         decision,
         reason,
         decided_at,
         opts
       ) do
    row.payload
    |> ensure_map()
    |> Map.put("decision", %{
      "decision" => Atom.to_string(decision),
      "reason" => reason,
      "decided_at" => DateTime.to_iso8601(decided_at),
      "operator_id" => Keyword.get(opts, :operator_id),
      "evidence_ref" => Keyword.get(opts, :evidence_ref)
    })
  end

  defp decision_event(
         %TelemetryObservationIdentityStateRow{} = previous_row,
         %TelemetryObservationIdentityStateRow{} = updated_row,
         decision,
         opts
       ) do
    updated_state = TelemetryObservationIdentityStateRow.to_domain(updated_row)
    actor_id = Keyword.get(opts, :actor_id) || Keyword.get(opts, :operator_id)

    ObservationIdentityDecisionEvent.new(%{
      decision_event_id: updated_row.decision_event_id,
      observation_identity_id: updated_row.observation_identity_id,
      organization_id: updated_row.organization_id,
      mission_id: updated_row.mission_id,
      realm: updated_row.realm,
      replay_run_id: updated_row.replay_run_id,
      data_source_id: updated_row.data_source_id,
      binding_id: updated_row.binding_id,
      observable_id: updated_row.observable_id,
      point_id: updated_row.point_id,
      spacecraft_id: updated_row.spacecraft_id,
      decision: decision,
      decision_reason: updated_row.decision_reason,
      actor_id: actor_id,
      actor_kind: actor_kind(opts, actor_id),
      evidence_ref: evidence_ref(opts),
      previous_state: state_snapshot(previous_row),
      new_state: state_snapshot(updated_state),
      occurred_at: updated_row.decided_at || DateTime.utc_now()
    })
  end

  defp actor_kind(opts, actor_id) do
    cond do
      present?(Keyword.get(opts, :actor_kind)) -> Keyword.get(opts, :actor_kind)
      present?(actor_id) -> "operator"
      true -> "system"
    end
  end

  defp evidence_ref(opts) do
    case Keyword.get(opts, :evidence_ref, %{}) do
      nil -> %{}
      evidence_ref -> evidence_ref
    end
  end

  defp state_snapshot(%TelemetryObservationIdentityStateRow{} = row) do
    row
    |> TelemetryObservationIdentityStateRow.to_domain()
    |> state_snapshot()
  end

  defp state_snapshot(%ObservationIdentityState{} = state) do
    state
    |> Map.from_struct()
    |> Map.delete(:payload)
    |> Map.put(:payload, state.payload || %{})
  end

  defp ensure_map(map) when is_map(map), do: map
  defp ensure_map(_value), do: %{}

  defp invalidate_revision_state([], _opts), do: :ok

  defp invalidate_revision_state(envelopes, opts) do
    if Keyword.get(opts, :dashboard_runtime_invalidation?, true) do
      invalidation_opts = Keyword.take(opts, [:runtime_cache])

      envelopes
      |> Enum.group_by(&revision_invalidation_group_key/1)
      |> Enum.each(fn {_group_key, [%ObservationEnvelope{} = envelope | _rest]} ->
        envelope
        |> revision_invalidation_filters()
        |> RuntimeInvalidation.telemetry_revision_state_changed(invalidation_opts)
      end)
    end

    :ok
  end

  defp refresh_latest_value(%ObservationIdentityState{} = state, opts) do
    if Keyword.get(opts, :refresh_latest_value?, true) do
      refresh_opts = Keyword.put(opts, :spacecraft_id, state.spacecraft_id)

      case TelemetryLatestValues.refresh_point(state.mission_id, state.point_id, refresh_opts) do
        {:ok, _sample_or_nil} -> :ok
        {:error, reason} -> {:error, {:latest_value_refresh_failed, reason}}
      end
    else
      :ok
    end
  end

  defp invalidate_revision_state_state(%ObservationIdentityState{} = state, opts) do
    if Keyword.get(opts, :dashboard_runtime_invalidation?, true) do
      dependency = TelemetryRevisionSummary.from_identity_states([state]).dependency

      state
      |> revision_invalidation_filters()
      |> Map.put(:telemetry_revision_dependency, dependency)
      |> RuntimeInvalidation.telemetry_revision_state_changed(
        Keyword.take(opts, [:runtime_cache])
      )
    end

    :ok
  end

  defp revision_invalidation_group_key(%ObservationEnvelope{} = envelope) do
    {
      envelope.organization_id,
      envelope.mission_id,
      envelope.data_source_id,
      envelope.binding_id,
      envelope.realm,
      envelope.replay_run_id,
      envelope.observable_id,
      envelope.observation_identity_id
    }
  end

  defp revision_invalidation_filters(%ObservationEnvelope{} = envelope) do
    %{
      organization_id: envelope.organization_id,
      mission_id: envelope.mission_id,
      logical_source: :telemetry,
      data_source_id: envelope.data_source_id,
      source_binding_id: envelope.binding_id,
      realm: envelope.realm,
      replay_run_id: envelope.replay_run_id,
      observable: envelope.observable_id,
      observation_identity_id: envelope.observation_identity_id
    }
  end

  defp revision_invalidation_filters(%ObservationIdentityState{} = state) do
    %{
      organization_id: state.organization_id,
      mission_id: state.mission_id,
      logical_source: :telemetry,
      data_source_id: state.data_source_id,
      source_binding_id: state.binding_id,
      realm: state.realm,
      replay_run_id: state.replay_run_id,
      observable: state.observable_id,
      observation_identity_id: state.observation_identity_id
    }
  end

  defp normalize_identity_ids(observation_identity_ids) do
    observation_identity_ids
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
  end

  defp fetch_many_with_context(ids, opts) do
    if required_context?(opts) do
      TelemetryObservationIdentityStateRow
      |> where([row], row.observation_identity_id in ^ids)
      |> filter(:organization_id, Keyword.get(opts, :organization_id))
      |> filter(:mission_id, Keyword.get(opts, :mission_id))
      |> filter(:realm, Keyword.get(opts, :realm))
      |> filter(:replay_run_id, Keyword.get(opts, :replay_run_id))
      |> filter(:data_source_id, Keyword.get(opts, :data_source_id))
      |> filter(:binding_id, Keyword.get(opts, :binding_id))
      |> order_by([row], asc: row.observation_identity_id)
      |> Repo.all()
      |> Enum.map(&TelemetryObservationIdentityStateRow.to_domain/1)
    else
      []
    end
  end

  defp required_context?(opts) do
    present?(Keyword.get(opts, :organization_id)) and present?(Keyword.get(opts, :mission_id))
  end

  defp present?(value), do: is_binary(value) and value != ""

  defp filter(query, _field, nil), do: query

  defp filter(query, field, value) do
    normalized_value = enum_string(value)
    where(query, [row], field(row, ^field) == ^normalized_value)
  end

  defp maybe_from_occurred_at(query, %DateTime{} = from_occurred_at) do
    where(query, [row], row.occurred_at >= ^from_occurred_at)
  end

  defp maybe_from_occurred_at(query, _from_occurred_at), do: query

  defp maybe_to_occurred_at(query, %DateTime{} = to_occurred_at) do
    where(query, [row], row.occurred_at < ^to_occurred_at)
  end

  defp maybe_to_occurred_at(query, _to_occurred_at), do: query

  defp result_limit(opts) do
    opts
    |> Keyword.get(:limit, 500)
    |> min(1_000)
    |> max(1)
  end

  defp earliest(nil, candidate), do: candidate
  defp earliest(current, nil), do: current

  defp earliest(current, candidate),
    do: if(DateTime.compare(candidate, current) == :lt, do: candidate, else: current)

  defp latest(nil, candidate), do: candidate
  defp latest(current, nil), do: current

  defp latest(current, candidate),
    do: if(DateTime.compare(candidate, current) == :gt, do: candidate, else: current)
end
