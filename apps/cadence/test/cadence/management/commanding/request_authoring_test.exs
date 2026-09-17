defmodule Cadence.Management.Commanding.RequestAuthoringTest do
  use Cadence.DataCase, async: false
  alias Cadence.Accounts.UserRow
  alias Cadence.Activations.ActiveBindingSetRow

  alias Cadence.Commanding.{
    CommandQueueEntryRow,
    CommandReleaseAttemptRow,
    CommandRequestRow,
    RequestStore
  }

  alias Cadence.CommandAuthoringFixtures
  alias Cadence.Management.Commanding.RequestAuthoring
  alias Cadence.MissionModels.RuntimePlanRow
  alias Cadence.Persistence.JsonDocument
  alias Cadence.SourceEndpoints.SourceEndpointRow

  setup do
    {:ok, CommandAuthoringFixtures.fixture!()}
  end

  defp input(c, overrides \\ %{}) do
    {:ok, catalog} = RequestAuthoring.load(c.scope, c.mission, %{})

    Map.merge(
      %{
        "expected_basis" => catalog["basis"]["token"],
        "source_endpoint_ref" => c.target.source_endpoint_id,
        "command_id" => c.model.commands_by_name["COMMAND_1"],
        "argument_values_json" => Jason.encode!(%{"amount" => 2}),
        "priority" => 3,
        "not_before" => nil,
        "expires_at" => nil
      },
      overrides
    )
  end

  defp create(c, held),
    do: RequestAuthoring.create(c.scope, c.mission, held, %{"expected_preview" => held.token})

  test "active-basis adapter preserves the existing identity bytes and scoped held snapshot", c do
    alias Cadence.Reads.MissionModels.ActiveBasis

    assert {:ok, activation} = Cadence.Activations.fetch_active_activation(c.org, c.mission)

    assert {:ok, snapshot} =
             ActiveBasis.with_command_catalog(c.org, c.mission, fn snapshot ->
               assert Repo.in_transaction?()
               assert snapshot.activation_id == activation.activation_id
               assert snapshot.generation == activation.generation
               refute Map.has_key?(snapshot, :metadata)
               refute Map.has_key?(snapshot, :__meta__)

               expected_token =
                 {:command_authoring_v1, {activation, snapshot.basis.runtime_plans.command}}
                 |> :erlang.term_to_binary([:deterministic])
                 |> then(&:crypto.hash(:sha256, &1))
                 |> Base.encode16(case: :lower)

               assert snapshot.token == expected_token
               {:ok, snapshot}
             end)

    assert snapshot.basis.mission_model_revision_id == c.model.revision_id
    assert ActiveBasis.active_revision_id(c.org, c.mission) == c.model.revision_id
    assert ActiveBasis.active_revision_id("foreign", c.mission) == nil

    assert {:error, :no_active_binding_set} =
             ActiveBasis.fetch_runtime_basis("foreign", c.mission)

    assert {:error, :command_authoring_basis_unavailable} =
             ActiveBasis.with_command_catalog("foreign", c.mission, fn _ ->
               flunk("foreign scope reached the authoring callback")
             end)
  end

  test "native model preview resolves arguments and persists the real human request without queue or release",
       c do
    {:ok, held} = RequestAuthoring.preview(c.scope, c.mission, input(c))
    assert held.request.resolved_argument_values == %{"amount" => 2, "delay_s" => 5}
    assert held.request.hazardous
    assert held.request.lifecycle_state == :approval_pending
    assert held.request.mission_model_revision_id == c.model.revision_id
    assert held.request.requested_by == %{"actor_kind" => "user", "user_id" => c.user.user_id}
    refute Repo.get(CommandRequestRow, held.request.command_request_id)
    assert {:ok, receipt} = create(c, held)
    assert receipt["request_id"] == held.request.command_request_id
    assert {:ok, stored} = RequestStore.fetch_request(c.org, c.mission, receipt["request_id"])
    assert stored == held.request
    assert {:ok, ^receipt} = RequestAuthoring.recover(c.scope, c.mission, held)
    refute Repo.exists?(from(row in CommandQueueEntryRow, where: row.mission_id == ^c.mission))

    refute Repo.exists?(
             from(row in CommandReleaseAttemptRow, where: row.mission_id == ^c.mission)
           )

    refute Jason.encode!(RequestAuthoring.public_preview(held)) =~ "target-secret"
  end

  test "authoring exposes the selected catalog command opcode and wire width", c do
    for i <- 1..2 do
      assert {:ok, catalog} =
               RequestAuthoring.load(c.scope, c.mission, %{
                 "command" => c.model.commands_by_name["COMMAND_#{i}"]
               })

      assert catalog["selected_command"]["opcode_json"] == Integer.to_string(i)
      assert catalog["selected_command"]["opcode_size_bits"] == 8
    end
  end

  test "a duplicate request identity returns an error and cannot substitute unstored content",
       c do
    {:ok, held} = RequestAuthoring.preview(c.scope, c.mission, input(c))
    assert {:ok, _} = create(c, held)
    assert {:error, %Ecto.Changeset{}} = create(c, held)
    changed = %{held.request | argument_values: %{"amount" => 99}}
    assert {:error, %Ecto.Changeset{}} = RequestStore.persist_request(c.org, changed)

    assert {:ok, original} =
             RequestStore.fetch_request(c.org, c.mission, held.request.command_request_id)

    assert original.argument_values == %{"amount" => 2}

    assert Repo.aggregate(
             from(row in CommandRequestRow, where: row.mission_id == ^c.mission),
             :count
           ) == 1
  end

  test "changed active generation or target requires a new preview", c do
    {:ok, held} = RequestAuthoring.preview(c.scope, c.mission, input(c))
    row = Repo.get!(ActiveBindingSetRow, c.mission)
    Repo.update!(Ecto.Changeset.change(row, generation: row.generation + 1))
    assert {:error, :command_authoring_basis_changed} = create(c, held)
    {:ok, next} = RequestAuthoring.preview(c.scope, c.mission, input(c))
    target = Repo.get!(SourceEndpointRow, c.target.source_endpoint_id)
    Repo.update!(Ecto.Changeset.change(target, scid: 8))
    assert {:error, :command_authoring_basis_changed} = create(c, next)
    refute Repo.exists?(from(row in CommandRequestRow, where: row.mission_id == ^c.mission))
  end

  test "fresh disabled-account admission rejects preview, create, discovery and receipt reads",
       c do
    {:ok, held} = RequestAuthoring.preview(c.scope, c.mission, input(c))
    row = Repo.get!(UserRow, c.user.user_id)
    Repo.update!(Ecto.Changeset.change(row, lifecycle_state: "disabled"))
    assert {:error, _} = RequestAuthoring.load(c.scope, c.mission, %{})
    assert {:error, _} = RequestAuthoring.preview(c.scope, c.mission, %{})
    assert {:error, _} = create(c, held)
    assert {:error, _} = RequestAuthoring.recover(c.scope, c.mission, held)
    refute Repo.get(CommandRequestRow, held.request.command_request_id)
  end

  test "foreign target and forged fields cannot create a preview or alter the held request", c do
    foreign = CommandAuthoringFixtures.fixture!()

    assert {:error, _} =
             RequestAuthoring.preview(
               c.scope,
               c.mission,
               input(c, %{"source_endpoint_ref" => foreign.target.source_endpoint_id})
             )

    assert {:error, _} =
             RequestAuthoring.preview(
               c.scope,
               c.mission,
               Map.put(input(c), "requested_by", %{"user_id" => foreign.user.user_id})
             )

    {:ok, held} = RequestAuthoring.preview(c.scope, c.mission, input(c))

    assert {:error, _} =
             RequestAuthoring.create(foreign.scope, foreign.mission, held, %{
               "expected_preview" => held.token
             })

    assert {:error, _} = create(c, %{held | request: %{held.request | priority: 0}})
    assert {:error, _} = RequestAuthoring.create(c.scope, c.mission, %{}, %{})
  end

  test "discovery pages exact scoped targets and commands with durable cursors", c do
    model = CommandAuthoringFixtures.activate!(c.org, c.mission, 27)
    for _ <- 1..26, do: CommandAuthoringFixtures.target!(c.org, c.mission)
    {:ok, first} = RequestAuthoring.load(c.scope, c.mission, %{})
    assert length(first["commands"]["entries"]) == 25
    assert length(first["targets"]["entries"]) == 25

    {:ok, last} =
      RequestAuthoring.load(c.scope, c.mission, %{
        "command_after" => first["commands"]["next_after"],
        "target_after" => first["targets"]["next_after"],
        "command" => model.commands_by_name["COMMAND_1"],
        "target" => c.target.source_endpoint_id
      })

    assert length(last["commands"]["entries"]) == 2
    assert length(last["targets"]["entries"]) == 2
    assert last["commands"]["next_after"] == nil
    assert last["selected_command"]["id"] == model.commands_by_name["COMMAND_1"]
    assert last["selected_target"]["id"] == c.target.source_endpoint_id
    refute Jason.encode!(last) =~ "target-secret"
  end

  test "catalog reads only revision metadata and one bounded command document", c do
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:cadence, :repo, :query],
        fn _, _, meta, recipient ->
          send(recipient, {:authoring_query, meta.query, meta.params})
        end,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    assert {:ok, _} = RequestAuthoring.load(c.scope, c.mission, %{})
    queries = drain_queries([])

    revision_queries =
      Enum.filter(queries, fn {sql, _} -> String.contains?(sql, "mission_model_revisions") end)

    assert revision_queries != []

    refute Enum.any?(revision_queries, fn {sql, _} ->
             String.contains?(sql, "revision_document")
           end)

    documents =
      Enum.filter(queries, fn {sql, _} ->
        String.contains?(sql, "mission_model_runtime_plans") and
          String.contains?(sql, "plan_document")
      end)

    assert [{sql, params}] = documents
    assert sql =~ "octet_length"
    assert 8_388_608 in params
  end

  defp drain_queries(acc) do
    receive do
      {:authoring_query, sql, params} -> drain_queries([{sql, params} | acc])
    after
      0 -> acc
    end
  end

  test "oversized command documents and changed admitted plan identities fail closed", c do
    row =
      Repo.one!(
        from(row in RuntimePlanRow,
          where: row.revision_id == ^c.model.revision_id and row.target == "command"
        )
      )

    original = row.plan_document

    huge =
      JsonDocument.unwrap_value(original)
      |> Map.put("oversized", String.duplicate("x", 8_388_608))
      |> JsonDocument.wrap_value()

    Repo.update!(Ecto.Changeset.change(row, plan_document: huge))
    assert {:error, _} = RequestAuthoring.load(c.scope, c.mission, %{})

    Repo.update!(
      Ecto.Changeset.change(row,
        plan_document: original,
        content_sha256: String.duplicate("0", 64)
      )
    )

    assert {:error, _} = RequestAuthoring.load(c.scope, c.mission, %{})
  end
end
