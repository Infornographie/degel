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
 
### Pattern UI émergent

- **Vues transversales** (panneaux globaux comme la production) : `res://scenes/ui/*.tscn`.
- **Vues de bâtiment** : `res://scenes/ui/buildings/<building_id>_view.tscn`. À terme une vue par bâtiment ; les mécaniques de transformation pourront être factorisées via une base commune quand on aura 2-3 vues de transformation extraites (campfire, kitchen, tool_workshop, synthesizer).
- **Composition** : MainUi reste responsable du layout (grille colony, position des panels). Les vues gèrent uniquement leur contenu et s'abonnent directement à GameState pour leurs refreshs.
- **Coquille minimale (B1)** : la `.tscn` contient un Control racine, le script construit le contenu dynamique. On étoffera la `.tscn` quand les assets arriveront.
---

## ✅ Jalons accomplis
 
### Phase 1 — Squelette de simulation (Jalons 1 à 4)
 
- Simulation pure (énergie, réveils, nourriture, famine, fin de partie)
- Roster, IDs stables, jobs en table, configs en Resources
- UI lisible style Colonization (productions individuelles + globales)
- Pool de 3 candidats + recherche ciblée
- Carte hexagonale (cube coords), jobs territorialisés, `TileConfig.tres`
- Localisation FR/EN
### Phase 2 — Énergie en flux pur
 
- `reactor_output` décroît tous les N tours, fin de run REACTOR_DEAD à 0
- Coûts d'élec en flux ce tour (wakes, synthé), pas de réserve
- Extinction nominative des cryos si élec négative (1 mort certain par 10, +% par point partiel)
- Signal unifié `nightly_deaths` (famine + extinction) + popup "News from the bunker" + nécrologie
### Phase 3 — Système de bâtiments complet (Jalon 5g-4)
 
- Modèle data-driven : `BuildingConfig.tres` (id, family, build_cost, build_order, build_work, inputs, outputs, workers, niveaux, unique, available)
- 4 starters : computer, cryo_room, synthesizer, construction_zone
- Constructibles : campfire, canteen (= kitchen renommé), tool_workshop
- Construction : choix d'une cible + placement sur slot vide → chantier en UNDER_CONSTRUCTION
- Consommation ordonnée des ressources selon `build_order`, force de travail des colons (`work_force`)
- Plusieurs chantiers en pause possibles, un seul actif, switch via clic
- Switch auto sur le suivant à fin de chantier
- Bâtiments opérationnels : transformations input → output, factor d'opération si stock partiel
- Filtrage des bâtiments uniques (déjà construits ou en chantier exclus)
### Phase 4 — Refonte UI (vue colonie, sprites, map hex)
 
- Vue colonie : grille 4×3 avec bâtiments starter en bunker + chantiers en colonie
- Différenciation visuelle bunker (gris-bleu froid) / colonie (brun chaud)
- Sprites colons (6 variantes pixel art via `sprite_variant`)
- Vraie carte hexagonale en `Polygon2D`, sprites des workers sur tuile, icônes de production en arrière-plan
- Settlement (au lieu de Bunker) pour la tuile centrale
- Affichage activité contextuelle : `Mara (CEO) — Cueilleuse @ Forêt (-2,0)`
- Tri des éveillés par ordre de réveil chronologique (`wake_order`)
### Phase 5 — Modèle Activity (Jalon 5h-3)
 
Refonte structurelle : les jobs génériques (FARMER/LUMBERJACK/MINER) deviennent des **activités** spécifiques par couple `(activity, tile_type)`.
 
- Resource `Activity.tres` : id, name_key, allowed_tile_types, produced_resource, inputs, success_rate, tile_health_delta
- `ActivityRegistry` charge les .tres listés explicitement
- `TileConfig` indexe les yields par `activity_id` au lieu de `Job`
- `Survivor.activity_id` remplace `Survivor.job`
- 7 activités initiales : gathering, hunting, wood_picker, lumberjack, forester, gardener, ore_picker
- Activités risquées (chasse) : tirage au tour, affichage espérance + pourcentage séparé
- Activités à inputs (bûcheron/forestier consomment outils)
- Dégradation forêt : bûcheron +1 health, forestier -1 (max 0), mutation FOREST → PLAINS à health ≥ 5
### Phase 6 — Refonte du panneau production
 
- Tableau 4 colonnes : Consommé / Stock (surplus ou déficit) / Impossible
- Ligne séparée pour activités risquées avec leur taux de succès
- Resserrement automatique des icônes au-delà de 6
- Ressources non-stockables (electricity, heat) : déficit traité comme impossible (perte sèche)
- Ressource `meal` + bâtiment `canteen` (1 food + 2 heat → 1 meal), pas encore consommée prioritairement
### Phase 7 — Refacto TurnResolver (CRITIQUE)
 
