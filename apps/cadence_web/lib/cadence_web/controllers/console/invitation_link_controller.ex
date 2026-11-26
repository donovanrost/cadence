defmodule CadenceWeb.Console.InvitationLinkController do
  @moduledoc """
  L5 invitation links for the console (`/api/v1/auth/invitations/:token`), signed in or
  out. The server decides the case from the token and the session; the client never says which
  account it is. Accepting by an existing account goes through its current password and the
  attempt limit (748fcbc9); joining as the signed-in user and declining reuse api's L21 functions.
  Contract: docs/apogee/api/session.md §Sign-in and invitation links.
  """

  use CadenceWeb, :controller

  alias Cadence.Accounts
  alias Cadence.Auth.Scope
  alias CadenceWeb.Console.{Problem, SignInController}

  @closed %{expired: "expired", withdrawn: "withdrawn", used: "used", declined: "declined"}

  def show(conn, %{"token" => token}) do
    case Accounts.inspect_invitation_token(token) do
      {:ok, view} -> json(conn, %{data: body(view, kase(view, conn.assigns.current_scope))})
      {:error, :not_found} -> json(conn, %{data: unknown()})
    end
  end

  def accept(conn, %{"token" => token} = params) do
    with {:ok, view} <- open(token),
         kase = kase(view, conn.assigns.current_scope),
         :ok <- expected_kind(params["kind"], kase),
         {:ok, conn, organization_id} <- join(conn, kase, view, token, params) do
      conn
      |> put_session(:current_organization_id, organization_id)
      |> json(%{data: %{organization_id: organization_id, redirect_to: "/console"}})
    else
      error -> respond(conn, error)
    end
  end

  def decline(conn, %{"token" => token}) do
    scope = conn.assigns.current_scope

    with {:ok, view} <- open(token),
         "signed_in_match" <- kase(view, scope),
         {:ok, _declined} <-
           Accounts.decline_invitation_as_user(scope.user.user_id, view.invitation_id) do
      send_resp(conn, :no_content, "")
    else
      "signed_in_other" -> Problem.respond(conn, :invitation_for_another_account)
      kase when is_binary(kase) -> Problem.respond(conn, :unauthenticated)
      error -> respond(conn, error)
    end
  end

  # Joining as the signed-in user it's addressed to.
  defp join(conn, "signed_in_match", view, _token, _params) do
    case Accounts.accept_invitation_as_user(
           conn.assigns.current_scope.user.user_id,
           view.invitation_id
         ) do
      {:ok, %{membership: membership}} -> {:ok, conn, membership.organization_id}
      {:error, reason} -> {:error, reason}
    end
  end

  defp join(_conn, "signed_in_other", _view, _token, _params),
    do: {:error, :invitation_for_another_account}

  # Signed out: a new account (name + new password) or an existing one (its current password).
  defp join(conn, kase, _view, token, params) when kase in ~w(new_account existing_account) do
    attrs =
      if kase == "new_account",
        do: %{display_name: params["name"], password: params["password"]},
        else: %{password: to_string(params["password"] || "")}

    case Accounts.accept_organization_invitation(token, attrs, ip: conn.remote_ip) do
      {:ok, accepted} ->
        {:ok, SignInController.start_session(conn, accepted), accepted.current_organization_id}

      error ->
        error
    end
  end

  # The client says which form it showed (`kind`); if the server now sees another case (signed
  # in or out meanwhile), it refuses rather than guess.
  defp expected_kind(nil, _kase), do: :ok
  defp expected_kind(kase, kase), do: :ok
  defp expected_kind(_kind, kase), do: {:error, {:case_changed, kase}}

  defp open(token) do
    case Accounts.inspect_invitation_token(token) do
      {:ok, %{state: :open} = view} -> {:ok, view}
      {:ok, %{state: state}} -> {:error, {:closed, Map.fetch!(@closed, state)}}
      {:error, :not_found} -> {:error, :invitation_not_found}
    end
  end

  defp kase(%{state: :open} = view, %Scope{user: %{email: email}}) do
    if normalize(email) == normalize(view.email), do: "signed_in_match", else: "signed_in_other"
  end

  defp kase(%{state: :open, account?: true}, _signed_out), do: "existing_account"
  defp kase(%{state: :open}, _signed_out), do: "new_account"
  defp kase(%{state: state}, _scope), do: Map.fetch!(@closed, state)

  defp normalize(email), do: email |> to_string() |> String.trim() |> String.downcase()

  defp body(view, kase) do
    open? = kase in ~w(new_account existing_account signed_in_match signed_in_other)

    %{
      case: kase,
      organization: %{name: view.organization.name},
      role: view.membership_role,
      invited_by: view.invited_by,
      invited_at: view.invited_at,
      # Only for an open invitation: the holder got this email, and signed_in_other shows it.
      email: if(open?, do: view.email),
      expires_at: view.expires_at
    }
  end

  defp unknown,
    do: %{
      case: "unknown",
      organization: nil,
      role: nil,
      invited_by: nil,
      invited_at: nil,
      email: nil,
      expires_at: nil
    }

  defp respond(conn, {:error, {:case_changed, kase}}),
    do: Problem.respond(conn, :invitation_case_changed, %{case: kase})

  defp respond(conn, {:error, {:closed, kase}}),
    do: Problem.respond(conn, :invitation_unavailable, %{case: kase})

  defp respond(conn, {:error, reason})
       when reason in [:invitation_not_found, :organization_invitation_not_found],
       do: Problem.respond(conn, :invitation_not_found)

  defp respond(conn, {:error, reason})
       when reason in [
              :organization_invitation_unavailable,
              :organization_invitation_expired,
              :invitation_not_pending,
              :invitation_expired
            ],
       do: Problem.respond(conn, :invitation_unavailable, %{case: "unavailable"})

  defp respond(conn, {:error, :invitation_for_another_account}),
    do: Problem.respond(conn, :invitation_for_another_account)

  defp respond(conn, {:error, :invalid_credentials}),
    do: Problem.respond(conn, :credentials_incorrect)

  defp respond(conn, {:error, {:too_many_attempts, retry_after}}) do
    conn
    |> put_resp_header("retry-after", Integer.to_string(retry_after))
    |> Problem.respond(:too_many_attempts, %{retry_after: retry_after})
  end

  defp respond(conn, {:error, :account_disabled}), do: Problem.respond(conn, :account_disabled)

  defp respond(conn, {:error, {:invalid_param, "display_name", _why}}),
    do: Problem.respond(conn, :invalid_params, %{name: "is required"})

  defp respond(conn, {:error, {:invalid_param, "password", :too_short}}),
    do: Problem.respond(conn, :invalid_params, %{password: "must be at least 12 characters"})

  defp respond(conn, {:error, {:invalid_param, "password", _why}}),
    do: Problem.respond(conn, :invalid_params, %{password: "is required"})

  defp respond(conn, {:error, :email_mismatch}),
    do: Problem.respond(conn, :invitation_for_another_account)

  defp respond(conn, _error),
    do: Problem.respond(conn, :invitation_unavailable, %{case: "unavailable"})
end
