# MASSIVE STORE: LOCUST

Survival horror pre Roblox. Si zavretý v **obrovskom opustenom supermarkete**. Cez deň
prehľadávaš obchod, zbieraš jedlo, materiály a vybavenie a staviaš si základňu. V noci
zhasnú svetlá a obchod začne prehľadávať **THE LOCUST** — vysoké, hmyzu podobné stvorenie,
ktoré je každú noc rýchlejšie, lepšie počuje a ľahšie rozbíja steny.

```
LOOT → BUILD → SURVIVE → UPGRADE → PREŽI ĎALŠIU NOC
```

Hotový súbor hry: **`MassiveStoreLocust.rbxlx`** → otvor v Roblox Studiu (*File → Open from File*).

Všetko (mapa, modely, Locust, ikony, UI, zvuky) je vyrobené kódom — nie sú potrebné žiadne
nahraté assety. Hra je pôvodná: nepoužíva nič z 3008 (assety, mapu, mená, UI ani kód).

![Hlavné podlažie (seed 2024)](docs/map_main.png)

---

## Ako to vyskúšať v Studiu

1. Otvor `MassiveStoreLocust.rbxlx`.
2. **Play** (jeden hráč) alebo **Test → Clients and Servers → 2–4 Players → Start**.
3. Po loading screene sa objaví 3D menu → **PLAY → ENTER THE STORE**.
4. Prvý deň trvá 5 minút. Rýchly test noci: v `ReplicatedStorage/Shared/Config` zníž
   `Cycle.FirstDay` a `Cycle.Day` napr. na 30.

