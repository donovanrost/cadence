defmodule CadenceWeb.OrganizationInvitationController do
  use CadenceWeb, :controller

  import Phoenix.Component, only: [to_form: 2]

  alias Cadence.Auth.Scope
  alias CadenceWeb.AuthenticatedEntry
  alias CadenceWeb.ControlPlaneParams

  def show(conn, %{"invitation_token" => invitation_token}) do
    case invitation_assigns(invitation_token) do
      {:ok, assigns} ->
        render_invitation(
          conn,
          Map.put(
            assigns,
            :form,
            acceptance_form(%{"display_name" => assigns.invitation.display_name || ""})
          ),
          nil
        )

      {:error, reason} ->
        conn
        |> put_status(error_status(reason))
        |> render_invitation(
          unavailable_invitation_assigns(invitation_token),
          error_message(reason)
        )
    end
  end

  def update(conn, %{"invitation_token" => invitation_token} = params) do
    case acceptance_params(params) do
      {:ok, acceptance_params} ->
        form = acceptance_form(acceptance_params)

        with {:ok, acceptance_attrs} <-
               ControlPlaneParams.organization_invitation_acceptance(acceptance_params),
             {:ok, acceptance_result} <-
               Cadence.accept_organization_invitation(invitation_token, acceptance_attrs) do
          finalize_acceptance(conn, acceptance_result)
        else
          {:error, reason} ->
            render_acceptance_error(conn, invitation_token, form, reason)
        end

      {:error, reason} ->
        conn
        |> put_status(error_status(reason))
        |> render_invitation(
          unavailable_invitation_assigns(invitation_token),
          error_message(reason)
        )
    end
  end

  defp render_acceptance_error(conn, invitation_token, form, reason) do
    case invitation_assigns(invitation_token) do
      {:ok, assigns} ->
        conn
        |> put_status(error_status(reason))
        |> render_invitation(Map.put(assigns, :form, form), error_message(reason))

      {:error, invitation_reason} ->
        conn
        |> put_status(error_status(invitation_reason))
        |> render_invitation(
          unavailable_invitation_assigns(invitation_token, form),
          error_message(invitation_reason)
        )
    end
  end

  defp finalize_acceptance(conn, acceptance_result) do
    conn
    |> renew_browser_session()
    |> put_session(:user_session_token, acceptance_result.session_token)
    |> put_session(:current_organization_id, acceptance_result.current_organization_id)
    |> put_flash(:info, "Invitation accepted. Your durable operator account is ready.")
    |> redirect(to: redirect_target(acceptance_result))
  end

  defp render_invitation(conn, assigns, error_message) do
    conn
    |> put_layout(html: {CadenceWeb.Layouts, :auth})
    |> render(:show, Map.merge(assigns, %{error_message: error_message}))
  end

  defp invitation_assigns(invitation_token) when is_binary(invitation_token) do
    with {:ok, invitation} <- Cadence.fetch_organization_invitation(invitation_token),
         {:ok, organization} <- Cadence.fetch_organization(invitation.organization_id) do
      {:ok,
       %{
         invitation_token: invitation_token,
         invitation: invitation,
         organization: organization,
         invitation_available?: true
       }}
    end
  end

  defp unavailable_invitation_assigns(invitation_token, form \\ acceptance_form()) do
    %{
      invitation_token: invitation_token,
      invitation: nil,
      organization: nil,
      invitation_available?: false,
      form: form
    }
  end

  defp acceptance_form(params \\ %{}) do
    to_form(params, as: :organization_invitation_acceptance)
  end

  defp acceptance_params(params) do
    case Map.get(params, "organization_invitation_acceptance", %{}) do
      acceptance_params when is_map(acceptance_params) -> {:ok, acceptance_params}
      _other -> {:error, :invalid_organization_invitation_acceptance_payload}
    end
  end

  defp redirect_target(acceptance_result) do
    current_scope =
      case Cadence.authenticate_api_token(acceptance_result.session_token,
             current_organization_id: acceptance_result.current_organization_id
           ) do
        {:ok, %Scope{} = current_scope} -> current_scope
        {:error, _reason} -> acceptance_result.user
      end

    AuthenticatedEntry.redirect_path(nil, current_scope)
  end

  defp error_status(:organization_invitation_not_found), do: :not_found
  defp error_status(:organization_invitation_expired), do: :gone
  defp error_status(:organization_invitation_unavailable), do: :gone
  defp error_status(_reason), do: :unprocessable_entity

  defp error_message(:organization_invitation_not_found) do
    "This invitation link is not valid."
  end

  defp error_message(:organization_invitation_expired) do
    "This invitation link has expired."
  end

  defp error_message(:organization_invitation_unavailable) do
    "This invitation can no longer be used."
  end

  defp error_message(:invalid_organization_invitation_acceptance_payload) do
    "Submit a valid invitation acceptance form."
  end

  defp error_message({:invalid_param, _field, :required}) do
    "Enter your name, password, and password confirmation."
  end

  defp error_message({:invalid_param, "password_confirmation", :mismatch}) do
    "Password confirmation does not match."
  end

  defp error_message({:invalid_param, "password", :too_short}) do
    "Password must be at least 12 characters."
  end

  defp error_message(_reason) do
    "Cadence could not accept this invitation."
  end

  defp renew_browser_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end
