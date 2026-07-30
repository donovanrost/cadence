defmodule CadenceWeb.AuthenticatedEntry do
  @moduledoc false

  alias Cadence.Accounts.User
  alias Cadence.Auth.Scope

  @admin_path "/admin"
  @organization_path "/"

  @spec entry_path(Scope.t() | User.t()) :: binary()
  def entry_path(%Scope{} = scope) do
    if Scope.admin_mode?(scope),
      do: @admin_path,
      else: @organization_path
  end

  def entry_path(%User{}), do: @organization_path

  @spec redirect_path(binary() | nil, Scope.t() | User.t()) :: binary()
  def redirect_path(return_to, actor) when is_binary(return_to) do
    if entry_route?(return_to), do: entry_path(actor), else: return_to
  end

  def redirect_path(_return_to, actor), do: entry_path(actor)

  defp entry_route?(path) when is_binary(path) do
    exact_or_query_path?(path, "/") or
      exact_or_query_path?(path, "/sign-in") or
      exact_or_query_path?(path, @admin_path)
  end

  defp exact_or_query_path?(path, "/"), do: path == "/" or String.starts_with?(path, "/?")

  defp exact_or_query_path?(path, base_path) when is_binary(path) and is_binary(base_path) do
    path == base_path or String.starts_with?(path, base_path <> "?")
  end
end
