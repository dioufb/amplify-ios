//
// Copyright 2018-2020 Amazon.com,
// Inc. or its affiliates. All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import XCTest

@testable import Amplify
@testable import AmplifyTestCommon
@testable import AWSPluginsCore
@testable import AWSDataStoreCategoryPlugin

class SyncEventEmitterTests: XCTestCase {
    var initialSyncOrchestrator: MockAWSInitialSyncOrchestrator?
    var reconciliationQueue: MockAWSIncomingEventReconciliationQueue?
    var syncEventEmitter: SyncEventEmitter?

    override func setUp() {
        super.setUp()

        ModelRegistry.reset()
        MockModelReconciliationQueue.reset()
        MockAWSInitialSyncOrchestrator.reset()
    }

    /// - Given: A SyncEventEmitter
    /// - When:
    ///    - One model is registered
    ///    - Perform an initial sync
    /// - Then:
    ///    - One modelSynced event should be received
    ///    - One syncQueriesReady event should be received
    func testModelSyncedAndSyncQueriesReadyWithOneModelRegistered() throws {
        let modelSyncedReceived = expectation(description: "modelSynced received")
        let syncQueriesReadyReceived = expectation(description: "syncQueriesReady received")

        ModelRegistry.register(modelType: Post.self)
        let testPost = Post(id: "1", title: "post1", content: "content", createdAt: .now())
        let anyPost = AnyModel(testPost)
        let anyPostMetadata = MutationSyncMetadata(id: "1",
                                               deleted: false,
                                               lastChangedAt: Int(Date().timeIntervalSince1970),
                                               version: 1)
        let anyPostMutationSync = MutationSync<AnyModel>(model: anyPost, syncMetadata: anyPostMetadata)
        let postMutationEvent = try MutationEvent(untypedModel: testPost, mutationType: .create)

        let listener = Amplify.Hub.publisher(for: .dataStore).sink { payload in
            switch payload.eventName {
            case HubPayload.EventName.DataStore.modelSynced:
                guard let modelSyncedEventPayload = payload.data as? ModelSyncedEvent else {
                    XCTFail("Couldn't cast payload data as ModelSyncedEvent")
                    return
                }
                XCTAssertEqual(modelSyncedEventPayload.modelName, "Post")
                XCTAssertTrue(modelSyncedEventPayload.isFullSync)
                XCTAssertFalse(modelSyncedEventPayload.isDeltaSync)
                XCTAssertEqual(modelSyncedEventPayload.added, 1)
                XCTAssertEqual(modelSyncedEventPayload.updated, 0)
                XCTAssertEqual(modelSyncedEventPayload.deleted, 0)
                modelSyncedReceived.fulfill()
            case HubPayload.EventName.DataStore.syncQueriesReady:
                syncQueriesReadyReceived.fulfill()
            default:
                break
            }
        }

        reconciliationQueue = MockAWSIncomingEventReconciliationQueue(modelTypes: [Post.self],
                                                                          api: nil,
                                                                          storageAdapter: nil,
                                                                          auth: nil)

        initialSyncOrchestrator = MockAWSInitialSyncOrchestrator(dataStoreConfiguration: .default,
                                                                 api: nil,
                                                                 reconciliationQueue: nil,
                                                                 storageAdapter: nil)

        syncEventEmitter = SyncEventEmitter(initialSyncOrchestrator: initialSyncOrchestrator,
                                                reconciliationQueue: reconciliationQueue)

        initialSyncOrchestrator?.initialSyncOrchestratorTopic.send(.started(modelType: Post.self, syncType: .fullSync))
        initialSyncOrchestrator?.initialSyncOrchestratorTopic.send(.mutationSync(anyPostMutationSync))
        initialSyncOrchestrator?.initialSyncOrchestratorTopic.send(.finished(modelType: Post.self))

        reconciliationQueue?.incomingEventSubject.send(.mutationEventApplied(postMutationEvent))

        waitForExpectations(timeout: 1)
        syncEventEmitter = nil
        listener.cancel()
    }

