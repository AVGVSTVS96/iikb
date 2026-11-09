# iikb privacy policy

iikb is a keyboard and an app for iPhone, iPad and Android. What you type and say stays on your phone. iikb has no account, no
ads, no analytics and no server of its own that receives your data.

## What stays on your iPhone

- What the keyboard learns: where your thumbs land, the words and phrases you use, your emoji and GIF picks.
- Your clipboard history, kept by the keyboard so you can paste it again.
- Dictation: recordings and transcripts are made on the iPhone by the voice model you pick, and kept there until you
  delete them.
- Your typing and dictation stats.

Deleting iikb deletes all of it.

## What leaves your iPhone, and only when you use it

- **Voice models.** The first time you dictate, iikb downloads its speech model from Hugging Face. Nothing you say is
  sent; the model runs on the iPhone.
- **GIF search.** What you type into GIF search goes to KLIPY, which returns the GIFs, with a random ID made for this
  install that KLIPY uses to rank results. Nothing else you type is sent.
- **App names.** To show apps by name in Stats, Transcripts and Writing Style, the iikb app asks Apple's App Store
  (iTunes Search API) for the names of the apps you've typed or dictated in, by their bundle IDs, once each.
- **Link icons.** For a link you copy, iikb fetches the site's icon from that site, or from where its home page says the icon
  is. Only the site's name is sent, never the link.
- **Extensions you add.** An extension gets the messages you write in its chat, and nothing you type elsewhere. None is
  added unless you add it.
- **Sources you add.** A source is a web service you choose to plug in. iikb sends it the text of the field you're typing
  in, as [docs/sources.md](sources.md) describes. None is added unless you add it.
- **Computers you add.** If you add your own Mac to Stats, iikb reads the typing counts it shares, over your own network.

## Full Access

iOS asks you to allow Full Access for a keyboard that uses the network or shares data with its app. iikb needs it for
haptics, voice typing, GIFs, the clipboard history, Stats and sources. Without it, iikb still types and corrects,
with nothing leaving the keyboard.

## On Android

The same holds on Android, with these differences:

- No Full Access: Android has no such switch. The microphone asks for its own permission the first time you dictate.
- Android's speech recognizer, when you pick it in Settings › Voice instead of Parakeet, is Google's, on the phone where
  it can be. Where it can't, Google's recognizer may send the recording to Google.
- Android's own backup copies iikb's settings and what it learned to your Google account, as it does for every app
  that allows it. Recordings and the voice models are left out. Turn it off in Android's Settings › Backup.
- Apps are named by Android itself, so nothing is sent for app names.
- There are no computers to add.

## Contact

iikb is open source: [github.com/AVGVSTVS96/iikb](https://github.com/AVGVSTVS96/iikb). Questions go to its
[issues](https://github.com/AVGVSTVS96/iikb/issues).
