# Tag&Rename 3.9.15 – funktionsoversigt til klon

Kilde: formularer (DFM) og strenge udtrukket af `TagRename.exe` (Delphi, 32-bit, juni 2018).
Rå formularer ligger i [`reference/forms/`](../reference/forms/) (32 stk., konverteret til tekst-DFM).
De bruges kun som reference for funktioner og indstillinger, ikke som kode eller design der kopieres.

**Status-kolonne**
- ✅ Lokal funktion – burde virke i originalen, skal bare genskabes
- ⚠️ Forældet/afhængig af ekstern ting – bør moderniseres
- ❌ Død – ekstern tjeneste lukket, skal erstattes

**Prioritet**: P1 = kerne (MVP), P2 = vigtig, P3 = kan vente/droppes

---

## 1. Hovedvindue og filliste

| Funktion | Status | Prio | Noter |
|---|---|---|---|
| Mappetræ (Stifinder-agtigt) med favoritter og historik | ✅ | P1 | Original: `TVirtualExplorerTree`. Lazarus: `TShellTreeView` eller egen træ-komponent |
| Adresselinje | ✅ | P2 | |
| Filliste med kolonner (tag-felter + filegenskaber) | ✅ | P1 | Virtuel liste – skal klare tusindvis af filer. Kolonnevalg, rækkefølge, bredde (`TFORMCOLUMNSETTINGS`) |
| Søg i undermapper / flad liste / træliste | ✅ | P1 | "Search Subfolders", "Flat File List", udvid/fold alle |
| Visningstilstand pr. tag-type: All, ID3v2, WMA, Ogg/Flac, MP4/M4A, APEv2 | ✅ | P2 | Filtrerer hvilke felter/kolonner der vises |
| Afkrydsning af filer (checkbox) vs. markering | ✅ | P1 | Mange funktioner virker kun på *afkrydsede* filer |
| Vælg alle / ingen / inverter / vælg fremhævede | ✅ | P1 | |
| Sortering, sekundær sorteringskolonne, tilfældig rækkefølge | ✅ | P2 | |
| Flyt fil op/ned (manuel rækkefølge) | ✅ | P2 | Bruges til at styre spornummerering |
| Filter: filtrér efter felt/tekst, skjul valgte, vis alle | ✅ | P2 | |
| Farver: lav bitrate, mangler ID3v1-indikator, skjul filtypenavn | ✅ | P3 | |
| Kopiér/flyt til mappe, slet, egenskaber, opret mappe/undermappe | ✅ | P2 | |
| Find (søg i valgte tag-felter, hel ord, versalfølsom, find alle, tæl) | ✅ | P2 | `TFORMFIND` |
| Kopiér tag / indsæt tag / indsæt i alle valgte (med "indsæt ikke titel/spor/BPM/kunstner/lyrics") | ✅ | P1 | `TFORMPASTETAG` |
| Afspil fil / valgte filer i standardafspiller | ✅ | P3 | |
| Winamp-styring (play/pause/næste, tilføj til playliste) | ⚠️ | P3 | Winamp er forældet – drop eller erstat med "åbn i afspiller" |
| Tilpas værktøjslinjer og genveje | ✅ | P3 | |
| Panel med mappens cover (folder.jpg) og filens cover | ✅ | P2 | Sæt tag-billede som mappecover, slet mappecover |

## 2. De tre hovedfunktioner (faner i hovedvinduet)

### 2a. Omdøb filer ud fra tags (F4) – P1 ✅
- Maske med variabler, fx `%1 - %3 (%2)`. `\` i masken opretter mapper (`%1\%3\%6 - %2`).
- Forhåndsvisning, Omdøb, **Fortryd** (undo).
- Versaltilpasning (Case-radiogruppe), "erstat mellemrum med understreg".
- Ord-erstatninger og "behold altid store/små bogstaver i disse ord" (Indstillinger → File Rename Strings).
- "Omdøb ikke hvis fil med samme navn findes".
- Gemte masker + **Maske-editor** (`TFORMMASKEDITOR`).

**Maskevariabler** (fra maske-editoren):

| Var | Felt | Var | Felt | Var | Felt |
|---|---|---|---|---|---|
| `%1` | Artist | `%b` | BPM | `%rb` | Remixed by |
| `%2` | Title | `%t` | Spilletid | `%key` | Initial key |
| `%3` | Album | `%#` | Disc # | `%swt` | Show title |
| `%4` | Year | `%aa` | Album artist | `%eid` | Episode ID |
| `%5` | Genre | `%co` | Conductor | `%snr` | Season number |
| `%6` | Track # | `%cp` | Composer | `%enr` | Episode number |
| `%7` | Filnavn | `%lb` | Label | `%rnd` | Tilfældigt tal |
| `%8` | Filnummer | `%md` | Mood | `%ext` | Filtypenavn |
| `%9` | Comment | `%rt` | Release time | `%khz` | Samplerate |
| `%0` | Bitrate | | | `%dbit` / `%enc` | Bitdybde / Encoder |

