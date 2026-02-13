# Shamell Red‑Packet Kampagnen – Ops & Analytics Playbook

Dieses Dokument fasst zusammen, wie WeChat‑ähnliche Red‑Packet‑Kampagnen in Shamell laufen – von der Anlage im Admin‑UI bis zur Auswertung. Außerdem skizziert es optionale, zukünftige Erweiterungen für Payments‑seitige Kampagnen‑KPIs.

## 1. Begriffe & Bausteine

- **Official Account**  
  Service-/Merchant‑Profil (z.B. `shamell_bus`) mit Feed, Chat, Locations und Mini‑App‑Verknüpfung.

- **Red‑Packet Campaign**  
  Ein benannter Kampagnen‑Slug pro Official, z.B. `redpacket_newyear`, gespeichert in `RedPacketCampaignDB` in der Official‑DB.

- **Feed‑Item (Promo)**  
  Ein Eintrag im Official‑Feed mit Deeplink in die Payments‑Mini‑App. Für Kampagnen:  
  `deeplink = {"mini_app_id":"payments","payload":{"section":"redpacket","campaign":"<slug>","merchant_official_id":"<accId>"}}`

- **Moments Origin**  
  Moments‑Posts mit Text, der `shamell://official/<account_id>/<campaign_id>` enthält, werden auf Server‑Seite automatisch mit  
  `origin_official_account_id = account_id` und  
  `origin_official_item_id = campaign_id` versehen.

---

## 2. Kampagne anlegen – Schritt für Schritt (Ops/Marketing)

### 2.1 Official Account vorbereiten

1. Öffne `GET /admin/officials` im Browser.
2. Prüfe, ob der gewünschte Merchant/Service schon als Official existiert:
   - Spalten: `ID`, `Name`, `Kind`, `Mini-App`, `Stadt`, `Kategorie`.
3. Falls nicht:
   - Im Block „Neuen Official Account anlegen“ einen neuen Eintrag erstellen:
     - `ID` (z.B. `shamell_bus`),
     - `Kind`: `service` oder `merchant`,
     - `Mini-App ID`: z.B. `payments`, `bus`,
     - `Stadt`, `Kategorie`, `Beschreibung` ausfüllen.
   - Sicherstellen, dass `Enabled` und ggf. `Official` angehakt sind.

### 2.2 Feed‑Kampagne (Promo) anlegen

1. Im Abschnitt **„Feed‑Items (Promos) pro Account“**:
   - Unter „Account wählen“ (`feed_account`) den gewünschten Official auswählen.
2. Klick auf **„Red‑Packet‑Kampagne vorbelegen“**:
   - Dialog fragt nach einer Kampagnen‑ID, z.B. `redpacket_newyear`.  
     Default: `redpacket_<account_id>`.
   - Danach werden automatisch befüllt:
     - `Feed-ID (Slug)` = Kampagnen‑ID,
     - `Typ` = `promo`,
     - `Title` (z.B. „Red‑packet campaign“),
     - `Snippet` (Beschreibung),
     - `Timestamp` = aktueller Zeitpunkt,
     - `Deeplink JSON` mit:
       ```json
       {
         "mini_app_id": "payments",
         "payload": {
           "section": "redpacket",
           "campaign": "<slug>",
           "merchant_official_id": "<account_id>"
         }
       }
       ```
3. Optional: Titel/Snippet/Grafik (`Thumb URL`) anpassen.
4. Button **„Feed‑Item speichern“** klicken.

Damit ist das Marketing‑Asset im Official‑Feed sichtbar. Der Client erkennt über `section='redpacket'` + `campaign` automatisch, dass es sich um eine Red‑Packet‑Kampagne handelt.

### 2.3 Kampagnen‑Stammdatensatz anlegen

1. Im selben Screen `/admin/officials` unterhalb des Feed‑Blocks gibt es den neuen Abschnitt **„Red‑Packet‑Kampagnen“**:
   - Formularfelder:
     - `Kampagnen-ID` – muss exakt mit dem Feed‑Slug übereinstimmen (z.B. `redpacket_newyear`),
     - `Titel` – Anzeigename der Kampagne (z.B. „New Year Red Packets“),
     - Checkbox `Aktiv`.
2. Vorgehen:
   - Sicherstellen, dass der korrekte Official oben bei `feed_account` ausgewählt ist.
   - `Kampagnen-ID` + `Titel` eingeben, `Aktiv` anhaken.
   - **„Kampagne speichern“** klicken.
