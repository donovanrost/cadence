defmodule CadenceWeb.AuthenticatedEntry do
  @moduledoc false

  alias Cadence.Accounts.User
  alias Cadence.Auth.Scope

  @operator_path "/operator"
  @setup_path "/setup"

  @spec entry_path(Scope.t() | User.t()) :: binary()
  def entry_path(%Scope{} = current_scope) do
    if setup_entry?(current_scope), do: @setup_path, else: @operator_path
  end

  def entry_path(%User{} = user) do
    if setup_entry?(user), do: @setup_path, else: @operator_path
  end

  @spec redirect_path(binary() | nil, Scope.t() | User.t()) :: binary()
  def redirect_path(return_to, actor) when is_binary(return_to) do
    if entry_route?(return_to), do: entry_path(actor), else: return_to
  end

  def redirect_path(_return_to, actor), do: entry_path(actor)

  @spec setup_access?(Scope.t() | User.t()) :: boolean()
  def setup_access?(%Scope{} = current_scope), do: setup_entry?(current_scope)
  def setup_access?(%User{} = user), do: setup_entry?(user)

  defp setup_entry?(%Scope{} = current_scope) do
    Cadence.initial_setup_pending?() and Scope.temporary_setup_access?(current_scope)
  end

  defp setup_entry?(%User{} = user) do
    Cadence.initial_setup_pending?() and User.temporary_setup_access?(user)
  end

  defp entry_route?(path) when is_binary(path) do
    exact_or_query_path?(path, "/") or
      exact_or_query_path?(path, "/sign-in") or
      exact_or_query_path?(path, @operator_path) or
      exact_or_query_path?(path, @setup_path)
  end

  defp exact_or_query_path?(path, "/"), do: path == "/" or String.starts_with?(path, "/?")

  defp exact_or_query_path?(path, base_path) when is_binary(path) and is_binary(base_path) do
    path == base_path or String.starts_with?(path, base_path <> "?")
  end
end
