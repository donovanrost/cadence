defmodule Cadence.Dashboards.StatelessAuthoring do
  @moduledoc """
  Dashboard authoring without a server-held draft (DECISIONS #76): the client keeps its
  commands and sends them with the version it started from. Each call opens the document at
  `base_version`, replays the commands through the authoring admission and changes (the legacy
  page's server-held draft went with L8a), and either returns the staged result (`preview/5`) or persists it
  through `CurrentVersions` (`save/6`, `copy/6`). `rebase/4` replays onto the latest version
  after someone else saved.

  `commands` is a list of `%{"event" => event, "input" => map}`, at most #{256}. The first
  command that fails is reported as `{:error, {:command, index, code, field}}`; more than the
  cap is `{:error, :too_many_commands}` (the client says "Save to keep going"). A save, copy or
  restore that fails publish readiness is `{:error, {:not_ready, [%{placement_id, code,
  message}]}}`.
  """

  alias Cadence.Accounts

  alias Cadence.Dashboards.{
    Authoring,
    AuthoringChanges,
    AuthoringErrors,
    AuthoringInput,
    CurrentVersions,
    Document,
    DocumentCodec,
    Documents,
    DocumentStore,
    PublishReadinessPresentation,
    ValidationResult,
    Version,
    VersionDiff
  }

  @max_commands 256

  @doc "The staged document for `commands` on `base_version`; nothing is written."
  def preview(scope, mission, dashboard, base_version, commands) do
    with {:ok, current} <- open(scope, mission, dashboard),
         {:ok, base} <- base(current, base_version),
         {:ok, document, details} <- replay(base, commands) do
      {:ok,
       %{
         document: document,
         base_version: base_version,
         current_version: Document.version(current),
         changes: changes(commands),
         details: details,
         diff: VersionDiff.changes(base, document)
       }}
    end
  rescue
    _exception -> {:error, :unknown}
  end

  @doc """
  Saves `commands` replayed on `base_version` as the next, current version. `base_version` must
  still be current (`{:error, {:conflict, current_version}}` otherwise; rebase first). No
  commands saves nothing (`changed: false`).
  """
  def save(scope, mission, dashboard, base_version, commands, message) do
    with {:ok, summary} <- message(message),
         {:ok, current} <- open(scope, mission, dashboard),
         :ok <- current?(current, base_version),
         {:ok, document, _details} <- replay(current, commands) do
      persist(scope, current, document, summary)
    end
  rescue
    _exception -> {:error, :unknown}
  end

  @doc """
  Replays `commands` onto the latest version. Commands that no longer apply are skipped with
  their reason; the client keeps only `applied` (indexes into `commands`).
  """
  def rebase(scope, mission, dashboard, commands) do
    with {:ok, current} <- open(scope, mission, dashboard),
         {:ok, admitted} <- admit_all(commands) do
      {document, applied, skipped} =
        admitted |> Enum.with_index() |> Enum.reduce({current, [], []}, &rebase_step/2)

      {:ok,
       %{
         document: document,
         base_version: Document.version(current),
         applied: Enum.reverse(applied),
         skipped: Enum.reverse(skipped)
       }}
    end
  rescue
    _exception -> {:error, :unknown}
  end

  @doc """
  A new dashboard from `base_version` with `commands` replayed (unsaved edits survive "Save as
  copy"); `[]` copies `base_version` as it is. `attrs`: `%{"name" => name}`.
  """
  def copy(scope, mission, dashboard, base_version, commands, %{"name" => name}) do
    with true <- AuthoringInput.text?(name, 512) and String.trim(name) != "",
         {:ok, current} <- open(scope, mission, dashboard),
         {:ok, base} <- base(current, base_version),
         {:ok, document, _details} <- replay(base, commands) do
      document
      |> DocumentCodec.copy_for_scope(scope.organization_id, mission,
        name: String.trim(name),
        description: document.description,
        source: "dashboard_clone",
        source_dashboard_id: dashboard,
        actor_id: scope.user.user_id
      )
      |> then(&CurrentVersions.create(scope.organization_id, &1, created_by: scope.user.user_id))
      |> normalize()
    else
      false -> {:error, :invalid_input}
      error -> error
    end
  rescue
    _exception -> {:error, :unknown}
  end

  def copy(_scope, _mission, _dashboard, _base_version, _commands, _attrs),
    do: {:error, :invalid_input}

  @doc """
  The dashboard's versions, newest first: `%{version, kind, based_on_version, created_by:
  %{id, name}, created_at, change_summary, current}`.
  """
  def versions(scope, mission, dashboard) do
    with {:ok, current} <- open(scope, mission, dashboard) do
      rows = DocumentStore.list_versions(scope.organization_id, mission, dashboard)
      first = rows |> Enum.map(& &1.version) |> Enum.min(fn -> nil end)
      names = names(rows)
      reverted = reverted(scope.organization_id, mission, dashboard)
      current_version = Document.version(current)

      {:ok,
       rows
       |> Enum.map(&version_row(&1, first, names, reverted, current_version))
       |> Enum.sort_by(& &1.version, :desc)}
    end
  rescue
    _exception -> {:error, :unknown}
  end

  @doc "Restores `version` as a new current version, observed at `expected_version`."
  def restore(scope, mission, dashboard, version, expected_version)
      when is_integer(version) and is_integer(expected_version) do
    with {:ok, _current} <- open(scope, mission, dashboard) do
      scope.organization_id
      |> CurrentVersions.restore(mission, dashboard, version,
        expected_version: expected_version,
        created_by: scope.user.user_id
      )
      |> restored()
    end
  rescue
    _exception -> {:error, :unknown}
  end

  def restore(_scope, _mission, _dashboard, _version, _expected), do: {:error, :invalid_input}

  ## Steps

  defp rebase_step({{event, payload}, index}, {doc, applied, skipped}) do
    case AuthoringChanges.apply(doc, event, payload) do
      {:ok, next, _details} -> {next, [index | applied], skipped}
      error -> {doc, applied, [%{index: index, event: event, code: code(error)} | skipped]}
    end
  end

  defp restored({:ok, %Version{document: document}}), do: {:ok, document}
  defp restored(error), do: normalize(error)

  defp open(scope, mission, dashboard) do
    with :ok <- Authoring.authorize(scope, mission),
         true <- AuthoringInput.id?(dashboard) || {:error, :invalid_input},
         {:ok, document} <-
           Documents.fetch_for_mode(scope.organization_id, mission, dashboard, :edit),
         true <-
           (document.organization_id == scope.organization_id and document.mission_id == mission and
              document.dashboard_id == dashboard) || {:error, :not_found} do
      {:ok, document}
    else
      {:error, reason} when reason in [:forbidden, :invalid_input, :not_found] -> {:error, reason}
      {:error, :dashboard_not_found} -> {:error, :not_found}
      error -> normalize(error)
    end
  end

  defp base(current, version) when is_integer(version) do
    if Document.version(current) == version do
      {:ok, current}
    else
      case DocumentStore.fetch_version(
             current.organization_id,
             current.mission_id,
             current.dashboard_id,
             version
           ) do
        {:ok, %Version{document: document}} -> {:ok, document}
        {:error, _missing} -> {:error, :not_found}
      end
    end
  end

  defp base(_current, _version), do: {:error, :invalid_input}

  defp current?(current, base_version) when is_integer(base_version) do
    if Document.version(current) == base_version,
      do: :ok,
      else: {:error, {:conflict, Document.version(current)}}
  end

  defp current?(_current, _base_version), do: {:error, :invalid_input}

  # Each command goes through the draft's admission (with the base as its observed version)
  # and changes; the first failure is reported by index.
  defp replay(document, commands) do
    with {:ok, admitted} <- admit_all(commands),
         {:ok, doc, details} <-
           admitted
           |> Enum.with_index()
           |> Enum.reduce_while({:ok, document, []}, &replay_step/2) do
      {:ok, doc, Enum.reverse(details)}
    end
  end

  defp replay_step({{event, payload}, index}, {:ok, doc, details}) do
    case AuthoringChanges.apply(doc, event, payload) do
      {:ok, next, detail} -> {:cont, {:ok, next, [detail | details]}}
      error -> {:halt, {:error, {:command, index, code(error), field(error)}}}
    end
  end

  defp admit_all(commands) when is_list(commands) and length(commands) > @max_commands,
    do: {:error, :too_many_commands}

  defp admit_all(commands) when is_list(commands) do
    commands
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {command, index}, {:ok, acc} ->
      case admit(command) do
        {:ok, admitted} -> {:cont, {:ok, [admitted | acc]}}
        :error -> {:halt, {:error, {:command, index, :invalid_input, nil}}}
      end
    end)
    |> case do
      {:ok, admitted} -> {:ok, Enum.reverse(admitted)}
      error -> error
    end
  end

  defp admit_all(_commands), do: {:error, :invalid_input}

  # The version check is the call's (`base_version`), so each command is admitted at version 1.
  # A new section or widget must carry its client-chosen id, so every replay gives the same ids.
  defp admit(%{"event" => "add_section", "input" => input})
       when not is_map_key(input, "section_id"),
       do: :error

  defp admit(%{"event" => "add_widget", "input" => input})
       when not is_map_key(input, "placement_id"),
       do: :error

  defp admit(%{"event" => event, "input" => input} = command)
       when map_size(command) == 2 and is_binary(event) and is_map(input) do
    case AuthoringInput.admit(event, Map.put(input, "expected_version", 1)) do
      {:ok, _version, payload} -> {:ok, {event, payload}}
      _invalid -> :error
    end
  end

  defp admit(_command), do: :error

  defp persist(scope, current, document, summary) do
    if document == current do
      {:ok, %{document: current, version: Document.version(current), changed: false}}
    else
      CurrentVersions.save(
        current.organization_id,
        current.mission_id,
        current.dashboard_id,
        document,
        expected_version: Document.version(current),
        created_by: scope.user.user_id,
        change_summary: summary || describe(VersionDiff.changes(current, document))
      )
      |> case do
        {:ok, saved} -> {:ok, %{document: saved, version: Document.version(saved), changed: true}}
        {:error, {:dashboard_version_conflict, _}} -> conflict(current)
        error -> normalize(error)
      end
    end
  end

  defp conflict(current) do
    case Documents.fetch_for_mode(
           current.organization_id,
           current.mission_id,
           current.dashboard_id,
           :edit
         ) do
      {:ok, latest} -> {:error, {:conflict, Document.version(latest)}}
      _missing -> {:error, :not_found}
    end
  end

  # Like the draft's save: without a note, what changed in words.
  defp describe([]), do: "Saved without changes"
  defp describe([%{label: label}]), do: label
  defp describe([%{label: label} | rest]), do: "#{label} and #{length(rest)} more"

  defp message(nil), do: {:ok, nil}

  defp message(message) when is_binary(message) do
    trimmed = String.trim(message)

    cond do
      byte_size(trimmed) > 1_000 or not String.valid?(trimmed) -> {:error, :invalid_input}
      trimmed == "" -> {:ok, nil}
      true -> {:ok, trimmed}
    end
  end

  defp message(_message), do: {:error, :invalid_input}

  defp changes(commands), do: Enum.frequencies_by(commands, & &1["event"])

  defp code(error) do
    case AuthoringErrors.normalize(error) do
      {:error, code} -> code
    end
  end

  defp field({:error, {_code, field}}) when is_binary(field) or is_atom(field), do: field
  defp field(_error), do: nil

  defp normalize({:error, :dashboard_not_found}), do: {:error, :not_found}

  # Retired between the command's check and the save (Q10): the placement's field error.
  defp normalize({:error, {:library_item_retired, _item}}),
    do: {:error, {:command, nil, :library_item_unavailable, "library_item_id"}}

  # A save is a publish, so a readiness failure names what to fix (api D9: the editor marks
  # failing placements).
  defp normalize({:error, {:invalid_dashboard_document, %ValidationResult{errors: errors}}}),
    do: {:error, {:not_ready, PublishReadinessPresentation.editor_issues(errors)}}

  defp normalize({:error, {:dashboard_version_conflict, _}}), do: {:error, :conflict}
  defp normalize({:ok, _} = ok), do: ok

  defp normalize(error) do
    case AuthoringErrors.normalize(error) do
      {:error, :unavailable} -> {:error, :not_found}
      normalized -> normalized
    end
  end

  ## Versions

  # The first version is "create"; a revert names the version it restored. Every version is
  # published at once (CurrentVersions), which overwrites snapshot_kind with :publish, so a revert
  # is known from its lifecycle event.
  defp version_row(%Version{} = row, first, names, reverted, current) do
    %{
      version: row.version,
      kind: kind(row, first, reverted),
      based_on_version: row.based_on_version,
      created_by: row.created_by && %{id: row.created_by, name: Map.get(names, row.created_by)},
      created_at: row.inserted_at,
      change_summary: row.change_summary,
      current: row.version == current
    }
  end

  defp kind(%Version{version: version}, version, _reverted), do: "create"
  defp kind(%Version{snapshot_kind: :migration}, _first, _reverted), do: "migration"

  defp kind(%Version{} = row, _first, reverted),
    do:
      if(row.snapshot_kind == :revert or MapSet.member?(reverted, row.version),
        do: "revert",
        else: "save"
      )

  defp reverted(organization_id, mission, dashboard) do
    for event <- DocumentStore.list_lifecycle_events(organization_id, mission, dashboard),
        to_string(event.event_type) == "reverted",
        version = (event.payload || %{})["reverted_version"],
        is_integer(version),
        into: MapSet.new(),
        do: version
  end

  defp names(rows) do
    rows
    |> Enum.map(& &1.created_by)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Map.new(fn id ->
      case Accounts.fetch_user(id) do
        {:ok, user} -> {id, user.display_name || user.email}
        _not_a_user -> {id, nil}
      end
    end)
  end
end
