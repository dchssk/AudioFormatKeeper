import CoreAudio
import Foundation

final class CoreAudioMonitor {
    private struct Registration {
        let objectID: AudioObjectID
        let address: AudioObjectPropertyAddress
        let listener: AudioObjectPropertyListenerBlock
    }

    private let queue = DispatchQueue(label: "org.audioformatkeeper.coreaudio-events", qos: .utility)
    private var registrations: [Registration] = []
    private var observedObjectSignature: [AudioObjectID] = []
    private var eventHandler: (() -> Void)?

    func rebind(devices: [AudioDeviceSnapshot], onChange: @escaping () -> Void) {
        let signature = devices.flatMap { [$0.id] + $0.outputStreams.map(\.id) }.sorted()
        eventHandler = onChange
        guard signature != observedObjectSignature || registrations.isEmpty else { return }

        stop(clearHandler: false)
        observedObjectSignature = signature

        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        register(systemObject, selector: kAudioHardwarePropertyDevices)
        register(systemObject, selector: kAudioHardwarePropertyDefaultOutputDevice)
        register(systemObject, selector: kAudioHardwarePropertyDefaultSystemOutputDevice)

        for device in devices {
            register(device.id, selector: kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
            register(device.id, selector: kAudioDevicePropertyNominalSampleRate)
            register(device.id, selector: kAudioDevicePropertyDeviceIsAlive)

            for stream in device.outputStreams {
                register(stream.id, selector: kAudioStreamPropertyPhysicalFormat)
                register(stream.id, selector: kAudioStreamPropertyVirtualFormat)
                register(stream.id, selector: kAudioStreamPropertyAvailablePhysicalFormats)
                register(stream.id, selector: kAudioStreamPropertyAvailableVirtualFormats)
            }
        }
    }

    func stop() {
        stop(clearHandler: true)
    }

    deinit {
        stop(clearHandler: true)
    }

    private func register(
        _ objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(objectID, &address) else { return }

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.eventHandler?()
        }
        let status = AudioObjectAddPropertyListenerBlock(objectID, &address, queue, listener)
        guard status == noErr else { return }
        registrations.append(Registration(objectID: objectID, address: address, listener: listener))
    }

    private func stop(clearHandler: Bool) {
        for registration in registrations {
            var address = registration.address
            AudioObjectRemovePropertyListenerBlock(
                registration.objectID,
                &address,
                queue,
                registration.listener
            )
        }
        registrations.removeAll()
        observedObjectSignature.removeAll()
        if clearHandler { eventHandler = nil }
    }
}
