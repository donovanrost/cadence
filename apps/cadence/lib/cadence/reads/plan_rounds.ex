defmodule Cadence.Reads.PlanRounds do
  @moduledoc """
  A contact plan's review rounds for plan detail (U36, qa #40):

  - `submission`: the round that submitted the shown version (`{actor, at, note, unchanged,
    round}`), or nil if it was never submitted;
  - `previous_round`: the round before it, with that version's decision (the `approval` shape)
    and the gap acknowledgements the author gave then, to prefill the gaps sheet; nil on the
    first round.
  """

  alias Cadence.ContactPlanning.PlanSubmissions
  alias Cadence.Reads.PlanApproval

  @spec load(binary(), binary(), binary(), pos_integer()) :: %{
          submission: map() | nil,
          previous_round: map() | nil
        }
  def load(organization_id, mission_id, plan_id, version) do
    rounds = PlanSubmissions.list(organization_id, mission_id, plan_id)
    current = Enum.find(rounds, &(&1.contact_plan_version == version))
    previous = current && Enum.find(rounds, &(&1.round == current.round - 1))

    %{
      submission: current && submission(current),
      previous_round:
        previous &&
          %{
            round: previous.round,
            version: previous.contact_plan_version,
            approval:
              PlanApproval.latest(
                organization_id,
                mission_id,
                plan_id,
                previous.contact_plan_version
              ),
            acknowledgements:
              Enum.map(previous.acknowledgements_document || [], &acknowledgement/1)
          }
    }
  end

  defp submission(round),
    do: %{
      round: round.round,
      actor: actor(round.actor_document),
      at: round.submitted_at,
      note: round.note,
      unchanged: round.unchanged
    }

  defp acknowledgement(ack), do: %{requirement_id: ack["requirement_id"], reason: ack["reason"]}

  defp actor(%{} = doc), do: %{kind: doc["kind"], id: doc["id"], name: doc["name"]}
  defp actor(_none), do: nil
end
