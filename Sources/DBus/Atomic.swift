//
//  Atomic.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 10/21/18.
//

import Foundation
import Dispatch

/// A thread-safe atomic value with concurrent reads and safe writes.
internal final class Atomic <T> {
    
    private var value: T
    
    private let queue: DispatchQueue
    
    public init(_ value: T) {
        
        self.value = value
        self.queue = DispatchQueue(label: "Atomic \(T.self) Queue", qos: .default, attributes: [.concurrent])
    }
    
    public func read() -> T {
        
        return queue.sync { [unowned self] in return self.value }
    }
    
    /// Async write
    public func write(_ block: @escaping (inout T) -> ()) {
        
        queue.async(flags: .barrier) { [weak self] in
            
            guard let atomic = self else { return }
            
            // modify value
            block(&atomic.value)
        }
    }
    
    public func write(_ newValue: T) {
        
        self.write { $0 = newValue }
    }
}

extension Atomic where T: ExpressibleByNilLiteral {
    
    /// Initialize value to `nil`.
    convenience init() {
        
        self.init(nil)
    }
    
    /// Set value to `nil`.
    func clear() {
        
        self.write(nil)
    }
}
