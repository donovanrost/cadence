defmodule CadenceWeb.OpsDashboardShowLive.RuntimeReplayTransportEvidenceScenario do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.{
    RuntimeReplayTransportEvidenceSetup,
    RuntimeReplayTransportFailedEvidenceCycleOne,
    RuntimeReplayTransportFailedEvidenceCycleTwo,
    RuntimeReplayTransportFailedEvidenceFinish,
    RuntimeReplayTransportFailedEvidenceStart,
    RuntimeReplayTransportRecordEvidence,
    RuntimeReplayTransportReleaseEvidence,
    RuntimeReplayTransportVerifierEvidence
  }

  def run do
    RuntimeReplayTransportEvidenceSetup.run()
    |> RuntimeReplayTransportReleaseEvidence.run()
    |> RuntimeReplayTransportFailedEvidenceStart.run()
    |> RuntimeReplayTransportFailedEvidenceCycleOne.run()
    |> RuntimeReplayTransportFailedEvidenceCycleTwo.run()
    |> RuntimeReplayTransportFailedEvidenceFinish.run()
    |> RuntimeReplayTransportVerifierEvidence.run()
    |> RuntimeReplayTransportRecordEvidence.run()
  end
end
