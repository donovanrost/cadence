defmodule CadenceWeb.Assets.ActivityTimelineRowTest do
  use ExUnit.Case, async: true

  test "activity timeline row composes the approved presentation children directly" do
    source =
      Path.expand("../../../assets/vue/ActivityTimelineRow.vue", __DIR__)
      |> File.read!()

    assert source =~ ~s(import ClipboardButton from "./ClipboardButton.vue")

    assert source =~
             ~s(import ComparisonReviewActivityDetails from "./ComparisonReviewActivityDetails.vue")

    assert source =~ ~s(import HealthSnapshotActivity from "./HealthSnapshotActivity.vue")
    assert source =~ "<ClipboardButton"
    assert source =~ "<ComparisonReviewActivityDetails"
    assert source =~ "<HealthSnapshotActivity"
    refute source =~ "<.vue"
  end
end
