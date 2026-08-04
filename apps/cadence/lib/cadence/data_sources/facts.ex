defmodule Cadence.DataSources.Facts do
  @moduledoc "Public fact publisher for committed Data Sources transitions."

  alias Cadence.Platform.EventBus

  @topic {:cadence, :data_sources, :facts}

  @spec subscribe(GenServer.server()) :: :ok
  def subscribe(subscriber \\ self()), do: EventBus.subscribe(@topic, subscriber)

  @spec publish(term()) :: :ok
  def publish(fact), do: EventBus.publish(@topic, fact)
end
