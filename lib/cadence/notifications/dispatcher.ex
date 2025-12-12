defmodule Cadence.Notifications.Dispatcher do
  @moduledoc """
  Subscribes to outbox events and dispatches notifications.

  This GenServer listens for relevant domain events via PubSub and
  creates notifications for the appropriate recipients based on
  user preferences.
  """

  use GenServer
  require Logger

  alias Cadence.Notifications
  alias Cadence.Notifications.NotificationBuilder
  alias Cadence.Outbox

  @notification_event_types ~w(
    procedure_submitted
    procedure_approved
    procedure_rejected
    procedure_finalized
  )

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Subscribe to relevant event types
    for event_type <- @notification_event_types do
      Outbox.subscribe_event_type(event_type)
    end

    Logger.info(
      "Notifications.Dispatcher started, subscribed to #{length(@notification_event_types)} event types"
    )

    {:ok, %{}}
  end

  @impl true
  def handle_info({:outbox_event, event}, state) do
    # Process event asynchronously to avoid blocking the GenServer
    Task.start(fn -> process_event(event) end)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp process_event(event) do
    case NotificationBuilder.build_from_event(event) do
      {:ok, notifications_attrs} ->
        dispatch_notifications(notifications_attrs, event)

      {:error, reason} ->
        Logger.warning(
          "Failed to build notifications from event #{event.id}: #{inspect(reason)}"
        )
    end
  end

  defp dispatch_notifications(notifications_attrs, _event) do
    for attrs <- notifications_attrs do
      # Check user preferences
      prefs =
        Notifications.get_preferences(
          attrs.user_id,
          attrs.type,
          attrs[:mission_id]
        )

      # Create in-app notification if enabled
      if prefs.in_app_enabled do
        case Notifications.create_notification(attrs) do
          {:ok, notification} ->
            maybe_schedule_email(notification, prefs)

          {:error, changeset} ->
            Logger.error("Failed to create notification: #{inspect(changeset.errors)}")
        end
      end
    end
  end

  defp maybe_schedule_email(notification, prefs) do
    if prefs.email_enabled do
      case prefs.email_frequency do
        "immediate" ->
          # Schedule immediate email delivery via Oban
          %{notification_id: notification.id}
          |> Cadence.Notifications.EmailWorker.new()
          |> Oban.insert()

        "daily_digest" ->
          # Notifications will be batched by DigestWorker
          :ok

        "weekly_digest" ->
          # Notifications will be batched by DigestWorker
          :ok

        _ ->
          :ok
      end
    end
  end
end