**Source unique de vérité pour la résolution d'un tour.** Élimine la duplication entre l'exécution (`game_state.advance_turn`) et la prédiction (UI `_compute_resource_flow`) qui causait des bugs de divergence (bilan food incohérent, construction trop rapide).
 
- `TurnResolver.compute_flow()` : bilan déterministe sur copie du stock, sans modification → utilisé par UI ET base du commit
- `TurnResolver.execute_turn()` : applique réellement, avec aléatoire (chasse, mutations)
- Ordre canonique en commit : risky → tile_production → construction → buildings → repas → extinctions → morts à la fin
- L'UI ne contient plus aucune logique de simulation, juste de l'affichage
- Effets de bord acceptés : la dépendance à l'ordre des bâtiments dans la liste (premier servi). Évolution possible : priorité réglable par le joueur
### Phase 8 — Cleanup technique (partiel)

Refacto de la dette accumulée. Trois sous-phases identifiées, deux faites.

- **2 — Extraction des helpers UI.** Création de `res://scenes/ui/ui_presentation.gd` (`class_name UiPresentation`, static func). Cinq helpers déplacés depuis `main_ui.gd` : `resource`, `placeholder_color`, `tile_label`, `activity`, `activity_for_building`. 11 call sites mis à jour. Nom dévié de `ui_labels.gd` vers `ui_presentation.gd` parce que le fichier contient aussi `placeholder_color` qui n'est pas un label.
- **3a — Extraction de ProductionView (première vue séparée).** Pattern posé : une vue = une `.tscn` minimale (B1, coquille seule) + un script `class_name XxxView extends Control`, qui s'abonne directement aux signals de GameState. Instanciée par MainUi via `preload(...).instantiate()`. UiPresentation augmenté avec `resource_icon()` et `production_icon()` + constantes sprite, désormais consommé par MainUi (pills) et ProductionView (lignes de prod). `main_ui.gd` réduit de ~210 lignes (1367 → ~1157).
- **3b — Extraction de CryoView + structure `buildings/`.** Sous-dossier `res://scenes/ui/buildings/` introduit pour les vues spécifiques à un type de bâtiment. CryoView extraite : contenu du slot cryo (sprites candidats inclinés + compteur). Le panel et le style "slot bunker" restent côté MainUi (responsabilité layout colony grid) — CryoView gère uniquement son contenu. `UiPresentation` augmenté avec `survivor_sprite()` (≥3 usages : CryoView, future SurvivorsView, helper assigned_worker_sprite). `main_ui.gd` réduit de ~50 lignes (1158 → ~1108).
- **3c — Extraction d'InfosSection.** Vue transversale du panneau d'infos haut-gauche (tour, électricité, label famine). Lecture seule, abonnée directement à turn_advanced, resources_changed, famine_started/ended, building_assignment_changed. main_ui.gd réduit de ~20 lignes.
- **3d — Extraction d'InfosSection + journal d'événements.** Vue transversale du panneau d'infos haut-gauche, enrichie d'un journal scrollable. Nouvelle infrastructure générique : `GameEvent` (turn + category + key + params) stocké dans `GameState.event_log`, alimenté via `log_event()` et diffusé via signal `event_logged`. 14 sites instrumentés à travers `game_state` et `turn_resolver`. Le popup nightly et le journal partagent désormais une source unique. Convention `"tr:CLÉ"` dans les params pour la localisation à chaud.
- **3e — Extraction de SurvivorsView.** Vue transversale liste des éveillés (sprites triés par ordre de réveil + tooltips détaillés). Lecture seule. Aucune nouvelle dépendance, consomme `UiPresentation.survivor_sprite()` et `UiPresentation.activity()` / `tile_label()`. `main_ui.gd` réduit de ~50 lignes.
- **3f — Extraction de ResourcesBar.** Vue transversale de la barre des stocks (food/wood/ore/tools, scrollable horizontalement). Lecture seule, abonnée à `resources_changed`. `main_ui.gd` réduit de ~33 lignes.
- **3g — Extraction de ButtonsSection.** Vue transversale des boutons d'action globaux + status label de fin de run. Pattern signal pour le couplage avec MainUi : émet `language_toggled` quand le rebuild complet de l'UI est nécessaire (responsabilité MainUi). `UiPresentation.show_popup()` ajoutée et adoptée par les trois sites (necrology, nightly news, run ended). `main_ui.gd` réduit de ~50 lignes.
- **3h — Extraction de ColonyView (orchestrateur grid + slots).** Vue transversale de la grille colony 4×3. Layout, slots vides, mode placement, dispatch des starters aux emplacements fixes. Les 5 `_add_*_slot` de MainUi sont refactorées en `_make_*_slot` qui retournent un Control — ColonyView les appelle via Callable. `UiPresentation` augmenté de `slot_panel`, `slot_title`, `assigned_worker_sprite`. `main_ui.gd` réduit de ~150 lignes.
- **3i — Slots bâtiment en vues dédiées, dispatch data-driven.** Chaque bâtiment a sa vue dans `res://scenes/ui/buildings/`, référencée via `BuildingConfig.view_scene: PackedScene`. ColonyView dispatch sans `match` ni Callable. `UiPresentation.open_building_popup` extrait (partagé entre 2 vues). ConstructionZoneView émet `placement_mode_requested` que ColonyView écoute. Pattern "ajouter un bâtiment sans toucher au code" désormais atteint : il suffit d'un `.tres` + une `.tscn` (ou réutiliser `generic_building_view`). `main_ui.gd` réduit de ~300 lignes.
- **3j — Extraction de MapView (fin du chantier UI).** Vue transversale de la carte hexagonale. Rendu en deux passes (backgrounds puis workers + icônes de production), popups tuile avec sous-menus par éveillé, calcul des positions absolues. Pattern `await get_tree().process_frame` + second `_rebuild()` géré localement (la seule vue qui en a besoin). MainUi nettoyé en profondeur : suppression de `_refresh` et de ses 9 connexions de signaux — chaque vue écoute désormais GameState directement, sans intermédiaire. `main_ui.gd` réduit de ~280 lignes.
- **4 — Suppression du legacy Job.** `enum Job`, `var job_outputs` et son init dans `game_state.gd`. Fonctions mortes `_on_tile_popup_selected` et `_aggregate_production` dans `main_ui.gd`. Commentaire obsolète sur `GameState.Job.X` dans `hex_tile.gd`. Confirmé par grep global : zéro référence restante.

