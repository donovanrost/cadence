defmodule Cadence.Alarms.Notifications.Notifier do
  @moduledoc """
  Behaviour for alarm notification handlers.

  Implement this behaviour to create custom notification channels
  (webhook, email, Slack, PagerDuty, etc.).

  ## Example Implementation

      defmodule Cadence.Alarms.Notifications.WebhookNotifier do
        @behaviour Cadence.Alarms.Notifications.Notifier

        @impl true
        def notify(alarm, event_type, rule, config) do
          url = config["url"]
          payload = build_payload(alarm, event_type)

          case HTTPoison.post(url, Jason.encode!(payload), headers()) do
            {:ok, %{status_code: code}} when code in 200..299 ->
              :ok
            {:ok, response} ->
              {:error, {:http_error, response.status_code}}
            {:error, reason} ->
              {:error, reason}
          end
        end

        @impl true
        def validate_config(config) do
          if Map.has_key?(config, "url") do
            :ok
          else
            {:error, "url is required"}
          end
        end
      end

  ## Configuration

  Notification channels are configured in alarm rules via the
  `notification_channels` field. The format is `"type:name"` where:

  - `type` - The notifier type (e.g., "webhook", "email", "slack")
  - `name` - A configuration name that maps to settings

  Example: `["webhook:ops", "email:oncall"]`
  """

  alias Cadence.Alarms.Alarm
  alias Cadence.Alarms.AlarmRule

  @type event_type :: :triggered | :escalated | :acknowledged | :cleared | :shelved | :unshelved
  @type config :: map()
  @type error :: {:error, term()}

  @doc """
  Sends a notification for an alarm event.

  ## Parameters

  - `alarm` - The alarm that triggered the notification
  - `event_type` - What happened (:triggered, :escalated, :cleared, etc.)
  - `rule` - The alarm rule that generated this alarm (may be nil)
  - `config` - Channel-specific configuration

  ## Returns

  - `:ok` on success
  - `{:error, reason}` on failure
  """
  @callback notify(
              alarm :: Alarm.t(),
              event_type :: event_type(),
              rule :: AlarmRule.t() | nil,
              config :: config()
            ) :: :ok | error()

  @doc """
  Validates the configuration for this notifier type.

  Called when configuring notification channels to ensure the
  configuration is valid before saving.

  ## Returns

  - `:ok` if valid
  - `{:error, reason}` if invalid
  """
  @callback validate_config(config :: config()) :: :ok | error()

  @optional_callbacks [validate_config: 1]
end
