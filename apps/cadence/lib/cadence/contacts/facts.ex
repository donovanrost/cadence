defmodule Cadence.Contacts.Facts do
  @moduledoc "Public control-plane fact publisher for committed Contact transitions."

  alias Cadence.Platform.EventBus

  @topic {:cadence, :contacts, :facts}

  @spec subscribe(GenServer.server()) :: :ok
  def subscribe(subscriber \\ self()), do: EventBus.subscribe(@topic, subscriber)

  @spec publish(term()) :: :ok
  def publish(fact), do: EventBus.publish(@topic, fact)
end
