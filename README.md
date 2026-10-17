# TagKlon

Tag-editor og musikorganisator i Lazarus/Free Pascal, inspireret af funktionerne i Tag&Rename 3.9.15
(se [docs/Funktionsoversigt.md](docs/Funktionsoversigt.md)). Arbejdstitel – navnet kan ændres.

## Status (MVP, trin 9)
- **Hovedvindue i Tag&Rename-stil:** menulinje (Filer, Rediger, Vis, Playliste, Værktøjer,
  Indstillinger, Hjælp), værktøjspanel (F8) med fanerne *Omdøb filer (F4)*, *Multi-fil-tag-editor
  (Ctrl+F4)* og *Tags fra filnavn (Shift+F4)* direkte i vinduet (med live-resultat for den markerede
  fil), panelerne *Mappens cover* og *Filens cover* (træk et billede hertil), ikonværktøjslinje,
  adresselinje med historik, filterlinje (Filtrer! / Skjul valgte filer / Vis alle), mappepanel med
  Op/Favoritter/Ny mappe, og statuslinje med antal og spilletid for alle/markerede/afkrydsede filer.
- Kopiér/indsæt tag (Ctrl+Shift+C/V), playlister (.m3u8/.m3u), afspil fil, vis i Stifinder.
- **Flere felter** (31 i alt): sangtekst, dirigent, tekstforfatter, oprindelig kunstner, remixet af,
  pladeselskab, katalognr., ISRC, copyright, kodet af, URL, gruppering, undertitel, stemning,
  toneart og fem sorteringsfelter – i ID3v2 (TPE3, TEXT, TOPE, TPE4, TPUB, TSRC, TCOP, TENC, WXXX,
  TIT1, TIT3, TMOO/TXXX:MOOD, TKEY, TSO*, USLT, TXXX:CATALOGNUMBER), Vorbis comments og MP4
  (©lyr, cprt, ©grp, so*, ----:com.apple.iTunes:*). Tag-editoren har fanerne Generelt, Flere felter,
  Sortering og Sangtekst; nye maskevariabler %co %lb %cat %grp %rb %md %key.
- **Flyt fil op/ned** (Ctrl+Op/Ned) – manuel rækkefølge, fx før "Nummerér i listens rækkefølge".
- **Eksportér** til CSV (Excel, semikolon + BOM), CSV (komma), tekst, HTML og XML med valgfrie
  kolonner; **importér** fra CSV/XLSX med forhåndsvisning (matcher på "Sti" eller "Filnavn").
- Mappetræ og virtuel filliste med 21 kolonner; klik på en kolonneoverskrift for at sortere.
- "Søg i undermapper"; tags læses i en baggrundstråd, så vinduet ikke fryser.
- Husker sidste mappe, undermappe-valg og træets bredde (`%LOCALAPPDATA%\TagKlon\tagklon.ini`).
- Læser tags (kun læsning endnu):
  - MP3: ID3v2.2/2.3/2.4 + ID3v1, varighed/bitrate inkl. VBR (Xing/Info/VBRI)
  - FLAC: Vorbis comments, STREAMINFO, billeder
  - Ogg Vorbis, Opus og Ogg FLAC
  - MP4/M4A/M4B: iTunes-atoms (`ilst`), AAC/ALAC
