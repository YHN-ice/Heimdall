//
//  CircularIndicatorView.swift
//  Heimdall Watch App
//
//  Created by 叶浩宁 on 2024-04-11.
//

import SwiftUI
struct VerticalBarView: View {
    @State private var hist = (0, [1.0,0.1,0.33,1.0])
    @Binding public var process:Process?
    
    var body: some View {
        ScrollView{
            Text(convert(hist:hist))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        Button("exec") {
            print("exec clicked")
            Task {
                if let process = self.process {
                    print("process.exec() called")
                    var (buf, _) = try! process.exec()
                    let usage = 1 - Double(buf.readString(length: buf.readableBytes)!.trimmingCharacters(in: .whitespacesAndNewlines))!/100.0
                    print("received response:\(usage)")
                    hist.1[hist.0%hist.1.count] = usage
                    hist.0 += 1
                } else {
                    print("please create process first")
                }
            }
        }

    }
}

func convert(hist:(Int, [Double])) -> String {
    let (idx, data) = hist
    let len = data.count
    return (idx..<idx+len).map{id in
        String.init(repeating: "-", count: Int(data[id%len] * 17))
    }.joined(separator: "\n")
}
