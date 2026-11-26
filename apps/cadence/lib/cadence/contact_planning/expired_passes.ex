defmodule Cadence.ContactPlanning.ExpiredPasses do
  @moduledoc """
  #273: the ONE rule for which of a plan's selected passes can't be booked any more ("booking
  window closed"). The plan read, the approve, the decision record and execution all use it, so
  they always agree on the same set.

  A pass counts as closed when its offer's `expires_at` is within `margin_seconds/0` (60 s) of the
  decision's `now`: the lookahead means a window about to close is already in the list the approver
  sees. A pass whose provider gave no `expires_at` counts as closed too (fail closed: there's no
  evidence its window is open). The rule is the provider's booking window, not the pass's AOS.

  `compute/2` returns:
  - `ids`: the closed passes' snapshot ids, sorted;
  - `skipped`: the same passes, each with its reason (`opportunity_expired` or `no_booking_window`),
    which the approval's decision record stores;
  - `digest`: `digest/1` of `ids`, which the approver echoes back as `expected_expired_digest`;
  - `next_expiry_at`: the earliest moment one of the still-bookable passes will count as closed
    (its `expires_at` minus the margin), or `nil` when none is left.

  All of them cover the WHOLE set. Only API responses cap the items they list.
  """

  @margin_seconds 60

  @type pass :: %{
          required(:contact_opportunity_snapshot_id) => binary(),
          required(:expires_at) => DateTime.t() | nil,
          optional(atom()) => term()
        }
  @type t :: %{
          ids: [binary()],
          skipped: [%{binary() => binary()}],
          digest: binary(),
          next_expiry_at: DateTime.t() | nil
        }

  @doc "The lookahead in seconds: a window closing within it already counts as closed."
  @spec margin_seconds() :: pos_integer()
  def margin_seconds, do: @margin_seconds

  @doc "The closed set among `passes` at `now` (see the moduledoc)."
  @spec compute([pass()], DateTime.t()) :: t()
  def compute(passes, %DateTime{} = now) when is_list(passes) do
    cutoff = DateTime.add(now, @margin_seconds, :second)
    {closed, open} = Enum.split_with(passes, &closed?(&1, cutoff))

    skipped =
      closed
      |> Enum.map(&%{"snapshot_id" => &1.contact_opportunity_snapshot_id, "reason" => reason(&1)})
      |> Enum.sort_by(& &1["snapshot_id"])

    ids = Enum.map(skipped, & &1["snapshot_id"])

    %{
      ids: ids,
      skipped: skipped,
      digest: digest(ids),
      next_expiry_at: next_expiry_at(open)
    }
  end

  @doc """
  The expired set's digest: lowercase hex SHA-256 of the canonical JSON `[1, <sorted ids>]`
  (layout 1, positional, no maps). This is the ONE definition; the API passes it through as an
  opaque string and never computes it. Golden-tested.
  """
  @spec digest([binary()]) :: binary()
  def digest(ids) when is_list(ids) do
    [1, Enum.sort(ids)]
    |> Jason.encode!(escape: :json)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp closed?(%{expires_at: %DateTime{} = expires_at}, cutoff),
    do: not DateTime.after?(expires_at, cutoff)

  defp closed?(_pass_without_window, _cutoff), do: true

  defp reason(%{expires_at: %DateTime{}}), do: "opportunity_expired"
  defp reason(_pass_without_window), do: "no_booking_window"

  defp next_expiry_at([]), do: nil

  defp next_expiry_at(open) do
    open
    |> Enum.map(&DateTime.add(&1.expires_at, -@margin_seconds, :second))
    |> Enum.min(DateTime)
  end
end
