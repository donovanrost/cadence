defmodule Cadence.Administration.PlatformNames do
  @moduledoc """
  People's names for the platform admin area (console L7: Admin › Organizations, Service
  identities, Audit), across organizations (#470). Its readers are platform administrators in
  admin mode, and that is enforced here: every call passes `Administration.Access` first, so it
  can't name anyone for a caller who isn't one (api-ops). Display name only, never the email;
  `nil` without one.

  A customer organization's reads name people by #146's rule C1 instead (`Control.ActorRef`).
  Only `Cadence.Administration.*` may call this (`PlatformNamesGuardTest`).
  """

  alias Cadence.Accounts.PlatformDirectory
  alias Cadence.Administration.Access

  @spec display_names(term(), [binary()]) ::
          {:ok, %{binary() => binary() | nil}} | {:error, term()}
  def display_names(scope, user_ids) when is_list(user_ids) do
    with {:ok, _admin} <- Access.authorize(scope),
         do: {:ok, PlatformDirectory.display_names(user_ids)}
  end
end
