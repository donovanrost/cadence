defmodule Cadence.Applications.HostContext do
  @moduledoc """
  Bounded resource context supplied by an authenticated application host.

  Actor authority remains in the separate `Cadence.Auth.Scope` argument passed
  to query and action services.
  """

  @type placement :: :organization | :user | :admin | :mission | :spacecraft

  @type organization_t :: %__MODULE__{
          placement: :organization,
          organization_id: binary(),
          user_id: nil,
          mission_id: nil,
          spacecraft_id: nil
        }

  @type user_t :: %__MODULE__{
          placement: :user,
          organization_id: nil,
          user_id: binary(),
          mission_id: nil,
          spacecraft_id: nil
        }

  @type admin_t :: %__MODULE__{
          placement: :admin,
          organization_id: nil,
          user_id: nil,
          mission_id: nil,
          spacecraft_id: nil
        }

  @type mission_t :: %__MODULE__{
          placement: :mission,
          organization_id: nil,
          user_id: nil,
          mission_id: binary(),
          spacecraft_id: nil
        }

  @type spacecraft_t :: %__MODULE__{
          placement: :spacecraft,
          organization_id: nil,
          user_id: nil,
          mission_id: binary(),
          spacecraft_id: binary()
        }

  @type t :: organization_t() | user_t() | admin_t() | mission_t() | spacecraft_t()

  @enforce_keys [:placement]
  defstruct [:placement, :organization_id, :user_id, :mission_id, :spacecraft_id]

  @spec organization(binary()) :: t()
  def organization(organization_id) when is_binary(organization_id) do
    %__MODULE__{placement: :organization, organization_id: organization_id}
  end

  @spec user(binary()) :: t()
  def user(user_id) when is_binary(user_id) do
    %__MODULE__{placement: :user, user_id: user_id}
  end

  @spec admin() :: t()
  def admin, do: %__MODULE__{placement: :admin}

  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{placement: :organization} = context) do
    valid_id?(context.organization_id) and
      is_nil(context.user_id) and is_nil(context.mission_id) and is_nil(context.spacecraft_id)
  end

  def valid?(%__MODULE__{placement: :user} = context) do
    is_nil(context.organization_id) and valid_id?(context.user_id) and
      is_nil(context.mission_id) and is_nil(context.spacecraft_id)
  end

  def valid?(%__MODULE__{placement: :admin} = context) do
    is_nil(context.organization_id) and is_nil(context.user_id) and
      is_nil(context.mission_id) and is_nil(context.spacecraft_id)
  end

  def valid?(%__MODULE__{placement: :mission} = context) do
    is_nil(context.organization_id) and is_nil(context.user_id) and
      valid_id?(context.mission_id) and is_nil(context.spacecraft_id)
  end

  def valid?(%__MODULE__{placement: :spacecraft} = context) do
    is_nil(context.organization_id) and is_nil(context.user_id) and
      valid_id?(context.mission_id) and valid_id?(context.spacecraft_id)
  end

  def valid?(_context), do: false

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

  defp valid_id?(value), do: is_binary(value) and value != ""
end
