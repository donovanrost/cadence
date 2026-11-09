defmodule CadenceWeb.ActivationMetadataApiTest do
  @moduledoc "DECISIONS #32: server-built activation metadata keys can't come from a client."
  use CadenceWeb.ConnCase, async: false

  import CadenceWeb.ControlPlaneApiFixtures

  setup %{conn: conn} do
    %{conn: conn, api_token: token, organization_id: org, mission_id: mission} = bootstrap(conn)
    %{conn: conn, token: token, path: "/api/organizations/#{org}/missions/#{mission}/activations"}
  end

  for key <- ~w(spacecraft_configuration_version spacecraft_configurations fleet
                configuration_review mission_model) do
    test "refuses reserved metadata key #{key}", c do
      conn =
        c.conn
        |> authorize(c.token)
        |> post(c.path, %{
          "activation" => %{
            "mission_model_revision_id" => "rev-1",
            "binding_set_id" => "bs-1",
            "version" => 1,
            "metadata" => %{unquote(key) => %{}}
          }
        })

      assert %{"errors" => [%{"field" => "metadata", "reason" => "reserved_metadata_key"}]} =
               json_response(conn, 422)
    end
  end

  test "ordinary metadata still passes parameter validation", c do
    conn =
      c.conn
      |> authorize(c.token)
      |> post(c.path, %{
        "activation" => %{
          "mission_model_revision_id" => "rev-1",
          "binding_set_id" => "bs-1",
          "version" => 1,
          "metadata" => %{"note" => "nightly"}
        }
      })

    refute match?(
             %{"errors" => [%{"reason" => "reserved_metadata_key"}]},
             json_response(conn, conn.status)
           )
  end
end
