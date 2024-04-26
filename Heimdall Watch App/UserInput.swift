//
//  UserInput.swift
//  Heimdall Watch App
//
//  Created by 叶浩宁 on 2024-04-26.
//

import SwiftUI
struct UserInput: View {
    
    @Binding var username: String
    @Binding var host: String

    var body: some View {
        ScrollView{
            TextField(
                "User Name",
                text: $username
            )
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            
            TextField(
                "HostIP",
                text: $host
            )
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            
            Text(String("username:\(username)\nhostip:\(host)"))
        }
    }
}
