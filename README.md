# Kiddo Shop — Roblox shop UI pre malé deti

Veľké tlačidlá, jasné farby, hrubé obrysy. Dizajn systém (farby, písmo, komponenty):
https://claude.ai/artifact/MBjEgrfa9DZRxWEMVHyeUB

## Ako to dať do Roblox Studia

1. Otvor svoj place v Roblox Studiu.
2. V Exploreri: **StarterPlayer → StarterPlayerScripts** → pravý klik → **Insert Object → LocalScript**.
3. Skopíruj doň obsah `src/StarterPlayerScripts/KiddoShop.client.lua`.
4. Stlač **Play** — vľavo je fialové tlačidlo **SHOP**.

Itemy upravíš v tabuľke `ITEMS` (meno, cena, rarita, `image = "rbxassetid://…"`).

> Mince sú v ukážke len na klientovi. V skutočnej hre drž peniaze na serveri
> (DataStore) a nákup rob cez `RemoteFunction`, inak sa dá podvádzať.

## Figma

Farby a rozmery sú v dizajn systéme vyššie — v Figme si ich vytvor ako Variables
(rovnaké názvy: `grape`, `mint`, `sunshine`, `radius-lg`…), aby Figma aj Studio sedeli.
