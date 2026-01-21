defmodule Cadence.Runtime.Transport.COP1.Context do
  @moduledoc """
  COP-1 control and correlation context.
  """

  alias Cadence.Runtime.Uplink.RouteDecision

  @type flag_value :: 0 | 1 | boolean()

  @type t :: %__MODULE__{
          stream_id: term() | nil,
          initial_seq: non_neg_integer() | nil,
          vcid: non_neg_integer() | nil,
          bypass_flag: flag_value() | nil,
          control_command_flag: flag_value() | nil,
          segment_header_flag: flag_value() | nil,
          cop1_control: :unlock | nil,
          bypass: boolean() | nil,
          correlation_id: term() | nil
        }

  defstruct [
    :stream_id,
    :initial_seq,
    :vcid,
    :bypass_flag,
    :control_command_flag,
    :segment_header_flag,
    :cop1_control,
    :bypass,
    :correlation_id
  ]

  @spec new(map() | keyword()) :: t()
  def new(attrs \\ %{}) do
    struct(__MODULE__, attrs)
  end

  @spec from_route_decision(RouteDecision.t()) :: t()
  def from_route_decision(%RouteDecision{} = decision) do
    %__MODULE__{
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

  @spec normalize_control(t()) :: t()
  def normalize_control(%__MODULE__{} = context) do
    case normalize_control_value(context.cop1_control) do
      nil ->
        context

      :unlock ->
        context
        |> Map.put(:control_command_flag, 1)
        |> Map.put(:bypass_flag, 1)
    end
  end

  @spec normalize_flag(flag_value() | nil, non_neg_integer()) :: non_neg_integer()
  def normalize_flag(nil, default), do: default
  def normalize_flag(true, _default), do: 1
  def normalize_flag(false, _default), do: 0
  def normalize_flag(1, _default), do: 1
  def normalize_flag(0, _default), do: 0
  def normalize_flag(_value, default), do: default

  @spec normalize_control_value(term()) :: :unlock | nil
  def normalize_control_value(nil), do: nil
  def normalize_control_value("unlock"), do: :unlock
  def normalize_control_value(:unlock), do: :unlock
  def normalize_control_value(_), do: nil
end
