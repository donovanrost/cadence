defmodule Cadence.Organizations do
  @moduledoc """
  Persistence boundary for organizations.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.Organizations.{Organization, OrganizationRow}
  alias Cadence.Repo

  @spec persist_organization(Organization.t()) :: {:ok, Organization.t()} | {:error, term()}
  def persist_organization(%Organization{} = organization) do
    case Repo.insert(OrganizationRow.changeset(organization),
           on_conflict: :nothing,
           conflict_target: [:organization_id]
         ) do
      {:ok, %OrganizationRow{} = row} ->
        {:ok, OrganizationRow.to_domain(row)}

      {:error, %Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  @spec fetch_organization(binary()) :: {:ok, Organization.t()} | {:error, term()}
  def fetch_organization(organization_id) when is_binary(organization_id) do
    case Repo.get(OrganizationRow, organization_id) do
      %OrganizationRow{} = row -> {:ok, OrganizationRow.to_domain(row)}
      nil -> {:error, :organization_not_found}
    end
  end

  @doc "Inserts a newly generated organization without suppressing a conflicting identity."
  def create_organization(%Organization{} = organization) do
    case Repo.insert(OrganizationRow.changeset(organization)) do
      {:ok, row} -> {:ok, OrganizationRow.to_domain(row)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc "A maximum of 50 organizations in binary slug and identity order."
  def page_organizations(cursor \\ nil) do
    query =
      OrganizationRow
      |> order_by([row],
        asc: fragment(~s(? COLLATE "C"), row.slug),
        asc: fragment(~s(? COLLATE "C"), row.organization_id)
      )
      |> limit(51)

    query =
      case cursor do
        nil ->
          query

        %{slug: slug, id: id} ->
          where(
            query,
            [row],
            fragment(~s(? COLLATE "C" > ? COLLATE "C"), row.slug, ^slug) or
              (row.slug == ^slug and
                 fragment(~s(? COLLATE "C" > ? COLLATE "C"), row.organization_id, ^id))
          )
      end

    rows = Repo.all(query)
    entries = Enum.take(rows, 50)
    last = List.last(entries)

    %{
      entries: Enum.map(entries, &OrganizationRow.to_domain/1),
      next_cursor:
        if(length(rows) > 50,
          do: %{"after_slug" => last.slug, "after_id" => last.organization_id},
          else: nil
        )
    }
  end

  @spec list_organizations() :: [Organization.t()]
  def list_organizations do
    OrganizationRow
    |> order_by([organization_row], asc: organization_row.slug)
    |> Repo.all()
    |> Enum.map(&OrganizationRow.to_domain/1)
  end

  @spec count_organizations() :: non_neg_integer()
  def count_organizations do
    Repo.aggregate(OrganizationRow, :count, :organization_id)
  end
end
