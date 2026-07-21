import Foundation

enum BandUploadPhase: String, Codable, Sendable {
    case preparing
    case uploading
    case processing
    case ready
    case failed
    case cancelled

    var title: String {
        switch self {
        case .preparing: "Preparing"
        case .uploading: "Uploading"
        case .processing: "Processing"
        case .ready: "Ready"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }
}

struct BandUploadTransfer: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let bandID: UUID
    let projectID: UUID?
    let localFileURL: URL
    let kind: BandAssetKind
    let contentType: String
    let byteSize: Int64
    var assetID: UUID?
    var taskIdentifier: Int?
    var progress: Double
    var phase: BandUploadPhase
    var failureMessage: String?
}

@MainActor
final class MediaUploadManager: NSObject, ObservableObject {
    @Published private(set) var transfers: [BandUploadTransfer] = []

    private let provider: any BandMediaProviding
    private let persistenceKey = "stew.band.uploads.v1"
    private lazy var session: URLSession = {
        let identifier = "com.stewuniversity.ios.band-media"
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.allowsCellularAccess = true
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    init(provider: (any BandMediaProviding)? = nil) {
        self.provider = provider ?? BandAPIClient.shared
        super.init()
        restore()
        Task { await reconnectTasks() }
    }

    @discardableResult
    func enqueue(
        fileURL: URL,
        bandID: UUID,
        projectID: UUID?,
        kind: BandAssetKind,
        contentType: String
    ) async -> UUID? {
        let transferID = UUID()
        do {
            let temporaryURL = try copyToManagedTemporaryFile(fileURL, transferID: transferID)
            let byteSize = try temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            var transfer = BandUploadTransfer(
                id: transferID,
                bandID: bandID,
                projectID: projectID,
                localFileURL: temporaryURL,
                kind: kind,
                contentType: contentType,
                byteSize: Int64(byteSize),
                progress: 0,
                phase: .preparing
            )
            transfers.append(transfer)
            persist()

            let slot = try await provider.createUploadSlot(
                bandID: bandID,
                projectID: projectID,
                kind: kind,
                filename: fileURL.lastPathComponent,
                contentType: contentType,
                byteSize: Int64(byteSize)
            )
            transfer.assetID = slot.asset.id
            var request = URLRequest(url: slot.uploadURL)
            request.httpMethod = "PUT"
            slot.requiredHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            let task = session.uploadTask(with: request, fromFile: temporaryURL)
            transfer.taskIdentifier = task.taskIdentifier
            transfer.phase = .uploading
            replace(transfer)
            task.resume()
            return transferID
        } catch {
            fail(transferID, message: error.localizedDescription)
            return nil
        }
    }

    func cancel(_ transferID: UUID) {
        guard let transfer = transfers.first(where: { $0.id == transferID }) else { return }
        session.getAllTasks { tasks in
            tasks.first(where: { $0.taskIdentifier == transfer.taskIdentifier })?.cancel()
        }
        update(transferID) {
            $0.phase = .cancelled
            $0.failureMessage = nil
        }
    }

    func retry(_ transferID: UUID) async {
        guard let transfer = transfers.first(where: { $0.id == transferID }),
              FileManager.default.fileExists(atPath: transfer.localFileURL.path) else {
            fail(transferID, message: "The temporary file is no longer available.")
            return
        }
        remove(transferID, deletingFile: false)
        _ = await enqueue(
            fileURL: transfer.localFileURL,
            bandID: transfer.bandID,
            projectID: transfer.projectID,
            kind: transfer.kind,
            contentType: transfer.contentType
        )
    }

    func remove(_ transferID: UUID, deletingFile: Bool = true) {
        guard let transfer = transfers.first(where: { $0.id == transferID }) else { return }
        transfers.removeAll { $0.id == transferID }
        if deletingFile { try? FileManager.default.removeItem(at: transfer.localFileURL) }
        persist()
    }

    func transfer(for assetID: UUID) -> BandUploadTransfer? {
        transfers.first { $0.assetID == assetID }
    }

    func waitUntilReady(_ transferID: UUID) async throws -> UUID {
        for _ in 0..<180 {
            guard let transfer = transfers.first(where: { $0.id == transferID }) else {
                throw BandAPIError.transport("The upload is no longer available.")
            }
            switch transfer.phase {
            case .ready:
                guard let assetID = transfer.assetID else { throw BandAPIError.invalidResponse }
                return assetID
            case .failed, .cancelled:
                throw BandAPIError.transport(transfer.failureMessage ?? "The upload did not finish.")
            case .preparing, .uploading, .processing:
                try await Task.sleep(for: .seconds(1))
            }
        }
        throw BandAPIError.transport("The upload is still processing. Try again shortly.")
    }

    private func finishUpload(taskIdentifier: Int) async {
        guard let transfer = transfers.first(where: { $0.taskIdentifier == taskIdentifier }),
              let assetID = transfer.assetID else { return }
        update(transfer.id) { $0.phase = .processing; $0.progress = 1 }
        do {
            var asset = try await provider.completeUpload(assetID: assetID)
            for _ in 0..<18 where asset.status == .processing || asset.status == .pending {
                try await Task.sleep(for: .seconds(2))
                asset = try await provider.fetchAsset(assetID: assetID)
            }
            if asset.status == .ready {
                update(transfer.id) { $0.phase = .ready; $0.failureMessage = nil }
                try? FileManager.default.removeItem(at: transfer.localFileURL)
            } else {
                fail(transfer.id, message: asset.failureReason ?? "Media validation did not finish.")
            }
        } catch {
            fail(transfer.id, message: error.localizedDescription)
        }
    }

    private func reconnectTasks() async {
        let tasks = await session.allTasks
        let activeIDs = Set(tasks.map(\.taskIdentifier))
        for transfer in transfers where transfer.phase == .uploading {
            if let taskIdentifier = transfer.taskIdentifier, activeIDs.contains(taskIdentifier) { continue }
            if transfer.assetID != nil { await finishUpload(taskIdentifier: transfer.taskIdentifier ?? -1) }
            else { fail(transfer.id, message: "Upload could not be restored.") }
        }
    }

    private func copyToManagedTemporaryFile(_ source: URL, transferID: UUID) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "BandUploads", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appending(path: "\(transferID.uuidString)-\(source.lastPathComponent)")
        if source.standardizedFileURL == target.standardizedFileURL { return source }
        try FileManager.default.copyItem(at: source, to: target)
        return target
    }

