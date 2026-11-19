defmodule Cadence.Management.ApprovalSettingAccess do
  @moduledoc """
  What THIS viewer may change in the governance (approval) setting, for the console's Settings
  read (#233; user ruling 11-18). `ActivationPolicy.save/4` enforces the same rule; the tests
  check every value offered here saves, and every value withheld is refused.

  - An organization admin (or a platform admin in admin mode) may set either value, at the
    organization and on any mission, and hand a mission back to the organization's value.
  - A mission admin may only TIGHTEN its own mission: `independent`, unless the mission already
    sets its own `independent` (ux 11-18: pinning an inherited `independent` keeps the mission
    strict if the organization later loosens); never `direct`, even while `direct` is in effect
    (pinning it would loosen in advance; lead 11-18). It may hand the mission back to the
    organization's value only when that isn't looser.
  - An operator may change nothing.
  - While the organization doesn't allow an override, nobody changes a mission's value (the
    organization's is changed at the organization).

  `allowed_values` are the values the viewer may save (the field's enum values; `true`/`false`
  for `allow_override`), `[]` when none. `can_inherit` (mission level only) is whether the viewer
  may clear the mission's own value.
  """

  alias Cadence.Auth.{Policy, Scope}

  @requirements ["direct", "independent"]

  @spec flags(Scope.t(), binary() | nil, binary(), map()) :: map()
  def flags(%Scope{} = scope, nil, "approval_requirement", _snapshot),
    do: %{allowed_values: if(organization_admin?(scope), do: @requirements, else: [])}

  def flags(%Scope{} = scope, nil, "allow_override", _snapshot),
    do: %{allowed_values: if(organization_admin?(scope), do: [true, false], else: [])}

  def flags(_scope, _mission_id, "approval_requirement", %{source: "enforced"}),
    do: %{allowed_values: [], can_inherit: false}

  def flags(%Scope{} = scope, mission_id, "approval_requirement", snapshot) do
    effective = requirement(snapshot.effective)
    inherited = requirement(snapshot.organization_default)

    cond do
      organization_admin?(scope) ->
        %{allowed_values: @requirements, can_inherit: true}

      mission_admin?(scope, mission_id) ->
        %{
          allowed_values: if(own(snapshot) == "independent", do: [], else: ["independent"]),
          can_inherit: not loosens?(effective, inherited)
        }

      true ->
        %{allowed_values: [], can_inherit: false}
    end
  end

  def flags(_scope, _mission_id, _path, _snapshot), do: %{}

  defp loosens?(before, after_value), do: before == "independent" and after_value == "direct"

  defp requirement(document), do: (document || %{})["approval_requirement"]

  # The mission's own value, when its override sets one.
  defp own(%{source: "overridden", saved: saved}), do: requirement(saved)
  defp own(_snapshot), do: nil

  # The same named Policy actions ActivationPolicy.save checks (its todo(authz) marks them for
  # Cedar).
  defp organization_admin?(scope),
    do:
      Policy.authorize(scope, :manage_missions, %{organization_id: scope.organization_id}) == :ok

  defp mission_admin?(scope, mission_id),
    do:
      Policy.authorize(scope, :manage_mission, %{
        organization_id: scope.organization_id,
        mission_id: mission_id
      }) == :ok
end
