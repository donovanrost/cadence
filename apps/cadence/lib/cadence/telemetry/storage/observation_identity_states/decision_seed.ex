defmodule Cadence.Telemetry.Storage.ObservationIdentityStates.DecisionSeed do
  @moduledoc """
  The row a decision creates for an identity that has none (the first-seen rule, 11-17: a
  canonical sighting with no decision writes no row).

  The facts come from the observation itself, through the history store's exact physical lookup,
  read BEFORE the decision's Postgres transaction opens. The lookup is scoped by the decision
  context (organization, mission, realm, data source, binding, replay run) and the item's
  `point_id`, `sample_id` (else `canonical_sample_id`) and `observed_at`: the sample's generation
  time, else its receipt time, which is the stored row's partition time, so the read touches one
  partition. The fetched row must carry the decided identity. Any error writes nothing.
  """

  alias Cadence.Repo
  alias Cadence.Telemetry.{HistoryStore, PhysicalSampleQuery, Sample}
  alias Cadence.Telemetry.Storage.ObservationEnvelope

  alias Cadence.Telemetry.Storage.ObservationIdentityStates.TelemetryObservationIdentityStateRow,
    as: Row

  @count_fields %{
    "canonical" => :canonical_count,
    "duplicate" => :duplicate_count,
    "conflict" => :conflict_count,
    "superseded" => :superseded_count,
    "advisory" => :advisory_count
  }

  @doc """
  Reads the observation and returns the attributes of the row to create (validated, with
  timestamps), or an error. Refuses to run inside a transaction: the read must not hold one open.
  """
  @spec facts(binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def facts(observation_identity_id, opts) when is_binary(observation_identity_id) do
    with :ok <- outside_transaction(),
         {:ok, query} <- physical_query(opts),
         {:ok, %Sample{} = sample} <- fetch_sample(query, opts),
         :ok <- same_identity(sample, observation_identity_id),
         {:ok, revision} <- revision(observation_identity_id, sample) do
      observation_identity_id
      |> attrs(query, sample, revision)
      |> validated()
    end
  end

  defp outside_transaction do
    if Repo.in_transaction?(), do: {:error, :decision_lookup_inside_transaction}, else: :ok
  end

  defp physical_query(opts) do
    with {:ok, sample_id} <- required(opts, :sample_id, Keyword.get(opts, :canonical_sample_id)),
         {:ok, point_id} <- required(opts, :point_id),
         {:ok, data_source_id} <- required(opts, :data_source_id),
         {:ok, binding_id} <- required(opts, :binding_id),
         {:ok, realm} <- required_realm(opts),
         {:ok, observed_at} <- observed_at(opts) do
      PhysicalSampleQuery.new(%{
        organization_id: Keyword.fetch!(opts, :organization_id),
        mission_id: Keyword.fetch!(opts, :mission_id),
        point_id: point_id,
        sample_id: sample_id,
        data_source_id: data_source_id,
        source_binding_id: binding_id,
        realm: realm,
        replay_run_id: Keyword.get(opts, :replay_run_id),
        from_observed_at: observed_at,
        to_observed_at: observed_at
      })
    end
  end

  defp required(opts, field, default \\ nil) do
    case Keyword.get(opts, field, default) || default do
      value when is_binary(value) and value != "" -> {:ok, value}
      _missing -> {:error, {:missing_field, field}}
    end
  end

  defp required_realm(opts) do
    case Keyword.get(opts, :realm) do
      realm when is_atom(realm) and not is_nil(realm) -> {:ok, realm}
      realm when is_binary(realm) and realm != "" -> {:ok, realm}
      _missing -> {:error, {:missing_field, :realm}}
    end
  end

  defp observed_at(opts) do
    case Keyword.get(opts, :observed_at) do
      %DateTime{} = observed_at ->
        {:ok, observed_at}

      value when is_binary(value) ->
        case DateTime.from_iso8601(value) do
          {:ok, observed_at, _offset} -> {:ok, observed_at}
          {:error, _reason} -> {:error, {:invalid_field, :observed_at}}
        end

      nil ->
        {:error, {:missing_field, :observed_at}}

      _other ->
        {:error, {:invalid_field, :observed_at}}
    end
  end

  defp fetch_sample(query, opts) do
    Keyword.get(opts, :fetch_sample_fun, &HistoryStore.fetch_sample/2).(query, [])
  end

  defp same_identity(%Sample{} = sample, observation_identity_id) do
    if storage(sample)["observation_identity_id"] == observation_identity_id,
      do: :ok,
      else: {:error, {:observation_identity_mismatch, observation_identity_id}}
  end

  # The row's revision, as every history backend carries it in the storage provenance (QuestDB's
  # physical lookup reads the revision column). The observation_id digest must agree with it.
  defp revision(observation_identity_id, %Sample{} = sample) do
    storage = storage(sample)

    with {:ok, revision} <- stored_revision(storage["revision"]) do
      observation_id =
        ObservationEnvelope.observation_id_for(
          observation_identity_id,
          sample.sample_id,
          sample.packet_id,
          sample.evidence_id,
          revision
        )

      if observation_id == storage["observation_id"],
        do: {:ok, revision},
        else: {:error, {:observation_revision_mismatch, observation_identity_id}}
    end
  end

  defp stored_revision(revision) when is_integer(revision) and revision > 0, do: {:ok, revision}
  defp stored_revision(_revision), do: {:error, {:missing_field, :revision}}

  # Pinned (11-17): observable_id = point_id. ObservationEnvelope.from_sample defaults it so and no
  # production write path passes :observable_id (a test fails if one does); no history backend
  # stores it. A path that writes another observable must carry it here.
  defp attrs(
         observation_identity_id,
         %PhysicalSampleQuery{} = query,
         %Sample{} = sample,
         revision
       ) do
    storage = storage(sample)
    validity = storage["validity_state"] || "canonical"
    now = DateTime.utc_now()

    %{
      observation_identity_id: observation_identity_id,
      organization_id: query.organization_id,
      mission_id: sample.mission_id,
      realm: query.realm,
      replay_run_id: query.replay_run_id,
      data_source_id: query.data_source_id,
      binding_id: query.source_binding_id,
      observable_id: sample.point_id,
      point_id: sample.point_id,
      spacecraft_id: sample.spacecraft_id,
      latest_observation_id: storage["observation_id"],
      latest_sample_id: sample.sample_id,
      latest_revision: revision,
      validity_state: validity,
      first_seen_at: now,
      last_seen_at: now,
      payload: %{
        latest_observation_id: storage["observation_id"],
        latest_sample_id: sample.sample_id,
        latest_validity_state: validity,
        source_endpoint_id: storage["source_endpoint_id"],
        evidence_id: sample.evidence_id,
        packet_id: sample.packet_id,
        created_by: "decision"
      }
    }
    |> Map.merge(Map.new(Map.values(@count_fields), &{&1, 0}))
    |> put_count(validity)
    |> put_canonical(validity, storage, sample, revision)
  end

  defp put_count(attrs, validity) do
    case Map.fetch(@count_fields, validity) do
      {:ok, field} -> Map.put(attrs, field, 1)
      :error -> attrs
    end
  end

  defp put_canonical(attrs, "canonical", storage, %Sample{} = sample, revision) do
    Map.merge(attrs, %{
      canonical_observation_id: storage["observation_id"],
      canonical_sample_id: sample.sample_id,
      canonical_revision: revision
    })
  end

  defp put_canonical(attrs, _validity, _storage, _sample, _revision), do: attrs

  defp validated(attrs) do
    changeset = Row.changeset(%Row{}, attrs)

    with {:ok, %Row{} = row} <- Ecto.Changeset.apply_action(changeset, :insert) do
      now = DateTime.utc_now()
      {:ok, row |> Map.take(Row.fields()) |> Map.merge(%{inserted_at: now, updated_at: now})}
    end
  end

  defp storage(%Sample{provenance: %{"storage" => storage}}) when is_map(storage), do: storage
  defp storage(%Sample{}), do: %{}
end
