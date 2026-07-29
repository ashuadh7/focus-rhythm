import Foundation

protocol RhythmLibraryStoring {
    func load() -> RhythmLibrary
    func save(_ library: RhythmLibrary)
}

final class UserDefaultsRhythmLibraryStore: RhythmLibraryStoring {
    private static let key = "rhythm.library.v1"
    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        defaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.defaults = defaults
        self.encoder = encoder
        self.decoder = decoder
    }

    func load() -> RhythmLibrary {
        guard let data = defaults.data(forKey: Self.key),
              let library = try? decoder.decode(RhythmLibrary.self, from: data) else {
            return .empty
        }
        return library
    }

    func save(_ library: RhythmLibrary) {
        guard let data = try? encoder.encode(library) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
