# DÉGEL — Roadmap

*État du chantier et plan pour la suite. À mettre à jour après les sessions importantes.*

---

## Décisions stables

- **Moteur** : Godot 4.6.3 — GDScript — tour-par-tour — GL Compatibility — pas de 3D
- **Convention** : identifiants en anglais, commentaires en français
- **Architecture** : simulation découplée de l'UI via `GameState` autoload + sous-systèmes + configs en Resources (`.tres`)
- **Localisation** : FR/EN, locale FR par défaut, CSV unique
- **Mode de travail** : 1 séance = 1 étape qui tourne, cadrage de design avant code, commits étape par étape

---

## Pattern UI

Architecture stabilisée après le chantier d'extraction de la Phase 8 :

- **Vues transversales** dans `res://scenes/ui/*.tscn` (production, infos, survivors, resources_bar, buttons, colony, map)
- **Vues de bâtiment** dans `res://scenes/ui/buildings/*_view.tscn`, référencées par `BuildingConfig.view_scene`
- **Composition** : MainUi = layout + instanciation. Chaque vue s'abonne directement à GameState pour ses refreshs et expose `setup(b)` si elle est liée à un bâtiment.
- **Coquille minimale (B1)** : `.tscn` = un Control racine, script construit le contenu dynamique. À étoffer quand les assets arriveront.
- **Helpers partagés** : `UiPresentation` (statics) pour labels, icônes, sprites, panels, popups.

---

## ✅ Jalons accomplis

### Phase 1 — Squelette de simulation

Simulation pure (énergie, réveils, nourriture, famine, fin de partie), roster avec IDs stables, UI lisible style Colonization, pool de candidats + recherche ciblée, carte hexagonale, localisation FR/EN.

### Phase 2 — Énergie en flux pur

`reactor_output` décroît tous les N tours, fin de run REACTOR_DEAD à 0. Coûts d'élec en flux (wakes, synthé), pas de réserve. Extinction nominative des cryos si élec négative. Signal unifié `nightly_deaths` + popup "News from the bunker" + nécrologie.

### Phase 3 — Système de bâtiments complet

Modèle data-driven `BuildingConfig.tres`. 4 starters (computer, cryo_room, synthesizer, construction_zone) + constructibles (campfire, canteen, tool_workshop). Construction par placement, consommation ordonnée des ressources, chantiers en pause possibles, switch auto à fin de chantier. Bâtiments opérationnels avec transformations input → output.

### Phase 4 — Refonte UI initiale

Vue colonie 4×3 (bunker bleu froid / colonie brun chaud), sprites colons (6 variantes via `sprite_variant`), carte hexagonale en `Polygon2D` avec sprites workers et icônes de production en arrière-plan. Settlement comme tuile centrale. Affichage activité contextuelle. Tri par `wake_order`.

### Phase 5 — Modèle Activity

Les jobs génériques (FARMER/LUMBERJACK/MINER) deviennent des **activités** spécifiques par couple `(activity, tile_type)`. Resource `Activity.tres` (id, name_key, allowed_tile_types, produced_resource, inputs, success_rate, tile_health_delta). `ActivityRegistry` + `Survivor.activity_id`. 7 activités initiales. Activités risquées (chasse) avec tirage au tour. Dégradation forêt par bûcheronnage non compensé, mutation FOREST → PLAINS.

### Phase 6 — Refonte du panneau production

Tableau 4 colonnes : Consommé / Stock / Impossible. Ligne séparée pour les activités risquées avec leur taux de succès. Resserrement automatique des icônes. Ressources non-stockables (electricity, heat) : déficit traité comme impossible. Ressource `meal` + bâtiment `canteen` (pas encore consommée prioritairement).

### Phase 7 — Refacto TurnResolver (critique)

**Source unique de vérité** pour la résolution d'un tour, élimine la duplication entre exécution (`game_state.advance_turn`) et prédiction (UI). `TurnResolver.compute_flow()` (bilan déterministe, sans modif) + `TurnResolver.execute_turn()` (applique réellement, avec aléatoire). Ordre canonique : risky → tile_production → construction → buildings → repas → extinctions → morts. L'UI ne contient plus aucune logique de simulation.

### Phase 8 — Cleanup UI

