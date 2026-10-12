//
//  Item.swift
//  thingsdiary-mac
//
//  Created by Mikhail Kalinin on 12.10.2026.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
