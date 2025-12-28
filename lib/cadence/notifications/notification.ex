defmodule Cadence.Notifications.Notification do
  @moduledoc """
  Schema for user notifications.

  Notifications are created in response to domain events and delivered
  through multiple channels (in-app, email) based on user preferences.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Accounts.User
  alias Cadence.Missions.Mission
  alias Cadence.Organizations.Organization
  alias Cadence.Outbox.Event

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @notification_types ~w(
    procedure_submitted
    procedure_approved
    procedure_rejected
    procedure_finalized
    procedure_withdrawn
  )

  @severities ~w(info warning critical)

  @type t :: %__MODULE__{}

  schema "notifications" do
    belongs_to :user, User
    belongs_to :organization, Organization
    belongs_to :mission, Mission
    belongs_to :actor, User
    belongs_to :outbox_event, Event

    field :type, :string
    field :title, :string
    field :body, :string
    field :severity, :string, default: "info"

    field :resource_type, :string
    field :resource_id, :binary_id
    field :action_url, :string

    field :metadata, :map, default: %{}

    field :read_at, :utc_datetime_usec
    field :archived_at, :utc_datetime_usec
    field :email_sent_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [
      :user_id,
      :organization_id,
      :mission_id,
      :actor_id,
      :outbox_event_id,
      :type,
      :title,
      :body,
      :severity,
      :resource_type,
      :resource_id,
      :action_url,
      :metadata,
      :read_at,
      :archived_at,
      :email_sent_at
    ])
    |> validate_required([:user_id, :organization_id, :type, :title])
    |> validate_inclusion(:type, @notification_types)
    |> validate_inclusion(:severity, @severities)
    |> validate_length(:title, max: 255)
    |> validate_length(:body, max: 2000)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:mission_id)
  end

  @doc """
  Changeset for marking a notification as read.
  """
  def mark_read_changeset(notification) do
    change(notification, %{read_at: DateTime.utc_now()})
  end

  @doc """
  Changeset for marking a notification as archived.
  """
  def mark_archived_changeset(notification) do
    change(notification, %{archived_at: DateTime.utc_now()})
  end

  @doc """
  Changeset for marking a notification email as sent.
  """
  def mark_email_sent_changeset(notification) do
    change(notification, %{email_sent_at: DateTime.utc_now()})
  end

  @doc """
  Returns all valid notification types.
  """
  def notification_types, do: @notification_types

  @doc """
  Returns all valid severities.
  """
  def severities, do: @severities
end
