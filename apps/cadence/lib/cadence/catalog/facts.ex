defmodule Cadence.Catalog.Facts do
  @moduledoc "Public catalog fact publisher for committed catalog transitions."

  alias Cadence.Platform.EventBus

  @topic {:cadence, :catalog, :facts}

  @spec subscribe(GenServer.server()) :: :ok
  def subscribe(subscriber \\ self()), do: EventBus.subscribe(@topic, subscriber)

  @spec publish(term()) :: :ok
  def publish(fact), do: EventBus.publish(@topic, fact)
end
