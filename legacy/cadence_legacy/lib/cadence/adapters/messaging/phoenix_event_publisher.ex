defmodule Cadence.Adapters.Messaging.PhoenixEventPublisher do
  @moduledoc """
  Phoenix.PubSub implementation of the EventPublisher port.

  This adapter wraps Phoenix.PubSub to provide the standard EventPublisher
  interface for domain event broadcasting.

  ## Configuration

  Uses `Cadence.PubSub` as the PubSub server by default. This is started
  in the application supervision tree.
  """

  @behaviour Cadence.Ports.Messaging.EventPublisher

  @pubsub Cadence.PubSub

  @impl true
  def publish(topic, event) do
    publish(topic, event, [])
  end

  @impl true
  def publish(topic, event, _opts) do
    Phoenix.PubSub.broadcast(@pubsub, topic, event)
  end

  @impl true
  def publish_batch(topic, events) do
    Enum.each(events, &publish(topic, &1))
    :ok
  end

  @impl true
  def subscribe(topic) do
    Phoenix.PubSub.subscribe(@pubsub, topic)
  end

  @impl true
  def unsubscribe(topic) do
    Phoenix.PubSub.unsubscribe(@pubsub, topic)
  end
end
