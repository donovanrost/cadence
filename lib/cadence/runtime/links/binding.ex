defmodule Cadence.Runtime.Links.Binding do
  @moduledoc """
  Binding between a ChannelId and an Interface.

  Bindings are the schedulable unit and are controlled independently of
  interface connection state.
  """

  alias Cadence.Runtime.ChannelId

  @type direction :: :uplink | :downlink | :both
  @type role :: :primary | :backup | :replay | :any
  @type state :: :inactive | :active | :draining

  @type t :: %__MODULE__{
          mission_id: String.t(),
          channel_id: ChannelId.t(),
          interface_id: String.t(),
          direction: direction(),
          role: role(),
          priority: non_neg_integer(),
          desired_state: state(),
          observed_state: state()
        }

  @enforce_keys [:mission_id, :channel_id, :interface_id, :direction]
  defstruct [
    :mission_id,
    :channel_id,
    :interface_id,
    :direction,
    role: :primary,
    priority: 0,
    desired_state: :inactive,
    observed_state: :inactive
  ]

  @spec key(t()) :: {ChannelId.t(), String.t(), direction()}
  def key(%__MODULE__{channel_id: channel_id, interface_id: interface_id, direction: direction}) do
    {channel_id, interface_id, direction}
  end

  @spec allows_direction?(t(), :uplink | :downlink) :: boolean()
  def allows_direction?(%__MODULE__{direction: :both}, _dir), do: true
  def allows_direction?(%__MODULE__{direction: dir}, dir), do: true
  def allows_direction?(_binding, _dir), do: false
end
