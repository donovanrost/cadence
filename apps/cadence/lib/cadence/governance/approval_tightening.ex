defmodule Cadence.Governance.ApprovalTightening do
  @moduledoc """
  What a tightening of a mission's approval setting does beyond the setting (#499; the director's
  answer on #283): standing authority approved by one person is suspended until a second,
  separated approval. Governance defines the hook; the implementation is registered in config
  (`:cadence, :approval_tightening`), so `ActivationPolicy` runs it on every save without
  depending on the contexts that hold that authority.

  Both callbacks run inside the setting's save, under its exclusive section lock:
  `preview/4` before the write (refuse with the list unless the caller acknowledged it),
  `apply/6` after it, in the same transaction. `opts`: `:now` (default the current time).
  """

  alias Cadence.Auth.Scope

  @doc """
  `:ok` when the tightening of `mission_ids` suspends nothing, or the caller's `acknowledged`
  digest matches what it would suspend; else `{:error, {code, details}}` (nothing is written).
  """
  @callback preview(binary(), [binary()], binary() | nil, keyword()) :: :ok | {:error, term()}

  @doc "Suspends what the tightening of `mission_ids` suspends; `level` is mission or organization."
  @callback apply(Scope.t(), binary(), [binary()], binary(), binary(), keyword()) ::
              {:ok, [binary()]} | {:error, term()}

  @doc """
  The registered implementation, or nil. A tightening save with nil is refused
  (`:approval_tightening_unavailable`, fail closed); config registers `GrantSuspension`.
  """
  @spec implementation() :: module() | nil
  def implementation, do: Application.get_env(:cadence, :approval_tightening)
end
