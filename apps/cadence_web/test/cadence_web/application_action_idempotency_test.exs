defmodule CadenceWeb.ApplicationActionIdempotencyTest do
  use Cadence.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox

  alias Cadence.Auth.Scope
  alias CadenceWeb.ApplicationActionIdempotency

  @now ~U[2026-09-04 12:00:00Z]
  @response_content_type "application/json; charset=utf-8"

  test "key and request digests are bounded opaque HMAC values with canonical request ordering" do
    assert {:ok, key_digest} = ApplicationActionIdempotency.key_digest("digest-key")
    assert key_digest =~ ~r/^hmac-sha256:[0-9a-f]{64}$/
    assert byte_size(key_digest) == 76

    assert {:error, :malformed_idempotency_key} =
             ApplicationActionIdempotency.key_digest(String.duplicate("x", 129))

    assert {:ok, first_request_digest} =
             ApplicationActionIdempotency.request_digest(%{"b" => 2, "a" => 1})

    assert {:ok, second_request_digest} =
             ApplicationActionIdempotency.request_digest(%{"a" => 1, "b" => 2})

    assert first_request_digest == second_request_digest
    assert first_request_digest =~ ~r/^hmac-sha256:[0-9a-f]{64}$/
  end

  test "durable success replay returns the exact stored response bytes and never stores the raw key" do
    parent = self()
    key = "durable-success-key"
    response = response(200, ~s({"result":"success","ordered":[1,2]}))

    assert {:ok, {:executed, first}} =
             run(scope(), identity(), key, request_document(), fn ->
               send(parent, :executed_once)
               {:ok, response}
             end)

    assert {:ok, {:replayed, second}} =
             run(scope(), identity(), key, request_document(), fn ->
               send(parent, :unexpected_execution)
               {:ok, response(200, ~s({"result":"wrong"}))}
             end)

    assert_receive :executed_once
    refute_receive :unexpected_execution
    assert first == second
    assert first.body == ~s({"result":"success","ordered":[1,2]})
    assert ApplicationActionIdempotency.key_digest(key) |> elem(1) != key
    row = Repo.one(ApplicationActionIdempotency)
    refute inspect(row) =~ key
    refute row.response_body =~ key
    assert Repo.aggregate(ApplicationActionIdempotency, :count, :id) == 1
  end

  test "a failed response is durable and replayed byte-for-byte without a second execution" do
    parent = self()
    key = "durable-failure-key"

    response =
      response(409, ~s({"schema":"cadence.application-host-problem.v1","code":"conflict"}))

    assert {:ok, {:executed, first}} =
             run(scope(), identity(), key, request_document(), fn ->
               send(parent, :failed_once)
               {:error, response}
             end)

    assert {:ok, {:replayed, second}} =
             run(scope(), identity(), key, request_document(), fn ->
               send(parent, :unexpected_failure_execution)
               {:error, response(500, ~s({"code":"wrong"}))}
             end)

    assert_receive :failed_once
    refute_receive :unexpected_failure_execution
    assert first == second
    assert first.status == 409
    assert Repo.one(ApplicationActionIdempotency).state == :failed
  end

  test "a different request digest is a collision and cannot execute" do
    parent = self()
    key = "collision-key"

    assert {:ok, {:executed, _response}} =
             run(scope(), identity(), key, request_document("first"), fn ->
               {:ok, response(200, ~s({"result":"first"}))}
             end)

    assert {:error, :idempotency_key_collision} =
             run(scope(), identity(), key, request_document("second"), fn ->
               send(parent, :collision_executed)
               {:ok, response(200, ~s({"result":"second"}))}
             end)

    refute_receive :collision_executed
    assert Repo.aggregate(ApplicationActionIdempotency, :count, :id) == 1
  end

  test "authentication identity mismatch is rejected before a database claim" do
    unauthorized_scope = scope("different-user")

    assert {:error, :application_action_scope_required} =
             ApplicationActionIdempotency.run(
               unauthorized_scope,
               identity(),
               "auth-before-claim",
               request_document(),
               fn -> {:ok, response(200, ~s({"result":"must-not-run"}))} end,
               now: @now
             )

    assert Repo.aggregate(ApplicationActionIdempotency, :count, :id) == 0
  end

  test "the active generation is part of logical identity" do
    parent = self()
    key = "generation-separated-key"
    first_identity = identity("generation-a")
    second_identity = identity("generation-b")

    assert {:ok, {:executed, _first}} =
             run(scope(), first_identity, key, request_document(), fn ->
               send(parent, :generation_a_executed)
               {:ok, response(200, ~s({"generation":"a"}))}
             end)

    assert {:ok, {:executed, _second}} =
             run(scope(), second_identity, key, request_document(), fn ->
               send(parent, :generation_b_executed)
               {:ok, response(200, ~s({"generation":"b"}))}
             end)

    assert_receive :generation_a_executed
    assert_receive :generation_b_executed
    assert Repo.aggregate(ApplicationActionIdempotency, :count, :id) == 2
  end

  test "concurrent identical claims allow one execution and return in-progress to the duplicate" do
    parent = self()
    key = "concurrent-claim-key"
    request = request_document()
    identity = identity()

    first_task =
      Task.async(fn ->
        receive do
          :start ->
            ApplicationActionIdempotency.run(
              scope(),
              identity,
              key,
              request,
              fn ->
                send(parent, :first_claimed)

                receive do
                  :finish -> {:ok, response(200, ~s({"result":"first"}))}
                end
              end,
              now: @now
            )
        end
      end)

    second_task =
      Task.async(fn ->
        receive do
          :start ->
            ApplicationActionIdempotency.run(
              scope(),
              identity,
              key,
              request,
              fn ->
                send(parent, :second_executed)
                {:ok, response(200, ~s({"result":"second"}))}
              end,
              now: @now
            )
        end
      end)

    Sandbox.allow(Repo, self(), first_task.pid)
    Sandbox.allow(Repo, self(), second_task.pid)
    send(first_task.pid, :start)
    assert_receive :first_claimed

    send(second_task.pid, :start)
    assert Task.await(second_task) == {:error, :idempotency_in_progress}
    refute_receive :second_executed

    send(first_task.pid, :finish)
    assert {:ok, {:executed, _response}} = Task.await(first_task)
    assert Repo.aggregate(ApplicationActionIdempotency, :count, :id) == 1
  end

  test "an expired in-progress claim becomes indeterminate and never re-executes" do
    parent = self()
    key = "expired-claim-key"
    request = request_document()
    assert {:ok, key_digest} = ApplicationActionIdempotency.key_digest(key)
    assert {:ok, request_digest} = ApplicationActionIdempotency.request_digest(request)

    assert {:ok, {:claimed, _row}} =
             ApplicationActionIdempotency.claim(
               identity(),
               key_digest,
               request_digest,
               now: DateTime.add(@now, -60, :second),
               lease_seconds: 1
             )

    assert {:ok, {:replayed, indeterminate}} =
             run(
               scope(),
               identity(),
               key,
               request,
               fn ->
                 send(parent, :expired_reexecuted)
                 {:ok, response(200, ~s({"result":"must-not-run"}))}
               end,
               now: @now
             )

    refute_receive :expired_reexecuted
    assert indeterminate == ApplicationActionIdempotency.indeterminate_response()
    assert Repo.one(ApplicationActionIdempotency).state == :indeterminate

    assert {:ok, {:replayed, replayed_indeterminate}} =
             run(scope(), identity(), key, request, fn ->
               send(parent, :indeterminate_reexecuted)
               {:ok, response(200, ~s({"result":"must-not-run"}))}
             end)

    refute_receive :indeterminate_reexecuted
    assert replayed_indeterminate == indeterminate
  end

  test "completion is compare-and-set by the private claim token" do
    assert {:ok, key_digest} = ApplicationActionIdempotency.key_digest("cas-key")
    assert {:ok, request_digest} = ApplicationActionIdempotency.request_digest(request_document())

    assert {:ok, {:claimed, row}} =
             ApplicationActionIdempotency.claim(identity(), key_digest, request_digest, now: @now)

    assert {:ok, _response} =
             ApplicationActionIdempotency.complete(row, response(200, ~s({"ok":true})), now: @now)

    assert {:error, :claim_lost} =
             ApplicationActionIdempotency.complete(row, response(200, ~s({"ok":false})),
               now: @now
             )

    assert Repo.one(ApplicationActionIdempotency).response_body == ~s({"ok":true})
  end

  test "the database exposes the complete logical identity uniqueness constraint" do
    assert [[index_definition]] =
             Repo.query!("""
             SELECT indexdef
             FROM pg_indexes
             WHERE tablename = 'federated_application_action_idempotencies'
               AND indexname = 'faaid_logical_identity_idx'
             """).rows

    for column <- ~w(
      organization_id actor_kind actor_id mission_id scope_kind scope_id
      application_key application_version surface_id surface_version operation
      operation_version generation_id release_id idempotency_key_digest
    ) do
      assert index_definition =~ column
    end
  end

  defp run(scope, identity, key, request, fun, opts \\ []) do
    ApplicationActionIdempotency.run(
      scope,
      identity,
      key,
      request,
      fun,
      Keyword.put_new(opts, :now, @now)
    )
  end

  defp response(status, body),
    do: %{status: status, content_type: @response_content_type, body: body}

  defp scope(actor_id \\ "user-1") do
    %Scope{actor_kind: :user, organization_id: "org-1", user: %{user_id: actor_id}}
  end

  defp identity(generation_id \\ "generation-1") do
    %{
      organization_id: "org-1",
      actor_kind: "user",
      actor_id: "user-1",
      mission_id: "mission-1",
      scope_kind: "mission",
      scope_id: "mission-1",
      application_key: "derived_telemetry",
      application_version: 1,
      surface_id: "manage",
      surface_version: 1,
      operation: "save_definition",
      operation_version: 1,
      generation_id: generation_id,
      release_id: "release-1"
    }
  end

  defp request_document(value \\ "same") do
    %{
      "applicationKey" => "derived_telemetry",
      "applicationVersion" => 1,
      "surfaceId" => "manage",
      "surfaceVersion" => 1,
      "operation" => "save_definition",
      "operationVersion" => 1,
      "params" => %{"value" => value}
    }
  end
end
