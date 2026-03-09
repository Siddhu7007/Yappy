//
//  Item.swift
//  Yappy
//
//  Created by Siddhant Daigavane on 09/03/26.
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
