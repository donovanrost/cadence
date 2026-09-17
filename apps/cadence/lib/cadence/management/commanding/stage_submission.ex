defmodule Cadence.Management.Commanding.StageSubmission do
  @moduledoc "Exact human-reviewed stage batches, atomic formal requests and read-only recovery."
  import Ecto.Query

  alias Cadence.Commanding.{
    CommandRequestRow,
    RequestValidation,
    StagedCommandItemRow,
    StageStore
  }

  alias Cadence.Management.Commanding.{
    AuthoringCatalog,
    RequestAuthoring,
    StageAccess,
    StageCatalog,
    StageInput
  }

  alias Cadence.Repo

  def preview(scope, mission_id, stage_id, input) do
    with {:ok, input} <- StageInput.preview_submission(input) do
      StageAccess.with_stage(scope, mission_id, stage_id, :write, fn fresh, _, stage ->
        preview_locked(scope, fresh, stage, input)
      end)
    end
  end

  # held comes only from preview/4 and is retained in the captured host session.
  def submit(scope, mission_id, stage_id, write_token, held, input) do
    with {:ok, input} <- StageInput.submit(input),
         :ok <- expected(input.expected_write, write_token),
         :ok <- expected(input.expected_preview, held.token) do
      StageAccess.with_stage(
        scope,
        mission_id,
        stage_id,
        :write,
        fn fresh, _, stage ->
          submit_locked(scope, fresh, stage, held)
        end,
        notify: true
      )
    end
  end

  defp preview_locked(scope, fresh, stage, input) do
    mission_id = stage.mission_id
    stage_id = stage.command_stage_id

    with :ok <- expected(input.expected_stage, StageCatalog.stage_token(stage)),
         :ok <- selected_items(stage, input.items),
         {:ok, batch} <-
           StageStore.preview_items(
             fresh.organization_id,
             mission_id,
             stage_id,
             Enum.map(input.items, & &1["id"]),
             actor(fresh)
           ) do
      held = %{
        organization_id: fresh.organization_id,
        mission_id: mission_id,
        stage_id: stage_id,
        actor_id: fresh.user.user_id,
        expected_stage: input.expected_stage,
        items: input.items,
        batch: batch
      }

      held = Map.put(held, :token, RequestValidation.authoring_digest(held))

      with {:ok, _, _} <- StageAccess.authorize(scope, mission_id),
           {:ok, _} <- public_preview(held),
           do: {:ok, held}
    end
  end

  defp submit_locked(scope, fresh, stage, held) do
    mission_id = stage.mission_id
    stage_id = stage.command_stage_id

    with :ok <- held_identity(fresh, mission_id, stage_id, held),
         :ok <- expected(held.expected_stage, StageCatalog.stage_token(stage)),
         :ok <- selected_items(stage, held.items),
         {:ok, requests} <-
           StageStore.submit_reviewed_items(
             fresh.organization_id,
             mission_id,
             stage_id,
             held.batch,
             fn -> authorize_insert(scope, mission_id) end
           ) do
      {:ok, receipt(stage_id, fresh.user.user_id, requests)}
    end
  end

  def recover(scope, mission_id, stage_id, held) do
    StageAccess.with_stage(scope, mission_id, stage_id, :read, fn fresh, _, stage ->
      with :ok <- held_identity(fresh, mission_id, stage_id, held),
           {:ok, requests} <- recover_requests(stage, held.batch.requests) do
        {:ok, receipt(stage_id, fresh.user.user_id, requests)}
      end
    end)
  end

  def public_preview(held) do
    document = %{
      "token" => held.token,
      "stage_id" => held.stage_id,
      "actor_id" => held.actor_id,
      "requests" =>
        Enum.map(held.batch.requests, fn request ->
          public =
            RequestAuthoring.public_preview(%{
              request: request,
              token: held.token,
              target:
                AuthoringCatalog.target(
                  Map.fetch!(held.batch.target_rows, request.command_request_id)
                )
            })

          Map.merge(public, %{
            "item_id" => request.source_staged_command_item_id,
            "notes" => request.metadata["notes"],
            "order" => request.metadata["stage_item_order"]
          })
        end)
    }

    case Jason.encode(document) do
      {:ok, json} when byte_size(json) <= 524_288 -> {:ok, document}
      _ -> {:error, :command_stage_preview_too_large}
    end
  rescue
    ArgumentError -> {:error, :command_stage_preview_too_large}
  end

  defp selected_items(stage, selected) do
    ids = Enum.map(selected, & &1["id"])

    rows =
      stage
      |> StageCatalog.item_query()
      |> where([row], row.staged_command_item_id in ^ids)
      |> Repo.all()

    observed = Map.new(rows, &{&1.staged_command_item_id, &1})

    valid? =
      length(rows) == length(selected) and
        Enum.all?(selected, fn item ->
          case observed[item["id"]] do
            %{
              token: token,
              lifecycle_state: "draft",
              notes_available: true,
              argument_values_document: arguments
            } ->
              token == item["expected_item"] and is_map(arguments)

            _ ->
              false
          end
        end)

    if valid?, do: :ok, else: {:error, :command_stage_changed}
  end

  defp held_identity(fresh, mission, stage, held) do
    if held.organization_id == fresh.organization_id and held.mission_id == mission and
         held.stage_id == stage and held.actor_id == fresh.user.user_id and
         held.token == RequestValidation.authoring_digest(Map.delete(held, :token)),
       do: :ok,
       else: {:error, :command_stage_changed}
  end

  defp recover_requests(stage, expected) do
    Enum.reduce_while(expected, {:ok, []}, fn request, {:ok, recovered} ->
      with {:ok, actual} <- recovered_request(stage, request.command_request_id),
           true <- same_receipt?(actual, request),
           true <- submitted_pointer?(stage, request) do
        {:cont, {:ok, recovered ++ [actual]}}
      else
        _ -> {:halt, {:error, :unconfirmed}}
      end
    end)
  end

  defp recovered_request(stage, request_id) do
    query =
      from(row in CommandRequestRow,
        where:
          row.organization_id == ^stage.organization_id and row.mission_id == ^stage.mission_id and
            row.command_request_id == ^request_id,
        where:
          fragment("octet_length(?::text)", row.argument_values_document) <= 32_768 and
            fragment("octet_length(?::text)", row.resolved_argument_values_document) <= 131_072 and
            fragment("octet_length(?::text)", row.metadata_document) <= 131_072
      )

    case Repo.one(query) do
      nil -> {:error, :unconfirmed}
      row -> {:ok, CommandRequestRow.to_domain(row)}
    end
  end

  defp same_receipt?(actual, expected) do
    # Lifecycle and verification may legitimately advance after insertion. Every
    # retained creation field, including resolved arguments and provenance, must match.
    Map.drop(Map.from_struct(actual), [:lifecycle_state, :verification_state]) ==
      Map.drop(Map.from_struct(expected), [:lifecycle_state, :verification_state])
  end

  defp submitted_pointer?(stage, request) do
    Repo.exists?(
      from(row in StagedCommandItemRow,
        where:
          row.organization_id == ^stage.organization_id and row.mission_id == ^stage.mission_id and
            row.command_stage_id == ^stage.command_stage_id and
            row.staged_command_item_id == ^request.source_staged_command_item_id and
            row.lifecycle_state == "submitted" and
            row.submitted_command_request_id == ^request.command_request_id
      )
    )
  end

  defp authorize_insert(scope, mission_id) do
    case StageAccess.authorize(scope, mission_id) do
      {:ok, _, _} -> :ok
      _ -> {:error, :unavailable}
    end
  end

  defp receipt(stage_id, actor_id, requests),
    do: %{
      "operation" => "requests_created",
      "stage_id" => stage_id,
      "actor_id" => actor_id,
      "requests" =>
        Enum.map(
          requests,
          &%{
            "request_id" => &1.command_request_id,
            "item_id" => &1.source_staged_command_item_id,
            "state" => Atom.to_string(&1.lifecycle_state),
            "requested_at" => DateTime.to_iso8601(&1.requested_at)
          }
        )
    }

  defp actor(fresh), do: %{"actor_kind" => "user", "user_id" => fresh.user.user_id}
  defp expected(value, value) when is_binary(value), do: :ok
  defp expected(_, _), do: {:error, :command_stage_changed}
end
