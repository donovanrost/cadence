defmodule Cadence.Notifications.Recipient do
  @moduledoc "Fresh human recipient authorization shared by inbox reads and actions."
  alias Cadence.Accounts
  alias Cadence.Accounts.User
  alias Cadence.Auth.Scope

  def authorize(%Scope{actor_kind: :user, user: %{user_id: id}}) when is_binary(id) do
    case Accounts.fetch_user(id) do
      {:ok, %User{lifecycle_state: :active} = user} -> {:ok, user}
      _ -> {:error, :unavailable}
    end
  end

  def authorize(_), do: {:error, :unavailable}
end
