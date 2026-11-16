import Foundation
import Testing

@testable import KeyboardCore

/// Dictation in each language iikb types: punctuation said by name, fillers, the marks it sets as it writes them,
/// addresses and digits in its words, and which language a dictation was said in.
struct DictationLanguageTests {
    private func write(
        _ heard: String, _ language: Language, _ style: DictationStyle = .formal, _ editing: DictationEditing = .asSaid
    ) -> String {
        DictationWriting(style: style, editing: editing, textMode: .spelledOut, language: language).written(heard)
    }

    private func dictate(_ heard: String, _ language: Language, kind: InputKind = .text) -> String {
        var engine = TypingEngine(traits: InputTraits(kind: kind))
        engine.corrector = Corrector(source: testLexicon)
        let document = TestDocument("")
        engine.handle(.dictated(heard, language: language), in: document)
        return document.text
    }

    private static let english = Lexicon(
        bytes: Bytes(
            [UInt8](
                FileManager.default.contents(
                    atPath: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                        .deletingLastPathComponent().appending(path: "Sources/KeyboardEnglish/Resources/en.lexicon")
                        .path
                )!)))!
    private static let french = Lexicon(counts: AlphabetTests.counts("fr"))

    @Test func everyLanguageHasItsOwnSpokenForms() {
        #expect(Set(SpokenForms.all.keys) == Set(Language.all))
    }