    private func replace(_ transfer: BandUploadTransfer) {
        guard let index = transfers.firstIndex(where: { $0.id == transfer.id }) else { return }
        transfers[index] = transfer
        persist()
    }

    private func update(_ id: UUID, body: (inout BandUploadTransfer) -> Void) {
        guard let index = transfers.firstIndex(where: { $0.id == id }) else { return }
        body(&transfers[index])
        persist()
    }

    private func fail(_ id: UUID, message: String) {
        update(id) { transfer in
            transfer.phase = .failed
            transfer.failureMessage = message
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(transfers) else { return }
        UserDefaults.standard.set(data, forKey: persistenceKey)
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey),
              let saved = try? JSONDecoder().decode([BandUploadTransfer].self, from: data) else { return }
        transfers = saved
    }
}

extension MediaUploadManager: URLSessionTaskDelegate, URLSessionDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        let progress = totalBytesExpectedToSend > 0
            ? Double(totalBytesSent) / Double(totalBytesExpectedToSend) : 0
        Task { @MainActor in
            guard let transfer = transfers.first(where: { $0.taskIdentifier == task.taskIdentifier }) else { return }
            update(transfer.id) { $0.progress = progress; $0.phase = .uploading }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        Task { @MainActor in
            guard let transfer = transfers.first(where: { $0.taskIdentifier == task.taskIdentifier }) else { return }
            if let error = error as? URLError, error.code == .cancelled {
                update(transfer.id) { $0.phase = .cancelled }
            } else if let error {
                fail(transfer.id, message: error.localizedDescription)
            } else if let response = task.response as? HTTPURLResponse,
                      !(200..<300).contains(response.statusCode) {
                fail(transfer.id, message: "Upload failed with status \(response.statusCode).")
            } else {
                await finishUpload(taskIdentifier: task.taskIdentifier)
            }
        }
    }
}
