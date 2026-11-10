# Writing Style

## Sub-features

How a dictation is typed (`DictationWriting`, KeyboardCore), as two things. Style, per app: one choice of capitals, punctuation and words, Formal. (ends with a period), Excited! (ends with "!"), Casual, the default (no last period, no comma after an opening "so" or "also"), very casual (Casual in lowercase, with btw and idk), texting (also u and tn) and slang (also fr and fire); the default's set in the app, an app's own in the app or the keyboard's bar. Cleanup, the same everywhere: As Said, the default, keeps every word, um and uh included; No Um or Uh leaves those out; Clean also leaves out words said twice and what "scratch that" takes back; Spoken Lists types a spoken list ("one, eggs, two, milk") as a numbered or bulleted one. Capitals follow Auto-Capitalization, as typing's do; very casual, texting and slang have none. Each style shows the same words as it would type them. Transcripts keep what the model wrote.

## How to get to it (user POV)

iikb app › Settings › Voice Typing › Writing Style, or the iikb tab's Writing Style card. Where the bar has room (the open Duo, an iPhone in landscape) and with Full Access, the style for the app you're in is picked in the bar, at the suggestions' right end before the mic.

## Driving it

`DictationStyleTests` (package) pins each style and editing, the capitals and spoken lists; `scripts/coretest --filter DictationStyleTests` runs them on Linux. `-iikbSettings writing` opens the page for a screenshot.