3. Verwaltung:
   - In der Tabelle „Red‑Packet‑Kampagnen“ pro Account:
     - „Bearbeiten“ lädt die Werte ins Formular zurück.
     - „Aktivieren/Deaktivieren“ toggelt `active` (Soft‑Delete).
   - Die Defaults werden verwendet:
     - im Official‑Profil‑Composer („Issue red packets for this campaign“) als Initialwerte,
     - in den Moments‑Share‑Templates als zusätzliche Info (z.B. „Default: total X, Y recipients“),
     - im Kampagnen‑Analytics‑Dashboard als Referenz (Spalten `Default amount (cents)` / `Default count`).

Hinweis: Die Kampagnen‑ID dient sowohl im Feed‑Deeplink als auch in Moments als Schlüssel (`origin_official_item_id`).

---

## 3. Client‑Flow (Kurzüberblick)

### 3.1 Official → Payments

- Offizielle Kampagnen‑Feed‑Items enthalten einen Deeplink mit:
  - `mini_app_id = "payments"`,
  - `payload.section = "redpacket"`,
  - `payload.campaign = "<slug>"`.
- Im Client (`OfficialAccountFeedPage._openMiniAppById`) wird daraus:
  - `initialSection = "redpacket:<slug>"` für die Payments‑Mini‑App.

### 3.2 Payments → Moments

- In der Wallet‑Übersicht (`PaymentOverviewTab`):
  - Wenn `initialSection` mit `redpacket:` beginnt, wird eine Kampagnen‑ID extrahiert.
  - Der Button „Share to Moments“:
    - ruft `GET /redpacket/campaigns/{campaign_id}/moments_template` auf,
    - wählt EN/AR‑Text aus der Antwort,
    - schreibt diesen in `moments_preset_text`,
    - öffnet die `MomentsPage`.

### 3.3 Moments → Analytics

- Beim Absenden des Moments‑Posts:
  - Server sucht nach `shamell://official/<account_id>/<campaign_id>` im Text.
  - Setzt:
    - `origin_official_account_id = account_id`,
    - `origin_official_item_id = campaign_id`.
- Das Kampagnen‑Analytics‑Dashboard aggregiert dann pro `origin_official_item_id`.

### 3.4 Kampagnen‑Issuing direkt im Official‑Profil

- Im `OfficialAccountFeedPage` (Official‑Profil) wird bei einer aktiven Kampagne ein zusätzlicher Button angezeigt:
  - EN: „Issue red packets for this campaign“
  - AR: „إصدار حزم حمراء لهذه الحملة“
- Dieser öffnet einen kleinen Composer:
  - `Total amount` / `Recipients` werden – falls im Admin gesetzt – aus `default_amount_cents` / `default_count` vorbefüllt.
  - Beim Absenden wird `POST /payments/redpacket/issue` mit `group_id = "campaign:<campaign_id>"` aufgerufen, so dass:
    - Payments‑Analytics die Kampagnen‑Red‑Packets eindeutig zuordnen kann,
    - Moments‑ & Payments‑KPI im Dashboard pro Kampagne zusammenlaufen.

---

## 4. Analytics – Was heute schon vorhanden ist

### 4.1 Official‑Analytics

- `/admin/officials/analytics` zeigt pro Official:
  - Follower‑Zahl,
  - Feed‑Items & letzter Feed‑Timestamp,
  - Moments‑Shares (gesamt / 30 Tage),
  - Red‑Packet‑Shares (Heuristik über Text),
  - Unique Sharers (gesamt / 30 Tage),
  - Shares pro 1k Follower,
  - Kommentar‑Zahlen.

### 4.2 Kampagnen‑Analytics

- Link in `/admin/officials`:
  - „Red‑Packet‑Kampagnen‑Analytics“ → `/admin/redpacket_campaigns/analytics`.

- Dashboard‑Inhalt:
  - Zeile pro `RedPacketCampaignDB`‑Eintrag:
    - `Campaign ID`,
    - `Title`,
    - `Account` + `Kind`,
    - `Status` (`active` / `inactive`),
    - `Moments shares` (gesamt),
    - `Moments (30d)`,
    - `Unique sharers` (gesamt / 30d),
    - `Last share TS`,
    - `Packets issued` / `Packets claimed`,
    - `Amount (total/claimed cents)`,
    - `Default amount (cents)` / `Default count` (sofern im Admin gesetzt).

- Datenbasis:
  - Aggregationen auf `MomentPostDB`:
    - `origin_official_item_id` = Kampagnen‑Slug,
    - Gruppierung pro Kampagne,
    - Zeitfenster 30 Tage für „recent“‑KPIs.

