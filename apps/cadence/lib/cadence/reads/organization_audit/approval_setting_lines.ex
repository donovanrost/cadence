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

  @doc """
  `{action, change}` for a governance revision's audit, or nil without one. `names`: mission id
  to display name, under the entry's organization (#430's moved missions; a missing one is null).
  """
  @spec line(map() | nil, map() | nil, %{binary() => binary()}) :: {binary(), map()} | nil
  def line(audit, mission, names \\ %{})

  def line(%{"scope" => "mission", "before" => before, "after" => after_value}, mission, _names) do
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

  def line(
        %{"scope" => "organization", "before" => before, "after" => after_value} = audit,
        _mission,
        names
      ) do
    {from, to} = {requirement(before["value"]), requirement(after_value["value"])}
    {allowed_before, allowed_after} = {before["allow_override"], after_value["allow_override"]}
    moved = moved(audit["missions"], names)

    sentences =
      ([
         from != to &&
           "#{direction(from, to)} approval (organization default): #{label(from)} → #{label(to)}",
         allowed_before != allowed_after && override_sentence(allowed_after)
       ] ++ moved_sentences(moved))
      |> Enum.filter(&is_binary/1)

    if sentences != [],
      do:
        {Enum.join(sentences, " "),
         %{
           before: %{approval_requirement: from, allow_override: allowed_before},
           after: %{approval_requirement: to, allow_override: allowed_after},
           missions: moved
         }}
  end

  def line(_audit, _mission, _names), do: nil

  # #430: the missions an organization save moved (stored with the save; none before #430), each
  # named under the entry's organization, null when it's gone.
  defp moved(missions, names) when is_list(missions) do
    for %{"mission_id" => id} = moved <- missions,
        do: %{id: id, name: Map.get(names, id), before: moved["before"], after: moved["after"]}
  end

  defp moved(_missions, _names), do: []

  # ux (#430): one sentence per new value, in the setting's own words (one save can move missions
  # both ways, so never "loosened" or "tightened" here): "Changed on 2 missions to Applies without
  # approval: EARENDIL and KESTREL." Up to 3 names, then "and N more"; a gone mission reads
  # "Unknown mission". A value outside the two reads "Changed approval on N missions."
  defp moved_sentences(moved) do
    moved
    |> Enum.group_by(& &1.after)
    |> Enum.sort_by(fn {value, _} -> Map.has_key?(@labels, value) |> Kernel.not() end)
    |> Enum.map(fn {value, missions} -> moved_sentence(Map.get(@labels, value), missions) end)
  end

  defp moved_sentence(nil, missions),
    do: "Changed approval on #{count(missions)}."

  defp moved_sentence(label, missions),
    do: "Changed on #{count(missions)} to #{label}: #{names(missions)}."

  defp count([_one]), do: "1 mission"
  defp count(missions), do: "#{length(missions)} missions"

  defp names(missions) do
    shown = missions |> Enum.take(3) |> Enum.map(&(&1.name || "Unknown mission"))
    rest = length(missions) - length(shown)

    case {shown, rest} do
      {[one], 0} -> one
      {shown, 0} -> Enum.join(Enum.drop(shown, -1), ", ") <> " and " <> List.last(shown)
      {shown, rest} -> Enum.join(shown, ", ") <> " and #{rest} more"
    end
  end

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
