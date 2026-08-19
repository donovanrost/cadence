defmodule Cadence.Activations.Facts do
  @moduledoc "Public control-plane fact publisher for committed activation transitions."

  alias Cadence.Platform.EventBus

  @topic {:cadence, :activations, :facts}

  @spec subscribe(GenServer.server()) :: :ok
  def subscribe(subscriber \\ self()), do: subscribe(EventBus, subscriber)

  @spec subscribe(EventBus.server(), GenServer.server()) :: :ok
  def subscribe(event_bus, subscriber), do: EventBus.subscribe(event_bus, @topic, subscriber)

  @spec publish(term()) :: :ok
  def publish(fact), do: publish(EventBus, fact)

  @spec publish(EventBus.server(), term()) :: :ok
  def publish(event_bus, fact), do: EventBus.publish(event_bus, @topic, fact)
end
