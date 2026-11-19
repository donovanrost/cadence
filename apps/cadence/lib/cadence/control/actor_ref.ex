defmodule Cadence.Control.ActorRef do
  @moduledoc """
  The console's actor for a stored actor id: `%{kind, id, name}` with the console's actor kinds.
  A user is named by their display name, a service identity of the organization by its name;
  anything else is `system` with no name.
  """

  alias Cadence.{Accounts, Auth}

  @spec resolve(binary() | nil, binary()) :: %{kind: binary(), id: binary(), name: binary() | nil}
  def resolve(organization_id, id) when is_binary(id) do
    case Accounts.fetch_user(id) do
      {:ok, user} -> %{kind: "user", id: id, name: user.display_name || user.email}
      _not_a_user -> service_or_system(organization_id, id)
    end
  end

  defp service_or_system(organization_id, id) when is_binary(organization_id) do
    case Auth.fetch_service_identity(organization_id, id) do
      {:ok, identity} -> %{kind: "service", id: id, name: identity.display_name}
      _unknown -> %{kind: "system", id: id, name: nil}
    end
  end

  defp service_or_system(_organization_id, id), do: %{kind: "system", id: id, name: nil}
end
