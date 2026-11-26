defmodule Cadence.Reads.VerifierSeries.Points do
  @moduledoc """
  Every telemetry point a group's verifiers watch (U2, fe-ops 11-14), with the members whose OWN
  verifiers watch it. Targets pinned to different catalog revisions can differ (11-14: only 001 on
  Revision 4 has 'Mode applied' on SET_MODE), so each point names its own targets.
  Ordered by stack position, then the verifier's order on the command.
  """

  @doc "A verifier plan's telemetry subject, or nil for an uplink (`transport:`) verifier."
  @spec subject(map()) :: binary() | nil
  def subject(%{success_criteria: %{subject_ref: ref}}) when is_binary(ref) do
    ref = String.trim(ref)

    if String.starts_with?(ref, "transport:"),
      do: nil,
      else: String.trim_leading(ref, "telemetry:")
  end

  def subject(_plan), do: nil

  @doc """
  `[%{position, subject, verifier_name, plan, request_ids}]` from each member's own verifier plans
  (`plans_for.(member)`).
  """
  @spec list([map()], (map() -> [map()])) :: [map()]
  def list(members, plans_for) do
    members
    |> Enum.flat_map(&entries(&1, plans_for))
    |> Enum.group_by(&elem(&1, 0))
    |> Enum.map(fn {{position, subject}, [{_key, _order, plan, _id} | _] = entries} ->
      %{
        position: position,
        subject: subject,
        order: entries |> Enum.map(&elem(&1, 1)) |> Enum.min(),
        verifier_name: plan.name,
        plan: plan,
        request_ids: entries |> Enum.map(&elem(&1, 3)) |> Enum.uniq()
      }
    end)
    |> Enum.sort_by(&{&1.position, &1.order, &1.subject})
  end

  # One entry per telemetry verifier on the member's command: {{position, subject}, order, plan, id}.
  defp entries(member, plans_for) do
    position = member.group_position

    for {plan, order} <- Enum.with_index(plans_for.(member)),
        subject = subject(plan),
        not is_nil(subject),
        do: {{position, subject}, order, plan, member.command_request_id}
  end
end
