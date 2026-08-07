import Foundation
import TPCircularBuffer

final class RingBuffer: @unchecked Sendable {
    var buffer = TPCircularBuffer()

    init(capacity: UInt32) {
        _TPCircularBufferInit(&buffer, capacity, MemoryLayout<TPCircularBuffer>.size)
    }

    deinit {
        TPCircularBufferCleanup(&buffer)
    }

    func clear() {
        TPCircularBufferClear(&buffer)
    }

    @discardableResult
    func write(_ data: UnsafeRawPointer, length: UInt32) -> Bool {
        TPCircularBufferProduceBytes(&buffer, data, length)
    }

    func read(into pointer: UnsafeMutableRawPointer, length: UInt32) -> UInt32 {
        var available: UInt32 = 0
        guard let tail = TPCircularBufferTail(&buffer, &available) else { return 0 }
        let toRead = min(length, available)
        memcpy(pointer, tail, Int(toRead))
        TPCircularBufferConsume(&buffer, toRead)
        return toRead
    }

    func availableBytes() -> UInt32 {
        var available: UInt32 = 0
        _ = TPCircularBufferTail(&buffer, &available)
        return available
    }
}