Refacto progressive de la dette accumulée. `main_ui.gd` passe de **1573 → ~140 lignes (~91% de réduction)** en 10 séances.

- **8.1 — Suppression du legacy Job.** `enum Job`, `var job_outputs`, fonctions mortes (`_on_tile_popup_selected`, `_aggregate_production`). Commentaires obsolètes nettoyés.
- **8.2 — Helpers UI extraits.** Création d'`UiPresentation` (static funcs, `res://scenes/ui/`) : labels, icônes ressources/production, sprites survivants, panels slot, popups d'affectation.
- **8.3a–j — Toutes les vues extraites.** Pattern uniforme : `.tscn` coquille B1 + script `class_name XxxView`, self-subscribed à GameState. Vues transversales : `ProductionView`, `InfosSection` (+ journal d'événements via `GameEvent`/`event_log`), `SurvivorsView`, `ResourcesBar`, `ButtonsSection`, `ColonyView` (orchestrateur grid + mode placement), `MapView`. Vues de bâtiment dans `buildings/` : `CryoView`, `ComputerView`, `SynthesizerView`, `ConstructionZoneView`, `GenericBuildingView`. Dispatch data-driven via `BuildingConfig.view_scene`. MainUi devenu coordinateur léger.

Conséquence stratégique : ajouter un bâtiment ne nécessite désormais qu'un `.tres` + une `.tscn` (ou réutiliser `generic_building_view`). Le terrain est prêt pour la phase data-driven complète.

### Phase 9 — Data-driven complet : roster, tribus, professions

Migration de `Roster.NAMES` / `PROFESSIONS` hardcodés vers un système entièrement data-driven, branché sur le manifest central `GameRegistry`.

- **`Profession.tres`** : id, name_key, tribu, rareté (enum `Rarity { ABSENT, ELITE, RARE, UNCOMMON, COMMON }`), `min_count` (garantie de présence), sprite.
- **`Tribe.tres`** : catégorie narrative invisible au joueur, support du futur système d'événements. 8 tribus posées : ruling_elite, finance, useless_tech, useful_elite, artistic_elite, liberal_professions, services, practical.
- **28 professions** réparties dans les tribus avec rareté graduée. Garanties de présence sur les pratiques (subsistence_farmer, auto_mechanic, practical_nurse) et le chef étoilé, pour ne pas laisser ces tribus statistiquement absentes.
- **Tirage pondéré** : poids `RARITY_WEIGHTS` (ABSENT=0, ELITE=1, RARE=3, UNCOMMON=10, COMMON=30). Étape 1 honore les min_count, étape 2 remplit au tirage pondéré. ABSENT permet de griser une profession dans un scénario sans la supprimer.
- **`Survivor.profession`** : passé de `String` (display name) à `StringName` (id). `Roster.display_name(id)` pour l'affichage immédiat, `Roster.name_key(id)` pour les logs d'événements avec préfixe `"tr:"` (traduction différée). Migration de tous les callers : game_state, turn_resolver, production_system, computer_view, cryo_view, map_view, survivors_view, ui_presentation, buttons_section.
- **Cache statique** : `Roster._professions_by_id` construit au premier appel pour lookup O(1). Sans ce cache, le jeu lagguait massivement (3 secondes par action) — bug surpris dès le premier test, corrigé immédiatement.
- **Sprites par profession** : champ `Profession.sprite` lu par `UiPresentation.survivor_sprite()` et `MapView`. Fallback générique sur `sprite_variant` tant que les sprites ne sont pas tous fournis.
- **GameRegistry étendu** : `tribes`, `professions`, `names` ajoutés au manifest central. Tout le contenu roster édité dans l'inspecteur, zéro code à toucher pour ajouter une profession.

Conséquence stratégique : la couche narrative à venir (Jalon 7) trouve déjà ses crochets posés — tribus pour les événements de groupe, professions pour les événements ciblés, sprites pour la caractérisation visuelle.

### Build & livraison

Build Windows exportable (BuildingRegistry/ActivityRegistry chargent via listes explicites, `DirAccess` ne marche pas dans les exe exportés).

---

## 🎯 Cap thématique : « Évoluer pour survivre » dans le moteur

Le one-pager pose une thèse forte : **on survit en cessant d'être ce qu'on était**. Pour que ce propos vive *avant même* la couche narrative, il doit s'incarner dans la mécanique de gestion.

Deux mécaniques actuelles le portent déjà :

1. **Modèle Activity contextuel** : on n'est pas "bûcheron", on *fait du bûcheronnage en forêt ce tour-ci*. L'identité est dans le devenir, pas dans le métier figé.
2. **Tension tech → reconversion** (à concevoir) : la communauté est tirée vers la reconstruction de l'ancien monde, bute sur des impossibilités, doit se réinventer.
- **Bonus/malus de production par profession** (prochaine séance). Que des bonus dans le contenu pour l'instant (base = les dépassés), mais le système gère bonus *et* malus pour accueillir la fatigue à venir. Trois axes : activité, construction, opération bâtiment. Filtre optionnel par ressource produite (cuistot = food). Arrondi `round`. Crochets posés en Phase 9.
À approfondir : lassitude par répétition (rotation organique, pas réglementaire), chaînes de production qui ne peuvent pas se boucler complètement (signature thématique), caractéristiques humaines acquises (pas des métiers, des traits).

---

## 🛠 Backlog prioritisé

### Data-driven : où on en est

Ajouter ou retirer une ressource, un bâtiment ou une activité se fait désormais **sans toucher au code** : on crée un `.tres` et on le glisse dans `res://resources/game_registry.tres` via l'inspecteur. Les trois registries (`ResourceRegistry`, `BuildingRegistry`, `ActivityRegistry`) lisent ce manifest central au démarrage et exposent leur API habituelle.

- ✅ **Bonus/malus de production par profession.** Trois axes sur `Profession.tres` : `activity_modifier`, `construction_modifier`, `building_modifier`. Filtre commun `modifier_resource_filter: Array[StringName]` qui matche input ∪ output côté bâtiment et la ressource produite côté activité. Trois helpers privés dans `TurnResolver` (`_activity_modifier`, `_construction_modifier`, `_building_output_modifier`). Arrondi `round`. Système accepte malus (futur : fatigue), contenu actuel = que des bonus thématiques. Subsistance_farmer testé : +20% en food, visible partout.
- ✅ **Calcul de yield centralisé.** `TurnResolver.compute_activity_yield(raw, s, resource)` est la source unique pour la production d'activité (famine + modifier profession). Appelée par les 3 sites de résolution interne et exposée via `GameState.expected_activity_yield(s, tile, activity)` pour l'UI (popup d'assignation, icônes de carte, overlay risky). `GameState.get_survivor_output()` passe par là aussi désormais. Sans cette centralisation, le modifier profession apparaissait dans la ProductionView mais pas sur la carte — bug classique "l'UI ment au joueur" résolu.
- ✅ **Intensité de bâtiment.** Régime sélectionnable 1→N par bâtiment via slider (défaut à `max(1, max_intensity / 2)`). Champ `max_intensity` sur `BuildingConfig`, instance porte `current_intensity`. Multiplie inputs ET outputs au prorata, helper `TurnResolver._building_multiplier()` factorise (niveau × intensité). Campfire passé à 1 wood → 1 heat unitaire, max_intensity = 5.
- ✅ `ResourceType` + `ResourceRegistry` (champs : `id`, `name_key`, `icon`, `stackable`, `max_stock`, `display_order`)
- ✅ Manifest central `GameRegistry` regroupant ressources, bâtiments, activités
- ✅ Recettes d'activité et de bâtiment éditables via `.tres` (déjà le cas, mais maintenant déclarées via le manifest)
- ✅ `is_bunker_building: bool` sur `BuildingConfig` (remplace `BUNKER_BUILDING_IDS` hardcodé dans ColonyView)
- ✅ `synthesizer` : coûts élec lus depuis `synthesizer.tres > inputs.electricity` (constantes `SYNTH_*` mortes supprimées de `GameState`)
- ✅ `Roster` complètement data-driven : Tribe + Profession en `.tres`, tirage pondéré par rareté, garanties via min_count, sprites par profession
- `GameState.resources` reste indexé par string (le `ResourceType` est une fiche descriptive accessible via le registry — pas d'indirection par objet, par anti-scope)

### Mécaniques de gestion à ajouter

- **Priorité de consommation des meals.** Les meals existent (canteen produit du meal), mais ne sont pas consommés prioritairement à la place de la food brute.
- **Sources multiples vers une même réserve.** Plusieurs icônes/sprites pour une même ressource (fraises, blé, gibier, synth → tous en `food`). Visualisation différenciée sur carte et prod view, compteur unique en réserve.
- **Substitution de ressources.** Certains bâtiments avancés acceptent l'un *ou* l'autre input (heat ⊕ electricity).
- **Améliorations de bâtiments** (niveau 1 → 2 → 3). Les champs existent dans `BuildingConfig`, à brancher avec coût d'upgrade et UI dédiée.
- **Bilan ressources ordonné** (polish d'équilibrage). Pouvoir exprimer des séquences en blocs (`5 wood, 5 ore, 5 wood, 5 tools`) plutôt que `build_order` linéaire.

### Carte & territoire

- **Outils + déboisement actif.** Action sur la carte pour transformer une tuile, consomme outils, change le type de tuile.
- **Accès au deuxième cercle.** Construction de chemins (coût en outils) qui débloquent les tuiles plus éloignées.
- **Rivière comme élément de carte.** Apparaît par événement, débloque l'irrigation des plaines.
- **Map scrollable** pour les territoires lointains (futur).

### Système d'événements (Jalon 6 préparatoire)

- **Premier système d'événements minimal.** Au minimum pour débloquer la zone de construction (qui est starter aujourd'hui, devrait être un event). Ouvre la voie au narratif.
- **News popup étendu** vers un vrai journal du tour (déjà en place via `event_log`, à enrichir).

### Direction graphique

- Tile-sets hex en pixel art (en cours, contribution fils d'Anthony)
- Sprites colons : variations via shader palette swap (au lieu de variantes pré-rendues)
- Icônes ressources sur grille plus fine (overlay deficit, etc.)
- Sprite "bâtiment en construction" qui évolue avec les ressources consommées
- **Z-order et superposition des panneaux UI** : plusieurs vues se chevauchent en transparence (ProductionView lisible sous les boutons, SurvivorsView invisible quand recouverte). À traiter au polish visuel.

---

## 🔮 Jalons à venir (conception)

### Jalon 6 — Couche relationnelle

Moteur d'observation passive : quels signaux mesurer, où les stocker, comment les exposer aux événements. Trois critères à tenir (cf. one-pager) :

1. Signaux lisibles dans la fiction
2. Événements ressentis comme causés
3. Conséquences qui bouclent sur la gestion

Signaux candidats : cohabitation, travail partagé, événements vécus ensemble, décisions du joueur, bien-être alimenté par les repas.

### Jalon 7 — Couche narrative + arc principal

Structure d'événements (scriptés + procéduraux), choix moraux à conséquences durables, aspirations cachées révélées, caractéristiques acquises. **Arc narratif principal** portant la question dramatique : *que devient cette communauté ?*

### Pistes en cristallisation

- **Travail comme état, pas identité.** Lassitude par répétition fait baisser l'efficacité. Caractéristiques acquises = traits humains, pas métiers. Bâtiments/techs débloquent des roulements automatisés.
- **Bunker computer comme voix narrative.** Interface de tutoriel et de guidage qui parle au joueur.
- **UI d'assignation bidirectionnelle façon Colonization** (polish prioritaire). Quand on clique sur une case : voir tous les personnages avec leur localisation actuelle et leur production sur cette case spécifique. Quand on clique sur un personnage : voir toutes les cases avec leur meilleure production possible si on le déplaçait. Révèle visuellement le système de bonus profession qui vient d'être mis en place, et conditionne sa lisibilité côté joueur.
---

## 🐛 Bugs à diagnostiquer

À traiter en séances dédiées quand l'envie passe par là :

- **Bug d'affichage `usable` électricité.** Le label affiche "synth: -3" mais l'usable ne reflète pas la déduction. Hypothèse : `synth.active` est true sans worker, ou conso pas déduite au bon moment dans TurnResolver.
- **Doublon de colonne "impossible"** dans `ProductionView._make_row` : la colonne 4 est ajoutée deux fois (FIXME dans le code). Visuel à diagnostiquer.
---

## 🏗 Dettes architecturales

À reprendre quand le contexte se présente — pas urgentes :

- **`necrology` redondant** avec `event_log` filtré sur `category == "loss"`. Migration possible.
- **Signal `nightly_deaths` mal nommé** : porte tous les events du tour, pas seulement les morts. À renommer (`turn_news` ou `nightly_events`).
- **`construction_started` réutilisé pour rafraîchir l'UI** (deux call sites avec `# rafraîchir` en commentaire dans `game_state.gd`). Un vrai signal de refresh manque.
- **Doublon `_find_building` vs `_find_building_by_type`** dans `GameState`. Fusion à faire en passant.
- **Layout colony hardcodé** (`COLONY_SLOTS=12`, `STARTER_SLOTS`) dans `ColonyView`. À déplacer dans une Resource configurable quand l'équilibrage l'exigera.
- **Ordre des bâtiments dans `_resolve_buildings_operation`** : premier servi sur les inputs partagés. Acceptable, à raffiner si gênant.
- **UI/loc encore branchées sur strings hardcodées — migration en cours.** `GameState.resources["food"]` reste la clé d'accès (par design). Côté affichage : `UiPresentation.resource()`, `UiPresentation.resource_icon()`, `ResourcesBar` et `ProductionView` migrés sur `ResourceRegistry`. Restent à migrer au fil des touches : `InfosSection` (affichage électricité/heat) et autres callsites qui hardcodent encore des noms de ressources.
- **Signal `building_assignment_changed` au nom trop étroit.** Sert désormais à refresh sur : assignation, toggle synth, changement d'intensité. À renommer (`building_settings_changed` ou `building_state_changed`) en cohérence avec les dettes déjà nommées sur `nightly_deaths` et `construction_started`.
---

## 🧹 Dettes mineures

À traiter sans urgence, voire à laisser tant que ça ne pose pas problème :

- **`OVERLAY_PATH` et `RESOURCE_SPRITE_PATH`** partagent la même valeur dans `UiPresentation`. Sémantiquement différents, factuellement identiques. À découpler quand les vrais assets d'overlay seront créés.
- **`CryoView` n'a pas de `setup(b)`** (ColonyView gère via `has_method`, hétérogène). À homogénéiser quand on touchera CryoView pour les évolutions visuelles (sprites de chambres en background).
- **Risque de popups multiples** ouverts simultanément entre les vues. Pas observé en jeu. Si UX en souffre → extraire un `PopupManager`.
- **Pas de virtualisation du journal UI** — 1 Label par event. À 1000+ events, à surveiller.
- **Pas de save state.** À ajouter quand la boucle de gameplay sera plus solide. Le journal est facilement sérialisable (Array de Dictionary).
- **Vue avec positions absolues = `await process_frame` initial.** Pour l'instant uniquement MapView. Si une nouvelle vue similaire émerge, reproduire le pattern.
- **Audit `translations.csv`** : clés vraisemblablement mortes à grep et supprimer si confirmé : `JOB_*` (enum supprimé en 8.1), `DEATH_*` (remplacés par `EVENT_DEATH_*`), `LABEL_FOOD/WOOD/ORE/HEAT/REACTOR/SYNTH_COST/USABLE/ELEC_HEADER` (anciens labels), `LABEL_SYNTH_TOGGLE` (ancien checkbox synthé), `ROLE_GATHERER/FARMER/HERBALIST/LUMBERJACK/MINER` (anciens roles d'activité). Doublons quasi-identiques à fusionner : `POPUP_NEWS_TITLE`/`NEWS_TITLE`, `POPUP_NEWS_PREFIX`/`NEWS_INTRO`, `BTN_ASSIGN`/`BTN_ASSIGN_WORKER`. Sections "à auditer" déjà marquées dans le CSV.
- **`MapView` duplique la logique de chargement de sprite survivant.** Lignes ~186 charge directement `SURVIVOR_SPRITE_PATH` au lieu de passer par `UiPresentation.survivor_sprite()`. Le bug "sprites flous" qui vient de tomber est exactement ce que cette duplication produit. À factoriser quand on touchera MapView pour autre chose.
- **`Survivor.sprite_variant` à retirer une fois tous les sprites profession en place.** Aujourd'hui sert de fallback quand `Profession.sprite` est null. Quand le pool sera complet (et avant ça, la décision sur le système de variants pour représentativité — voir one-pager), `sprite_variant` et `SURVIVOR_SPRITE_PATH` deviendront morts.
- **Signal `targeted_wake_failed` émis dans le vide.** Plus aucun handler ne l'écoute depuis l'extraction de la phase 8. Du coup, échec de recherche ciblée = élec dépensée silencieusement, aucun feedback au joueur. À rebrancher dans `ComputerView` ou dans le journal d'événements.
- **Affichage des bonus profession dans l'UI d'assignation.** Mécanique en place et fonctionnelle, mais le joueur voit "+4 food" sans savoir que c'est un bonus profession (vs. "+3 de base"). À révéler via la prochaine refonte UI d'assignation bidirectionnelle (voir backlog "Refonte sélection sur tuile façon Colonization").
- **Erreur Godot `_push_unhandled_input_internal: !is_inside_tree()`.** Warning interne récurrent, probablement lié à un popup qui se `queue_free` pendant qu'il a encore le focus. Pas reproductible en pattern clair pour l'instant, à surveiller.
---

## 🎯 Indicateurs de santé du projet

À surveiller au fil des jalons :

- La boucle de jeu reste-t-elle simple à expliquer ?
- Chaque ressource a-t-elle un usage clair ?
- Le harsh est-il tenable ou frustrant ? À éprouver en playtest.
- Les personnages sont-ils encore interchangeables ? Tant que oui, le cap thématique n'est pas franchi.
- La gestion seule tient-elle plusieurs runs ? Test à passer avant la couche relationnelle.
- L'UI ment-elle au joueur ? Plus depuis le TurnResolver — à confirmer en jeu prolongé.

---

## 📋 Tech & process

- **Engine** : Godot 4.6.3, GDScript, GL Compatibility, pas de 3D
- **Structure projet** :
  - `res://systems/core/` : game_state, game_config, tile_config, turn_resolver, game_event
  - `res://systems/world/` : hex_map, hex_tile, production_system, activity, activity_registry
  - `res://systems/survivors/` : roster, survivor
  - `res://systems/buildings/` : building, building_config, building_registry
- `res://resources/` : tres de config (game, tile, activities/, buildings/, resource_types/) + `game_registry.tres` (manifest central de tout le contenu data-driven)
  - `res://assets/` : sprites colons (generic0-5), icônes ressources
  - `res://localization/` : CSV FR/EN
  - `res://scenes/` : main_ui (coordinateur léger, ~140 lignes)
  - `res://scenes/ui/` : vues transversales + `ui_presentation.gd` (helpers statics)
  - `res://scenes/ui/buildings/` : vues spécifiques bâtiment
- **Process** : 1 séance = 1 étape qui tourne, design avant code, commits étape par étape, refactor honnête quand le besoin émerge
- **Conventions code**
  - `@warning_ignore("unused_signal")` sur les signals déclarés dans `GameState` mais émis depuis `TurnResolver` (faux positif du linter)
  - Pas de `match` dans une lambda inline GDScript : extraire en variable nommée + `if/elif`
- **Conventions `translations.csv`**
  - Organisé par sections, séparées par une ligne vide et un faux-clé `# ─── NOM SECTION ─────,,` (commentaire visuel ; Godot l'ingère mais ne s'en sert pas)
  - Sections existantes : Game flow, Resources, Production view, Famine, Map & tiles, Survivants, Workers & assignation, Roles, Activities, Colony view, Construction, Buildings, Synthesizer, Computer, News & events, Necrology & deaths, Professions
  - Préfixes de clés : `BTN_`, `LABEL_`, `RES_`, `BUILDING_`, `EVENT_`, `ACTIVITY_`, `ROLE_`, `PROF_`, `TILE_TYPE_`, `POPUP_`, `PROD_`, `TOOLTIP_`, `NEWS_`
  - Ajouter une clé = trouver la bonne section (par préfixe), insérer en respectant l'ordre alphabétique local si possible
  - Sections marquées "(à auditer)" : clés vraisemblablement mortes en attente de vérification — voir dette dédiée