Sous-phase 3 (les autres vues : ColonyView, MapView, SurvivorsView, CryoView, InfosSection) reste à faire — pattern validé, reproduction vue par vue.

### Build & livraison
 
- Build Windows exportable (BuildingRegistry/ActivityRegistry chargent via listes explicites, `DirAccess` ne marche pas dans les exe exportés)
---
 
## 🎯 Cap thématique : « Évoluer pour survivre » dans le moteur
 
Le one-pager pose une thèse forte : **on survit en cessant d'être ce qu'on était**. Pour que ce propos vive *avant même* la couche narrative, il doit s'incarner dans la mécanique de gestion.
 
Deux mécaniques actuelles le portent déjà :
 
1. **Modèle Activity contextuel** : on n'est pas "bûcheron", on *fait du bûcheronnage en forêt ce tour-ci*. L'identité est dans le devenir, pas dans le métier figé.
2. **Tension tech → reconversion** (à concevoir) : la communauté est tirée vers la reconstruction de l'ancien monde, bute sur des impossibilités, doit se réinventer.
À approfondir avec :
- Lassitude par répétition (rotation organique, pas réglementaire)
- Chaînes de production qui ne peuvent pas se boucler complètement (signature thématique)
- Caractéristiques humaines acquises (pas des métiers, des traits)
---
 
## 🛠 Backlog prioritisé
 
### Cleanup technique (en attente)

**Découper `main_ui.gd` en vues séparées.** `MapView`, `ColonyView`, `ProductionView`, `SurvivorsView`, `CryoView`, coordonnées par un `MainUI` léger. Vue par vue, validation à chaque extraction. Le fichier fait ~1374 lignes, c'est nécessaire pour la maintenabilité.

**Consolider le doublon `_find_building` vs `_find_building_by_type` dans `GameState`.** Pas une suppression, une fusion : choisir la bonne signature, migrer les appels. À traiter en standalone ou pendant un autre passage sur les buildings.
 
### Mécaniques de gestion à ajouter
 
**Priorité de consommation des meals.** Les meals existent (canteen produit du meal), mais ne sont pas consommés prioritairement à la place de la food brute. Logique à brancher : meals d'abord, food en complément.
 
**Sources multiples vers une même réserve.** Plusieurs icônes/sprites pour une même ressource (fraises, blé, gibier, synth → tous en `food` ; branches, bois → `wood`). Visualisation différenciée sur carte et prod view, compteur unique en réserve.
 
**Substitution de ressources.** Certains bâtiments avancés acceptent l'un *ou* l'autre input (heat ⊕ electricity). Mécanique de substitution dans les inputs de `BuildingConfig`.
 
