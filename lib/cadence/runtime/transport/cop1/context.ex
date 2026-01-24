defmodule Cadence.Runtime.Transport.COP1.Context do
  @moduledoc """
  COP-1 control and correlation context.

  This context carries stream identity and COP-1 control information.
  Flag fields (bypass_flag, control_command_flag, segment_header_flag) are
  intentionally NOT included here - they are derived from segmentation config
  at the interface level in TCFraming.
  """

  alias Cadence.Runtime.Uplink.RouteDecision
  alias Cadence.Transport.TCStreamId

  @type t :: %__MODULE__{
          stream_id: TCStreamId.t() | nil,
          vcid: non_neg_integer() | nil,
          cop1_control: :unlock | nil,
          bypass: boolean() | nil,
          correlation_id: term() | nil
        }

  defstruct [
    :stream_id,
    :vcid,
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

  @doc """
  Returns the TC frame flags required for a COP-1 control command.
  For :unlock, returns flags with control_command_flag=1 and bypass_flag=1.
  For normal commands, returns nil.
  """
  @spec control_flags(t()) :: %{bypass_flag: 0 | 1, control_command_flag: 0 | 1} | nil
  def control_flags(%__MODULE__{} = context) do
    case normalize_control_value(context.cop1_control) do
      nil -> nil
      :unlock -> %{bypass_flag: 1, control_command_flag: 1}
    end
  end

  @doc """
  Returns true if this context represents a COP-1 control command (e.g., unlock).
  """
  @spec control_command?(t()) :: boolean()
  def control_command?(%__MODULE__{} = context) do
    normalize_control_value(context.cop1_control) != nil
  end

  @spec normalize_control_value(term()) :: :unlock | nil
  def normalize_control_value(nil), do: nil
  def normalize_control_value("unlock"), do: :unlock
  def normalize_control_value(:unlock), do: :unlock
  def normalize_control_value(_), do: nil
end
