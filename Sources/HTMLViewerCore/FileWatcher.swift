import Foundation

/// 登録ルート群を FSEvents で監視し、変更パスのバッチを `AsyncStream` で流す(UI 非依存)。
///
/// 設計(docs/05 D4 / docs/03 §2-6):
/// - 複数ルートを 1 ストリームで再帰監視。`kFSEventStreamCreateFlagFileEvents | UseCFTypes | WatchRoot`、latency 0.3s。
/// - C コールバックはクロージャをキャプチャできないため `FSEventStreamContext.info` + `Unmanaged` で self を渡す。
/// - 専用 serial queue に閉じ込め、外界へは `events`(AsyncStream)のみで通信。`@unchecked Sendable`。
/// - `stop()` は Stop → Invalidate → Release の順を守り、`isStopping` ガードで停止中コールバックを no-op に(self 生存保証・クラッシュ防止)。
public final class FileWatcher: @unchecked Sendable {
    private let roots: [URL]
    private let latency: CFTimeInterval
    private let queue = DispatchQueue(label: "com.hayashi.htmlviewer.filewatcher")
    private var stream: FSEventStreamRef?
    private var isStopping = false
    private let continuation: AsyncStream<[String]>.Continuation

    /// 変更パスのバッチ列(canonical 正規化は消費側で行う)。
    public let events: AsyncStream<[String]>

    public init(roots: [URL], latency: CFTimeInterval = 0.3) {
        self.roots = roots
        self.latency = latency
        (events, continuation) = AsyncStream.makeStream(of: [String].self)
    }

    public func start() {
        queue.sync {
            guard stream == nil else { return }
            isStopping = false
            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil
            )
            let flags = UInt32(
                kFSEventStreamCreateFlagFileEvents
                    | kFSEventStreamCreateFlagUseCFTypes
                    | kFSEventStreamCreateFlagWatchRoot
            )
            guard let s = FSEventStreamCreate(
                kCFAllocatorDefault,
                fileWatcherCallback,
                &context,
                roots.map(\.path) as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                latency,
                flags
            ) else { return }
            FSEventStreamSetDispatchQueue(s, queue)
            FSEventStreamStart(s)
            stream = s
        }
    }

    public func stop() {
        queue.sync {
            isStopping = true
            guard let s = stream else { return }
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            stream = nil
        }
        continuation.finish()
    }

    /// コールバック(queue 上)から呼ばれる。停止中は何もしない。
    fileprivate func emit(_ paths: [String]) {
        guard !isStopping else { return }
        continuation.yield(paths)
    }
}

/// FSEvents の C コールバック(グローバル関数・キャプチャ不可)。`info` から self を復元して emit する。
private func fileWatcherCallback(
    stream: ConstFSEventStreamRef,
    info: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info else { return }
    let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
    // UseCFTypes 指定なので eventPaths は CFArray<CFString>
    let cfArray = unsafeBitCast(eventPaths, to: CFArray.self)
    let count = CFArrayGetCount(cfArray)
    var paths: [String] = []
    paths.reserveCapacity(count)
    for i in 0..<count {
        guard let raw = CFArrayGetValueAtIndex(cfArray, i) else { continue }
        let cfStr = unsafeBitCast(raw, to: CFString.self)
        paths.append(cfStr as String)
    }
    watcher.emit(paths)
}
