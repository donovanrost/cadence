defmodule Cadence.ActivationFixtures do
  @moduledoc false

  alias Cadence.Accounts.User
  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Auth.Scope
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.MissionRuntimeReconciler
  alias Cadence.Control.Missions, as: ControlMissions
  alias Cadence.Management.Activations, as: ManagementActivations
  alias Cadence.Runtime.MissionRuntimeSpec

  def activate_binding_set(organization_id, mission_id, binding_set_id, version, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(binding_set_id) and
             is_integer(version) and version > 0 and is_list(opts) do
    with {:ok, %BindingSet{} = binding_set} <-
           Cadence.Governance.fetch_binding_set(
             organization_id,
             mission_id,
             binding_set_id,
             version
           ) do
      activate(binding_set, opts)
    end
  end

  def activate_binding_set(mission_id, binding_set_id, version, opts \\ [])
      when is_binary(mission_id) and is_binary(binding_set_id) and is_integer(version) and
             version > 0 and is_list(opts) do
    with {:ok, %BindingSet{} = binding_set} <-
           Cadence.Governance.fetch_binding_set(mission_id, binding_set_id, version) do
      activate(binding_set, opts)
    end
  end

  defp activate(%BindingSet{organization_id: nil} = binding_set, opts) do
    content_sha256 = MissionRuntimeSpec.content_sha256(binding_set)

    with {:ok, activation} <-
           Cadence.Activations.record_binding_set_activation(
             binding_set.mission_id,
             binding_set.binding_set_id,
             binding_set.version,
             Keyword.put(opts, :binding_set_content_sha256, content_sha256)
           ),
         {:ok, _mission_control} <- ControlMissions.ensure_started(binding_set.mission_id),
         {:ok, _generation_applied} <-
           MissionRuntimeReconciler.apply_generation(
             binding_set.mission_id,
             activation,
             binding_set
           ) do
      {:ok, activation}
    end
  end

  defp activate(%BindingSet{} = binding_set, opts) do
    requester = user_scope(binding_set.organization_id, "activation-fixture-requester")
    approver = user_scope(binding_set.organization_id, "activation-fixture-approver")
    workflow_time = Keyword.get(opts, :activated_at, DateTime.utc_now())

    with {:ok, request} <-
           ManagementActivations.request(
             requester,
             binding_set.mission_id,
             binding_set.binding_set_id,
             binding_set.version,
             change_class: :mission_data_plane,
             metadata: Keyword.get(opts, :metadata, %{}),
             now: workflow_time
           ),
         {:ok, _request, _decision, approved} <-
           ManagementActivations.approve(
             approver,
             request.activation_request_id,
             "approved by test fixture",
             now: workflow_time
           ),
         {:ok, _execution} <-
           ControlActivations.execute(
             approved,
             opts
             |> Keyword.put(:now, workflow_time)
             |> Keyword.put_new(:activated_at, workflow_time)
           ) do
      ControlActivations.fetch_active_basis(
        binding_set.organization_id,
        binding_set.mission_id
      )
    end
  end

  defp user_scope(organization_id, prefix) do
    user_id = "#{prefix}-#{System.unique_integer([:positive])}"

    user =
      User.new(%{
        user_id: user_id,
        email: user_id <> "@example.test",
        display_name: user_id,
        capabilities: [:platform_admin]
      })

    Scope.new(%{user: user, organization_id: organization_id})
  end
end
