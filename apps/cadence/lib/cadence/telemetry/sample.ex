defmodule Cadence.Telemetry.Sample do
  @moduledoc """
  Canonical telemetry sample emitted by a telemetry application handler.
  """

  @type quality_state :: :good | :suspect | :bad

  @typedoc """
  What tells one measurement from another when they share a generation time (identity v2):
  `{:seq, apid, sequence_count}` from a CCSDS packet (a property of the measurement, stable
  across paths and replays), or `{:pos, stream, position}` for count-less data whose generation
  time is only its receipt time (stable on journal replay).
  """
  @type frame_ref ::
          {:seq, non_neg_integer(), non_neg_integer()}
          | {:pos, binary(), non_neg_integer()}

  @type t :: %__MODULE__{
          sample_id: binary(),
          mission_id: binary(),
          spacecraft_id: binary() | nil,
          point_id: binary(),
          point_name: binary(),
          semantic_id: binary() | nil,
          qualified_name: binary() | nil,
          producer_kind: atom() | nil,
          producer_id: binary() | nil,
          mission_model_revision_id: binary() | nil,
          runtime_plan_id: binary() | nil,
          packet_definition_id: binary(),
          packet_definition_version: pos_integer(),
          packet_id: binary(),
          evidence_id: binary(),
          raw_value: term(),
          engineering_value: term(),
          quality_state: quality_state(),
          generation_time: DateTime.t() | nil,
          receipt_time: DateTime.t(),
          generation_time_source: :onboard | :receipt | nil,
          frame_ref: frame_ref() | nil,
          provenance: map()
        }

  defstruct [
    :sample_id,
    :mission_id,
    :spacecraft_id,
    :point_id,
    :point_name,
    :semantic_id,
    :qualified_name,
    :producer_kind,
    :producer_id,
    :mission_model_revision_id,
    :runtime_plan_id,
    :packet_definition_id,
    :packet_definition_version,
    :packet_id,
    :evidence_id,
    :raw_value,
    :engineering_value,
    :quality_state,
    :generation_time,
    :receipt_time,
    :generation_time_source,
    :frame_ref,
    provenance: %{}
  ]

  @doc """
  The names a command verifier or transmission constraint may give this sample's subject: the
  parameter's semantic id (`semantic:parameter:…`, as mission-model plans name it), its qualified
  name, and the catalog point (`PACKET.field`), each as `normalize_subject_ref/1` leaves it.
  """
  @spec subject_refs(t()) :: [binary()]
  def subject_refs(%__MODULE__{} = sample) do
    [sample.semantic_id, sample.qualified_name, sample.point_id, sample.point_name]
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&normalize_subject_ref/1)
    |> Enum.uniq()
  end

  @doc "A subject reference without surrounding space or a `telemetry:` prefix."
  @spec normalize_subject_ref(binary()) :: binary()
  def normalize_subject_ref(subject_ref) when is_binary(subject_ref) do
    subject_ref
    |> String.trim()
    |> String.trim_leading("telemetry:")
  end

  @doc "A JSON-safe form of a frame ref, for metadata that may be encoded (`decode_frame_ref/1`)."
  @spec encode_frame_ref(frame_ref() | nil) :: [term()] | nil
  def encode_frame_ref({:seq, apid, count}), do: ["seq", apid, count]
  def encode_frame_ref({:pos, stream, position}), do: ["pos", stream, position]
  def encode_frame_ref(_ref), do: nil

  @spec decode_frame_ref(term()) :: frame_ref() | nil
  def decode_frame_ref(["seq", apid, count]) when is_integer(apid) and is_integer(count),
    do: {:seq, apid, count}

  def decode_frame_ref(["pos", stream, position]) when is_binary(stream) and is_integer(position),
    do: {:pos, stream, position}

  def decode_frame_ref({_kind, _a, _b} = ref), do: decode_frame_ref(encode_frame_ref(ref))
  def decode_frame_ref(_ref), do: nil
end
