import AudioToolbox
import CoreAudio
import Foundation

final class CoreAudioClient {
    private let systemObject = AudioObjectID(kAudioObjectSystemObject)

    func outputDevices() throws -> [AudioDeviceSnapshot] {
        let devicesAddress = propertyAddress(kAudioHardwarePropertyDevices)
        let deviceIDs: [AudioDeviceID] = try readArray(systemObject, address: devicesAddress)
        let defaultOutput = try? readScalar(
            systemObject,
            address: propertyAddress(kAudioHardwarePropertyDefaultOutputDevice),
            initialValue: AudioDeviceID(kAudioObjectUnknown)
        )

        return try deviceIDs.compactMap { deviceID in
            let streamsAddress = propertyAddress(
                kAudioDevicePropertyStreams,
                scope: kAudioDevicePropertyScopeOutput
            )
            let streamIDs: [AudioStreamID] = try readArray(deviceID, address: streamsAddress)
            guard !streamIDs.isEmpty else { return nil }

            let uid = try readString(
                deviceID,
                address: propertyAddress(kAudioDevicePropertyDeviceUID)
            )
            let name = (try? readString(
                deviceID,
                address: propertyAddress(kAudioObjectPropertyName)
            )) ?? uid
            let manufacturer = (try? readString(
                deviceID,
                address: propertyAddress(kAudioObjectPropertyManufacturer)
            )) ?? L10n.string("value.unknown_manufacturer")
            let transportValue = (try? readScalar(
                deviceID,
                address: propertyAddress(kAudioDevicePropertyTransportType),
                initialValue: UInt32(0)
            )) ?? 0
            let nominalAddress = propertyAddress(kAudioDevicePropertyNominalSampleRate)
            let nominalRate = try? readScalar(deviceID, address: nominalAddress, initialValue: Float64(0))
            let nominalRangesRaw: [AudioValueRange] = (try? readArray(
                deviceID,
                address: propertyAddress(kAudioDevicePropertyAvailableNominalSampleRates)
            )) ?? []
            let nominalRanges = nominalRangesRaw.map(SampleRateRange.init)

            let streams = try streamIDs.enumerated().map { index, streamID in
                try outputStream(
                    streamID,
                    index: index,
                    nominalRanges: nominalRanges,
                    currentNominalSampleRate: nominalRate
                )
            }

            return AudioDeviceSnapshot(
                id: deviceID,
                uid: uid,
                name: name,
                manufacturer: manufacturer,
                transport: transportName(transportValue),
                isDefaultOutput: deviceID == defaultOutput,
                nominalSampleRate: nominalRate,
                availableNominalSampleRates: nominalRanges,
                nominalSampleRateIsSettable: isSettable(deviceID, address: nominalAddress),
                outputStreams: streams
            )
        }
        .sorted {
            if $0.isDefaultOutput != $1.isDefaultOutput { return $0.isDefaultOutput }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func apply(rule: DeviceRule, to device: AudioDeviceSnapshot) -> ApplyResult {
        var result = ApplyResult()
        var resolvedTargets: [(StreamFormatTarget, AudioStreamSnapshot, FormatChoice)] = []

        for target in rule.targets {
            guard let stream = device.outputStreams.first(where: { $0.index == target.streamIndex }) else {
                result.issues.append(L10n.format(
                    "issue.stream_missing",
                    device.name,
                    target.streamIndex + 1
                ))
                continue
            }
            guard stream.isSettable(target.domain) else {
                result.issues.append(L10n.format(
                    "issue.format_read_only",
                    device.name,
                    target.streamIndex + 1,
                    target.domain.title
                ))
                continue
            }
            guard let available = stream.options(for: target.domain).first(where: {
                $0.semanticallyMatches(target.choice)
            }) else {
                result.issues.append(L10n.format(
                    "issue.format_not_advertised",
                    device.name,
                    target.domain.title
                ))
                continue
            }
            resolvedTargets.append((target, stream, available))
        }

        let targetRates = Set(resolvedTargets.map { Int($0.2.sampleRate.rounded()) })
        if targetRates.count > 1 {
            result.issues.append(L10n.format("issue.conflicting_rates", device.name))
            return result
        }

        if let resolvedRate = resolvedTargets.first?.2.sampleRate {
            let rateIsAdvertised = device.availableNominalSampleRates.isEmpty
                || device.availableNominalSampleRates.contains(where: { $0.contains(resolvedRate) })
            guard rateIsAdvertised else {
                result.issues.append(L10n.format(
                    "issue.rate_not_advertised",
                    device.name,
                    FormatChoice.formatSampleRate(resolvedRate)
                ))
                return result
            }

            if device.nominalSampleRateIsSettable,
               device.nominalSampleRate.map({ abs($0 - resolvedRate) >= 0.5 }) ?? true {
                do {
                    try setScalar(
                        device.id,
                        address: propertyAddress(kAudioDevicePropertyNominalSampleRate),
                        value: resolvedRate,
                        operation: L10n.string("operation.set_nominal_rate")
                    )
                    result.changesAttempted += 1
                } catch {
                    result.issues.append(error.localizedDescription)
                    return result
                }
            }
        }

        let orderedTargets = resolvedTargets.sorted {
            if $0.0.domain != $1.0.domain { return $0.0.domain == .physical }
            return $0.0.streamIndex < $1.0.streamIndex
        }

        for (target, stream, available) in orderedTargets {
            if stream.current(for: target.domain)?.semanticallyMatches(available) == true { continue }
            do {
                try setFormat(available, on: stream.id, domain: target.domain)
                result.changesAttempted += 1
            } catch {
                result.issues.append(error.localizedDescription)
            }
        }

        return result
    }

    private func outputStream(
        _ streamID: AudioStreamID,
        index: Int,
        nominalRanges: [SampleRateRange],
        currentNominalSampleRate: Double?
    ) throws -> AudioStreamSnapshot {
        let currentPhysicalAddress = propertyAddress(kAudioStreamPropertyPhysicalFormat)
        let currentVirtualAddress = propertyAddress(kAudioStreamPropertyVirtualFormat)
        let availablePhysicalAddress = propertyAddress(kAudioStreamPropertyAvailablePhysicalFormats)
        let availableVirtualAddress = propertyAddress(kAudioStreamPropertyAvailableVirtualFormats)

        let physicalDescription = try? readScalar(
            streamID,
            address: currentPhysicalAddress,
            initialValue: AudioStreamBasicDescription()
        )
        let virtualDescription = try? readScalar(
            streamID,
            address: currentVirtualAddress,
            initialValue: AudioStreamBasicDescription()
        )
        let physicalRanges: [AudioStreamRangedDescription] = (try? readArray(
            streamID,
            address: availablePhysicalAddress
        )) ?? []
        let virtualRanges: [AudioStreamRangedDescription] = (try? readArray(
            streamID,
            address: availableVirtualAddress
        )) ?? []
        let startingChannel = (try? readScalar(
            streamID,
            address: propertyAddress(kAudioStreamPropertyStartingChannel),
            initialValue: UInt32(1)
        )) ?? 1

        return AudioStreamSnapshot(
            id: streamID,
            index: index,
            startingChannel: startingChannel,
            physicalOptions: FormatCandidateBuilder.choices(
                streamIndex: index,
                domain: .physical,
                descriptions: physicalRanges,
                nominalRanges: nominalRanges,
                currentSampleRate: physicalDescription?.mSampleRate ?? currentNominalSampleRate
            ),
            virtualOptions: FormatCandidateBuilder.choices(
                streamIndex: index,
                domain: .virtual,
                descriptions: virtualRanges,
                nominalRanges: nominalRanges,
                currentSampleRate: virtualDescription?.mSampleRate ?? currentNominalSampleRate
            ),
            currentPhysical: physicalDescription.map {
                FormatChoice(streamIndex: index, domain: .physical, description: $0)
            },
            currentVirtual: virtualDescription.map {
                FormatChoice(streamIndex: index, domain: .virtual, description: $0)
            },
            physicalIsSettable: isSettable(streamID, address: currentPhysicalAddress),
            virtualIsSettable: isSettable(streamID, address: currentVirtualAddress)
        )
    }

    private func setFormat(_ choice: FormatChoice, on streamID: AudioStreamID, domain: FormatDomain) throws {
        let selector = domain == .physical
            ? kAudioStreamPropertyPhysicalFormat
            : kAudioStreamPropertyVirtualFormat
        var address = propertyAddress(selector)
        var format = choice.makeASBD()
        let size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectSetPropertyData(streamID, &address, 0, nil, size, &format)
        guard status == noErr else {
            throw CoreAudioError(
                operation: L10n.format("operation.set_format", domain.title),
                status: status
            )
        }
    }

    private func setScalar<T: BitwiseCopyable>(
        _ objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        value: T,
        operation: String
    ) throws {
        var address = address
        var value = value
        let status = AudioObjectSetPropertyData(
            objectID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<T>.size),
            &value
        )
        guard status == noErr else { throw CoreAudioError(operation: operation, status: status) }
    }

    private func readScalar<T: BitwiseCopyable>(
        _ objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        initialValue: T
    ) throws -> T {
        var address = address
        var value = initialValue
        var size = UInt32(MemoryLayout<T>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)
        guard status == noErr else {
            throw CoreAudioError(operation: L10n.string("operation.read_property"), status: status)
        }
        return value
    }

    private func readArray<T: BitwiseCopyable>(
        _ objectID: AudioObjectID,
        address: AudioObjectPropertyAddress
    ) throws -> [T] {
        var address = address
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &size)
        guard status == noErr else {
            throw CoreAudioError(operation: L10n.string("operation.read_property_size"), status: status)
        }
        guard size > 0 else { return [] }
        guard Int(size) % MemoryLayout<T>.stride == 0 else {
            throw CoreAudioError(
                operation: L10n.string("operation.read_malformed_array"),
                status: kAudioHardwareUnspecifiedError
            )
        }

        let count = Int(size) / MemoryLayout<T>.stride
        let rawPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<T>.alignment
        )
        defer { rawPointer.deallocate() }