> V Studiu nefungujú teleporty, preto **prvý stlačený mód** (Survival / Infection / Hardcore /
> Solo) rozhodne, aký mód testovací server hrá.
>
> **Ukladanie dát:** *File → Publish to Roblox*, potom *Game Settings → Security →
> Enable Studio Access to API Services*. Bez toho hra funguje, len sa XP/kredity neuložia
> (menu ukáže „progress isn't saving“).

### Po publikovaní
- *Game Settings → Places → Max Players* = **12**.
- Kredity za Robux (voliteľné): vytvor 3 Developer Products a ich ID daj do
  `Config.CreditProducts`. Kým sú `0`, obchod píše, že balíčky nie sú nastavené.
- Odporúčaný avatar: R15 (R6 tiež funguje).

---

## Ovládanie

| Klávesa | Akcia |
| --- | --- |
| WASD / Shift | chôdza / šprint (hlučný!) |
| C (alebo držať Ctrl) | krčenie — tichý pohyb, horšie ťa vidno |
| E | interakcia (zobrať, otvoriť, skryť sa, oživiť – podržať) |
| 1–6, klik | držať predmet / použiť (jesť, hodiť svetlicu…) |
| Q | zahodiť držaný predmet |
| Tab | inventár (klik = vybrať, klik na iný slot = presunúť) |
| B | stavanie · R otočiť · klik postaviť · pravý klik zrušiť |
| U / P / X | (v režime stavania, mierenie na stavbu) vylepšiť / opraviť / odstrániť |
| F / R | baterka / vymeniť batérie |
| N | nočné videnie (ak máš okuliare) |
| M | mapa obchodu |
| G / X | pustiť vozík / otvoriť kôš vozíka |
| L | druhá akcia pri dverách / generátore (zamknúť, doplniť palivo) |
| H | emoty |
| Space | vyliezť zo skrýše |

Mobil: tlačidlá USE / RUN / SNEAK / LIGHT / BAG / BUILD + MAP / CART / DROP. Gamepad: R2 použiť,
L3 šprint, R3 krčenie, Y stavanie, D-pad predmety.

---

## Čo v hre je

### Obchod (procedurálny)
Každý server vygeneruje **nový obchod** (`StoreLayout`, seed). Mriežka 20×15 buniek po 80 studov
(≈1600×1200 studov) + podzemie. Prejsť z jednej strany na druhú trvá minúty.

- Oddelenia: Grocery, Drinks, Frozen Foods, Bakery, Food Court, Electronics, Home & Furniture,
  Garden Center, Pharmacy, Toys, Clothing, Restrooms, Staff Only, Stock Rooms, Security Office,
  Warehouse, Loading Docks, Maintenance, Escalators (pokazené eskalátory), Entrance.
- Podzemie **B1**: Parking Garage, Underground Storage, Maintenance Tunnels (otvorí sa na
  **noc 10** alebo kartou Security Keycard).
- **Sealed Wing** (otvorí sa na noc 20) – najlepší loot.
- **Zamknuté miestnosti** (páčidlo / karta) a **skryté miestnosti** za uvoľneným panelom.
- Regály s tovarom, rozhádzaný tovar, palety, vozíky, tabule „AISLE 12“, blikajúce svetlá…
- Skrýše: skrinky, kabínky na WC, pulty pokladní, skrine, kabínky v obchode s oblečením,
  záhradné kôlne, vetracie šachty.

![Podzemie B1](docs/map_basement.png)

### Deň a noc
- **Deň**: Locust spí. Lootuj, staviaj, opravuj. Tímový cieľ dňa dáva XP.
- **Súmrak**: svetlá blikajú, „NIGHT IS COMING“.
- **Noc**: väčšina oddelení úplne zhasne, niektoré bežia na červenom núdzovom svetle,
  objaví sa banner **NIGHT N — THE LOCUST IS HUNTING** a Locust sa zjaví ďaleko od hráčov.
- **Úsvit (6:00)**: odmeny (XP, Store Credits), mŕtvi sa vrátia (do postele, ak si ju
  postavili), obchod sa doplní.
- Keď sú v noci všetci dole → **THE STORE CLAIMED YOU** → výsledky → nový obchod.
- Každých 10 nocí **THE STORE SHIFTS**: otvoria sa nové oblasti, zamknuté miestnosti sa
  znova zamknú s novým tovarom, lepší loot, nové varianty Locusta.

### THE LOCUST (AI)
Nevie, kde si. Musí ťa **vidieť** (zorné pole, tma ho oslabuje, baterka ťa prezradí, krčenie
pomáha), **počuť** (šprint, vozíky, stavanie, generátory, dvere, svetlice…) alebo byť **veľmi
blízko**. Pamätá si, kde sa hráči zdržiavajú a kde sú základne, a vracia sa tam.

Stavy: hliadkovanie → vyšetrovanie zvuku → prehľadávanie → naháňačka → rozbíjanie → ústup.
Ďaleké trasy ide po „pruhoch“ obchodu (A*), blízko používa PathfindingService.
Prekážky: slabé stavby rozbije, vozíky odsunie, dvere otvorí (od noci 2), inak hľadá inú cestu.

Fér pravidlá: keď ťa dlho nevidí, vzdá to; dlhá naháňačka ho „frustruje“; zostrelený
odhodlaním (veže, pasce, obušok) **ustúpi**; do repelentu nevojde; nekempuje pri zrazenom hráčovi.

| Noc | Čo pribudne |
| --- | --- |
| 1 | pomalý (pod rýchlosťou šprintu), slabý, zle vidí v tme |
| 2 | otvára dvere obchodu a odomknuté dvere |
| 3 | rozbíja drevené barikády, učí sa (pamäť), láka ho svetlo základne |
| 4 | prehľadáva skrýše |
| 5 | prehľadáva základne, rozbíja drevené steny a dvere |
| 7 | Shriek – výkrik odhalí hráčov a rozbliká baterky |
| 10 | rozbíja kovové stavby · otvorí sa podzemie |
| 12 | Lunge – výpad na krátku vzdialenosť |
| 15 | rozbíja zosilnené stavby, Light Surge vyradí svetlá |
| 20+ | Advanced stavby, roj Nymf (malí prieskumníci), variant HOLLOW LOCUST |
| 30+ / 40+ | IRON LOCUST / SWARM QUEEN |

Rýchlosť a sila sú zastropované, aby sa dalo vždy prežiť taktikou.

### Prežitie
Zdravie, hlad, výdrž (šprint), energia (spánok v posteli, káva, energetáky).
Pri 0 HP si **zrazený** (plazíš sa, krvácaš) – spoluhráč ťa oživí podržaním E.
Solo: oživíš sa sám lekárničkou. Hardcore: oživenie stojí lekárničku.

### Loot
5 vzácností (COMMON → LEGENDARY), ~45 predmetov: jedlo a pitie, stavebné materiály, nástroje
(baterka, kladivo, páčidlo, svetlice, budík, karta, paralyzačný obušok), batérie, lieky, palivo,
špeciálne (mapa obchodu, repelent, maják zásob, nočné videnie, šťastná minca).
Tisíce miest na loot, každý server iné rozloženie, každú noc vzácnejšie.

### Stavanie
Steny, dvere (zamykateľné), okná, barikády, podlahy/stropy, rampy, stoly, úložné boxy (limitované
sloty), postele (respawn), lampy, kamery, pasce, šokové platne, strážne veže, generátory
a kozmetické dekorácie. Stupne **WOOD → METAL → REINFORCED → ADVANCED**. Materiály sa berú
z inventára aj z vozíka, ktorý tlačíš.

### Elektrina
Generátor (palivo) napája zariadenia v dosahu do svojej kapacity. Došlo palivo →
**THE BASE GOES DARK**. Záložné generátory obchodu treba opraviť a natankovať — potom svieti
celé okolie aj v noci. Generátory sú hlučné.

### Vozíky, tím, udalosti
- Vozíky: tlač (E), kôš je kontajner; vylepšenia košíka a koliesok cez úrovne; hlučné.
- Tím: dávanie predmetov, spoločné stavanie, oživovanie, zoznam preživších so smerom.
- Náhodné udalosti: POWER OUTAGE, SECURITY ALERT, SUPPLY DROP, LOCUST ROAR, LOCKDOWN,
  GENERATOR FAILURE, RARE LOOT.

### Módy
| Mód | |
| --- | --- |
| SURVIVAL | klasika, 1–12 hráčov |
| INFECTION | od noci 2 sa jeden hráč zmení na infikovaného lovca; nákaza sa šíri, ráno zmizne |
| HARDCORE | menej zásob, silnejší Locust, oživenie len s lekárničkou |
| SOLO | pre jedného hráča, samo-oživenie lekárničkou |

Verejné servery hrajú SURVIVAL. Iný mód → hra nájde server toho módu alebo vytvorí rezervovaný
server a teleportuje ťa. **SERVERS** v menu ukazuje bežiace obchody.

### Progres, misie, obchod
- Survival XP za noci, vzácny loot, oživenia, stavanie, objavovanie, tímové ciele, misie.
- Úrovne odomykajú väčší inventár, lepšiu baterku, lepší vozík, vyššie stupne stavieb, tituly.
- **Denné misie** (3 denne) → Store Credits + XP.
- **SHOP** len kozmetika: tituly, outfity, farby baterky, farby vozíka, efekty, emoty, dekorácie
  základne. Nič, čo pomáha prežiť, sa nedá kúpiť.

---

## Štruktúra

```
massive-store/
  default.project.json               Rojo projekt
  MassiveStoreLocust.rbxlx           zostavená hra
  src/ReplicatedFirst/LoadingScreen  cinematic loading screen
  src/ReplicatedStorage/Shared/      zdieľané (server + klient)
    Config        VŠETKY čísla (časy, prežitie, Locust, módy, loot, ekonomika)
    StoreLayout   generátor obchodu (čisté dáta) · Zones · Nav (A*)
    Items, Rarity, Buildables, Cosmetics, Progression, Missions
    InventoryCore, LocustRig, Models, Net, Signal, Util
  src/ServerScriptService/
    Main.server   spustí všetko
    Services/     World, Director, Locust, Survival, Inventory, Loot, Building, Power,
                  Carts, Tools, Defense, Events, Infection, Modes, Shop, Progress, Data,
                  Noise, Prompts, State, RateLimiter
  src/StarterPlayerScripts/
    Main.client   spustí klienta
    Client/       UI, Menu, MenuScene, HUD, InventoryUI, BuildUI, MapUI, PromptUI,
                  Atmosphere, Audio, LocustAnimator, CameraFX, Controls, ClientState
  tests/          testy generátora + headless simulácie servera aj klienta
  tools/          check.sh (lint), test.sh (všetky testy), render_map.py (náhľad mapy)
```

## Úpravy

| Chcem… | Kde |
| --- | --- |
| dĺžku dňa/noci, hlad, rýchlosti, silu Locusta, odmeny | `Shared/Config` |
| veľkosť obchodu, počet zamknutých miestností | `Config.Map` |
| nové oddelenie | riadok v `Shared/Zones` (+ `Fill` v `StoreLayout`) |
| nový predmet | riadok v `Shared/Items` (model aj ikona sa vytvoria samé) |
| novú stavbu | riadok v `Shared/Buildables` |
| kozmetiku | `Shared/Cosmetics` |
| zvuky | `Client/Audio` → tabuľka `LIB` (nahraď `Id` vlastným `rbxassetid://…`) |

Zvuky sú poskladané zo vstavaných zvukov Roblox klienta (`rbxasset://sounds/...`) s efektmi
(pitch, skreslenie, reverb). Pre finálnu atmosféru odporúčam nahradiť ich vlastnými nahratými
zvukmi — stačí zmeniť ID v `LIB`, recepty (vrstvy, efekty) ostanú.

## Bezpečnosť
Klient len **žiada**. Server rozhoduje o všetkom: zdraví, hlade, rýchlosti (aj kontrola
rýchlosti pohybu), inventári (sloty, množstvá, dosah, kto má kontajner otvorený), stavaní
(odomknutia, mriežka, dosah, prekrývanie, materiály), poškodení, XP, kreditoch a nákupoch
(idempotentné spracovanie Robux nákupov). Všetky remotes majú rate-limit.

## Výkon
StreamingEnabled, ukotvené diely bez fyziky, malé diely bez raycastov/tieňov, jeden AI
„mozog“ s tickom 0.2 s, vizuálne efekty (svetlá, blikanie, animácia Locusta, zvuky) len
na klientovi, stav hráča cez atribúty, tímové info 1× za sekundu.

## Testy a build
Potrebné: [Rojo](https://rojo.space) a Luau CLI (`luau`, `luau-analyze`, `luau-compile`).

```
LUAU_BIN=/cesta/k/luau tools/test.sh     # lint + testy + 9 simulácií (server aj klient)
rojo build default.project.json -o MassiveStoreLocust.rbxlx
python3 tools/render_map.py 2024         # náhľad mapy do docs/
```

Simulácie spúšťajú skutočný kód hry na falošnom Roblox engine (virtuálny čas, boti):
viac dní a nocí, Locust (naháňačka, zrazenie, oživenie, skrývanie, rozbíjanie, ústup),
základňa s elektrinou a obranou, všetky udalosti, noc 10 a 25, všetky módy, matchmaking
a celý klient (loading screen, menu, HUD, inventár, stavanie, mapa, výsledky).
Nenahrádzajú test v Studiu (fyzika, vzhľad, zvuky), ale chytia chyby v logike.
