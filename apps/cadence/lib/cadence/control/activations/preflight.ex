defmodule Cadence.Control.Activations.Preflight do
  @moduledoc """
  The deterministic checks an activation's apply runs before it changes anything, and an
  approval runs before it records (director 11-17): one list (`checks/0`), so the two can't drift.
  """
  alias Cadence.Activations.SpacecraftConfiguration, as: ConfigurationActivation
  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Control.MissionModelPromotion
  alias Cadence.Governance
  alias Cadence.Governance.ActivationPolicy

  @doc """
  Whether an approval of `request` could apply: the deterministic checks an apply runs before it
  changes anything (the approved content, the mission-model gate, the policy, a spacecraft review's
  freshness), run BEFORE a decision is recorded (director 11-17). An approval of a request that
  can't apply would record 'approved' for something that never ran. Every approve path calls this
  before deciding; execute runs the SAME list (`run_checks/3`), so the two can't drift.
  Only transient failures (the runtime apply, a lost connection) are left for after the decision,
  where Retry apply handles them. `opts[:checks]` replaces the list (tests).

  Approval runs it inside the decision's transaction, under the locks in
  `Cadence.Governance.ActivationLocks`' order (`Cadence.Control.Activations.Approval`), so nothing
  it read can change before the record. For a reviewed-spacecraft request the admission locks each
  reviewed craft too, so a large review's approval waits for, and holds up, a concurrent change-set
  apply on its mission.
  """
  @spec run(map(), keyword()) :: :ok | {:error, term()}
  def run(request, opts \\ []) do
    with {:ok, %BindingSet{} = binding_set} <-
           Governance.fetch_binding_set(
             request.organization_id,
             request.mission_id,
             request.binding_set_id,
             request.binding_set_version
           ) do
      run_checks(request, binding_set, opts)
    end
  end

  @doc "The deterministic checks, in order: what both an apply and an approval's preflight run."
  def checks,
    do: [
      &exact_approved_content/2,
      &model_gate/2,
      &__MODULE__.policy_current/2,
      &__MODULE__.configuration_current/2
    ]

  # The policy and the configuration admission: an apply runs them inside the activation's own
  # transaction, under its locks and only for a not-yet-recorded activation (Activations), so
  # execute's pre-check skips them; the approval preflight runs the whole list.
  @admitted_in_transaction [&__MODULE__.policy_current/2, &__MODULE__.configuration_current/2]

  @doc """
  Runs the checks on `activation` against `binding_set`, stopping at the first refusal.
  `executing?: true` (execute) skips the two its own transaction runs under its locks.
  """
  @spec run_checks(map(), BindingSet.t(), keyword()) :: :ok | {:error, term()}
  def run_checks(activation, binding_set, opts) do
    opts
    |> Keyword.get(:checks, checks())
    |> Enum.reject(&(Keyword.get(opts, :executing?, false) and &1 in @admitted_in_transaction))
    |> Enum.reduce_while(:ok, fn check, :ok ->
      case check.(activation, binding_set) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp model_gate(activation, binding_set),
    do:
      MissionModelPromotion.validate_activation_metadata(
        activation.organization_id,
        activation.mission_id,
        binding_set,
        activation.metadata
      )

  @doc false
  def policy_current(activation, _binding_set),
    do:
      ActivationPolicy.validate(
        activation.organization_id,
        activation.mission_id,
        activation.policy_document
      )

  # A spacecraft review or change-set fleet still matches what's active (read-only, under the
  # configuration lock; the activation's own transaction runs it again).
  @doc false
  def configuration_current(activation, _binding_set) do
    activation
    |> Map.take([
      :organization_id,
      :mission_id,
      :binding_set_id,
      :binding_set_version,
      :binding_set_content_sha256,
      :metadata,
      :activation_request_id
    ])
    |> ConfigurationActivation.admit()
    |> case do
      {:ok, _admitted} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp exact_approved_content(approved_activation, binding_set) do
    if BindingSet.content_sha256(binding_set) == approved_activation.binding_set_content_sha256 do
      :ok
    else
      {:error, :approved_activation_content_mismatch}
    end
  end
end
