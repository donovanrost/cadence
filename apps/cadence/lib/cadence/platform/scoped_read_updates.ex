defmodule Cadence.Platform.ScopedReadUpdates do
  @moduledoc "Scoped read invalidations shared by management and execution transaction owners."

  alias Cadence.Repo
  @pubsub Cadence.PubSub

  def subscribe(event, organization_id, mission_id) when is_atom(event),
    do: Phoenix.PubSub.subscribe(@pubsub, topic(event, organization_id, mission_id))

  def unsubscribe(event, organization_id, mission_id) when is_atom(event),
    do: Phoenix.PubSub.unsubscribe(@pubsub, topic(event, organization_id, mission_id))

  # Nested stores leave notification to their outer transaction owner. A rolled-back
  # transaction must never announce a write to another connection.
  def publish_result({:ok, _} = result, event, organization_id, mission_id) when is_atom(event) do
    publish(event, organization_id, mission_id)
    result
  end

  def publish_result(result, _, _, _), do: result

  def publish(event, organization_id, mission_id) when is_atom(event) do
    if !Repo.in_transaction?() && Process.whereis(@pubsub) do
      Phoenix.PubSub.broadcast(
        @pubsub,
        topic(event, organization_id, mission_id),
        {event, organization_id, mission_id}
      )
    end

    :ok
  end

  defp topic(event, org, mission), do: "read-updates:#{event}:#{org}:#{mission}"
end
