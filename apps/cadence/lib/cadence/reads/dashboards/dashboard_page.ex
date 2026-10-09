defmodule Cadence.Reads.Dashboards.DashboardPage do
  @moduledoc """
  Authorized read model for the Ops dashboard page.

  Authors see the latest saved draft so their own work is visible before it is
  published; every other mission member sees the published version. A
  dashboard without a published version is only reported as unpublished to
  non-authors, never resolved from its draft.

  The runtime spacecraft scope comes from the browser, so it is admitted only
  when it names a spacecraft of this mission.
  """
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Dashboards.{AuthoringDraft, DashboardSummary, Documents}
  alias Cadence.Reads.Dashboards.Workspace
  alias Cadence.SpacecraftStore

  @max_scope_options 1_000

  @type view :: %{
          version: 2,
          author: boolean(),
          publication: map(),
          snapshot: map() | nil,
          scope_options: [map()]
        }

  @spec load(Scope.t(), binary(), binary(), map()) :: {:ok, view()} | {:error, atom()}
  def load(%Scope{} = scope, mission, dashboard, runtime) when is_map(runtime) do
    with {:ok, options} <- scope_options(scope, mission, runtime),
         {:ok, author, snapshot} <- snapshot(scope, mission, dashboard, runtime),
         {:ok, summary} <- Documents.fetch_summary(scope.organization_id, mission, dashboard) do
      {:ok,
       %{
         version: 2,
         author: author,
         publication: publication(summary),
         snapshot: snapshot,
         scope_options: options
       }}
    else
      {:error, :invalid_scope} -> {:error, :invalid_scope}
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  def load(_, _, _, _), do: {:error, :unavailable}

  @doc """
  Projects a staged authoring transaction for the edit-mode page: the same view
  shape, with the unsaved candidate resolved in place of the saved draft.

  When someone else saved a newer version, the candidate is still shown (the
  preview reauthorizes edit access) and reported as conflicting, so the author
  can review it before discarding to adopt the newer version.
  """
  @spec staged(Scope.t(), struct(), map()) ::
          {:ok, view(), %{document: struct(), conflict: boolean()}} | {:error, atom()}
  def staged(%Scope{} = scope, %AuthoringDraft{} = draft, runtime) when is_map(runtime) do
    with {:ok, options} <- scope_options(scope, draft.mission_id, runtime),
         {:ok, document, conflict} <- candidate(scope, draft),
         {:ok, snapshot} <- Workspace.preview(scope, document, runtime: runtime),
         {:ok, summary} <-
           Documents.fetch_summary(scope.organization_id, draft.mission_id, draft.dashboard_id) do
      {:ok,
       %{
         version: 2,
         author: true,
         publication: publication(summary),
         snapshot: snapshot,
         scope_options: options
       }, %{document: document, conflict: conflict}}
    else
      {:error, :invalid_scope} -> {:error, :invalid_scope}
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  defp candidate(scope, draft) do
    case AuthoringDraft.current(scope, draft) do
      {:ok, document} -> {:ok, document, false}
      {:error, :conflict} -> {:ok, draft.document, true}
      error -> error
    end
  end

  # Authors resolve the latest saved draft; Workspace refuses :edit to everyone else.
  defp snapshot(scope, mission, dashboard, runtime) do
    case Workspace.load(scope, mission, dashboard, :edit, runtime: runtime) do
      {:ok, snapshot} ->
        {:ok, true, snapshot}

      _ ->
        case Workspace.load(scope, mission, dashboard, :view, runtime: runtime) do
          {:ok, snapshot} -> {:ok, snapshot.author, snapshot}
          _ -> unpublished(scope, mission, dashboard)
        end
    end
  end

  defp unpublished(scope, mission, dashboard) do
    case Workspace.publication_requirement(scope, mission, dashboard) do
      {:ok, requirement} -> {:ok, requirement.author, nil}
      error -> error
    end
  end

  defp publication(%DashboardSummary{} = summary) do
    latest = summary.latest_version || summary.document_version
    published = summary.published_version

    %{
      latest_version: latest,
      published_version: published,
      published_at: summary.published_at && DateTime.to_iso8601(summary.published_at),
      lifecycle: summary.lifecycle_state,
      state:
        cond do
          is_nil(published) -> "unpublished"
          published == latest -> "published"
          true -> "draft_ahead"
        end
    }
  end

  defp scope_options(scope, mission, runtime) do
    resource = %{organization_id: scope.organization_id, mission_id: mission}

    with :ok <- Policy.authorize(scope, :operate_mission, resource) do
      spacecraft =
        scope.organization_id
        |> SpacecraftStore.list_spacecraft(mission)
        |> Enum.take(@max_scope_options)
        |> Enum.map(&%{id: &1.spacecraft_id, name: &1.display_name || &1.spacecraft_id})

      selected = get_in(runtime, [:scope_context, :spacecraft_id])

      if is_nil(selected) or Enum.any?(spacecraft, &(&1.id == selected)),
        do: {:ok, spacecraft},
        else: {:error, :invalid_scope}
    end
  end
end
