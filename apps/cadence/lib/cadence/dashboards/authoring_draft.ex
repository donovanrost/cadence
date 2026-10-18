defmodule Cadence.Dashboards.AuthoringDraft do
  @moduledoc """
  Server-owned, actor-bound staging transaction for one dashboard draft.

  Staging and discarding never write documents. Save persists the accumulated
  document against the originally observed durable version, exactly once under
  the store's optimistic lock, and makes it the current version (there is no
  separate publish step; see `Cadence.Dashboards.CurrentVersions`).

  The admitted commands are retained so that, after someone else saves, the
  author can `rebase/2`: replay their edits onto the newer version. This struct is not a browser DTO and must never
  be reconstructed from client-supplied document maps. A host owns its lifetime
  and must replace its retained value only after a confirmed response.
  """
  alias Cadence.Dashboards.{
    Authoring,
    AuthoringChanges,
    AuthoringErrors,
    AuthoringInput,
    CurrentVersions,
    Document,
    Documents,
    VersionDiff
  }

  @events ~w(rename add_section update_section remove_section move_section add_widget update_widget remove_widget layout runtime_defaults)
  @enforce_keys [:organization_id, :mission_id, :dashboard_id, :user_id, :baseline, :document]
  defstruct @enforce_keys ++ [revision: 0, changes: %{}, commands: []]

  def open(scope, mission, dashboard) do
    protect(fn ->
      with :ok <- Authoring.authorize(scope, mission),
           true <- AuthoringInput.id?(dashboard),
           {:ok, document} <-
             Documents.fetch_for_mode(scope.organization_id, mission, dashboard, :edit),
           true <- document_identity?(document, scope.organization_id, mission, dashboard),
           true <- length(document.sections) <= 64 and length(document.placements) <= 1024 do
        {:ok,
         %__MODULE__{
           organization_id: scope.organization_id,
           mission_id: mission,
           dashboard_id: dashboard,
           user_id: scope.user.user_id,
           baseline: document,
           document: document
         }}
      end
    end)
  end

  @doc "Reauthorizes and checks the retained baseline without replacing the staged document."
  def current(scope, %__MODULE__{} = draft) do
    protect(fn ->
      with :ok <- check(scope, draft), do: {:ok, draft.document}
    end)
  end

  def current(_, _), do: {:error, :invalid_input}

  def stage(scope, %__MODULE__{} = draft, event, input) when is_map(input) do
    protect(fn ->
      with true <- event in @events,
           :ok <- revision(draft, input["expected_revision"]),
           {:ok, version, payload} <-
             AuthoringInput.admit(event, Map.delete(input, "expected_revision")),
           :ok <- version(draft, version),
           :ok <- check(scope, draft),
           {:ok, document, details} <- AuthoringChanges.apply(draft.document, event, payload) do
        {:ok,
         %{
           draft
           | document: document,
             revision: draft.revision + 1,
             changes: Map.update(draft.changes, event, 1, &(&1 + 1)),
             commands: draft.commands ++ [{event, payload}]
         }, details}
      end
    end)
  end

  def stage(_, _, _, _), do: {:error, :invalid_input}

  def discard(scope, %__MODULE__{} = draft, input) do
    protect(fn ->
      with :ok <- control(draft, input), :ok <- check(scope, draft) do
        {:ok,
         %{
           draft
           | document: draft.baseline,
             changes: %{},
             commands: [],
             revision: draft.revision + 1
         }}
      end
    end)
  end

  def discard(_, _, _), do: {:error, :invalid_input}

  def save(scope, %__MODULE__{} = draft, input) do
    protect(fn ->
      with {:ok, message} <- message(input),
           :ok <- control(draft, Map.delete(input, "message")),
           :ok <- check(scope, draft),
           changed? = dirty?(draft),
           {:ok, saved} <- persist(scope, draft, changed?, message) do
        next = %{
          draft
          | document: saved,
            baseline: saved,
            changes: %{},
            commands: [],
            revision: draft.revision + 1
        }

        {:ok, next,
         %{
           version: 1,
           event: "save_draft",
           dashboard_id: draft.dashboard_id,
           document_version: Document.version(saved),
           changed: changed?
         }}
      end
    end)
  end

  def save(_, _, _), do: {:error, :invalid_input}

  def dirty?(%__MODULE__{} = draft), do: draft.document != draft.baseline

  @doc """
  Replays the staged commands onto the latest saved version after someone else
  saved. Commands that no longer apply (e.g. their widget was removed) are
  skipped and reported; the rest stay staged against the new baseline.
  """
  def rebase(scope, %__MODULE__{} = draft) do
    protect(fn ->
      with :ok <- Authoring.authorize(scope, draft.mission_id),
           true <- scope.organization_id == draft.organization_id,
           true <- scope.user.user_id == draft.user_id,
           {:ok, latest} <-
             Documents.fetch_for_mode(
               draft.organization_id,
               draft.mission_id,
               draft.dashboard_id,
               :edit
             ),
           true <-
             document_identity?(
               latest,
               draft.organization_id,
               draft.mission_id,
               draft.dashboard_id
             ) do
        {document, applied, skipped} = replay(latest, draft.commands)

        {:ok,
         %{
           draft
           | baseline: latest,
             document: document,
             commands: applied,
             changes: Enum.frequencies_by(applied, &elem(&1, 0)),
             revision: draft.revision + 1
         }, %{version: 1, event: "rebase", skipped: Enum.map(skipped, &elem(&1, 0))}}
      end
    end)
  end

  def rebase(_, _), do: {:error, :invalid_input}

  defp replay(document, commands) do
    Enum.reduce(commands, {document, [], []}, fn {event, payload} = command,
                                                 {doc, applied, skipped} ->
      case AuthoringChanges.apply(doc, event, payload) do
        {:ok, next, _details} -> {next, applied ++ [command], skipped}
        _ -> {doc, applied, skipped ++ [command]}
      end
    end)
  end

  defp persist(_scope, draft, false, _message), do: {:ok, draft.baseline}

  defp persist(scope, draft, true, message) do
    summary = message || describe(VersionDiff.changes(draft.baseline, draft.document))

    CurrentVersions.save(
      draft.organization_id,
      draft.mission_id,
      draft.dashboard_id,
      draft.document,
      expected_version: Document.version(draft.baseline),
      created_by: scope.user.user_id,
      change_summary: summary
    )
  end

  # Without a note, record what changed in words, like "Added widget “Uptime” and 2 more".
  defp describe([]), do: "Saved without changes"
  defp describe([%{label: label}]), do: label
  defp describe([%{label: label} | rest]), do: "#{label} and #{length(rest)} more"

  defp message(%{"message" => message}) when is_binary(message) do
    trimmed = String.trim(message)

    cond do
      byte_size(trimmed) > 1_000 or not String.valid?(trimmed) -> {:error, :invalid_input}
      trimmed == "" -> {:ok, nil}
      true -> {:ok, trimmed}
    end
  end

  defp message(%{"message" => _}), do: {:error, :invalid_input}
  defp message(_input), do: {:ok, nil}

  defp control(draft, %{"expected_version" => version, "expected_revision" => revision} = input)
       when map_size(input) == 2 do
    with :ok <- revision(draft, revision), do: version(draft, version)
  end

  defp control(_, _), do: {:error, :invalid_input}

  defp revision(draft, revision) when is_integer(revision) and revision in 0..999_999,
    do: if(draft.revision == revision, do: :ok, else: {:error, :conflict})

  defp revision(_, _), do: {:error, :invalid_input}

  defp version(draft, version) when is_integer(version) and version in 1..9_007_199_254_740_990,
    do: if(Document.version(draft.baseline) == version, do: :ok, else: {:error, :conflict})

  defp version(_, _), do: {:error, :invalid_input}

  defp check(scope, draft) do
    with :ok <- Authoring.authorize(scope, draft.mission_id),
         true <-
           scope.organization_id == draft.organization_id and scope.user.user_id == draft.user_id,
         true <-
           document_identity?(
             draft.baseline,
             draft.organization_id,
             draft.mission_id,
             draft.dashboard_id
           ),
         true <-
           document_identity?(
             draft.document,
             draft.organization_id,
             draft.mission_id,
             draft.dashboard_id
           ),
         true <- draft.document.metadata == draft.baseline.metadata,
         {:ok, current} <-
           Documents.fetch_for_mode(
             draft.organization_id,
             draft.mission_id,
             draft.dashboard_id,
             :edit
           ),
         true <-
           document_identity?(
             current,
             draft.organization_id,
             draft.mission_id,
             draft.dashboard_id
           ) do
      version(draft, Document.version(current))
    end
  end

  defp document_identity?(%Document{} = document, org, mission, dashboard),
    do:
      document.organization_id == org and document.mission_id == mission and
        document.dashboard_id == dashboard

  defp document_identity?(_, _, _, _), do: false

  defp protect(fun) do
    case fun.() do
      {:ok, _} = result -> result
      {:ok, _, _} = result -> result
      false -> {:error, :invalid_input}
      error -> AuthoringErrors.normalize(error)
    end
  rescue
    _ -> {:error, :unknown}
  catch
    _, _ -> {:error, :unknown}
  end
end
