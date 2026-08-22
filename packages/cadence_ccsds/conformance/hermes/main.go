package main

import (
	"bufio"
	"bytes"
	"encoding/hex"
	"fmt"
	"os"
	"runtime"
	"strconv"
	"strings"

	"github.com/nasa/hermes/pkg/ccsds"
	"github.com/nasa/hermes/pkg/serial"
)

const (
	hermesVersion = "v4.0.11"
	hermesCommit  = "433a8f9fc69a078eb430dab01285d7644e78eb07"
)

func main() {
	fmt.Printf("META\thermes\t%s\t%s\t%s\n", hermesVersion, hermesCommit, runtime.Version())

	scanner := bufio.NewScanner(os.Stdin)
	for scanner.Scan() {
		fields := strings.Split(scanner.Text(), "\t")
		if len(fields) == 0 {
			continue
		}

		switch fields[0] {
		case "PACKET":
			verifyPacket(fields)
		case "TC":
			verifyTC(fields)
		case "TM":
			verifyTM(fields)
		default:
			fail("unexpected input line %q", scanner.Text())
		}
	}

	if err := scanner.Err(); err != nil {
		fail("read cases: %v", err)
	}
}

func verifyPacket(fields []string) {
	requireFields(fields, 9)
	id := fields[1]
	packetType := uint8(number(fields[2], map[string]int{"telemetry": 0, "command": 1}))
	secondary := uint8(integer(fields[3]))
	apid := uint16(integer(fields[4]))
	sequenceFlag := uint8(number(fields[5], map[string]int{
		"continuation": 0,
		"first":        1,
		"last":         2,
		"unsegmented":  3,
	}))
	sequenceCount := uint16(integer(fields[6]))
	payload := binary(fields[7])
	cadence := binary(fields[8])

	packet := ccsds.Packet{
		Version:         0,
		Type:            ccsds.PacketType(packetType),
		SecondaryHeader: secondary,
		Apid:            apid,
		SequenceFlags:   ccsds.SequenceFlag(sequenceFlag),
		SequenceCount:   sequenceCount,
		Payload:         payload,
	}

	external := marshal(func(writer *serial.Writer) error { return packet.Marshal(writer) })
	requireEqual(id, cadence, external)

	decoded := ccsds.Packet{}
	reader := serial.NewReader(cadence)
	if err := decoded.Unmarshal(reader); err != nil {
		fail("%s: Hermes packet decode: %v", id, err)
	}
	require(reader.BytesLeft() == 0, "%s: Hermes packet left %d bytes", id, reader.BytesLeft())
	require(decoded.Version == 0, "%s: packet version", id)
	require(uint8(decoded.Type) == packetType, "%s: packet type", id)
	require(decoded.SecondaryHeader == secondary, "%s: secondary-header flag", id)
	require(decoded.Apid == apid, "%s: APID", id)
	require(uint8(decoded.SequenceFlags) == sequenceFlag, "%s: sequence flag", id)
	require(decoded.SequenceCount == sequenceCount, "%s: sequence count", id)
	require(bytes.Equal(decoded.Payload, payload), "%s: packet payload", id)

	emit(append(fields[:8], upperHex(external))...)
}

func verifyTC(fields []string) {
	requireFields(fields, 7)
	id := fields[1]
	scid := uint16(integer(fields[2]))
	vcid := uint8(integer(fields[3]))
	frameSequence := uint8(integer(fields[4]))
	payload := binary(fields[5])
	cadence := binary(fields[6])

	frame := ccsds.TcFrame{
		SpacecraftId:     scid,
		VirtualChannelId: vcid,
		FrameSequence:    frameSequence,
		Payload:          payload,
	}

	external := marshal(func(writer *serial.Writer) error { return frame.Marshal(writer, true) })
	requireEqual(id, cadence, external)

	decoded := ccsds.TcFrame{}
	reader := serial.NewReader(cadence)
	if err := decoded.Unmarshal(reader, true); err != nil {
		fail("%s: Hermes TC decode: %v", id, err)
	}
	require(decoded.SpacecraftId == scid, "%s: TC SCID", id)
	require(decoded.VirtualChannelId == vcid, "%s: TC VCID", id)
	require(decoded.FrameSequence == frameSequence, "%s: TC frame sequence", id)
	require(bytes.Equal(decoded.Payload, payload), "%s: TC payload", id)

	emit(append(fields[:6], upperHex(external))...)
}

