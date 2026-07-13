# CODEMAP — DÉGEL
 
Carte de structure du projet : où vit chaque logique, quelles fonctions existent déjà.
But : éviter de recoder une logique existante ailleurs, garder "une logique, un endroit".
 
⚠️ Ce fichier n'est pas synchronisé automatiquement. À régénérer/mettre à jour en fin de
session ayant changé la structure (nouveau fichier, fonction publique ajoutée/supprimée),
même flux que ROADMAP.md.
 
Dernière génération : à partir du commit `[commit à venir]` (Popup d'affectation aux tuiles — Phase 11).
 
---
 
## Dette repérée pendant la génération de cette carte
 
Ces éléments ne sont pas corrigés ici — ce sont des observations remontées pour arbitrage,
conformément à la règle 5 (nommer la dette). À ajouter à la ROADMAP si tu valides.
 
2. **Dette déjà nommée dans le code** (remontée ici pour visibilité, déjà correctement
   commentée par toi) :
   - `GameState._find_trait()` : lookup linéaire dans `GameRegistry.traits`, commenté
     "Duplication temporaire — voir dette TraitRegistry dans la roadmap."
   - `ColonyView` : nombre de slots et disposition des starters hardcodés en constantes ;
	 commentaire "à terme, déplacer dans une Resource configurable (dette)."
   - `ResourceType.max_stock` : champ déclaré mais "pas encore appliqué dans GameState
     (dette consciente)."
3. **`scenes/ui/tile_assignment_popup.gd`** duplique plusieurs constantes et le pattern
   de rendu de MapView : `HEX_RADIUS`, `TILE_PROD_ICON_SIZE`, `WORKER_SPRITE_SCALE`,
   `TILE_COLORS`, `_hex_polygon_points()`, plus le code inline du slot (icônes en fond
   + sprite dessus). Assumé temporairement — factorisation prévue en même temps que
   la dette SurvivorSprite (règle 3).
4. **`scenes/ui/tile_assignment_popup.gd`** duplique aussi le pattern tooltip riche
   de `SurvivorsView.SurvivorSprite` : classe interne `RichHoverSlot` avec
   `_make_custom_tooltip`, helpers `_survivor_header_text` / `_build_trait_lines` /
   `_format_output`, constante `TRAIT_COLORS`. À unifier vers `UiPresentation`.
---
 
## systems/core/ — Boucle de jeu, configuration, registre central
 
### systems/core/game_state.gd
`extends Node` — Autoload, cœur de la simulation. Détient l'état (ressources, tour,
survivants, bâtiments) et orchestre la boucle de tour. Délègue la résolution à
`TurnResolver`, les survivants à `Roster`, la carte à `HexMap`.
 
**Fonctions clés :**
- `advance_turn() -> void` — boucle de tour complète : résolution, repas/famine, extinctions, érosion réacteur, fin de run
- `wake(id) -> bool` / `targeted_wake(prof_id) -> bool` — réveil normal / ciblé d'un survivant
- `assign_activity(...)`, `assign_to_tile(...)`, `assign_to_building(...)` et leurs `unassign_*` — affectations joueur
- `start_construction(target_type_id, slot_index) -> bool`, `cancel_construction`, `set_active_construction` — gestion des chantiers
- `expected_activity_yield(s, tile, activity) -> int` — helper UI, délègue à `TurnResolver.compute_activity_yield()`
- `get_survivor_output(s) -> Dictionary` — production projetée d'un survivant (utilisé par `survivors_view.gd`, `map_view.gd`)
- `log_event(category, key, params)`, `events_for_turn(t)` — journal d'événements
- `compute_score() -> Dictionary`
- `best_yield_for_activity(s, activity, exclude_tile_key = "") -> int` — meilleur yield d'un survivant pour une activité, sur les tuiles workables compatibles ; exclut optionnellement une tuile (utilisé par le popup d'affectation pour révéler le "meilleur ailleurs")
- `best_yield_all_survivors(activity) -> int` — meilleur yield tous éveillés × toutes tuiles confondus (échelle absolue affichée en en-tête de section du popup)
**Autres fonctions :**
`can_wake(id)`, `can_targeted_wake()`, `awake_count()`, `awake_survivors()`, `survivors()`, `electricity_consumed_this_turn()`, `_find_building_by_type(type_id)`, `_find_building_by_instance(instance_id)`, `_remove_survivor_from_assignments(s)`, [...]
 
