defmodule CadenceWeb.SetupController do
  use CadenceWeb, :controller

  import Phoenix.Component, only: [to_form: 2]

  alias Ecto.Changeset

  alias Cadence.Accounts.OrganizationInvitation
  alias Cadence.Setup.Workflow
  alias CadenceWeb.AuthenticatedEntry
  alias CadenceWeb.ControlPlaneParams
  alias CadenceWeb.UserNotifier

  def show(conn, _params) do
    if AuthenticatedEntry.setup_access?(conn.assigns.current_scope) do
      render_setup(conn, organization_form(), handoff_form(), nil)
    else
      redirect(conn, to: AuthenticatedEntry.entry_path(conn.assigns.current_scope))
    end
  end

  def create(conn, params) do
    if AuthenticatedEntry.setup_access?(conn.assigns.current_scope) do
      case organization_params(params) do
        {:ok, organization_params} ->
          form = organization_form(organization_params)

          with {:ok, organization} <- ControlPlaneParams.organization(organization_params),
               {:ok, _result} <-
                 Cadence.create_initial_setup_organization(
                   conn.assigns.current_scope,
                   organization
                 ) do
            conn
            |> put_flash(
              :info,
              "First tenant created. Continue setup to establish the durable admin handoff."
            )
            |> redirect(to: "/setup")
          else
            {:error, reason} ->
              conn
              |> put_status(error_status(reason))
              |> render_setup(form, handoff_form(), error_message(reason))
          end

        {:error, reason} ->
          conn
          |> put_status(error_status(reason))
          |> render_setup(organization_form(), handoff_form(), error_message(reason))
      end
    else
      redirect(conn, to: AuthenticatedEntry.entry_path(conn.assigns.current_scope))
    end
  end

  def handoff(conn, params) do
    if AuthenticatedEntry.setup_access?(conn.assigns.current_scope) do
      case handoff_params(params) do
        {:ok, handoff_params} ->
          form = handoff_form(handoff_params)

          with {:ok, handoff} <- ControlPlaneParams.initial_admin_handoff(handoff_params),
               {:ok, %{access_result: access_result}} <-
                 Cadence.establish_initial_setup_admin_handoff(
                   conn.assigns.current_scope,
                   handoff.email,
                   membership_role: handoff.membership_role,
                   display_name: handoff.display_name
                 ),
               :ok <- maybe_deliver_invitation(conn, access_result) do
            conn
            |> put_flash(:info, success_message(access_result))
            |> redirect(to: "/setup")
          else
            {:error, reason} ->
              conn
              |> put_status(error_status(reason))
              |> render_setup(organization_form(), form, error_message(reason))
          end

        {:error, reason} ->
          conn
          |> put_status(error_status(reason))
          |> render_setup(organization_form(), handoff_form(), error_message(reason))
      end
    else
      redirect(conn, to: AuthenticatedEntry.entry_path(conn.assigns.current_scope))
    end
  end

  defp render_setup(conn, organization_form, handoff_form, error_message) do
    case setup_assigns() do
      {:ok, assigns} ->
        render(
          conn,
          :show,
          %{
            current_scope: conn.assigns.current_scope,
            form: organization_form,
            handoff_form: handoff_form,
            error_message: error_message
          }
          |> Map.merge(assigns)
        )

      {:error, :invalid_setup_state} ->
        render(conn, :show,
          current_scope: conn.assigns.current_scope,
          form: organization_form,
          handoff_form: handoff_form,
          error_message: error_message || error_message(:invalid_setup_state),
          current_workflow: nil,
          active_organization: nil,
          durable_admin_handoff: nil,
          invalid_setup_state?: true,
          show_tenant_form?: false,
          show_handoff_form?: false,
          setup_step_title: "Setup state requires operator attention",
          setup_step_body:
            "Cadence found an unexpected first-run setup state. Tenant creation is paused until the platform setup workflow is repaired."
        )
    end
  end

  defp setup_assigns do
    with {:ok, %Workflow{} = current_workflow} <- Cadence.fetch_initial_setup_workflow(),
         {:ok, active_organization} <- active_organization(current_workflow) do
      {:ok,
       %{
         current_workflow: current_workflow,
         active_organization: active_organization,
         durable_admin_handoff: Map.get(current_workflow.metadata, "durable_admin_handoff"),
         invalid_setup_state?: false,
         show_tenant_form?: current_workflow.current_step == :pending_tenant_creation,
         show_handoff_form?: current_workflow.current_step == :pending_durable_admin_handoff,
         setup_step_title: setup_step_title(current_workflow.current_step),
         setup_step_body: setup_step_body(current_workflow.current_step)
       }}
    end
  end

  defp active_organization(%Workflow{active_organization_id: nil}), do: {:ok, nil}

  defp active_organization(%Workflow{active_organization_id: active_organization_id})
       when is_binary(active_organization_id) do
    case Cadence.fetch_organization(active_organization_id) do
      {:ok, organization} -> {:ok, organization}
      {:error, :organization_not_found} -> {:error, :invalid_setup_state}
    end
  end

  defp organization_form(params \\ %{}) do
    to_form(params, as: :organization)
  end

  defp handoff_form(params \\ %{}) do
    to_form(params, as: :initial_admin_handoff)
  end

  defp organization_params(params) do
    case Map.get(params, "organization", %{}) do
      organization_params when is_map(organization_params) -> {:ok, organization_params}
      _other -> {:error, :invalid_organization_payload}
    end
  end

  defp handoff_params(params) do
    case Map.get(params, "initial_admin_handoff", %{}) do
      handoff_params when is_map(handoff_params) -> {:ok, handoff_params}
      _other -> {:error, :invalid_setup_handoff_payload}
    end
  end

  defp maybe_deliver_invitation(_conn, %{mode: :granted}), do: :ok

  defp maybe_deliver_invitation(
         _conn,
         %{
           mode: :invited,
           invitation: %OrganizationInvitation{} = invitation,
           invitation_token: invitation_token
         }
       ) do
    with {:ok, organization} <- Cadence.fetch_organization(invitation.organization_id),
         {:ok, _email} <-
           UserNotifier.deliver_organization_invitation(
             invitation,
             organization,
             url(~p"/invitations/#{invitation_token}")
           ) do
      :ok
    else
      {:error, _reason} -> {:error, :organization_invitation_delivery_failed}
    end
  end

  defp success_message(%{mode: :granted, user: user}) do
    "Durable admin handoff established for #{user.email}. Setup is now waiting on explicit completion."
  end

  defp success_message(%{mode: :invited, invitation: invitation}) do
    "Invitation sent to #{invitation.email}. Setup remains pending until the durable user accepts it."
  end

  defp setup_step_title(:pending_tenant_creation), do: "Create the first tenant"
  defp setup_step_title(:pending_durable_admin_handoff), do: "Establish the durable admin handoff"
  defp setup_step_title(:pending_completion), do: "Complete first-run setup"
  defp setup_step_title(:completed), do: "Setup is complete"

  defp setup_step_body(:pending_tenant_creation) do
    "Temporary setup access can create the first durable organization tenant, but it does not create tenant membership yet."
  end

  defp setup_step_body(:pending_durable_admin_handoff) do
    "Cadence can now create or invite the first durable human, assign platform-admin authority separately from tenant membership, and keep temporary setup access isolated."
  end

  defp setup_step_body(:pending_completion) do
    "The durable handoff has been established. Temporary setup access can now be retired once the remaining setup completion slice is finished."
  end

  defp setup_step_body(:completed) do
    "First-run setup has completed and Cadence can route durable operators into the normal shell."
  end

  defp error_status(:invalid_setup_state), do: :conflict
  defp error_status(:setup_tenant_already_created), do: :conflict
  defp error_status(:setup_handoff_unavailable), do: :conflict
  defp error_status(:forbidden), do: :forbidden
  defp error_status(:organization_invitation_delivery_failed), do: :bad_gateway
  defp error_status(_reason), do: :unprocessable_entity

  defp error_message(:invalid_organization_payload) do
    "Submit a valid first-tenant form."
  end

  defp error_message(:invalid_setup_handoff_payload) do
    "Submit a valid durable handoff form."
  end

  defp error_message(:invalid_setup_state) do
    "Cadence found an invalid first-run setup state."
  end

  defp error_message(:setup_tenant_already_created) do
    "The first tenant has already been created for this deployment."
  end

  defp error_message(:setup_handoff_unavailable) do
    "The durable admin handoff is not available for the current setup workflow state."
  end

  defp error_message(:invalid_organization_role) do
    "Select a valid organization role for the first durable membership."
  end

  defp error_message(:organization_invitation_delivery_failed) do
    "Cadence created the invitation, but email delivery failed. Submit the handoff again to issue a fresh invitation."
  end

  defp error_message({:invalid_param, "email", :required}) do
    "Enter the durable admin email."
  end

  defp error_message({:invalid_param, _field, :required}) do
    "Enter all required setup values."
  end

  defp error_message(%Changeset{} = changeset) do
    changeset
    |> translate_errors()
    |> List.first()
    |> case do
      nil -> "Cadence could not complete the requested setup step."
      %{field: field, reason: reason} -> "#{field_label(field)} #{reason}"
    end
  end

  defp error_message(_reason) do
    "Cadence could not complete the requested setup step."
  end

  defp translate_errors(%Changeset{} = changeset) do
    Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.flat_map(fn {field, messages} ->
      Enum.map(messages, fn message ->
        %{field: field, reason: message}
      end)
    end)
  end

  defp field_label(:display_name), do: "Tenant name"
  defp field_label(:slug), do: "Tenant slug"
  defp field_label(:email), do: "Email"
  defp field_label(:membership_role), do: "Organization role"
  defp field_label(field), do: Phoenix.Naming.humanize(field)
end
