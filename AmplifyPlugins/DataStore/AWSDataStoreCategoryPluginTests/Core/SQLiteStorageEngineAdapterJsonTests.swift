//
// Copyright 2018-2020 Amazon.com,
// Inc. or its affiliates. All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import XCTest

@testable import Amplify
@testable import AmplifyTestCommon
@testable import AWSDataStoreCategoryPlugin

import Foundation
import SQLite

class SQLiteStorageEngineAdapterJsonTests: XCTestCase {

    var connection: Connection!
    var storageEngine: StorageEngine!
    var storageAdapter: SQLiteStorageEngineAdapter!

    // MARK: - Lifecycle

    override func setUp() {
        super.setUp()
        sleep(2)
        Amplify.reset()
        Amplify.Logging.logLevel = .warn

        let validAPIPluginKey = "MockAPICategoryPlugin"
        let validAuthPluginKey = "MockAuthCategoryPlugin"
        do {
            connection = try Connection(.inMemory)
            storageAdapter = try SQLiteStorageEngineAdapter(connection: connection)
            try storageAdapter.setUp(schemas: StorageEngine.systemModelSchemas)

            let syncEngine = try RemoteSyncEngine(storageAdapter: storageAdapter,
                                                  dataStoreConfiguration: .default)
            storageEngine = StorageEngine(storageAdapter: storageAdapter,
                                          dataStoreConfiguration: .default,
                                          syncEngine: syncEngine,
                                          validAPIPluginKey: validAPIPluginKey,
                                          validAuthPluginKey: validAuthPluginKey)
        } catch {
            XCTFail(String(describing: error))
            return
        }

        let dataStorePublisher = DataStorePublisher()
        let dataStorePlugin = AWSDataStorePlugin(modelRegistration: TestJsonModelRegistration(),
                                                 storageEngine: storageEngine,
                                                 dataStorePublisher: dataStorePublisher,
                                                 validAPIPluginKey: validAPIPluginKey,
                                                 validAuthPluginKey: validAuthPluginKey)

        let dataStoreConfig = DataStoreCategoryConfiguration(plugins: [
            "awsDataStorePlugin": true
        ])
        let amplifyConfig = AmplifyConfiguration(dataStore: dataStoreConfig)

        do {

            try Amplify.add(plugin: dataStorePlugin)
            try Amplify.configure(amplifyConfig)
        } catch {
            XCTFail(String(describing: error))
            return
        }
    }

    /// - Given: a list a `Post` instance
    /// - When:
    ///   - the `save(post)` is called
    /// - Then:
    ///   - call `query(Post)` to check if the model was correctly inserted
    func testInsertPost() {
        let expectation = self.expectation(
            description: "it should save and select a Post from the database")

        // insert a post
        let post = ["title": "title",
                    "content": "content information"] as [String: JSONValue]
        let model = DynamicModel(values: post)
        storageAdapter.save(model, schema: ModelRegistry.modelSchema(from: "Post")!) { saveResult in
            switch saveResult {
            case .success:
                self.storageAdapter.query(
                    DynamicModel.self,
                    schema: ModelRegistry.modelSchema(from: "Post")!) { queryResult in
                        switch queryResult {
                        case .success(let posts):
                            XCTAssert(posts.count == 1)
                            if let savedPost = posts.first {
                                XCTAssert(model.id == savedPost.id)
                            }
                            expectation.fulfill()
                        case .failure(let error):
                            XCTFail(String(describing: error))
                            expectation.fulfill()
                        }
                }
            case .failure(let error):
                XCTFail(String(describing: error))
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5)
    }

    /// - Given: a list a `Post` instance
    /// - When:
    ///   - the `save(post)` is called
    /// - Then:
    ///   - call `query(Post, where: title == post.title)` to check
    ///   if the model was correctly inserted using a predicate
    func testInsertPostAndSelectByTitle() {
        let expectation = self.expectation(
            description: "it should save and select a Post from the database")

        // insert a post
        let post = Post(title: "title", content: "content", createdAt: .now())
        storageAdapter.save(post) { saveResult in
            switch saveResult {
            case .success:
                let predicate = Post.keys.title == post.title
                self.storageAdapter.query(Post.self, predicate: predicate) { queryResult in
                    switch queryResult {
                    case .success(let posts):
                        XCTAssertEqual(posts.count, 1)
                        if let savedPost = posts.first {
                            XCTAssert(post.id == savedPost.id)
                            XCTAssert(post.title == savedPost.title)
                            XCTAssert(post.content == savedPost.content)
                            XCTAssertEqual(post.createdAt.iso8601String, savedPost.createdAt.iso8601String)
                        }
                        expectation.fulfill()
                    case .failure(let error):
                        XCTFail(String(describing: error))
                        expectation.fulfill()
                    }
                }
            case .failure(let error):
                XCTFail(String(describing: error))
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5)
    }


}