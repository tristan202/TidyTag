# Tag&Rename-funktioner, som TagKlon ikke har endnu

Udarbejdet ud fra originalens formularer og handlinger (IDR-udtræk i `reference/idr`, kun som
reference). Kun *hvad* funktionerne gør er brugt – ingen kode. Prioritet: **A** = stor værdi i
dagligt brug, **B** = nyttigt, **C** = sjældent/nichepræget, **–** = droppes.

## Tag-værktøjer (menuen Værktøjer)
| Funktion | Prioritet | Bemærkning |
|---|---|---|
| Byt felter: Kunstner ↔ Titel, Kunstner ↔ Album, Album ↔ Titel, avanceret (vilkårlige felter) | **Færdig** | Klassiker efter forkert "tags fra filnavn" |
| Kopiér tekst fra ét tag-felt til et andet | **Færdig** | Fx Kunstner → Albumkunstner |
| Fjern mellemrum (efterstillede / foran og bagved) i alle felter | **Færdig** | |
| Kunstner-værktøjer: fjern indledende "The", "The Artist" ↔ "Artist, The", "Fornavn Efternavn" ↔ "Efternavn, Fornavn" | **Færdig** | Kan også skrive til sorteringsfelterne |
| Fjern tags helt (Ctrl+Del) | **Færdig** | Pr. tagtype (ID3v1/ID3v2/APE ...) |
| Mp3-tag-synkronisering: ID3v1 → ID3v2 eller omvendt (spring over / kun tomme felter / alle felter) | **Færdig** | |
| Spornummer: "x/xx"-format, automatisk episodenummer | C | Formatering findes allerede |
| Skift filtype .mp4 → .m4a og .mp4/.m4a → .m4b | C | |

## Cover-værktøjer
| Funktion | Prioritet | Bemærkning |
|---|---|---|
| Læg mappens cover (folder.jpg) ind i alle filers tag | **Færdig** | |
| Udtræk cover fra filernes tag til folder.jpg | **Færdig** | |
| Slet mappe-cover i alle valgte mapper | B | |
| Skalér cover i filer/mapper (maks. dimension, JPEG-kvalitet, konvertér til JPEG) | B | Også som indstilling: skalér store billeder automatisk ved tilføjelse |
| Brug tag-billede som mappe-cover | B | Delvist: man kan trække billeder til panelerne |

## Omdøbning
| Funktion | Prioritet | Bemærkning |
|---|---|---|
| "Rename Actions": navngivne forudindstillinger (filmaske + mappemaske) i en menu | **Færdig** | Én klik for faste mønstre |
| Maske-editor med knapper for variabler, eksempel og gemte masker | B | Vi har Variabler-menu og historik |
| Ordudskiftninger (fx "&" → "and") og ord der altid beholder versaler (fx "AC/DC", "ABBA") | **Færdig** | Indstillinger > File Rename Strings |
| Flere maskevariabler: %rt udgivelsestid, %rnd tilfældigt tal, %dbit bitdybde, %enc encoder, tv-serie (%swt %eid %snr %enr) | B | |
| "Omdøb ikke, hvis filen findes" som indstilling | C | Vi springer allerede over ved konflikt |
| Rediger fil-/mappenavn i dialog med "og forrige/næste" (F6) | C | Vi har direkte omdøbning i listen |

## Fil-liste og visning
| Funktion | Prioritet | Bemærkning |
|---|---|---|
| Visningstilstand: vis kun filer med ID3v2 / WMA / Ogg-Flac / MP4 / APE | B | Filter på tagtype |
| Flad filliste (alle undermapper) | – | Findes: "Søg i undermapper" |
| Søg: i valgte felter, helt ord, store/små bogstaver, find alle, tæl | B | Vi har et simpelt filter |
| Kolonner: autotilpas bredde (også efter mappeskift), sekundær sortering, tilfældig rækkefølge | B | |
| Farver: marker lav bitrate, vis "mangler ID3v1", skjul filtypenavne, gitterlinjer | C | |
| Udvid/fold alle mapper, "afspil filer i mappe" fra mappemenuen | C | |
| Historik-menu for mapper | C | Adresselinjen har historik |

## Filhandlinger
| Funktion | Prioritet | Bemærkning |
|---|---|---|
| Slet filer (papirkurv) | B | |
| Kopiér/flyt til mappe | B | |
| Egenskaber (Windows-dialog) | C | |

## Tag-editor
| Funktion | Prioritet | Bemærkning |
|---|---|---|
| "Del af opsamling" (TCMP/cpil) og "Podcast"-markering | B | |
| Rediger tag i alle valgte filer (Ctrl+F5) | – | Findes: Rediger flere filer |

## Indsæt tag
| Funktion | Prioritet | Bemærkning |
|---|---|---|
| Vælg hvilke felter der *ikke* indsættes (titel, spor, BPM, kunstner, sangtekst) | **Færdig** | Vi springer fast over titel og spor |

## Indstillinger (dialog)
| Funktion | Prioritet | Bemærkning |
|---|---|---|
| Samlet indstillingsdialog | B | Nu spredt i menuer |
| ID3v2: gem altid i Unicode / ASCII hvis muligt | C | Vi gemmer UTF-16 ved behov |
| Kopiér Kunstner → Albumkunstner (hvis tom / altid) | **Færdig** | |
| Afspiller pr. filtype | C | Vi bruger Windows' standardprogram |
| Playliste: EXTINF, fulde stier, hurtig-gem uden dialog | C | |
| Startmappe, skriftstørrelse | C | |
| Genre-liste-editor (vælg standardgenrer, egne genrer) | C | |

## Droppes
| Funktion | Grund |
|---|---|
| Winamp-styring | Winamp bruges sjældent; vi har "Afspil fil" |
| Freedb, Amazon/TrackType.org | Tjenesterne er lukket – erstattet af MusicBrainz/Discogs |
| Opdateringstjek, RSS, Køb, Lås op, nag-skærm | Ikke relevant |
| Proxy- og Amazon AWS-indstillinger | Tilhører de lukkede tjenester (WinInet bruger Windows' proxy) |
| Shell-integration (højreklik i Stifinder) | Mulig senere; kræver registry-ændringer |
| Tilpas værktøjslinjer og genveje | Stor opgave, lille gevinst |