    @Test func spanishPunctuationSaidByNameIsTyped() {
        #expect(
            write("Hola Marta coma ¿vienes mañana a la reunión? Te espero punto", .spanish)
                == "Hola Marta, ¿vienes mañana a la reunión? Te espero.")
        #expect(
            write("Necesito tres cosas dos puntos pan coma leche y huevos punto", .spanish)
                == "Necesito tres cosas: pan, leche y huevos.")
        #expect(write("¿Cuál es tu dirección signo de interrogación?", .spanish) == "¿Cuál es tu dirección?")
        #expect(write("Primera línea nueva línea segunda línea", .spanish) == "Primera línea\nSegunda línea.")
        #expect(write("Llego tarde punto y coma lo siento", .spanish) == "Llego tarde; lo siento.")
    }

    @Test func frenchPunctuationSaidByNameIsTyped() {
        #expect(write("Salut Marie Virgule tu viens de main point.", .french) == "Salut Marie, tu viens de main.")
        #expect(write("Quelle est ton adresse point d'interrogation ?", .french) == "Quelle est ton adresse\u{A0}?")
        #expect(write("Première ligne à la ligne deuxième ligne.", .french) == "Première ligne\nDeuxième ligne.")
        #expect(
            write("Il faut trois choses deux-points du pain point-virgule du lait", .french)
                == "Il faut trois choses\u{A0}: du pain\u{A0}; du lait.")
        #expect(write("Il me faut du pain virgule des œufs", .french) == "Il me faut du pain, des œufs.")
    }

    @Test func germanPortugueseItalianAndSwedishPunctuationSaidByNameIsTyped() {
        #expect(write("Hallo Anna Komma kommst du morgen Fragezeichen", .german) == "Hallo Anna, kommst du morgen?")
        #expect(write("Erste Zeile neue Zeile zweite Zeile", .german) == "Erste Zeile\nZweite Zeile.")
        #expect(write("Olá Ana vírgula você vem amanhã ponto", .portuguese) == "Olá Ana, você vem amanhã.")
        #expect(
            write("Mi servono tre cose, due punti pane, virgola, latte e uova.", .italian)
                == "Mi servono tre cose: pane, latte e uova.")
        #expect(write("Prima riga a capo Seconda riga.", .italian) == "Prima riga\nSeconda riga.")
        #expect(write("Qual è il tuo indirizzo punto interrogativo?", .italian) == "Qual è il tuo indirizzo?")
        #expect(write("Hej Anna komma tecken kommer du i morgon punkt.", .swedish) == "Hej Anna, kommer du i morgon.")
        #expect(write("Vad är din adress frågetecken?", .swedish) == "Vad är din adress?")
    }

    /// Parakeet writes the mark itself and then the name it heard; the two are one mark.
    @Test func aMarkWrittenBeforeItsNameIsOne() {
        #expect(write("Wie ist deine Adresse? Fragezeichen.", .german) == "Wie ist deine Adresse?")
        #expect(write("Qual é o seu endereço? Ponto de interrogação?", .portuguese) == "Qual é o seu endereço?")
        #expect(write("What's your address? question mark.", .english) == "What's your address?")
    }

    @Test func aNameStaysAWordWhereItIsOne() {
        #expect(write("Desde mi punto de vista está bien", .spanish) == "Desde mi punto de vista está bien.")
        #expect(write("Estoy a punto de salir", .spanish) == "Estoy a punto de salir.")
        #expect(write("Lo vemos punto por punto", .spanish) == "Lo vemos punto por punto.")
        #expect(write("C'est un bon point de départ", .french) == "C'est un bon point de départ.")
        #expect(write("Das ist der Punkt", .german) == "Das ist der Punkt.")
        #expect(write("Wir gehen das Punkt für Punkt durch", .german) == "Wir gehen das Punkt für Punkt durch.")
        #expect(write("Do meu ponto de vista está ótimo", .portuguese) == "Do meu ponto de vista está ótimo.")
        #expect(write("Ho parlato con il capo", .italian) == "Ho parlato con il capo.")
        #expect(write("Il nuovo capo arriva domani", .italian) == "Il nuovo capo arriva domani.")
        #expect(write("È a capo del progetto", .italian) == "È a capo del progetto.")
        #expect(write("Compra del pane virgola del latte", .italian) == "Compra del pane, del latte.")
        #expect(write("Escríbeme a ventas arroba tienda punto com", .spanish).contains("punto com"))
        #expect(write("Un autre point important", .french) == "Un autre point important.")
        #expect(write("Certo punto ho ragione", .italian) == "Certo punto ho ragione.")
        #expect(write("Es fehlt ein Komma im Satz", .german) == "Es fehlt ein Komma im Satz.")
        #expect(write("Es sind drei Komma fünf Prozent", .german) == "Es sind drei Komma fünf Prozent.")
        #expect(write("Es sind 3 Komma 5 Prozent", .german) == "Es sind 3 Komma 5 Prozent.")
    }

    /// A name that ends a sentence is a mark where the sentence ends: last, before a capital, a mark or another name.
    @Test func aNameIsAMarkWhereTheSentenceEnds() {
        #expect(write("Me siento mal coma no voy", .spanish) == "Me siento mal, no voy.")
        #expect(write("Was ist das Fragezeichen", .german) == "Was ist das?")
        #expect(write("Gracias punto Por favor ven pronto", .spanish) == "Gracias. Por favor ven pronto.")
        #expect(write("Vou ao mercado ponto", .portuguese) == "Vou ao mercado.")
        #expect(write("Isso é tudo ponto Com certeza", .portuguese) == "Isso é tudo. Com certeza.")
        #expect(write("Titta punkt Se här", .swedish) == "Titta. Se här.")
        #expect(
            write("Llego mañana a la reunión punto nueva línea Saludos", .spanish)
                == "Llego mañana a la reunión.\nSaludos.")
    }

    /// Only a mark the model wrote gives way to its name, so marks said one after another all stay.
    @Test func marksSaidTwiceStay() {
        #expect(write("First new line new line second", .english) == "First\n\nSecond.")
        #expect(write("Wait!! exclamation point", .english, .casual) == "Wait!!")
        #expect(write("Erste Zeile neue Zeile neue Zeile zweite", .german) == "Erste Zeile\n\nZweite.")
    }

    @Test func aFillerThatAsksStays() {
        #expect(write("Vienes mañana, eh?", .spanish, .formal, .light) == "¿Vienes mañana, eh?")
    }

    @Test func eachLanguageLosesItsOwnFillers() {
        #expect(
            write("Eh, creo que podemos quedar a las tres.", .spanish, .formal, .light)
                == "Creo que podemos quedar a las tres.")
        #expect(write("Euh, je pense que oui.", .french, .formal, .light) == "Je pense que oui.")
        #expect(
            write("Äh, ich glaube, ähm, wir können uns treffen.", .german, .formal, .light)
                == "Ich glaube, wir können uns treffen.")
        #expect(write("Eu tenho um carro.", .portuguese, .formal, .light) == "Eu tenho um carro.")
        #expect(write("Um, I have a car.", .english, .formal, .light) == "I have a car.")
    }

    @Test func frenchSpacesItsMarks() {
        #expect(write("Merci! Tu viens demain ?", .french) == "Merci\u{A0}! Tu viens demain\u{A0}?")
        #expect(write("Quoi ?!", .french) == "Quoi\u{A0}?!")
        #expect(
            write("Rendez-vous à 14:30 sur https://exemple.fr.", .french)
                == "Rendez-vous à 14:30 sur https://exemple.fr.")
        #expect(write("Merci! Tu viens?", .english) == "Merci! Tu viens?")
    }

    @Test func spanishOpensItsQuestionsAndExclamations() {
        #expect(write("Vienes mañana?", .spanish) == "¿Vienes mañana?")
        #expect(write("Qué bien! Nos vemos.", .spanish) == "¡Qué bien! Nos vemos.")
        #expect(write("Hola Marta, ¿vienes mañana?", .spanish) == "Hola Marta, ¿vienes mañana?")
        #expect(write("Hola. Cuál es tu dirección signo de interrogación", .spanish) == "Hola. ¿Cuál es tu dirección?")
    }

    /// English's rules beside a sentence in another language each would get wrong.
    @Test func englishRulesStayInEnglish() {
        #expect(write("Do i libri a Marco.", .italian) == "Do i libri a Marco.")
        #expect(write("Do you know Marco.", .english) == "Do you know Marco?")
        #expect(write("Va bene, no, grazie.", .italian, .formal, .clean) == "Va bene, no, grazie.")
        #expect(write("At two, I mean three.", .english, .formal, .clean) == "At three.")
        #expect(
            write("Ich gehe früh, so dass ich pünktlich bin", .german, .veryCasual)
                == "Ich gehe früh, so dass ich pünktlich bin")
        #expect(write("I left early, so I made it", .english, .veryCasual) == "I left early so I made it")
        #expect(write("Also ich komme morgen", .german) == "Also ich komme morgen.")
        #expect(write("So, ich komme morgen", .german, .casual) == "So, ich komme morgen")
        #expect(
            DictationWriting(style: .casual, textMode: .texting, language: .french).written("Envoie-moi un message")
                == "Envoie-moi un message")
    }

    @Test func anAddressIsSaidInEachLanguagesWords() {
        #expect(dictate("juan punto perez arroba gmail punto com", .spanish, kind: .email) == "juan.perez@gmail.com")
        #expect(dictate("ana guion bajo ruiz arroba correo punto es", .spanish, kind: .email) == "ana_ruiz@correo.es")
        #expect(dictate("jean point dupont arobase gmail point com", .french, kind: .email) == "jean.dupont@gmail.com")
        #expect(dictate("max punkt müller at gmail punkt de", .german, kind: .email) == "max.müller@gmail.de")
        #expect(
            dictate("marco punto rossi chiocciola gmail punto com", .italian, kind: .email) == "marco.rossi@gmail.com")
        #expect(
            dictate("joao ponto silva arroba gmail ponto com ponto br", .portuguese, kind: .email)
                == "joao.silva@gmail.com.br")
        #expect(
            dictate("erik punkt larsson snabel-a gmail punkt se", .swedish, kind: .email) == "erik.larsson@gmail.se")
        #expect(
            dictate("Mi correo es juan.perez arroba gmail punto com", .spanish) == "Mi correo es juan.perez@gmail.com")
        #expect(dictate("Mi correo es juan.perez arroba gmail punto com", .english).contains("arroba"))
        #expect(dictate("Escríbeme a ventas arroba tienda punto com", .spanish) == "Escríbeme a ventas@tienda.com")
        #expect(dictate("Mi web es tienda punto es", .spanish) == "Mi web es tienda.es")
        #expect(dictate("Isso é tudo ponto Com certeza", .portuguese) == "Isso é tudo ponto Com certeza")
        #expect(dictate("Det är bra punkt se här", .swedish) == "Det är bra punkt se här")
        #expect(dictate("j o h n arroba gmail punto com", .spanish, kind: .email) == "john@gmail.com")
    }

    @Test func digitsSaidOneByOneAreTypedInEachLanguage() {
        #expect(
            dictate("Me liga no nove nove sete seis cinco quatro três.", .portuguese) == "Me liga no 9976543.")
        #expect(
            dictate("Llámame al seis cero cero, cuatro uno dos, nueve cinco siete.", .spanish)
                == "Llámame al 600-412-957.")
        #expect(
            dictate("Chiamami al tre quattro sette uno due tre quattro cinque sei sette.", .italian)
                == "Chiamami al 3471234567.")
        #expect(
            dictate("Ruf mich an unter null eins sieben zwei drei vier fünf.", .german) == "Ruf mich an unter 0172345.")
        #expect(dictate("Ce sont trois chats.", .french) == "Ce sont trois chats.")
        #expect(dictate("El código es cuatro siete uno nueve.", .spanish) == "El código es 4719.")
        #expect(dictate("Ich habe vier drei zwei eins.", .german) == "Ich habe vier drei zwei eins.")
        #expect(
            dictate("Call four one five five five five zero one nine nine.", .english) == "Call 415-555-0199.")
    }

    @Test func aDictationIsInTheLanguageWhoseWordsItSays() {
        let english = (language: Language.english, lexicon: Self.english)
        let french = (language: Language.french, lexicon: Self.french)
        let spanish = (language: Language.spanish, lexicon: AlphabetTests.spanish)
        let german = (language: Language.german, lexicon: AlphabetTests.german)
        #expect(Language.of("good point", among: [english, french]) == .english)
        #expect(Language.of("good point", among: [french, english]) == .english)
        #expect(Language.of("C'est un bon point de départ.", among: [english, french]) == .french)
        #expect(Language.of("Hola Marta, ¿vienes mañana a la reunión?", among: [english, spanish]) == .spanish)
        #expect(Language.of("Wie ist deine Adresse?", among: [english, german]) == .german)
        #expect(Language.of("Are you free tonight?", among: [german, spanish, english]) == .english)
        #expect(Language.of("Mi correo es juan.perez@gmail.com", among: [english, spanish]) == .spanish)
    }

    @Test func aWordEveryLanguageSaysStaysInTheFirst() {
        let english = (language: Language.english, lexicon: Self.english)
        let german = (language: Language.german, lexicon: AlphabetTests.german)
        #expect(Language.of("Hallo!", among: [german, english]) == .german)
        #expect(Language.of("Hallo!", among: [english, german]) == .english)
        #expect(Language.of("415-555-0199", among: [german, english]) == .german)
        #expect(Language.of("", among: []) == .english)
    }

    @Test func aDictationMayBeInAnyLanguageYouTypeOrEnglish() {
        var settings = KeyboardSettings()
        settings.languages = [.german, .french]
        #expect(settings.dictationLanguages == [.german, .french, .english])
        settings.languages = [.spanish, .english, .italian]
        #expect(settings.dictationLanguages == [.spanish, .english, .italian])
    }
}
