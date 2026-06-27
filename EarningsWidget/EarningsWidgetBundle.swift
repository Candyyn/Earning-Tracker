//
//  EarningsWidgetBundle.swift
//  EarningsWidget
//
//  Created by Emil Magnusson on 2025-10-01.
//

import WidgetKit
import SwiftUI

@main
struct EarningsWidgetBundle: WidgetBundle {
    var body: some Widget {
        EarningsWidget()
        EarningsWidgetLiveActivity()
    }
}
