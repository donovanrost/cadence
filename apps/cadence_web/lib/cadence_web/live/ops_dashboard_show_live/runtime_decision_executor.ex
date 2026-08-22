defmodule CadenceWeb.OpsDashboardShowLive.RuntimeDecisionExecutor do
  @moduledoc """
  Interprets pure dashboard runtime decisions at the LiveView boundary.

  The coordinator decides what should happen. This module maps those decisions
  to owner-provided start and cancel effects so ordering and supersession can be
  tested without timing a real task.
  """

  @type decision :: map()
  @type effect :: (term(), term() -> term()) | (term(), term(), term(), keyword() -> term())

  @spec apply(term(), [decision()], keyword(), keyword(effect())) :: term()
  def apply(socket, decisions, opts, effects)
      when is_list(decisions) and is_list(opts) and is_list(effects) do
    cancel_resolve = Keyword.fetch!(effects, :cancel_resolve)
    start_resolve = Keyword.fetch!(effects, :start_resolve)

    Enum.reduce(decisions, socket, fn
      %{action: :cancel_obsolete, superseded_resolve_id: resolve_id}, socket ->
        cancel_resolve.(socket, resolve_id)

      %{action: :start_resolve, resolve_mode: resolve_mode, resolve_id: resolve_id}, socket ->
        start_resolve.(socket, resolve_mode, resolve_id, opts)

      _decision, socket ->
        socket
    end)
  end
end