Signaux : `turn_advanced`, `resources_changed`, `survivor_woken`, `survivor_assigned`, `nightly_deaths`, `famine_started`, `famine_ended`, `candidates_changed`, `tile_assignment_changed`, `run_ended`, `building_assignment_changed`, `construction_started`, `construction_progressed`, `construction_completed`, `event_logged`
 
### systems/core/turn_resolver.gd
`class_name TurnResolver` extends RefCounted — Source unique de vérité pour la résolution
d'un tour. Deux usages : `compute_flow()` (prévision déterministe sur copie de stock, sans
effet de bord) et `execute_turn()` (application réelle, avec aléatoire). Le partage entre
les deux garantit que l'affichage ne ment jamais.
 
**Fonctions clés :**
- `compute_flow() -> Dictionary` — bilan déterministe (production/consommation/impossible) par ressource, sur COPIE du stock
- `execute_turn() -> void` — applique le tour réel : risky → tuiles → construction → bâtiments → mutations → fatigue → durées de traits
- `gather_risky() -> Array` — activités risquées en cours, pour affichage séparé
- `compute_activity_yield(raw, s, produced_resource) -> float` — calcul unique du rendement d'un survivant (agrège les modifiers de traits)
- `enforce_tired_invariant(s) -> void` — pose ou retire le trait `tired` selon l'invariante (streak ≥ seuil ET activity_id == last_activity_id ET activity_id != ""). Appelé en interne par `_resolve_fatigue`, et par `GameState` après chaque mutation d'`activity_id`.
**Autres fonctions :**
`_init(game_state)`, `_resolve_risky()`, `_resolve_tile_production()`, `_resolve_construction()`, `_resolve_buildings_operation()`, `_resolve_tile_mutations()`, `_resolve_fatigue()`, `_resolve_trait_durations()`, `_building_operates(b) -> bool`, `_building_multiplier(b) -> float`, `_operation_factor(b, stock, bmult) -> float`, `_has_inputs(stock, inputs, scale) -> bool`, `_simulate_construction(stock, consumption)`, `_build_order(target) -> Array`, `_activity_modifier(s, resource_name) -> float`, `_construction_modifier(s) -> float`, `_building_output_modifier(b) -> float`, `_add(dict, key, amount)`, `_get_trait_by_id(id) -> TraitConfig`
 
⚠️ L'aléatoire et les morts ne sont jamais calculés en prévision, uniquement dans `execute_turn()`.
 
