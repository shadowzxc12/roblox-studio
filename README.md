# Kiddo Shop — Roblox shop UI pre deti (simulator štýl)

Bočné menu s ikonami vľavo, STORE okno s oranžovým pruhovaným záhlavím, R$ tlačidlá,
Starter Pack, Server Luck, Game Passes a ponuky vznášajúce sa vpravo —
s animáciami, efektmi (konfety, lesk, lúče) a zvukmi.

Dizajn systém (farby, komponenty, animácie): https://claude.ai/artifact/MBjEgrfa9DZRxWEMVHyeUB

## Ako to dať do Roblox Studia

1. **StarterPlayer → StarterPlayerScripts** → Insert Object → **LocalScript** →
   vlož obsah `src/StarterPlayerScripts/KiddoShop.client.lua`.
2. **ServerScriptService** → Insert Object → **Script** →
   vlož obsah `src/ServerScriptService/ShopReceipts.server.lua`.
3. Stlač **Play**. Vľavo klikni na **Store** (alebo na ponuku vpravo).

## Nastavenie

- `PRODUCTS` v LocalScripte: ID Developer Productov / Game Passov z Creator Dashboard.
  Kým je `id = 0`, tlačidlo spraví len ukážkový efekt (bez platby).
- `REWARDS` v server Scripte: čo hráč dostane po kúpe (bez toho Roblox nákup nepotvrdí).
- `SFX`: zvuky. Teraz sú tam vstavané zvuky Robloxu, vymeň ich za vlastné `rbxassetid://…`.
- Ikony sú emoji — môžeš ich nahradiť obrázkami (ImageLabel s `rbxassetid://…`).
