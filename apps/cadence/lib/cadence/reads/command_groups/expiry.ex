defmodule Cadence.Reads.CommandGroups.Expiry do
  @moduledoc """
  ux U75 (DECISIONS #97): how a group's expiry went, for its list row and read ("Expired · 2 of 5
  sent"). A group's members share one `expires_at`, so when it passes every member not yet sent
  ends `expired` at once.

  `%{expires_at, expired, sent, total}` once at least one member ended `expired`, else `nil`:
  `expired` counts members with `end_reason: :expired`; `sent` members that went out (released,
  in flight, or verified either way); `total` the group's `member_count`.
  """

  # Member stages that mean the member went out.
  @sent ~w(radiating executed indeterminate verified no_verifier verify_failed)a

  @spec summary(map(), [map()]) :: map() | nil
  def summary(group, targets) do
    members = Enum.flat_map(targets, & &1.members)

    case Enum.count(members, &(&1.end_reason == :expired)) do
      0 ->
        nil

      expired ->
        %{
          expires_at: expires_at(group),
          expired: expired,
          sent: Enum.count(members, &(&1.stage in @sent)),
          total: group.member_count
        }
    end
  end

  defp expires_at(%{release: %{"expires_at" => %DateTime{} = at}}), do: at

  defp expires_at(%{release: %{"expires_at" => iso}}) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, at, _offset} -> at
      _invalid -> nil
    end
  end

  defp expires_at(_group), do: nil
end
