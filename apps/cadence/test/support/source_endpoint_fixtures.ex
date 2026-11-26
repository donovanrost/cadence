defmodule Cadence.SourceEndpointFixtures do
  @moduledoc """
  Inserts a source endpoint with a fixture ID for tests that pin existing
  routes, bindings, or ingress evidence to a known persisted row.
  """

  alias Cadence.Platform.ScopedReadUpdates
  alias Cadence.Repo
  alias Cadence.SourceEndpoints.{SourceEndpoint, SourceEndpointRow}

  def persist(%SourceEndpoint{} = endpoint) do
    with {:ok, row} <- Repo.insert(SourceEndpointRow.changeset(endpoint)) do
      resource = SourceEndpointRow.to_domain(row)

      ScopedReadUpdates.publish_result(
        {:ok, resource},
        :spacecraft_configuration_changed,
        resource.organization_id,
        resource.mission_id
      )
    end
  end

  def persist(organization_id, %SourceEndpoint{} = endpoint) do
    persist(%{endpoint | organization_id: organization_id})
  end
end
