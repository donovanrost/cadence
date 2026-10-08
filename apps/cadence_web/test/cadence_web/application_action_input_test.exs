defmodule CadenceWeb.ApplicationActionInputTest do
  use CadenceWeb.ConnCase, async: true
  alias CadenceWeb.{ApplicationActionIdempotency, ApplicationActionInput}

  test "only the exact reserve capability field admits a long opaque token" do
    request = request(String.duplicate("a", 4096))
    assert {:ok, ^request} = ApplicationActionInput.safe(request)

    for invalid <- [
          put_in(request, ["input", "token"], String.duplicate("a", 8193)),
          Map.put(request, "surfaceId", "other"),
          Map.put(request, "applicationKey", "other"),
          Map.put(request, "actionId", "search"),
          put_in(request, ["input", "unexpected"], "value"),
          Map.put(request, "other", String.duplicate("b", 241)),
          Map.put(request, "params", %{"token" => "different"})
        ] do
      assert {:error, _} = ApplicationActionInput.safe(invalid)
    end
  end

  test "idempotency digests retain the complete capability and ordinary input bounds" do
    document =
      request(String.duplicate("a", 4096))
      |> Map.delete("actionId")
      |> Map.put("operation", "reserve")
      |> Map.put("operationVersion", 1)

    assert {:ok, first} = ApplicationActionIdempotency.request_digest(document)
    assert {:ok, ^first} = ApplicationActionIdempotency.request_digest(document)

    assert {:ok, other} =
             ApplicationActionIdempotency.request_digest(
               put_in(document, ["input", "token"], String.duplicate("b", 4096))
             )

    refute first == other

    assert {:error, :invalid_application_request} =
             ApplicationActionIdempotency.request_digest(%{
               "token" => String.duplicate("a", 4096)
             })
  end

  test "version two capability admission preserves operation identity without widening other fields" do
    input = %{
      "contract_version" => 2,
      "operation_id" => Ecto.UUID.generate(),
      "payload" => %{"token" => String.duplicate("x", 4096)}
    }

    envelope = request("unused") |> Map.put("input", input)
    assert {:ok, ^envelope} = ApplicationActionInput.safe(envelope)

    for bad <- [
          put_in(envelope, ["input", "operation_id"], "invalid"),
          put_in(envelope, ["input", "payload", "token"], String.duplicate("x", 8193)),
          put_in(envelope, ["input", "payload", "extra"], "value"),
          put_in(envelope, ["input", "contract_version"], 3)
        ] do
      assert {:error, _} = ApplicationActionInput.safe(bad)
    end
  end

  defp request(token),
    do: %{
      "applicationKey" => "ops_console",
      "applicationVersion" => 1,
      "surfaceId" => "contact_schedule",
      "surfaceVersion" => 1,
      "actionId" => "reserve",
      "input" => %{"token" => token}
    }
end