### 2b. Multi-fil tag-editor (Ctrl+F4) – P1 ✅
- Sæt Artist/Album/Year/Comment/Genre på alle afkrydsede filer; kun afkrydsede felter ændres.
- Versaltilpasning, Gem tags, Fjern tags, "Kopiér fra fokuseret fil", "Rediger alle felter".

### 2c. Tags fra filnavn (Shift+F4) – P1 ✅
- Maske som `%6 %1 - %2`; `%d` springer en del over; filtypenavn fjernes automatisk.
- Kan bruge mappenavne (sti-dele) i masken.
- Forhåndsvisning/test (`TFORMFILENAMETOTAGTEST`), "erstat understreg med mellemrum", versaltilpasning.

## 3. Tag-editor for enkeltfil (`TFORMTAGEDITOR`) – P1 ✅

Faner og felter:
- **General**: Title, Artist, Album, Year, Track #, Genre, Comment, Composer, Orig. Artist, Copyright, URL, Encoded by, BPM, Disc #, Rating, Mood, "Part of a compilation", filinformation, **cover art** (tilføj/fjern/gem til fil, flere billeder).
- **Lyrics**: indlæs/gem fra tekstfil, ryd, fjern foranstillede mellemrum.
- **Additional**: Album Artist, Conductor, Lyricist, Original lyricist, Label, ISRC, Catalog #, Remixed by, Initial Key, webadresser (fil-info, kunstner, lydkilde, køb CD, radiostation), radiostationsnavn.
- **More Additional** (MP4/iTunes): Grouping, Music/Video kind, Subtitle, Podcast (kategori, beskrivelse, ID, URL), Release time, Show title, Episode ID, Season #, Episode #.
- **Sorting**: Sort Title/Artist/Album Artist/Album/Composer/Show.
- Knapper: Gem, Gem og forrige/næste, Fjern tag, Kopiér fra ID3v1, versaltilpasning.

## 4. Værktøjer (Tools-menu)

| Funktion | Status | Prio |
|---|---|---|
| Spornummer-format: `x`, `0x`, `00x`, `xx/xx`, `xx` | ✅ | P1 |
| Auto-udfyld spor # / episode # (efter rækkefølge i listen) | ✅ | P1 |
| Byt felter: Artist↔Album, Artist↔Title, Album↔Title, avanceret | ✅ | P2 |
| Kopiér tekst fra ét felt til et andet (`TFORMCOPYFIELDTEXT`) | ✅ | P2 |
| Fjern efterstillede / for- og efterstillede mellemrum i alle felter | ✅ | P2 |
| Artist-værktøjer: fjern "The", "The Artist"↔"Artist, The", "Fornavn Efternavn"↔"Efternavn, Fornavn" | ✅ | P3 |
| Cover: tilføj folder.jpg/png til tags, udtræk cover til folder.jpg, slet mappecovers | ✅ | P2 |
| Skalér cover i filer/mapper (maks. dimension, JPEG-kvalitet, konvertér til JPEG) | ✅ | P2 |
| Skift filtypenavn .mp4→.m4a, .mp4/.m4a/.m4p→.m4b | ✅ | P3 |
| MP3 tag-synkronisering: ID3v1↔ID3v2 (skriv ikke / kun tomme felter / alle felter) | ✅ | P2 |
| Omdøb mappe ud fra tags (mappemaske, anvend på alle fremhævede mapper) | ✅ | P1 |
| Rediger fil-/mappenavn manuelt (forrige/næste) | ✅ | P2 |
| **Rename Actions**: navngivne kombinationer af fil- og mappemaske (`TFORMACTIONS`) | ✅ | P2 |
| Genre-liste-editor (standardgenrer + egne) | ✅ | P2 |

