defmodule Cadence.Control.Commanding.WithdrawnAtGo do
  @moduledoc """
  What a GO knew about withdrawn model approvals (E2, #546, the CTO's ruling): a group is armed
  by a GO (`GroupDecision`) or by its submit when no second GO is needed (`GroupSubmission`).
  Either way, a craft running a revision whose approval was withdrawn needs an acknowledged
  `model_approval_withdrawn` HOLD (#1012). This is the check and the record of it, run in the
  arming's own transaction:

  - `seen/4` reads the withdrawals now (`Control.WithdrawnPins`) over the group's craft and checks
    that the acknowledgement the GO carries is for exactly them (the HOLD's own `basis`). A
    withdrawal that came in since the preflight the person saw isn't covered: refused, so the
    record below never blesses a decision nobody acknowledged.
  - the answer, `%{spacecraft_id => "<revision_id>:withdrawn:<decided_at>"}`, goes in each armed
    member's own approval row (`metadata["withdrawn_seen"]`; append-only, written in the same
    transaction as the arming). The unattended release compares a craft's current withdrawal with
    its member's row (`Commanding.release_command_queue_entry/6`, `unattended: true`).
  """

  alias Cadence.Control.WithdrawnPins

  @key "model_approval_withdrawn"

  @doc """
  `{:ok, %{spacecraft_id => basis}}` for the craft among `spacecraft_ids` that run a withdrawn
  revision (empty when none), or `{:error, :withdrawal_not_acknowledged}` when `acks` (the
  acknowledgements the GO carries, `%{key, hold_basis, ...}`) don't cover exactly those.
  """
  @spec seen(binary(), binary(), [binary()], [map()], map() | nil) ::
          {:ok, %{binary() => binary()}} | {:error, :withdrawal_not_acknowledged}
  def seen(organization_id, mission_id, spacecraft_ids, acks, activation \\ nil) do
    pins = WithdrawnPins.for_spacecraft(organization_id, mission_id, spacecraft_ids, activation)

    cond do
      pins == %{} ->
        {:ok, %{}}

      acknowledged?(acks, WithdrawnPins.basis(pins)) ->
        {:ok, Map.new(pins, fn {id, pin} -> {id, pin.hold_basis} end)}

      true ->
        {:error, :withdrawal_not_acknowledged}
    end
  end

  @doc """
  The metadata a member's approval row records: its own craft's basis, or nil when it ran an
  approved model. The key is always present, so a row that lacks it predates the record.
  """
  @spec metadata(%{binary() => binary()}, binary() | nil) :: map()
  def metadata(seen, spacecraft_id), do: %{"withdrawn_seen" => Map.get(seen, spacecraft_id)}

  defp acknowledged?(acks, basis),
    do: Enum.any?(acks, &(to_string(&1.key) == @key and &1.hold_basis == basis))
end
