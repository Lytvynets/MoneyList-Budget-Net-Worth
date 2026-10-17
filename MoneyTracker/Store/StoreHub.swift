import Foundation
import SwiftData
import CoreData

/// Owns the single SwiftData container shared by the app, App Intents and upkeep jobs.
enum StoreHub {

    enum Mode: Equatable {
        /// Normal: on-device store mirrored to the person's private iCloud.
        case cloud
        /// iCloud mirroring failed to start; the same on-device store opened without sync.
        case localOnly
        /// Nothing could be opened; changes are kept in memory for this session only.
        case memoryOnly
    }

    static let cloudContainerID = "iCloud.com.MoneyListl.VladLytvynets.dev"

    static let schema = Schema([
        Account.self,
        TransactionCategory.self,
        Transaction.self,
        Budget.self,
        Asset.self,
        AssetTransaction.self,
        Goal.self,
        UserProfile.self,
        RecurringRule.self,
        Attachment.self
    ])

    private(set) static var mode: Mode = .cloud
    private(set) static var openError: String?

    static let container: ModelContainer = open()

    private static func open() -> ModelContainer {
        do {
            // Same default store file and CloudKit setup as version 1, so existing data opens as-is.
            let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            mode = .cloud
            return container
        } catch {
            openError = error.localizedDescription
            print("Money List: cloud store failed to open — \(error)")
        }
        do {
            let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            mode = .localOnly
            return container
        } catch {
            openError = error.localizedDescription
            print("Money List: local store failed to open — \(error)")
        }
        do {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            mode = .memoryOnly
            return container
        } catch {
            fatalError("Money List: no store could be created — \(error)")
        }
    }

    /// A fresh context for background-ish work (intents, imports).
    static func makeContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }
}

#if DEBUG
/// Development helper: creates every record type and field in the CloudKit
/// *development* schema so it can be deployed to production from the
/// CloudKit Console. Uses a throw-away store file, never the live one.
enum CloudSchemaPusher {

    static func push() -> String {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("schema-push-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }

            let description = NSPersistentStoreDescription(url: folder.appendingPathComponent("schema.store"))
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: StoreHub.cloudContainerID)
            description.shouldAddStoreAsynchronously = false

            guard let model = NSManagedObjectModel.makeManagedObjectModel(for: [
                Account.self, TransactionCategory.self, Transaction.self, Budget.self, Asset.self,
                AssetTransaction.self, Goal.self, UserProfile.self, RecurringRule.self, Attachment.self
            ]) else {
                return "Could not build the managed object model."
            }

            var loadError: Error?
            let container = NSPersistentCloudKitContainer(name: "SchemaPush", managedObjectModel: model)
            container.persistentStoreDescriptions = [description]
            container.loadPersistentStores { _, error in loadError = error }
            if let loadError { return "Store failed to load: \(loadError.localizedDescription)" }

            try container.initializeCloudKitSchema()
            for store in container.persistentStoreCoordinator.persistentStores {
                try container.persistentStoreCoordinator.remove(store)
            }
            return "Schema pushed to the CloudKit development environment. Deploy it to Production in the CloudKit Console."
        } catch {
            return "Schema push failed: \(error.localizedDescription)"
        }
    }
}
#endif
