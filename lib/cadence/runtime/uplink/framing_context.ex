defmodule Cadence.Runtime.Uplink.FramingContext do
  @moduledoc """
  Context for TC/SDLP framing inputs and segmentation identity.
  """

  alias Cadence.Runtime.Uplink.RouteDecision
  alias Cadence.Transport.TCStreamId

  @type flag_value :: 0 | 1 | boolean()

  @type t :: %__MODULE__{
          frame_size: non_neg_integer() | nil,
          scid: non_neg_integer() | nil,
          vcid: non_neg_integer() | nil,
          map_id: non_neg_integer() | nil,
          ocf: binary() | nil,
          ocf_length: non_neg_integer() | nil,
          bypass_flag: flag_value() | nil,
          control_command_flag: flag_value() | nil,
          segment_header_flag: flag_value() | nil,
          stream_id: TCStreamId.t() | nil,
          initial_seq: non_neg_integer() | nil
        }

  defstruct [
    :frame_size,
    :scid,
    :vcid,
    :map_id,
    :ocf,
    :ocf_length,
    :bypass_flag,
    :control_command_flag,
    :segment_header_flag,
    :stream_id,
    :initial_seq
  ]

  @spec new(map() | keyword()) :: t()
  def new(attrs \\ %{}) do
    struct(__MODULE__, attrs)
  end

  @spec from_route_decision(RouteDecision.t()) :: t()
  def from_route_decision(%RouteDecision{} = decision) do
    %__MODULE__{
      scid: decision.scid,
      vcid: decision.vcid,
      stream_id: decision.tc_stream_id
    }
  end

  @spec merge(t(), t() | nil) :: t()
  def merge(%__MODULE__{} = base, nil), do: base

  def merge(%__MODULE__{} = base, %__MODULE__{} = overrides) do
    overrides
    |> Map.from_struct()
    |> Enum.reduce(base, fn {key, value}, acc ->
      if is_nil(value), do: acc, else: Map.put(acc, key, value)
    end)
  end

  @spec put_if_nil(t(), atom(), term()) :: t()
  def put_if_nil(%__MODULE__{} = context, key, value) when is_atom(key) do
    if Map.get(context, key) == nil do
      Map.put(context, key, value)
    else
      context
    end
  end

  @spec with_defaults(t(), keyword() | nil) :: t()
  def with_defaults(%__MODULE__{} = context, nil), do: context

  def with_defaults(%__MODULE__{} = context, opts) do
    frame_size = opts[:uplink_frame_size] || opts[:frame_size]
    scid = opts[:uplink_scid] || opts[:scid]
    vcid = opts[:uplink_vcid] || opts[:vcid]
    map_id = opts[:uplink_map_id]

    context
    |> put_if_nil(:frame_size, frame_size)
    |> put_if_nil(:scid, scid)
    |> put_if_nil(:vcid, vcid)
    |> put_if_nil(:map_id, map_id)
  end

  @spec normalize_flag(flag_value() | nil, non_neg_integer()) :: non_neg_integer()
  def normalize_flag(nil, default), do: default
  def normalize_flag(true, _default), do: 1
  def normalize_flag(false, _default), do: 0
  def normalize_flag(1, _default), do: 1
  def normalize_flag(0, _default), do: 0
  def normalize_flag(_value, default), do: default
end
