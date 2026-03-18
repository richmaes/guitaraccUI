//
//  Item.swift
//  guitaraccUI
//
//  Created by Rich Maes on 3/17/26.
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
