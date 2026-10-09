defmodule Cadence.Dashboards.CurrentVersions do
  @moduledoc """
  Grafana-style dashboard versioning: there is no separate publish step.

  Every operation that produces a version — create, save, restore — also makes
  that version the dashboard's current (published) version in the same
  transaction, so what an author saves is what everyone sees. Publish-readiness
  validation therefore gates the save itself. History stays append-only:
  restoring an old version creates a new version that copies it.

  Runtime invalidations are broadcast again after commit so subscribers that
  re-read on a pre-commit notice still observe the new version.
  """
  alias Cadence.Dashboards.{Document, DocumentStore, RuntimeInvalidation, Version}
  alias Cadence.Repo

  @doc "Creates a dashboard whose first version is immediately current."
  @spec create(binary(), Document.t(), keyword()) :: {:ok, Document.t()} | {:error, term()}
  def create(organization_id, %Document{} = document, opts \\ []) do
    transact(fn ->
      with {:ok, created} <- DocumentStore.persist_document(organization_id, document),
           {:ok, _} <- publish(created, opts) do
        created
      end
    end)
  end

  @doc """
  Saves `document` as the next version, observed at `expected_version`, and
  makes it current. Options: `:created_by`, `:change_summary`.
  """
  @spec save(binary(), binary(), binary(), Document.t(), keyword()) ::
          {:ok, Document.t()} | {:error, term()}
  def save(organization_id, mission_id, dashboard_id, %Document{} = document, opts) do
    transact(fn ->
      with {:ok, saved} <-
             DocumentStore.update_document(organization_id, mission_id, dashboard_id, document,
               expected_version: Keyword.fetch!(opts, :expected_version),
               created_by: Keyword.get(opts, :created_by),
               change_summary: Keyword.get(opts, :change_summary)
             ),
           {:ok, _} <- publish(saved, opts) do
        saved
      end
    end)
  end

  @doc """
  Restores `version` as a new current version, observed at `expected_version`.
  """
  @spec restore(binary(), binary(), binary(), pos_integer(), keyword()) ::
          {:ok, Version.t()} | {:error, term()}
  def restore(organization_id, mission_id, dashboard_id, version, opts) do
    transact(fn ->
      with {:ok, %Version{} = restored} <-
             DocumentStore.revert_document(organization_id, mission_id, dashboard_id, version,
               expected_version: Keyword.fetch!(opts, :expected_version),
               created_by: Keyword.get(opts, :created_by),
               change_summary: "Restored from version #{version}"
             ),
           {:ok, _} <- publish(restored.document, opts) do
        restored
      end
    end)
  end

  defp publish(%Document{} = document, opts) do
    version = Document.version(document)

    DocumentStore.publish_document(
      document.organization_id,
      document.mission_id,
      document.dashboard_id,
      version,
      expected_version: version,
      published_by: Keyword.get(opts, :created_by)
    )
  end

  defp transact(fun) do
    result =
      Repo.transaction(fn ->
        case fun.() do
          {:error, reason} -> Repo.rollback(reason)
          value -> value
        end
      end)

    with {:ok, value} <- result do
      notify(value)
      {:ok, value}
    end
  end

  defp notify(%Version{document: document}), do: notify(document)

  defp notify(%Document{} = document) do
    RuntimeInvalidation.dashboard_version_changed(%{
      organization_id: document.organization_id,
      mission_id: document.mission_id,
      dashboard_id: document.dashboard_id,
      document_version: Document.version(document),
      lifecycle_action: :published
    })
  end
end
