defmodule Cadence.Control.MissionRuntimeStatus do
  @moduledoc """
  Whether a mission's runtime has applied its active generation (2026-11-12 outage: it hadn't,
  for hours, and nothing said so). The mission's `MissionRuntimeReconciler` records a status
  here after every reconcile; reads are a `:persistent_term` lookup, cheap enough for `/counts`
  on every ops screen, and never call a process.

  `status/1`:

  - `nil`: nothing recorded on this node (no active generation, or the reconciler hasn't run).
  - `%{state: "not_applied", ...}` once applying the desired generation has failed for
    `#{60}` s or more (a normal apply never shows). `since` is that first failure.
  - `%{state: "applied", ...}` otherwise, with `applied_at`, when the runtime last applied.

  Recorded only on change, so a 30 s poll doesn't rewrite the term. When the visible state
  flips, the reconciler publishes `:attention_changed` (the `mission_runtime` attention item and
  `/counts` both follow it).
  """

  alias Cadence.Persistence.OrganizationScope
  alias Cadence.Platform.ScopedReadUpdates

  @debounce_s 60
  @reasons %{
    mission_runtime_spec_mismatch: "spec_mismatch",
    reconcile_crashed: "reconcile_crashed",
    mission_runtime_not_running: "runtime_not_running"
  }

  @doc "The stable `reason` strings (anything else reads `apply_failed`)."
  def reasons, do: Map.values(@reasons) ++ ["apply_failed"]

  @spec status(binary(), DateTime.t()) :: map() | nil
  def status(mission_id, now \\ DateTime.utc_now()) when is_binary(mission_id) do
    case :persistent_term.get(key(mission_id), nil) do
      nil -> nil
      record -> view(record, now)
    end
  rescue
    _exception -> nil
  end

  @doc """
  Records the reconciler's state (only when it changed) and publishes `:attention_changed` when
  the visible state flips between applied and not_applied. Never raises.
  """
  @spec record(map(), map() | nil) :: :ok
  def record(%{mission_id: mission_id} = reconciler_state, activation) do
    previous = :persistent_term.get(key(mission_id), nil)
    record = record_from(reconciler_state, activation, previous)

    if record != previous do
      :persistent_term.put(key(mission_id), record)
      maybe_announce(mission_id, previous, record)
    end

    :ok
  rescue
    _exception -> :ok
  end

  defp record_from(state, activation, previous) do
    %{
      desired_generation: state.desired_generation,
      applied_generation: state.applied_generation,
      reason: reason(state.last_error),
      failure_message: failure_message(state.last_error),
      failing_since: state.failing_since,
      applied_at: state.applied_at,
      activated_at: activation_field(activation, previous, :activated_at),
      change_set_id: activation_field(activation, previous, :change_set_id)
    }
  end

  defp activation_field(nil, nil, _field), do: nil
  defp activation_field(nil, previous, field), do: Map.get(previous, field)
  defp activation_field(activation, _previous, :activated_at), do: activation.activated_at

  defp activation_field(activation, _previous, :change_set_id),
    do: get_in(activation.metadata || %{}, ["change_set", "id"])

  # The visible state can flip at a poll after the debounce, so announce on what readers see.
  defp maybe_announce(mission_id, previous, record) do
    now = DateTime.utc_now()

    if visible(previous, now) != visible(record, now) do
      case OrganizationScope.organization_id_for_mission(mission_id) do
        nil -> :ok
        org -> ScopedReadUpdates.publish(:attention_changed, org, mission_id)
      end
    end
  end

  defp visible(nil, _now), do: nil

  defp visible(record, now) do
    case view(record, now) do
      %{state: state} -> state
      nil -> nil
    end
  end

  defp view(%{failing_since: %DateTime{} = since} = record, now) do
    if DateTime.diff(now, since) >= @debounce_s,
      do: %{state: "not_applied", since: since} |> Map.merge(common(record)),
      else: applied_view(record)
  end

  defp view(record, _now), do: applied_view(record)

  defp applied_view(%{applied_generation: generation} = record) when is_integer(generation),
    do: %{state: "applied", since: nil} |> Map.merge(common(record))

  # Nothing applied and nothing failing yet (a node just started): nothing to say.
  defp applied_view(_record), do: nil

  defp common(record) do
    %{
      reason: Map.get(record, :reason),
      failure_message: Map.get(record, :failure_message),
      desired_generation: Map.get(record, :desired_generation),
      applied_generation: Map.get(record, :applied_generation),
      applied_at: Map.get(record, :applied_at),
      activated_at: Map.get(record, :activated_at),
      change_set_id: Map.get(record, :change_set_id)
    }
  end

  defp reason(nil), do: nil
  defp reason({kind, _detail}) when is_atom(kind), do: Map.get(@reasons, kind, "apply_failed")
  defp reason(kind) when is_atom(kind), do: Map.get(@reasons, kind, "apply_failed")
  defp reason(_other), do: "apply_failed"

  defp failure_message(nil), do: nil

  defp failure_message({:reconcile_crashed, message}) when is_binary(message),
    do: truncate(message)

  defp failure_message(error), do: error |> inspect(limit: 10) |> truncate()

  defp truncate(text) when byte_size(text) <= 300, do: text
  defp truncate(text), do: binary_part(text, 0, 300) <> "…"

  defp key(mission_id), do: {__MODULE__, mission_id}
end
