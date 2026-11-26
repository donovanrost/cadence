defmodule Cadence.Telemetry.Storage.ObservationIdentityStates.Decisions do
  @moduledoc """
  Operator decisions on an observation identity's state.

  Since the first-seen rule (11-17) an identity may have no row yet. `seed/2` then reads the
  observation's facts through `DecisionSeed`, BEFORE any Postgres transaction opens; `persist/4`
  creates the row from them with ON CONFLICT DO NOTHING (a batch or decision that created it first
  wins), locks the scoped row and applies the decision, its decision event and its operational
  event in one transaction. Any error writes nothing.
  """

  import Ecto.Query

  alias Cadence.Ids
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event, as: OperationalEvent
  alias Cadence.Repo
  alias Cadence.Telemetry.Storage.ObservationIdentityDecisionEvent
  alias Cadence.Telemetry.Storage.ObservationIdentityState
  alias Cadence.Telemetry.Storage.ObservationIdentityStates.DecisionEventRow
  alias Cadence.Telemetry.Storage.ObservationIdentityStates.DecisionSeed

  alias Cadence.Telemetry.Storage.ObservationIdentityStates.TelemetryObservationIdentityStateRow,
    as: Row

  @decisions [:mark_canonical, :mark_conflict, :mark_superseded, :mark_advisory]

  @spec validate(atom(), keyword()) :: :ok | {:error, term()}
  def validate(decision, opts) do
    with :ok <- require_decision(decision) do
      require_decision_context(opts)
    end
  end

  @doc "nil when the scoped row exists; else the row to create, read from the observation."
  @spec seed(binary(), keyword()) :: {:ok, map() | nil} | {:error, term()}
  def seed(observation_identity_id, opts) do
    if observation_identity_id |> scoped_row_query(opts) |> Repo.exists?(),
      do: {:ok, nil},
      else: DecisionSeed.facts(observation_identity_id, opts)
  end

  @spec persist(binary(), map() | nil, atom(), keyword()) :: {:ok, struct()} | {:error, term()}
  def persist(observation_identity_id, seed, decision, opts) do
    Repo.transaction(fn ->
      with :ok <- insert_seed(seed),
           {:ok, row} <- lock_scoped_row(observation_identity_id, opts),
           {:ok, attrs} <- decision_attrs(row, decision, opts),
           {:ok, updated_row} <- persist_decision(row, attrs, decision, opts) do
        updated_row
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

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

  defp scoped_row_query(observation_identity_id, opts) do
    Row
    |> where([row], row.observation_identity_id == ^observation_identity_id)
    |> filter(:organization_id, Keyword.fetch!(opts, :organization_id))
    |> filter(:mission_id, Keyword.fetch!(opts, :mission_id))
    |> filter(:realm, Keyword.get(opts, :realm))
    |> filter(:replay_run_id, Keyword.get(opts, :replay_run_id))
    |> filter(:data_source_id, Keyword.get(opts, :data_source_id))
    |> filter(:binding_id, Keyword.get(opts, :binding_id))
  end

  defp lock_scoped_row(observation_identity_id, opts) do
    observation_identity_id
    |> scoped_row_query(opts)
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> case do
      %Row{} = row -> {:ok, row}
      nil -> {:error, :observation_identity_state_not_found}
    end
  end

  # A batch or another decision that created the row first wins; this decision then applies to
  # that row under its lock.
  defp insert_seed(nil), do: :ok

  defp insert_seed(seed) do
    {_count, _rows} =
      Repo.insert_all(Row, [seed],
        on_conflict: :nothing,
        conflict_target: [:observation_identity_id]
      )

    :ok
  end

  defp decision_attrs(%Row{} = row, decision, opts) do
    decided_at = Keyword.get(opts, :decided_at, DateTime.utc_now())
    reason = decision_reason(decision, opts)
    decision_event_id = decision_event_id(opts)

    attrs =
      row
      |> Map.from_struct()
      |> Map.take(Row.fields())
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

  defp persist_decision(%Row{} = row, attrs, decision, opts) do
    with {:ok, updated_row} <- Repo.update(Row.changeset(row, attrs)),
         {:ok, event_row} <-
           row
           |> decision_event(updated_row, decision, opts)
           |> DecisionEventRow.changeset()
           |> Repo.insert(),
         {:ok, _event} <-
           event_row
           |> DecisionEventRow.to_domain()
           |> OperationalEvent.from_observation_identity_decision_event()
           |> then(&OperationalEvents.persist_event(Repo, &1)) do
      {:ok, updated_row}
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
         %Row{} = row,
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
         %Row{} = previous_row,
         %Row{} = updated_row,
         decision,
         opts
       ) do
    updated_state = Row.to_domain(updated_row)
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

  defp state_snapshot(%Row{} = row) do
    row
    |> Row.to_domain()
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

  defp present?(value), do: is_binary(value) and value != ""

  defp filter(query, _field, nil), do: query

  defp filter(query, field, value) do
    normalized_value = enum_string(value)
    where(query, [row], field(row, ^field) == ^normalized_value)
  end

  defp enum_string(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_string(value), do: value
end
