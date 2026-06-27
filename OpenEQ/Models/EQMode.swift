//
//  EQMode.swift
//  OpenEQ
//
//  Created by Codex on 26.06.2026.
//

import Foundation

enum EQMode: String, CaseIterable, Codable, Identifiable {
    case graphic
    case parametric

    var id: String { rawValue }

    var title: String {
        switch self {
        case .graphic:
            return "Graphic"
        case .parametric:
            return "Parametric"
        }
    }
}
