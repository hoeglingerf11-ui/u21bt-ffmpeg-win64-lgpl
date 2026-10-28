# U21BT – FFmpeg LGPL Shared Build

## Freigegebener Umfang

Dieser öffentliche Arbeitsstand enthält ausschließlich generische Builddateien für FFmpeg; er enthält keine ShyCreator-Quellen, Modelle, Stimmen, Projekte, Zugangsdaten oder privaten Angaben. Das Repository ist öffentlich, damit der genehmigte Standardrunner-Build ohne Kosten ausgeführt werden kann.

## Gepinnte Quellen und Toolchain

- FFmpeg-Quellcommit: 46d899d7a02bc63237472cc4897258d5ddf274ac.
- BtbN-Rezeptcommit: 63ac3265b0789ea16c7b1f8351cd2ad195a28722, Variante win64-lgpl-shared.
- OCI-Image: ghcr.io/btbn/ffmpeg-builds/base-win64@sha256:284c22c72ffe8f2ff2f6676a60482a9ca0ee7e093c9938a801bc1a4d83b0e9c1.
- BtbN-Rezept nennt crosstool-ng 1.29.0.7, binutils 2.47, GCC 16.2.0 und MinGW-w64 v14.0.0; der Workflow protokolliert Laufzeitversionen.
- Öffentliche Quellstände: [FFmpeg](https://github.com/FFmpeg/FFmpeg/tree/46d899d7a02bc63237472cc4897258d5ddf274ac) und [BtbN](https://github.com/BtbN/FFmpeg-Builds/tree/63ac3265b0789ea16c7b1f8351cd2ad195a28722).

## Buildumfang

Erstellt werden soll ein LGPLv3 Shared-Build für Windows x64. Die Konfiguration aktiviert Media Foundation und deaktiviert automatische Fremdbibliothekserkennung. GPL-, Nonfree- und x264-Optionen sind ausgeschlossen und werden geprüft. FFV1, h264_mf, AAC, MP4 sowie die von der vorhandenen Pipeline benötigten Filter werden im Windows-Standardrunner-Smoke-Test geprüft. Der Test benutzt synthetische Medien und ersetzt keine ShyCreator-Abnahme.

Korrespondierende FFmpeg-Quellen, tatsächlich verwendete BtbN-Rezeptdateien samt MIT-Lizenz, Änderungen, Configure-Aufruf und -Log, Toolchain-Identität, PE-Importliste und Lizenzhinweise gehören in das Quellen-/Build-Archiv. Das Laufzeitarchiv enthält die erzeugten Programme und benötigten DLLs sowie LGPLv3-Text und Drittanbieterhinweise. SHA256SUMS und ein Buildmanifest dokumentieren die Ausgaben.

## Workflow- und Kostenbegrenzung

Der Workflow ist ausschließlich über workflow_dispatch startbar. Er verwendet ubuntu-24.04 und windows-2022 öffentliche Standardrunner, hat Zeitlimits und keine Retry-Logik. Das Toolchain-Image wird vor dem Netzwerkisolierten Build anhand des Digests gezogen. Der Workflow verweigert private Repositories, fordert mindestens 8 GiB freien Runnerplatz und begrenzt die abgelegten Artefakte auf 250 MiB mit drei Tagen Aufbewahrung.

GitHub-Free-Speicher und Kosten wurden unmittelbar vor dem genehmigten Lauf separat geprüft. Genehmigtes Kostenlimit: 0,00 €. Keine Zahlungsmethode oder kostenpflichtigen Dienste verwenden.

## Vorgesehene Artefakte

1. ffmpeg-win64-lgpl-shared-u21bt.zip: FFmpeg/ffprobe, erforderliche DLLs und LGPLv3-Text.
2. ffmpeg-win64-lgpl-source-build-u21bt.zip: korrespondierende Quellen, Rezeptdateien, Änderungen, Buildprotokolle, Toolchain- und PE-Nachweise sowie Hinweise.
3. Buildmanifest und SHA256SUMS.txt.
4. Windows-Smoke-Bericht mit Encodern, Filtern, PE-Imports und dem erzeugten/dekodierten synthetischen MP4.

## Grenzen

Ein erfolgreicher Build oder synthetischer Windows-Smoke-Test allein belegt weder vollständige LGPL-Empfängerpflichten noch kommerzielle Freigabe oder ShyCreator-Kompatibilität. Der GPLv3-Gyan-Build wird nicht verwendet. Laufzeitimporte und tatsächliche Artefaktgröße werden erst durch den genehmigten Lauf bestätigt.
