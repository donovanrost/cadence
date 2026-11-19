defmodule Cadence.Contacts.PassClusters do
  @moduledoc """
  Whether a pass is near: any scheduled contact, in any mission, from `margin` before its AOS
  to `margin` after its LOS (canceled ones aside), or any realized contact still active (one
  that overruns its scheduled LOS, or was started by hand). Maintenance that should stay out of
  passes asks this before it runs (#359's identity state retention).

  The margin is 5 minutes by default: the team's pass-cluster window, AOS−5 min to LOS+5 min.
  """

  import Ecto.Query

  alias Cadence.Contacts.ContactStore.{RealizedContactRow, ScheduledContactRow}
  alias Cadence.Repo

  @default_margin_s 300

  @doc "True while any contact is within `margin_s` of its window, or a realized one is active."
  @spec near?(DateTime.t(), non_neg_integer()) :: boolean()
  def near?(%DateTime{} = now, margin_s \\ @default_margin_s)
      when is_integer(margin_s) and margin_s >= 0 do
    scheduled_near?(now, margin_s) or realized_active?()
  end

  defp scheduled_near?(now, margin_s) do
    latest_start = DateTime.add(now, margin_s, :second)
    earliest_end = DateTime.add(now, -margin_s, :second)

    ScheduledContactRow
    |> where([s], s.lifecycle_state != "canceled")
    |> where([s], s.starts_at <= ^latest_start)
    # A contact with no LOS yet counts from its AOS only, so a stale one can't hold this forever.
    |> where([s], coalesce(s.ends_at, s.starts_at) >= type(^earliest_end, :utc_datetime_usec))
    |> Repo.exists?()
  end

  defp realized_active? do
    RealizedContactRow
    |> where([r], r.lifecycle_state == "active")
    |> Repo.exists?()
  end
end
