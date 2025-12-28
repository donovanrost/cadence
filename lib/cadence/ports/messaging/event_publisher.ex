defmodule Cadence.Ports.Messaging.EventPublisher do
  @moduledoc """
  Port (behavior) defining the contract for publishing domain events.

  This behavior abstracts event broadcasting from the domain, enabling:
  - Unit testing without PubSub dependencies
  - Swapping message brokers (Phoenix.PubSub, RabbitMQ, Kafka, etc.)
  - Clear separation between business logic and infrastructure

  ## Topic Naming Convention

  Events are published to hierarchical topics:
  - `"organization:{org_id}:alarms"` - All alarms for an organization
  - `"mission:{mission_id}:alarms"` - Mission-specific alarms
  - `"mission:{mission_id}:commands"` - Mission-specific commands
  - `"mission:{mission_id}:telemetry"` - Mission telemetry updates

  ## Implementations

  - `Cadence.Adapters.Messaging.PhoenixEventPublisher` - Production via Phoenix.PubSub
  - `Cadence.Test.Adapters.FakeEventPublisher` - Collects events for test assertions
  """

  @type topic :: String.t()
  @type event_type :: atom()
  @type payload :: map() | struct()
  @type event :: {event_type(), payload()}
  @type opts :: keyword()

  @doc """
  Publishes an event to a topic.

  Returns `:ok` on success. Broadcasting is typically fire-and-forget.

  ## Example

      EventPublisher.publish("mission:abc123:alarms", {:alarm_triggered, alarm})
  """
  @callback publish(topic(), event()) :: :ok

  @doc """
  Publishes an event with additional options.

  ## Options

  - `:dispatcher` - Custom dispatcher module (PubSub-specific)
  - `:metadata` - Additional metadata to include with the event
  """
  @callback publish(topic(), event(), opts()) :: :ok

  @doc """
  Publishes multiple events to the same topic atomically.

  Useful when a single operation generates multiple events that should
  be delivered together.
  """
  @callback publish_batch(topic(), [event()]) :: :ok

  @doc """
  Subscribes the current process to a topic.

  Returns `:ok` on success. The process will receive messages matching
  the event format used in `publish/2`.
  """
  @callback subscribe(topic()) :: :ok | {:error, term()}

  @doc """
  Unsubscribes the current process from a topic.
  """
  @callback unsubscribe(topic()) :: :ok

  @doc """
  Returns the configured event publisher implementation.
  """
  @spec impl() :: module()
  def impl do
    Application.get_env(
      :cadence,
      :event_publisher,
      Cadence.Adapters.Messaging.PhoenixEventPublisher
    )
  end
end
