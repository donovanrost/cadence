defmodule Cadence.Telemetry.Storage.ObservationEnvelope do
  @moduledoc """
  Storage-neutral telemetry observation write envelope.

  This is the contract between Cadence telemetry ingest and physical TSDB
  adapters. It captures source binding, tenant context, idempotency, and
  projection metadata before a database-specific writer serializes anything.
  """

  alias Cadence.Telemetry.Sample
  alias Cadence.Telemetry.Storage.WriteContext

  @type validity_state :: :canonical | :duplicate | :conflict | :superseded | :advisory

  @type t :: %__MODULE__{
          observation_id: binary(),
          observation_identity_id: binary(),
          idempotency_key: binary(),
          organization_id: binary(),
          mission_id: binary(),
          realm: WriteContext.realm(),
          data_source_id: binary(),
          binding_id: binary(),
          replay_run_id: binary() | nil,
          source_endpoint_id: binary() | nil,
          sample_id: binary(),
          spacecraft_id: binary() | nil,
          observable_id: binary(),
          point_id: binary(),
          point_name: binary(),
          packet_definition_id: binary(),
          packet_definition_version: pos_integer(),
          packet_id: binary(),
          evidence_id: binary(),
          raw_value: term(),
          engineering_value: term(),
          quality_state: Sample.quality_state(),
          validity_state: validity_state(),
          generation_time: DateTime.t() | nil,
          receipt_time: DateTime.t(),
          ingested_at: DateTime.t(),
          revision: pos_integer(),
          supersedes_observation_id: binary() | nil,
          provenance: map(),
          metadata: map()
        }

  defstruct [
    :observation_id,
    :observation_identity_id,
    :idempotency_key,
    :organization_id,
    :mission_id,
    :realm,
    :data_source_id,
    :binding_id,
    :replay_run_id,
    :source_endpoint_id,
    :sample_id,
    :spacecraft_id,
    :observable_id,
    :point_id,
    :point_name,
    :packet_definition_id,
    :packet_definition_version,
    :packet_id,
    :evidence_id,
    :raw_value,
    :engineering_value,
    :quality_state,
    :validity_state,
    :generation_time,
    :receipt_time,
    :ingested_at,
    :revision,
    :supersedes_observation_id,
    provenance: %{},
    metadata: %{}
  ]

  @validity_states [:canonical, :duplicate, :conflict, :superseded, :advisory]

  @spec from_sample(WriteContext.t(), Sample.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def from_sample(%WriteContext{} = context, %Sample{} = sample, opts \\ []) when is_list(opts) do
    with :ok <- WriteContext.validate(context),
         :ok <- validate_sample(context, sample),
         {:ok, validity_state} <- validity_state(opts),
         {:ok, revision} <- revision(opts) do
      envelope = %__MODULE__{
        organization_id: context.organization_id,
        mission_id: context.mission_id,
        realm: context.realm,
        data_source_id: context.data_source_id,
        binding_id: context.binding_id,
        replay_run_id: context.replay_run_id,
        source_endpoint_id: context.source_endpoint_id,
        sample_id: sample.sample_id,
        spacecraft_id: sample.spacecraft_id,
        observable_id: Keyword.get(opts, :observable_id, sample.point_id),
        point_id: sample.point_id,
        point_name: sample.point_name,
        packet_definition_id: sample.packet_definition_id,
        packet_definition_version: sample.packet_definition_version,
        packet_id: sample.packet_id,
        evidence_id: sample.evidence_id,
        raw_value: sample.raw_value,
        engineering_value: sample.engineering_value,
        quality_state: sample.quality_state,
        validity_state: validity_state,
        generation_time: sample.generation_time,
        receipt_time: sample.receipt_time,
        ingested_at: context.recorded_at || DateTime.utc_now(),
        revision: revision,
        supersedes_observation_id: Keyword.get(opts, :supersedes_observation_id),
        provenance: sample.provenance,
        metadata: Map.merge(context.metadata, Keyword.get(opts, :metadata, %{}))
      }

      observation_identity_id = observation_identity_id(envelope)
      observation_id = observation_id(envelope, observation_identity_id)

      {:ok,
       %{
         envelope
         | observation_id: observation_id,
           observation_identity_id: observation_identity_id,
           idempotency_key: idempotency_key(envelope)
       }}
    end
  end

  @spec batch_from_samples(WriteContext.t(), [Sample.t()], keyword()) ::
          {:ok, [t()]} | {:error, term()}
  def batch_from_samples(%WriteContext{} = context, samples, opts \\ [])
      when is_list(samples) and is_list(opts) do
    samples
    |> Enum.reduce_while({:ok, []}, fn sample, {:ok, acc} ->
      case from_sample(context, sample, opts) do
        {:ok, envelope} -> {:cont, {:ok, [envelope | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, envelopes} -> {:ok, Enum.reverse(envelopes)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec to_sample(t()) :: Sample.t()
  def to_sample(%__MODULE__{} = envelope) do
    provenance = enriched_provenance(envelope)

    %Sample{
      sample_id: envelope.sample_id,
      mission_id: envelope.mission_id,
      spacecraft_id: envelope.spacecraft_id,
      point_id: envelope.point_id,
      point_name: envelope.point_name,
      semantic_id: provenance_value(provenance, :semantic_id),
      qualified_name: provenance_value(provenance, :qualified_name),
      producer_kind: provenance_value(provenance, :producer_kind) |> normalize_optional_atom(),
      producer_id: provenance_value(provenance, :producer_id),
      mission_model_revision_id: provenance_value(provenance, :mission_model_revision_id),
      runtime_plan_id: provenance_value(provenance, :runtime_plan_id),
      packet_definition_id: envelope.packet_definition_id,
      packet_definition_version: envelope.packet_definition_version,
      packet_id: envelope.packet_id,
      evidence_id: envelope.evidence_id,
      raw_value: envelope.raw_value,
      engineering_value: envelope.engineering_value,
      quality_state: envelope.quality_state,
      generation_time: envelope.generation_time,
      receipt_time: envelope.receipt_time,
      provenance: provenance
    }
  end

  defp validate_sample(%WriteContext{mission_id: mission_id}, %Sample{mission_id: mission_id}) do
    :ok
  end

  defp validate_sample(%WriteContext{mission_id: context_mission_id}, %Sample{
         mission_id: sample_mission_id
       }) do
    {:error, {:mission_mismatch, context_mission_id, sample_mission_id}}
  end

  defp validity_state(opts) do
    state = Keyword.get(opts, :validity_state, :canonical)

    if state in @validity_states do
      {:ok, state}
    else
      {:error, {:unsupported_validity_state, state}}
    end
  end

  defp revision(opts) do
    case Keyword.get(opts, :revision, 1) do
      revision when is_integer(revision) and revision > 0 -> {:ok, revision}
      revision -> {:error, {:invalid_revision, revision}}
    end
  end

  defp observation_identity_id(%__MODULE__{} = envelope) do
    stable_digest([
      envelope.organization_id,
      envelope.mission_id,
      envelope.realm,
      envelope.binding_id,
      envelope.replay_run_id,
      envelope.observable_id,
      envelope.spacecraft_id,
      envelope.point_id,
      envelope.point_name,
      envelope.packet_definition_id,
      envelope.packet_definition_version,
      envelope.generation_time
    ])
  end

  defp observation_id(%__MODULE__{} = envelope, observation_identity_id) do
    stable_digest([
      observation_identity_id,
      envelope.sample_id,
      envelope.packet_id,
      envelope.evidence_id,
      envelope.revision
    ])
  end

  defp idempotency_key(%__MODULE__{} = envelope) do
    stable_digest([
      envelope.organization_id,
      envelope.mission_id,
      envelope.realm,
      envelope.data_source_id,
      envelope.binding_id,
      envelope.replay_run_id,
      envelope.sample_id,
      envelope.revision
    ])
  end

  defp stable_digest(parts) do
    :sha256
    |> :crypto.hash(:erlang.term_to_binary(parts))
    |> Base.url_encode64(padding: false)
  end

  defp enriched_provenance(%__MODULE__{} = envelope) do
    Map.put(envelope.provenance || %{}, "storage", %{
      "organization_id" => envelope.organization_id,
      "realm" => Atom.to_string(envelope.realm),
      "data_source_id" => envelope.data_source_id,
      "binding_id" => envelope.binding_id,
      "source_endpoint_id" => envelope.source_endpoint_id,
      "replay_run_id" => envelope.replay_run_id,
      "observation_id" => envelope.observation_id,
      "observation_identity_id" => envelope.observation_identity_id,
      "validity_state" => Atom.to_string(envelope.validity_state),
      "revision" => envelope.revision,
      "supersedes_observation_id" => envelope.supersedes_observation_id
    })
  end

  defp provenance_value(provenance, key) do
    Map.get(provenance, key, Map.get(provenance, Atom.to_string(key)))
  end

  defp normalize_optional_atom(nil), do: nil
  defp normalize_optional_atom(value) when is_atom(value), do: value
  defp normalize_optional_atom(value) when is_binary(value), do: String.to_existing_atom(value)
end