        status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, rawPointer)
        guard status == noErr else {
            throw CoreAudioError(operation: L10n.string("operation.read_array"), status: status)
        }
        let pointer = rawPointer.bindMemory(to: T.self, capacity: count)
        return Array(UnsafeBufferPointer(start: pointer, count: count))
    }

    private func readString(
        _ objectID: AudioObjectID,
        address: AudioObjectPropertyAddress
    ) throws -> String {
        var address = address
        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else {
            throw CoreAudioError(operation: L10n.string("operation.read_string"), status: status)
        }
        return value as String
    }

    private func isSettable(_ objectID: AudioObjectID, address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable = DarwinBoolean(false)
        let status = AudioObjectIsPropertySettable(objectID, &address, &settable)
        return status == noErr && settable.boolValue
    }

    private func propertyAddress(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
    }

    private func transportName(_ value: UInt32) -> String {
        switch value {
        case kAudioDeviceTransportTypeBuiltIn: return L10n.string("transport.built_in")
        case kAudioDeviceTransportTypeAggregate: return L10n.string("transport.aggregate")
        case kAudioDeviceTransportTypeVirtual: return L10n.string("transport.virtual")
        case kAudioDeviceTransportTypePCI: return L10n.string("transport.pci")
        case kAudioDeviceTransportTypeUSB: return L10n.string("transport.usb")
        case kAudioDeviceTransportTypeFireWire: return L10n.string("transport.firewire")
        case kAudioDeviceTransportTypeBluetooth: return L10n.string("transport.bluetooth")
        case kAudioDeviceTransportTypeBluetoothLE: return L10n.string("transport.bluetooth_le")
        case kAudioDeviceTransportTypeHDMI: return L10n.string("transport.hdmi")
        case kAudioDeviceTransportTypeDisplayPort: return L10n.string("transport.displayport")
        case kAudioDeviceTransportTypeAirPlay: return L10n.string("transport.airplay")
        case kAudioDeviceTransportTypeAVB: return L10n.string("transport.avb")
        case kAudioDeviceTransportTypeThunderbolt: return L10n.string("transport.thunderbolt")
        default: return value == 0 ? L10n.string("transport.unknown") : fourCC(value)
        }
    }
}
