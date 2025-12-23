defmodule Cadence.Domain.Notifications.Entities.Notification do
  @moduledoc """
  Pure domain entity representing a user notification.

  Notifications are created in response to domain events and delivered
  through multiple channels (in-app, email) based on user preferences.

  ## Usage

      {:ok, notification} = Notification.new(%{
        user_id: user_id,
        organization_id: org_id,
        type: :procedure_submitted,
        title: "Procedure submitted for approval",
        severity: :info
      })

      # Mark as read
      {:ok, notification} = Notification.mark_read(notification)

      # Archive
      {:ok, notification} = Notification.archive(notification)
  """

  alias Cadence.Domain.Notifications.ValueObjects.NotificationType
  alias Cadence.Domain.Notifications.ValueObjects.NotificationSeverity

  @type t :: %__MODULE__{
          id: String.t() | nil,
          user_id: String.t(),
          organization_id: String.t(),
          mission_id: String.t() | nil,
          actor_id: String.t() | nil,
          outbox_event_id: String.t() | nil,
          type: NotificationType.t(),
          title: String.t(),
          body: String.t() | nil,
          severity: NotificationSeverity.t(),
          resource_type: String.t() | nil,
          resource_id: String.t() | nil,
          action_url: String.t() | nil,
          metadata: map(),
          read_at: DateTime.t() | nil,
          archived_at: DateTime.t() | nil,
          email_sent_at: DateTime.t() | nil,
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defstruct [
    :id,
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
    :read_at,
    :archived_at,
    :email_sent_at,
    :created_at,
    :updated_at,
    metadata: %{}
  ]

  @doc """
  Creates a new Notification entity.

  ## Required Fields

  - `:user_id` - Recipient user ID
  - `:organization_id` - Organization ID
  - `:type` - Notification type (atom or string)
  - `:title` - Notification title

  ## Optional Fields

  - `:mission_id` - Mission context
  - `:actor_id` - User who triggered the event
  - `:body` - Notification body
  - `:severity` - Severity level (default: :info)
  - `:resource_type` - Type of related resource
  - `:resource_id` - ID of related resource
  - `:action_url` - URL for notification action
  - `:metadata` - Additional metadata
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    with :ok <- validate_required(attrs, [:user_id, :organization_id, :type, :title]),
         {:ok, type} <- parse_type(attrs[:type]),
         {:ok, severity} <- parse_severity(attrs[:severity]),
         :ok <- validate_title(attrs[:title]) do
      {:ok,
       %__MODULE__{
         id: attrs[:id],
         user_id: attrs[:user_id],
         organization_id: attrs[:organization_id],
         mission_id: attrs[:mission_id],
         actor_id: attrs[:actor_id],
         outbox_event_id: attrs[:outbox_event_id],
         type: type,
         title: attrs[:title],
         body: attrs[:body],
         severity: severity,
         resource_type: attrs[:resource_type],
         resource_id: attrs[:resource_id],
         action_url: attrs[:action_url],
         metadata: attrs[:metadata] || %{},
         read_at: attrs[:read_at],
         archived_at: attrs[:archived_at],
         email_sent_at: attrs[:email_sent_at],
         created_at: attrs[:created_at],
         updated_at: attrs[:updated_at]
       }}
    end
  end

  @doc """
  Creates a notification from database storage format.
  """
  @spec from_storage(map()) :: {:ok, t()} | {:error, term()}
  def from_storage(attrs) when is_map(attrs) do
    new(%{
      id: get_attr(attrs, :id),
      user_id: get_attr(attrs, :user_id),
      organization_id: get_attr(attrs, :organization_id),
      mission_id: get_attr(attrs, :mission_id),
      actor_id: get_attr(attrs, :actor_id),
      outbox_event_id: get_attr(attrs, :outbox_event_id),
      type: get_attr(attrs, :type),
      title: get_attr(attrs, :title),
      body: get_attr(attrs, :body),
      severity: get_attr(attrs, :severity),
      resource_type: get_attr(attrs, :resource_type),
      resource_id: get_attr(attrs, :resource_id),
      action_url: get_attr(attrs, :action_url),
      metadata: get_attr(attrs, :metadata) || %{},
      read_at: get_attr(attrs, :read_at),
      archived_at: get_attr(attrs, :archived_at),
      email_sent_at: get_attr(attrs, :email_sent_at),
      created_at: get_attr(attrs, :inserted_at) || get_attr(attrs, :created_at),
      updated_at: get_attr(attrs, :updated_at)
    })
  end

  @doc """
  Converts the notification to database storage format.
  """
  @spec to_storage(t()) :: map()
  def to_storage(%__MODULE__{} = notification) do
    %{
      id: notification.id,
      user_id: notification.user_id,
      organization_id: notification.organization_id,
      mission_id: notification.mission_id,
      actor_id: notification.actor_id,
      outbox_event_id: notification.outbox_event_id,
      type: NotificationType.to_string(notification.type),
      title: notification.title,
      body: notification.body,
      severity: NotificationSeverity.to_string(notification.severity),
      resource_type: notification.resource_type,
      resource_id: notification.resource_id,
      action_url: notification.action_url,
      metadata: notification.metadata,
      read_at: notification.read_at,
      archived_at: notification.archived_at,
      email_sent_at: notification.email_sent_at
    }
  end

  @doc """
  Marks the notification as read.
  """
  @spec mark_read(t()) :: {:ok, t()}
  def mark_read(%__MODULE__{} = notification) do
    {:ok, %{notification | read_at: DateTime.utc_now(), updated_at: DateTime.utc_now()}}
  end

  @doc """
  Archives the notification.
  """
  @spec archive(t()) :: {:ok, t()}
  def archive(%__MODULE__{} = notification) do
    {:ok, %{notification | archived_at: DateTime.utc_now(), updated_at: DateTime.utc_now()}}
  end

  @doc """
  Marks the notification email as sent.
  """
  @spec mark_email_sent(t()) :: {:ok, t()}
  def mark_email_sent(%__MODULE__{} = notification) do
    {:ok, %{notification | email_sent_at: DateTime.utc_now(), updated_at: DateTime.utc_now()}}
  end

  @doc """
  Returns true if the notification has been read.
  """
  @spec read?(t()) :: boolean()
  def read?(%__MODULE__{read_at: nil}), do: false
  def read?(%__MODULE__{}), do: true

  @doc """
  Returns true if the notification has been archived.
  """
  @spec archived?(t()) :: boolean()
  def archived?(%__MODULE__{archived_at: nil}), do: false
  def archived?(%__MODULE__{}), do: true

  @doc """
  Returns true if the email has been sent.
  """
  @spec email_sent?(t()) :: boolean()
  def email_sent?(%__MODULE__{email_sent_at: nil}), do: false
  def email_sent?(%__MODULE__{}), do: true

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp validate_required(attrs, fields) do
    missing = Enum.filter(fields, fn field -> is_nil(attrs[field]) end)

    if Enum.empty?(missing) do
      :ok
    else
      {:error, {:missing_fields, missing}}
    end
  end

  defp parse_type(nil), do: {:error, :invalid_notification_type}
  defp parse_type(type), do: NotificationType.parse(type)

  defp parse_severity(nil), do: {:ok, NotificationSeverity.default()}
  defp parse_severity(severity), do: NotificationSeverity.parse(severity)

  defp validate_title(nil), do: {:error, :title_required}

  defp validate_title(title) when is_binary(title) do
    cond do
      String.length(title) < 1 -> {:error, :title_too_short}
      String.length(title) > 255 -> {:error, :title_too_long}
      true -> :ok
    end
  end

  defp validate_title(_), do: {:error, :invalid_title}

  defp get_attr(attrs, key) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end
end
