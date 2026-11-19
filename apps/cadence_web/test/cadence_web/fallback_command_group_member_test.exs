defmodule CadenceWeb.FallbackCommandGroupMemberTest do
  @moduledoc """
  ux U87 (amended, #121): the REST refusal of a command-group member names the act tried, and
  an action it doesn't know names no act, so a future caller is never told the wrong one.
  """
  use CadenceWeb.ConnCase, async: true

  alias CadenceWeb.FallbackController

  test "an action with no words of its own gets the neutral line, not another act's", %{
    conn: conn
  } do
    conn =
      conn
      |> Plug.Conn.put_private(:phoenix_action, :some_future_action)
      |> FallbackController.call({:error, :command_request_in_group})

    assert json_response(conn, 409) == %{
             "errors" => [
               %{
                 "reason" => "command_request_in_group",
                 "message" => "This command is part of a command group. Use its group instead."
               }
             ]
           }
  end
end