---

## 5. Optionale Erweiterung: Payments‑Kampagnen‑Analytics (Design)

Die aktuelle Lösung misst Kampagnen über Moments‑Shares (Social Impact).  
Für tiefe WeChat‑ähnliche Auswertungen im Zahlungsbereich (z.B. „Wie viele Red‑Packets / welcher Umsatz pro Kampagne?“) wären folgende Schritte sinnvoll.

### 5.1 Datenmodell (Payments‑Service)

**Ziel:** Red‑Packet‑Transaktionen eindeutig Kampagnen zuordnen.

Vorschlag:

- `RedPacket` (in `apps/payments/app/main.py`) um Feld erweitern:
  - `campaign_id: Optional[str]` (max. 64 Zeichen).
- `RedPacketIssueReq` um optionales Feld erweitern:
  - `campaign_id: Optional[str]`.
- Bei `redpacket_issue`:
  - Kampagnen‑ID, falls gesetzt, in `RedPacket.campaign_id` speichern.
- Bei `redpacket_claim`:
  - Zusätzlich zu `Txn.kind="redpacket"` einen Meta‑Tag in der Ledger‑Beschreibung setzen, z.B.:
    - `description="redpacket_claim:<rp.id>; campaign=<campaign_id>"`.

Damit lassen sich Kampagnen anhand von Zahlungen eindeutig identifizieren.

### 5.2 BFF‑API‑Design für Kampagnen‑KPIs (Payments‑Ebene)

Neue Endpoints (Design war ursprünglich skizziert, ist inzwischen in einer ersten Version implementiert):

1. `GET /admin/redpacket_campaigns/payments_analytics`

   **Query‑Parameter:**
   - `campaign_id` (erforderlich),
   - optional `from_iso`, `to_iso` für Zeitfenster.

   **Antwort (Beispiel):**
   ```json
   {
     "campaign_id": "redpacket_newyear",
     "total_packets_issued": 120,
     "total_packets_claimed": 110,
     "total_amount_cents": 2500000,
     "claimed_amount_cents": 2300000,
     "unique_senders": 15,
     "unique_claimants": 320,
     "time_window": {
       "from_iso": "2025-01-01T00:00:00Z",
       "to_iso": "2025-01-31T23:59:59Z"
     }
   }
   ```

   **Ermittlung (aktuelle Implementierung):**
   - `RedPacket`‑Zeilen, deren `group_id` entweder exakt `campaign_id` oder `campaign:<campaign_id>` ist.
   - Optionales Zeitfenster über `RedPacket.created_at` sowie `RedPacketClaim.claimed_at`.
   - Zugehörige `RedPacketClaim`‑Zeilen:
     - zählen Claims und Unique Claimant‑Wallets,
     - summieren `amount_cents`.

2. Integration in bestehendes Kampagnen‑Dashboard

   - Im HTML‑Dashboard `/admin/redpacket_campaigns/analytics` wurden zusätzliche Spalten ergänzt (siehe oben), die die Payments‑KPIs anzeigen.
   - Datenquelle:
     - Beim Rendern optional pro Kampagne ein interner Call auf den neuen BFF‑Endpoint (oder direkt auf Payments, falls `PAYMENTS_INTERNAL` aktiv ist).

### 5.3 Client‑Integration (optional)

Für die meisten Business‑Stakeholder genügt die HTML‑Konsole. Optional könnten wir:

- Einen „Kampagnen‑Details“‑Screen bauen (Web/Flutter), der:
  - Moments‑KPI (bestehende Aggregation),
  - Payments‑KPI (neue Endpoint‑Antwort)
  kombiniert darstellt.

---

## 6. Zusammenfassung

Heute bereits vorhanden:

- Admin‑Flow zum Anlegen von:
  - Official‑Accounts,
  - Red‑Packet‑Feed‑Promos,
  - Red‑Packet‑Kampagnen (Stammdaten).
- Client‑Flows:
  - Official‑Feed → Payments (mit Kampagnen‑Context),
  - Payments → Moments (kampagnenspezifische Share‑Templates),
  - Moments → Kampagnen‑Analytics (social impact).
- Admin‑Dashboards:
  - Official‑Analytics,
  - Red‑Packet‑Campaigns‑Analytics.

Optional / Zukunft:

- Erweiterung des Payments‑Schemas um `campaign_id`,
- Kampagnen‑KPIs direkt auf Transaktions‑Daten,
- Erweiterte Dashboards, die Social + Payments‑Kennzahlen kombinieren.
