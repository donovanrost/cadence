defmodule Cadence.Administration.ConsoleOrganizations do
  @moduledoc """
  Organizations for the console admin area (L7 AD1/AD2), platform administrators in admin mode
  only (`Access`). The list is 50 per page by slug, searchable by name or slug, with member and
  mission counts, when it was created and (once recorded) by whom. One organization adds its
  members, pending invitations and missions (up to 500 each). Queries:
  `Accounts.PlatformDirectory`. People are named by display name only, never the email
  (`PlatformNames`, #470).
  """

  alias Cadence.Accounts.PlatformDirectory
  alias Cadence.Administration.{Access, PlatformEvents, PlatformNames}

  @page 50
  @detail_cap 500

  @spec list(term(), map()) :: {:ok, map()} | {:error, term()}
  def list(scope, params) do
    with {:ok, _admin} <- Access.authorize(scope) do
      {page, more} =
        params["q"]
        |> PlatformDirectory.organizations(params["after"], @page + 1)
        |> Enum.split(@page)

      ids = Enum.map(page, & &1.id)
      members = PlatformDirectory.member_counts(ids)
      missions = PlatformDirectory.mission_counts(ids)
      creators = PlatformEvents.creators(ids)
      {:ok, names} = PlatformNames.display_names(scope, Map.values(creators))

      {:ok,
       %{
         organizations:
           Enum.map(page, fn org ->
             creator = Map.get(creators, org.id)

             Map.merge(org, %{
               members: Map.get(members, org.id, 0),
               missions: Map.get(missions, org.id, 0),
               created_by: creator && %{name: Map.get(names, creator)}
             })
           end),
         next: if(more != [], do: List.last(page).id)
       }}
    end
  end

  @spec show(term(), binary()) :: {:ok, map()} | {:error, term()}
  def show(scope, organization_id) do
    with {:ok, _admin} <- Access.authorize(scope),
         %{} = org <- PlatformDirectory.organization(organization_id) do
      {:ok,
       %{
         organization: org,
         members: PlatformDirectory.members(organization_id, @detail_cap),
         invitations: invitations(organization_id),
         missions: PlatformDirectory.missions(organization_id, @detail_cap)
       }}
    else
      nil -> {:error, :organization_not_found}
      error -> error
    end
  end

  @doc "Every mission with its organization (AD4)."
  def missions(limit), do: PlatformDirectory.all_missions(limit)

  @doc "Whether a slug is free; when it isn't, a free variant to suggest."
  @spec slug(term(), binary()) :: {:ok, map()} | {:error, term()}
  def slug(scope, slug) do
    with {:ok, _admin} <- Access.authorize(scope) do
      slug = String.trim(slug)
      available = not PlatformDirectory.slug_taken?(slug)

      {:ok,
       %{
         slug: slug,
         available: available,
         suggestion: if(available, do: nil, else: suggestion(slug))
       }}
    end
  end

  @doc false
  def suggestion(slug),
    do:
      Enum.find_value(2..50, fn n ->
        candidate = "#{slug}-#{n}"
        if PlatformDirectory.slug_taken?(candidate), do: nil, else: candidate
      end)

  defp invitations(organization_id) do
    now = DateTime.utc_now()

    organization_id
    |> PlatformDirectory.pending_invitations(@detail_cap)
    |> Enum.map(fn invitation ->
      invitation
      |> Map.put(:invited_by, invitation.inviter && %{name: invitation.inviter})
      |> Map.delete(:inviter)
      |> Map.put(
        :state,
        if(DateTime.before?(now, invitation.expires_at), do: "pending", else: "expired")
      )
    end)
  end
end
