defmodule Cadence.Reads.Administration.OrganizationDetail do
  @moduledoc "Authorized organization facts and independently bounded membership, invitation and service pages."
  alias Cadence.{Accounts, Auth, Ids, Organizations}
  alias Cadence.Administration.Access

  @keys ~w(members_after invitations_after services_after)
  def load(scope, organization_id, params \\ %{}) do
    with {:ok, user} <- Access.authorize(scope),
         true <- Ids.valid_identifier?(organization_id),
         {:ok, organization} <- Organizations.fetch_organization(organization_id),
         {:ok, query} <- query(params) do
      members =
        Accounts.page_organization_members(organization_id, cursor(query["members_after"]))

      invitations =
        Accounts.page_pending_organization_invitations(
          organization_id,
          cursor(query["invitations_after"])
        )

      services =
        Auth.page_organization_service_identities(
          organization_id,
          cursor(query["services_after"])
        )

      {:ok,
       %{
         "version" => 1,
         "user_id" => user.user_id,
         "observed_at" => DateTime.to_iso8601(DateTime.utc_now()),
         "organization" => %{
           "id" => organization.organization_id,
           "name" => organization.display_name,
           "slug" => organization.slug
         },
         "limit" => 25,
         "query" => query,
         "issued_identity" => nil,
         "members" => page(members),
         "invitations" => invitation_page(invitations),
         "services" => page(services)
       }}
    else
      _ -> {:error, :unavailable}
    end
  end

  defp query(params) when is_map(params) do
    if Enum.all?(params, fn {k, v} -> k in @keys and (v == "" or Ids.valid_identifier?(v)) end),
      do: {:ok, Map.merge(Map.new(@keys, &{&1, ""}), params)},
      else: {:error, :invalid_query}
  end

  defp query(_), do: {:error, :invalid_query}
  defp cursor(""), do: nil
  defp cursor(value), do: value

  defp page(%{entries: rows, next_after: next}),
    do: %{"entries" => Enum.map(rows, &string_keys/1), "next_after" => next}

  defp invitation_page(value) do
    value
    |> Map.update!(
      :entries,
      &Enum.map(&1, fn row -> %{row | expires_at: DateTime.to_iso8601(row.expires_at)} end)
    )
    |> page()
  end

  defp string_keys(row), do: Map.new(row, fn {k, v} -> {Atom.to_string(k), v} end)
end
