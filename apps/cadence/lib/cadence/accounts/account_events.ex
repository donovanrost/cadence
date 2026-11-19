defmodule Cadence.Accounts.AccountEvents do
  @moduledoc """
  Changes a person made to their own sign-in, for the organization audit: `password_changed`
  (`details.other_sessions_signed_out`), `session_signed_out` (`details.session_id`,
  `details.current`) and `other_sessions_signed_out` (`details.count`). The actor is the
  signed-in user (always the account's owner today). Entries hold ids and counts, never a
  password, token or digest.
  """

  import Ecto.Query

  alias Cadence.Accounts.AccountEventRow
  alias Cadence.Ids
  alias Cadence.Repo

  @actions ~w(password_changed session_signed_out other_sessions_signed_out)

  @spec record(binary(), binary(), String.t(), map()) :: :ok
  def record(user_id, actor_id, action, details) when action in @actions do
    Repo.insert!(%AccountEventRow{
      account_event_id: Ids.new("acev"),
      user_id: user_id,
      actor_id: actor_id,
      action: action,
      details: details,
      occurred_at: DateTime.utc_now()
    })

    :ok
  end

  @doc "These users' events, newest first, at most `limit`."
  @spec list([binary()], pos_integer()) :: [map()]
  def list([], _limit), do: []

  def list(user_ids, limit) do
    AccountEventRow
    |> where([e], e.user_id in ^user_ids)
    |> order_by([e], desc: e.occurred_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(
      &%{
        id: &1.account_event_id,
        user_id: &1.user_id,
        actor_id: &1.actor_id,
        action: &1.action,
        details: &1.details,
        at: &1.occurred_at
      }
    )
  end
end
