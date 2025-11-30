defmodule Cadence.Alarms.Notifications.Dispatcher do
  @moduledoc """
  Routes alarm notifications to configured channels.

  The dispatcher parses notification channel identifiers from alarm rules
  and routes notifications to the appropriate notifier implementations.

  ## Channel Format

  Channels are specified as `"type:name"` strings:

  - `type` - The notifier type (webhook, email, slack, pagerduty, etc.)
  - `name` - A configuration name that maps to stored credentials/settings

  Examples:
  - `"webhook:ops"` - Send to webhook with config named "ops"
  - `"email:oncall"` - Send email using "oncall" configuration
  - `"slack:alerts"` - Post to Slack channel using "alerts" config

  ## Configuration Storage

  Channel configurations are stored in the organization's settings.
  This is a stub implementation - actual configuration storage will be
  added when notification channels are implemented.

  ## Usage

      # From TelemetryLimitHandler after creating an alarm
      Dispatcher.dispatch(alarm, :triggered, rule)

      # After acknowledging
      Dispatcher.dispatch(alarm, :acknowledged, rule)
  """

  require Logger

  alias Cadence.Alarms.Alarm
  alias Cadence.Alarms.AlarmRule

  @type event_type :: :triggered | :escalated | :acknowledged | :cleared | :shelved | :unshelved

  @doc """
  Dispatches notifications to all configured channels for an alarm event.

  This is an async operation - notifications are queued and sent in the background.
  Failures are logged but do not affect the alarm processing.
  """
  @spec dispatch(Alarm.t(), event_type(), AlarmRule.t() | nil) :: :ok
  def dispatch(%Alarm{} = alarm, event_type, rule) do
    channels = get_channels(rule)

    if Enum.empty?(channels) do
      Logger.debug("No notification channels configured for alarm #{alarm.id}")
    else
      # In a full implementation, this would queue notifications for async delivery
      # For now, we just log what would be sent
      Enum.each(channels, fn channel ->
        dispatch_to_channel(alarm, event_type, rule, channel)
      end)
    end

    :ok
  end

  @doc """
  Parses a channel identifier into type and name.

  ## Examples

      iex> parse_channel("webhook:ops")
      {:ok, "webhook", "ops"}

      iex> parse_channel("invalid")
      {:error, :invalid_format}
  """
  @spec parse_channel(String.t()) :: {:ok, String.t(), String.t()} | {:error, :invalid_format}
  def parse_channel(channel) when is_binary(channel) do
    case String.split(channel, ":", parts: 2) do
      [type, name] when byte_size(type) > 0 and byte_size(name) > 0 ->
        {:ok, type, name}

      _ ->
        {:error, :invalid_format}
    end
  end

  @doc """
  Returns the list of supported notifier types.

  This will be expanded as notifiers are implemented.
  """
  @spec supported_types() :: [String.t()]
  def supported_types do
    [
      "webhook",
      "email",
      "slack",
      "pagerduty",
      "teams"
    ]
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp get_channels(nil), do: []
  defp get_channels(%AlarmRule{notification_channels: nil}), do: []
  defp get_channels(%AlarmRule{notification_channels: channels}), do: channels

  defp dispatch_to_channel(%Alarm{} = alarm, event_type, _rule, channel) do
    case parse_channel(channel) do
      {:ok, type, name} ->
        Logger.info(
          "Would notify #{type}:#{name} about alarm #{alarm.id} (#{event_type}): #{alarm.message}"
        )

        # TODO: Implement actual notification dispatch
        # This will involve:
        # 1. Looking up the notifier module for the type
        # 2. Fetching the configuration for the name
        # 3. Calling notifier.notify(alarm, event_type, rule, config)
        # 4. Handling retries and failures
        :ok

      {:error, :invalid_format} ->
        Logger.warning("Invalid notification channel format: #{channel}")
        :ok
    end
  end
end
