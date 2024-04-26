//
//  Process.swift
//  Heimdall Watch App
//
//  Created by 叶浩宁 on 2024-04-11.
//

import Foundation
import Dispatch
import NIOCore
import NIOPosix
import NIOSSH

// https://github.com/apple/swift-nio-ssh/tree/main/Sources/NIOSSHClient
enum SSHClientError: Swift.Error {
    case passwordAuthenticationNotSupported
    case commandExecFailed
    case invalidChannelType
    case invalidData
}

public final class SimplePubkeyDelegate {
    private var authRequest: NIOSSHUserAuthenticationOffer?

    public init(username: String, key: TyPrvKey) {
        self.authRequest = NIOSSHUserAuthenticationOffer(username: username, serviceName: "", offer: .privateKey(.init(privateKey: NIOSSHPrivateKey(p256Key: key))))
    }
}

@available(*, unavailable)
extension SimplePubkeyDelegate: Sendable {}

extension SimplePubkeyDelegate: NIOSSHClientUserAuthenticationDelegate {
    public func nextAuthenticationType(availableMethods: NIOSSHAvailableUserAuthenticationMethods, nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>) {
        if let authRequest = self.authRequest, availableMethods.contains(.publicKey) {
            // We need to nil out our copy because any future calls must return nil
            self.authRequest = nil
            nextChallengePromise.succeed(authRequest)
        } else {
            nextChallengePromise.succeed(nil)
        }
    }
}

final class ErrorHandler: ChannelInboundHandler {
    typealias InboundIn = Any

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("Error in pipeline: \(error)")
        context.close(promise: nil)
    }
}

final class AcceptAllHostKeysDelegate: NIOSSHClientServerAuthenticationDelegate {
    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        // Do not replicate this in your own code: validate host keys! This is a
        // choice made for expedience, not for any other reason.
        validationCompletePromise.succeed(())
    }
}

final class ExampleExecHandler: ChannelDuplexHandler {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData

    private var completePromise: EventLoopPromise<Int>?
    private var responsePromise: EventLoopPromise<ByteBuffer>?

    private let command: String

    init(command: String, completePromise: EventLoopPromise<Int>, responsePromise: EventLoopPromise<ByteBuffer>) {
        self.completePromise = completePromise
        self.responsePromise = responsePromise
        self.command = command
    }

    func handlerAdded(context: ChannelHandlerContext) {
        print("ExampleExecHandler.channelAdded()")
        context.channel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true).whenFailure { error in
            context.fireErrorCaught(error)
        }
    }

    func channelActive(context: ChannelHandlerContext) {
        print("ExampleExecHandler.channelActive()")
        let execRequest = SSHChannelRequestEvent.ExecRequest(command: self.command, wantReply: true)
        context.triggerUserOutboundEvent(execRequest).whenFailure { _ in
            context.close(promise: nil)
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        print("ExampleExecHandler.userInboundEventTriggered()")
        switch event {
        case let event as SSHChannelRequestEvent.ExitStatus:
            print("Receiving ExitStatus...")
            if let promise = self.completePromise {
                self.completePromise = nil
                print("ExitStatus promise succeed!")
                promise.succeed(event.exitStatus)
            }

        default:
            print("Receiving \(event)")
            context.fireUserInboundEventTriggered(event)
        }
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        print("ExampleExecHandler.handlerRemoved()")
        if let promise = self.completePromise {
            self.completePromise = nil
            promise.fail(SSHClientError.commandExecFailed)
        }
        if let promise = self.responsePromise {
            self.responsePromise = nil
            promise.fail(SSHClientError.commandExecFailed)
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        print("ExampleExecHandler.channelRead()")
        let data = self.unwrapInboundIn(data)

        guard case .byteBuffer(let bytes) = data.data else {
            fatalError("Unexpected read type")
        }

        switch data.type {
        case .channel:
            if let promise = self.responsePromise {
                self.responsePromise = nil
                promise.succeed(bytes)
            }
//            context.fireChannelRead(self.wrapInboundOut(bytes))
            return

        case .stdErr:
            // We just write to stderr directly, pipe channel can't help us here.
            bytes.withUnsafeReadableBytes { str in
                let rc = fwrite(str.baseAddress!, 1, str.count, stderr)
                precondition(rc == str.count)
            }

        default:
            fatalError("Unexpected message type")
        }
    }
}


class Process {
    let channel: Channel
    let group: MultiThreadedEventLoopGroup
    
    init(host: String, username: String, key: TyPrvKey) throws {
        print("Init process with\n host:\(host)\nusername:\(username)")
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        let bootstrap = ClientBootstrap(group: group)
            .channelInitializer { channel in
                channel.pipeline.addHandlers([NIOSSHHandler(role: .client(.init(userAuthDelegate: SimplePubkeyDelegate(username: username, key:key), serverAuthDelegate: AcceptAllHostKeysDelegate())), allocator: channel.allocator, inboundChildChannelInitializer: nil), ErrorHandler()])
            }
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)

        self.channel = try bootstrap.connect(host: host, port: 22).wait()
    }
    deinit {
        print("deinit process...")
        try! self.channel.close().wait()
        try! self.group.syncShutdownGracefully()
    }

    func exec(command:String="top -bn1 | grep \"Cpu(s)\" | awk \'{print $8}\'") throws -> (ByteBuffer, Int) {
        // We've been asked to exec.
        let exitStatusPromise = self.channel.eventLoop.makePromise(of: Int.self)
        let responsePromise = self.channel.eventLoop.makePromise(of: ByteBuffer.self)
        let childChannel: Channel = try! self.channel.pipeline.handler(type: NIOSSHHandler.self).flatMap { sshHandler in
            let promise = self.channel.eventLoop.makePromise(of: Channel.self)
            sshHandler.createChannel(promise) { childChannel, channelType in
                guard channelType == .session else {
                    return self.channel.eventLoop.makeFailedFuture(SSHClientError.invalidChannelType)
                }
                return childChannel.pipeline.addHandlers([ExampleExecHandler(command: command, completePromise: exitStatusPromise, responsePromise: responsePromise), ErrorHandler()])
            }
            return promise.futureResult
        }.wait()
        
        // Wait for the connection to close
        try childChannel.closeFuture.wait()
        let exitStatus = try! exitStatusPromise.futureResult.wait()
        let response = try! responsePromise.futureResult.wait()
        return (response, exitStatus)
    }
}
