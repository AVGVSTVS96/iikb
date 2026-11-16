import Foundation
import KeyboardStore
import Testing

@MainActor
struct DictationRequestTests {
    @Test func theLinkCarriesTheAppToGoBackTo() {
        let request = Dictation.Request(host: "ph.telegra.Telegraph")
        #expect(request.url.absoluteString == "iikb://dictate?host=ph.telegra.Telegraph")
        #expect(Dictation.Request(request.url) == request)
    }

    @Test func aLinkWithoutAnAppStillDictates() {
        #expect(Dictation.Request(host: nil).url.absoluteString == "iikb://dictate")
        #expect(Dictation.Request(URL(string: "iikb://dictate")!) == Dictation.Request(host: nil))
    }

    @Test func otherLinksAreNotRequests() {
        #expect(Dictation.Request(URL(string: "iikb://source?url=x")!) == nil)
        #expect(Dictation.Request(URL(string: "tg://dictate")!) == nil)
    }

    /// A dictation an older app left, before notes carried their language, is typed as English.
    @Test func aNoteLeftBeforeLanguagesIsEnglish() throws {
        let id = UUID()
        let older = #"{"heard":{"_0":"Hola","plain":"hola","keyboard":7,"id":"\#(id.uuidString)"}}"#
        #expect(
            try JSONDecoder().decode(Dictation.Note.self, from: Data(older.utf8))
                == .heard("Hola", plain: "hola", keyboard: 7, id: id, language: nil))
        let spanish = Dictation.Note.heard("Hola", plain: "hola", keyboard: nil, id: id, language: "es")
        #expect(try JSONDecoder().decode(Dictation.Note.self, from: JSONEncoder().encode(spanish)) == spanish)
    }
}
