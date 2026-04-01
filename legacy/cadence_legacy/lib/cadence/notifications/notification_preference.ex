defmodule Cadence.Notifications.NotificationPreference do
  @moduledoc """
  User preferences for notification delivery.

  Preferences can be set globally (mission_id = nil) or per-mission.
  Mission-level preferences override global preferences.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Accounts.User
  alias Cadence.Missions.Mission

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @email_frequencies ~w(immediate daily_digest weekly_digest none)

  schema "notification_preferences" do
    belongs_to :user, User
    belongs_to :mission, Mission

    field :notification_type, :string
    field :in_app_enabled, :boolean, default: true
    field :email_enabled, :boolean, default: true
    field :email_frequency, :string, default: "immediate"

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(preference, attrs) do
    preference
    |> cast(attrs, [
      :user_id,
      :mission_id,
      :notification_type,
      :in_app_enabled,
      :email_enabled,
      :email_frequency
    ])
    |> validate_required([:user_id, :notification_type])
    |> validate_inclusion(:email_frequency, @email_frequencies)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:mission_id)
  end

  @doc """
  Returns all valid email frequency options.
  """
  def email_frequencies, do: @email_frequencies

  @doc """
  Returns default preferences for a notification type.
  """
  def defaults do
    %{
      in_app_enabled: true,
      email_enabled: true,
      email_frequency: "immediate"
    }
  end
end
