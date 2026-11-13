defmodule Cadence.Administration.PlatformAudit do
  @moduledoc """
  The platform audit for Admin › Audit (L7) and, filtered to one organization, that
  organization's Audit (`kind: "platform"`): server sentences over `Administration.PlatformEvents`.
  """

  alias Cadence.Accounts
  alias Cadence.Accounts.PlatformDirectory
  alias Cadence.Administration.{Access, PlatformEvents}

  @page 100

  @spec list(term(), map()) :: {:ok, map()} | {:error, term()}
  def list(scope, params) do
    with {:ok, _admin} <- Access.authorize(scope) do
      rows = PlatformEvents.list(after: params["after"], limit: @page + 1)
      {page, more} = Enum.split(rows, @page)
      {:ok, %{events: events(page), next: if(more != [], do: List.last(page).platform_event_id)}}
    end
  end

  @doc "One organization's platform events, for its Audit (kind platform)."
  @spec for_organization(binary(), pos_integer()) :: [map()]
  def for_organization(organization_id, limit \\ 200) do
    [organization_id: organization_id, limit: limit]
    |> PlatformEvents.list()
    |> events()
  end

  @doc false
  def events(rows) do
    orgs = organizations(rows)
    actors = actors(rows)

    Enum.map(rows, fn row ->
      org = row.organization_id && Map.get(orgs, row.organization_id)

      %{
        id: "platform:#{row.platform_event_id}",
        at: row.occurred_at,
        actor: %{kind: "user", id: row.actor_id, name: Map.get(actors, row.actor_id)},
        kind: "platform",
        action: sentence(row, org),
        target:
          row.target_kind && %{kind: row.target_kind, id: row.target_id, label: row.target_label},
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

  defp sentence(%{action: "service_identity_revoked", target_id: id}, org),
    do: "Revoked service identity #{id} in #{org || "an organization"}"

  defp sentence(%{action: "admin_mode_entered", details: %{"expires_at" => until}}, _org)
       when is_binary(until),
       do: "Entered admin mode (until #{String.slice(until, 11, 5)}Z)"

  defp sentence(%{action: "admin_mode_entered"}, _org), do: "Entered admin mode"
  defp sentence(%{action: "admin_mode_left"}, _org), do: "Left admin mode"
  defp sentence(%{action: action}, _org), do: action

  defp organizations(rows) do
    rows
    |> Enum.map(& &1.organization_id)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> PlatformDirectory.organization_names()
  end

  defp actors(rows) do
    rows
    |> Enum.map(& &1.actor_id)
    |> Enum.uniq()
    |> Map.new(fn id ->
      case Accounts.fetch_user(id) do
        {:ok, user} -> {id, user.display_name || user.email}
        _missing -> {id, nil}
      end
    end)
  end
end
