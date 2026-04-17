defmodule Cadence.Setup do
  @moduledoc """
  First-run setup workflow state and transitions.
  """

  alias Cadence.Accounts
  alias Cadence.Accounts.{OrganizationInvitation, OrganizationMembership, User}
  alias Ecto.Multi

  alias Cadence.Auth.Scope
  alias Cadence.Organizations
  alias Cadence.Organizations.Organization
  alias Cadence.Persistence.Schemas.OrganizationRow
  alias Cadence.Persistence.Schemas.SetupWorkflowRow
  alias Cadence.Repo
  alias Cadence.Setup.Workflow

  @initial_setup_lock_key 4_001_039

  @spec fetch_initial_workflow() :: {:ok, Workflow.t()} | {:error, term()}
  def fetch_initial_workflow do
    fetch_initial_workflow(Repo)
  end

  defp fetch_initial_workflow(repo) do
    case repo.get(SetupWorkflowRow, Workflow.initial_workflow_id()) do
      %SetupWorkflowRow{} = row ->
        row
        |> SetupWorkflowRow.to_domain()
        |> validate_workflow()

      nil ->
        infer_initial_workflow(repo)
    end
  end

  @spec active?(Workflow.t()) :: boolean()
  def active?(%Workflow{} = workflow), do: Workflow.active?(workflow)

  @spec create_initial_organization(Scope.t(), Organization.t()) ::
          {:ok, %{organization: Organization.t(), workflow: Workflow.t()}} | {:error, term()}
  def create_initial_organization(%Scope{} = current_scope, %Organization{} = organization) do
    with :ok <- authorize_setup_access(current_scope) do
      created_by_user_id = current_scope.user.user_id

      Multi.new()
      |> Multi.run(:setup_lock, fn repo, _changes ->
        lock_initial_workflow(repo)
      end)
      |> Multi.run(:current_workflow, fn repo, _changes ->
        with {:ok, workflow} <- fetch_initial_workflow(repo),
             :ok <- ensure_pending_tenant_creation(workflow) do
          {:ok, workflow}
        end
      end)
      |> Multi.run(:organization, fn _repo, _changes ->
        Organizations.persist_organization(organization)
      end)
      |> Multi.run(:workflow, fn repo,
                                 %{
                                   current_workflow: %Workflow{} = workflow,
                                   organization: %Organization{} = persisted_organization
                                 } ->
        persist_workflow(
          repo,
          Workflow.new(%{
            setup_workflow_id: workflow.setup_workflow_id,
            current_step: :pending_durable_admin_handoff,
            active_organization_id: persisted_organization.organization_id,
            created_by_user_id: created_by_user_id,
            completed_at: nil,
            metadata: workflow.metadata
          })
        )
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{organization: persisted_organization, workflow: persisted_workflow}} ->
          {:ok, %{organization: persisted_organization, workflow: persisted_workflow}}

        {:error, _operation, reason, _changes_so_far} ->
          {:error, reason}
      end
    end
  end

  @spec establish_initial_admin_handoff(Scope.t(), binary(), keyword()) ::
          {:ok, %{workflow: Workflow.t(), access_result: Accounts.organization_access_result()}}
          | {:error, term()}
  def establish_initial_admin_handoff(%Scope{} = current_scope, email, opts \\ [])
      when is_binary(email) and is_list(opts) do
    with :ok <- authorize_setup_access(current_scope) do
      membership_role = Keyword.get(opts, :membership_role, :organization_admin)
      display_name = Keyword.get(opts, :display_name)

      Multi.new()
      |> Multi.run(:setup_lock, fn repo, _changes ->
        lock_initial_workflow(repo)
      end)
      |> Multi.run(:current_workflow, fn repo, _changes ->
        with {:ok, workflow} <- fetch_initial_workflow(repo),
             :ok <- ensure_pending_durable_admin_handoff(workflow) do
          {:ok, workflow}
        end
      end)
      |> Multi.run(:access_result, fn _repo, %{current_workflow: %Workflow{} = workflow} ->
        Accounts.establish_organization_access(email, workflow.active_organization_id,
          membership_role: membership_role,
          grant_platform_admin: true,
          invited_by_user_id: current_scope.user.user_id,
          display_name: display_name,
          membership_metadata: %{"granted_via" => "initial_setup_handoff"},
          invitation_metadata: %{
            "created_via" => "initial_setup_handoff",
            "setup_workflow_id" => workflow.setup_workflow_id
          }
        )
      end)
      |> Multi.run(:workflow, fn repo,
                                 %{
                                   current_workflow: %Workflow{} = workflow,
                                   access_result: access_result
                                 } ->
        persist_workflow(
          repo,
          Workflow.new(%{
            setup_workflow_id: workflow.setup_workflow_id,
            current_step: handoff_workflow_step(access_result),
            active_organization_id: workflow.active_organization_id,
            created_by_user_id: workflow.created_by_user_id,
            completed_at: workflow.completed_at,
            metadata: handoff_workflow_metadata(workflow.metadata, access_result)
          })
        )
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{workflow: workflow, access_result: access_result}} ->
          {:ok, %{workflow: workflow, access_result: access_result}}

        {:error, _operation, reason, _changes_so_far} ->
          {:error, reason}
      end
    end
  end

  @spec complete_initial_workflow(binary(), keyword()) :: {:ok, Workflow.t()} | {:error, term()}
  def complete_initial_workflow(active_organization_id, opts \\ [])
      when is_binary(active_organization_id) and is_list(opts) do
    existing_workflow =
      case fetch_initial_workflow() do
        {:ok, workflow} -> workflow
        {:error, _reason} -> Workflow.new(%{setup_workflow_id: Workflow.initial_workflow_id()})
      end

    workflow =
      Workflow.new(%{
        setup_workflow_id: Workflow.initial_workflow_id(),
        current_step: :completed,
        active_organization_id: active_organization_id,
        created_by_user_id:
          Keyword.get(opts, :completed_by_user_id, existing_workflow.created_by_user_id),
        completed_at: DateTime.utc_now(),
        metadata: Map.merge(existing_workflow.metadata, Keyword.get(opts, :metadata, %{}))
      })

    persist_workflow(Repo, workflow)
  end

  defp authorize_setup_access(%Scope{} = current_scope) do
    if MapSet.member?(current_scope.capabilities, :platform_admin) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp ensure_pending_tenant_creation(%Workflow{} = workflow) do
    if Workflow.pending_tenant_creation?(workflow) do
      :ok
    else
      {:error, :setup_tenant_already_created}
    end
  end

  defp ensure_pending_durable_admin_handoff(%Workflow{
         current_step: :pending_durable_admin_handoff
       }),
       do: :ok

  defp ensure_pending_durable_admin_handoff(%Workflow{}), do: {:error, :setup_handoff_unavailable}

  defp infer_initial_workflow(repo) do
    case list_organizations(repo) do
      [] ->
        {:ok,
         Workflow.new(%{
           setup_workflow_id: Workflow.initial_workflow_id(),
           current_step: :pending_tenant_creation
         })}

      [%Organization{} = organization] ->
        {:ok,
         Workflow.new(%{
           setup_workflow_id: Workflow.initial_workflow_id(),
           current_step: :completed,
           active_organization_id: organization.organization_id,
           metadata: %{"inferred" => true, "legacy_install" => true}
         })}

      _organizations ->
        {:error, :invalid_setup_state}
    end
  end

  defp lock_initial_workflow(repo) do
    case repo.query("SELECT pg_advisory_xact_lock($1)", [@initial_setup_lock_key]) do
      {:ok, _result} -> {:ok, :locked}
      {:error, reason} -> {:error, reason}
    end
  end

  defp persist_workflow(repo, %Workflow{} = workflow) do
    case repo.get(SetupWorkflowRow, workflow.setup_workflow_id) do
      nil -> insert_workflow(repo, workflow)
      %SetupWorkflowRow{} = row -> update_workflow(repo, row, workflow)
    end
  end

  defp insert_workflow(repo, %Workflow{} = workflow) do
    case repo.insert(SetupWorkflowRow.changeset(workflow)) do
      {:ok, %SetupWorkflowRow{} = row} ->
        {:ok, SetupWorkflowRow.to_domain(row)}

      {:error, %Ecto.Changeset{} = changeset} ->
        handle_insert_workflow_error(repo, workflow, changeset)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_workflow(repo, %SetupWorkflowRow{} = row, %Workflow{} = workflow) do
    case repo.update(SetupWorkflowRow.update_changeset(row, workflow)) do
      {:ok, %SetupWorkflowRow{} = updated_row} ->
        {:ok, SetupWorkflowRow.to_domain(updated_row)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_insert_workflow_error(
         _repo,
         %Workflow{current_step: :pending_durable_admin_handoff},
         %Ecto.Changeset{} = changeset
       ) do
    if setup_workflow_id_conflict?(changeset) do
      {:error, :setup_tenant_already_created}
    else
      {:error, changeset}
    end
  end

  defp handle_insert_workflow_error(
         repo,
         %Workflow{} = workflow,
         %Ecto.Changeset{} = changeset
       ) do
    if setup_workflow_id_conflict?(changeset) do
      case repo.get(SetupWorkflowRow, workflow.setup_workflow_id) do
        %SetupWorkflowRow{} = row -> update_workflow(repo, row, workflow)
        nil -> {:error, changeset}
      end
    else
      {:error, changeset}
    end
  end

  defp setup_workflow_id_conflict?(%Ecto.Changeset{} = changeset) do
    Enum.any?(changeset.errors, fn
      {:setup_workflow_id, {_message, opts}} -> opts[:constraint] == :unique
      _other -> false
    end)
  end

  defp list_organizations(repo) do
    OrganizationRow
    |> repo.all()
    |> Enum.map(&OrganizationRow.to_domain/1)
  end

  defp handoff_workflow_step(%{mode: :granted}), do: :pending_completion
  defp handoff_workflow_step(%{mode: :invited}), do: :pending_durable_admin_handoff

  defp handoff_workflow_metadata(existing_metadata, %{
         mode: :granted,
         user: user,
         membership: membership
       })
       when is_map(existing_metadata) do
    Map.merge(existing_metadata, %{
      "durable_admin_handoff" => granted_handoff_metadata(user, membership)
    })
  end

  defp handoff_workflow_metadata(existing_metadata, %{mode: :invited, invitation: invitation})
       when is_map(existing_metadata) do
    Map.merge(existing_metadata, %{
      "durable_admin_handoff" => invited_handoff_metadata(invitation)
    })
  end

  defp granted_handoff_metadata(%User{} = user, %OrganizationMembership{} = membership) do
    %{
      "status" => "granted",
      "mode" => "direct_grant",
      "email" => user.email,
      "user_id" => user.user_id,
      "organization_membership_id" => membership.organization_membership_id,
      "organization_role" => Atom.to_string(membership.role),
      "platform_admin" => :platform_admin in user.capabilities,
      "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp invited_handoff_metadata(%OrganizationInvitation{} = invitation) do
    %{
      "status" => "invited",
      "mode" => "invitation",
      "email" => invitation.email,
      "display_name" => invitation.display_name,
      "invitation_id" => invitation.organization_invitation_id,
      "organization_role" => Atom.to_string(invitation.membership_role),
      "platform_admin" => invitation.grant_platform_admin,
      "invited_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "expires_at" => DateTime.to_iso8601(invitation.expires_at)
    }
  end

  defp validate_workflow(
         %Workflow{current_step: :pending_tenant_creation, active_organization_id: nil} = workflow
       ),
       do: {:ok, workflow}

  defp validate_workflow(
         %Workflow{current_step: current_step, active_organization_id: active_organization_id} =
           workflow
       )
       when current_step in [:pending_durable_admin_handoff, :pending_completion, :completed] and
              is_binary(active_organization_id),
       do: {:ok, workflow}

  defp validate_workflow(%Workflow{}), do: {:error, :invalid_setup_state}
end
