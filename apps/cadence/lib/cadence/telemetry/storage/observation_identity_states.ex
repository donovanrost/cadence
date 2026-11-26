defmodule Cadence.Telemetry.Storage.ObservationIdentityStates do
  @moduledoc """
  Current-state projection for telemetry observation identity revisions.

  Append-oriented observation stores keep immutable rows. This projection tracks
  the current canonical row and revision counters per logical observation
  identity so consumers can ask what Cadence currently considers canonical
  without mutating the physical TSDB row.

  A row exists only for an identity something has been said about (the first-seen rule, 11-17):
  a decision, or a non-canonical sighting. A canonical sighting of an identity with no row writes
  nothing; readers treat such a sample by its own validity. `EnvelopeWrites` holds the batch
  write path, `Decisions` and `DecisionSeed` the decision path.
  """

  import Ecto.Query

  alias Cadence.Platform.EventBus

  alias Cadence.Repo

  alias Cadence.Telemetry.{
    Facts,
    ObservationIdentityDependency,
    ObservationIdentitySelectionChanged,
    ObservationIdentityStateChanged
  }

  alias Cadence.Telemetry.Storage.ObservationEnvelope
  alias Cadence.Telemetry.Storage.ObservationIdentityDecisionEvent
  alias Cadence.Telemetry.Storage.ObservationIdentityState

  alias Cadence.Telemetry.Storage.ObservationIdentityStates.DecisionEventRow,
    as: TelemetryObservationIdentityDecisionEventRow

  alias Cadence.Telemetry.Storage.ObservationIdentityStates.Decisions
  alias Cadence.Telemetry.Storage.ObservationIdentityStates.EnvelopeWrites
  alias Cadence.Telemetry.Storage.ObservationIdentityStates.TelemetryObservationIdentityStateRow

  @spec record_envelopes([ObservationEnvelope.t()], keyword()) :: :ok | {:error, term()}
  def record_envelopes(envelopes, opts \\ []) when is_list(envelopes) and is_list(opts) do
    opts = Keyword.put_new(opts, :event_bus, EventBus)

    Repo.transaction(fn ->
      case EnvelopeWrites.record(Repo, envelopes) do
        {:ok, changed} -> changed
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, changed} ->
        publish_envelope_state_changes(envelopes, changed, opts)
        :ok

      {:error, reason} ->
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
    opts = Keyword.put_new(opts, :event_bus, EventBus)

    with :ok <- Decisions.validate(decision, opts),
         {:ok, seed} <- Decisions.seed(observation_identity_id, opts),
         {:ok, updated_row} <- Decisions.persist(observation_identity_id, seed, decision, opts) do
      state = TelemetryObservationIdentityStateRow.to_domain(updated_row)

      publish_state_changed(state, opts)
      publish_latest_value_refresh(state, opts)
      {:ok, state}
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

  @doc """
  Returns the identity states needed for effective telemetry selection.

  With `:observation_identity_ids`, only those identities' states (a primary-key lookup): a
  history read passes the identities of the rows it fetched, since a sample's selection depends
  only on its own identity's state. Without it, every state matching the filters (a point's
  whole history: avoid on a hot read path).
  """
  @spec list_for_selection(binary(), keyword()) :: [ObservationIdentityState.t()]
  def list_for_selection(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    case Keyword.fetch(opts, :observation_identity_ids) do
      {:ok, ids} when is_list(ids) ->
        case normalize_identity_ids(ids) do
          [] ->
            []

          ids ->
            mission_id
            |> selection_query(opts)
            |> where([row], row.observation_identity_id in ^ids)
            |> load_states()
        end

      :error ->
        mission_id |> selection_query(opts) |> load_states()
    end
  end

  defp selection_query(mission_id, opts) do
    TelemetryObservationIdentityStateRow
    |> where([row], row.mission_id == ^mission_id)
    |> filter(:organization_id, Keyword.get(opts, :organization_id))
    |> filter(:realm, Keyword.get(opts, :realm))
    |> filter(:replay_run_id, Keyword.get(opts, :replay_run_id))
    |> filter(:data_source_id, Keyword.get(opts, :data_source_id))
    |> filter(:binding_id, Keyword.get(opts, :binding_id))
    |> filter(:point_id, Keyword.get(opts, :point_id))
    |> filter(:spacecraft_id, Keyword.get(opts, :spacecraft_id))
  end

  defp load_states(query) do
    query
    |> Repo.all()
    |> Enum.map(&TelemetryObservationIdentityStateRow.to_domain/1)
  end

  defp enum_string(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_string(value), do: value

  defp publish_latest_value_refresh(%ObservationIdentityState{} = state, opts) do
    if Keyword.get(opts, :refresh_latest_value?, true) do
      Facts.publish(Keyword.fetch!(opts, :event_bus), %ObservationIdentitySelectionChanged{
        observation_identity_id: state.observation_identity_id,
        organization_id: state.organization_id,
        mission_id: state.mission_id,
        point_id: state.point_id,
        spacecraft_id: state.spacecraft_id,
        realm: state.realm,
        replay_run_id: state.replay_run_id,
        data_source_id: state.data_source_id,
        binding_id: state.binding_id,
        committed_at: DateTime.utc_now()
      })
    end

    :ok
  end

  # One fact per identity whose stored state this batch changed (#689), not one per sample: a
  # batch that stored nothing publishes nothing. Each fact is a call into the node's event bus.
  defp publish_envelope_state_changes(envelopes, changed, opts) do
    if publish_state_facts?(opts) and MapSet.size(changed) > 0 do
      envelopes
      |> Enum.filter(&MapSet.member?(changed, &1.observation_identity_id))
      |> Enum.uniq_by(& &1.observation_identity_id)
      |> Enum.each(fn %ObservationEnvelope{} = envelope ->
        Facts.publish(Keyword.fetch!(opts, :event_bus), %ObservationIdentityStateChanged{
          observation_identity_id: envelope.observation_identity_id,
          organization_id: envelope.organization_id,
          mission_id: envelope.mission_id,
          point_id: envelope.observable_id,
          spacecraft_id: envelope.spacecraft_id,
          realm: envelope.realm,
          replay_run_id: envelope.replay_run_id,
          data_source_id: envelope.data_source_id,
          binding_id: envelope.binding_id,
          dependency: nil,
          committed_at: envelope.ingested_at
        })
      end)
    end

    :ok
  end

  defp publish_state_changed(%ObservationIdentityState{} = state, opts) do
    if publish_state_facts?(opts) do
      Facts.publish(Keyword.fetch!(opts, :event_bus), %ObservationIdentityStateChanged{
        observation_identity_id: state.observation_identity_id,
        organization_id: state.organization_id,
        mission_id: state.mission_id,
        point_id: state.point_id,
        spacecraft_id: state.spacecraft_id,
        realm: state.realm,
        replay_run_id: state.replay_run_id,
        data_source_id: state.data_source_id,
        binding_id: state.binding_id,
        dependency: ObservationIdentityDependency.from_states([state]),
        committed_at: DateTime.utc_now()
      })
    end

    :ok
  end

  defp publish_state_facts?(opts) do
    Keyword.get(
      opts,
      :publish_facts?,
      Keyword.get(opts, :dashboard_runtime_invalidation?, true)
    )
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
end
