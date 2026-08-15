# Civ Strategy Analyst — plan aplikacji

## Context

Aplikacja analizuje rozgrywki Civilization 5 + LEKMOD na podstawie logów eventów
(JSONL) produkowanych przez sąsiedni projekt `civ-narrative-logger`. Cel: ustalić,
dlaczego strategia danego gracza wygrywała/przegrywała, oraz wskazać kluczowe momenty
i decyzje. Dane wejściowe: plik JSONL (przykład: `filtered.jsonl`, 4580 eventów,
36 typów), docelowo pliki do kilku MB.

Decyzje użytkownika (potwierdzone):
- **Baza wielu gier** w Postgres (z czasem analiza cross-game).
- **Wynik gry**: podawany ręcznie przy analizie + fallback wnioskowania ze snapshotów
  (w danych nie ma eventu zwycięstwa; gra może być w toku).
- **Interfejs**: CLI jako główny + prosty szkielet UI w Rails (lista gier, widok raportu).
- **LLM**: konfigurowalny od startu (RubyLLM), raporty **po angielsku**.
- **Storage**: zwykła tabela `game_events` z jsonb (NIE Rails Event Store).
- **Testy**: Minitest. TDD: najpierw czerwone testy → review użytkownika → implementacja.

## Kluczowe fakty o danych (z eksploracji `filtered.jsonl` i docs loggera)

- Jedna linia = jeden event JSON; wspólne pola: `event`, `turn`; większość ma `civ`.
- **Duplikaty po restarcie sesji**: `session_started` pojawia się przy każdym
  podpięciu loggera (nowa gra, reload, restart pitbossa) — przykładowy plik ma sesje
  od tury 0 i 149, przez co eventy z tur 149–150 są zdublowane. Dedup jest zadaniem
  konsumenta (potwierdzone w `civ-narrative-logger/docs/design-decisions.md`).
- **Eventy drużynowe**: `tech_researched`, `era_entered`, `war_declared`, `peace_made`,
  `teams_met` mają `team`/`team_a`/`team_b` + tablice `*_civs` zamiast pojedynczego `civ`.
- `snapshot` per cywilizacja per tura: `score`, `science`, `culture`, `gold`,
  `gold_per_turn`, `faith`, `happiness`, `military_might`, `military_units`,
  `population`, `cities`, `techs` — podstawa krzywych metryk.
- `unit_lost` ma `cause` + `confidence`; `improvement_built` czasem bez nazwy;
  niektóre nazwy to surowe klucze (`TXT_KEY_...`).
- `session_started` niesie roster: `players[{civ, name, human, handicap}]` + ustawienia mapy.

## Stack

Rails (najnowszy) + Postgres + Minitest + gem `ruby_llm` (provider konfigurowalny przez
ENV/parametr). Aplikacja w bieżącym katalogu `civ-strategy-analyst/` (git init, częste
małe commity, bez wzmianek o Claude, bez push).

## Schemat bazy

- `games` — name, map_script, map_size, game_speed, max_turns, start_era,
  winner_civ (nullable), victory_type (nullable), completed (bool, default false)
- `players` — game_id, civ, leader_name, human, handicap
- `game_events` — game_id, seq (kolejność w pliku), session_index, turn, event_type,
  civ (nullable — denormalizacja dla zapytań), payload (jsonb);
  indeksy: (game_id, turn), (game_id, event_type), (game_id, civ)
- `analyses` — game_id, model, report (markdown), digest (jsonb — pakiet wysłany do LLM),
  created_at

## Architektura (3 warstwy)

### 1. Import (`ImportGame`)
Streamingowy parser JSONL (linia po linii — pliki do kilku MB, bez ładowania całości).
Tworzy `Game` + `players` z pierwszego `session_started`. Śledzi granice sesji
(`session_index++` przy każdym `session_started`). **Dedup**: odrzuca event, jeśli
identyczny (turn, event_type, payload) wystąpił w *innej* sesji (restart replayuje
końcówkę); duplikaty wewnątrz jednej sesji są legalne i zostają.

### 2. Projekcje deterministyczne (czyste klasy Ruby, czytają eventy z bazy)
- `MetricSeries` — krzywe per civ ze snapshotów: wartości, delty, ranking w czasie,
  punkty przecięcia (zmiany lidera).
- `PlayerTimeline` — per civ: miasta (założone/zdobyte/utracone), techi (rozwiązanie
  team→civs), polityki/gałęzie, religia (pantheon→founded→enhanced), wojny (agresor/
  obrońca, bilans strat i zdobyczy), wielcy ludzie, ery, golden age'y, city-states.
