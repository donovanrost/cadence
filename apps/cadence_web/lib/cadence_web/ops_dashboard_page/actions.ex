defmodule CadenceWeb.OpsDashboardPage.Actions do
  @moduledoc """
  Effects and queries of the Ops dashboard page.

  Saving follows Grafana: a save creates a version that is immediately current
  (`Cadence.Dashboards.CurrentVersions`), with an optional message and an
  opt-in to keep the viewer's time range or spacecraft as the new defaults.
  After someone else saves, `rebase` replays the author's staged edits onto
  their version. Effects consume the page's action sequence; queries do not.
  """
  alias Cadence.Dashboards.{
    Authoring,
    AuthoringDefaults,
    AuthoringDraft,
    CurrentVersions,
    DocumentCodec
  }

  alias Cadence.Reads.Dashboards.{ObservableChoices, Versions}

  @stage_events ~w(rename add_section update_section remove_section move_section add_widget update_widget remove_widget layout runtime_defaults)
  @effects @stage_events ++ ~w(save discard rebase save_as_copy restore)
  @queries ~w(search_observables versions compare compare_staged)
  @invalid ~w(invalid_input invalid_defaults missing_section missing_placement unsupported_widget invalid_widget invalid_type invalid_title invalid_options invalid_binding invalid_document capacity)a

  def events, do: @effects ++ @queries
  def query?(event), do: event in @queries

  ## Queries

  def query(scope, %{mode: :edit, draft: %AuthoringDraft{} = draft}, "search_observables", input) do
    case ObservableChoices.staged(scope, draft, input) do
      {:ok, choices} -> %{status: "ok", choices: choices}
      _ -> %{status: "unavailable"}
    end
  end

  def query(scope, session, "versions", input) when input == %{} do
    {_, _, mission, dashboard, _} = session.identity

    case Versions.list(scope, mission, dashboard) do
      {:ok, versions} -> %{status: "ok", versions: versions}
      _ -> %{status: "unavailable"}
    end
  end

  def query(scope, session, "compare", %{"from" => from, "to" => to} = input)
      when map_size(input) == 2 do
    {_, _, mission, dashboard, _} = session.identity

    case Versions.compare(scope, mission, dashboard, from, to) do
      {:ok, comparison} -> %{status: "ok", comparison: comparison}
      _ -> %{status: "unavailable"}
    end
  end

  def query(scope, %{mode: :edit, draft: %AuthoringDraft{} = draft}, "compare_staged", input)
      when input == %{} do
    case AuthoringDraft.current(scope, draft) do
      {:ok, document} -> %{status: "ok", comparison: Versions.staged(draft.baseline, document)}
      _ -> %{status: "unavailable"}
    end
  end

  def query(_scope, _session, _event, _input), do: %{status: "unavailable"}

  ## Effects: {status, code, session, result}

  def effect(scope, %{mode: :edit, draft: %AuthoringDraft{} = draft} = session, event, command)
      when event in @stage_events do
    AuthoringDraft.stage(scope, draft, event, command) |> applied(session)
  end

  def effect(scope, %{mode: :edit, draft: %AuthoringDraft{}} = session, "save", command) do
    {options, control} = Map.split(command, ["defaults"])

    case stage_defaults(scope, session, Map.get(options, "defaults"), control) do
      {:ok, session, control} ->
        AuthoringDraft.save(scope, session.draft, control) |> applied(session)

      {:error, code} ->
        applied({:error, code}, session)
    end
  end

  def effect(
        scope,
        %{mode: :edit, draft: %AuthoringDraft{} = draft} = session,
        "discard",
        command
      ) do
    # Discarding after someone else saved adopts their version instead of failing.
    case AuthoringDraft.discard(scope, draft, command) do
      {:error, :conflict} -> {"ok", nil, reopen(scope, session), nil}
      result -> applied(result, session)
    end
  end

  def effect(scope, %{mode: :edit, draft: %AuthoringDraft{} = draft} = session, "rebase", command)
      when command == %{} do
    case AuthoringDraft.rebase(scope, draft) do
      {:ok, draft, details} -> {"ok", nil, %{session | draft: draft}, %{skipped: details.skipped}}
      error -> applied(error, session)
    end
  end

  def effect(scope, %{mode: :edit, draft: %AuthoringDraft{} = draft} = session, "save_as_copy", %{
        "name" => name
      })
      when is_binary(name) do
    {org, user, mission, dashboard, _} = session.identity
    name = String.trim(name)

    with true <- name != "" and byte_size(name) <= 512,
         :ok <- Authoring.authorize(scope, mission),
         {:ok, document} <- AuthoringDraft.current(scope, draft),
         copy =
           DocumentCodec.copy_for_scope(document, org, mission,
             name: name,
             description: document.description,
             source: "dashboard_copy",
             source_dashboard_id: dashboard,
             actor_id: user
           ),
         {:ok, created} <- CurrentVersions.create(org, copy, created_by: user) do
      {"ok", nil, session, %{dashboard_id: created.dashboard_id}}
    else
      false -> {"invalid", "invalid_title", session, nil}
      _ -> {"unknown", nil, session, nil}
    end
  end

  def effect(scope, session, "restore", %{"version" => version, "expected_version" => current})
      when is_integer(version) and is_integer(current) and version > 0 do
    {_, user, mission, dashboard, _} = session.identity

    with :ok <- Authoring.authorize(scope, mission),
         {:ok, restored} <-
           CurrentVersions.restore(scope.organization_id, mission, dashboard, version,
             expected_version: current,
             created_by: user
           ) do
      {"ok", nil, reopen(scope, session), %{version: restored.version}}
    else
      {:error, {:dashboard_version_conflict, _}} -> {"conflict", nil, session, nil}
      {:error, {:invalid_dashboard_document, _}} -> {"invalid", "invalid_document", session, nil}
      _ -> {"unknown", nil, session, nil}
    end
  end

  def effect(_scope, session, _event, _command), do: {"rejected", nil, session, nil}

  # Opted-in viewer context becomes the dashboard's runtime defaults in the same
  # save. Staging checks the client's observed revision; the save then observes
  # the revision that staging produced.
  defp stage_defaults(_scope, session, nil, control), do: {:ok, session, control}

  defp stage_defaults(scope, %{runtime: {:ok, runtime}, draft: draft} = session, flags, control)
       when is_map(flags) do
    with {:ok, json} <- AuthoringDefaults.encode(draft.document.defaults),
         {:ok, defaults} <- Jason.decode(json),
         defaults = defaults_from(defaults, runtime, flags),
         {:ok, encoded} <- AuthoringDefaults.encode(defaults),
         {:ok, staged, _} <-
           AuthoringDraft.stage(scope, draft, "runtime_defaults", %{
             "defaults_json" => encoded,
             "expected_version" => control["expected_version"],
             "expected_revision" => control["expected_revision"]
           }) do
      {:ok, %{session | draft: staged}, Map.put(control, "expected_revision", staged.revision)}
    else
      {:error, code} -> {:error, code}
      _ -> {:error, :invalid_defaults}
    end
  end

  defp stage_defaults(_scope, _session, _flags, _control), do: {:error, :invalid_input}

  defp defaults_from(defaults, runtime, flags) do
    defaults
    |> then(&if(flags["time"] == true, do: put_time(&1, runtime.time_context), else: &1))
    |> then(&if(flags["scope"] == true, do: put_scope(&1, runtime.scope_context), else: &1))
  end

  defp put_time(defaults, time) do
    kept = Map.take(Map.get(defaults, "time") || %{}, ["axis"])

    selected =
      case time do
        %{mode: "live", window_seconds: seconds} ->
          %{"mode" => "live", "window_seconds" => seconds}

        %{mode: mode, from: from, to: to} ->
          %{"mode" => mode, "from" => iso(from), "to" => iso(to)}

        _ ->
          %{"mode" => "live"}
      end

    Map.put(defaults, "time", Map.merge(kept, selected))
  end

  defp put_scope(defaults, %{spacecraft_id: id}) when is_binary(id),
    do:
      Map.put(defaults, "scope", %{
        "primary" => %{"kind" => "spacecraft", "mode" => "one", "ids" => [id]},
        "spacecraft_id" => id
      })

  defp put_scope(defaults, _scope), do: Map.delete(defaults, "scope")

  defp iso(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp applied({:ok, draft, _details}, session), do: {"ok", nil, %{session | draft: draft}, nil}
  defp applied({:ok, draft}, session), do: {"ok", nil, %{session | draft: draft}, nil}

  defp applied({:error, code}, session) when code in @invalid,
    do: {"invalid", Atom.to_string(code), session, nil}

  defp applied({:error, :conflict}, session), do: {"conflict", nil, session, nil}
  defp applied(_, session), do: {"unknown", nil, session, nil}

  @doc "Opens the author's staging transaction for the edit route."
  def open(scope, session) do
    {_, _, mission, dashboard, _} = session.identity

    case AuthoringDraft.open(scope, mission, dashboard) do
      {:ok, draft} -> %{session | draft: draft}
      _ -> session
    end
  end

  # A new current version moves the saved baseline; a held draft must observe it.
  defp reopen(scope, %{mode: :edit} = session), do: open(scope, %{session | draft: nil})
  defp reopen(_scope, session), do: session
end