### systems/core/game_registry.gd
`class_name GameRegistry` extends Resource — Manifest central de tout le contenu
data-driven (`.tres` unique, édité dans l'inspecteur). Ajouter/retirer un type de contenu
ne touche que ce fichier, pas le code.
- `static load_default() -> GameRegistry` — charge `res://resources/game_registry.tres` (caché par Godot, sans coût en appels répétés)
Champs : `resource_types`, `buildings`, `activities`, `tribes`, `professions`, `traits`, `names` (tous `Array[...]`)
 
### systems/core/game_config.gd
`class_name GameConfig` extends Resource — Configuration globale d'équilibrage, éditable
via `.tres`. Pas de logique, uniquement des `@export` : réacteur (output initial, décroissance),
réveil (coûts, quota, pool candidats), nourriture, taille du roster, extinction.
 
### systems/core/game_event.gd
`class_name GameEvent` extends RefCounted — Un événement de partie (journal + news de fin
de tour). Stocke key i18n + params positionnels pour traduction différée.
- `format() -> String` — rend le texte traduit ; convention `"tr:CLÉ"` dans un param = traduit lui-même à l'affichage
### systems/core/tile_config.gd
`class_name TileConfig` extends Resource — Ratios de génération de tuiles et rendements
par activité, par type de tuile.
- `yields_for_tile(tile_type) -> Dictionary`
---
 
## systems/world/ — Carte, ressources, activités
 
### systems/world/hex_map.gd
`class_name HexMap` extends RefCounted — Carte hexagonale (coordonnées cube) autour du bunker.
- `_init(radius, config)` — génère la carte : place le bunker au centre, répartit plaines/forêt/montagne selon les ratios de `TileConfig`, assigne les yields
- `get_tile(q, r) -> HexTile`, `get_tile_by_key(key) -> HexTile`
- `neighbors(tile) -> Array[HexTile]`
- `workable_tiles() -> Array[HexTile]` — toutes sauf le bunker
- `mutate_tile(tile, new_type) -> void` — change le type d'une tuile et recalcule ses yields (utilisé par la mutation forêt épuisée → plaine)
**Autres fonctions :** `_generate()`, `_assign_yields(tile)`
 
### systems/world/hex_tile.gd
`class_name HexTile` extends RefCounted — Une tuile hexagonale (q, r, s cube, q+r+s=0).
`enum Type { BUNKER, PLAINS, FOREST, MOUNTAIN }`. Porte `worker_id`, `yields` (Dictionary
indexé par activity_id), `health` (santé, modifiée par les activités).
- `key() -> String`, `static make_key(q, r) -> String`
### systems/world/activity.gd
`class_name Activity` extends Resource — Une activité réalisable sur une tuile. Data-driven :
`id`, `allowed_tile_types`, `inputs`, `produced_resource`, `success_rate` (< 1.0 = risky),
`tile_health_delta`.
 
### systems/world/activity_registry.gd
`class_name ActivityRegistry` extends RefCounted — Registry des `Activity`, chargé depuis
`GameRegistry`.
- `get_activity(id) -> Activity`
- `available_for_tile(tile_type) -> Array[Activity]`
### systems/world/resource_type.gd
`class_name ResourceType` extends Resource — Descripteur d'une ressource. `id`, `name_key`,
`icon`, `stackable` (false = flux réinitialisé chaque tour, ex: electricity/heat),
`max_stock` (⚠️ pas encore appliqué — dette), `display_order`.
 
### systems/world/resource_registry.gd
`class_name ResourceRegistry` extends RefCounted — Registry **statique** des `ResourceType`,
chargé depuis `GameRegistry`, indexé et trié par `display_order`.
- `static get_type(id) -> ResourceType`
- `static all() -> Array[ResourceType]`
- `static ids() -> Array[StringName]`
### systems/world/production_system.gd ⚠️ MORT — voir section Dette
`class_name ProductionSystem` extends RefCounted — Ancien système de résolution de
production, remplacé par `TurnResolver`. Instancié dans `GameState` mais jamais appelé.
Contient `get_survivor_output()` et `resolve()`, tous deux orphelins.
 
---
 
## systems/survivors/ — Roster, professions, tribus
 
### systems/survivors/survivor.gd
`class_name Survivor` extends RefCounted — Un survivant : identité, état d'éveil,
affectation (tuile/bâtiment/activité), traits actifs, fatigue.
 
**Fonctions clés :**
- `add_trait(t) -> void` — ajoute un trait ; si STATE, retire les autres STATE (unicité) ; si déjà présent, reset la durée
- `remove_trait(id) -> void`, `has_trait(id) -> bool`, `get_trait(id) -> TraitConfig`
Champs notables : `traits: Array[TraitConfig]`, `trait_durations: Dictionary`,
`fatigue_streak: int`, `last_activity_id: StringName`.
 
### systems/survivors/roster.gd
`class_name Roster` extends RefCounted — Gère la liste des survivants : génération pondérée
par rareté, accès, candidats. Détenu par `GameState`.
 
**Fonctions clés :**
- `_generate(count) -> void` — tirage : honore d'abord les `min_count` des professions, puis tirage pondéré par `rarity` pour combler ; noms sans remise, professions avec remise
- `get_by_id(id) -> Survivor`, `awake_survivors() -> Array[Survivor]`, `awake_count() -> int`
- `draw_candidates(count, exclude_ids) -> Array[int]` — pool de réveil
- `static get_profession(prof_id) -> Profession` — cache statique indexé (pattern partagé avec `ResourceRegistry`)
- `static display_name(prof_id) -> String`, `static name_key(prof_id) -> String` — nom localisé / clé i18n d'une profession
**Autres fonctions :**
`_pick_weighted(pool, total_weight)`, `size()`, `is_empty()`, `remove(survivor)`, `pick_random_awake()`, `sleeping_count()`, `_ensure_professions_loaded()`, `sleeping_profession_ids()`, `all_profession_ids()`, `find_sleeping_by_profession_id(prof_id)`
 
### systems/survivors/profession.gd
`class_name Profession` extends Resource — Identité narrative + paramètres de tirage.
`enum Rarity { ABSENT, ELITE, RARE, UNCOMMON, COMMON }` avec poids de tirage `RARITY_WEIGHTS`.
Champs : `id`, `name_key`, `tribe`, `rarity`, `min_count` (garantie de présence), `sprite`,
`initial_traits` (traits NATURE posés au réveil).
- `weight() -> int`
### systems/survivors/tribe.gd
`class_name Tribe` extends Resource — Tribu narrative d'appartenance d'une profession.
Invisible pour le joueur, sert au système d'événements. Champs seuls : `id`, `name_key`.
 
---
 
## systems/buildings/ — Bâtiments
 
### systems/buildings/building.gd
`class_name Building` extends RefCounted — Instance d'un bâtiment dans la colonie :
référence une `BuildingConfig`, porte l'état courant (niveau, workers, construction,
intensité).
- `can_operate() -> bool`, `workers_max() -> int`, `level_multiplier() -> float`, `complete_construction() -> void`
Champs notables : `state` (UNDER_CONSTRUCTION/OPERATIONAL), `current_intensity` (init à
`max(1, max_intensity/2)`), `construction_target`, `slot_index`.
 
