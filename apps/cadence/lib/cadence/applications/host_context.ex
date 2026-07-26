defmodule Cadence.Applications.HostContext do
  @moduledoc """
  Bounded resource context supplied by an authenticated application host.

  Actor authority remains in the separate `Cadence.Auth.Scope` argument passed
  to query and action services.
  """

  @type placement :: :mission | :spacecraft

  @type t :: %__MODULE__{
          placement: placement(),
          mission_id: binary(),
          spacecraft_id: binary() | nil
        }

  @enforce_keys [:placement, :mission_id]
  defstruct [:placement, :mission_id, :spacecraft_id]

  @spec mission(binary()) :: t()
  def mission(mission_id) when is_binary(mission_id) do
    %__MODULE__{placement: :mission, mission_id: mission_id}
  end

  @spec spacecraft(binary(), binary()) :: t()
  def spacecraft(mission_id, spacecraft_id)
      when is_binary(mission_id) and is_binary(spacecraft_id) do
    %__MODULE__{
      placement: :spacecraft,
      mission_id: mission_id,
      spacecraft_id: spacecraft_id
    }
  end
end
