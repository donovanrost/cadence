defmodule CadenceWeb.Plugs.AssignUserMenuContext do
  @moduledoc """
  Assigns `:user_menu_memberships` and `:user_menu_platform_admin?` on the
  connection so the `CadenceWeb.UI.user_menu/1` component can render for
  controller-backed pages.
  """

  import Plug.Conn

  alias Cadence.Auth.Scope

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> assign(:user_menu_memberships, memberships_for(conn))
    |> assign(:user_menu_platform_admin?, platform_admin?(conn))
  end

  defp memberships_for(%Plug.Conn{assigns: %{current_scope: %Scope{user: %{user_id: user_id}}}})
       when is_binary(user_id) do
    Cadence.Accounts.list_user_memberships(user_id)
  end

  defp memberships_for(_conn), do: []

  defp platform_admin?(%Plug.Conn{assigns: %{current_scope: %Scope{} = scope}}),
    do: Scope.platform_admin_eligible?(scope)

  defp platform_admin?(_conn), do: false
end
