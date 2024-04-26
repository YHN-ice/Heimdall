//
//  ContentView.swift
//  Heimdall Watch App
//
//  Created by 叶浩宁 on 2024-04-11.
//

import SwiftUI

func showKey() -> String {
    if let (_, pubkeyDesc) = loadKey() {
        return pubkeyDesc
    } else {
        print("key not found creating new one...")
        storeKey()
        guard let (_, pubkey) = loadKey() else {
            fatalError("create key failed")
        }
        return pubkey
    }
}

func destroyKey() {
    deleteKey()
}

struct ContentView: View {
    @State private var process:Process? = nil
    @State private var pubkey:String? = nil
    
    var body: some View {
        ScrollView {
//            Image(systemName: "globe")
//                .imageScale(.large)
//                .foregroundStyle(.tint)
            VerticalBarView(process: $process)
            Button("Creat Process") {
                if let (prvKey, _) = loadKey(), self.process==nil {
                    print("trying to create process")
                    self.process = try! Process(host: "host", username: "username", key: prvKey)
                } else if self.process != nil {
                    print("process already existed")
                } else {
                    print("please create key first")
                }
            }
            Button("Creat or Show Key") {
                let showedKey = showKey()
                print(showedKey)
                guard self.pubkey != nil else {
                    self.pubkey = showedKey
                    return
                }
            }
            Button("Destroy Key") {
                destroyKey()
                self.pubkey = nil
            }
            Text(self.pubkey ?? "key placeholder")
            
        }
    }
}


#Preview {
    ContentView()
}
