defmodule Cadence.Runtime.Facts do
  @moduledoc "Public data-plane fact publisher."

  alias Cadence.Platform.EventBus

  @topic {:cadence, :runtime, :facts}

  @spec subscribe(GenServer.server()) :: :ok
  def subscribe(subscriber \\ self()), do: EventBus.subscribe(@topic, subscriber)

  @spec publish(term()) :: :ok
  def publish(fact), do: EventBus.publish(@topic, fact)
end