- WMA, APE, WavPack, MPC, WAV og AIFF bliver vist i listen, men deres tags læses ikke endnu.
- **Skriver tags** til MP3 (ID3v2.3/2.4 + opdaterer et eksisterende ID3v1), FLAC og MP4/M4A:
  - felter vi ikke redigerer (ReplayGain, MusicBrainz-id'er, iTunes-felter, ...) bevares uændret
  - skriver på stedet, når der er plads (padding/`free`), ellers via midlertidig fil, der erstatter originalen
  - MP4: chunk-offsets (`stco`/`co64`) rettes, når lyddata flyttes
- **Tag-editor** for én fil (dobbeltklik, Enter eller "Rediger tag..."): titel, kunstner, album,
  albumkunstner, komponist, år, spor, disc, genre, BPM, kommentar og cover-billeder
  (tilføj/fjern/gem som fil), "Gem og forrige/næste" og "Bevar filens dato".
- Ogg/Opus kan læses, men ikke gemmes endnu.
- **Omdøb filer** ud fra tags med maske (`%1 - %2`, `%1\%3\%6 - %2` laver mapper), versaler,
  mellemrum→`_`, 2-cifret spornummer, live forhåndsvisning (uændret / mangler felt / findes allerede /
  dublet) og **Fortryd omdøbning** (fjerner også mapper, der blev tomme).
- **Tags fra filnavn** med maske (`%6 - %1 - %2`, `%d` springer over, `\` bruger mappenavne),
  `_`→mellemrum, versaler, forhåndsvisning og skrivning.
- Brugte masker huskes (seneste 15).
- **Afkrydsning** (☑-kolonnen): klik i kolonnen eller tryk mellemrum; højreklik for
  afkryds markerede/alle, fjern og inverter. Statuslinjen viser antal afkrydsede.
  Rediger flere, Omdøb og Tags fra filnavn bruger de afkrydsede filer (ellers de markerede).
- **Rediger flere filer**: fælles værdier vises, forskellige vises som hint; kun felter med
  flueben gemmes (tomt felt med flueben = ryd). Erstat eller fjern cover i alle filer,
  statuslinje og annuller.
- **Spornumre**: formatér eksisterende numre (`7`, `07`, `007`, `7/12`, `07/12` – totalen tages fra
  filen eller tælles pr. mappe) eller nummerér i listens rækkefølge (startnummer, forfra pr. mappe).
- **Omdøb mapper** ud fra tags (`%1 - %4 - %3`, `%f` = nuværende navn, `\` laver undermapper).
  Bruger værdier, der er ens for alle filer i mappen (forskellige kunstnere → albumkunstner).
  Listen og mappetræet følger med, og det kan fortrydes.
- **MusicBrainz-opslag** (erstatter freedb/Amazon): søg på kunstner + album, vælg udgivelse
  (dato, land, format, pladeselskab, katalognr.), filerne parres efter disk/spornummer eller
  rækkefølge (Op/Ned), og valgte felter + forside fra Cover Art Archive skrives (også som
  folder.jpg). Netværk via Windows' WinInet – ingen OpenSSL-DLL'er. Overholder MusicBrainz'
  grænse på 1 forespørgsel/sek. og prøver igen ved 503.
- **Discogs** som ekstra kilde i samme dialog (vælg kilde øverst til venstre). Søgning kræver et
  personligt token (discogs.com > Settings > Developers), som indsættes via "Discogs-token..." og
  gemmes i indstillingsfilen. Sporpositioner som A1/B2/2-05 omsættes til disk + nummer, og
  navnetilføjelser som "(2)" fjernes. Cover = udgivelsens primære billede.

## Byg
```
C:\lazarus\lazbuild.exe TagKlon.lpi
```
Resultat: `bin\TagKlon.exe`. Projektet kan også åbnes i Lazarus-IDE'en (`TagKlon.lpi`).

Testværktøj, der skriver tags ud i konsollen:
```
C:\lazarus\fpc\3.2.2\bin\x86_64-win64\fpc.exe -Mobjfpc -Sh -Fusrc -FUlib\tools -FEbin tools\tagdump.lpr
bin\tagdump.exe "D:\Musik\Album" -r
```

Skrivetest (arbejder på **kopier** i den angivne testmappe og tjekker felter, billeder og at lyddata er uændrede):
```
C:\lazarus\fpc\3.2.2\bin\x86_64-win64\fpc.exe -Mobjfpc -Sh -Fusrc -FUlib\tools -FEbin tools\tagtest.lpr
bin\tagtest.exe C:\Temp\tagtest "D:\Musik\sang.mp3" "D:\Musik\sang.flac"
```

Test af omdøbning (filer og mapper), tags fra filnavn og spornumre (opretter tomme testfiler i den angivne mappe):
```
C:\lazarus\fpc\3.2.2\bin\x86_64-win64\fpc.exe -Mobjfpc -Sh -Fusrc -FUlib\tools -FEbin tools\renametest.lpr
bin\renametest.exe C:\Temp\renametest
```

Øvrige værktøjer i `tools\`: `webtest.lpr` (offline-test af MusicBrainz-svar og parring),
`dgtest.lpr` (live Discogs: `bin\dgtest.exe 249504`), `mbtest.lpr` (live-søgning: `bin\mbtest.exe "Gasolin'" "Gas 5"`), `exporttest.lpr` (eksport/import), `tagset.lpr` (sæt felter:
`bin\tagset.exe fil.mp3 artist=X album=Y track=1`).

Bemærk: `lazbuild` genbygger ikke en formular, hvis kun `.lfm`-filen er ændret – gem også den tilhørende `.pas`.

## Struktur
| Fil | Indhold |
|---|---|
| `src/audiotypes.pas` | `TAudioInfo` – formatuafhængigt resultat |
| `src/audiotags.pas` | Vælger læser ud fra filtypenavn |
| `src/mp3reader.pas` | ID3v2/ID3v1 + MPEG-lydinfo |
| `src/vorbisreader.pas` | FLAC + Ogg (Vorbis/Opus/FLAC) |
| `src/mp4reader.pas` | MP4/M4A-atoms |
| `src/tagutils.pas` | Byte-hjælpere, tekstdekodning, ID3-genreliste |
| `src/scanthread.pas` | Baggrundstråd: find filer og læs tags |
| `src/tagwriter.pas` | Vælger skriver ud fra filtypenavn, bevarer evt. tidsstempel |
| `src/id3writer.pas` | ID3v2 (+ID3v1) til MP3 |
| `src/flacwriter.pas` | FLAC-metadatablokke og Vorbis comments |
| `src/mp4writer.pas` | MP4-atomtræ, `ilst`, chunk-offsets |
| `src/tageditform.pas/.lfm` | Tag-editor for én fil |
| `src/renamecore.pas` | Maske → fil-/mappenavn, rensning, plan/udfør/fortryd |
| `src/filenametags.pas` | Filnavn → tags (maske-matchning) |
| `src/renameform.pas/.lfm` | Dialog: Omdøb filer / Omdøb mapper |
| `src/filetotagform.pas/.lfm` | Dialog: Tags fra filnavn |
| `src/appsettings.pas` | Indstillingsfil og maske-historik |
| `src/multieditform.pas/.lfm` | Dialog: Rediger flere filer |
| `src/trackcore.pas` | Spornumre: formatér og nummerér |
| `src/tracktoolsform.pas/.lfm` | Dialog: Spornumre |
| `src/discogs.pas` | Discogs-søgning/-udgivelse/-billede (samme datastrukturer som MusicBrainz) |
| `src/musicbrainz.pas` | HTTP (WinInet), MusicBrainz-søgning/-udgivelse, Cover Art Archive |
| `src/trackmatch.pas` | Parring af filer og spor, udfyldning af felter |
| `src/weblookupform.pas/.lfm` | Dialog: Web-opslag (MusicBrainz/Discogs) |
| `src/mainform.pas/.lfm` | Hovedvindue (menu/værktøjslinje bygges i koden fra én handlingstabel) |
| `src/exportimport.pas` | Eksport (CSV/TXT/HTML/XML), CSV-/XLSX-læsning, import-plan |
| `src/exportimportform.pas/.lfm` | Dialog: Eksportér/importér tags |
| `src/batchwrite.pas` | Gem udvalgte felter/cover i én fil (bruges af faner, indsæt tag, træk-og-slip) |
| `res/icons/`, `res/icons.rc` | Ikoner (Lazarus general_purpose af Roland Hahn, CC0) |
| `reference/forms/` | Formularer fra originalen (kun som reference – må ikke kopieres) |

## Næste skridt
1. Ogg/Opus-skrivning og understøttelse af WMA, APE/WavPack og WAV/AIFF
2. Rating (POPM) og flere billedtyper i editoren
4. Indstilling for kontakt-info i MusicBrainz' User-Agent (anbefales af MusicBrainz)