    /// - Given: A SyncEventEmitter
    /// - When:
    ///    - Two model are registered
    ///    - Perform an initial sync
    /// - Then:
    ///    - Two modelSynced event should be received
    ///    - One syncQueriesReady event should be received
    func testModelSyncedAndSyncQueriesReadyWithTwoModelsRegistered() throws {
        let modelSyncedReceived = expectation(description: "modelSynced received")
        let syncQueriesReadyReceived = expectation(description: "syncQueriesReady received")

        ModelRegistry.register(modelType: Post.self)
        ModelRegistry.register(modelType: Comment.self)
        let testPost = Post(id: "1", title: "post1", content: "content", createdAt: .now())
        let anyPost = AnyModel(testPost)
        let anyPostMetadata = MutationSyncMetadata(id: "1",
                                               deleted: false,
                                               lastChangedAt: Int(Date().timeIntervalSince1970),
                                               version: 1)
        let anyPostMutationSync = MutationSync<AnyModel>(model: anyPost, syncMetadata: anyPostMetadata)
        let postMutationEvent = try MutationEvent(untypedModel: testPost, mutationType: .create)

        let testComment = Comment(id: "1", content: "content", createdAt: .now(), post: testPost)
        let anyComment = AnyModel(testComment)
        let anyCommentMetadata = MutationSyncMetadata(id: "1",
                                               deleted: false,
                                               lastChangedAt: Int(Date().timeIntervalSince1970),
                                               version: 1)
        let anyCommentMutationSync = MutationSync<AnyModel>(model: anyComment, syncMetadata: anyCommentMetadata)
        let commentMutationEvent = try MutationEvent(untypedModel: testComment, mutationType: .create)

        var modelSyncedEventPayloads = [ModelSyncedEvent]()
        let listener = Amplify.Hub.publisher(for: .dataStore).sink { payload in
            switch payload.eventName {
            case HubPayload.EventName.DataStore.modelSynced:
                guard let modelSyncedEventPayload = payload.data as? ModelSyncedEvent else {
                    XCTFail("Couldn't cast payload data as ModelSyncedEvent")
                    return
                }
                modelSyncedEventPayloads.append(modelSyncedEventPayload)

                if modelSyncedEventPayloads.count == 2 {
                    XCTAssertEqual(modelSyncedEventPayloads[0].modelName, "Post")
                    XCTAssertEqual(modelSyncedEventPayloads[1].modelName, "Comment")
                    XCTAssertTrue(modelSyncedEventPayloads[0].isFullSync)
                    XCTAssertTrue(modelSyncedEventPayloads[1].isFullSync)
                    XCTAssertFalse(modelSyncedEventPayloads[0].isDeltaSync)
                    XCTAssertFalse(modelSyncedEventPayloads[1].isDeltaSync)
                    XCTAssertEqual(modelSyncedEventPayloads[0].added, 1)
                    XCTAssertEqual(modelSyncedEventPayloads[1].added, 1)
                    XCTAssertEqual(modelSyncedEventPayloads[0].updated, 0)
                    XCTAssertEqual(modelSyncedEventPayloads[1].updated, 0)
                    XCTAssertEqual(modelSyncedEventPayloads[0].deleted, 0)
                    XCTAssertEqual(modelSyncedEventPayloads[1].deleted, 0)
                    modelSyncedReceived.fulfill()
                }
            case HubPayload.EventName.DataStore.syncQueriesReady:
                syncQueriesReadyReceived.fulfill()
            default:
                break
            }
        }

        let syncableModelTypes = ModelRegistry.models.filter { $0.schema.isSyncable }

        reconciliationQueue = MockAWSIncomingEventReconciliationQueue(modelTypes: syncableModelTypes,
                                                                          api: nil,
                                                                          storageAdapter: nil,
                                                                          auth: nil)

        initialSyncOrchestrator = MockAWSInitialSyncOrchestrator(dataStoreConfiguration: .default,
                                                                 api: nil,
                                                                 reconciliationQueue: nil,
                                                                 storageAdapter: nil)

        syncEventEmitter = SyncEventEmitter(initialSyncOrchestrator: initialSyncOrchestrator,
                                                reconciliationQueue: reconciliationQueue)

        initialSyncOrchestrator?.initialSyncOrchestratorTopic.send(.started(modelType: Post.self, syncType: .fullSync))
        initialSyncOrchestrator?.initialSyncOrchestratorTopic.send(.mutationSync(anyPostMutationSync))
        initialSyncOrchestrator?.initialSyncOrchestratorTopic.send(.finished(modelType: Post.self))

        initialSyncOrchestrator?.initialSyncOrchestratorTopic.send(.started(modelType: Comment.self, syncType: .fullSync))
        initialSyncOrchestrator?.initialSyncOrchestratorTopic.send(.mutationSync(anyCommentMutationSync))
        initialSyncOrchestrator?.initialSyncOrchestratorTopic.send(.finished(modelType: Comment.self))

        reconciliationQueue?.incomingEventSubject.send(.mutationEventApplied(postMutationEvent))
        reconciliationQueue?.incomingEventSubject.send(.mutationEventApplied(commentMutationEvent))

        waitForExpectations(timeout: 1)
        syncEventEmitter = nil
        listener.cancel()
    }
}