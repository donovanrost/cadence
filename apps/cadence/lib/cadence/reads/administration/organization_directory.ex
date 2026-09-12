defmodule Cadence.Reads.Administration.OrganizationDirectory do
  @moduledoc "Bounded global organization directory for active platform administrators."
  alias Cadence.Administration.Access
  alias Cadence.Organizations

  def load(scope, params \\ %{}) do
    with {:ok, user} <- Access.authorize(scope),
         {:ok, cursor} <- cursor(params) do
      page = Organizations.page_organizations(cursor)

      {:ok,
       %{
         "version" => 1,
         "user_id" => user.user_id,
         "observed_at" => DateTime.to_iso8601(DateTime.utc_now()),
         "limit" => 50,
         "query" => params,
         "organizations" => Enum.map(page.entries, &organization/1),
         "next_cursor" => page.next_cursor
       }}
    end
  end

  defp cursor(params) when params == %{}, do: {:ok, nil}

  defp cursor(%{"after_slug" => slug, "after_id" => id} = params)
       when map_size(params) == 2 and is_binary(slug) and byte_size(slug) in 1..800 and
              is_binary(id) and byte_size(id) in 1..120,
       do: {:ok, %{slug: slug, id: id}}

  defp cursor(_), do: {:error, :invalid_query}

  defp organization(org),
    do: %{"id" => org.organization_id, "name" => org.display_name, "slug" => org.slug}
end
