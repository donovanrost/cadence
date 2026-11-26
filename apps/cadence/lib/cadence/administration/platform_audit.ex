defmodule Cadence.Administration.PlatformAudit do
  @moduledoc """
  The platform audit for Admin › Audit (L7) and, filtered to one organization, that
  organization's Audit (`kind: "platform"`): server sentences over `Administration.PlatformEvents`.

  Who it names depends on who reads it (#470):
  - `list/2` is for platform administrators in admin mode only (`Access`, checked first). It names
    the platform admin who acted, by display name only, never the email (`PlatformNames`).
  - `for_organization/2` feeds a customer organization's own Audit. Its actors carry only their
    id, never a name; `Reads.OrganizationAudit` names them by that organization's rule, so a
    platform admin who isn't one of its members reads `{kind: "user", id: nil, name: nil}`. Every
    platform event is a platform admin's act, which is how the console words those rows (ux,
    ca-ux #523: "the team that runs Cadence").
  """

  alias Cadence.Accounts.PlatformDirectory
  alias Cadence.Administration.{Access, PlatformEvents, PlatformNames}

  @page 100

  @spec list(term(), map()) :: {:ok, map()} | {:error, term()}
  def list(scope, params) do
    with {:ok, _admin} <- Access.authorize(scope) do
      rows = PlatformEvents.list(after: params["after"], limit: @page + 1)
      {page, more} = Enum.split(rows, @page)

      {:ok, names} =
        PlatformNames.display_names(scope, page |> Enum.map(& &1.actor_id) |> Enum.uniq())

      {:ok,
       %{events: events(page, names), next: if(more != [], do: List.last(page).platform_event_id)}}
    end
  end

  @doc """
  One organization's platform events, for its Audit (kind platform). Actors are unnamed here:
  `Reads.OrganizationAudit` names them under the organization's rule.
  """
  @spec for_organization(binary(), pos_integer()) :: [map()]
  def for_organization(organization_id, limit \\ 200) do
    [organization_id: organization_id, limit: limit]
    |> PlatformEvents.list()
    |> events()
  end

  @doc false
  # Sentences with unnamed actors (an id only); `names` (platform admins' reads) names them.
  def events(rows, names \\ %{}) do
    orgs = organizations(rows)

    Enum.map(rows, fn row ->
      org = row.organization_id && Map.get(orgs, row.organization_id)

      %{
        id: "platform:#{row.platform_event_id}",
        at: row.occurred_at,
        actor: %{kind: "user", id: row.actor_id, name: Map.get(names, row.actor_id)},
        kind: "platform",
        action: sentence(row, org),
        target: row.target_kind && %{kind: row.target_kind, id: row.target_id, label: label(row)},
        organization: row.organization_id && %{id: row.organization_id, name: org},
        mission: nil,
        reason: nil
      }
    end)
  end

  defp sentence(%{action: "organization_created", target_label: name}, _org),
    do: "Created organization #{name}"

  defp sentence(%{action: "invitation_created", target_label: email}, org),
    do: "Invited #{email} to #{org || "an organization"}"

  defp sentence(%{action: "invitation_withdrawn"}, org),
    do: "Withdrew an invitation to #{org || "an organization"}"

  defp sentence(%{action: "service_identity_issued", target_label: name}, org),
    do: "Issued service identity #{name} in #{org || "an organization"}"

  defp sentence(%{action: "service_identity_rotated", target_label: name}, _org),
    do: "Rotated the token of service identity #{name}"

  defp sentence(%{action: "service_identity_revoked"} = row, org),
    do: "Revoked service identity #{label(row)} in #{org || "an organization"}"

  defp sentence(%{action: "admin_mode_entered", details: %{"expires_at" => until}}, _org)
       when is_binary(until),
       do: "Entered admin mode (until #{String.slice(until, 11, 5)}Z)"

  defp sentence(%{action: "admin_mode_entered"}, _org), do: "Entered admin mode"
  defp sentence(%{action: "admin_mode_left"}, _org), do: "Left admin mode"

  # ux U53: 'Switched platform binding default_flight_telemetry from <from> to <to> · 12 missions,
  # 3 live passes: "<reason>"'. A count that wasn't recorded is left out, never guessed (U20).
  defp sentence(%{action: "platform_binding_switched", details: details} = row, _org)
       when is_map(details) do
    counts =
      [
        count(details["affected_missions"], "mission", "missions"),
        count(details["live_passes_total"], "live pass", "live passes")
      ]
      |> Enum.reject(&is_nil/1)

    suffix = if counts == [], do: "", else: " · " <> Enum.join(counts, ", ")

    "Switched platform binding #{label(row)} from #{source_name(details["from"])} to " <>
      "#{source_name(details["to"])}#{suffix}: “#{details["reason"]}”"
  end

  defp sentence(%{action: action}, _org), do: action

  defp source_name(%{"display_name" => name}) when is_binary(name), do: name
  defp source_name(%{"id" => id}) when is_binary(id), do: id
  defp source_name(_source), do: "a source"

  defp count(1, singular, _plural), do: "1 #{singular}"
  defp count(n, _singular, plural) when is_integer(n), do: "#{n} #{plural}"
  defp count(_n, _singular, _plural), do: nil

  # The target's name when one was recorded, else its id: never null (withdrawn invitations and
  # revokes recorded before 11-13 carry no name).
  defp label(row), do: row.target_label || to_string(row.target_id)

  defp organizations(rows) do
    rows
    |> Enum.map(& &1.organization_id)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> PlatformDirectory.organization_names()
  end
end
