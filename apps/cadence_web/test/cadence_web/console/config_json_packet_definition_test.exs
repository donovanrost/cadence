defmodule CadenceWeb.Console.ConfigJSONPacketDefinitionTest do
  @moduledoc """
  #534 (api-ops' condition 3): a generation refused because another saved a packet definition
  under the same version answers 409, says nothing was applied and that a resubmit works, never a
  500 or the generic 422.
  """
  use CadenceWeb.ConnCase, async: true

  alias CadenceWeb.Console.ConfigJSON

  test "a packet definition version race is a retryable 409", %{conn: conn} do
    conn = ConfigJSON.error(conn, {:packet_definition_content_changed, "semantic:container:x", 4})

    assert %{
             "code" => "packet_definition_version_taken",
             "message" => message,
             "details" => %{
               "packet_definition_id" => "semantic:container:x",
               "version" => 4,
               "retryable" => true
             }
           } = json_response(conn, 409)["error"]

    assert message =~ "nothing was applied"
    assert message =~ "Submit again"
  end
end
