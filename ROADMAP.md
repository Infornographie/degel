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

### Phase 10 — Système de traits unifié

Migration du système de bonus/malus vers un modèle de traits unifié : STATE (état temporaire, un seul à la fois), NATURE (qui il est devenu, semi-permanent), EVENT (son histoire). Un seul `TraitConfig.tres` porte les modifiers + métadonnées d'affichage + lifecycle ; la résolution les agrège indistinctement, l'UI les séparera par catégorie.

- **`TraitConfig` resource** (`systems/traits/trait_config.gd`) : id, name_key, description_key, category (STATE/NATURE/EVENT), icon, color_hint sémantique, 3 modifiers + filtre ressource, duration_turns.
- **`Survivor` étendu** : `traits: Array[TraitConfig]`, `trait_durations: Dictionary`, méthodes `add_trait` (avec unicité STATE et reset de durée), `remove_trait`, `has_trait`, `get_trait`. Plus `fatigue_streak` et `last_activity_id`.
- **`TurnResolver`** : les 3 helpers (`_activity_modifier`, `_construction_modifier`, `_building_output_modifier`) itèrent maintenant sur `s.traits`. Les signatures ne changent pas — les call sites (dont `compute_activity_yield`) restent intacts.
- **Mécanique de fatigue** : `_resolve_fatigue()` détecte la répétition d'activité (seuil = 3 tours) et met à jour `fatigue_streak` / `last_activity_id`. La pose/retrait du trait `tired` est déléguée à `TurnResolver.enforce_tired_invariant(s)`, appelée aussi par `GameState` à chaque mutation d'`activity_id` (assignation, désassignation, réaffectation) pour que la nouvelle activité bénéficie immédiatement du plein rendement. Nettoyage bonus : `activity_id` est désormais reset au départ d'une tuile (le champ pouvait rester stale et polluer le compteur de fatigue).
- **Décrément des durées** : `_resolve_trait_durations()` en fin de tour retire les traits expirés ; si c'était un STATE, repose `normal` pour maintenir l'invariant "toujours un STATE actif".
- **`Profession`** : perd les 4 champs de modifiers, gagne `initial_traits: Array[TraitConfig]`. Redevient une étiquette d'origine immuable.
- **`Tribe`** : inchangée — reste une étiquette narrative pure pour les events futurs.
- **`GameState.wake()` et `targeted_wake()`** : posent le trait `normal` + les `initial_traits` de la profession après réveil, via `_apply_initial_traits()`.
- **`GameRegistry`** étendu : nouveau champ `traits: Array[TraitConfig]`.
- **Six traits initiaux créés** : `normal`, `tired`, `famished` (posé mais pas encore utilisé par la famine), `food_savvy`, `out_of_touch`, `handy`.
- **Famine migrée vers le trait `famished`.** La variable globale `production_multiplier` de `GameState` et la constante `FAMINE_PROD_MULTIPLIER` supprimées, ainsi que `TurnResolver._apply_multiplier`. `compute_activity_yield` se réduit à `round(raw * _activity_modifier(...))`. Deux helpers `_apply_famished()` / `_clear_famished()` sur `GameState` posent/retirent le trait sur tous les éveillés. Effet mineur d'ajustement : `round` remplace `floor + "au moins 1"` — la prod famine peut différer de 1 sur certaines valeurs (raw=2 : 2 au lieu de 1). Comportement à ajuster si le gameplay l'exige.
- **Trait `first_awakened`** posé sur le tout premier réveillé de la partie (wake_order == 0), toutes voies confondues (`wake` et `targeted_wake`). Catégorie EVENT, purement narratif (modifiers à 1.0) — valide le support des traits sans effet stat.
- **Section Traits dans `translations.csv`** : 7 traits × 2 clés (name + description) × 2 langues. Écriture solarpunk-post-deuil.
- **Hover riche sur les survivants** : tooltip custom via inner class `SurvivorSprite` avec RichTextLabel + BBCode. Nom du trait coloré selon `color_hint` sémantique (positive/negative/story/neutral), description en gris atténué. Ordre stable STATE → NATURE → EVENT. Signature déblocable pour le chantier UI Colonization : le pattern `_make_custom_tooltip` est posé et prêt à être factorisé.

