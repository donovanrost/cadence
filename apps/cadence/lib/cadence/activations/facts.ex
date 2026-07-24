defmodule Cadence.Activations.Facts do
  @moduledoc "Public control-plane fact publisher for committed activation transitions."

  alias Cadence.Platform.EventBus

  @topic {:cadence, :activations, :facts}

  @spec subscribe(GenServer.server()) :: :ok
  def subscribe(subscriber \\ self()), do: EventBus.subscribe(@topic, subscriber)

  @spec publish(term()) :: :ok
  def publish(fact), do: EventBus.publish(@topic, fact)
end
