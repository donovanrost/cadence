defmodule Cadence.Reads.OrganizationAudit.ApprovalSettingLines do
  @moduledoc """
  The audit's sentence and raw before/after for a change to the approval (governance) setting
  (#233; ux U96), from the revision's `audit` that `ActivationPolicy.save/4` stores. Never the raw
  words `direct`/`independent` in a sentence; `change` carries the raw values.

  A revision stored before #233 has no `audit`: `line/2` answers nil and the entry keeps the
  generic "Changed Governance settings".
  """

  @labels %{
    "direct" => "Applies without approval",
    "independent" => "Needs a second person's approval"
  }

  @doc "`{action, change}` for a governance revision's audit, or nil without one."
  @spec line(map() | nil, map() | nil) :: {binary(), map()} | nil
  def line(%{"scope" => "mission", "before" => before, "after" => after_value}, mission) do
    from = requirement(before["effective"])
    to = requirement(after_value["effective"])
    own_before? = own?(before["override"])
    own_after? = own?(after_value["override"])
    name = (mission && mission[:name]) || "this mission"

    case mission_sentence(name, from, to, own_before?, own_after?) do
      nil ->
        nil

      action ->
        {action,
         %{
           before: %{approval_requirement: from, override: own_before?},
           after: %{approval_requirement: to, override: own_after?}
         }}
    end
  end

  def line(%{"scope" => "organization", "before" => before, "after" => after_value}, _mission) do
    {from, to} = {requirement(before["value"]), requirement(after_value["value"])}
    {allowed_before, allowed_after} = {before["allow_override"], after_value["allow_override"]}

    sentences =
      [
        from != to &&
          "#{direction(from, to)} approval (organization default): #{label(from)} → #{label(to)}",
        allowed_before != allowed_after && override_sentence(allowed_after)
      ]
      |> Enum.filter(&is_binary/1)

    if sentences != [],
      do:
        {Enum.join(sentences, " "),
         %{
           before: %{approval_requirement: from, allow_override: allowed_before},
           after: %{approval_requirement: to, allow_override: allowed_after}
         }}
  end

  def line(_audit, _mission), do: nil

  defp mission_sentence(name, from, to, _own_before?, own_after?) when from != to do
    suffix = if own_after?, do: "", else: " (the organization's setting)"
    "#{direction(from, to)} approval on #{name}: #{label(from)} → #{label(to)}#{suffix}"
  end

  defp mission_sentence(name, _from, to, true, false),
    do:
      "#{name} now uses the organization's approval setting (#{label(to)}); " <>
        "what applies doesn't change."

  defp mission_sentence(name, _from, to, false, true),
    do: "#{name} now sets its own approval setting (#{label(to)}); what applies doesn't change."

  defp mission_sentence(_name, _from, _to, _own_before?, _own_after?), do: nil

  defp override_sentence(true), do: "Missions may now set their own approval setting."
  defp override_sentence(_false), do: "Missions can no longer set their own approval setting."

  # No value before (an organization that never saved one): neither way, just set.
  defp direction(nil, _to), do: "Set"
  defp direction("independent", "direct"), do: "Loosened"
  defp direction(_from, _to), do: "Tightened"

  defp label(value), do: Map.get(@labels, value, "Not set")

  defp requirement(document), do: (document || %{})["approval_requirement"]

  defp own?(override), do: is_map(override) and Map.has_key?(override, "approval_requirement")
end