- `KeyMomentDetector` — heurystyki kluczowych momentów: wypowiedzenia wojen i ich
  bilans (zdobyte miasta, spike'i `unit_lost`), zmiany lidera score/science, kolejność
  wejść w ery (przewaga technologiczna), założenie religii, załamania `military_might`
  (spadek > próg), trwała dywergencja nachylenia score (moment "snowballu"),
  nuklearne detonacje, przejęcia sojuszy city-states.
- `OutcomeResolver` — winner/victory_type z parametrów użytkownika, inaczej lider
  ostatnich snapshotów + oznaczenie "game in progress" (turn < max_turns, brak wyniku).

### 3. Warstwa LLM (`AnalyzeGame`)
Buduje **kompaktowy digest** (JSON, rzędu 10–20 kB — nie surowe 500 kB): roster,
ustawienia, wynik/stan gry, per-civ podsumowania metryk w checkpointach (co ~25 tur),
timeline'y, lista kluczowych momentów z heurystyk. Wysyła przez RubyLLM (model
konfigurowalny, per-run override) z promptem "Civ 5 strategy analyst". Raport po
angielsku, sekcje: final standings, per-player strategic verdict (why winning/losing),
key moments, decisive decisions, counterfactuals. Zapis do `analyses` + plik
`reports/<game>-<timestamp>.md`. Testy z klientem LLM za stubem (bez sieci).

### Interfejsy
- CLI: `bin/civ import path.jsonl [--name ...]`,
  `bin/civ analyze GAME_ID [--winner Chile] [--victory-type domination] [--model ...]`,
  `bin/civ list` (cienkie wrappery na serwisy).
- UI szkielet: `GamesController#index` (lista gier + status analizy), `#show`
  (standings, kluczowe momenty, raport markdown przez `redcarpet`/`commonmarker`).
  Bez wykresów na razie.

## Kolejność iteracji (każda: czerwone testy → review → implementacja → commit)

1. **Szkielet**: `rails new` (Postgres, Minitest), migracje `games`/`players`/
   `game_events`/`analyses`, modele z walidacjami.
2. **Import + dedup**: testy na parsowanie linii, roster z `session_started`,
   granice sesji, dedup cross-session (fixture z fragmentem prawdziwego pliku),
   odporność na nieznane typy eventów (loguj i kontynuuj).
3. **MetricSeries** (snapshoty → krzywe, ranking, zmiany lidera).
4. **PlayerTimeline** (w tym rozwiązanie eventów drużynowych team→civ).
5. **KeyMomentDetector** (heurystyki po jednej — każda osobny mały cykl TDD).
6. **OutcomeResolver** + **DigestBuilder** (digest jako czysta struktura — łatwe asercje).
7. **AnalyzeGame + RubyLLM** (stub klienta; prompt jako wersjonowany szablon w repo).
8. **CLI** (`bin/civ`).
9. **UI szkielet** (2 widoki).

Import przykładowego `filtered.jsonl` jako smoke test od iteracji 2.

## Weryfikacja end-to-end

- `bin/rails test` — zielone po każdej iteracji.
- Po iteracji 2: `bin/civ import filtered.jsonl` → sprawdzić liczbę eventów po dedupie
  (< 4580, dokładna liczba do ustalenia testem) i roster 4 graczy.
- Po iteracji 7: `bin/civ analyze 1 --model <tani model>` na prawdziwym pliku →
  raport w `reports/`, ocena jakości digested promptu ręcznie.
- Po iteracji 9: `bin/rails server` → lista gier i raport w przeglądarce.

## Poza zakresem (świadomie, na później)

API przyjmujące eventy, wykresy w UI, analizy cross-game (schemat je umożliwia),
automatyczny watcher plików, porównania wielu analiz LLM.

## Status implementacji

Wszystkie 9 iteracji zaimplementowane (TDD, czerwone testy → review → implementacja,
commit per iteracja/heurystyka). 89 testów, zielone. Zobacz `README.md` po instrukcje
uruchomienia.

## Pomysły niezaimplementowane / na przyszłość

- **Korelacja panteonów/wierzeń ze zwycięstwem (cross-game)** — pomysł zgłoszony przez
  użytkownika przy okazji `KeyMomentDetector#religion_foundings`: śledzić, które
  wierzenia (pantheon i religia założona) gracze wybierają w wielu grach, i ocenić,
  które z nich częściej korelują ze zwycięstwem. Wymaga warstwy cross-game analysis
  (patrz "Poza zakresem" wyżej) — dane per gra już są dostępne przez
  `PlayerTimeline#religion` + `OutcomeResolver`, brakuje tylko agregacji między grami.
  Zapisane też w pamięci Claude (`idea-belief-winrate-analysis`).
