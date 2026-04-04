defmodule Cadence.Organizations do
  @moduledoc """
  Persistence boundary for organizations.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.Organizations.Organization
  alias Cadence.Persistence.Schemas.OrganizationRow
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
