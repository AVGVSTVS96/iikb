import Testing

@testable import FullKeyboard

struct KeyboardHostTests {
    @Test func aShareSheetExtendsItsAppAndAnotherAppDoesNot() {
        let apps = ["ph.telegra.Telegraph", "ph.telegra.Telegraph.Share", "com.atebits.Tweetie2"]
        #expect(KeyboardHost.isExtension("ph.telegra.Telegraph.Share", ofAny: apps))
        #expect(!KeyboardHost.isExtension("ph.telegra.Telegraph", ofAny: apps))
        #expect(!KeyboardHost.isExtension("ph.telegra.TelegraphX", ofAny: apps))
        #expect(!KeyboardHost.isExtension("net.whatsapp.WhatsApp", ofAny: apps))
    }
}
