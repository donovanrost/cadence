defmodule Cadence.Dashboards.Creation do
  @moduledoc "Scoped blank, clone and import creation independent of frontend delivery."
  require Logger

  alias Cadence.Auth.{Policy, Scope}

  alias Cadence.Dashboards.{
    AuthoringDefaults,
    CurrentVersions,
    Document,
    DocumentCodec,
    DocumentDiff,
    Documents
  }

  alias Cadence.{Missions, SpacecraftStore}

  def authorize(
        %Scope{organization_id: org, mission_id: scoped, user: %{user_id: user}} = scope,
        mission
      )
      when is_binary(org) and org != "" and is_binary(mission) and mission != "" and
             is_binary(user) and user != "" and (is_nil(scoped) or scoped == mission) do
    with :ok <-
           Policy.authorize(scope, :author_dashboards, %{
             organization_id: org,
             mission_id: mission
           }),
         {:ok, _} <- Missions.fetch_mission(org, mission),
         do: :ok
  end

  def authorize(_, _), do: {:error, :forbidden}

  @doc """
  Creates a dashboard: blank (`mode: "new"`), cloned, or imported from a document (`"import"`).

  An import takes `identity`: `"copy"` (the default) makes a new dashboard with a new id, named
  `name` (else "Copy of ..."); `"keep"` keeps the document's own `dashboard_id`, so provisioning
  can re-run: the same id with an identical document is `{:ok, %{existing?: true}}` and changes
  nothing, the same id with a different document is `{:invalid, {:conflict, summary}}`, and an id
  another mission (`{:invalid, {:id_in_use, mission_id}}`, in the same organization only) or
  organization (`{:invalid, :id_in_use}`, naming nothing) already holds is refused. A dashboard id
  is unique across all of them, since it is the table's primary key.
  """
  def create(scope, mission, model, input) do
    with :ok <- authorize(scope, mission),
         {:ok, fields} <- fields(input, model.mode),
         {:ok, document} <- document(scope, mission, model, fields) do
      case CurrentVersions.create(scope.organization_id, document, created_by: scope.user.user_id) do
        {:ok, saved} ->
          {:ok,
           %{dashboard_id: saved.dashboard_id, version: Document.version(saved), mode: model.mode}}

        # Creating publishes the first version: a readiness failure says what to fix.
        {:error, {:invalid_dashboard_document, _result}} = not_ready ->
          not_ready

        error ->
          Logger.warning("dashboard creation failed: #{inspect(error, limit: 20)}")
          {:error, :unknown}
      end
    else
      # An import that keeps its id met the identical dashboard already there: nothing to do.
      {:existing, %Document{} = existing} ->
        {:ok,
         %{
           dashboard_id: existing.dashboard_id,
           version: Document.version(existing),
           mode: model.mode,
           existing?: true
         }}

      other ->
        other
    end
  rescue
    _ -> {:error, :unknown}
  catch
    _, _ -> {:error, :unknown}
  end

  # An import: the document, and whether it keeps its id; `name` and `description` only rename a
  # copy (a kept id keeps the document as it is, or it would not be the same document).
  defp fields(input, "import") when is_map(input) do
    with true <- text?(input["document_json"], 262_144) or {:field, "document"},
         {:ok, identity} <- identity(Map.get(input, "identity", "copy")),
         :ok <- import_keys(input, identity),
         {:ok, name} <- optional_text(input, "name", 512),
         {:ok, description} <- optional_text(input, "description", 4096) do
      {:ok,
       %{
         name: name,
         description: description,
         json: input["document_json"],
         identity: identity,
         tags: [],
         spacecraft_id: nil
       }}
    else
      {:field, field} -> {:invalid, {:field, field}}
    end
  end

  # A new (blank) dashboard may also carry `tags` and a `spacecraft` default (console D4); the
  # other modes take exactly their keys.
  defp fields(input, mode) when is_map(input) and map_size(input) <= 5 do
    keys = if mode == "import", do: ~w(name description document_json), else: ~w(name description)
    optional = if mode == "new", do: ~w(tags spacecraft), else: []

    with true <- Enum.sort(Map.keys(input) -- optional) == Enum.sort(keys),
         true <- text?(input["name"], 512) and String.trim(input["name"]) != "",
         true <- text?(input["description"], 4096),
         true <- mode != "import" or text?(input["document_json"], 262_144),
         {:ok, tags} <- tags(Map.get(input, "tags", [])),
         {:ok, spacecraft} <- spacecraft(Map.get(input, "spacecraft")) do
      {:ok,
       %{
         name: String.trim(input["name"]),
         description: String.trim(input["description"]),
         json: input["document_json"],
         tags: tags,
         spacecraft_id: spacecraft
       }}
    else
      _ -> {:invalid, :fields}
    end
  end

  defp fields(_, _), do: {:invalid, :fields}

  defp identity(value) when value in ["copy", "keep"], do: {:ok, String.to_existing_atom(value)}
  defp identity(_other), do: {:field, "identity"}

  defp import_keys(input, :copy),
    do:
      if(Map.keys(input) -- ~w(name description document_json identity) == [],
        do: :ok,
        else: {:field, "document"}
      )

  defp import_keys(input, :keep),
    do: if(Map.keys(input) -- ~w(document_json identity) == [], do: :ok, else: {:field, "name"})

  defp optional_text(input, key, max) do
    case Map.get(input, key) do
      nil ->
        {:ok, nil}

      value ->
        if text?(value, max) and String.trim(value) != "",
          do: {:ok, String.trim(value)},
          else: {:field, key}
    end
  end

  defp tags(tags) when is_list(tags) and length(tags) <= 10 do
    trimmed = tags |> Enum.filter(&text?(&1, 64)) |> Enum.map(&String.trim/1)

    if length(trimmed) == length(tags) and "" not in trimmed,
      do: {:ok, Enum.uniq(trimmed)},
      else: :error
  end

  defp tags(_tags), do: :error

  # `fixed` sets the document's default scope to that spacecraft; `context` and `fleet` (the
  # viewer picks, or constellation-wide widgets) set none.
  defp spacecraft(nil), do: {:ok, nil}

  defp spacecraft(%{"mode" => mode} = input)
       when mode in ~w(context fleet) and map_size(input) == 1,
       do: {:ok, nil}

  defp spacecraft(%{"mode" => "fixed", "spacecraft_id" => id} = input)
       when map_size(input) == 2 and is_binary(id) and byte_size(id) in 1..256,
       do: {:ok, id}

  defp spacecraft(_input), do: :error

  defp text?(value, max),
    do: is_binary(value) and byte_size(value) <= max and String.valid?(value)

  defp document(scope, mission, %{mode: "new"}, fields) do
    with {:ok, defaults} <- defaults(scope, mission, fields.spacecraft_id) do
      {:ok, blank(scope, mission, fields, defaults)}
    end
  end

  defp document(scope, mission, %{mode: "clone", source: source}, fields) do
    case Documents.fetch_for_mode(scope.organization_id, mission, source.id, :edit) do
      {:ok, document} ->
        if Document.version(document) == source.version,
          do: {:ok, copy(document, scope, mission, fields, "dashboard_clone")},
          else: {:invalid, :source_changed}

      _ ->
        {:invalid, :source_changed}
    end
  end

  defp document(scope, mission, %{mode: "import"}, %{identity: :copy} = fields) do
    case decode(fields.json) do
      {:ok, document} ->
        named = %{
          fields
          | name: fields.name || "Copy of " <> document.name,
            description: fields.description || document.description || ""
        }

        {:ok, copy(document, scope, mission, named, "dashboard_import")}

      _ ->
        {:invalid, :document}
    end
  end

  defp document(scope, mission, %{mode: "import"}, %{identity: :keep} = fields) do
    case decode(fields.json) do
      {:ok, document} -> keep(document, scope, mission)
      _ -> {:invalid, :document}
    end
  end

  defp document(_, _, _, _), do: {:invalid, :fields}

  # A document that does not decode (not a dashboard, a failed bundle check, a shape the migration
  # cannot read) is the caller's mistake, never a server error.
  defp decode(json) do
    DocumentCodec.decode_import(json)
  rescue
    _ -> {:error, :invalid_document}
  end

  # The document as it will be saved here: this mission's, with its own id and no version (an
  # import is the dashboard's first saved version). Then what the id already means.
  # A kept id has to be one the document names.
  defp keep(%Document{dashboard_id: id}, _scope, _mission) when not is_binary(id) or id == "",
    do: {:invalid, :document}

  defp keep(%Document{} = document, scope, mission) do
    metadata =
      Map.drop(document.metadata || %{}, [
        :version,
        "version",
        :dashboard_version,
        "dashboard_version"
      ])

    incoming = %Document{
      document
      | organization_id: scope.organization_id,
        mission_id: mission,
        metadata: metadata
    }

    organization_id = scope.organization_id

    case Documents.dashboard_owner(incoming.dashboard_id) do
      :error ->
        {:ok, incoming}

      {:ok, %{organization_id: ^organization_id, mission_id: ^mission}} ->
        same_or_conflict(incoming, scope, mission)

      # Another mission of this organization: it may be named. Another organization: nothing is.
      {:ok, %{organization_id: ^organization_id, mission_id: other}} ->
        {:invalid, {:id_in_use, other}}

      {:ok, _another_organization} ->
        {:invalid, :id_in_use}
    end
  end

  defp same_or_conflict(%Document{} = incoming, scope, mission) do
    case Documents.fetch_for_mode(scope.organization_id, mission, incoming.dashboard_id, :edit) do
      {:ok, %Document{} = existing} ->
        wanted = DocumentDiff.comparable(incoming)
        found = DocumentDiff.comparable(existing)

        if wanted == found,
          do: {:existing, existing},
          else: {:invalid, {:conflict, DocumentDiff.summary(found, wanted)}}

      # Archived (or unreadable): the id is taken, and it is not this document's to replace.
      _unavailable ->
        {:invalid, :id_in_use}
    end
  end

  defp defaults(_scope, _mission, nil), do: {:ok, %{}}

  # The same scope OpsWorkspaceURL admits for one spacecraft; it must be this mission's.
  defp defaults(scope, mission, spacecraft_id) do
    owned? =
      match?(
        {:ok, _},
        SpacecraftStore.fetch_spacecraft(scope.organization_id, mission, spacecraft_id)
      )

    defaults = %{
      "scope" => %{
        "primary" => %{"kind" => "spacecraft", "mode" => "one", "ids" => [spacecraft_id]},
        "spacecraft_id" => spacecraft_id
      }
    }

    if owned? and AuthoringDefaults.validate(defaults) == :ok,
      do: {:ok, defaults},
      else: {:invalid, :spacecraft}
  end

  defp blank(scope, mission, fields, defaults) do
    %Document{
      dashboard_id: Cadence.Ids.new("ops_dashboard"),
      organization_id: scope.organization_id,
      mission_id: mission,
      name: fields.name,
      description: fields.description,
      defaults: defaults,
      metadata:
        %{"source" => "dashboard_creation", "created_by" => scope.user.user_id}
        |> put_tags(fields.tags)
    }
  end

  defp put_tags(metadata, []), do: metadata
  defp put_tags(metadata, tags), do: Map.put(metadata, "tags", tags)

  defp copy(document, scope, mission, fields, source) do
    DocumentCodec.copy_for_scope(document, scope.organization_id, mission,
      name: fields.name,
      description: fields.description,
      source: source,
      source_dashboard_id: document.dashboard_id,
      actor_id: scope.user.user_id
    )
  end
end
