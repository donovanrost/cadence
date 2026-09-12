defmodule Cadence.Administration.Access do
  @moduledoc "Fresh platform administrator admission after the host checks session admin mode."
  alias Cadence.Accounts
  alias Cadence.Accounts.User
  alias Cadence.Auth.Scope

  def authorize(%Scope{actor_kind: :user, user: %{user_id: id}} = scope) do
    with true <- Scope.admin_mode?(scope),
         {:ok, %User{lifecycle_state: :active} = user} <- Accounts.fetch_user(id),
         true <- Scope.platform_admin_eligible?(Scope.new(%{user: user})) do
      {:ok, user}
    else
      _ -> {:error, :unavailable}
    end
  end

  def authorize(_), do: {:error, :unavailable}
end