Effet bonus observé : le passage famine → fatigue à la fin d'une famine fonctionne (le compteur `fatigue_streak` a continué à monter pendant la famine, `_resolve_fatigue` repose `tired` au tour suivant si le seuil est encore atteint). Confirme que traits STATE et fatigue interagissent proprement.
Test validé : subsistance_farmer avec trait `food_savvy` produit +4 en cueillette forêt (au lieu de +3). Le trait `tired` se pose et se retire correctement avec la répétition/changement d'activité.

### Phase 11 — Popup d'affectation aux tuiles (Colonization-style)

Refonte complète du popup clic tuile de MapView. Remplacement du `PopupMenu` natif à sous-menus par un composant custom `TileAssignmentPopup` pensé pour la lisibilité du système de bonus profession/traits mis en place en Phase 9/10.

- **Nouveau composant `TileAssignmentPopup`** (`res://scenes/ui/tile_assignment_popup.gd`, extends PopupPanel) : popup fixe centré, matrice activités × persos éveillés.
- **Structure d'une row d'activité** : header fixe à gauche (nom · [inputs] → [output] · max N [+ % si risky]) + `ScrollContainer` horizontal propre à chaque activité contenant les slots persos. Header d'activité contraint à `COL_HEADER_MIN_WIDTH = 220` pour aligner les scrolls entre rows.
- **Slots visuels reproduisant le pattern MapView** : hex de la couleur de la tuile en fond (`Polygon2D`), icônes de yield derrière, sprite du perso par-dessus. Meilleur candidat dispo mis en avant par teinte verte modulate sur l'hex.
- **Séparation Dispo / Occupés** : dispo à gauche, `VSeparator`, occupés à droite. **Filtre pertinence** : les persos déjà en train de faire cette activité ailleurs sont masqués des occupés (les déplacer ne ferait qu'annuler leur prod actuelle pour la re-poser ici).
- **Tooltip riche identique à SurvivorsView** : classe interne `RichHoverSlot` avec `_make_custom_tooltip` custom (BBCode : nom + profession + rôle + location + prod + traits colorés par `color_hint`).
- **Dimensionnement adaptatif** : hauteur du popup = header + N_activités × row_height ; largeur = header + `MAX_VISIBLE_COLS = 5` slots visibles avant scroll horizontal. Cap 90% écran comme filet.
- **Deux nouveaux helpers publics dans `GameState`** :
  - `best_yield_for_activity(s, activity, exclude_tile_key)` — meilleur yield d'un survivant sur une activité, sur les tuiles workables compatibles (exclusion optionnelle pour révéler le "meilleur ailleurs")
  - `best_yield_all_survivors(activity)` — meilleur yield tous éveillés × toutes tuiles confondues (échelle absolue affichée en tête de section)
- **`MapView._open_tile_popup`** réduit à 4 lignes (délègue à `TileAssignmentPopup.open()`). Anciens champs `_tile_popup`, `_popup_submenus`, `_popup_tile_key` et callbacks `_on_main_popup_selected`, `_on_submenu_selected` supprimés (règle 1).
- **5 nouvelles clés i18n** dans `translations.csv`, section "POPUP AFFECTATION TUILE".

### Phase 12 — Widget survivant centralisé + fatigue à effet immédiat

Chantier UI Colonization en deux volets qui se sont imbriqués : le signal visuel de fatigue (bug UX critique — le jeu était illisible sans) demandait un endroit stable pour être posé, et la sémantique de fatigue elle-même avait besoin d'être corrigée pour que le signal ne mente pas.

**Sémantique de fatigue à effet immédiat.** Voir Phase 10 ligne "Mécanique de fatigue" pour la version actuelle. Le point saillant : la pose/retrait de `tired` est délégué à `TurnResolver.enforce_tired_invariant(s)`, appelée aussi par `GameState` à chaque mutation d'`activity_id`. Réaffecter un fatigué lui rend immédiatement le plein rendement — plus de tour de "gueule de bois" sur la nouvelle activité. `compute_activity_yield` gagne un paramètre optionnel `target_activity_id` : le popup d'affectation évalue `tired` de manière hypothétique (l'estimation affichée n'inclut plus un malus qui aurait été retiré par l'assignation).

**Widget centralisé `SurvivorSpriteWidget`.** Nouveau composant `res://scenes/ui/survivor_sprite_widget.gd` (extends TextureRect) qui encapsule : chargement du sprite (profession si dispo, fallback générique via `sprite_variant`), tooltip riche BBCode (nom, rôle, location, prod, traits colorés par catégorie sémantique), badge d'état visuel en coin haut-droit (fatigue : icône `TraitConfig.icon` ou fallback ColorRect orange selon `color_hint`), signal `clicked` optionnel. Deux booléens de setup pilotent le comportement souris : `capture_clicks=false` (défaut, `MOUSE_FILTER_PASS`) pour laisser le clic filer au parent quand un slot/hex captureur est en dessous ; `capture_clicks=true` (`MOUSE_FILTER_STOP` + curseur pointeur) pour les sprites qui ont leur propre action. La fonction statique `build_rich_tooltip(s, click_hint_key)` est extraite pour usage par d'autres Controls (le slot hexagonal de `TileAssignmentPopup` la réutilise pour offrir le tooltip sur toute la surface de l'hex, pas juste le sprite — une seule source de vérité de tooltip, deux zones de hover).

**Migration des 5 sites en 6 étapes committées** :
- `CryoView` — remplace `UiPresentation.survivor_sprite`. Header dégradé nom+profession seul pour les endormis.
- `SurvivorsView` — suppression de la classe interne `SurvivorSprite` (166 → 55 lignes).
- `MapView::_render_tile_worker` — sprite rendu cliquable : cliquer un colon sur la carte ouvre le popup d'affectation de sa tuile, comme cliquer l'hex.
- `TileAssignmentPopup::_survivor_slot` — `RichHoverSlot` réduite à un délégué du tooltip statique ; sa raison d'être devient uniquement d'étendre la zone de hover aux coins de l'hex.
- `UiPresentation.assigned_worker_sprite` — wrapper thin autour du widget avec `capture_clicks=true` + hint `TOOLTIP_CLICK_TO_UNASSIGN` + connexion `clicked → unassign_from_building`. Les workers dans un bâtiment gagnent un vrai tooltip riche (avant : nom + profession + hint seul).
- Nettoyage final : `UiPresentation.survivor_sprite()` et les constantes `SURVIVOR_SPRITE_PATH` / `SURVIVOR_SPRITE_SCALE` supprimées de `UiPresentation`.

**Piège rencontré chemin faisant** : `assign_to_tile` appelle `_remove_survivor_from_assignments` qui clear `activity_id` — l'ordre des appels dans `_on_activity_selected` a dû être inversé (`assign_to_tile` puis `assign_activity`). Voir dette mineure sur l'atomicité de ces deux méthodes.

**Dettes réglées** : items CODEMAP 1 (map_view sprite inline) et 4 (RichHoverSlot dup), plus la dette mineure "duplication du chargement de sprite survivant". La dette hex (constantes partagées MapView/TileAssignmentPopup) reste ouverte pour un chantier "hex slot component" séparé.

### Build & livraison

Build Windows exportable (BuildingRegistry/ActivityRegistry chargent via listes explicites, `DirAccess` ne marche pas dans les exe exportés).

### Phase 13 — Système d'événements narratifs (Phase 1)

Premier pipeline d'événements narratifs de bout en bout : data model, queue à priorité, déclenchement par milestones, popup de résolution avec verrouillage du tour suivant.

- **`EventConfig` resource** (`systems/events/event_config.gd`) : id, title/body localisés, choices, priority/is_urgent/one_shot, trigger par milestone, prerequisites.
- **`EventChoice` resource** (`systems/events/event_choice.gd`) : label localisé, effets ressources (`resource_effects`), traits à poser (`traits_to_add`). Phase 1 = effets globaux sur tous les éveillés ; targeting par survivant prévu en Phase 2.
- **`EventManager`** (`systems/events/event_manager.gd`) : sous-système RefCounted de GameState. Gère les milestone flags, la queue triée (urgent > priority), le scan d'éligibilité, la résolution avec application des effets. `set_milestone(flag)` comme point d'entrée pour le déclenchement.
- **`EventPopup`** (`scenes/ui/event_popup.gd`) : PopupPanel centré avec titre, corps narratif en RichTextLabel (BBCode prêt), boutons de choix. Fermeture sans résolution possible (Échap), le joueur revient via le bouton.
- **UI ButtonsSection** : bouton "⚡ Événement" visible quand la queue est non vide, bouton "Tour suivant" grisé tant qu'il reste des events à résoudre.
- **GameRegistry** étendu : `events: Array[EventConfig]`.
- **Deux milestones posés** : `first_wake` (dans `wake()`/`targeted_wake()`), `first_deforestation` (dans `_resolve_tile_mutations()`).
- **Deux events de test** : premier éveil (narratif du computer, 1 choix accusé de réception), première déforestation (avertissement écologique, 2 choix).
- **6 clés i18n** ajoutées dans `translations.csv`, sections "ÉVÉNEMENTS NARRATIFS" et events individuels.

### Phase 15 — Corrections bâtiments & fatigue

- **Fix construction** : complétion avec epsilon (les accumulations flottantes retardaient d'un tour) ; `build_progress` mort supprimé.
- **Fatigue en bâtiment** : clé d'occupation unifiée (`occupation_key`), même seuil que les tuiles.
- **Production de bâtiment** : modifiers de traits moyennés sur tous les workers ; report fractionnaire par output (`Building.output_carry`) — stocks entiers, bonus fractionnaires matérialisés dans le temps.
- **Stats enrichies** : détail par personnage, suivi des événements résolus/en attente.

**Dette réglée :**
- [x] ~~`build_progress`/`build_work` morts~~ — supprimés (la complétion = ressources consommées)

**Dette nommée :**
- [ ] **`action` du fait `event_resolved` stocke l'index du choix, pas son id** — si l'ordre des choix d'un EventConfig change, l'historique devient ambigu. Acceptable tant que les events sont figés ; à revisiter si on veut des triggers conditionnés aux choix passés.

### Phase 16 — Courbes de stocks

- **Chronicle** : snapshot des stocks en fin de tour (`snapshot_resources`), historique requêtable (`resource_history`).
- **`ResourceChart`** : Control custom, `_draw()`, auto-scale, légende. Filtre sur `ResourceType.stackable`.
- **Intégration StatsPopup** : graphique en tête du popup.

**Dette nommée :**
- [ ] **Palette codée en dur** dans `ResourceChart.PALETTE`. À terme, une couleur pourrait vivre sur `ResourceType.color` (comme `icon`). Fallback HSV en attendant, donc pas bloquant.
- [ ] **Pas de survol/tooltip sur les points** — lecture des valeurs uniquement via la grille. À ajouter si le besoin devient pressant.

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

- **Sources multiples vers une même réserve.** Plusieurs icônes/sprites pour une même ressource (fraises, blé, gibier, synth → tous en `food`). Visualisation différenciée sur carte et prod view, compteur unique en réserve.
- **Substitution de ressources.** Certains bâtiments avancés acceptent l'un *ou* l'autre input (heat ⊕ electricity).
- **Améliorations de bâtiments** (niveau 1 → 2 → 3). Les champs existent dans `BuildingConfig`, à brancher avec coût d'upgrade et UI dédiée.
- **Bilan ressources ordonné** (polish d'équilibrage). Pouvoir exprimer des séquences en blocs (`5 wood, 5 ore, 5 wood, 5 tools`) plutôt que `build_order` linéaire.
- **`first_awakened` trait** à poser sur les 3 survivants du choix initial (ou sur le tout premier réveillé si pas encore de choix initial). Premier trait de catégorie EVENT à intégrer — validation du support de la catégorie narrative pure.

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
- **UI d'assignation bidirectionnelle façon Colonization**. Sens tuile → persos livré en Phase 11 (matrice activités × persos, révèle enfin les bonus profession/traits). Reste à faire le sens perso → tuiles (popup clic sur un sprite listant les activités possibles + meilleure tuile pour chaque) et le drag & drop entre sprites et cases/bâtiments.

  Stockage sur `Survivor` : `traits: Array[TraitConfig]` (un par id maximum, pas de stacking — re-pose = reset de durée) + `trait_durations: Dictionary` (id → tours restants). Plus `fatigue_streak: int` et `last_activity_id: StringName` pour la mécanique de fatigue.

  Calcul des modifiers : composition multiplicative en itérant sur `s.traits`. `_activity_modifier`, `_construction_modifier`, `_building_output_modifier` deviennent les seuls call sites, déjà centralisés via la phase précédente.

  Migration depuis Profession : les 4 champs de modifiers quittent `Profession`, remplacés par `initial_traits: Array[TraitConfig]`. `Tribe` ne porte aucun trait — elle reste une étiquette narrative pure pour les events futurs (accessible via `prof.tribe`).

  Famine migrée : `production_multiplier` global de GameState supprimé, remplacé par un trait `famished` (STATE, -20%) posé sur tous les éveillés pendant la famine. `_apply_multiplier` probablement supprimé en même temps.

  Premier set de traits à coder : `normal` (STATE défaut, neutre), `tired` (STATE, -20%, posé après 3 tours sur la même activité), `famished` (STATE, -20%), `food_savvy` (NATURE), `out_of_touch` (NATURE), `handy` (NATURE), `first_awakened` (EVENT, narratif pur). D'autres au fil de l'intégration des professions.

  Pose au réveil : trait `normal` + boucle sur `prof.initial_traits`. Professions sans NATURE initial = juste `normal` (caractérisation différée). `out_of_touch` posable en bouche-trou sur les métiers de l'ancien monde quand le narratif n'est pas écrit.
- **Tooltips cliquables à hyperliens** (long terme). Inspiration Pathfinder/Owlcat : hover sur un mot-clé ouvre une popup avec termes soulignés ; clic sur un terme ouvre une autre popup. Pas avant que le contenu narratif (events + traits + professions multiples) ne crée une vraie densité de références croisées. Côté préparation : descriptions en `RichTextLabel` + BBCode dès le système de traits, pour que le passage soit indolore.
- **Traits de communauté** (idée parquée). Plutôt qu'un trait posé identiquement sur chaque survivant, un trait porté par la communauté entière. À creuser quand d'autres cas d'usage émergeront (politique collective ? résultat d'event ? saison ?). Pas avant.
---

## 🐛 Bugs à diagnostiquer

À traiter en séances dédiées quand l'envie passe par là :

- **Bug d'affichage `usable` électricité.** Le label affiche "synth: -3" mais l'usable ne reflète pas la déduction. Hypothèse : `synth.active` est true sans worker, ou conso pas déduite au bon moment dans TurnResolver.
- **Invariant "toujours un STATE actif" potentiellement cassé après retrait de STATE.** `_clear_famished()` retire `famished` sans reposer `normal`. Si le survivant n'était pas fatigué avant, il se retrouve sans STATE. Même préoccupation à surveiller pour tout futur retrait de STATE hors du système de durée (qui, lui, repose `normal` correctement via `_resolve_trait_durations`). À vérifier visuellement dès que l'UI affichera les STATE. Fix pressenti : reposer `normal` côté appelant après tout `remove_trait` de STATE, ou centraliser dans `Survivor.remove_trait` avec une dépendance au registry (moins propre).
---

## 🏗 Dettes architecturales

À reprendre quand le contexte se présente — pas urgentes :

- **`necrology` redondant** avec `event_log` filtré sur `category == "loss"`. Migration possible.
- **Signal `nightly_deaths` mal nommé** : porte tous les events du tour, pas seulement les morts. À renommer (`turn_news` ou `nightly_events`).
- **`construction_started` réutilisé pour rafraîchir l'UI** (deux call sites avec `# rafraîchir` en commentaire dans `game_state.gd`). Un vrai signal de refresh manque.
- **Layout colony hardcodé** (`COLONY_SLOTS=12`, `STARTER_SLOTS`) dans `ColonyView`. À déplacer dans une Resource configurable quand l'équilibrage l'exigera.
- **Ordre des bâtiments dans `_resolve_buildings_operation`** : premier servi sur les inputs partagés. Acceptable, à raffiner si gênant.
- **UI/loc encore branchées sur strings hardcodées — migration en cours.** `GameState.resources["food"]` reste la clé d'accès (par design). Côté affichage : `UiPresentation.resource()`, `UiPresentation.resource_icon()`, `ResourcesBar` et `ProductionView` migrés sur `ResourceRegistry`. Restent à migrer au fil des touches : `InfosSection` (affichage électricité/heat) et autres callsites qui hardcodent encore des noms de ressources.
- **Signal `building_assignment_changed` au nom trop étroit.** Sert désormais à refresh sur : assignation, toggle synth, changement d'intensité. À renommer (`building_settings_changed` ou `building_state_changed`) en cohérence avec les dettes déjà nommées sur `nightly_deaths` et `construction_started`.
- **`TraitRegistry` à créer**, sur le modèle de `BuildingRegistry` / `ActivityRegistry`. Aujourd'hui, deux lookups linéaires existent en parallèle : `TurnResolver._get_trait_by_id` avec cache local, `GameState._find_trait` sans cache. À centraliser en une classe dédiée avec cache statique et lookup O(1), accessible depuis les deux (et depuis l'UI plus tard).
- **`TileAssignmentPopup` duplique le pattern MapView pour le rendu hexagonal.** Le sprite survivant est unifié via `SurvivorSpriteWidget` depuis la Phase 12, mais les constantes `HEX_RADIUS`, `TILE_PROD_ICON_SIZE`, `WORKER_SPRITE_SCALE`, `TILE_COLORS` + le rendu des icônes de prod + `_hex_polygon_points` restent dupliqués entre les deux vues. À factoriser dans un chantier "hex slot component" séparé.
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
- **`Survivor.sprite_variant` à retirer une fois tous les sprites profession en place.** Aujourd'hui sert de fallback quand `Profession.sprite` est null. Quand le pool sera complet (et avant ça, la décision sur le système de variants pour représentativité — voir one-pager), `sprite_variant` et `SURVIVOR_SPRITE_PATH` deviendront morts.
- **Affichage des bonus profession dans l'UI d'assignation.** Mécanique en place et fonctionnelle, mais le joueur voit "+4 food" sans savoir que c'est un bonus profession (vs. "+3 de base"). À révéler via la prochaine refonte UI d'assignation bidirectionnelle (voir backlog "Refonte sélection sur tuile façon Colonization").
- **Erreur Godot `_push_unhandled_input_internal: !is_inside_tree()`.** Warning interne récurrent, probablement lié à un popup qui se `queue_free` pendant qu'il a encore le focus. Pas reproductible en pattern clair pour l'instant, à surveiller.
- **`assign_to_tile` + `assign_activity` non atomiques.** Le popup d'affectation appelle les deux séquentiellement, avec un ordre qui compte (la tuile d'abord — `_remove_survivor_from_assignments` clear `activity_id`, cf. commentaire dans `_on_activity_selected`). Un seul call site pour l'instant. Dès qu'il y en aura un deuxième, extraire un `GameState.assign_to_tile_with_activity(id, tile_key, activity_id)` atomique.
- **Tooltip riche parfois coupé sous l'écran.** Godot ne clampe pas automatiquement la position d'un `_make_custom_tooltip` custom à la viewport. Option A retenue en Phase 12 : `custom_minimum_size` + `fit_content` (fonctionne dans la plupart des cas). Si le débord redevient gênant à l'usage, migrer vers option B : `PopupPanel` interne géré par `mouse_entered`/`mouse_exited` avec clamp explicite à la viewport rect.
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
  - `res://systems/world/` : hex_map, hex_tile, activity, activity_registry, resource_type, resource_registry
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