**Améliorations de bâtiments** (niveau 1 → 2 → 3). Les champs `max_level`, `output_multiplier_per_level`, `workers_max_increase_per_level` existent dans `BuildingConfig`, à brancher. Coût d'upgrade, UI dédiée.
 
**Bilan ressources ordonné** (polish d'équilibrage). Aujourd'hui `build_order = ["wood", "ore"]` consomme tout le wood puis tout le ore. À terme, pouvoir exprimer des séquences en blocs (`5 wood, 5 ore, 5 wood, 5 tools`). À traiter quand l'équilibrage des bâtiments deviendra sérieux.
 
### Carte & territoire
 
**Outils + déboisement actif.** Action sur la carte pour transformer une tuile (au-delà de la dégradation passive du bûcheron). Consomme outils, change le type de tuile, ouvre la production.
 
**Accès au deuxième cercle.** Pas d'accès dès le départ. Construction de chemins (coût en outils) qui débloquent les tuiles plus éloignées et améliorent légèrement leur production. Activable plus tard via événement.
 
**Rivière comme élément de carte.** Apparaît par événement, traverse certaines tuiles, débloque l'irrigation des plaines (jardinier → farmer) et le `ore_picker` en plaine.
 
**Map scrollable.** Pour les territoires lointains accessibles via expéditions narratives (futur).
 
### Système d'événements (Jalon 6 préparatoire)
 
**Premier système d'événements minimal.** Au minimum pour débloquer la zone de construction (qui est starter aujourd'hui, devrait être un event). Ouvre la voie au narratif.
 
**News popup étendu.** L'infrastructure existe (`nightly_deaths` → `_on_nightly_deaths` qui affiche). À étendre avec un vrai journal du tour : constructions terminées, chasses ratées, transformations de tuiles, événements narratifs.
 
**Z-order et superposition des panneaux UI.** Plusieurs vues se chevauchent en transparence (ProductionView lisible sous les boutons, SurvivorsView invisible quand recouverte). À diagnostiquer quand on attaquera le polish visuel

### Direction graphique
 
