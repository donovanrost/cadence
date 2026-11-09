defmodule Cadence.Reads.PlanSupersession do
  @moduledoc """
  Whether newer requirement or template versions have overtaken a draft (K1,
  ux ScheduleFlow `superseded`). A plan that is still `draft` or
  `pending_approval` is superseded when a requirement it was planned for:

  - was cancelled because its template was versioned or its spacecraft left the
    template's target (`template_changed`; `TemplateSupersession`);
  - was cancelled or closed otherwise (`requirement_closed`);
  - has a newer version than the plan used (`requirement_changed`).

  Returns `%{at, by: %{name} | nil, reason, changes: [%{kind, id, name,
  from_version, to_version}]}` or nil. Nothing is written: the plan keeps its
  state, the console shows it dimmed with why.
  """

  alias Cadence.Accounts
  alias Cadence.ContactPlanning.{ContactRequirements, ContactRequirementTemplates}

  @open [:draft, :pending_approval]

  @spec check(binary(), binary(), map(), map()) :: map() | nil
  def check(organization_id, mission_id, %{lifecycle_state: state}, version)
      when state in @open do
    changes =
      ((version.requirement_refs_document || %{})["requirements"] || [])
      |> Enum.flat_map(&change(organization_id, mission_id, &1))

    summarize(changes)
  end

  def check(_organization_id, _mission_id, _plan, _version), do: nil

  defp change(organization_id, mission_id, %{"id" => id, "version" => used}) do
    case ContactRequirements.fetch(organization_id, mission_id, id) do
      {:ok, requirement, current} ->
        requirement_change(organization_id, mission_id, requirement, current, used)

      _missing ->
        []
    end
  end

  defp change(_organization_id, _mission_id, _ref), do: []

  defp requirement_change(organization_id, mission_id, requirement, current, used) do
    reason = requirement.lifecycle_reason || ""

    cond do
      requirement.lifecycle_state == :canceled and template_cause?(reason) ->
        [template_change(organization_id, mission_id, requirement, current)]

      requirement.lifecycle_state in [:canceled, :closed] ->
        [
          %{
            reason: "requirement_closed",
            at: requirement.lifecycle_changed_at,
            by: requirement.lifecycle_changed_by,
            change: requirement_ref(requirement, current, used)
          }
        ]

      requirement.current_version > used ->
        [
          %{
            reason: "requirement_changed",
            at: current.created_at,
            by: current.created_by,
            change: requirement_ref(requirement, current, used)
          }
        ]

      true ->
        []
    end
  end

  defp template_change(organization_id, mission_id, requirement, current) do
    generation = (current.metadata || %{})["generation"] || %{}
    template_id = generation["contact_requirement_template_id"]

    {name, to_version} =
      case ContactRequirementTemplates.fetch(organization_id, mission_id, template_id || "") do
        {:ok, _template, version} -> {version.name, version.version}
        _missing -> {nil, nil}
      end

    %{
      reason: "template_changed",
      at: requirement.lifecycle_changed_at,
      by: requirement.lifecycle_changed_by,
      change: %{
        kind: "template",
        id: template_id,
        name: name,
        from_version: generation["contact_requirement_template_version"],
        to_version: to_version
      }
    }
  end

  defp requirement_ref(requirement, current, used),
    do: %{
      kind: "requirement",
      id: requirement.contact_requirement_id,
      name: current.contact_intent,
      from_version: used,
      to_version: requirement.current_version
    }

  defp template_cause?(reason),
    do:
      String.starts_with?(reason, "template_versioned") or
        String.starts_with?(reason, "left_template_target")

  defp summarize([]), do: nil

  defp summarize(changes) do
    latest = Enum.max_by(changes, & &1.at, DateTime)

    reason =
      Enum.find_value(
        ["template_changed", "requirement_changed", "requirement_closed"],
        fn reason -> Enum.find_value(changes, &(&1.reason == reason and reason)) end
      )

    %{
      at: latest.at,
      by: actor(latest.by),
      reason: reason,
      changes: changes |> Enum.map(& &1.change) |> Enum.uniq()
    }
  end

  defp actor(user_id) when is_binary(user_id) do
    case Accounts.fetch_user(user_id) do
      {:ok, user} -> %{name: user.display_name || user.email}
      _system -> nil
    end
  end

  defp actor(_none), do: nil
end
