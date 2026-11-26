defmodule CadenceWeb.Console.ConfigJSONPacketDefinitionTest do
  @moduledoc """
  #534 (api-ops' condition 3): a generation refused because another saved a packet definition
  under the same version answers 409, says nothing was applied and that a resubmit works, never a
  500 or the generic 422.
  """
  use CadenceWeb.ConnCase, async: true

  alias CadenceWeb.Console.{ConfigJSON, Problem, SpacecraftWorkspaceWords}

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

    assert message ==
             "Not applied: another change saved a packet definition at the same moment, so nothing changed. Try again."
  end

  test "the workspace submit's refusal is a 409 with mms-ux's U94 line" do
    assert {409, "packet_definition_version_taken", _default} =
             Problem.describe(:packet_definition_version_taken)

    assert SpacecraftWorkspaceWords.message(:packet_definition_version_taken, :submit, %{}) ==
             "Not sent: another change saved a packet definition at the same moment. Send it again."
  end
end
