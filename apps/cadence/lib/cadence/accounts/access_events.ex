defmodule Cadence.Accounts.AccessEvents do
  @moduledoc """
  Announces that a person's access changed (#1153): their membership was removed, their role
  changed, their account was deactivated. A live console channel subscribed to the person
  (`subscribe/1`) re-checks its authorization when it hears this and closes if it no longer
  passes, so a socket doesn't keep streaming after the access behind it has gone.

  Sent after the write has committed (never from inside a transaction), so a listener that
  re-reads sees the change.
  """

  alias Cadence.Repo

  @pubsub Cadence.PubSub

  @spec subscribe(binary()) :: :ok | {:error, term()}
  def subscribe(user_id) when is_binary(user_id),
    do: Phoenix.PubSub.subscribe(@pubsub, topic(user_id))

  @doc """
  Announces the change. Raises inside a transaction: a listener that re-reads before the commit
  would see the old access, and a silent drop would leave the channel open (callers announce after
  the write has committed).
  """
  @spec changed(binary()) :: :ok
  def changed(user_id) when is_binary(user_id) do
    if Repo.in_transaction?(),
      do:
        raise(
          ArgumentError,
          "AccessEvents.changed/1 must run after the commit, not inside a transaction"
        )

    if Process.whereis(@pubsub),
      do: Phoenix.PubSub.broadcast(@pubsub, topic(user_id), {:access_changed, user_id})

    :ok
  end

  defp topic(user_id), do: "access-changed:#{user_id}"
end
