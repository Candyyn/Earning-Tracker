//
//  MainView.swift
//  Tracker
//
//  Created by Emil Magnusson on 2025-08-11.
//
import SwiftUI

struct MainView: View {
    @ObservedObject var vm: EarningsViewModel
    
    @State private var lastEarnings: Double = 0
    @State private var floatingText: String? = nil
    @State private var animateFloating = false
    @State private var randomXOffset: CGFloat = 0
    @State private var randomXOffsetStart: CGFloat = 0
    @State private var randomYOffset: CGFloat = 0

    
    var currencyFormater: NumberFormatter = {
            var formatter = NumberFormatter()
            
            formatter.numberStyle = .currency
            formatter.currencySymbol = "kr"
            
            return formatter
        }()
    

    
    var body: some View {
        ZStack {
            VStack {
                
                SecondProgressBar()
                    .frame(height: 30)
                Text("This Month's Earnings")
                    .font(.headline)
                ZStack {
                    Text("\(currencyFormater.string(from: vm.currentEarnings as NSNumber)!)")
                        .contentTransition(.numericText(value: vm.currentEarnings))
                        .font(.largeTitle)
                        .bold()
                        .animation(.default, value: vm.currentEarnings)
                    
                }
                
                Text("\(currencyFormater.string(from: vm.hourlyRate(for: Date()) as NSNumber) ?? "")/h \(vm.isOnBreak() ? " - Break" : "")")
                    .contentTransition(.numericText(value: vm.hourlyRate(for: Date())))
                    .animation(.default, value: vm.currentEarnings)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .ignoresSafeArea()
        }
        .onAppear {
            lastEarnings = vm.currentEarnings
        }
        .onChange(of: vm.currentEarnings) { oldvalue, newValue in
                    let diff = newValue - lastEarnings
                    if diff != 0 {
                        let diffText = "+\(currencyFormater.string(from: diff as NSNumber) ?? "")"
                        floatingText = diffText
                        randomXOffset = CGFloat.random(in: -40...40)
                        //randomXOffsetStart = CGFloat.random(in: -80...80)
                        randomYOffset = CGFloat.random(in: -80 ... -40)
                    }
                    lastEarnings = newValue
                }
    }
}

