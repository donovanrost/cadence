defmodule Cadence.Telemetry.Facts do
  @moduledoc "Public data-plane telemetry fact publisher."

  alias Cadence.Platform.EventBus

  @topic {:cadence, :telemetry, :facts}

  @spec subscribe(GenServer.server()) :: :ok
  def subscribe(subscriber \\ self()), do: subscribe(EventBus, subscriber)

  @spec subscribe(EventBus.server(), GenServer.server()) :: :ok
  def subscribe(event_bus, subscriber), do: EventBus.subscribe(event_bus, @topic, subscriber)

  @spec publish(term()) :: :ok
  def publish(fact), do: publish(EventBus, fact)

  @spec publish(EventBus.server(), term()) :: :ok
  def publish(event_bus, fact), do: EventBus.publish(event_bus, @topic, fact)
end
