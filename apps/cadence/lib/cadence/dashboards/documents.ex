defmodule Cadence.Dashboards.Documents do
  @moduledoc """
  Application service for dashboard document lifecycle and persistence.
  """

  alias Cadence.Dashboards.{Document, DocumentCodec, DocumentStore}

  def clone(organization_id, mission_id, source_dashboard_id, opts \\ []) do
    with {:ok, %Document{} = source} <-
           fetch_for_mode(organization_id, mission_id, source_dashboard_id, :edit) do
      source
      |> DocumentCodec.copy_for_scope(organization_id, mission_id,
        name: Keyword.get(opts, :name, "Copy of #{source.name}"),
        description: Keyword.get(opts, :description, source.description),
        source: "dashboard_clone",
        source_dashboard_id: source.dashboard_id,
        actor_id: Keyword.get(opts, :actor_id)
      )
      |> then(&persist(organization_id, &1))
    end
  end

  def import(organization_id, mission_id, json, opts \\ []) do
    with {:ok, %Document{} = source} <- DocumentCodec.decode_import(json) do
      source
      |> DocumentCodec.copy_for_scope(organization_id, mission_id,
        name: Keyword.get(opts, :name, source.name),
        description: Keyword.get(opts, :description, source.description),
        source: "dashboard_import",
        source_dashboard_id: source.dashboard_id,
        actor_id: Keyword.get(opts, :actor_id)
      )
      |> then(&persist(organization_id, &1))
    end
  end

  defdelegate persist(organization_id, document), to: DocumentStore, as: :persist_document

  defdelegate update(organization_id, mission_id, dashboard_id, document, opts),
    to: DocumentStore,
    as: :update_document

  defdelegate fetch(organization_id, mission_id, dashboard_id),
    to: DocumentStore,
    as: :fetch_document

  defdelegate fetch_published(organization_id, mission_id, dashboard_id),
    to: DocumentStore,
    as: :fetch_published_document

  defdelegate fetch_for_mode(organization_id, mission_id, dashboard_id, mode),
    to: DocumentStore,
    as: :fetch_document_for_mode

  defdelegate list(organization_id, mission_id), to: DocumentStore, as: :list_documents

  defdelegate list_summaries(organization_id, mission_id),
    to: DocumentStore,
    as: :list_dashboard_summaries

  defdelegate list_archived_summaries(organization_id, mission_id),
    to: DocumentStore,
    as: :list_archived_dashboard_summaries

  defdelegate archive(organization_id, mission_id, dashboard_id, opts),
    to: DocumentStore,
    as: :archive_document

  defdelegate restore(organization_id, mission_id, dashboard_id, opts),
    to: DocumentStore,
    as: :restore_document

  defdelegate delete(organization_id, mission_id, dashboard_id, opts),
    to: DocumentStore,
    as: :delete_document

  defdelegate list_versions(organization_id, mission_id, dashboard_id), to: DocumentStore
  defdelegate fetch_version(organization_id, mission_id, dashboard_id, version), to: DocumentStore

  defdelegate publish(organization_id, mission_id, dashboard_id, version, opts),
    to: DocumentStore,
    as: :publish_document

  defdelegate revert(organization_id, mission_id, dashboard_id, version, opts),
    to: DocumentStore,
    as: :revert_document
end