func verifyTM(fields []string) {
	requireFields(fields, 13)
	id := fields[1]
	scid := uint16(integer(fields[2]))
	vcid := uint8(integer(fields[3]))
	mcfc := uint8(integer(fields[4]))
	vcfc := uint8(integer(fields[5]))
	syncFlag := uint8(integer(fields[6]))
	packetOrderFlag := uint8(integer(fields[7]))
	segmentLengthID := uint8(integer(fields[8]))
	fhp := uint16(integer(fields[9]))
	secondaryData := optionalBinary(fields[10])
	payload := binary(fields[11])
	cadence := binary(fields[12])

	frame := ccsds.TmFrame{
		Version:                  0,
		SpacecraftId:             scid,
		VirtualChannelId:         vcid,
		MasterChannelFrameCount:  mcfc,
		VirtualChannelFrameCount: vcfc,
		SyncFlag:                 syncFlag,
		PacketOrderFlag:          packetOrderFlag,
		SegmentLengthId:          segmentLengthID,
		FirstHeaderPointer:       fhp,
		SecondaryHeader: &ccsds.TmFrameSecondaryHeader{
			Version: 0,
			Data:    secondaryData,
		},
		Payload: payload,
	}

	external := marshal(func(writer *serial.Writer) error { return frame.Marshal(writer, false) })
	requireEqual(id, cadence, external)

	decoded := ccsds.TmFrame{}
	reader := serial.NewReader(cadence)
	if err := decoded.Unmarshal(reader, false); err != nil {
		fail("%s: Hermes TM decode: %v", id, err)
	}
	require(reader.BytesLeft() == 0, "%s: Hermes TM left %d bytes", id, reader.BytesLeft())
	require(decoded.Version == 0, "%s: TM version", id)
	require(decoded.SpacecraftId == scid, "%s: TM SCID", id)
	require(decoded.VirtualChannelId == vcid, "%s: TM VCID", id)
	require(decoded.MasterChannelFrameCount == mcfc, "%s: TM MCFC", id)
	require(decoded.VirtualChannelFrameCount == vcfc, "%s: TM VCFC", id)
	require(decoded.SyncFlag == syncFlag, "%s: TM sync flag", id)
	require(decoded.PacketOrderFlag == packetOrderFlag, "%s: TM packet-order flag", id)
	require(decoded.SegmentLengthId == segmentLengthID, "%s: TM segment-length ID", id)
	require(decoded.FirstHeaderPointer == fhp, "%s: TM FHP", id)
	require(bytes.Equal(decoded.Payload, payload), "%s: TM payload", id)

	if len(secondaryData) == 0 {
		require(decoded.SecondaryHeader == nil, "%s: unexpected TM secondary header", id)
	} else {
		require(decoded.SecondaryHeader != nil, "%s: missing TM secondary header", id)
		require(bytes.Equal(decoded.SecondaryHeader.Data, secondaryData), "%s: TM secondary header", id)
	}

	emit(append(fields[:12], upperHex(external))...)
}

func marshal(marshal func(*serial.Writer) error) []byte {
	writer := serial.NewWriter()
	if err := marshal(writer); err != nil {
		fail("Hermes marshal: %v", err)
	}
	return writer.Get()
}

func requireEqual(id string, cadence []byte, external []byte) {
	if !bytes.Equal(cadence, external) {
		fail("%s: bytes differ: cadence=%s hermes=%s", id, upperHex(cadence), upperHex(external))
	}
}

func requireFields(fields []string, count int) {
	if len(fields) != count {
		fail("expected %d fields, got %d in %q", count, len(fields), strings.Join(fields, "\\t"))
	}
}

func integer(value string) int {
	parsed, err := strconv.Atoi(value)
	if err != nil {
		fail("invalid integer %q: %v", value, err)
	}
	return parsed
}

func number(value string, values map[string]int) int {
	parsed, ok := values[value]
	if !ok {
		fail("invalid enumeration %q", value)
	}
	return parsed
}

func binary(value string) []byte {
	decoded, err := hex.DecodeString(value)
	if err != nil {
		fail("invalid hex %q: %v", value, err)
	}
	return decoded
}

func optionalBinary(value string) []byte {
	if value == "-" {
		return nil
	}
	return binary(value)
}

func upperHex(value []byte) string {
	return strings.ToUpper(hex.EncodeToString(value))
}

func emit(fields ...string) {
	fmt.Printf("RESULT\t%s\n", strings.Join(fields, "\t"))
}

func require(condition bool, format string, arguments ...any) {
	if !condition {
		fail(format, arguments...)
	}
}

func fail(format string, arguments ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", arguments...)
	os.Exit(1)
}
