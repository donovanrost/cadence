defmodule Cadence.Accounts.Scope do
  @moduledoc """
  Defines the scope of the caller to be used throughout the app.

  The `Cadence.Accounts.Scope` allows public interfaces to receive
  information about the caller, such as if the call is initiated from an
  end-user, and if so, which user. Additionally, such a scope can carry fields
  such as "super user" or other privileges for use as authorization, or to
  ensure specific code paths can only be access for a given scope.

  It is useful for logging as well as for scoping pubsub subscriptions and
  broadcasts when a caller subscribes to an interface or performs a particular
  action.

  Feel free to extend the fields on this struct to fit the needs of
  growing application requirements.
  """

  alias Cadence.Accounts.User
  alias Cadence.Organizations.Organization

  defstruct [
    :user,
    :current_organization,
    :all_organizations,
    system_admin?: false
  ]

  @doc """
  Creates a scope for the given user.

  Returns nil if no user is given.

  Options:
  - `:current_organization_id` - The ID of the organization to set as current (defaults to first org)
  - `:preload_organizations` - Whether to preload all organizations (defaults to true)
  """
  def for_user(user_or_nil, opts \\ [])

  def for_user(%User{} = user, opts) do
    preload_orgs? = Keyword.get(opts, :preload_organizations, true)

    user =
      if preload_orgs? do
        Cadence.Repo.preload(user, :organization_memberships, force: true)
        |> Cadence.Repo.preload([organization_memberships: :organization], force: true)
        # Preload deprecated association
        |> Cadence.Repo.preload(:organization, force: true)
      else
        user
      end

    organizations = get_user_organizations(user)
    current_org = get_current_organization(user, organizations, opts)

    %__MODULE__{
      user: user,
      current_organization: current_org,
      all_organizations: organizations,
      system_admin?: user.system_admin
    }
  end

  def for_user(nil, _opts), do: nil

  @doc """
  Switches the current organization for the scope.

  Returns {:ok, scope} if the user has access to the organization,
  {:error, :unauthorized} otherwise.
  """
  def switch_organization(%__MODULE__{} = scope, organization_id) do
    case Enum.find(scope.all_organizations, &(&1.id == organization_id)) do
      %Organization{} = org ->
        {:ok, %{scope | current_organization: org}}

      nil ->
        {:error, :unauthorized}
    end
  end

  @doc """
  Returns true if the scope represents a system admin.
  """
  def system_admin?(%__MODULE__{system_admin?: system_admin?}), do: system_admin?
  def system_admin?(_), do: false

  defp get_user_organizations(%User{organization_memberships: memberships})
       when is_list(memberships) do
    Enum.map(memberships, & &1.organization)
  end

  defp get_user_organizations(_), do: []

  defp get_current_organization(user, organizations, opts) do
    cond do
      # If current_organization_id is specified, use it
      org_id = Keyword.get(opts, :current_organization_id) ->
        Enum.find(organizations, &(&1.id == org_id))

      # If user has deprecated organization_id, use it for backward compatibility
      user.organization_id && user.organization ->
        user.organization

      # Otherwise use first organization
      true ->
        List.first(organizations)
    end
  end
end
