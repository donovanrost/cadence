defmodule Cadence.Commanding.Groups.MemberCheck do
  @moduledoc """
  Whether a command group's member rows still match what submission recorded (four-eyes audit
  11-17, P0, defence in depth). The review token covers the group row's `member_count`, not the
  member ids, so a GO on a group whose member rows changed is refused, and the group read says so
  before anyone tries (#120, ux U92 "Up front"). Both use this one test, so they never disagree.

  It compares counts, not which commands, so its words say only that the commands changed.
  todo(#120): GroupDecision's private members_as_submitted/2 calls this once #280 lands; until
  then Cadence.Reads.CommandGroupMembersChangedTest pins the two together.
  """

  alias Cadence.Commanding.Groups.CommandGroup

  @spec as_submitted(CommandGroup.t(), non_neg_integer()) ::
          :ok | {:error, {:command_group_members_changed, non_neg_integer(), non_neg_integer()}}
  def as_submitted(%CommandGroup{member_count: submitted}, current) when is_integer(current) do
    if current == submitted,
      do: :ok,
      else: {:error, {:command_group_members_changed, submitted, current}}
  end

  @doc """
  The group read's three fields: while the group awaits a decision, whether its members changed
  and both counts; otherwise all three nil (always present, so a reader can't mistake an older
  server for a group that isn't pending).
  """
  @spec read_fields(CommandGroup.t(), [map()]) :: %{
          members_changed: boolean() | nil,
          submitted_member_count: non_neg_integer() | nil,
          current_member_count: non_neg_integer() | nil
        }
  def read_fields(%CommandGroup{state: :approval_pending} = group, members) do
    current = length(members)

    %{
      members_changed: as_submitted(group, current) != :ok,
      submitted_member_count: group.member_count,
      current_member_count: current
    }
  end

  def read_fields(%CommandGroup{}, _members),
    do: %{members_changed: nil, submitted_member_count: nil, current_member_count: nil}
end
