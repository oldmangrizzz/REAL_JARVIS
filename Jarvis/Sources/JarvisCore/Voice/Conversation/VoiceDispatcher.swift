import Foundation

public enum VoiceAction {
    case speak(String)
    case stop
}

public protocol VoiceDispatcherConsumer {
    func dispatch(_ action: VoiceAction)
}

public final class VoiceDispatcher {
    private var consumers: [VoiceDispatcherConsumer] = []
    
    public init() {}
    
    public func addConsumer(_ consumer: VoiceDispatcherConsumer) {
        consumers.append(consumer)
    }
    
    public func dispatch(_ action: VoiceAction) {
        for consumer in consumers {
            consumer.dispatch(action)
        }
    }
}