defmodule CadenceWeb.FallbackCommandWindowTest do
  @moduledoc "U46 / DECISIONS #84: the legacy release path answers the gate's refusal as a 409."
  use CadenceWeb.ConnCase, async: true

  test "command_window_closed is a 409 naming why and the contact", %{conn: conn} do
    conn =
      CadenceWeb.FallbackController.call(
        conn,
        {:error, {:command_window_closed, "realized-1", :uplink_leg_dropped}}
      )

    assert json_response(conn, 409) == %{
             "errors" => [
               %{
                 "reason" => "command_window_closed",
                 "why" => "uplink_leg_dropped",
                 "realized_contact_id" => "realized-1"
               }
             ]
           }
  end
end
