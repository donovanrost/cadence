defmodule Cadence.Management.Commanding.StageCatalog do
  @moduledoc "Authorized, paged stage discovery and model-independent draft inspection."
  import Ecto.Query
  alias Cadence.Commanding.{RequestValidation, StagedCommandItemRow}
  alias Cadence.Management.Commanding.{StageAccess, StageInput}
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo
  alias Cadence.SourceEndpoints

  @item_fields ~w(staged_command_item_id command_stage_id organization_id mission_id source_endpoint_ref mission_model_revision_id command_id priority not_before expires_at item_order lifecycle_state submitted_command_request_id inserted_at updated_at)a

  def directory(scope, mission_id, params) do
    with {:ok, fresh, mission} <- StageAccess.authorize(scope, mission_id),
         {:ok, query} <- StageInput.directory(params) do
      rows =
        fresh
        |> StageAccess.visible_query(mission_id)
        |> where([row], row.command_stage_id > ^query.after)
        |> filter_state(query.state)
        |> filter_name(query.query)
        |> order_by([row], asc: row.command_stage_id)
        |> limit(26)
        |> select([row], %{
          id: row.command_stage_id,
          name: row.stage_name,
          visibility: row.visibility,
          state: row.lifecycle_state,
          owner_id: fragment("? #>> '{value,user_id}'", row.owner_document)
        })
        |> Repo.all()

      entries = Enum.take(rows, 25)

      bounded(
        Map.merge(context(fresh, mission), %{
          "query" => string_keys(query),
          "stages" => %{
            "limit" => 25,
            "entries" => Enum.map(entries, &string_keys/1),
            "next_after" => if(length(rows) > 25, do: List.last(entries).id, else: nil)
          }
        })
      )
    end
  end

  def workbench(scope, mission_id, stage_id, params) do
    with {:ok, query} <- StageInput.workbench(params) do
      StageAccess.with_stage(scope, mission_id, stage_id, :read, fn fresh, mission, stage ->
        page = items_page(stage, query)
        selected = selected_item(stage, query.item)
        target_ids = Enum.map(page["entries"] ++ List.wrap(selected), & &1["target_id"])
        names = SourceEndpoints.display_names(fresh.organization_id, mission_id, target_ids)
        named_item = &Map.put(&1, "target_name", names[&1["target_id"]])

        bounded(
          Map.merge(context(fresh, mission), %{
            "version" => 2,
            "stage" => stage_document(stage, fresh),
            "query" =>
              Map.put(
                string_keys(query),
                "after_order",
                if(is_nil(query.after_order), do: "", else: to_string(query.after_order))
              ),
            "items" => Map.update!(page, "entries", &Enum.map(&1, named_item)),
            "selected_item" => if(selected, do: named_item.(selected))
          })
        )
      end)
    end
  end

  def stage_token(stage) do
    stage
    |> Map.from_struct()
    |> Map.delete(:__meta__)
    |> RequestValidation.authoring_digest()
  end

  # Digest the exact stored row in PostgreSQL, so even private metadata changes
  # invalidate a retained selection without sending that metadata to the browser.
  # Size predicates bound materialization, not physical PostgreSQL document IO.
  def item_query(stage) do
    from(row in StagedCommandItemRow,
      where:
        row.organization_id == ^stage.organization_id and row.mission_id == ^stage.mission_id and
          row.command_stage_id == ^stage.command_stage_id,
      select: map(row, ^@item_fields),
      select_merge: %{
        token: fragment("encode(sha256(convert_to(to_jsonb(?)::text, 'UTF8')), 'hex')", row),
        notes:
          fragment("CASE WHEN octet_length(?) <= 4000 THEN ? ELSE NULL END", row.notes, row.notes),
        notes_available: is_nil(row.notes) or fragment("octet_length(?) <= 4000", row.notes),
        argument_values_document:
          fragment(
            "CASE WHEN octet_length(?::text) <= 32768 THEN ? ELSE NULL END",
            row.argument_values_document,
            row.argument_values_document
          )
      }
    )
  end

  defp items_page(stage, query) do
    rows =
      stage
      |> item_query()
      |> filter_state(query.state)
      |> after_item(query)
      |> order_by([row], asc: row.item_order, asc: row.staged_command_item_id)
      |> limit(26)
      |> Repo.all()

    entries = Enum.take(rows, 25)
    last = List.last(entries)

    %{
      "limit" => 25,
      "entries" => Enum.map(entries, &item_document(&1, false)),
      "next_after" =>
        if(length(rows) > 25,
          do: %{"id" => last.staged_command_item_id, "order" => last.item_order},
          else: nil
        )
    }
  end

  defp after_item(query, %{after: ""}), do: query

  defp after_item(query, cursor) do
    where(
      query,
      [row],
      row.item_order > ^cursor.after_order or
        (row.item_order == ^cursor.after_order and row.staged_command_item_id > ^cursor.after)
    )
  end

  defp selected_item(_, ""), do: nil

  defp selected_item(stage, id) do
    case stage
         |> item_query()
         |> where([row], row.staged_command_item_id == ^id)
         |> Repo.one() do
      nil -> nil
      row -> item_document(row, true)
    end
  end

  defp item_document(row, selected?) do
    available = row.notes_available and is_map(row.argument_values_document)

    %{
      "id" => row.staged_command_item_id,
      "expected_item" => row.token,
      "command_id" => row.command_id,
      "revision_id" => row.mission_model_revision_id,
      "target_id" => row.source_endpoint_ref,
      "order" => row.item_order,
      "state" => row.lifecycle_state,
      "priority" => row.priority,
      "not_before" => time(row.not_before),
      "expires_at" => time(row.expires_at),
      "request_id" => row.submitted_command_request_id,
      "notes" => row.notes,
      "available" => available,
      "argument_values_json" =>
        if(selected? and available,
          do: Jason.encode!(JsonDocument.unwrap_value(row.argument_values_document)),
          else: nil
        )
    }
  end

  defp stage_document(stage, fresh) do
    editable = stage.lifecycle_state in ~w(draft in_review ready_to_submit)

    %{
      "id" => stage.command_stage_id,
      "expected_stage" => stage_token(stage),
      "name" => stage.stage_name,
      "description" => stage.description,
      "visibility" => stage.visibility,
      "state" => stage.lifecycle_state,
      "owner_id" => get_in(stage.owner_document, ["value", "user_id"]),
      "can_edit_items" => editable,
      "can_edit_stage" => editable and StageAccess.owner?(stage, fresh)
    }
  end

  defp filter_state(query, ""), do: query
  defp filter_state(query, state), do: where(query, [row], row.lifecycle_state == ^state)
  defp filter_name(query, ""), do: query

  defp filter_name(query, value) do
    escaped =
      value
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    where(query, [row], ilike(row.stage_name, ^("%" <> escaped <> "%")))
  end

  defp context(fresh, mission),
    do: %{
      "version" => 1,
      "context" => %{"organizationId" => fresh.organization_id, "missionId" => mission.mission_id},
      "mission_name" => mission.display_name,
      "actor_id" => fresh.user.user_id,
      "observed_at" => time(DateTime.utc_now())
    }

  defp bounded(document) do
    case Jason.encode(document) do
      {:ok, bytes} when byte_size(bytes) <= 262_144 -> {:ok, document}
      _ -> {:error, :command_stage_unavailable}
    end
  end

  defp string_keys(map), do: Map.new(map, fn {key, value} -> {Atom.to_string(key), value} end)
  defp time(nil), do: nil
  defp time(value), do: DateTime.to_iso8601(value)
end
