defmodule Cadence.Control.Configuration do
  @moduledoc """
  Public facade for mission change sets and the configuration revision ledger
  (`docs/apogee/api/domain.md`).

  Every call takes the caller's scope and an explicit `mission_id`, and authorizes against the
  mission. Mutations publish `:configuration_changed` read invalidations after commit. An apply
  also broadcasts its step list on `"change-sets:" <> change_set_id`, and the runtime outcome as
  `{:config_runtime, map}` on `"config:" <> org <> ":" <> mission`.
  """

  alias Cadence.Activations
  alias Cadence.Applications.TelemetryDecom
  alias Cadence.Auth.Scope
  alias Cadence.Catalog.FleetSnapshot
  alias Cadence.Configuration.{Access, Editing, Ledger, Preview, Staging, Status, Submission}
  alias Cadence.Configuration.ChangeSetStore
  alias Cadence.Contacts.Scheduler
  alias Cadence.Control.MissionRuntimeReconciler
  alias Cadence.Control.Missions, as: ControlMissions
  alias Cadence.Platform.ScopedReadUpdates

  @pubsub Cadence.PubSub
  @steps [
    {"validate", "Validate"},
    {"write_config", "Write configuration"},
    {"notify_runtime", "Notify runtime"},
    {"verify", "Verify"}
  ]

  @spec permissions(Scope.t(), String.t()) :: {:ok, [String.t()]} | {:error, term()}
  defdelegate permissions(scope, mission_id), to: Access

  @spec current(Scope.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def current(%Scope{} = scope, mission_id) do
    with {:ok, mission} <- Access.authorize(scope, mission_id, :read) do
      {:ok, Status.current(mission.organization_id, mission.mission_id)}
    end
  end

  @spec change_set(Scope.t(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def change_set(%Scope{} = scope, mission_id, change_set_id) do
    with {:ok, mission} <- Access.authorize(scope, mission_id, :read),
         do: Status.change_set(mission.mission_id, change_set_id)
  end

  @spec stage(Scope.t(), String.t(), map(), [map()]) :: {:ok, map()} | {:error, term()}
  def stage(%Scope{} = scope, mission_id, attrs, ops) do
    with {:ok, mission} <- Access.authorize(scope, mission_id, :stage) do
      head = Ledger.ensure_head(mission.organization_id, mission.mission_id)

      mission.organization_id
      |> Staging.stage(mission.mission_id, head.revision_number, Access.actor(scope), attrs, ops)
      |> changed(mission)
    end
  end

  @spec withdraw(Scope.t(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def withdraw(%Scope{} = scope, mission_id, change_id) do
    with {:ok, mission} <- Access.authorize(scope, mission_id, :stage) do
      mission.mission_id
      |> Editing.withdraw(change_id, Access.actor(scope), discard_any?(scope, mission))
      |> changed(mission)
    end
  end

  @spec discard(Scope.t(), String.t(), String.t(), integer()) :: {:ok, map()} | {:error, term()}
  def discard(%Scope{} = scope, mission_id, change_set_id, expected_version) do
    with {:ok, mission} <- Access.authorize(scope, mission_id, :stage) do
      mission.mission_id
      |> Editing.discard(
        change_set_id,
        expected_version,
        Access.actor(scope),
        discard_any?(scope, mission)
      )
      |> changed(mission)
    end
  end

  @spec rebase(Scope.t(), String.t(), String.t(), :keep_mine | :take_live) ::
          {:ok, map()} | {:error, term()}
  def rebase(%Scope{} = scope, mission_id, op_id, resolution) do
    with {:ok, mission} <- Access.authorize(scope, mission_id, :stage) do
      mission.organization_id
      |> Editing.rebase(
        mission.mission_id,
        op_id,
        resolution,
        Access.actor(scope),
        discard_any?(scope, mission)
      )
      |> changed(mission)
    end
  end

  @doc """
  Dry run of the staged set (`change_set_id`) or of unstaged ops (`{:ops, ops}`, e.g. the
  Profile P4 aside). Nothing is written.
  """
  @spec preview(Scope.t(), String.t(), String.t() | {:ops, [map()]}) ::
          {:ok, Preview.t()} | {:error, term()}
  def preview(%Scope{} = scope, mission_id, {:ops, ops}) do
    with {:ok, mission} <- Access.authorize(scope, mission_id, :read),
         {:ok, prepared} <- Staging.prepare_ops(mission.organization_id, mission.mission_id, ops) do
      head = Ledger.ensure_head(mission.organization_id, mission.mission_id)
      Preview.run(mission.organization_id, mission.mission_id, head.revision_number, prepared)
    end
  end

  def preview(%Scope{} = scope, mission_id, change_set_id) when is_binary(change_set_id) do
    with {:ok, mission} <- Access.authorize(scope, mission_id, :read),
         {:ok, set} <- ChangeSetStore.fetch(mission.mission_id, change_set_id) do
      ops = ChangeSetStore.staged_ops(set.change_set_id)
      Preview.run(mission.organization_id, mission.mission_id, set.base_revision_number, ops)
    end
  end

  @doc "Params: `reason` (required), `expected_version`, `acknowledged_holds`."
  @spec submit(Scope.t(), String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def submit(%Scope{} = scope, mission_id, change_set_id, params) do
    with {:ok, mission} <- Access.authorize(scope, mission_id, :apply) do
      progress(change_set_id, "validate", :running)

      mission.organization_id
      |> Submission.submit(mission.mission_id, change_set_id, Access.actor(scope), params)
      |> after_apply(mission, change_set_id)
    end
  end

  @doc "Params: `comment` (required), `expected_version`."
  @spec review(Scope.t(), String.t(), String.t(), :approve | :send_back, map()) ::
          {:ok, map()} | {:error, term()}
  def review(%Scope{} = scope, mission_id, change_set_id, decision, params) do
    with {:ok, mission} <- Access.authorize(scope, mission_id, :review) do
      if decision == :approve, do: progress(change_set_id, "validate", :running)

      mission.organization_id
      |> Submission.review(
        mission.mission_id,
        change_set_id,
        Access.actor(scope),
        decision,
        params
      )
      |> after_apply(mission, change_set_id)
    end
  end

  @spec list_revisions(Scope.t(), String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_revisions(%Scope{} = scope, mission_id, opts \\ []) do
    with {:ok, mission} <- Access.authorize(scope, mission_id, :read),
         do: {:ok, Status.list_revisions(mission.organization_id, mission.mission_id, opts)}
  end

  @spec get_revision(Scope.t(), String.t(), pos_integer()) :: {:ok, map()} | {:error, term()}
  def get_revision(%Scope{} = scope, mission_id, number) do
    with {:ok, mission} <- Access.authorize(scope, mission_id, :read),
         do: Status.get_revision(mission.organization_id, mission.mission_id, number)
  end

  @spec compare(Scope.t(), String.t(), pos_integer(), pos_integer()) ::
          {:ok, [map()]} | {:error, term()}
  def compare(%Scope{} = scope, mission_id, from, to) do
    with {:ok, mission} <- Access.authorize(scope, mission_id, :read),
         do: Status.compare(mission.mission_id, from, to)
  end

  @spec entity_history(Scope.t(), String.t(), String.t(), String.t()) ::
          {:ok, [map()]} | {:error, term()}
  def entity_history(%Scope{} = scope, mission_id, kind, entity_id) do
    with {:ok, mission} <- Access.authorize(scope, mission_id, :read),
         do: {:ok, Status.entity_history(mission.mission_id, kind, entity_id)}
  end

  @doc "Topic carrying `{:change_set_progress, change_set_id, step}` for one change set."
  @spec progress_topic(String.t()) :: String.t()
  def progress_topic(change_set_id), do: "change-sets:" <> change_set_id

  @doc "Topic carrying `{:config_runtime, map}` for a mission."
  @spec runtime_topic(String.t(), String.t()) :: String.t()
  def runtime_topic(organization_id, mission_id), do: "config:#{organization_id}:#{mission_id}"

  defp discard_any?(scope, mission), do: Access.allowed?(scope, mission, :discard_any)

  defp changed({:ok, _} = result, mission) do
    ScopedReadUpdates.publish(:configuration_changed, mission.organization_id, mission.mission_id)
    result
  end

  defp changed(error, _mission), do: error

  defp after_apply({:ok, %{state: :applied} = result}, mission, change_set_id) do
    progress(change_set_id, "validate", :done)
    progress(change_set_id, "write_config", :done)
    progress(change_set_id, "notify_runtime", :running)
    notify_runtime(mission, result.impacts)
    result = converge(mission, result)
    progress(change_set_id, "notify_runtime", :done)
    progress(change_set_id, "verify", if(result.runtime == :degraded, do: :failed, else: :done))
    broadcast_runtime(mission, result)
    publish_entity_updates(mission, result.kinds)
    changed({:ok, Map.drop(result, [:impacts, :kinds, :activation_payload])}, mission)
  end

  defp after_apply({:ok, _result} = ok, mission, change_set_id) do
    progress(change_set_id, "validate", :done)
    changed(ok, mission)
  end

  defp after_apply({:error, reason} = error, mission, change_set_id) do
    progress(change_set_id, "validate", :failed)
    if reopened?(reason), do: changed({:ok, :reopened}, mission)
    error
  end

  defp reopened?({:checks_failed, _}), do: true
  defp reopened?(:activation_policy_changed), do: true
  defp reopened?(_reason), do: false

  # Stores skip their own read invalidations inside the apply transaction; re-announce them
  # after commit so existing pages that listen for them refresh.
  defp publish_entity_updates(mission, kinds) do
    if Enum.any?(kinds, &(&1 in ["spacecraft", "spacecraft_profile"])) do
      ScopedReadUpdates.publish(
        :spacecraft_configuration_changed,
        mission.organization_id,
        mission.mission_id
      )
    end
  end

  # Admission and the generation were committed with the revision; here the runtime converges
  # on it. A failure leaves the revision applied and the runtime degraded; the mission
  # reconciler keeps retrying on its safety loop.
  defp converge(_mission, %{activation_payload: nil} = result), do: result

  defp converge(
         mission,
         %{activation_payload: %{activation: activation, binding_set: binding_set}} = result
       ) do
    Activations.publish_activation(activation)

    runtime =
      with {:ok, _} <- ControlMissions.ensure_started(mission.mission_id),
           {:ok, _} <-
             MissionRuntimeReconciler.apply_generation(
               mission.mission_id,
               activation,
               binding_set
             ),
           {:ok, entries} <- FleetSnapshot.entries(activation.metadata),
           :ok <-
             TelemetryDecom.activation_applied(binding_set, %{
               "spacecraft_configuration_version" => 1,
               "spacecraft_configurations" => entries
             }) do
        :applied
      else
        _failed -> :degraded
      end

    %{result | runtime: runtime}
  end

  defp converge(_mission, result), do: result

  defp notify_runtime(mission, impacts) do
    if :contacts in impacts, do: Scheduler.notify_contact_changed(mission.mission_id)
    :ok
  end

  defp progress(change_set_id, key, state) do
    {^key, label} = List.keyfind(@steps, key, 0)
    step = %{key: key, label: label, state: state, at: DateTime.utc_now()}

    Phoenix.PubSub.broadcast(
      @pubsub,
      progress_topic(change_set_id),
      {:change_set_progress, change_set_id, step}
    )
  end

  defp broadcast_runtime(mission, result) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      runtime_topic(mission.organization_id, mission.mission_id),
      {:config_runtime,
       Map.take(result, [:revision, :activation_id, :generation, :runtime, :degraded_partitions])}
    )
  end
end