### systems/buildings/building_config.gd
`class_name BuildingConfig` extends Resource — Description data-driven d'un type de
bâtiment. `enum Family { TRANSFORMATION, FUNCTION }`. Groupes : Identity, Construction
(`build_cost`, `build_order`, `build_work`), Operation (`inputs`, `outputs`,
`workers_required/max`, `can_run_on_electricity`, `max_intensity`), Upgrades (`max_level`,
`output_multiplier_per_level`), Availability, UI (`view_scene`, `is_bunker_building`,
`worker_role_key`).
 
### systems/buildings/building_registry.gd
`class_name BuildingRegistry` extends RefCounted — Registry des `BuildingConfig`, chargé
depuis `GameRegistry`.
- `get_config(id) -> BuildingConfig`, `starters() -> Array[BuildingConfig]`, `constructibles() -> Array[BuildingConfig]`
---
 
## systems/traits/ — Traits
 
### systems/traits/trait_config.gd
`class_name TraitConfig` extends Resource — Un trait porté par un survivant (STATE
temporaire / NATURE semi-permanent / EVENT narratif). Un seul modèle pour les trois ;
la résolution les agrège indistinctement, l'UI les sépare par catégorie.
- `activity_modifier_for(res) -> float`
- `building_modifier_for(resources_in_play) -> float`
Champs clés : `category`, `activity_modifier`, `construction_modifier`, `building_modifier`,
`modifier_resource_filter` (vide = s'applique partout), `duration_turns` (-1 = permanent).
 
---
 
## scenes/ — Coordination UI
 
### scenes/main_ui.gd
`extends Control` — Coordinateur léger de l'interface. Layout global (3 rangs),
instanciation des vues, rebuild complet au changement de langue, popups globaux
(score de fin de run, news nocturnes). Aucune vue n'a de logique de simulation ; toutes
s'abonnent directement à `GameState`.
 
**Fonctions clés :** `_build_ui()`, `_rebuild_ui()` (destroy + rebuild complet, nécessaire
car `tr()` est résolu à la création des Labels, pas réévalué dynamiquement)
 
**Autres fonctions :** `_on_run_ended(cause)`, `_on_nightly_deaths(events)`
 
---
 
## scenes/ui/ — Vues
 
### scenes/ui/ui_presentation.gd
`class_name UiPresentation` extends Object — Helpers de présentation statiques partagés
entre toutes les vues (aucune logique d'état). Utilise `TranslationServer.translate()`
plutôt que `tr()` (inaccessible en `static func`).
 
**Fonctions clés :**
- `resource_icon(resource_name, icon_size) -> Control` — icône ressource, fallback ColorRect si pas d'icône
- `production_icon(resource_name, overlay) -> Control` — icône + overlay (surplus/deficit/crossed)
- `survivor_sprite(s, tooltip) -> TextureRect` — sprite standard d'un survivant (⚠️ dupliqué en inline dans `map_view.gd`, voir Dette)
- `assigned_worker_sprite(s)` — wrapper autour de `SurvivorSpriteWidget` : sprite cliquable (unassign_from_building) avec tooltip riche et hint "cliquer pour désassigner"
- `open_building_popup(parent, b, popup_position) -> void` — popup d'affectation à un bâtiment opérationnel
- `show_popup(parent, title, message) -> void` — AcceptDialog générique
**Autres fonctions :** `resource(resource_name)`, `placeholder_color(resource_name)`, `tile_label(key)`, `activity_for_building(building_id)`, `activity(s)`, `slot_panel(is_bunker)`, `slot_title(text)`
 
### scenes/ui/survivor_sprite_widget.gd
`class_name SurvivorSpriteWidget` extends TextureRect — Widget centralisé de rendu
d'un sprite survivant : chargement (profession ou fallback), tooltip riche BBCode
(nom + profession + rôle + location + prod + traits colorés), badge d'état
(fatigue en coin haut-droit), signal `clicked` optionnel.

Contrat : `setup(s, sprite_scale=4, capture_clicks=false, click_hint_key="") -> void`
à appeler une fois après `new()`. Pour rafraîchir, queue_free + recréer.

`capture_clicks=false` (défaut) : `mouse_filter=PASS`, tooltip actif, le clic file
au parent (usage MapView / TileAssignmentPopup / SurvivorsView / CryoView).
`capture_clicks=true` : `mouse_filter=STOP`, émet `clicked(survivor_id)` au clic
gauche (usage assigned_worker_sprite pour désassigner d'un bâtiment).

Migrations en cours (chantier UI Colonization) : CryoView migré, restent MapView,
SurvivorsView, TileAssignmentPopup, et l'adaptation de `UiPresentation.assigned_worker_sprite`.

### scenes/ui/colony_view.gd
`class_name ColonyView` extends Control — Grille 4×3 des bâtiments. Starters à emplacements
fixes (`STARTER_SLOTS`), autres selon `slot_index`. Délègue le rendu d'un slot occupé à
`BuildingConfig.view_scene`. ⚠️ Slots/dispositions hardcodés — dette nommée dans le fichier.
 
**Fonctions clés :**
- `enter_placement_mode(type_id) -> void` — bascule les slots vides en mode cliquable pour construction
**Autres fonctions :** `_rebuild()`, `_find_starter(id)`, `_make_building_slot(b)`, `_make_empty_slot(slot_idx)`
 
### scenes/ui/map_view.gd
`class_name MapView` extends Control — Carte hexagonale : tuiles colorées par type,
sprites des workers, icônes de production, popup d'assignation par activité au clic.
Deux passes de rendu (backgrounds puis sprites/icônes par-dessus).
 
**Fonctions clés :**
- `_open_tile_popup(tile_key, popup_position)` — délègue à `TileAssignmentPopup.open()` (le param `popup_position` est ignoré depuis la Phase 11, le popup est centré)
**Autres fonctions :** `_rebuild()`, `_draw_hex_background(tile, center)`, `_render_tile_worker(tile, center)` ⚠️ duplique le chargement de sprite (voir Dette), `_hex_to_pixel(q, r)`, `_hex_polygon_points()`

### scenes/ui/tile_assignment_popup.gd
`class_name TileAssignmentPopup` extends PopupPanel — Popup d'affectation à une
tuile de carte. Matrice activités × persos éveillés (une row par activité, colonnes
= slots persos triés dispo/séparateur/occupés). Popup fixe centré, taille adaptée
au nombre d'activités de la tuile. `ScrollContainer` horizontal indépendant par
activité si beaucoup de persos. Auto-cleanup au `popup_hide`.

**Fonctions clés :**
- `static open(parent, tile, popup_position = Vector2.ZERO) -> TileAssignmentPopup` — construit et centre le popup (param `popup_position` gardé pour compat MapView, ignoré)
- `_activity_row(activity, available, occupied) -> Control` — une row : header d'activité fixe + `ScrollContainer` H des slots persos, avec filtre pertinence sur les occupés (ceux qui font déjà cette activité ailleurs sont masqués)
- `_survivor_slot(s, y, activity, is_occupied, is_best) -> Control` — slot MapView-like (hex de la couleur de la tuile, icônes yield en fond, sprite dessus, teinte verte si meilleur candidat)
- `_compute_target_size() -> Vector2i` — largeur adaptée à `MAX_VISIBLE_COLS`, hauteur au nombre d'activités

**Autres fonctions :** `_build()`, `_activity_header(activity)`, `_survivor_header_text(s)`, `_build_trait_lines(s)`, `_format_output(s)`, `_muted_label(text)`, `_vsep_narrow()`, `_is_available(s)`, `_current_activity_context(s)`, `_hex_polygon_points()`, `_on_clear_pressed()`, `_on_activity_selected(sid, aid)`

**Classe interne :** `RichHoverSlot extends Control` — slot cliquable avec `_make_custom_tooltip` renvoyant un `RichTextLabel` BBCode (dup pattern `SurvivorsView.SurvivorSprite`). 

### scenes/ui/production_view.gd
`class_name ProductionView` extends Control — Tableau 4 colonnes (net/consommé/stock/
impossible) + ligne des activités risquées. Lit `TurnResolver.compute_flow()`.
 
**Fonctions clés :** `_rebuild()`, `_make_row(type, production, consumption, impossible)`
 
**Autres fonctions :** `_make_header()`, `_make_header_label(text)`, `_make_risky_row(row)`, `_make_empty_column()`, `_make_icon_column(resource_name, count, overlay)`
 
### scenes/ui/survivors_view.gd
`class_name SurvivorsView` extends Control — Liste des survivants éveillés, triés par
ordre de réveil. Sprites délégués à `SurvivorSpriteWidget` (tooltip riche + badge fatigue).

**Fonctions clés :** `_rebuild()`, `_add_row(s)`
 
### scenes/ui/infos_section.gd
`class_name InfosSection` extends Control — Panneau tour/électricité/famine + journal
d'événements scrollable, alimenté en streaming via `event_logged` (pattern chat,
auto-scroll bas).
 
**Fonctions clés :** `_rebuild()`, `_load_journal_history()`, `_on_event_logged(ev)`, `_append_line(ev)`
 
**Autres fonctions :** `_build()`, `_scroll_to_bottom()`
 
### scenes/ui/buttons_section.gd
`class_name ButtonsSection` extends Control — Boutons d'action globaux (tour suivant,
nécrologie, langue, quitter) + label de statut de fin de run. Émet `language_toggled`
(le rebuild complet reste la responsabilité de `MainUi`).
 
**Fonctions clés :** `_on_advance_pressed()`, `_on_necrology_pressed()`, `_on_toggle_lang_pressed()`, `_on_run_ended(cause)`
 
### scenes/ui/resources_bar.gd
`class_name ResourcesBar` extends Control — Barre des stocks en bas d'écran. Itère
`ResourceRegistry`, filtre sur `stackable` (electricity/heat vivent dans `InfosSection`).
 
**Fonctions clés :** `_rebuild()`, `_make_pill(type)`
 
---
 
## scenes/ui/buildings/ — Vues spécifiques par bâtiment
 
Toutes suivent le contrat `setup(b: Building) -> void`, instanciées via
`BuildingConfig.view_scene` par `ColonyView`.
 
### scenes/ui/buildings/generic_building_view.gd
`class_name GenericBuildingView` extends Control — Vue générique (slider d'intensité,
état construction/opérationnel) pour les bâtiments sans UI dédiée.
- `setup(b)`, `_rebuild(...)`, `_build_under_construction(vbox)`, `_build_operational(vbox)`
### scenes/ui/buildings/computer_view.gd
`class_name ComputerView` extends Control — Bouton "Interagir" → popup avec recherche
ciblée par profession (bouton "discuter" en placeholder, tutoriel narratif prévu plus tard).
- `setup(b)`, `_on_interact_pressed()`
### scenes/ui/buildings/synthesizer_view.gd
`class_name SynthesizerView` extends Control — Checkbox on/off + info statique.
- `setup(b)` — la vue ne se reconstruit pas réellement (`_rebuild` est un `pass`, commenté comme volontaire tant que la vue n'affiche rien de plus)
### scenes/ui/buildings/cryo_view.gd
`class_name CryoView` extends Control — Pool de candidats à réveiller (sprites inclinés
type "chambre cryo" via `SurvivorSpriteWidget`) + compteur de cryogénisés restants.
La recherche ciblée vit dans `ComputerView`, pas ici.
- `setup(b)`, `_rebuild()`, `_make_candidate_card(s)`
### scenes/ui/buildings/construction_zone_view.gd
`class_name ConstructionZoneView` extends Control — Workers assignés, cible de
construction courante + icônes de ce qui sera consommé ce tour, boutons "Choisir une
cible" / "Affecter un travailleur". Émet `placement_mode_requested(type_id)`, écouté par `ColonyView`.
- `setup(b)`, `_rebuild()`, `_on_choose_target_pressed()`
 
