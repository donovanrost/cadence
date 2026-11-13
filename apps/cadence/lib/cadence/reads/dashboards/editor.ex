defmodule Cadence.Reads.Dashboards.Editor do
  @moduledoc "Authorized, versioned dashboard authoring state without frontend presentation."
  alias Cadence.Dashboards.{
    Authoring,
    AuthoringDefaults,
    AuthoringDraft,
    AuthoringInput,
    AuthoringWidget,
    Document,
    Documents,
    LibraryLifecycle
  }

  alias Cadence.Reads.Dashboards.Workspace

  def load(scope, mission, dashboard, opts \\ []) do
    with :ok <- Authoring.authorize(scope, mission),
         true <- AuthoringInput.id?(dashboard),
         {:ok, document} <-
           Documents.fetch_for_mode(scope.organization_id, mission, dashboard, :edit),
         true <-
           document.organization_id == scope.organization_id and document.mission_id == mission and
             document.dashboard_id == dashboard do
      {:ok, project(document, preview(scope, mission, dashboard, document, opts))}
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  @doc """
  Projects a reauthorized staging transaction and its actual unsaved preview.
  The model's document_version is the save precondition, not a claim that the
  candidate is persisted. Revision identifies the staged content independently.
  """
  def staged(scope, %AuthoringDraft{} = draft, opts \\ []) do
    with {:ok, document} <- AuthoringDraft.current(scope, draft) do
      preview =
        case Workspace.preview(scope, document, opts) do
          {:ok, snapshot} -> snapshot
          _ -> nil
        end

      {:ok,
       %{
         version: 1,
         revision: draft.revision,
         dirty: AuthoringDraft.dirty?(draft),
         model: project(document, preview)
       }}
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  @doc "Editable outline of a server-held document, without resolving a preview."
  def outline(%Document{} = document), do: document |> project(nil) |> Map.delete(:preview)

  defp project(document, preview) do
    {:ok, defaults_json} = AuthoringDefaults.encode(document.defaults)
    library = placed_library_items(document)

    %{
      version: 3,
      organization_id: document.organization_id,
      mission_id: document.mission_id,
      dashboard_id: document.dashboard_id,
      document_version: Document.version(document),
      name: document.name,
      description: document.description || "",
      defaults: AuthoringWidget.defaults(),
      runtime_defaults_json: defaults_json,
      grid: Map.take(document.grid, [:columns, :row_height_px, :gap_px]),
      sections:
        Enum.map(
          document.sections,
          &%{
            id: &1.section_id,
            title: &1.title,
            description: &1.description || "",
            collapsed_by_default: &1.collapsed_by_default?
          }
        ),
      placements: Enum.map(document.placements, &placement(document, &1, library)),
      preview: preview
    }
  end

  # One lookup for every library item the document places (dashboards' retired caution).
  defp placed_library_items(document) do
    ids =
      for %{content_kind: :library, library_widget_id: id} <- document.placements,
          is_binary(id),
          uniq: true,
          do: id

    LibraryLifecycle.placed_items(document.organization_id, document.mission_id, ids)
  end

  defp placement(document, placement, library) do
    fields = AuthoringWidget.fields(placement)

    editable =
      placement.content_kind == :embedded and not is_nil(placement.widget_def) and
        placement.widget_def.widget_type_version == 1 and AuthoringInput.widget_fields?(fields)

    %{
      id: placement.placement_id,
      section_id: placement.section_id,
      title: title(placement, library),
      library: library_ref(placement, library),
      editable: editable,
      fields: if(editable, do: fields, else: nil),
      observables: if(editable, do: AuthoringWidget.observables(placement), else: []),
      layout: Map.take(placement.layout, [:x, :y, :w, :h]),
      constraints: Document.layout_constraints(document, placement)
    }
  end

  defp title(%{widget_def: %{} = widget_def}, _library), do: widget_def.title || "Untitled widget"

  defp title(%{content_kind: :library, library_widget_id: id}, library),
    do: get_in(library, [id, :name]) || "Library widget"

  defp title(_placement, _library), do: "Library widget"

  # Null for embedded placements; `retired` means a save would be refused for it.
  defp library_ref(%{content_kind: :library, library_widget_id: id} = placement, library)
       when is_binary(id),
       do: %{
         item_id: id,
         version: placement.library_version,
         retired: get_in(library, [id, :retired]) != false
       }

  defp library_ref(_placement, _library), do: nil

  defp preview(scope, mission, dashboard, document, opts) do
    case Workspace.load(scope, mission, dashboard, :edit, opts) do
      {:ok, %{document_version: version} = snapshot} ->
        if version == Document.version(document), do: snapshot

      _ ->
        nil
    end
  end
end
