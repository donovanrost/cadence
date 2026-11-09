defmodule Cadence.Alarms.Ground do
  @moduledoc """
  Ground-limit hooks for alarm episodes, called from `Cadence.Limits` inside its evaluation and
  projection-rebuild transactions, plus the after-commit notification. The episode's
  organization is filled from its mission by the database.
  """

  alias Cadence.Alarms.{Episodes, Notify, Sources}

  @type outcome :: {String.t(), non_neg_integer()}

  @doc "Observes evaluation events in order. Returns `{:ok, {mission_id, changed_count}}`."
  @spec observe(module(), String.t(), list()) :: {:ok, outcome()}
  def observe(repo, mission_id, events) do
    now = DateTime.utc_now()
    {:ok, changed} = Episodes.observe_many(repo, Enum.map(events, &Sources.ground(&1, now)))
    {:ok, {mission_id, changed}}
  end

  @doc "Reconciles episodes with a rebuilt latest-state projection (see `Episodes.reconcile_ground/4`)."
  @spec reconcile(module(), String.t(), String.t() | nil, list()) :: {:ok, outcome()}
  def reconcile(repo, mission_id, spacecraft_id, events) do
    now = DateTime.utc_now()
    observations = Enum.map(events, &Sources.ground(&1, now))
    {:ok, changed} = Episodes.reconcile_ground(repo, mission_id, spacecraft_id, observations)
    {:ok, {mission_id, changed}}
  end

  @spec notify(outcome()) :: :ok
  def notify({mission_id, changed}) when changed > 0, do: Notify.missions_changed([mission_id])
  def notify(_outcome), do: :ok
end
