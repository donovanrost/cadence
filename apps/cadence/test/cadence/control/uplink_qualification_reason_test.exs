defmodule Cadence.Control.UplinkQualificationReasonTest do
  @moduledoc "Recorded uplink readiness reasons are keys, normalized where they're recorded (§8 domain 9)."
  use ExUnit.Case, async: true

  alias Cadence.Control.UplinkQualification
  alias Cadence.GroundNetworks.ProviderError

  test "atoms and strings stay, provider errors and tuples become keys, anything else is unknown" do
    assert UplinkQualification.reason_key(:attestation_peer_mismatch) ==
             :attestation_peer_mismatch

    assert UplinkQualification.reason_key("cop1_awaiting_clcw") == "cop1_awaiting_clcw"

    assert UplinkQualification.reason_key(%ProviderError{category: :known_timeout}) ==
             :provider_known_timeout

    assert UplinkQualification.reason_key({:fencing_rejected, %{"detail" => "x"}}) ==
             :fencing_rejected

    assert UplinkQualification.reason_key(%{unexpected: true}) == :unknown
    assert UplinkQualification.reason_key(42) == :unknown
  end
end
