defmodule Cadence.OrganizationsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities related to organizations.
  """

  alias Cadence.Organizations.Organization
  alias Cadence.Repo

  def unique_org_slug, do: "org-#{System.unique_integer([:positive])}"

  def organization_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        name: "Test Organization",
        slug: unique_org_slug(),
        status: "active",
        subscription_tier: "free"
      })

    %Organization{}
    |> Organization.changeset(attrs)
    |> Repo.insert!()
  end
end
