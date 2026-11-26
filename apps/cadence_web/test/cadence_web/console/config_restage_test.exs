defmodule CadenceWeb.Console.ConfigRestageTest do
  @moduledoc """
  D3 (#544; U109, mms-ux on #633): `restage_needed` on the wire. A 409 whose message names why the
  staged version isn't the one to use any more (one why per `current_reason`), by the act, with the
  entries and their numbers in details.
  """
  use CadenceWeb.ConnCase, async: true

  alias CadenceWeb.Console.ConfigJSON

  defp entry(reason, extra \\ %{}),
    do:
      Map.merge(
        %{
          composition_id: "mission_model_composition:a",
          recorded_revision_id: "mission_model_revision:old",
          current_revision_id: "mission_model_revision:new",
          current_reason: reason,
          catalog_revision_number: 4,
          composition_number: 3
        },
        extra
      )

  defp message(conn, entries),
    do: conn |> ConfigJSON.error({:restage_needed, entries}) |> json_response(409)

  test "a 409 restage_needed with the entries in details; the why by current_reason" do
    whys = [
      {"newer_approved", "a newer approved version of catalog rev 4 is now the one to use"},
      {"withdrawn", "catalog rev 4's approval was withdrawn"},
      {"unrunnable",
       "the version of catalog rev 4 it staged doesn't run on this version of Cadence"},
      {nil, "the version of catalog rev 4 it staged isn't the one to use any more"}
    ]

    for {reason, why} <- whys do
      body = message(build_conn(), [entry(reason)])
      assert body["error"]["code"] == "restage_needed"

      assert body["error"]["message"] ==
               "Not applied: #{why}, so nothing changed. Stage it again to use the current version."

      assert [%{"composition_id" => "mission_model_composition:a", "current_reason" => ^reason}] =
               body["error"]["details"]["entries"]
    end
  end

  test "none left ends 'Move it to an approved composition first'; several entries count" do
    body = message(build_conn(), [entry("none_left", %{current_revision_id: nil}), entry(nil)])

    assert body["error"]["message"] ==
             "Not applied: no approved version of catalog rev 4 is left and 1 more catalog " <>
               "revision changed too, so nothing changed. Move it to an approved composition first."
  end

  test "the pin is named by its composition number when it has no catalog revision, else 'this composition'" do
    composed = entry("newer_approved", %{catalog_revision_number: nil})
    assert message(build_conn(), [composed])["error"]["message"] =~ "version of composition 3 is"

    unnamed = %{composed | composition_number: nil}

    assert message(build_conn(), [unnamed])["error"]["message"] =~
             "version of this composition is"
  end

  test "an approve takes U95's form; a request review opens 'Not sent for review:'" do
    approve = build_conn() |> Plug.Conn.put_private(:phoenix_action, :review)

    assert message(approve, [entry("newer_approved")])["error"]["message"] ==
             "Not approved: a newer approved version of catalog rev 4 is now the one to use, so " <>
               "nothing was applied and the change set stays in review. Your approval wasn't " <>
               "recorded. Send it back so it can be staged again."

    assert message(approve, [entry("none_left", %{current_revision_id: nil})])["error"]["message"] =~
             "Send it back so it can move to an approved composition."

    review = build_conn() |> Plug.Conn.assign(:submit_act, :request_review)
    assert message(review, [entry(nil)])["error"]["message"] =~ "Not sent for review: "
  end
end