- Tile-sets hex en pixel art (en cours, contribution fils d'Anthony)
- Sprites colons : variations via shader palette swap (pour ne pas multiplier les variantes pré-rendues)
- Icônes ressources sur grille plus fine pour permettre détails (overlay deficit, etc.)
- Sprite "bâtiment en construction" qui évolue avec les ressources consommées (la séquence ordonnée le permet)
### Jalon 6 — Couche relationnelle (conception)
 
Concevoir et implémenter le moteur d'observation passive : quels signaux mesurer, où les stocker, comment les exposer aux événements.
 
Trois critères à tenir (cf. one-pager) :
1. Signaux lisibles dans la fiction
2. Événements ressentis comme causés
3. Conséquences qui bouclent sur la gestion
Signaux candidats : cohabitation, travail partagé, événements vécus ensemble, décisions du joueur, bien-être alimenté par les repas.
 
### Jalon 7 — Couche narrative + arc principal (conception)
 
- Structure d'événements (scriptés + procéduraux)
- Choix moraux à conséquences durables
- Aspirations cachées révélées
- Caractéristiques acquises
- **Arc narratif principal** portant la question dramatique : *que devient cette communauté ?*
### Pistes en cristallisation à valider
 
- **Travail comme état, pas identité.** Lassitude par répétition fait baisser l'efficacité. Caractéristiques acquises = traits humains, pas métiers. Bâtiments/techs débloquent des roulements automatisés.
- **Bunker computer comme voix narrative.** Interface de tutoriel et de guidage qui parle au joueur.
---
 
## 🐛 Bugs / suspicions à vérifier
 
- **Construction trop rapide ?** Signalé en session, à reproduire et confirmer maintenant que le TurnResolver unifie le calcul.
- **Bilan food bizarre ?** Probablement résolu par le TurnResolver, à confirmer en jeu.
- **Famine bug** : confirmé comme legacy, non régression. Hypothèse : multiplier 0.8 crée des spirales bloquées. À diagnostiquer.
- **Ordre des bâtiments dans `_resolve_buildings_operation`** : premier servi sur les inputs partagés. Acceptable maintenant, à raffiner si gênant en jeu.
- **Doublon de colonne "impossible"** dans `ProductionView._make_row`. Le code ajoute la colonne 4 deux fois (une avec `total_impossible`, une avec `imp_int`). Hérité de l'ancien `_make_production_row`, préservé fidèlement avec un FIXME dans le code. Visuel à diagnostiquer : soit la 5ème colonne est invisible parce que masquée par le layout, soit il y a un vrai bug d'affichage. Test rapide : provoquer un cas "impossible" non nul et regarder ce que le panneau affiche.
- **`OVERLAY_PATH` et `RESOURCE_SPRITE_PATH` partagent la même valeur** dans `UiPresentation`. Sémantiquement différents, factuellement identiques. À découpler quand les vrais assets d'overlay seront créés.
- **Affichage du usable électricité incohérent avec le label synth: -3.** Migré tel quel dans InfosSection._rebuild. Hypothèse : synth.active est true sans worker, donc le label apparaît à tort, ou bien la conso n'est pas déduite au bon moment dans TurnResolver. Diagnostic à faire en séance dédiée.
- **Bug d'affichage usable électricité non lié au synth.active actif** → à diagnostiquer
- **necrology redondant avec event_log filtré sur category** == "loss" — à migrer en séance dédiée
- **Signal nightly_deaths mal nommé** — porte tous les events du tour maintenant, pas seulement les morts. À renommer (turn_news ou nightly_events)
- **Pas de virtualisation du journal UI** — 1 Label par event. À 1000+ events, à surveiller. Mitigation : "voir les N derniers" + bouton "tout afficher" si besoin
- **construction_started réutilisé pour rafraîchir l'UI** (deux call sites avec # rafraîchir en commentaire dans game_state.gd) — un vrai signal de refresh manque
- **Layout colony hardcodé** (`COLONY_SLOTS=12`, `STARTER_SLOTS` dictionnaire d'emplacements) dans `ColonyView`. À déplacer dans une Resource configurable quand l'équilibrage et les nouveaux bâtiments l'exigeront.
- **`_render_slot_fn: Callable`** est un couplage transitoire ColonyView ↔ MainUi. Disparaîtra en séance 2 (Phase 8.3i) quand chaque slot deviendra sa propre vue dans `res://scenes/ui/buildings/` avec dispatch data-driven via `BuildingConfig.view_scene`.
- **`BUNKER_BUILDING_IDS`** migré dans ColonyView mais peut-être plus utilisé nulle part. À grep et supprimer si vrai.
- **Risque de deux popups ouverts simultanément** : mécanisme "un seul popup à la fois" perdu (était assuré par `_tile_popup` partagé dans MainUi). En pratique l'UX tient — un clic à la fois. Si problème observé, extraire un `PopupManager`.
- **`BUNKER_BUILDING_IDS` hardcodé dans ColonyView**. À déplacer dans `BuildingConfig.is_bunker_building: bool` pour rendre l'ajout d'un nouveau bâtiment 100% data-driven.
- **Layout colony hardcodé** (`COLONY_SLOTS=12`, `STARTER_SLOTS`). À mettre dans une Resource configurable quand l'équilibrage l'exigera.
- **`CryoView` n'a pas de `setup(b)`**. ColonyView gère via `has_method` mais hétérogène. À homogénéiser quand on touchera CryoView pour les futures évolutions visuelles.
---
 
## 🎯 Indicateurs de santé du projet
 
À surveiller au fil des jalons :
 
- **La boucle de jeu reste-t-elle simple à expliquer ?**
- **Chaque ressource a-t-elle un usage clair ?**
- **Le harsh est-il tenable ou frustrant ?** À éprouver en playtest.
- **Les personnages sont-ils encore interchangeables ?** Tant que oui, le cap thématique n'est pas franchi.
- **La gestion seule tient-elle plusieurs runs ?** Test à passer avant la couche relationnelle.
- **L'UI ment-elle au joueur ?** Plus depuis le TurnResolver — à confirmer en jeu prolongé.
---
 
## 📋 Tech & process
 
- **Engine** : Godot 4.6.3, GDScript, GL Compatibility, pas de 3D
- **Structure projet** :
  - `res://systems/core/` : game_state, game_config, tile_config, turn_resolver
  - `res://systems/world/` : hex_map, hex_tile, production_system, activity, activity_registry
  - `res://systems/survivors/` : roster, survivor
  - `res://systems/buildings/` : building, building_config, building_registry
  - `res://resources/` : tres de config (game, tile, activities/, buildings/)
  - `res://assets/` : sprites colons (generic0-5), icônes ressources
  - `res://localization/` : CSV FR/EN
  - `res://scenes/` : main_ui (à découper en plusieurs vues à terme)
- **Dette technique connue** : `main_ui.gd` à ~1374 lignes, à découper en vues
- **Process** : 1 séance = 1 étape qui tourne, design avant code, commits étape par étape, refactor honnête quand le besoin émerge
 
