defmodule Cadence.Limits.Facts do
  @moduledoc "Public data-plane fact publisher for committed limit transitions."

  alias Cadence.Platform.EventBus

  @topic {:cadence, :limits, :facts}

  @spec subscribe(GenServer.server()) :: :ok
  def subscribe(subscriber \\ self()), do: EventBus.subscribe(@topic, subscriber)

  @spec publish(term()) :: :ok
  def publish(fact), do: EventBus.publish(@topic, fact)
end
