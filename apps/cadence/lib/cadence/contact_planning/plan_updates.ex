defmodule Cadence.ContactPlanning.PlanUpdates do
  @moduledoc """
  Console read invalidation for contact plans and fleet planning runs (S10 `contact_plans`):
  publishes `:contact_plans_changed` for a mission when a plan or run changes state or version,
  when a requirement or template change can supersede a plan, and when a placed booking
  crosses the #52 confirmation window (a plan can turn `unconfirmed` by time alone).

  Called after a successful write. Inside a transaction the commit hasn't happened yet, so the
  publish is delayed briefly (a reader refetching right away would see the old state); outside
  one it's immediate. The time-based publish is best effort: it doesn't survive a restart, and
  the console still refetches on reconnect.
  """

  alias Cadence.ContactPlanning.ConfirmationWindow
  alias Cadence.Platform.ScopedReadUpdates
  alias Cadence.Repo

  @event :contact_plans_changed
  @after_commit_ms 1_000

  @doc "Publishes when `result` is `{:ok, ...}`; returns `result` unchanged."
  @spec published(term(), binary(), binary()) :: term()
  def published(result, organization_id, mission_id)
      when is_tuple(result) and elem(result, 0) == :ok do
    changed(organization_id, mission_id)
    result
  end

  def published(result, _organization_id, _mission_id), do: result

  @doc "Publishes now, or shortly after the surrounding transaction."
  @spec changed(binary(), binary()) :: :ok
  def changed(organization_id, mission_id) do
    if Repo.in_transaction?(),
      do: changed_after(organization_id, mission_id, @after_commit_ms),
      else: ScopedReadUpdates.publish(@event, organization_id, mission_id)

    :ok
  end

  @doc "Publishes once just after a booking placed at `started_at` passes the #52 window."
  @spec when_unconfirmed(binary(), binary(), DateTime.t()) :: :ok
  def when_unconfirmed(organization_id, mission_id, %DateTime{} = started_at) do
    due =
      DateTime.add(started_at, ConfirmationWindow.window_ms() + @after_commit_ms, :millisecond)

    changed_after(
      organization_id,
      mission_id,
      max(DateTime.diff(due, DateTime.utc_now(), :millisecond), 0)
    )
  end

  @doc "Publishes once after `ms` (best effort)."
  @spec changed_after(binary(), binary(), non_neg_integer()) :: :ok
  def changed_after(organization_id, mission_id, ms) do
    {:ok, _ref} =
      :timer.apply_after(ms, ScopedReadUpdates, :publish, [@event, organization_id, mission_id])

    :ok
  end
end
