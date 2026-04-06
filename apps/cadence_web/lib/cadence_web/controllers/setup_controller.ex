defmodule CadenceWeb.SetupController do
  use CadenceWeb, :controller

  import Phoenix.Component, only: [to_form: 2]

  alias Ecto.Changeset

  alias Cadence.Setup.Workflow
  alias CadenceWeb.AuthenticatedEntry
  alias CadenceWeb.ControlPlaneParams

  def show(conn, _params) do
    if AuthenticatedEntry.setup_access?(conn.assigns.current_scope) do
      render_setup(conn, organization_form(), nil)
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
              |> render_setup(form, error_message(reason))
          end

        {:error, reason} ->
          conn
          |> put_status(error_status(reason))
          |> render_setup(organization_form(), error_message(reason))
      end
    else
      redirect(conn, to: AuthenticatedEntry.entry_path(conn.assigns.current_scope))
    end
  end

  defp render_setup(conn, form, error_message) do
    case setup_assigns() do
      {:ok, assigns} ->
        render(conn, :show, Map.merge(assigns, %{form: form, error_message: error_message}))

      {:error, :invalid_setup_state} ->
        render(conn, :show,
          form: form,
          error_message: error_message || error_message(:invalid_setup_state),
          current_workflow: nil,
          active_organization: nil,
          invalid_setup_state?: true,
          show_tenant_form?: false,
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
         invalid_setup_state?: false,
         show_tenant_form?: current_workflow.current_step == :pending_tenant_creation,
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

  defp organization_params(params) do
    case Map.get(params, "organization", %{}) do
      organization_params when is_map(organization_params) -> {:ok, organization_params}
      _other -> {:error, :invalid_organization_payload}
    end
  end

  defp setup_step_title(:pending_tenant_creation), do: "Create the first tenant"
  defp setup_step_title(:pending_durable_admin_handoff), do: "Prepare the durable admin handoff"
  defp setup_step_title(:pending_completion), do: "Complete first-run setup"
  defp setup_step_title(:completed), do: "Setup is complete"

  defp setup_step_body(:pending_tenant_creation) do
    "Temporary setup access can create the first durable organization tenant, but it does not create tenant membership yet."
  end

  defp setup_step_body(:pending_durable_admin_handoff) do
    "The first tenant now exists and is the active setup context. The next setup slice will establish the first durable human handoff."
  end

  defp setup_step_body(:pending_completion) do
    "Cadence still needs an explicit completion handoff before temporary setup access can be retired."
  end

  defp setup_step_body(:completed) do
    "First-run setup has completed and Cadence can route durable operators into the normal shell."
  end

  defp error_status(:invalid_setup_state), do: :conflict
  defp error_status(:setup_tenant_already_created), do: :conflict
  defp error_status(:forbidden), do: :forbidden
  defp error_status(_reason), do: :unprocessable_entity

  defp error_message(:invalid_organization_payload) do
    "Submit a valid first-tenant form."
  end

  defp error_message(:invalid_setup_state) do
    "Cadence found an invalid first-run setup state."
  end

  defp error_message(:setup_tenant_already_created) do
    "The first tenant has already been created for this deployment."
  end

  defp error_message({:invalid_param, _field, _reason}) do
    "Enter both the tenant name and slug."
  end

  defp error_message(%Changeset{} = changeset) do
    changeset
    |> translate_errors()
    |> List.first()
    |> case do
      nil -> "Cadence could not create the first tenant."
      %{field: field, reason: reason} -> "#{field_label(field)} #{reason}"
    end
  end

  defp error_message(_reason) do
    "Cadence could not create the first tenant."
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
  defp field_label(field), do: Phoenix.Naming.humanize(field)
end
