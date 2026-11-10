defmodule CadenceWeb.Console.ConfigErrorsTest do
  @moduledoc "Change-set error codes for catalog generations (#65)."
  use CadenceWeb.ConnCase, async: true

  alias CadenceWeb.Console.ConfigJSON

  test "holds_blocking carries the preview; an in-flight race names the requests" do
    preview = %{verdict: :hold, checks: [%{key: "compatibility", blocking: true, items: []}]}

    conn = ConfigJSON.error(build_conn(), {:holds_blocking, preview})

    assert %{"error" => %{"code" => "holds_blocking", "details" => %{"checks" => [check]}}} =
             json_response(conn, 409)

    assert check["blocking"] == true

    conn = ConfigJSON.error(build_conn(), {:catalog_command_in_flight, ["cmd_1", "cmd_2"]})

    assert %{
             "error" => %{
               "code" => "catalog_command_in_flight",
               "details" => %{"command_request_ids" => ["cmd_1", "cmd_2"]}
             }
           } = json_response(conn, 409)
  end

  test "an interrupted apply that didn't land is 503 apply_interrupted (qa #19)" do
    conn = ConfigJSON.error(build_conn(), :apply_interrupted)

    assert %{"error" => %{"code" => "apply_interrupted", "message" => message}} =
             json_response(conn, 503)

    assert message =~ "did not take effect"
  end
end
