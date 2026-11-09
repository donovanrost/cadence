defmodule Cadence.ContactPlanning.ConfirmationWindow do
  @moduledoc """
  How long a placed booking may wait for its provider's answer (DECISIONS #52). Counted from
  placement (`started_at`, set when the item is claimed just before the provider call), so
  later provider errors don't restart it. Past it, an `uncertain` item reads `unconfirmed` and
  can be resolved by an operator (#53).

  Options: `:now`, `:confirmation_window_ms` (default `:provider_confirmation_window_ms`, 10 min).
  """

  alias Cadence.ContactPlanning.ContactPlanExecutionItem

  @spec overdue?(ContactPlanExecutionItem.t(), keyword()) :: boolean()
  def overdue?(
        %ContactPlanExecutionItem{lifecycle_state: :uncertain, started_at: %DateTime{} = at},
        opts
      ),
      do: DateTime.compare(at, cutoff(opts)) == :lt

  def overdue?(_item, _opts), do: false

  defp cutoff(opts) do
    DateTime.add(
      Keyword.get_lazy(opts, :now, &DateTime.utc_now/0),
      -Keyword.get_lazy(opts, :confirmation_window_ms, &window_ms/0),
      :millisecond
    )
  end

  defp window_ms,
    do: Application.get_env(:cadence, :provider_confirmation_window_ms, :timer.minutes(10))
end