## 5. Playlister – P2 ✅
- Gem valgte/alle filer som playliste; "hurtig gem" med navnemaske (`%1 %2 %3 %4 %f %aa`, `\` til mapper).
- Mulighed for EXTINF-linjer (med maske), fuld vs. relativ sti, fast playliste-mappe.
- Formater: m3u (+ sandsynligvis pls/wpl ifølge MIME-tabellen i programmet).

## 6. Eksport/import (`TFORMEXPORTIMPORT`) – P2 ✅
- Eksport til CSV, HTML, XML og tekst (ifølge Readme) med valg af felter.
- Import **kun fra XLS/XLSX**: anvend på alle filer der findes i regnearket, eller kun valgte filer.
- Originalen bruger TMS FlexCel til Excel. I klonen: læs **XLSX** med `fpspreadsheet` (Lazarus-pakke), evt. også CSV-import.

## 7. Web-import – her er det, der er i stykker

Adresser fundet i programfilen:

| Tjeneste i originalen | Adresse(r) | Status i dag | Erstatning i klonen |
|---|---|---|---|
| freedb (CDDB-protokol over HTTP) | `freedb.freedb.org`, `freedb.musicbrainz.org`, `.../~cddb/cddb.cgi?cmd=cddb+read+...` | ❌ Lukket (2019–2020) | **MusicBrainz** web-API (JSON). Evt. **gnudb.org** (bruger stadig CDDB-protokollen) |
| gnudb | `gnudb.gnudb.org` | ⚠️ Kører stadig så vidt vides – skal testes | Kan beholdes som sekundær kilde |
| TrackType.org | `tracktype.org/~cddb/cddb.cgi?cmd=cddb+album+...` | ❌ Lukket | MusicBrainz |
| Amazon (com/co.uk/de/ca) | `ecs.amazonaws.*` (det gamle Product Advertising API, før v5) + egne AWS-nøgler | ❌ Lukket – API'et er udskiftet og kræver salgskonto | **Cover Art Archive** (MusicBrainz) til cover; evt. iTunes Search API til cover |
| Discogs | `api.discogs.com/database/search`, OAuth 1.0a (`request_token`, `authorize`, `access_token`) | ⚠️ API'et findes stadig; fejl skyldes sandsynligvis gammel OpenSSL/TLS eller ændringer i API'et | Discogs med **personligt token** (enklere end OAuth) |
| Opdateringstjek, RSS, "Køb", hjemmeside | `softpointer.com/...` | ❌ Udgået | Drop, eller egen GitHub-releases-tjek |

Dialoger og funktioner der skal genskabes (P2):
- **Søgning** (`TFORMWEBIMPORT`): kunstner/album/år, vælg kilde, næste resultatside, kun "master releases" (Discogs).
- **Albuminformation** (`TFORMWEBALBUMINFORMATION`): vælg hvilke felter der skrives (artist, album, år, genre, label, kommentar, titler, spornumre, compilation), sorter filer ↔ spor med træk-og-slip, gem cover i tag og/eller som jpg, gem anmeldelse som tekstfil, gem katalognummer, anvend Rename Action (normal CD / compilation-CD), "Titel - Orig. Artist"-format.
- Indstillinger: cover-filnavn (`%1 %2 %3 %f`), søge-URL til cover (`%1..%4`), spor i `xx/xx`-format, kopier Artist til Album Artist, proxy.
- Ny mulighed i klonen: opslag ud fra **disc-ID/TOC** eller **AcoustID** (lydfingeraftryk) via MusicBrainz – det kunne originalen ikke.

## 8. Indstillinger (`TFORMPROGRAMOPTIONS`)

- **General**: integration i Stifinder, luk ikke tag-editor ved fejl, **bevar filens tidsstempel ved gem**, omdøb ikke hvis navn findes, interface-skrifttype, versal-indstillinger, startmappe (sidste/fast).
- **File List**: efter åbning af mappe (udvid alle; vælg rodfiler/alle/ingen), farver, linjer, lav bitrate, ID3v1-indikator, skjul filtypenavn, auto-vælg filer når mappe vælges, brug checkbokse.
- **File List Columns**: synlige kolonner.
- **Players**: musikafspiller, Winamp-sti.
- **Web Import**: freedb-server + e-mail, cover/anmeldelses-filnavne, cover-søge-URL, proxy.
- **Playlists**: se afsnit 5.
- **File Rename Strings**: ord-erstatninger, ord der altid beholder deres versaler.
- **Tags**: maks. padding (KB) og omskriv fil hvis større, Artist→Album Artist-regler, "Various Artists" ved compilation, ID3v2 altid Unicode / ASCII, automatisk skalering og JPEG-konvertering af cover.
- **Advanced**: egne Amazon AWS-nøgler (drop), samt avancerede valg (fx "gem ID3-chunk sidst i WAV" ifølge WhatsNew).

## 9. Filformater og tag-typer (krav til tag-bibliotek)

Fra Readme/WhatsNew: MP3 (ID3v1, ID3v2.2/2.3/2.4), MPC/MP+ (APEv1/v2, ID3v1), WMA/ASF/WMV, Ogg Vorbis, FLAC (Vorbis comments), MP4/M4A/M4B/M4P (iTunes-atoms, inkl. Xtra-atom), Monkey's Audio (APE), WavPack, OptimFROG, Apple Lossless, WMA Lossless, WAV (ID3-chunk), AIFF.

**Forslag til MVP**: MP3 (ID3v2.3/2.4 + v1), FLAC, Ogg Vorbis, MP4/M4A. Dernæst APE-tags (APE/WavPack/MPC), WMA/ASF, WAV/AIFF.

## 10. Ikke med i klonen
- Registrering, oplåsning og påmindelsesskærm (`TFORMUNLOCK`, `TFORMNAGSCREEN`).
- Opdateringstjek mod softpointer.com, "Køb", RSS.
- Amazon AWS-nøgler.
- Winamp-styring (evt. senere).

---

## Foreslået MVP (første version)
1. Mappetræ + virtuel filliste med kolonner, undermapper, afkrydsning.
2. Læs/skriv tags for MP3, FLAC, Ogg, M4A (titel, artist, album, år, spor, disc, genre, kommentar, album artist, cover).
3. Enkeltfil-tag-editor (General-fanen + cover).
4. Multi-fil tag-editor.
5. Omdøb filer og mapper ud fra maske med forhåndsvisning og fortryd.
6. Tags fra filnavn.
7. Spornummer-værktøjer.

Derefter: MusicBrainz + Cover Art Archive, Discogs, eksport/import, playlister, resten af værktøjerne.