- **Rozmiar digestu LLM** — `DigestBuilder` daje ~52 kB na `filtered.jsonl` zamiast
  zakładanych 10–20 kB (dominują `timelines.city_states` i `timelines.techs/policies`).
  Świadomie zostawione bez przycinania do czasu oceny jakości promptu na prawdziwym
  LLM (iteracja 7) — jeśli rozmiar/koszt/jakość odpowiedzi faktycznie przeszkadza,
  najpierw skrócić `city_states` do podsumowania (ostatni status sojuszu per city-state
  zamiast pełnej listy zmian przyjaźni), potem ew. `techs`/`policies` do samych liczników.
- **Inne metryki w `MetricSeries`/`KeyMomentDetector#snowballs`** — obie klasy są już
  generyczne względem nazwy metryki (dowolny klucz z payloadu `snapshot`: `culture`,
  `gold`, `faith`, `happiness`, `military_units`, `population`, `cities`, `techs`...),
  więc dodanie nowej metryki do analizy nie wymaga zmian w kodzie — tylko wywołania
  z inną nazwą stringa.

## Plan: wstrzykiwanie danych LEKMOD do digestu (zaplanowane, nie zaczęte)

Kontekst: modele LLM znają reguły podstawowej gry (BNW), a nie LEKMOD — nie znają
cywilizacji dodanych przez mod (Chile, Vietnam, Bolivia...) ani zmienionych efektów.
Dane referencyjne per wersja moda leżą już znormalizowane w `db/lekmod/<wersja>/`
(patrz `db/lekmod/README.md`; procedura dodania nowej wersji: `script/normalize_lekmod`).
Kluczowa pułapka: logi gier identyfikują polityki/tenety/wierzenia wewnętrznymi
vanillowymi ID, które LEKMOD zachowuje mimo zmiany wyświetlanej nazwy
(`POLICY_MERCHANT_NAVY` → "Colonialism", `BELIEF_WALLS` → "Goddess of Protection") —
pliki referencyjne mają te ID inline i matchować należy po ID, nie po nazwie.

Iteracje (każda: czerwone testy → review → implementacja → commit):

1. **`lekmod_version` na `games`** — migracja (string, nullable — stare importy bez
   wersji), flaga `bin/civ import --lekmod-version 34.15`, przechowanie w `ImportGame`;
   override `bin/civ analyze --lekmod-version` dla już zaimportowanych gier.
   `session_started` dziś nie niesie wersji moda ("Lekmap v5.2" w `map_script` to
   wersja mapy, nie moda) — patrz punkt "poza tym repo" niżej.
2. **`LekmodReference`** — czysta klasa czytająca `db/lekmod/<wersja>/`:
   - rozwiązywanie wersji: dokładna → najbliższa starsza (z notką o rozbieżności) →
     brak (z notką, że szczegóły rulesetu niedostępne);
   - ekstrakcja per encja: sekcja `## Civ (Leader)` z `civilizations.md` po nazwie civ
     z rosteru; wpisy z `policies.md`/`ideologies.md`/`religion.md` po ID
     (`POLICY_*`/`BELIEF_*`) występujących w timeline'ach gry; `general.md` w całości
     lub sekcjami (decyzja przy implementacji — patrz uwaga o rozmiarze digestu wyżej).
3. **Rozszerzenie `DigestBuilder`** — nowy klucz `lekmod` w digeście:
   `{version, resolution_note, civilizations, beliefs, policies, general_rules}`.
   Wstrzykiwać tylko encje obecne w tej grze (roster/timeline), nie całe pliki.
4. **Prompt v7** — notka: ruleset to LEKMOD; tam gdzie digest podaje opisy
   uników/wierzeń/polityk, opierać się na nich, a nie na wiedzy o grze bazowej;
   przy braku danych referencyjnych zaznaczać niepewność zamiast uzupełniać vanillą.
5. **Weryfikacja end-to-end** — `bin/civ analyze` na chile-vs-vietnam z v7+digest
   i porównanie A/B z raportami v5/v6 w `reports/` (ta sama gra, kolejne wersje promptu).

Poza tym repo: patch do `civ-narrative-logger`, żeby `session_started` emitował wersję
aktywnego moda (Lua `Modding.GetActivatedMods()` daje ID + wersję) — wtedy flaga
z iteracji 1 staje się fallbackiem dla starych logów.
