> **Nová hra v tomto repozitári: [MASSIVE STORE: LOCUST](massive-store/README.md)** —
> survival horror v obrovskom supermarkete (`massive-store/MassiveStoreLocust.rbxlx`).

# STUD CHASE — Roblox multiplayer naháňačka (stud štýl)

Hotový súbor hry: **`StudChase.rbxlx`** → otvor v Roblox Studiu (*File → Open from File*).

Dva herné módy (**NORMAL CHASE** a **INFECTION**), matchmaking s rezervovanými servermi,
loading screen, 3D hlavné menu, výsledky s odmenami, ukladanie dát, cosmetic shop a nastavenia.
Mapy sú jednoduché a v klasickom „stud" štýle (plastové kocky so studs).

## Ako to vyskúšať v Studiu

1. Otvor `StudChase.rbxlx`.
2. **Test → Clients and Servers → 2 Players → Start** (na naháňačku treba aspoň 2 hráčov).
3. V každom okne klikni v menu na **NORMAL CHASE** alebo **INFECTION → PLAY**.
   V Studiu sa teleport nedá použiť, preto sa zápas spustí priamo v testovacom serveri.
4. Po 15 s intermission sa spustí kolo: odhalenie chasera, 3-2-1-GO!, naháňačka, výsledky.

> **Ukladanie dát v Studiu:** *File → Publish to Roblox*, potom
> *Game Settings → Security → Enable Studio Access to API Services*.
> Bez toho hra funguje, len sa coins/XP neuložia.

## Ako to funguje na Roblox serveroch

- Hráč príde do **lobby** (verejný server) → loading screen → 3D menu.
- Vyberie mód → „**Finding Players... 3/12**“ → lobby nájde otvorený zápas toho istého módu
  (zdieľaný cez `MemoryStoreService` naprieč všetkými servermi) alebo vytvorí nový
  **Reserved Server** (`TeleportService:ReserveServer`) a hráčov tam teleportuje.
  Módy sa nikdy nemiešajú.
- Match server hrá kolá dookola. **PLAY AGAIN** = ďalšie kolo, **MAIN MENU** = späť do lobby.

## Štruktúra

```
ReplicatedFirst/LoadingScreen          loading screen (hneď po pripojení)
ReplicatedStorage/
  Remotes/                             všetky RemoteEvents/Functions na jednom mieste
  Modules/Config                       VŠETKY čísla hry (časy, odmeny, rýchlosti, matchmaking)
  Modules/Cosmetics                    katalóg shopu (len vizuálne veci)
  Modules/UIKit, Icons, Sounds, Util   UI stavebnice, kreslené ikony, zvuky
  Assets/Sounds/                       Sound objekty – vymeň SoundId za vlastné
ServerScriptService/
  ServerMain                           jediný server Script: spustí všetko, lobby vs match
  RoundManager                         stavový automat kola (LOBBY…RETURNING)
  TagManager                           chytanie (iba server, cooldown, no tag-back, anti-teleport)
  MatchmakingManager                   fronty, reserved servers, MemoryStore
  DataManager                          DataStore (pcall, retry, session lock, BindToClose)
  RewardManager, ShopManager, RoleManager, MapManager, RateLimiter
  Modes/Normal, Modes/Infection        logika módov (nový mód = nový modul + riadok v Config)
ServerStorage/Maps/Map1..3             mapy (nová mapa = nový Model so Spawns priečinkom)
StarterPlayer/StarterPlayerScripts/
  ClientMain                           jediný klient LocalScript
  MenuController, UIController, CameraController, PanelsController, ClientState
Workspace/Lobby                        čakacia plocha + MenuScene (3D pozadie menu)
```

UI sa vytvára kódom (`UIKit`) do PlayerGui ako ScreenGuis: `LoadingScreen`, `MainMenu`,
`GameModeUI`, `GameUI`, `ResultsUI`, `SettingsUI`, `ShopUI`, `CreditsUI`, `Notifications`.

## Úpravy

| Chcem… | Kde |
| --- | --- |
| dĺžku kola, odmeny, rýchlosť, dosah chytania | `ReplicatedStorage/Modules/Config` |
| novú mapu | Model do `ServerStorage/Maps` s priečinkom `Spawns` (Party `Spawn`, voliteľne `ChaserSpawn`) a atribútom `DisplayName` |
| nový cosmetic | riadok v `Modules/Cosmetics` |
| zvuky / hudbu | `ReplicatedStorage/Assets/Sounds` → `SoundId` (MenuMusic, MatchMusic sú zatiaľ prázdne) |
| mapy cez generátor | `python3 tools/build_maps.py && rojo build -o StudChase.rbxlx` |

## Bezpečnosť

Klient iba **žiada** (vybrať mód, kúpiť, uložiť nastavenie). Roly, chytanie, výsledky, coins, XP
a teleporty rieši server. Remotes majú rate-limit a server kontroluje každý vstup.

`legacy/kiddo-shop/` obsahuje predchádzajúci shop UI demo.
