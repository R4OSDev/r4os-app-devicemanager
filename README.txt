Device Manager
==============

DEVMGR.R4X ist die grafische Hardwareuebersicht fuer Desktop.

Die App nutzt R4XStart und die R4DEV-/R4DESK-/R4DRAW-Vertraege:
- `device_inventory_summary(out)`
- `device_inventory_record(index, out)`
- `net_detail_get(index, out)` fuer Netzwerkadapter ab ABI v60/v61
- `hardware_summary(out)` als aggregierte R4DEV-Hardwareuebersicht ab ABI v93

Damit liest sie echte Laufzeitdaten aus dem Kernel-Inventar statt Terminal-
Konsolenberichte oder Bootlogs als Datenquelle zu nutzen. Die Ansicht gruppiert Geraete nach:
- Erkannte Hardware mit Treiber
- Erkannte Hardware ohne Treiber
- Unknown Device

Seit 0.11.7 enthaelt das Inventar neben Bus-/Controllergeraeten auch die
registrierten Blockdevices. Dadurch zeigt DEVMGR fuer Storage nicht nur den
Controller, sondern auch Eintraege wie `ahci0`, `ahci1`, `nvme0` und
`nvme1` mit Treiber, Status und Notiz. Fuer NVMe wird sichtbar, ob der
Controller nur gefunden, initialisiert, mit nutzbarem Namespace vorbereitet,
als Blockdevice registriert oder bereits als Laufwerk gemountet ist.

Im gehosteten Desktop-Fenster zeigt sie Summary, Tabellenliste und Detaildaten.
Die GUI nutzt seit 0.18.11 staerker `r4os.gui`: Filter und Export laufen ueber
`ToolbarButton`, die Hardwareliste ueber `TableView` inklusive Scrollbar,
Auswahl und PageUp/PageDown/Home/End, die Netzwerkdetailseite ueber `TabBar`
und die grobe Fensteraufteilung ueber `LayoutCursor`. Wenn sie ausserhalb
eines GUI-Fensters gestartet wird, gibt sie dieselben strukturierten Daten mit
Bus, Treiber, Status und Notiz kompakt auf der Console aus und schreibt
denselben Hardwarebericht automatisch nach `C:\Temp\HWREPORT.TXT`, sofern das
aktuelle C:-Laufwerk beschreibbar ist. Im GUI-Fenster bleibt der Export ueber
den Button `Export` oder Taste `E` verfuegbar.

Die Hardwareliste besitzt eine Filterbar mit `All`, `Driver`, `NoDrv`, `Net`,
`Store` und `Proto`. Die Filter koennen per Maus oder ueber die Tasten `A`,
`D`, `M`, `N`, `S` und `P` gewaehlt werden.

Fuer Netzwerkadapter besitzt DEVMGR eine eigene tabbasierte Detailansicht:
`Adapter`, `Protocols` und `TCP`. Die Ansicht nutzt den strukturierten
Netzwerk-Snapshot statt Konsolenberichte zu parsen und zeigt MAC, IPv4, Gateway,
DNS, Lifecycle/Link, RX/TX/Error-Zaehler, Backend-/IRQ-/Pollingstatus, ARP/DHCP/DNS/TCP-
Zaehler, IPC-Service-Zeilen fuer DHCP/DNS/TCP/UDP, R4P-/Fallback-Quellen und bis zu acht TCP-Verbindungen. Wenn der ausgewaehlte
Eintrag der PCI-/PCIe-Netzwerkcontroller ist, ordnet DEVMGR ihn ueber die
PCI-Adresse oder Vendor-/Device-ID dem passenden registrierten NetBackend zu
und zeigt dieselben Tabs.

`DEVMGR.R4X /NETDETAIL` startet im Console-Modus einen Headless-Selftest der
Netzwerkdetail-Zeilen fuer Adapter-, Protokoll- und TCP-Tab. Der Test wird von
`Tests/Runtime/Run-DeviceManagerNetworkTest.ps1` genutzt und
ergaenzt den normalen Export-Smoke. Seit R4X v2 wird kein Stack-Budget mehr im
Header gesetzt; DEVMGR.R4X nutzt die zentrale Start-Stack-Groesse des Loaders.

Projektstruktur seit 0.51.18:
- `build.zig` baut DEVMGR.R4X als eigenes SDK-Projekt.
- `build.zig.zon` bindet `r4os_sdk` als Paket.
- `module.R4MF` beschreibt Artefakt, Zielpfad und Contract.

Build:

    cd Code\System\Software\DeviceManager
    ..\..\..\DevTools\Zig\zig.exe build

Ergebnis:

    Code\System\Software\DeviceManager\zig-out\DEVMGR.R4X

Contract:
- R4XStart-Entry: `devmgr_main`
- App-Klasse: `console`
- R4L-Imports: `R4DESK:Query:1`, `R4DRAW:Query:1`, `R4DEV:Query:1`
- Zielpfad im Image: `C:\R4OS\SOFTWARE\DESKTOP\DEVMGR.R4X`
