defmodule Cadence.Control.Configuration do
  @moduledoc """
  Public facade for mission change sets and the configuration revision ledger
  (`docs/apogee/api/domain.md`).

  Every call takes the caller's scope and an explicit `mission_id`, and authorizes against the
  mission. Mutations publish `:configuration_changed` read invalidations after commit. An apply
  also broadcasts its step list on `"change-sets:" <> change_set_id`, and the runtime outcome as
  `{:config_runtime, map}` on `"config:" <> org <> ":" <> mission`.
  """

  require Logger

  alias Cadence.Activations
  alias Cadence.Applications.TelemetryDecom
  alias Cadence.Auth.Scope
  alias Cadence.Catalog.FleetSnapshot
  alias Cadence.Commanding.Groups

  alias Cadence.Configuration.{
    Access,
    Editing,
    Kinds,
    Ledger,
    Preview,
    Staging,
    Status,
    Submission
  }

  alias Cadence.Configuration.ChangeSetStore
  alias Cadence.Contacts.Scheduler
  alias Cadence.Control.MissionRuntimeReconciler
  alias Cadence.Control.Missions, as: ControlMissions
  alias Cadence.Control.ScidSharing
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

  @doc """
  Whether submitting the set is a Request review (see `Submission.needs_approval?/3`). It doesn't
  authorize: only for wording a submit the caller already authorized, never as a read (api-ops).
  """
  @spec needs_approval?(Scope.t(), String.t(), String.t()) :: boolean()
  def needs_approval?(%Scope{} = scope, mission_id, change_set_id),
    do: Submission.needs_approval?(scope.organization_id, mission_id, change_set_id)

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

      mission.organization_id
      |> Preview.run(mission.mission_id, head.revision_number, prepared)
      |> ScidSharing.for_viewer(scope, mission)
    end
  end

  def preview(%Scope{} = scope, mission_id, change_set_id) when is_binary(change_set_id) do
    with {:ok, mission} <- Access.authorize(scope, mission_id, :read),
         {:ok, set} <- ChangeSetStore.fetch(mission.mission_id, change_set_id) do
      ops = ChangeSetStore.staged_ops(set.change_set_id)

      mission.organization_id
      |> Preview.run(mission.mission_id, set.base_revision_number, ops)
      |> ScidSharing.for_viewer(scope, mission)
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
      |> ScidSharing.for_viewer(scope, mission)
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
      |> ScidSharing.for_viewer(scope, mission)
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

  @doc """
  The revisions whose entries touch one entity, newest first (fe-setup, Profile History): each
  revision's summary (as `list_revisions/3`) plus `entries`, that entity's entries in it (as
  `get_revision/3`'s). At most `opts[:limit]` (default 25) revisions.
  """
  @spec entity_revisions(Scope.t(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def entity_revisions(%Scope{} = scope, mission_id, kind, entity_id, opts \\ []) do
    with {:ok, mission} <- Access.authorize(scope, mission_id, :read) do
      by_revision =
        mission.mission_id
        |> Status.entity_history(kind, entity_id)
        |> Enum.group_by(& &1.revision)

      numbers =
        by_revision |> Map.keys() |> Enum.sort(:desc) |> Enum.take(Keyword.get(opts, :limit, 25))

      recent =
        mission.organization_id
        |> Status.list_revisions(mission.mission_id, limit: 200)
        |> Map.new(&{&1.revision, &1})

      revisions =
        for number <- numbers,
            %{} = summary <- [summary(mission, recent, number)],
            do: Map.put(summary, :entries, Enum.reverse(by_revision[number]))

      {:ok, revisions}
    end
  end

  # Most entity histories fall within the 200 newest revisions; an older one is read alone.
  defp summary(mission, recent, number) do
    Map.get_lazy(recent, number, fn ->
      case Status.get_revision(mission.organization_id, mission.mission_id, number) do
        {:ok, revision} -> Map.delete(revision, :entries)
        _missing -> nil
      end
    end)
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
    result = post_commit(mission, change_set_id, result)
    progress(change_set_id, "notify_runtime", :done)
    progress(change_set_id, "verify", if(result.runtime == :degraded, do: :failed, else: :done))
    broadcast_runtime(mission, result)
    publish_entity_updates(mission, result.kinds)
    changed({:ok, Map.drop(result, [:impacts, :kinds, :activation_payload, :committed])}, mission)
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
  defp reopened?({:in_use, _}), do: true
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

  # The revision is committed: nothing after this may fail the response (qa #19). A crash or
  # exit while notifying or converging (a pool timeout under load) leaves the revision applied
  # and reports the runtime degraded; the mission reconciler keeps retrying.
  defp post_commit(mission, change_set_id, result) do
    notify_runtime(mission, result.impacts)
    after_commit_kinds(mission, Map.get(result, :committed, []))
    announce_canceled(mission, result)
    converge(mission, result)
  rescue
    error -> degraded_after_commit(mission, change_set_id, result, Exception.message(error))
  catch
    :exit, reason -> degraded_after_commit(mission, change_set_id, result, inspect(reason))
  end

  defp degraded_after_commit(mission, change_set_id, result, reason) do
    Logger.warning(
      "change set #{change_set_id} applied (revision #{inspect(result[:revision])}) but " <>
        "post-commit runtime work failed for mission #{mission.mission_id}: #{reason}"
    )

    %{result | runtime: :degraded}
  end

  # #65: commands a catalog change canceled with the apply (committed with it).
  defp announce_canceled(mission, %{activation_payload: %{canceled_request_ids: [_ | _] = ids}}) do
    ScopedReadUpdates.publish(:commanding_changed, mission.organization_id, mission.mission_id)
    Groups.Timeline.settle_requests(mission.organization_id, mission.mission_id, ids)
  end

  defp announce_canceled(_mission, _result), do: :ok

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

  # A kind that announces outside the database does it here, once the revision has committed.
  defp after_commit_kinds(mission, entries) do
    entries
    |> Enum.group_by(& &1.kind)
    |> Enum.each(fn {kind, kind_entries} ->
      with {:ok, module} <- Kinds.fetch(kind),
           true <- function_exported?(module, :after_commit, 3) do
        module.after_commit(mission.organization_id, mission.mission_id, kind_entries)
      end
    end)
  end

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
