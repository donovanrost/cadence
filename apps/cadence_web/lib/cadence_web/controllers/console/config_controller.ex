defmodule CadenceWeb.Console.ConfigController do
  @moduledoc """
  Mission change sets and configuration revisions under
  `/api/v1/missions/:mission_id/config`: a thin pass-through of
  `Cadence.Control.Configuration`. Contract: docs/apogee/api/changes.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Configuration.Kinds

  alias Cadence.Control.{
    Activations,
    Configuration,
    ConfigurationRollback,
    LegacyRouteConversion,
    SpacecraftOps
  }

  alias Cadence.Reads.{ChangeSetOutcome, ChangeSetViewer, ConfigKindSchema, ConfigLabels}
  alias CadenceWeb.Console.{ConfigJSON, ConfigParams, Problem}

  def show(conn, _params) do
    with {:ok, current} <- Configuration.current(scope(conn), mission_id(conn)),
         {:ok, permissions} <- Configuration.permissions(scope(conn), mission_id(conn)) do
      current = Map.update!(current, :change_set, &annotate(conn, &1))

      ok(conn, Map.put(current, :permissions, permissions))
    end
    |> reply(conn)
  end

  def change_set(conn, %{"change_set_id" => id}) do
    case Configuration.change_set(scope(conn), mission_id(conn), id) do
      {:ok, set} -> {:data, annotate(conn, set)}
      other -> other
    end
    |> reply(conn)
  end

  def stage(conn, body) do
    with {:ok, attrs, ops} <- params(ConfigParams.stage(body)),
         {:ok, ops} <-
           params(SpacecraftOps.prepare(scope(conn).organization_id, mission_id(conn), ops)),
         {:ok, result} <- Configuration.stage(scope(conn), mission_id(conn), attrs, ops) do
      conn |> put_status(:created) |> ok(result)
    end
    |> reply(conn)
  end

  def withdraw(conn, %{"change_id" => id}),
    do: Configuration.withdraw(scope(conn), mission_id(conn), id) |> wrap() |> reply(conn)

  def discard(conn, %{"change_set_id" => id} = body) do
    with {:ok, version} <- params(ConfigParams.expected_version(body)),
         {:ok, result} <- Configuration.discard(scope(conn), mission_id(conn), id, version) do
      ok(conn, result)
    end
    |> reply(conn)
  end

  def preview_set(conn, %{"change_set_id" => id}),
    do:
      Configuration.preview(scope(conn), mission_id(conn), id, outcome: ChangeSetOutcome)
      |> labelled(conn)
      |> with_active_configuration(conn)
      |> wrap()
      |> reply(conn)

  def preview_ops(conn, body) do
    with {:ok, ops} <- params(ConfigParams.ops(body)),
         {:ok, ops} <-
           params(SpacecraftOps.prepare(scope(conn).organization_id, mission_id(conn), ops)),
         {:ok, preview} <-
           Configuration.preview(scope(conn), mission_id(conn), {:ops, ops},
             outcome: ChangeSetOutcome
           )
           |> labelled(conn)
           |> with_active_configuration(conn) do
      ok(conn, preview)
    end
    |> reply(conn)
  end

  def rebase(conn, %{"op_id" => op_id} = body) do
    with {:ok, choice} <- params(ConfigParams.rebase_choice(body)),
         {:ok, result} <- Configuration.rebase(scope(conn), mission_id(conn), op_id, choice) do
      ok(conn, result)
    end
    |> reply(conn)
  end

  def submit(conn, %{"change_set_id" => id} = body) do
    with {:ok, submit} <- params(ConfigParams.submit(body)),
         {:ok, result} <- Configuration.submit(scope(conn), mission_id(conn), id, submit) do
      ok(conn, applied_with_configuration(result, conn))
    end
    |> reply(assign(conn, :submit_act, submit_act(conn, id)))
  end

  # mms-ux (for ca-ux): a submit's refusals name its act. Under 'needs a second person's approval'
  # the button is Request review, so the server-worded refusals open "Not sent for review:". The
  # act is the submit's own decision, a legacy route conversion's forced approval included
  # (fe-setup on #555), not a second read of the mission's setting.
  defp submit_act(conn, change_set_id) do
    if Configuration.needs_approval?(scope(conn), mission_id(conn), change_set_id),
      do: :request_review,
      else: :apply
  end

  def review(conn, %{"change_set_id" => id} = body) do
    with {:ok, decision, review} <- params(ConfigParams.review(body)),
         {:ok, result} <-
           Configuration.review(scope(conn), mission_id(conn), id, decision, review) do
      ok(conn, applied_with_configuration(result, conn))
    end
    |> reply(conn)
  end

  # fe-setup (Profile History): the revisions touching one entity, each with its labelled entries.
  def revisions(conn, %{"entity_kind" => kind, "entity_id" => id} = params)
      when is_binary(kind) and is_binary(id) and id != "" do
    org = scope(conn).organization_id

    with {:ok, opts} <- params(ConfigParams.list_opts(params)),
         {:ok, _module} <- params(known_kind(kind)),
         {:ok, revisions} <-
           Configuration.entity_revisions(scope(conn), mission_id(conn), kind, id, opts) do
      ok(conn, %{
        revisions: Enum.map(revisions, &ConfigLabels.revision(org, mission_id(conn), &1))
      })
    end
    |> reply(conn)
  end

  def revisions(conn, params) do
    with {:ok, opts} <- params(ConfigParams.list_opts(params)),
         {:ok, revisions} <- Configuration.list_revisions(scope(conn), mission_id(conn), opts) do
      ok(conn, %{revisions: revisions})
    end
    |> reply(conn)
  end

  defp known_kind(kind) do
    case Kinds.fetch(kind) do
      {:ok, module} -> {:ok, module}
      {:error, _unknown} -> {:error, %{entity_kind: "is not a configuration kind"}}
    end
  end

  def revision(conn, %{"revision" => number}) do
    with {:ok, n} <- params(ConfigParams.revision_number(number)),
         {:ok, revision} <- Configuration.get_revision(scope(conn), mission_id(conn), n) do
      ok(conn, ConfigLabels.revision(scope(conn).organization_id, mission_id(conn), revision))
    end
    |> reply(conn)
  end

  def compare(conn, params) do
    with {:ok, from} <- params(ConfigParams.revision_number(params["from"])),
         {:ok, to} <- params(ConfigParams.revision_number(params["to"])),
         {:ok, entries} <- Configuration.compare(scope(conn), mission_id(conn), from, to) do
      # The same display fields as a revision's entries (fe-setup).
      ok(
        conn,
        ConfigLabels.revision(scope(conn).organization_id, mission_id(conn), %{
          from: from,
          to: to,
          entries: entries
        })
      )
    end
    |> reply(conn)
  end

  def kind_schema(conn, %{"kind" => kind}) do
    case ConfigKindSchema.fields(kind, scope(conn).organization_id, mission_id(conn)) do
      {:ok, fields} ->
        json(conn, %{data: ConfigJSON.encode(%{kind: kind, fields: fields})})

      {:error, :unknown_kind} ->
        Problem.respond(conn, :invalid_params, %{
          kind: "is not an editable kind"
        })
    end
  end

  @doc "What rolling back to `to` would do (change-sets.md §8). Nothing is written."
  def rollback_preview(conn, params) do
    with {:ok, to} <- params(ConfigParams.revision_number(params["to"])),
         {:ok, result} <-
           rollback_error(ConfigurationRollback.preview(scope(conn), mission_id(conn), to)),
         {:ok, preview} <- labelled({:ok, result.preview}, conn) do
      ok(conn, %{result | preview: preview})
    end
    |> reply(conn)
  end

  @doc "Stages the rollback to `to` as a new change set (then submit / review like any set)."
  def rollback(conn, params) do
    with {:ok, to} <- params(ConfigParams.revision_number(params["to"])),
         {:ok, result} <-
           rollback_error(ConfigurationRollback.stage(scope(conn), mission_id(conn), to)) do
      ok(conn, result)
    end
    |> reply(conn)
  end

  defp rollback_error({:error, {:rollback_crosses_legacy, newest}}),
    do: {:error, {:rollback_crosses_legacy, %{newest_legacy_revision: newest}}}

  defp rollback_error({:error, {:rollback_unknown_kind, kind}}),
    do: {:error, {:rollback_unknown_kind, %{kind: kind}}}

  defp rollback_error(result), do: result

  # Names and field labels for the console's sentences (ConfigLabels).
  defp labelled({:ok, preview}, conn),
    do: {:ok, ConfigLabels.preview(scope(conn).organization_id, mission_id(conn), preview)}

  defp labelled(other, _conn), do: other

  # ux U93: whether the mission has an active configuration (an activation exists; not runtime
  # health). With none, applying saves the changes and starts nothing: a mission's first
  # generation comes from each spacecraft's configuration (domain, 11-17). On every preview, and
  # on a result that applied.
  defp with_active_configuration({:ok, preview}, conn),
    do: {:ok, Map.put(preview, :has_active_configuration, active_configuration?(conn))}

  defp with_active_configuration(other, _conn), do: other

  defp applied_with_configuration(%{state: :applied} = result, conn),
    do: Map.put(result, :has_active_configuration, active_configuration?(conn))

  defp applied_with_configuration(result, _conn), do: result

  defp active_configuration?(conn) do
    match?(
      {:ok, _activation},
      Activations.fetch_active_basis(scope(conn).organization_id, mission_id(conn))
    )
  end

  # ux U79: who may review it, and (TEMPORARY, removed with 9ac6dc8ee) whether it holds a legacy
  # route conversion batch.
  defp annotate(_conn, nil), do: nil

  defp annotate(conn, %{id: id} = set) do
    scope(conn)
    |> ChangeSetViewer.annotate(mission_id(conn), set)
    |> Map.put(:legacy_conversion, LegacyRouteConversion.change_set_batch(mission_id(conn), id))
  end

  defp ok(conn, data), do: {:sent, json(conn, %{data: ConfigJSON.encode(data)})}

  defp wrap({:ok, data}), do: {:data, data}
  defp wrap(other), do: other

  defp reply({:sent, conn}, _conn), do: conn
  defp reply({:data, data}, conn), do: json(conn, %{data: ConfigJSON.encode(data)})
  defp reply({:error, reason}, conn), do: ConfigJSON.error(conn, reason)

  defp params({:error, details}) when is_map(details), do: {:error, {:invalid_params, details}}
  defp params(ok), do: ok

  defp scope(conn), do: conn.assigns.current_scope
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
