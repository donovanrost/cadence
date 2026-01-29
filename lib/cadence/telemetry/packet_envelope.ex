defmodule Cadence.Telemetry.PacketEnvelope do
  @moduledoc """
  Durable, format-agnostic boundary envelope for telemetry bytes.
  """

  alias Cadence.Telemetry.Evidence
  alias Cadence.Time, as: CadenceTime

  @type t :: %__MODULE__{
          packet_id: binary(),
          mission_id: binary(),
          ingest_ts: DateTime.t(),
          ingest_monotonic_ns: non_neg_integer(),
          raw: binary(),
          provenance: map(),
          evidence: [Evidence.t()],
          observations: map() | nil,
          router_version: binary() | integer() | nil,
          config_version_seen: non_neg_integer(),
          quality: :good | :suspect | :bad | nil,
          mode: :realtime | :replay | :sim
        }

  defstruct [
    :packet_id,
    :mission_id,
    :ingest_ts,
    :ingest_monotonic_ns,
    :raw,
    provenance: %{},
    evidence: [],
    observations: nil,
    router_version: nil,
    config_version_seen: 0,
    quality: nil,
    mode: :realtime
  ]

  @spec new(keyword() | map()) :: t()
  def new(opts) when is_list(opts) do
    mission_id = Keyword.get(opts, :mission_id)
    raw = Keyword.get(opts, :raw)

    if is_binary(mission_id) and is_binary(raw) do
      opts = Keyword.drop(opts, [:mission_id, :raw])
      new(mission_id, raw, opts)
    else
      raise ArgumentError, "PacketEnvelope.new/1 requires :mission_id and :raw"
    end
  end

  def new(opts) when is_map(opts) do
    mission_id = Map.get(opts, :mission_id) || Map.get(opts, "mission_id")
    raw = Map.get(opts, :raw) || Map.get(opts, "raw")

    if is_binary(mission_id) and is_binary(raw) do
      opts =
        opts
        |> Map.drop([:mission_id, "mission_id", :raw, "raw"])
        |> Enum.into([])

      new(mission_id, raw, opts)
    else
      raise ArgumentError, "PacketEnvelope.new/1 requires :mission_id and :raw"
    end
  end

  @spec new(binary(), binary(), keyword()) :: t()
  def new(mission_id, raw, opts \\ []) when is_binary(mission_id) and is_binary(raw) do
    ingest_ts = Keyword.get(opts, :ingest_ts, CadenceTime.now())

    ingest_monotonic_ns =
      Keyword.get(opts, :ingest_monotonic_ns, CadenceTime.monotonic(:nanosecond))

    %__MODULE__{
      packet_id: Keyword.get(opts, :packet_id, Ecto.UUID.generate()),
      mission_id: mission_id,
      ingest_ts: ingest_ts,
      ingest_monotonic_ns: ingest_monotonic_ns,
      raw: raw,
      provenance: Keyword.get(opts, :provenance, %{}),
      evidence: Keyword.get(opts, :evidence, []),
      observations: Keyword.get(opts, :observations),
      router_version: Keyword.get(opts, :router_version),
      config_version_seen: Keyword.get(opts, :config_version_seen, 0),
      quality: Keyword.get(opts, :quality),
      mode: Keyword.get(opts, :mode, :realtime)
    }
  end

  @spec add_evidence(t(), Evidence.t() | [Evidence.t()]) :: t()
  def add_evidence(%__MODULE__{} = envelope, %Evidence{} = evidence) do
    %{envelope | evidence: envelope.evidence ++ [evidence]}
  end

  def add_evidence(%__MODULE__{} = envelope, evidence_list) when is_list(evidence_list) do
    add_evidence_many(envelope, evidence_list)
  end

  @spec add_evidence_many(t(), [Evidence.t()]) :: t()
  def add_evidence_many(%__MODULE__{} = envelope, evidence_list) when is_list(evidence_list) do
    %{envelope | evidence: envelope.evidence ++ evidence_list}
  end
end
