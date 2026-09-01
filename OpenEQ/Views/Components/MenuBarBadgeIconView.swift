//
//  MenuBarBadgeIconView.swift
//  OpenEQ
//
//  Created by Ozan
//

import SwiftUI

struct MenuBarBadgeIconView: View {
    @Bindable var viewModel: OpenEQViewModel
    
    var body: some View {
        if !viewModel.isEnabled {
            Image(systemName: "waveform.slash")
        } else if viewModel.isSystemEQActive {
            Image(systemName: "waveform.circle.fill")
        } else {
            Image(systemName: "waveform")
        }
    }
}
