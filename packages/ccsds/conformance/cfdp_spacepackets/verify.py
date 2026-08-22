from importlib.metadata import version
import sys

from spacepackets.cfdp import (
    ChecksumType,
    ConditionCode,
    CrcFlag,
    DeliveryCode,
    Direction,
    DirectiveType,
    FileStatus,
    LargeFileFlag,
    PduConfig,
    PduFactory,
    TransmissionMode,
)
from spacepackets.cfdp.pdu import (
    AckPdu,
    EofPdu,
    FileDataParams,
    FileDataPdu,
    FinishedParams,
    FinishedPdu,
    KeepAlivePdu,
    MetadataParams,
    MetadataPdu,
    NakPdu,
    PromptPdu,
    TransactionStatus,
)
from spacepackets.cfdp.pdu.prompt import ResponseRequired
from spacepackets.cfdp.tlv import FlowLabelTlv, MessageToUserTlv
from spacepackets.util import UnsignedByteField


EXPECTED_VERSION = "0.32.0"


def configuration(
    *,
    direction=Direction.TOWARDS_RECEIVER,
    mode=TransmissionMode.ACKNOWLEDGED,
    crc=CrcFlag.NO_CRC,
    large=LargeFileFlag.NORMAL,
    entity_octets=1,
    sequence_octets=1,
):
    return PduConfig(
        source_entity_id=UnsignedByteField(1, entity_octets),
        dest_entity_id=UnsignedByteField(3, entity_octets),
        transaction_seq_num=UnsignedByteField(2, sequence_octets),
        trans_mode=mode,
        file_flag=large,
        crc_flag=crc,
        direction=direction,
    )


def independently_generated_cases():
    unack = configuration(mode=TransmissionMode.UNACKNOWLEDGED)
    sender = configuration(direction=Direction.TOWARDS_SENDER)

    return [
        (
            "metadata",
            MetadataPdu(
                unack,
                MetadataParams(False, ChecksumType.MODULAR, 3, "a", "b"),
            ),
        ),
        (
            "metadata-options",
            MetadataPdu(
                configuration(mode=TransmissionMode.UNACKNOWLEDGED),
                MetadataParams(True, ChecksumType.NULL_CHECKSUM, 0, None, None),
                [MessageToUserTlv(b"proxy"), FlowLabelTlv(bytes([1, 2]))],
            ),
        ),
        (
            "file-data-crc",
            FileDataPdu(
                configuration(
                    mode=TransmissionMode.UNACKNOWLEDGED,
                    crc=CrcFlag.WITH_CRC,
                ),
                FileDataParams(bytes.fromhex("AABBCC"), 0),
            ),
        ),
        (
            "file-data-large",
            FileDataPdu(
                configuration(
                    mode=TransmissionMode.UNACKNOWLEDGED,
                    large=LargeFileFlag.LARGE,
                    entity_octets=8,
                    sequence_octets=8,
                ),
                FileDataParams(bytes([1, 2, 3]), 0x100000000),
            ),
        ),
        ("eof", EofPdu(configuration(mode=TransmissionMode.UNACKNOWLEDGED), 0xAABBCCDD, 3)),
        (
            "finished",
            FinishedPdu(
                sender,
                FinishedParams(
                    ConditionCode.NO_ERROR,
                    DeliveryCode.DATA_COMPLETE,
                    FileStatus.FILE_STATUS_UNREPORTED,
                ),
            ),
        ),
        (
            "ack-eof",
            AckPdu(sender, DirectiveType.EOF_PDU, ConditionCode.NO_ERROR, TransactionStatus.ACTIVE),
        ),
        (
            "ack-finished",
            AckPdu(
                configuration(),
                DirectiveType.FINISHED_PDU,
                ConditionCode.NO_ERROR,
                TransactionStatus.TERMINATED,
            ),
        ),
        ("nak", NakPdu(sender, 0, 12, [(0, 0), (4, 8)])),
        ("prompt", PromptPdu(configuration(), ResponseRequired.KEEP_ALIVE)),
        ("keep-alive", KeepAlivePdu(sender, 8)),
    ]


def main():
    actual_version = version("spacepackets")
    if actual_version != EXPECTED_VERSION:
        raise RuntimeError(f"expected spacepackets {EXPECTED_VERSION}, got {actual_version}")

    print(f"META\tspacepackets\t{actual_version}\t{sys.version.split()[0]}")

    for raw_line in sys.stdin:
        fields = raw_line.rstrip("\n").split("\t")
        if len(fields) != 3 or fields[0] != "CASE":
            raise RuntimeError(f"invalid CCSDS case line: {raw_line!r}")
        _, case_id, wire_hex = fields
        wire = bytes.fromhex(wire_hex)
        packet = PduFactory.from_raw(wire)
        if packet is None:
            raise RuntimeError(f"spacepackets rejected {case_id}")
        repacked = bytes(packet.pack())
        if repacked != wire:
            raise RuntimeError(
                f"spacepackets changed {case_id}: {wire.hex()} != {repacked.hex()}"
            )
        print(f"RESULT\tCCSDS\t{case_id}\t{wire.hex().upper()}")

    for case_id, packet in independently_generated_cases():
        wire = bytes(packet.pack())
        print(f"RESULT\tSPACEPACKETS\t{case_id}\t{wire.hex().upper()}")


if __name__ == "__main__":
    main()
